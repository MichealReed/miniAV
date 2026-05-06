/// Builder that captures recording configuration: sources + sinks + global
/// options. Compose then call [build] to get a [Recorder].
library;

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

import 'recorder.dart';
import 'recorder_sink.dart';
import 'recorder_source.dart';

export 'screen_effect.dart';
export 'screen_scale_policy.dart';

class RecorderBuilder {
  final List<RecorderSource> _sources = [];
  final List<RecorderSink> _sinks = [];

  /// Default video encoder bitrate (bits/sec) when a source doesn't override.
  int defaultVideoBitrate = 6_000_000;

  /// Default audio encoder bitrate (bits/sec) when a source doesn't override.
  int defaultAudioBitrate = 128_000;

  /// Default frame-rate hint passed to video encoders. Capture sources may
  /// supply a different actual rate.
  int defaultFrameRate = 30;

  /// Backend preference (forwarded to [MiniAVTools.createEncoder] /
  /// [MiniAVTools.createAudioEncoder]).
  BackendPreference backendPreference = BackendPreference.auto;

  /// When true (and at least one source benefits, e.g. screen capture on
  /// Windows with HW encoding), the recorder spins up a shared GPU device
  /// and asks backends to use a zero-copy data path. Backends fall back
  /// to the regular CPU upload path on any failure, so this is safe to
  /// leave on. Defaults to `true`.
  bool preferZeroCopy = true;

  // --- sources -------------------------------------------------------------

  /// Add a screen / display source.
  ///
  /// If [displayId] is null, the platform's default display is used.
  /// [codec] defaults to H.264. Provide [width]/[height]/[fps] to override
  /// the platform default capture format.
  ///
  /// [scale] controls optional GPU downscaling before encoding.
  /// [ScreenScalePolicy.h264Friendly] is recommended for ultrawide / 4K+
  /// displays — it auto-downscales so H.264 HW stays in range (max dim ≤ 4096)
  /// without the automatic HEVC codec promotion.
  ///
  /// [effects] is an ordered list of GPU post-processing effects applied after
  /// downscaling. All effects run on the GPU (WGSL compute shaders) with no
  /// CPU copy. Requires the zero-copy GPU path; silently ignored otherwise.
  void addScreen({
    String? displayId,
    String? windowId,
    VideoCodec codec = VideoCodec.h264,
    int? bitrateBps,
    int? width,
    int? height,
    int? fps,
    HwAccelPreference hwAccel = HwAccelPreference.preferred,
    ScreenScalePolicy scale = ScreenScalePolicy.none,
    List<ScreenEffect> effects = const [],
  }) {
    _sources.add(
      ScreenRecorderSource(
        displayId: displayId,
        windowId: windowId,
        codec: codec,
        bitrateBps: bitrateBps,
        width: width,
        height: height,
        fps: fps,
        hwAccel: hwAccel,
        scale: scale,
        effects: effects,
      ),
    );
  }

  /// Add a camera source.
  void addCamera({
    required String deviceId,
    VideoCodec codec = VideoCodec.h264,
    int? bitrateBps,
    int? width,
    int? height,
    int? fps,
    HwAccelPreference hwAccel = HwAccelPreference.preferred,
  }) {
    _sources.add(
      CameraRecorderSource(
        deviceId: deviceId,
        codec: codec,
        bitrateBps: bitrateBps,
        width: width,
        height: height,
        fps: fps,
        hwAccel: hwAccel,
      ),
    );
  }

  /// Add a microphone source.
  void addMic({
    required String deviceId,
    AudioCodec codec = AudioCodec.aac,
    int? bitrateBps,
    int? sampleRate,
    int? channels,
  }) {
    _sources.add(
      MicRecorderSource(
        deviceId: deviceId,
        codec: codec,
        bitrateBps: bitrateBps,
        sampleRate: sampleRate,
        channels: channels,
      ),
    );
  }

  /// Add a system-loopback source (records what's currently being played).
  void addLoopback({
    required String deviceId,
    AudioCodec codec = AudioCodec.aac,
    int? bitrateBps,
    int? sampleRate,
    int? channels,
  }) {
    _sources.add(
      LoopbackRecorderSource(
        deviceId: deviceId,
        codec: codec,
        bitrateBps: bitrateBps,
        sampleRate: sampleRate,
        channels: channels,
      ),
    );
  }

  // --- sinks ---------------------------------------------------------------

  /// Mux every source's encoded packets into a container file.
  ///
  /// [container] defaults to MKV when the file has any audio source +
  /// any video source (more permissive than MP4 with multiple tracks).
  /// Otherwise MP4.
  void addFileOutput(String path, {Container? container}) {
    _sinks.add(FileRecorderSink(path: path, container: container));
  }

  /// Receive a [TrackChunk] for every encoded packet from every source.
  /// Useful for live streaming / network forwarding without an on-disk
  /// container.
  void addStreamOutput(void Function(Object chunk) onChunk) {
    _sinks.add(StreamRecorderSink(onChunk: onChunk));
  }

  // --- build ---------------------------------------------------------------

  Recorder build() {
    if (_sources.isEmpty) {
      throw StateError(
        'RecorderBuilder.build: no sources — call addScreen/addCamera/'
        'addMic/addLoopback first.',
      );
    }
    if (_sinks.isEmpty) {
      throw StateError(
        'RecorderBuilder.build: no sinks — call addFileOutput / '
        'addStreamOutput first.',
      );
    }
    return Recorder.internal(
      sources: List.unmodifiable(_sources),
      sinks: List.unmodifiable(_sinks),
      defaultVideoBitrate: defaultVideoBitrate,
      defaultAudioBitrate: defaultAudioBitrate,
      defaultFrameRate: defaultFrameRate,
      backendPreference: backendPreference,
      preferZeroCopy: preferZeroCopy,
    );
  }
}
