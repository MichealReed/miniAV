/// Runtime browser capability detection.
///
/// Use before creating encoders or initialising GPU compute to avoid
/// exceptions from unavailable APIs.
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'web_audio_interop.dart' as wc;

@JS('globalThis.VideoEncoder')
external JSAny? get _videoEncoderCtor;

@JS('globalThis.VideoDecoder')
external JSAny? get _videoDecoderCtor;

@JS('globalThis.AudioEncoder')
external JSAny? get _audioEncoderCtor;

@JS('globalThis.AudioDecoder')
external JSAny? get _audioDecoderCtor;

@JS('globalThis.MediaRecorder')
external JSAny? get _mediaRecorderCtor;

@JS('globalThis.OffscreenCanvas')
external JSAny? get _offscreenCanvasCtor;

@JS('navigator.gpu')
external JSAny? get _navigatorGpu;

/// Static helpers that probe the current browser environment.
///
/// All getters are synchronous and safe to call at any time (they do not
/// throw even in a non-browser or restricted context).
abstract final class WebCapability {
  WebCapability._();

  // ---------------------------------------------------------------------------
  // Synchronous feature flags
  // ---------------------------------------------------------------------------

  /// True when the WebCodecs [VideoEncoder] API is present.
  ///
  /// Supported: Chrome 94+, Safari 16.4+, Firefox 130+.
  static bool get hasVideoEncoder {
    final v = _videoEncoderCtor;
    return v != null && !v.isUndefined;
  }

  /// True when the WebCodecs [VideoDecoder] API is present.
  static bool get hasVideoDecoder {
    final v = _videoDecoderCtor;
    return v != null && !v.isUndefined;
  }

  /// True when the WebCodecs [AudioEncoder] API is present.
  static bool get hasAudioEncoder {
    final v = _audioEncoderCtor;
    return v != null && !v.isUndefined;
  }

  /// True when the WebCodecs [AudioDecoder] API is present.
  static bool get hasAudioDecoder {
    final v = _audioDecoderCtor;
    return v != null && !v.isUndefined;
  }

  /// True when the [MediaRecorder] API is present (universal baseline fallback).
  static bool get hasMediaRecorder {
    final v = _mediaRecorderCtor;
    return v != null && !v.isUndefined;
  }

  /// True when WebGPU (`navigator.gpu`) is available.
  ///
  /// Requires Chrome 113+, Edge 113+ (or earlier with `--enable-unsafe-webgpu`).
  /// Firefox and Safari do not yet ship WebGPU unconditionally.
  static bool get hasWebGPU {
    final v = _navigatorGpu;
    return v != null && !v.isUndefined;
  }

  /// True when `OffscreenCanvas` is available (needed for CPU→VideoFrame conversion).
  static bool get hasOffscreenCanvas {
    final v = _offscreenCanvasCtor;
    return v != null && !v.isUndefined;
  }

  // ---------------------------------------------------------------------------
  // Async codec support checks
  // ---------------------------------------------------------------------------

  /// Returns `true` if a [VideoEncoder] can be configured with [codecString]
  /// at the given [width] × [height].
  ///
  /// Uses `VideoEncoder.isConfigSupported()` — an async call to the browser.
  /// Returns `false` if [hasVideoEncoder] is false or on any error.
  ///
  /// Example codec strings: `'avc1.42E01E'` (H.264 Baseline 3.0),
  /// `'vp09.00.10.08'` (VP9), `'av01.0.04M.08'` (AV1).
  static Future<bool> isVideoEncoderSupported(
    String codecString, {
    int width = 1280,
    int height = 720,
  }) async {
    if (!hasVideoEncoder) return false;
    try {
      final support = await web.VideoEncoder.isConfigSupported(
        web.VideoEncoderConfig(
          codec: codecString,
          width: width,
          height: height,
        ),
      ).toDart;
      return support.supported;
    } catch (_) {
      return false;
    }
  }

  /// Returns `true` if a [VideoDecoder] can actually be configured for
  /// [codecString].
  ///
  /// [hasVideoDecoder] only proves the CONSTRUCTOR exists. HEVC and AV1 in
  /// particular depend on the browser AND the hardware, so a decoder that
  /// exists can still refuse the codec — without this the backend would
  /// configure and throw instead of declining. (Video ENCODE has always been
  /// gated this way; decode was not, which was simply an oversight.)
  ///
  /// Returns `false` if [hasVideoDecoder] is false; `true` when the probe
  /// itself is unavailable, leaving `configure()` as the judge.
  static Future<bool> isVideoDecoderSupported(
    String codecString, {
    int width = 1280,
    int height = 720,
  }) async {
    if (!hasVideoDecoder) return false;
    try {
      final support = await web.VideoDecoder.isConfigSupported(
        web.VideoDecoderConfig(
          codec: codecString,
          codedWidth: width,
          codedHeight: height,
        ),
      ).toDart;
      return support.supported;
    } catch (_) {
      return true;
    }
  }

  /// Returns `true` if an [AudioDecoder] can actually be configured for
  /// [codecString] at [sampleRate]/[channels].
  ///
  /// [hasAudioDecoder] only proves the CONSTRUCTOR exists; a browser can ship
  /// the API without a given codec. Checking here lets the WebCodecs backend
  /// decline cleanly so the negotiator falls through to a fallback, instead of
  /// configuring and throwing at the user.
  ///
  /// Returns `false` if [hasAudioDecoder] is false or on any error.
  static Future<bool> isAudioDecoderSupported(
    String codecString, {
    int sampleRate = 48000,
    int channels = 2,
  }) async {
    if (!hasAudioDecoder) return false;
    try {
      final support = await wc.AudioDecoder.isConfigSupported(
        wc.AudioDecoderConfig(
          codec: codecString,
          sampleRate: sampleRate,
          numberOfChannels: channels,
        ),
      ).toDart;
      return support.supported;
    } catch (_) {
      // Older implementations lack isConfigSupported entirely. Absence of the
      // probe is not evidence of absence of the codec — assume supported and
      // let configure() be the judge, exactly as before this check existed.
      return true;
    }
  }
}
