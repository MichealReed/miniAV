/// First-party libopus audio encoder — FFmpeg-free.
///
/// Wraps the `miniav_opus_enc_*` native functions (libopus, static-linked into
/// the codecs native asset). Buffers the delivered interleaved PCM into fixed
/// 20 ms Opus frames, encodes each with `opus_encode_float`, and emits bare
/// Opus packets + an `OpusHead` [extraData] — the same shape the FFmpeg libopus
/// path produced, with zero FFmpeg in the process.
///
/// The emitted `OpusHead` carries libopus's real lookahead as the RFC 7845
/// pre-skip, so a player trims the encoder's priming instead of playing it.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

import '../codecs_native.dart';
import 'opus_bitstream.dart';

/// Max compressed bytes for one Opus frame (libopus recommends 4000).
const int _kMaxPacketBytes = 4000;

class OpusAudioEncoder implements PlatformAudioEncoder {
  OpusAudioEncoder._(this._handle, this._sampleRate, this._channels, this.preSkip48k)
    : _frameSamplesPerCh = _sampleRate ~/ 50, // 20 ms frames
      _leftover = Float32List((_sampleRate ~/ 50) * _channels),
      _in = calloc<Float>((_sampleRate ~/ 50) * _channels),
      _out = calloc<Uint8>(_kMaxPacketBytes) {
    _frameSamplesTotal = _frameSamplesPerCh * _channels;
    _extraData = CodecExtraData.audio(
      AudioCodec.opus,
      buildOpusHead(_channels, _sampleRate, preSkip48k),
    );
  }

  /// Pre-skip written into the emitted OpusHead: libopus's real lookahead for
  /// this encoder, expressed at 48 kHz (the unit RFC 7845 mandates).
  ///
  /// A decoder discards this many samples from the front of the stream. Writing
  /// 0 here — which this encoder used to do — leaves the encoder's priming in
  /// the file: an audible click at the start and every later sample stamped
  /// ~6.5 ms early against video. Our own round-trip could not see it, because
  /// our decoder honours whatever pre-skip it reads.
  final int preSkip48k;

  final Pointer<Void> _handle;
  final int _sampleRate;
  final int _channels;
  final int _frameSamplesPerCh;
  late final int _frameSamplesTotal;

  final Float32List _leftover; // < one full frame of carry-over samples
  int _leftoverLen = 0;
  final Pointer<Float> _in;
  final Pointer<Uint8> _out;
  late final CodecExtraData _extraData;

  int _basePtsUs = 0;
  bool _havePts = false;
  int _framesEmitted = 0; // per-channel frames encoded so far
  bool _closed = false;

  /// Open an Opus encoder, or `null` if the codec isn't Opus / libopus rejects
  /// the rate or channels (→ the facade falls through to the next backend).
  static Future<OpusAudioEncoder?> open(AudioEncoderConfig config) async {
    if (config.codec != AudioCodec.opus) return null;
    final sampleRate = config.sampleRate > 0 ? config.sampleRate : 48000;
    final channels = config.channels >= 1 && config.channels <= 2
        ? config.channels
        : 2;
    // Opus only encodes at 8/12/16/24/48 kHz; libopus accepts these exactly.
    const valid = {8000, 12000, 16000, 24000, 48000};
    if (!valid.contains(sampleRate)) return null;
    final handle = opusEncCreate(
      sampleRate,
      channels,
      config.bitrateBps,
      kOpusApplicationAudio,
    );
    if (handle == nullptr) return null;
    // OpusHead's pre-skip is always in 48 kHz samples, whatever the encoder
    // runs at, so scale libopus's answer (which is at `sampleRate`) up.
    final lookahead = opusEncLookahead(handle);
    final preSkip48k = lookahead <= 0
        ? 0
        : (lookahead * 48000 + sampleRate ~/ 2) ~/ sampleRate;
    return OpusAudioEncoder._(handle, sampleRate, channels, preSkip48k);
  }

