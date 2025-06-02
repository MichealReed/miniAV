import 'package:miniav_platform_interface/miniav_platform_interface.dart';
import '../miniav_ffi_types.dart';
import '../miniav_ffi_bindings.dart' as bindings;
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
  Future<List<MiniAVVideoInfo>> getSupportedFormats(String deviceId) async {
    final deviceIdPtr = deviceId.toNativeUtf8();
    final formatsPtrPtr = calloc<ffi.Pointer<bindings.MiniAVVideoInfo>>();
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
        return <MiniAVVideoInfo>[];
      }
      final formatList = <MiniAVVideoInfo>[];
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
  Future<MiniAVVideoInfo> getDefaultFormat(String deviceId) async {
    final deviceIdPtr = deviceId.toNativeUtf8();
    final formatOutPtr = calloc<bindings.MiniAVVideoInfo>();
    try {
      final result = bindings.MiniAV_Camera_GetDefaultFormat(
        deviceIdPtr.cast(),
        formatOutPtr,
      );
      if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw Exception(
          'Failed to get default format for device $deviceId: ${result.name}',
        );
      }
      return VideoFormatInfoFFIToPlatform.fromNative(
        formatOutPtr.ref,
      ).toPlatformType();
    } finally {
      calloc.free(deviceIdPtr);
      calloc.free(formatOutPtr);
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
  bindings.MiniAVCameraContextHandle? _context;
  ffi.NativeCallable<bindings.MiniAVBufferCallbackFunction>? _callbackHandle;
  bool _isDestroyed = false;
  late final Finalizer<bindings.MiniAVCameraContextHandle> _finalizer;

  MiniFFICameraContext(bindings.MiniAVCameraContextHandle context)
    : _context = context {
    // Auto-cleanup if destroy() is never called
    _finalizer = Finalizer<bindings.MiniAVCameraContextHandle>((handle) {
      print(
        'Warning: CameraContext was garbage collected without calling destroy()',
      );
      bindings.MiniAV_Camera_DestroyContext(handle);
    });
    _finalizer.attach(this, context, detach: this);
  }

  /// Throws if the context has been destroyed
  void _ensureNotDestroyed() {
    if (_isDestroyed || _context == null) {
      throw StateError(
        'CameraContext has been destroyed. Create a new context to continue using camera.',
      );
    }
  }

  /// Whether this context has been destroyed
  bool get isDestroyed => _isDestroyed;

  @override
  Future<void> configure(String deviceId, MiniAVVideoInfo format) async {
    _ensureNotDestroyed();

    final deviceIdPtr = deviceId.toNativeUtf8();
    final nativeFormatPtr = calloc<bindings.MiniAVVideoInfo>();
    try {
      VideoFormatInfoFFIToPlatform.copyToNative(format, nativeFormatPtr.ref);
      final result = bindings.MiniAV_Camera_Configure(
        _context!,
        deviceIdPtr.cast(),
        nativeFormatPtr.cast(),
      );
      if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw Exception('Failed to configure camera: ${result.name}');
      }
    } finally {
      calloc.free(deviceIdPtr);
      calloc.free(nativeFormatPtr);
    }
  }

  @override
  Future<MiniAVVideoInfo> getConfiguredFormat() async {
    _ensureNotDestroyed();

    final formatOutPtr = calloc<bindings.MiniAVVideoInfo>();
    try {
      final result = bindings.MiniAV_Camera_GetConfiguredFormat(
        _context!,
        formatOutPtr,
      );
      if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw Exception(
          'Failed to get configured camera format: ${result.name}',
        );
      }
      return VideoFormatInfoFFIToPlatform.fromNative(
        formatOutPtr.ref,
      ).toPlatformType();
    } finally {
      calloc.free(formatOutPtr);
    }
  }

  @override
  Future<void> startCapture(
    void Function(MiniAVBuffer buffer, Object? userData) onFrame, {
    Object? userData,
  }) async {
    _ensureNotDestroyed();

    await stopCapture(); // Clean up any previous callback

    void ffiCallback(
      ffi.Pointer<bindings.MiniAVBuffer> buffer,
      ffi.Pointer<ffi.Void> cbUserData,
    ) {
      // Check if context was destroyed during callback
      if (_isDestroyed) {
        return; // Silently ignore if destroyed
      }

      final platformBuffer = MiniAVBufferFFI.fromPointer(buffer);
      try {
        onFrame(platformBuffer, userData);
      } catch (e, s) {
        print('Error in camera user callback: $e\n$s');
      }
    }

    _callbackHandle =
        ffi.NativeCallable<bindings.MiniAVBufferCallbackFunction>.listener(
          ffiCallback,
        );

    final result = bindings.MiniAV_Camera_StartCapture(
      _context!,
      _callbackHandle!.nativeFunction,
      ffi.nullptr,
    );

    if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
      await _cleanupCallback();
      throw Exception('Failed to start camera capture: ${result.name}');
    }
  }

  Future<void> _cleanupCallback() async {
    _callbackHandle?.close();
    _callbackHandle = null;
  }

  @override
  Future<void> stopCapture() async {
    // Don't throw if context is destroyed - just clean up Dart resources
    if (_isDestroyed || _context == null) {
      await _cleanupCallback();
      return;
    }

    // Don't throw if already stopped - this is idempotent
    if (_callbackHandle == null) {
      return; // Already stopped
    }

    final result = bindings.MiniAV_Camera_StopCapture(_context!);

    await _cleanupCallback();

    // Only warn on unexpected errors, not "already stopped" errors
    if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS &&
        result != bindings.MiniAVResultCode.MINIAV_ERROR_NOT_RUNNING) {
      print('Warning: MiniAV_Camera_StopCapture failed: ${result.name}');
    }
  }

  @override
  Future<void> destroy() async {
    // Idempotent - can be called multiple times safely
    if (_isDestroyed) {
      return; // Already destroyed
    }

    _isDestroyed = true; // Mark as destroyed first to prevent new operations

    await stopCapture(); // Stop capture if running

    if (_context != null) {
      _finalizer.detach(this); // Prevent finalizer from running
      final result = bindings.MiniAV_Camera_DestroyContext(_context!);
      _context = null; // Clear the handle

      if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw Exception('Failed to destroy camera context: ${result.name}');
      }
    }
  }
}
