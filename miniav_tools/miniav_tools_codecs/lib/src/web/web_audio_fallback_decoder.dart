/// Last-resort audio decode for browsers WITHOUT WebCodecs, via the ancient and
/// universally available `BaseAudioContext.decodeAudioData`.
///
/// WebCodecs `AudioDecoder` is Chrome 94+ / Safari 16.4+ / Firefox 130+. Older
/// Safari, older Firefox and plenty of embedded webviews have none of it, and on
/// web there is no FFmpeg and no `dart:ffi`, so [SwAudioDecoder]'s dr_mp3 path
/// does not exist either — MP3 simply had NO decoder on those browsers.
/// `decodeAudioData` has shipped in every browser for over a decade.
///
/// ## Why this is whole-buffer, not streaming
///
/// `decodeAudioData` takes a COMPLETE, self-contained bitstream and hands back
/// fully decoded PCM; there is no packet-at-a-time entry point. So this
/// accumulates across [decode] and produces everything at [flush] — the same
/// shape [SwAudioDecoder] uses for FLAC/Vorbis, and for the same reason (a slice
/// of a stream is not a decodable unit). Output is then chopped into ~1 s
/// [DecodedAudio] chunks with real timestamps so a player still gets a normal
/// sequence of buffers rather than one enormous one.
///
/// The cost is honest and worth naming: nothing is emitted until end-of-stream,
/// so this is a FALLBACK for file playback, not a live-stream decoder. Where
/// WebCodecs exists the negotiator prefers it (priority 80 vs this backend's
/// 40) and streams packet-by-packet as before.
///
/// ## Why MP3 only
///
/// Packets arriving here are DEMUXED — container framing already stripped.
/// Concatenated MP3 frames are themselves a valid MP3 bitstream, so they feed
/// `decodeAudioData` directly. Demuxed AAC (no ADTS wrapper), FLAC (no
/// STREAMINFO) and Vorbis (no setup headers) are not self-contained and would
/// need re-wrapping first — exactly the reasoning that made [SwAudioBackend]
/// claim MP3 alone. AAC could be supported later by synthesising ADTS headers
/// from the AudioSpecificConfig in `extraData`.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';
import 'package:web/web.dart' as web;

class WebAudioFallbackDecoder implements PlatformAudioDecoder {
  WebAudioFallbackDecoder._(this._sampleRateHint);

  /// Sample rate to decode AT. `decodeAudioData` resamples to the context's
  /// rate, so seeding the context with the container's rate keeps MP3 at its
  /// native 44.1 kHz instead of silently resampling everything to 48 kHz.
  final int _sampleRateHint;

  final BytesBuilder _buf = BytesBuilder();
  int _firstPtsUs = 0;
  bool _havePts = false;
  bool _closed = false;

  /// Frames per emitted chunk (~1 s), so consumers get a normal cadence of
  /// buffers instead of one allocation the size of the whole track.
  static const int _chunkFrames = 48000;

  /// Web Audio only accepts context rates in [8000, 96000].
  static const int _minRate = 8000;
  static const int _maxRate = 96000;

  static WebAudioFallbackDecoder? create(AudioDecoderConfig config) {
    if (config.codec != AudioCodec.mp3) return null;
    final hint = config.sampleRate;
    final rate = (hint != null && hint >= _minRate && hint <= _maxRate)
        ? hint
        : 48000;
    return WebAudioFallbackDecoder._(rate);
  }

  @override
  Future<List<DecodedAudio>> decode(EncodedPacket packet) async {
    if (_closed) return const [];
    if (!_havePts) {
      _firstPtsUs = packet.ptsUs;
      _havePts = true;
    }
    _buf.add(packet.data);
    return const []; // whole-buffer decoder — everything lands at flush()
  }

  @override
  Future<List<DecodedAudio>> flush() async {
    if (_closed) return const [];
    final bytes = _buf.takeBytes();
    if (bytes.isEmpty) return const [];

    final web.AudioBuffer decoded;
    try {
      // OfflineAudioContext: decodes without touching an output device, so no
      // autoplay-policy user gesture is required.
      final ctx = web.OfflineAudioContext(1.toJS, 1, _sampleRateHint);
      // A tight copy: `bytes` may be a view, and decodeAudioData DETACHES the
      // ArrayBuffer it is given.
      final ab = Uint8List.fromList(bytes).buffer.toJS;
      decoded = await ctx.decodeAudioData(ab).toDart;
    } catch (e) {
      throw StateError(
        'decodeAudioData could not decode the MP3 bitstream ($e). '
        'This fallback needs a self-contained stream; if these packets came '
        'from a container, the demuxer must emit raw MP3 frames.',
      );
    }

    final channels = decoded.numberOfChannels;
    final frames = decoded.length;
    final rate = decoded.sampleRate.round();
    if (channels <= 0 || frames <= 0) return const [];

    // Web Audio is planar; every consumer here wants interleaved.
    final planes = <Float32List>[
      for (var c = 0; c < channels; c++) decoded.getChannelData(c).toDart,
    ];

    final out = <DecodedAudio>[];
    for (var start = 0; start < frames; start += _chunkFrames) {
      final n = (start + _chunkFrames <= frames) ? _chunkFrames : frames - start;
      final inter = Float32List(n * channels);
      for (var c = 0; c < channels; c++) {
        final plane = planes[c];
        var o = c;
        for (var f = 0; f < n; f++, o += channels) {
          inter[o] = plane[start + f];
        }
      }
      out.add(
        DecodedAudio(
          samples: inter,
          frameCount: n,
          sampleRate: rate,
          channels: channels,
          ptsUs: _firstPtsUs + (start * 1000000) ~/ rate,
        ),
      );
    }
    return out;
  }

  @override
  Future<void> close() async {
    _closed = true;
    _buf.clear();
  }
}
