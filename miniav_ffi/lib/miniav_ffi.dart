import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:miniav_ffi/miniav_ffi_log_port.dart';
import 'package:miniav_ffi/modules/miniav_ffi_audio_input.dart';
import 'package:miniav_ffi/modules/miniav_ffi_audio_output.dart';
import 'package:miniav_ffi/modules/miniav_ffi_loopback.dart';
import 'package:miniav_ffi/modules/miniav_ffi_input.dart';
import 'package:miniav_ffi/modules/miniav_ffi_inject.dart';
import 'miniav_ffi_bindings.dart' as bindings;
import 'modules/miniav_ffi_camera.dart';
import 'modules/miniav_ffi_screen.dart';
import 'package:miniav_platform_interface/miniav_platform_interface.dart';

// Export camera FFI implementation for external use
export 'modules/miniav_ffi_camera.dart';
export 'modules/miniav_ffi_screen.dart';
export 'modules/miniav_ffi_audio_input.dart';
export 'modules/miniav_ffi_audio_output.dart';
export 'modules/miniav_ffi_loopback.dart';
export 'modules/miniav_ffi_input.dart';
export 'modules/miniav_ffi_inject.dart';

// --- Platform Implementation ---

class MiniAVFFIPlatform extends MiniAVPlatformInterface {
  MiniAVFFIPlatform();

  final MiniFFICameraPlatform _camera = MiniFFICameraPlatform();
  final MiniFFIScreenPlatform _screen = MiniFFIScreenPlatform();
  final MiniAVFFILoopbackPlatform _loopback = MiniAVFFILoopbackPlatform();
  final MiniAVFFIAudioInputPlatform _audioInput = MiniAVFFIAudioInputPlatform();
  final MiniAVFFIAudioOutputPlatform _audioOutput =
      MiniAVFFIAudioOutputPlatform();
  final MiniAVFFIInputPlatform _input = MiniAVFFIInputPlatform();
  final MiniAVFFIInjectPlatform _inject = MiniAVFFIInjectPlatform();

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
  String getVersionString() {
    final ptr = bindings.MiniAV_GetVersionString();
    if (ptr == ffi.nullptr) return "Unknown Version";
    return ptr.cast<Utf8>().toDartString();
  }

  @override
  void setLogLevel(int level) {
    // The platform interface enum index order is: none=0, trace=1, debug=2,
    // info=3, warn=4, error=5.  The C enum order is: TRACE=0, DEBUG=1,
    // INFO=2, WARN=3, ERROR=4, NONE=5.  They differ: none is first in Dart
    // but last in C.  Map by semantic meaning, not by index.
    //   platform none(0) → C NONE(5), trace(1)→TRACE(0), debug(2)→DEBUG(1),
    //   info(3)→INFO(2), warn(4)→WARN(3), error(5)→ERROR(4).
    final cValue = level == 0 ? 5 : level - 1;
    final result = bindings.MiniAV_SetLogLevel(
      bindings.MiniAVLogLevel.fromValue(cValue),
    );
    if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
      throw Exception('Failed to set log level');
    }
  }

  // ---- Log callback --------------------------------------------------------
  // Delivery is a Dart NATIVE PORT, not a NativeCallable.
  //
  // MiniAV_SetLogCallback installs a PROCESS-GLOBAL function pointer. A
  // NativeCallable there is owned by ONE isolate, and when that isolate exits
  // the VM deletes the trampoline while the C library keeps the pointer — the
  // next log line from a capture thread (or from inside a leaf FFI call such
  // as MiniAV_ReleaseBuffer) aborts the whole process. A whole-suite
  // `dart test` run reproduces this every time, because each test file is its
  // own isolate inside one VM process. A closed port is merely inert.
  //
  // PROCESS-GLOBAL, LAST WRITER WINS: with several isolates registered only
  // the most recent one receives log lines — exactly the old function-pointer
  // behaviour, minus the crash.

  /// Receive port for native log lines in THIS isolate.
  ReceivePort? _logPort;

  /// Whether `MiniAV_InitDartApi` has succeeded in this isolate.
  bool _dartApiInitialised = false;

  @override
  void setLogCallback(void Function(int level, String message)? callback) {
    final old = _logPort;
    _logPort = null;

    if (callback == null) {
      miniavSetLogPort(0);
      old?.close();
      return;
    }

    if (!_dartApiInitialised) {
      if (miniavInitDartApi(ffi.NativeApi.initializeApiDLData) != 0) {
        // Built without the Dart API (web/wasm) or an SDK mismatch. Leave the
        // native library on its stderr sink rather than risk the crash-prone
        // function-pointer path.
        old?.close();
        return;
      }
      _dartApiInitialised = true;
    }

    final port = ReceivePort('miniav_ffi.log');
    port.listen((dynamic message) {
      // Wire format: [int32 level, Uint8List utf8Bytes]. Bytes rather than a
      // string because device names may carry non-UTF-8 (Latin-1) sequences;
      // allowMalformed keeps those from throwing.
      if (message is! List || message.length != 2) return;
      callback(
        message[0] as int,
        const Utf8Decoder(
          allowMalformed: true,
        ).convert(message[1] as Uint8List),
      );
    });
    _logPort = port;
    miniavSetLogPort(port.sendPort.nativePort);
    old?.close();
  }

  @override
  void dispose() {
    // Atomically disable callback dispatch and wait for any in-flight
    // callback invocations to finish.  Safe to call from Flutter's
    // reassemble() before the Dart isolate closes its NativeCallable handles.
    bindings.MiniAV_Dispose();
  }

  @override
  Future<void> releaseBuffer(MiniAVBuffer buffer) async {
    releaseBufferSync(buffer);
  }

  /// Synchronous buffer release. The underlying C call `MiniAV_ReleaseBuffer`
  /// is itself synchronous, so this does the work inline with no [Future] /
  /// microtask allocation — the recorder's per-frame capture callback uses this
  /// rather than the async [releaseBuffer] to keep the hot path allocation-free.
  @override
  void releaseBufferSync(MiniAVBuffer buffer) {
    final nativeHandle = buffer.nativeHandle;
    try {
      if (nativeHandle != null && nativeHandle is ffi.Pointer) {
        final result = bindings.MiniAV_ReleaseBuffer(
          nativeHandle.cast<ffi.Void>(),
        );
        if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
          throw Exception('Failed to release buffer: $result');
        }
      }
    } catch (e) {
      print('Error releasing buffer: $e');
    }
  }
}

MiniAVPlatformInterface registeredInstance() => MiniAVFFIPlatform();
