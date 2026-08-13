/// First-party software audio decoders — MP3 (dr_mp3), FLAC (dr_flac), Vorbis
/// (stb_vorbis). All FFmpeg-free (public-domain single-header libs in the
/// codecs native asset).
///
/// These libraries own their own container/framing (a raw `.mp3`, a native
/// `.flac`, or an Ogg-wrapped Vorbis stream) and the native entry points take a
/// COMPLETE buffer (`drmp3_init_memory` and friends), so this decoder
/// accumulates compressed bytes across [decode] calls rather than decoding one
/// packet at a time. Feeding it a whole file and flushing still works exactly
/// as before.
///
/// It does NOT wait for [flush] to produce anything, though. Fed a packet
/// STREAM (a demuxer emitting one frame per packet), decoding only at flush
/// starves every streaming consumer: each [decode] returns nothing, the player
/// writes no audio for the whole file, and the entire track then arrives as one
/// chunk during end-of-stream drain — which sounds like a fraction of a second
/// of audio followed by an immediate end-of-stream. So once a SECOND MP3 packet
/// arrives (i.e. this is a stream, not a one-shot whole-file feed) the buffer is
/// decoded in batches of [_batchBytes] and emitted as it goes, timestamped from
/// the first packet of each batch. FLAC and Vorbis are never batched — a slice
/// of a container is not a container — so a chunked whole-file feed of either
/// still accumulates and decodes once at [SwAudioDecoder.flush].
///
/// Batching rather than per-packet decode is forced by the native layer: a lone
/// MP3 frame is too little for `drmp3_init_memory` to open at all (it fails),
/// so a packet-sized decode is not available without a native push API. A batch
/// boundary costs the bit reservoir of its first frame — bounded, and the
/// alternative is no streaming audio at all.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

import '../codecs_native.dart';
import '../framing/mp3_container.dart' show mp3PcmFrameCount;

class SwAudioDecoder implements PlatformAudioDecoder {
  SwAudioDecoder._(this._lib, this._codec);

  final SwAudioLib _lib;
  final AudioCodec _codec;
  final BytesBuilder _buf = BytesBuilder();
  bool _closed = false;

  /// Compressed bytes to gather before decoding a batch. ~0.7 s at 192 kbps —
  /// small enough that playback starts promptly, large enough that
  /// `drmp3_init_memory` has plenty to sync on (a single frame is not).
  static const int _batchBytes = 16 * 1024;

  /// Tail of the previous batch, replayed in front of the next one so the
  /// decoder has something to sync and prime on. 4 KiB is several frames at any
  /// Layer III bitrate, comfortably more than the 511-byte bit reservoir.
  static const int _carryBytes = 4096;

  /// Packets fed so far (not per batch), the PTS of the current batch's first
  /// packet, and the previous batch's tail.
  int _packetsFed = 0;
  int? _batchPtsUs;
  Uint8List _carry = Uint8List(0);

  /// More than one packet has arrived, so the caller is feeding a STREAM rather
  /// than handing over a whole file in one go — AND the batch is one this
  /// decoder can actually cut.
  ///
  /// MP3 only. An MP3 batch is a run of self-contained frames, so a slice of
  /// one decodes. A FLAC or Ogg-Vorbis batch is a slice of a CONTAINER: the
  /// second batch has no `fLaC`/`OggS` header in front of it and
  /// `drflac_open_memory` / `stb_vorbis_open_memory` reject it outright. A
  /// chunked whole-file feed of either (the documented "accumulate, then
  /// flush" contract) must therefore stay unbatched, however many chunks it
  /// arrives in, or it throws at the first batch boundary.
  bool get _batching => _packetsFed >= 2 && _lib == SwAudioLib.mp3;

  static SwAudioLib? libFor(AudioCodec c) => switch (c) {
        AudioCodec.mp3 => SwAudioLib.mp3,
        AudioCodec.flac => SwAudioLib.flac,
        AudioCodec.vorbis => SwAudioLib.vorbis,
        _ => null,
      };

  static Future<SwAudioDecoder?> open(AudioDecoderConfig config) async {
    final lib = libFor(config.codec);
    if (lib == null) return null;
    return SwAudioDecoder._(lib, config.codec);
  }