  @override
  Future<List<EncodedPacket>> encode({
    required Uint8List pcm,
    required MiniAVAudioFormat format,
    required int frameCount,
    required int ptsUs,
  }) async {
    _checkOpen();
    if (!_havePts) {
      _havePts = true;
      _basePtsUs = ptsUs;
    }
    final chunk = _toFloat(pcm, format, frameCount * _channels);
    return _drain(chunk, flushTail: false);
  }

  /// Encode any buffered leftover, zero-padded to a full frame.
  @override
  Future<List<EncodedPacket>> flush() async {
    _checkOpen();
    if (_leftoverLen == 0) return const [];
    return _drain(Float32List(0), flushTail: true);
  }

  List<EncodedPacket> _drain(Float32List chunk, {required bool flushTail}) {
    final total = _leftoverLen + chunk.length;
    final work = Float32List(
      flushTail && total < _frameSamplesTotal ? _frameSamplesTotal : total,
    );
    work.setRange(0, _leftoverLen, _leftover);
    work.setRange(_leftoverLen, total, chunk);
    // flushTail path: the pad region [total, frameSamplesTotal) stays 0 (silence).

    final end = flushTail ? work.length : total;
    final packets = <EncodedPacket>[];
    var offset = 0;
    while (end - offset >= _frameSamplesTotal) {
      _in
          .asTypedList(_frameSamplesTotal)
          .setRange(0, _frameSamplesTotal, work, offset);
      final bytes = opusEncEncode(
        _handle,
        _in,
        _frameSamplesPerCh,
        _out,
        _kMaxPacketBytes,
      );
      if (bytes < 0) {
        throw CodecRuntimeException('opus', 'opus_encode_float failed: $bytes');
      }
      if (bytes > 0) {
        final data = Uint8List(bytes)..setAll(0, _out.asTypedList(bytes));
        final pts =
            _basePtsUs + (_framesEmitted * 1000000) ~/ _sampleRate;
        packets.add(EncodedPacket(
          data: data,
          ptsUs: pts,
          dtsUs: pts,
          durationUs: (_frameSamplesPerCh * 1000000) ~/ _sampleRate,
        ));
        _framesEmitted += _frameSamplesPerCh;
      }
      offset += _frameSamplesTotal;
    }

    // Carry the remainder (always < one frame) to the next call.
    _leftoverLen = flushTail ? 0 : total - offset;
    if (_leftoverLen > 0) {
      _leftover.setRange(0, _leftoverLen, work, offset);
    }
    return packets;
  }

  @override
  CodecExtraData? get extraData => _extraData;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    opusEncDestroy(_handle);
    calloc.free(_in);
    calloc.free(_out);
  }

  void _checkOpen() {
    if (_closed) throw StateError('OpusAudioEncoder has been closed.');
  }

  /// Read [n] interleaved samples from [pcm] (format [fmt]) as float in [-1,1].
  Float32List _toFloat(Uint8List pcm, MiniAVAudioFormat fmt, int n) {
    final out = Float32List(n);
    final bd = ByteData.sublistView(pcm);
    switch (fmt) {
      case MiniAVAudioFormat.f32:
        final avail = pcm.lengthInBytes ~/ 4;
        final m = n < avail ? n : avail;
        for (var i = 0; i < m; i++) {
          out[i] = bd.getFloat32(i * 4, Endian.little);
        }
      case MiniAVAudioFormat.s16:
        final avail = pcm.lengthInBytes ~/ 2;
        final m = n < avail ? n : avail;
        for (var i = 0; i < m; i++) {
          out[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
        }
      case MiniAVAudioFormat.s32:
        final avail = pcm.lengthInBytes ~/ 4;
        final m = n < avail ? n : avail;
        for (var i = 0; i < m; i++) {
          out[i] = bd.getInt32(i * 4, Endian.little) / 2147483648.0;
        }
      case MiniAVAudioFormat.u8:
        final m = n < pcm.lengthInBytes ? n : pcm.lengthInBytes;
        for (var i = 0; i < m; i++) {
          out[i] = (pcm[i] - 128) / 128.0;
        }
      case MiniAVAudioFormat.unknown:
        break;
    }
    return out;
  }
}
