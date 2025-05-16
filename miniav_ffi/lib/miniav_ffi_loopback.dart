import 'dart:async';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

import 'package:miniav_platform_interface/miniav_loopback_interface.dart';
import 'package:miniav_platform_interface/miniav_platform_types.dart';

import 'miniav_ffi_bindings.dart' as bindings;
import 'miniav_ffi_types.dart'; // For ...FFIToPlatform and MiniAVBufferFFI

/// FFI implementation of [MiniLoopbackPlatformInterface].
class MiniAVFFILoopbackPlatform extends MiniLoopbackPlatformInterface {
  MiniAVFFILoopbackPlatform();

  @override
  Future<List<MiniAVDeviceInfo>> enumerateDevices() async {
    final devicesPtrPtr = calloc<ffi.Pointer<bindings.MiniAVDeviceInfo>>();
    final countPtr = calloc<ffi.Uint32>();

    try {
      final res = bindings.MiniAV_Loopback_EnumerateTargets(
        bindings.MiniAVLoopbackTargetType.MINIAV_LOOPBACK_TARGET_SYSTEM_AUDIO,
        devicesPtrPtr,
        countPtr,
      );

      if (res != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw Exception('Failed to enumerate loopback devices: ${res.name}');
      }

      final count = countPtr.value;
      if (count == 0) {
        return [];
      }

      final devicesPtr = devicesPtrPtr.value;
      final devices = <MiniAVDeviceInfo>[];
      for (int i = 0; i < count; i++) {
        final deviceInfoC = devicesPtr.elementAt(i).ref;
        devices.add(
          DeviceInfoFFIToPlatform.fromNative(deviceInfoC).toPlatformType(),
        );
      }

      bindings.MiniAV_FreeDeviceList(devicesPtr, count);
      return devices;
    } finally {
      calloc.free(devicesPtrPtr);
      calloc.free(countPtr);
    }
  }

  @override
  Future<MiniAVAudioInfo> getDefaultFormat(String deviceId) async {
    final deviceIdPtr = deviceId.toNativeUtf8();
    final formatOutPtr = calloc<bindings.MiniAVAudioInfo>();

    try {
      final res = bindings.MiniAV_Loopback_GetDefaultFormat(
        deviceIdPtr.cast<ffi.Char>(),
        formatOutPtr,
      );

      if (res != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw Exception(
          'Failed to get default loopback format for $deviceId: ${res.name}',
        );
      }
      return AudioInfoFFIToPlatform.fromNative(
        formatOutPtr.ref,
      ).toPlatformType();
    } finally {
      calloc.free(deviceIdPtr);
      calloc.free(formatOutPtr);
    }
  }

  @override
  Future<MiniLoopbackContextPlatformInterface> createContext() async {
    final contextHandlePtr = calloc<bindings.MiniAVLoopbackContextHandle>();
    try {
      final res = bindings.MiniAV_Loopback_CreateContext(contextHandlePtr);
      if (res != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw Exception('Failed to create loopback context: ${res.name}');
      }
      return MiniAVFFILoopbackContextPlatform(contextHandlePtr.value);
    } finally {
      calloc.free(contextHandlePtr);
    }
  }
}

/// FFI implementation of [MiniLoopbackContextPlatformInterface].
class MiniAVFFILoopbackContextPlatform
    extends MiniLoopbackContextPlatformInterface {
  final bindings.MiniAVLoopbackContextHandle _contextHandle;
  ffi.NativeCallable<bindings.MiniAVBufferCallbackFunction>? _callbackHandle;

  MiniAVFFILoopbackContextPlatform(this._contextHandle);

  @override
  Future<void> configure(String deviceId, MiniAVAudioInfo format) async {
    final deviceIdPtr = deviceId.toNativeUtf8();
    final formatCPtr = calloc<bindings.MiniAVAudioInfo>();

    try {
      AudioInfoFFIToPlatform.copyToNative(format, formatCPtr.ref);

      final res = bindings.MiniAV_Loopback_Configure(
        _contextHandle,
        deviceIdPtr.cast<ffi.Char>(),
        formatCPtr,
      );

      if (res != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw Exception(
          'Failed to configure loopback for $deviceId: ${res.name}',
        );
      }
    } finally {
      calloc.free(deviceIdPtr);
      calloc.free(formatCPtr);
    }
  }

  @override
  Future<MiniAVAudioInfo> getConfiguredFormat() async {
    final formatOutPtr = calloc<bindings.MiniAVAudioInfo>();
    try {
      final res = bindings.MiniAV_Loopback_GetConfiguredFormat(
        _contextHandle,
        formatOutPtr,
      );
      if (res != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw Exception(
          'Failed to get configured loopback format: ${res.name}',
        );
      }
      return AudioInfoFFIToPlatform.fromNative(
        formatOutPtr.ref,
      ).toPlatformType();
    } finally {
      calloc.free(formatOutPtr);
    }
  }

  @override
  Future<void> startCapture(
    void Function(MiniAVBuffer buffer, Object? userData) onData, {
    Object? userData,
  }) async {
    await stopCapture(); // Clean up any previous callback

    void ffiCallback(
      ffi.Pointer<bindings.MiniAVBuffer> buffer,
      ffi.Pointer<ffi.Void> cbUserData, // This will be ffi.nullptr from C
    ) {
      final platformBuffer = MiniAVBufferFFI.fromPointer(buffer);
      try {
        onData(platformBuffer, userData);
      } catch (e, s) {
        print('Error in loopback user callback: $e\n$s');
      }
      // If MiniAV_ReleaseBuffer is needed and buffer.ref.internal_handle is valid:
      // if (buffer.ref.internal_handle != ffi.nullptr) {
      //   _bindings.MiniAV_ReleaseBuffer(buffer.ref.internal_handle);
      // }
    }

    _callbackHandle =
        ffi.NativeCallable<bindings.MiniAVBufferCallbackFunction>.listener(
          ffiCallback,
        );

    final res = bindings.MiniAV_Loopback_StartCapture(
      _contextHandle,
      _callbackHandle!.nativeFunction,
      ffi.nullptr, // User data for C callback; Dart closure handles state
    );

    if (res != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
      _callbackHandle?.close();
      _callbackHandle = null;
      throw Exception('Failed to start loopback capture: ${res.name}');
    }
  }

  @override
  Future<void> stopCapture() async {
    // Only stop if context and callback were potentially active
    if (_callbackHandle == null) {
      return Future.value();
    }
    final res = bindings.MiniAV_Loopback_StopCapture(_contextHandle);

    _callbackHandle?.close();
    _callbackHandle = null;

    // MINIAV_ERROR_NOT_RUNNING is an acceptable "failure" if already stopped.
    if (res != bindings.MiniAVResultCode.MINIAV_SUCCESS &&
        res != bindings.MiniAVResultCode.MINIAV_ERROR_NOT_RUNNING) {
      // Log or throw based on strictness. Camera example throws.
      print('Warning: MiniAV_Loopback_StopCapture failed: ${res.name}');
      // throw Exception('Failed to stop loopback capture: ${res.name}');
    }
  }

  @override
  Future<void> destroy() async {
    await stopCapture(); // Ensures callback is closed
    final res = bindings.MiniAV_Loopback_DestroyContext(_contextHandle);
    if (res != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
      throw Exception('Failed to destroy loopback context: ${res.name}');
    }
  }
}