  @override
  Future<List<DecodedAudio>> decode(EncodedPacket packet) async {
    _check();
    _batchPtsUs ??= packet.ptsUs;
    _buf.add(packet.data);
    _packetsFed++;
    // One packet is a whole-file feed until proven otherwise, and a whole file
    // must keep decoding exactly as it always has (at flush, as one chunk).
    // From the second packet on this is a stream, so emit batches as they fill.
    if (!_batching || _buf.length < _batchBytes) return const [];
    return _drainBuffer();
  }

  @override
  Future<List<DecodedAudio>> flush() async {
    _check();
    return _drainBuffer();
  }

  /// Decode everything buffered so far and reset the batch.
  ///
  /// Streaming MP3 batches are decoded with the previous batch's tail in front
  /// of them and then cut back to their own frames. Without that, every batch
  /// silently loses its first frame — `drmp3_init_memory` spends it syncing —
  /// which is a 24 ms hole every batch plus a steadily growing drift, measured
  /// at ~1 s missing over 30 s. The whole-file path (one big packet, never
  /// batched) keeps its original behaviour: no context, no trim.
  List<DecodedAudio> _drainBuffer() {
    final data = _buf.takeBytes();
    final ptsUs = _batchPtsUs ?? 0;
    final streaming = _batching;
    _batchPtsUs = null;
    if (data.isEmpty) return const [];
    if (!streaming) return _decodeAll(data, ptsUs);

    final wanted = mp3PcmFrameCount(data);
    final carry = _carry;
    _carry = data.length <= _carryBytes
        ? data
        : Uint8List.sublistView(data, data.length - _carryBytes);
    if (carry.isEmpty) return _decodeAll(data, ptsUs);

    final input = Uint8List(carry.length + data.length)
      ..setRange(0, carry.length, carry)
      ..setRange(carry.length, carry.length + data.length, data);
    final out = _decodeAll(input, ptsUs);
    if (out.isEmpty || wanted <= 0) return out;
    return [for (final c in out) _keepTail(c, wanted)];
  }

  /// Keep the last [frames] sample-frames of [c] (all of it if it is shorter).
  DecodedAudio _keepTail(DecodedAudio c, int frames) {
    if (c.frameCount <= frames || c.channels <= 0) return c;
    final drop = (c.frameCount - frames) * c.channels;
    return DecodedAudio(
      samples: Float32List.sublistView(c.samples, drop),
      frameCount: frames,
      sampleRate: c.sampleRate,
      channels: c.channels,
      ptsUs: c.ptsUs,
    );
  }

  List<DecodedAudio> _decodeAll(Uint8List data, int ptsUs) {
    final inBuf = calloc<Uint8>(data.length);
    inBuf.asTypedList(data.length).setAll(0, data);
    final outPtr = calloc<Pointer<Float>>();
    final chPtr = calloc<Int32>();
    final ratePtr = calloc<Int32>();
    try {
      final frames = swDecode(_lib, inBuf, data.length, outPtr, chPtr, ratePtr);
      if (frames < 0) {
        throw CodecRuntimeException(_codec.name, 'SW decode failed');
      }
      final channels = chPtr.value;
      final rate = ratePtr.value;
      final buf = outPtr.value;
      final n = frames * channels;
      final samples = Float32List(n);
      if (n > 0 && buf != nullptr) {
        samples.setAll(0, buf.asTypedList(n));
      }
      if (buf != nullptr) swFree(buf.cast());
      if (frames == 0) return const [];
      return [
        DecodedAudio(
          samples: samples,
          frameCount: frames,
          sampleRate: rate,
          channels: channels,
          // The batch's own start time. Reporting 0 for every chunk (as this
          // did when it only ever emitted once) makes a player anchor its clock
          // at zero on each emission.
          ptsUs: ptsUs,
        ),
      ];
    } finally {
      calloc.free(inBuf);
      calloc.free(outPtr);
      calloc.free(chPtr);
      calloc.free(ratePtr);
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    _buf.clear();
    _packetsFed = 0;
    _batchPtsUs = null;
    _carry = Uint8List(0);
  }

  void _check() {
    if (_closed) throw StateError('SwAudioDecoder has been closed.');
  }
}
