import 'dart:async';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

import 'package:miniav_platform_interface/miniav_audio_input_interface.dart';
import 'package:miniav_platform_interface/miniav_platform_types.dart';

import 'miniav_ffi_bindings.dart' as bindings;
import 'miniav_ffi_types.dart'; // For ...FFIToPlatform and MiniAVBufferFFI

/// FFI implementation of [MiniAudioInputPlatformInterface].
class MiniAVFFIAudioInputPlatform extends MiniAudioInputPlatformInterface {
  MiniAVFFIAudioInputPlatform();

  @override
  Future<List<MiniAVDeviceInfo>> enumerateDevices() async {
    final devicesPtrPtr = calloc<ffi.Pointer<bindings.MiniAVDeviceInfo>>();
    final countPtr = calloc<ffi.Uint32>();

    try {
      final res = bindings.MiniAV_Audio_EnumerateDevices(
        devicesPtrPtr,
        countPtr,
      );

      if (res != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw Exception('Failed to enumerate audio input devices: ${res.name}');
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
      final res = bindings.MiniAV_Audio_GetDefaultFormat(
        deviceIdPtr.cast<ffi.Char>(),
        formatOutPtr,
      );

      if (res != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw Exception(
          'Failed to get default audio input format for $deviceId: ${res.name}',
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
  Future<List<MiniAVAudioInfo>> getSupportedFormats(String deviceId) async {
    final deviceIdPtr = deviceId.toNativeUtf8();
    final formatsOutPtrPtr = calloc<ffi.Pointer<bindings.MiniAVAudioInfo>>();
    final countOutPtr = calloc<ffi.Uint32>();

    try {
      final res = bindings.MiniAV_Audio_GetSupportedFormats(
        deviceIdPtr.cast<ffi.Char>(),
        formatsOutPtrPtr,
        countOutPtr,
      );

      if (res != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw Exception(
          'Failed to get supported audio input formats for $deviceId: ${res.name}',
        );
      }

      final count = countOutPtr.value;
      if (count == 0) {
        return [];
      }

      final formatsPtr = formatsOutPtrPtr.value;
      final formats = <MiniAVAudioInfo>[];
      for (int i = 0; i < count; i++) {
        final formatInfoC = (formatsPtr + i).ref;
        formats.add(
          AudioInfoFFIToPlatform.fromNative(formatInfoC).toPlatformType(),
        );
      }
      if (count > 0 && formatsPtr != ffi.nullptr) {
        bindings.MiniAV_FreeDeviceList(
          formatsPtr.cast<bindings.MiniAVDeviceInfo>(),
          count,
        );
      }

      return formats;
    } finally {
      calloc.free(deviceIdPtr);
      calloc.free(formatsOutPtrPtr);
      calloc.free(countOutPtr);
    }
  }

  @override
  Future<MiniAudioInputContextPlatformInterface> createContext() async {
    final contextHandlePtr = calloc<bindings.MiniAVAudioContextHandle>();
    try {
      final res = bindings.MiniAV_Audio_CreateContext(contextHandlePtr);
      if (res != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw Exception('Failed to create audio input context: ${res.name}');
      }
      return MiniAVFFIAudioInputContextPlatform(contextHandlePtr.value);
    } finally {
      calloc.free(contextHandlePtr);
    }
  }
}

/// FFI implementation of [MiniAudioInputContextPlatformInterface].
class MiniAVFFIAudioInputContextPlatform
    extends MiniAudioInputContextPlatformInterface {
  final bindings.MiniAVAudioContextHandle _contextHandle;
  ffi.NativeCallable<bindings.MiniAVBufferCallbackFunction>? _callbackHandle;

  MiniAVFFIAudioInputContextPlatform(this._contextHandle);

  @override
  Future<void> configure(String deviceId, MiniAVAudioInfo format) async {
    final deviceIdPtr = deviceId.toNativeUtf8();
    final formatCPtr = calloc<bindings.MiniAVAudioInfo>();

    try {
      AudioInfoFFIToPlatform.copyToNative(format, formatCPtr.ref);

      final res = bindings.MiniAV_Audio_Configure(
        _contextHandle,
        deviceIdPtr.cast<ffi.Char>(),
        formatCPtr,
      );

      if (res != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw Exception(
          'Failed to configure audio input for $deviceId: ${res.name}',
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
      final res = bindings.MiniAV_Audio_GetConfiguredFormat(
        _contextHandle,
        formatOutPtr,
      );
      if (res != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw Exception(
          'Failed to get configured audio input format: ${res.name}',
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
        print('Error in audio input user callback: $e\n$s');
      }
      // If MiniAV_ReleaseBuffer is needed and buffer.ref.internal_handle is valid:
      // if (buffer.ref.internal_handle != ffi.nullptr) {
      //   bindings.MiniAV_ReleaseBuffer(buffer.ref.internal_handle);
      // }
    }

    _callbackHandle =
        ffi.NativeCallable<bindings.MiniAVBufferCallbackFunction>.listener(
          ffiCallback,
        );

    final res = bindings.MiniAV_Audio_StartCapture(
      _contextHandle,
      _callbackHandle!.nativeFunction,
      ffi.nullptr, // User data for C callback; Dart closure handles state
    );

    if (res != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
      _callbackHandle?.close();
      _callbackHandle = null;
      throw Exception('Failed to start audio input capture: ${res.name}');
    }
  }

  @override
  Future<void> stopCapture() async {
    if (_callbackHandle == null) {
      return Future.value();
    }
    final res = bindings.MiniAV_Audio_StopCapture(_contextHandle);

    _callbackHandle?.close();
    _callbackHandle = null;

    if (res != bindings.MiniAVResultCode.MINIAV_SUCCESS &&
        res != bindings.MiniAVResultCode.MINIAV_ERROR_NOT_RUNNING) {
      print('Warning: MiniAV_Audio_StopCapture failed: ${res.name}');
      // throw Exception('Failed to stop audio input capture: ${res.name}');
    }
  }

  @override
  Future<void> destroy() async {
    await stopCapture(); // Ensures callback is closed
    final res = bindings.MiniAV_Audio_DestroyContext(_contextHandle);
    if (res != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
      throw Exception('Failed to destroy audio input context: ${res.name}');
    }
  }
}
