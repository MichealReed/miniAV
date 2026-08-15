/// WebCodecs-backed audio decoder.
///
/// Wraps the browser `AudioDecoder` (hand-rolled interop — `package:web` lacks
/// the audio WebCodecs types) and implements [PlatformAudioDecoder]. Each
/// packet decodes to `AudioData`, which is copied out as INTERLEAVED f32 (the
/// [DecodedAudio] layout the player's miniaudio `StreamPlayer` sink wants).
///
/// The browser `AudioDecoder` needs `sampleRate` + `numberOfChannels` at
/// configure time (WebCodecs does not derive them from the bitstream), so
/// [AudioDecoderConfig.sampleRate] / `.channels` are REQUIRED here — the
/// player supplies them from the container's audio-track info (or the app's
/// `AudioStreamSpec`). For AAC, `extraData` (AudioSpecificConfig) is passed as
/// the decoder `description`.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

import 'web_audio_interop.dart' as wc;
import 'web_backend.dart';

/// WebCodecs codec string for [codec]. Library-visible so the backend can ask
/// `AudioDecoder.isConfigSupported` about the exact string it would configure
/// with. (The encoder keeps its own copy — same table, opposite direction.)
String audioCodecString(AudioCodec codec, Map<String, String> opts) {
  if (opts.containsKey('codecString')) return opts['codecString']!;
  return switch (codec) {
    AudioCodec.aac => 'mp4a.40.2', // AAC-LC
    AudioCodec.opus => 'opus',
    AudioCodec.mp3 => 'mp3',
    AudioCodec.flac => 'flac',
    AudioCodec.vorbis => 'vorbis',
    _ => throw UnsupportedError('WebCodecs audio: no codec string for $codec'),
  };
}

class WebCodecsAudioDecoder implements PlatformAudioDecoder {
  WebCodecsAudioDecoder._();

  wc.AudioDecoder? _decoder;
  final List<DecodedAudio> _pending = [];
  Object? _lastError;

  /// Woken by [_handleData] / [_handleError]. See [_awaitOutput].
  Completer<void>? _output;

