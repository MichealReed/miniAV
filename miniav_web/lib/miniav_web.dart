import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:miniav_platform_interface/miniav_platform_interface.dart';
import 'package:web/web.dart' as web;

import 'src/miniav_wasm.dart' as wasm;

export 'package:miniav_platform_interface/miniav_platform_interface.dart';

part 'modules/miniav_web_camera.dart';
part 'modules/miniav_web_screen.dart';
part 'modules/miniav_web_audio_input.dart';
part 'modules/miniav_web_audio_output.dart';
part 'modules/miniav_web_loopback.dart';
part 'modules/miniav_web_input.dart';
part 'modules/miniav_web_inject.dart';
part './miniav_web_utils.dart';
part './miniav_web_subscriptions.dart';

/// Web implementation of MiniAV platform interface
class MiniAVWebPlatform extends MiniAVPlatformInterface {
  MiniAVWebPlatform();

  final MiniCameraPlatformInterface _camera = MiniAVWebCameraPlatform();
  final MiniScreenPlatformInterface _screen = MiniAVWebScreenPlatform();
  final MiniAudioInputPlatformInterface _audioInput =
      MiniAVWebAudioInputPlatform();
  final MiniAudioOutputPlatformInterface _audioOutput =
      MiniAVWebAudioOutputPlatform();
  final MiniLoopbackPlatformInterface _loopback = MiniAVWebLoopbackPlatform();
  final MiniInputPlatformInterface _input = MiniAVWebInputPlatform();
  final MiniInjectPlatformInterface _inject = MiniAVWebInjectPlatform();

  @override
  MiniCameraPlatformInterface get camera => _camera;

  @override
  MiniScreenPlatformInterface get screen => _screen;

  @override
  MiniAudioInputPlatformInterface get audioInput => _audioInput;

  @override
  MiniAudioOutputPlatformInterface get audioOutput => _audioOutput;

  @override
  MiniLoopbackPlatformInterface get loopback => _loopback;

  @override
  MiniInputPlatformInterface get input => _input;

  @override
  MiniInjectPlatformInterface get inject => _inject;

  @override
  String getVersionString() => '1.0.0-web';

  @override
  void setLogLevel(int level) {
    // Web implementation uses console logging
    // Could be extended to filter based on level
  }

  @override
  void dispose() {}

  @override
  Future<void> releaseBuffer(MiniAVBuffer buffer) async {
    releaseBufferSync(buffer);
  }

  @override
  void releaseBufferSync(MiniAVBuffer buffer) {
    // 🔴 NO LONGER A NO-OP. A CPU buffer is plain Dart bytes and needs nothing,
    // which is why this used to do nothing at all — but a
    // [MiniAVBufferContentType.gpuWebVideoFrame] buffer carries a WebCodecs
    // `VideoFrame`, and a VideoFrame that is not `close()`d pins a capture
    // surface. The browser hands out only a few at a time, so a
    // `MediaStreamTrackProcessor` whose frames leak STOPS PRODUCING once its
    // queue fills — silently, with no error and no event. Leaving this a no-op
    // would make the zero-copy camera path deliver about three frames and then
    // freeze, which looks exactly like a broken camera.
    if (buffer.contentType != MiniAVBufferContentType.gpuWebVideoFrame) return;
    final vb = buffer.data;
    if (vb is! MiniAVVideoBuffer || vb.nativeHandles.isEmpty) return;
    final frame = vb.nativeHandles[0];
    if (frame is web.VideoFrame) frame.close();
  }
}

/// Registers the web implementation of MiniAV
MiniAVPlatformInterface registeredInstance() => MiniAVWebPlatform();
