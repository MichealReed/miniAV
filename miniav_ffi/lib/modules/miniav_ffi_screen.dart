import 'package:miniav_platform_interface/miniav_platform_interface.dart';
import '../miniav_ffi_types.dart';
import '../miniav_ffi_bindings.dart' as bindings;
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

class MiniFFIScreenPlatform implements MiniScreenPlatformInterface {
  @override
  Future<List<MiniAVDeviceInfo>> enumerateDisplays() async {
    final displaysPtrPtr = calloc<ffi.Pointer<bindings.MiniAVDeviceInfo>>();
    final countPtr = calloc<ffi.Uint32>();
    try {
      final result = bindings.MiniAV_Screen_EnumerateDisplays(
        displaysPtrPtr,
        countPtr,
      );
      if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw Exception('Failed to enumerate displays: ${result.name}');
      }
      final displaysArrayPtr = displaysPtrPtr.value;
      final count = countPtr.value;
      if (displaysArrayPtr == ffi.nullptr || count == 0) {
        return <MiniAVDeviceInfo>[];
      }
      final displayList = <MiniAVDeviceInfo>[];
      for (int i = 0; i < count; i++) {
        final ffiDevice = (displaysArrayPtr + i).ref;
        displayList.add(
          DeviceInfoFFIToPlatform.fromNative(ffiDevice).toPlatformType(),
        );
      }
      bindings.MiniAV_FreeDeviceList(displaysArrayPtr, count);
      return displayList;
    } finally {
      calloc.free(displaysPtrPtr);
      calloc.free(countPtr);
    }
  }

  @override
  Future<List<MiniAVDeviceInfo>> enumerateWindows() async {
    final windowsPtrPtr = calloc<ffi.Pointer<bindings.MiniAVDeviceInfo>>();
    final countPtr = calloc<ffi.Uint32>();
    try {
      final result = bindings.MiniAV_Screen_EnumerateWindows(
        windowsPtrPtr,
        countPtr,
      );
      if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw Exception('Failed to enumerate windows: ${result.name}');
      }
      final windowsArrayPtr = windowsPtrPtr.value;
      final count = countPtr.value;
      if (windowsArrayPtr == ffi.nullptr || count == 0) {
        return <MiniAVDeviceInfo>[];
      }
      final windowList = <MiniAVDeviceInfo>[];
      for (int i = 0; i < count; i++) {
        final ffiDevice = (windowsArrayPtr + i).ref;
        windowList.add(
          DeviceInfoFFIToPlatform.fromNative(ffiDevice).toPlatformType(),
        );
      }
      bindings.MiniAV_FreeDeviceList(windowsArrayPtr, count);
      return windowList;
    } finally {
      calloc.free(windowsPtrPtr);
      calloc.free(countPtr);
    }
  }

  @override
  Future<ScreenFormatDefaults> getDefaultFormats(String displayId) async {
    final displayIdPtr = displayId.toNativeUtf8();
    final videoFormatOutPtr = calloc<bindings.MiniAVVideoInfo>();
    final audioFormatOutPtr = calloc<bindings.MiniAVAudioInfo>();

    try {
      final result = bindings.MiniAV_Screen_GetDefaultFormats(
        displayIdPtr.cast<ffi.Char>(),
        videoFormatOutPtr,
        audioFormatOutPtr,
      );

      if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw Exception(
          'Failed to get default formats for display $displayId: ${result.name}',
        );
      }

      final videoFormat = VideoFormatInfoFFIToPlatform.fromNative(
        videoFormatOutPtr.ref,
      ).toPlatformType();
      // Audio might not be supported or returned, check for zeroed struct or specific values if needed
      final audioFormat = AudioInfoFFIToPlatform.fromNative(
        audioFormatOutPtr.ref,
      ).toPlatformType();

      // Determine if audioFormat is valid (e.g. sampleRate > 0 or format != UNKNOWN)
      // For simplicity, we'll assume if C API returns success, audioFormat might be valid or zeroed.
      // A more robust check would be to see if audioFormat.sampleRate > 0 or similar.
      final bool isAudioFormatValid =
          audioFormat.sampleRate > 0 && audioFormat.channels > 0;

      return (videoFormat, isAudioFormatValid ? audioFormat : null);
    } finally {
      calloc.free(displayIdPtr);
      calloc.free(videoFormatOutPtr);
      calloc.free(audioFormatOutPtr);
    }
  }

  @override
  Future<MiniScreenContextPlatformInterface> createContext() async {
    final contextPtr = calloc<bindings.MiniAVScreenContextHandle>();
    try {
      final result = bindings.MiniAV_Screen_CreateContext(contextPtr);
      if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw Exception('Failed to create screen context: ${result.name}');
      }
      return MiniFFIScreenContext(contextPtr.value);
    } finally {
      calloc.free(contextPtr);
    }
  }
}

class MiniFFIScreenContext implements MiniScreenContextPlatformInterface {
  bindings.MiniAVScreenContextHandle? _context;
  ffi.NativeCallable<bindings.MiniAVBufferCallbackFunction>? _callbackHandle;
  bool _isDestroyed = false;
  late final Finalizer<bindings.MiniAVScreenContextHandle> _finalizer;

