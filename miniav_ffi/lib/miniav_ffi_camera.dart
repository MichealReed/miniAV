import 'package:miniav_platform_interface/miniav_platform_interface.dart';
import 'miniav_ffi_types.dart';
import 'miniav_ffi_bindings.dart' as bindings;
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

class MiniFFICameraPlatform implements MiniCameraPlatformInterface {
  @override
  Future<List<MiniAVDeviceInfo>> enumerateDevices() async {
    final devicesPtrPtr = calloc<ffi.Pointer<bindings.MiniAVDeviceInfo>>();
    final countPtr = calloc<ffi.Uint32>();
    try {
      final result = bindings.MiniAV_Camera_EnumerateDevices(
        devicesPtrPtr,
        countPtr,
      );
      if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw Exception('Failed to enumerate camera devices');
      }
      final devicesArrayPtr = devicesPtrPtr.value;
      final count = countPtr.value;
      if (devicesArrayPtr == ffi.nullptr || count == 0) {
        return <MiniAVDeviceInfo>[];
      }
      final deviceList = <MiniAVDeviceInfo>[];
      for (int i = 0; i < count; i++) {
        final ffiDevice = (devicesArrayPtr + i).ref;
        deviceList.add(
          DeviceInfoFFIToPlatform.fromNative(ffiDevice).toPlatformType(),
        );
      }
      bindings.MiniAV_FreeDeviceList(devicesArrayPtr, count);
      return deviceList;
    } finally {
      calloc.free(devicesPtrPtr);
      calloc.free(countPtr);
    }
  }

  @override
  Future<List<MiniAVVideoFormatInfo>> getSupportedFormats(
    String deviceId,
  ) async {
    final deviceIdPtr = deviceId.toNativeUtf8();
    final formatsPtrPtr = calloc<ffi.Pointer<bindings.MiniAVVideoFormatInfo>>();
    final countPtr = calloc<ffi.Uint32>();
    try {
      final result = bindings.MiniAV_Camera_GetSupportedFormats(
        deviceIdPtr.cast(),
        formatsPtrPtr,
        countPtr,
      );
      if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw Exception('Failed to get supported formats');
      }
      final formatsArrayPtr = formatsPtrPtr.value;
      final count = countPtr.value;
      if (formatsArrayPtr == ffi.nullptr || count == 0) {
        return <MiniAVVideoFormatInfo>[];
      }
      final formatList = <MiniAVVideoFormatInfo>[];
      for (int i = 0; i < count; i++) {
        final ffiFormat = (formatsArrayPtr + i).ref;
        formatList.add(
          VideoFormatInfoFFIToPlatform.fromNative(ffiFormat).toPlatformType(),
        );
      }
      bindings.MiniAV_FreeFormatList(formatsArrayPtr.cast<ffi.Void>(), count);
      return formatList;
    } finally {
      calloc.free(deviceIdPtr);
      calloc.free(formatsPtrPtr);
      calloc.free(countPtr);
    }
  }

  @override
  Future<MiniCameraContextPlatformInterface> createContext() async {
    final contextPtr = calloc<bindings.MiniAVCameraContextHandle>();
    try {
      final result = bindings.MiniAV_Camera_CreateContext(contextPtr);
      if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw Exception('Failed to create camera context');
      }
      return MiniFFICameraContext(contextPtr.value);
    } finally {
      calloc.free(contextPtr);
    }
  }
}

class MiniFFICameraContext implements MiniCameraContextPlatformInterface {
  final bindings.MiniAVCameraContextHandle _context;
  ffi.NativeCallable<bindings.MiniAVBufferCallbackFunction>? _callbackHandle;

  MiniFFICameraContext(this._context);

  @override
  Future<void> configure(String deviceId, MiniAVVideoFormatInfo format) async {
    final deviceIdPtr = deviceId.toNativeUtf8();
    final nativeFormatPtr = calloc<bindings.MiniAVVideoFormatInfo>();
    try {
      VideoFormatInfoFFIToPlatform.copyToNative(format, nativeFormatPtr.ref);
      final result = bindings.MiniAV_Camera_Configure(
        _context,
        deviceIdPtr.cast(),
        nativeFormatPtr.cast(),
      );
      if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw Exception('Failed to configure camera');
      }
    } finally {
      calloc.free(deviceIdPtr);
      calloc.free(nativeFormatPtr);
    }
  }

  @override
  Future<void> startCapture(
    void Function(MiniAVBuffer buffer, Object? userData) onFrame, {
    Object? userData,
  }) async {
    // Clean up any previous callback
    await stopCapture();

    void ffiCallback(
      ffi.Pointer<bindings.MiniAVBuffer> buffer,
      ffi.Pointer<ffi.Void> cbUserData,
    ) {
      final platformBuffer = MiniAVBufferFFI.fromPointer(
        buffer,
      ); // You must implement this
      onFrame(platformBuffer, userData);
    }

    _callbackHandle =
        ffi.NativeCallable<bindings.MiniAVBufferCallbackFunction>.listener(
          ffiCallback,
        );

    final result = bindings.MiniAV_Camera_StartCapture(
      _context,
      _callbackHandle!.nativeFunction,
      ffi.nullptr, // You can pass userData pointer if needed
    );

    if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
      _callbackHandle?.close();
      _callbackHandle = null;
      throw Exception('Failed to start camera capture');
    }
  }

  @override
  Future<void> stopCapture() async {
    final result = bindings.MiniAV_Camera_StopCapture(_context);
    _callbackHandle?.close();
    _callbackHandle = null;
    if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
      throw Exception('Failed to stop camera capture');
    }
  }

  @override
  Future<void> destroy() async {
    await stopCapture();
    final result = bindings.MiniAV_Camera_DestroyContext(_context);
    if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
      throw Exception('Failed to destroy camera context');
    }
  }
}
