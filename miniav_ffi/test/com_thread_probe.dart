// Diagnostic probe (not a test): prints COMTRACE lines emitted by the native
// layer so the OS thread ids behind Dart FFI calls can be inspected.
//
//   MINIAV_COM_TRACE=1 [MINIAV_LEGACY_COM=1] dart run test/com_thread_probe.dart
//
// What to look for:
//   * the SAME isolate tag with DIFFERENT tid values  -> an isolate's FFI calls
//     migrate across OS threads, so CoInitializeEx/CoUninitialize pairs split.
//   * DIFFERENT isolate tags sharing a tid            -> pool threads are reused
//     across isolates, so one isolate's CoUninitialize evicts another's thread.
import 'dart:async';
import 'dart:isolate';

import 'package:miniav_ffi/miniav_ffi.dart';

const int _trace = 1;

Future<void> _cameraWork() async {
  final camera = MiniAVFFIPlatform().camera;
  for (var i = 0; i < 4; i++) {
    final devices = await camera.enumerateDevices();
    await Future<void>.delayed(const Duration(milliseconds: 15));
    if (devices.isNotEmpty) {
      await camera.getSupportedFormats(devices.first.deviceId);
      await Future<void>.delayed(const Duration(milliseconds: 15));
    }
    final ctx = await camera.createContext();
    await Future<void>.delayed(const Duration(milliseconds: 15));
    await ctx.destroy();
    await Future<void>.delayed(const Duration(milliseconds: 15));
  }
}

Future<void> _loopbackWork() async {
  final loopback = MiniAVFFIPlatform().loopback;
  for (var i = 0; i < 4; i++) {
    await loopback.enumerateDevices();
    await Future<void>.delayed(const Duration(milliseconds: 15));
    final ctx = await loopback.createContext();
    await Future<void>.delayed(const Duration(milliseconds: 15));
    await ctx.destroy();
    await Future<void>.delayed(const Duration(milliseconds: 15));
  }
}

void _cameraIsolate(SendPort done) async {
  await _cameraWork();
  done.send(true);
}

void _loopbackIsolate(SendPort done) async {
  await _loopbackWork();
  done.send(true);
}

Future<void> main() async {
  final platform = MiniAVFFIPlatform();
  platform.setLogLevel(_trace);
  platform.setLogCallback((level, message) {
    if (message.contains('COMTRACE')) print(message);
  });

  // Isolate A touches ONLY the camera (MF), isolate B ONLY the loopback
  // (WASAPI). The main isolate makes no capture calls at all. Any OS thread id
  // that shows BOTH an mf_* and a wasapi_* call therefore served two different
  // isolates; any single isolate whose calls span several tids migrated.
  final a = ReceivePort();
  final b = ReceivePort();
  await Isolate.spawn(_cameraIsolate, a.sendPort);
  await Isolate.spawn(_loopbackIsolate, b.sendPort);
  await a.first;
  await b.first;
  a.close();
  b.close();
  platform.setLogCallback(null);
}
