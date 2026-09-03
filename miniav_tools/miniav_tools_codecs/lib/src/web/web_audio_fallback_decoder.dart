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
/// ## Why MP3 and AAC, and nothing else
///
/// Packets arriving here are DEMUXED — container framing already stripped.
/// Concatenated MP3 frames are themselves a valid MP3 bitstream, so they feed
/// `decodeAudioData` directly. AAC is one synthesized header away from the
/// same property: wrapping each raw frame in a 7-byte ADTS header (built from
/// the AudioSpecificConfig in `extraData`) yields a valid `.aac` stream, and
/// packets that are ALREADY ADTS (an `.aac` file demuxed by container framing)
/// pass through untouched. That matters on WebKit specifically: iOS shipped
/// WebCodecs `VideoDecoder` years before `AudioDecoder`, so an MP4's H.264
/// track could decode while its AAC track had no decoder at all — and a player
/// that requires both then fails the WHOLE file over the audio track.
///
/// FLAC (no STREAMINFO) and Vorbis (no setup headers) stay out: their demuxed
/// packets cannot be made self-contained without rebuilding a real container,
/// which is [ContainerFramingBackend]'s job, not a decode-time patch.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';
import 'package:web/web.dart' as web;

/// ADTS parameters recovered from an AudioSpecificConfig, enough to wrap raw
/// AAC frames into a decodable `.aac` stream. Null fields mean "could not be
/// expressed in ADTS" and the packet must already carry its own header.
@visibleForTesting
class AdtsParams {
  const AdtsParams(this.profile, this.freqIndex, this.channelConfig);

  /// ADTS 2-bit profile: audioObjectType - 1. HE-AAC (AOT 5/29) is carried as
  /// its LC core with implicit SBR signalling — which is exactly how every
  /// ADTS HE-AAC stream in the wild is written.
  final int profile;
  final int freqIndex;
  final int channelConfig;

  static const _rates = [
    96000, 88200, 64000, 48000, 44100, 32000,
    24000, 22050, 16000, 12000, 11025, 8000, 7350,
  ];

  /// Parse the leading fields of an AudioSpecificConfig (ISO 14496-3 §1.6.2.1).
  static AdtsParams? fromAudioSpecificConfig(Uint8List asc) {
    if (asc.length < 2) return null;
    var bitPos = 0;
    int read(int n) {
      var v = 0;
      for (var i = 0; i < n; i++) {
        final byte = bitPos >> 3;
        if (byte >= asc.length) return -1;
        v = (v << 1) | ((asc[byte] >> (7 - (bitPos & 7))) & 1);
        bitPos++;
      }
      return v;
    }

    var aot = read(5);
    if (aot == 31) aot = 32 + read(6);
    var freqIndex = read(4);
    if (freqIndex == 15) {
      // Explicit 24-bit rate: only expressible in ADTS if it maps back onto a
      // table entry exactly.
      final rate = read(24);
      freqIndex = _rates.indexOf(rate);
      if (freqIndex < 0) return null;
    }
    final channelConfig = read(4);
    if (aot < 0 || freqIndex < 0 || channelConfig < 0) return null;

    // ADTS's 2-bit profile can express AOT 1..4. HE-AAC (5=SBR, 29=PS) rides
    // on its LC core; anything else (ER codecs, xHE) cannot be ADTS-wrapped.
    final int profile;
    if (aot >= 1 && aot <= 4) {
      profile = aot - 1;
    } else if (aot == 5 || aot == 29) {
      profile = 1; // AAC-LC core; the first freqIndex in an HE-AAC ASC IS the core rate
    } else {
      return null;
    }
    return AdtsParams(profile, freqIndex, channelConfig);
  }

  /// 7-byte ADTS header (protection absent) for a raw frame of [payloadLen].
  Uint8List headerFor(int payloadLen) {
    final frameLen = payloadLen + 7;
    final h = Uint8List(7);
    h[0] = 0xFF;
    h[1] = 0xF1; // sync low nibble: MPEG-4, layer 00, protection_absent
    h[2] = ((profile & 0x3) << 6) |
        ((freqIndex & 0xF) << 2) |
        ((channelConfig >> 2) & 0x1);
    h[3] = ((channelConfig & 0x3) << 6) | ((frameLen >> 11) & 0x3);
    h[4] = (frameLen >> 3) & 0xFF;
    h[5] = ((frameLen & 0x7) << 5) | 0x1F; // buffer fullness high (0x7FF = VBR)
    h[6] = 0xFC; // buffer fullness low | 1 raw data block
    return h;
  }
}

class WebAudioFallbackDecoder implements PlatformAudioDecoder {
  WebAudioFallbackDecoder._(this._sampleRateHint, this._codec, this._adts);

  /// Sample rate to decode AT. `decodeAudioData` resamples to the context's
  /// rate, so seeding the context with the container's rate keeps MP3 at its
  /// native 44.1 kHz instead of silently resampling everything to 48 kHz.
  final int _sampleRateHint;

  final AudioCodec _codec;

  /// Non-null when raw AAC frames can be ADTS-wrapped. Null for MP3 (never
  /// needed) and for AAC configs whose ASC was absent or inexpressible — those
  /// still play IF the packets already carry ADTS headers.
  final AdtsParams? _adts;

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
    if (config.codec != AudioCodec.mp3 && config.codec != AudioCodec.aac) {
      return null;
    }
    AdtsParams? adts;
    if (config.codec == AudioCodec.aac) {
      final asc = config.extraData;
      if (asc != null && asc.isNotEmpty) {
        adts = AdtsParams.fromAudioSpecificConfig(asc);
      }
      // adts == null is still viable: an .aac file demuxed by container
      // framing arrives with ADTS headers already on every packet.
    }
    final hint = config.sampleRate;
    final rate = (hint != null && hint >= _minRate && hint <= _maxRate)
        ? hint
        : 48000;
    return WebAudioFallbackDecoder._(rate, config.codec, adts);
  }

  /// True when [data] already starts with an ADTS header (12-bit syncword +
  /// layer 00) — pass through rather than double-wrapping.
  static bool _isAdts(Uint8List data) =>
      data.length >= 2 && data[0] == 0xFF && (data[1] & 0xF6) == 0xF0;

  @override
  Future<List<DecodedAudio>> decode(EncodedPacket packet) async {
    if (_closed) return const [];
    if (!_havePts) {
      _firstPtsUs = packet.ptsUs;
      _havePts = true;
    }
    final data = packet.data;
    if (_codec == AudioCodec.aac && !_isAdts(data)) {
      final adts = _adts;
      if (adts == null) {
        throw StateError(
          'AAC packet without an ADTS header, and no usable '
          'AudioSpecificConfig in extraData to synthesise one — this raw AAC '
          'stream cannot be fed to decodeAudioData.',
        );
      }
      if (data.length + 7 > 0x1FFF) {
        // ADTS frame_length is 13 bits; a real AAC frame is ~1/4 of this.
        throw StateError(
          'AAC packet of ${data.length} bytes exceeds the ADTS frame-length '
          'field — this is not a single raw AAC frame.',
        );
      }
      _buf.add(adts.headerFor(data.length));
    }
    _buf.add(data);
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
        'decodeAudioData could not decode the ${_codec.name} bitstream ($e). '
        'This fallback needs a self-contained stream: raw MP3 frames, or AAC '
        'as ADTS (native ADTS packets, or raw frames wrapped here from the '
        "container's AudioSpecificConfig).",
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