  MiniFFIScreenContext(bindings.MiniAVScreenContextHandle context)
    : _context = context {
    // Auto-cleanup if destroy() is never called
    _finalizer = Finalizer<bindings.MiniAVScreenContextHandle>((handle) {
      print(
        'Warning: ScreenContext was garbage collected without calling destroy()',
      );
      bindings.MiniAV_Screen_DestroyContext(handle);
    });
    _finalizer.attach(this, context, detach: this);
  }

  /// Throws if the context has been destroyed
  void _ensureNotDestroyed() {
    if (_isDestroyed || _context == null) {
      throw StateError(
        'ScreenContext has been destroyed. Create a new context to continue using screen capture.',
      );
    }
  }

  /// Whether this context has been destroyed
  bool get isDestroyed => _isDestroyed;

  @override
  Future<void> configureDisplay(
    String displayId,
    MiniAVVideoInfo format, {
    bool captureAudio = false,
  }) async {
    _ensureNotDestroyed();

    final displayIdPtr = displayId.toNativeUtf8();
    final nativeFormatPtr = calloc<bindings.MiniAVVideoInfo>();
    try {
      VideoFormatInfoFFIToPlatform.copyToNative(format, nativeFormatPtr.ref);
      final result = bindings.MiniAV_Screen_ConfigureDisplay(
        _context!,
        displayIdPtr.cast(),
        nativeFormatPtr,
        captureAudio,
      );
      if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw Exception('Failed to configure display: ${result.name}');
      }
    } finally {
      calloc.free(displayIdPtr);
      calloc.free(nativeFormatPtr);
    }
  }

  @override
  Future<void> configureWindow(
    String windowId,
    MiniAVVideoInfo format, {
    bool captureAudio = false,
  }) async {
    _ensureNotDestroyed();

    final windowIdPtr = windowId.toNativeUtf8();
    final nativeFormatPtr = calloc<bindings.MiniAVVideoInfo>();
    try {
      VideoFormatInfoFFIToPlatform.copyToNative(format, nativeFormatPtr.ref);
      final result = bindings.MiniAV_Screen_ConfigureWindow(
        _context!,
        windowIdPtr.cast(),
        nativeFormatPtr,
        captureAudio,
      );
      if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw Exception('Failed to configure window: ${result.name}');
      }
    } finally {
      calloc.free(windowIdPtr);
      calloc.free(nativeFormatPtr);
    }
  }

  @override
  Future<ScreenFormatDefaults> getConfiguredFormats() async {
    _ensureNotDestroyed();

    final videoFormatOutPtr = calloc<bindings.MiniAVVideoInfo>();
    final audioFormatOutPtr = calloc<bindings.MiniAVAudioInfo>();
    try {
      final result = bindings.MiniAV_Screen_GetConfiguredFormats(
        _context!.cast(),
        videoFormatOutPtr,
        audioFormatOutPtr,
      );
      if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw Exception(
          'Failed to get configured screen formats: ${result.name}',
        );
      }
      final videoFormat = VideoFormatInfoFFIToPlatform.fromNative(
        videoFormatOutPtr.ref,
      ).toPlatformType();
      final audioFormat = AudioInfoFFIToPlatform.fromNative(
        audioFormatOutPtr.ref,
      ).toPlatformType();

      final bool isAudioFormatValid =
          audioFormat.sampleRate > 0 && audioFormat.channels > 0;

      return (videoFormat, isAudioFormatValid ? audioFormat : null);
    } finally {
      calloc.free(videoFormatOutPtr);
      calloc.free(audioFormatOutPtr);
    }
  }

  @override
  Future<void> startCapture(
    void Function(MiniAVBuffer buffer, Object? userData) onFrame, {
    Object? userData,
  }) async {
    _ensureNotDestroyed();

    await stopCapture(); // Ensure any previous capture is stopped

    void ffiCallback(
      ffi.Pointer<bindings.MiniAVBuffer> bufferPtr,
      ffi.Pointer<ffi.Void> cbUserData,
    ) {
      // Check if context was destroyed during callback
      if (_isDestroyed) {
        return; // Silently ignore if destroyed
      }

      // Important: Check if bufferPtr is not null before dereferencing
      if (bufferPtr == ffi.nullptr) {
        print("FFI Callback received null buffer pointer");
        return;
      }

      final platformBuffer = MiniAVBufferFFI.fromPointer(bufferPtr);
      try {
        onFrame(platformBuffer, userData);
      } catch (e, s) {
        print('Error in screen capture user callback: $e\n$s');
      }
    }

    _callbackHandle =
        ffi.NativeCallable<bindings.MiniAVBufferCallbackFunction>.listener(
          ffiCallback,
        );

    final result = bindings.MiniAV_Screen_StartCapture(
      _context!,
      _callbackHandle!.nativeFunction,
      ffi.nullptr,
    );

    if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
      await _cleanupCallback();
      throw Exception('Failed to start screen capture: ${result.name}');
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

    final result = bindings.MiniAV_Screen_StopCapture(_context!);

    await _cleanupCallback();

    // Only warn on unexpected errors, not "already stopped" errors
    if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS &&
        result != bindings.MiniAVResultCode.MINIAV_ERROR_NOT_RUNNING) {
      print('Warning: MiniAV_Screen_StopCapture failed: ${result.name}');
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
      final result = bindings.MiniAV_Screen_DestroyContext(_context!);
      _context = null; // Clear the handle

      if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw Exception('Failed to destroy screen context: ${result.name}');
      }
    }
  }
}
