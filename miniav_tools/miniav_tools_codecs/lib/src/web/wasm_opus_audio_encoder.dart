/// WASM libopus audio encoder (web) — byte-identical to the native OpusBackend.
///
/// The web twin of `opus/opus_audio_encoder.dart`: identical 20ms framing,
/// PTS accounting, OpusHead extraData and flush-tail zero-pad, but calls libopus
/// compiled to WebAssembly (via [CodecsWasm]) instead of dart:ffi. Because it is
/// the SAME libopus v1.5.2 as the native build (same OPUS_APPLICATION_AUDIO, VBR,
/// no intrinsics), its bitstream is byte-identical to native — which is the whole
/// point: a web sender interops with a native receiver and vice-versa.
library;

import 'dart:typed_data';

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

import '../opus/opus_bitstream.dart';
import 'codecs_wasm.dart';

class WasmOpusAudioEncoder implements PlatformAudioEncoder {
  WasmOpusAudioEncoder._(
      this._handle, this._sampleRate, this._channels, this.preSkip48k)
      : _frameSamplesPerCh = _sampleRate ~/ 50, // 20 ms frames
        _leftover = Float32List((_sampleRate ~/ 50) * _channels) {
    _frameSamplesTotal = _frameSamplesPerCh * _channels;
    _extraData = CodecExtraData.audio(
      AudioCodec.opus,
      buildOpusHead(_channels, _sampleRate, preSkip48k),
    );
  }

  /// libopus's real lookahead for this encoder, at 48 kHz — see
  /// `OpusAudioEncoder.preSkip48k`. Same libopus build as native, so the same
  /// value, but it is asked for rather than assumed.
  final int preSkip48k;

  final int _handle;
  final int _sampleRate;
  final int _channels;
  final int _frameSamplesPerCh;
  late final int _frameSamplesTotal;

  final Float32List _leftover; // < one full frame of carry-over samples
  int _leftoverLen = 0;
  late final CodecExtraData _extraData;

  int _basePtsUs = 0;
  bool _havePts = false;
  int _framesEmitted = 0; // per-channel frames encoded so far
  bool _closed = false;

  static Future<WasmOpusAudioEncoder?> open(AudioEncoderConfig config) async {
    if (config.codec != AudioCodec.opus) return null;
    final sampleRate = config.sampleRate > 0 ? config.sampleRate : 48000;
    final channels =
        config.channels >= 1 && config.channels <= 2 ? config.channels : 2;
    const valid = {8000, 12000, 16000, 24000, 48000};
    if (!valid.contains(sampleRate)) return null;
    try {
      await CodecsWasm.instance.ensureLoaded();
    } catch (_) {
      return null; // wasm unavailable → facade falls through to WebCodecs
    }
    final handle = CodecsWasm.instance.createEncoder(
      sampleRate,
      channels,
      config.bitrateBps,
      kOpusApplicationAudio,
    );
    if (handle == 0) return null;
    // Pre-skip is defined at 48 kHz whatever the encoder runs at.
    final lookahead = CodecsWasm.instance.encoderLookahead(handle);
    final preSkip48k = lookahead <= 0
        ? 0
        : (lookahead * 48000 + sampleRate ~/ 2) ~/ sampleRate;
    return WasmOpusAudioEncoder._(handle, sampleRate, channels, preSkip48k);
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

    final end = flushTail ? work.length : total;
    final packets = <EncodedPacket>[];
    var offset = 0;
    final frame = Float32List(_frameSamplesTotal);
    while (end - offset >= _frameSamplesTotal) {
      frame.setRange(0, _frameSamplesTotal, work, offset);
      final data =
          CodecsWasm.instance.encode(_handle, frame, _frameSamplesPerCh);
      if (data.isNotEmpty) {
        final pts = _basePtsUs + (_framesEmitted * 1000000) ~/ _sampleRate;
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
    CodecsWasm.instance.destroyEncoder(_handle);
  }

  void _checkOpen() {
    if (_closed) throw StateError('WasmOpusAudioEncoder has been closed.');
  }

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