  void _wake() {
    final waiter = _output;
    _output = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  void _handleData(JSAny? dataJs) {
    if (dataJs == null || dataJs.isUndefined) return;
    final data = dataJs as wc.AudioData;
    try {
      final frames = data.numberOfFrames;
      final channels = data.numberOfChannels;
      final sampleRate = data.sampleRate;
      // Copy out as a single INTERLEAVED f32 plane (WebCodecs converts from
      // the decoder's native planar/other format).
      final opts = wc.AudioDataCopyToOptions(planeIndex: 0, format: 'f32');
      final bytes = data.allocationSize(opts);
      final out = Float32List(bytes ~/ 4);
      data.copyTo(out.toJS, opts);
      _pending.add(
        DecodedAudio(
          samples: out,
          frameCount: frames,
          sampleRate: sampleRate,
          channels: channels,
          ptsUs: data.timestamp.toInt(),
        ),
      );
    } finally {
      data.close();
      _wake();
    }
  }

  void _handleError(JSAny? errJs) {
    _lastError = errJs;
    _wake();
  }

  /// Waits for the decoder's next output callback, or [_kOutputGrace].
  ///
  /// This used to poll: `await Future.delayed(Duration.zero)` up to sixteen
  /// times, checking after each. That reads as "yield briefly", but dart2js
  /// compiles it to `setTimeout(0)` and browsers CLAMP nested timeouts to 4 ms
  /// — so the decoder's callback would fire in ~0.1 ms and we would not LOOK
  /// for another 4 ms. Measured: 5.0 ms median to decode a packet holding
  /// 20 ms of audio, i.e. a quarter of the sink's refill budget spent waiting
  /// on a timer, before anything else on the page competes. That is what
  /// underruns the audio ring and clicks.
  ///
  /// Waiting on the callback itself removes the timer from the common path
  /// entirely. The grace only runs when a packet legitimately produces nothing
  /// — Opus pre-skip, a decoder still priming — which must return empty rather
  /// than hang.
  Future<void> _awaitOutput() async {
    if (_pending.isNotEmpty || _lastError != null) return;
    final waiter = _output = Completer<void>();
    await waiter.future.timeout(_kOutputGrace, onTimeout: () {});
    _output = null;
  }

  static const Duration _kOutputGrace = Duration(milliseconds: 20);

  void _throwIfError() {
    final e = _lastError;
    if (e != null) {
      _lastError = null;
      throw CodecRuntimeException(WebCodecsBackend.backendName, e.toString());
    }
  }

  @override
  Future<List<DecodedAudio>> decode(EncodedPacket packet) async {
    _throwIfError();
    final dec = _decoder;
    if (dec == null) throw StateError('WebCodecsAudioDecoder: not open');
    final chunk = wc.EncodedAudioChunk(
      wc.EncodedAudioChunkInit(
        type: packet.isKeyframe ? 'key' : 'delta',
        timestamp: packet.ptsUs,
        // The VIEW, not `.buffer`: a demuxed packet is routinely a window into
        // a larger container buffer, and the whole backing store would feed the
        // decoder neighbouring packets as if they were this one.
        data: packet.data.toJS,
      ),
    );
    dec.decode(chunk);
    // Wait for the output callback, not for a timer; return whatever decoded
    // (0+). See [_awaitOutput].
    await _awaitOutput();
    _throwIfError();
    final out = List<DecodedAudio>.from(_pending);
    _pending.clear();
    return out;
  }

  @override
  Future<List<DecodedAudio>> flush() async {
    final dec = _decoder;
    if (dec == null) return const [];
    await dec.flush().toDart;
    _throwIfError();
    final out = List<DecodedAudio>.from(_pending);
    _pending.clear();
    return out;
  }

  @override
  Future<void> close() async {
    try {
      _decoder?.close();
    } catch (_) {}
    _decoder = null;
    _pending.clear();
    // A decode racing this close is waiting on a callback that will now never
    // come; release it rather than leave it on the grace timeout.
    _wake();
  }

  static Future<WebCodecsAudioDecoder> create(AudioDecoderConfig config) async {
    final sampleRate = config.sampleRate;
    final channels = config.channels;
    if (sampleRate == null || channels == null) {
      throw CodecInitException(
        WebCodecsBackend.backendName,
        'WebCodecs audio decode requires sampleRate + channels in '
        'AudioDecoderConfig (WebCodecs does not derive them from the '
        'bitstream). Got sampleRate=$sampleRate channels=$channels.',
      );
    }
    final dec = WebCodecsAudioDecoder._();
    final codecStr = audioCodecString(config.codec, config.backendOptions);
    dec._decoder = wc.AudioDecoder(
      wc.AudioDecoderInit(
        output: (JSAny? d) {
          dec._handleData(d);
        }.toJS,
        error: (JSAny? e) {
          dec._handleError(e);
        }.toJS,
      ),
    );
    // Codec-private data: AAC AudioSpecificConfig, FLAC STREAMINFO, Vorbis
    // headers. MP3 has none.
    //
    // `description` must be OMITTED entirely when there is none — passing it as
    // null sets the key to JS `null`, and WebCodecs then fails converting it to
    // a BufferSource with "Failed to read the 'description' property from
    // 'AudioDecoderConfig'". (A named argument explicitly passed as null is
    // still emitted into the JS object literal; only an argument left off is
    // absent.) This is why MP3 could not play on web at all.
    final extra = config.extraData;
    // Tight copy so `description` is exactly those bytes — `extra` may be a
    // view into a larger buffer.
    final cfg = (extra != null && extra.isNotEmpty)
        ? wc.AudioDecoderConfig(
            codec: codecStr,
            sampleRate: sampleRate,
            numberOfChannels: channels,
            description: Uint8List.fromList(extra).toJS,
          )
        : wc.AudioDecoderConfig(
            codec: codecStr,
            sampleRate: sampleRate,
            numberOfChannels: channels,
          );
    dec._decoder!.configure(cfg);
    dec._throwIfError();
    return dec;
  }
}
