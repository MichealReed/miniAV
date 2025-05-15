import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'miniav_ffi_bindings.dart' as bindings;

// Helper function to convert ffi.Array<ffi.Char> to String
String _charArrayToString(ffi.Array<ffi.Char> array, int maxLength) {
  final sb = StringBuffer();
  for (int i = 0; i < maxLength; ++i) {
    final charCode = array[i];
    if (charCode == 0) break; // Null terminator
    sb.writeCharCode(charCode);
  }
  return sb.toString();
}

/// Dart representation of MiniAVDeviceInfo.
class DeviceInfo {
  final String deviceId;
  final String name;
  final bool isDefault;

  DeviceInfo({
    required this.deviceId,
    required this.name,
    required this.isDefault,
  });

  factory DeviceInfo.fromNative(bindings.MiniAVDeviceInfo nativeInfo) {
    return DeviceInfo(
      deviceId: _charArrayToString(
        nativeInfo.device_id,
        bindings.MINIAV_DEVICE_ID_MAX_LEN,
      ),
      name: _charArrayToString(
        nativeInfo.name,
        bindings.MINIAV_DEVICE_NAME_MAX_LEN,
      ),
      isDefault: nativeInfo.is_default,
    );
  }

  @override
  String toString() =>
      'DeviceInfo(deviceId: $deviceId, name: $name, isDefault: $isDefault)';
}

/// Dart representation of MiniAVVideoFormatInfo.
class VideoFormatInfo {
  final int width;
  final int height;
  final bindings.MiniAVPixelFormat pixelFormat;
  final int frameRateNumerator;
  final int frameRateDenominator;
  final bindings.MiniAVOutputPreference outputPreference;

  VideoFormatInfo({
    required this.width,
    required this.height,
    required this.pixelFormat,
    required this.frameRateNumerator,
    required this.frameRateDenominator,
    required this.outputPreference,
  });

  factory VideoFormatInfo.fromNative(
    bindings.MiniAVVideoFormatInfo nativeInfo,
  ) {
    return VideoFormatInfo(
      width: nativeInfo.width,
      height: nativeInfo.height,
      pixelFormat: nativeInfo.pixel_format, // Uses the getter from bindings
      frameRateNumerator: nativeInfo.frame_rate_numerator,
      frameRateDenominator: nativeInfo.frame_rate_denominator,
      outputPreference:
          nativeInfo.output_preference, // Uses the getter from bindings
    );
  }

  @override
  String toString() =>
      'VideoFormatInfo(width: $width, height: $height, pixelFormat: ${pixelFormat.name}, frameRate: $frameRateNumerator/$frameRateDenominator, preference: ${outputPreference.name})';
}

/// Exception class for MiniAV errors.
class MiniAVException implements Exception {
  final String message;
  final bindings.MiniAVResultCode resultCode;

  MiniAVException(this.message, this.resultCode);

  @override
  String toString() {
    // Attempt to get a more descriptive error message from the library itself.
    // This assumes MiniAV is initialized enough to call getErrorString.
    // If MiniAV itself failed to initialize, this might not be feasible or might throw another error.
    // A safer approach might be to have a static, initialized MiniAV instance for this,
    // or to simply not call getErrorString here if the library state is uncertain.
    String errorDescription;
    try {
      // Ensure the library is loaded before trying to get an error string.
      // This is a simplified approach; a more robust solution might involve
      // checking if the library is loaded or having a dedicated, initialized
      // MiniAV instance for utility functions like this.
      // For now, we'll assume getErrorString can be called.
      final tempMiniAV =
          MiniAV(); // Creates an instance, which should load the library
      errorDescription = tempMiniAV.getErrorString(resultCode);
    } catch (e) {
      errorDescription =
          "Unable to retrieve detailed error string from native library.";
    }
    return 'MiniAVException: $message (Code: ${resultCode.name} [${resultCode.value}]) - $errorDescription';
  }
}

typedef UserDartMiniAVLogCallbackFunction =
    void Function(
      bindings.MiniAVLogLevel level,
      String message, // Expects a Dart String
      ffi.Pointer<ffi.Void> userData,
    );

class MiniAV {
  // For Log Callback
  ffi.NativeCallable<bindings.MiniAVLogCallbackFunction>? _logCallbackCallable;
  ReceivePort? _logReceivePort;
  StreamSubscription<dynamic>? _logStreamSubscription;
  UserDartMiniAVLogCallbackFunction? _userLogCallback;

  // For Camera Buffer Callback
  // Corrected type here to match the typedef from bindings.dart
  ffi.NativeCallable<bindings.MiniAVBufferCallbackFunction>?
  _cameraBufferCallbackCallable;
  ReceivePort? _cameraReceivePort;
  StreamSubscription<dynamic>? _cameraStreamSubscription;
  bindings.DartMiniAVBufferCallbackFunction? _userCameraCallback;

  MiniAV() {
    // Initialize the library, if necessary.
    // For now, we assume the dynamic library is loaded when functions are called.
    // _bindings = bindings.MiniAVFFIBindings(ffi.DynamicLibrary.open(_getLibraryPath())); // Remove this
    // Ensure the library is loaded. We can do this once, perhaps lazily.
  }

  void dispose() {
    // Cleanup log callback resources
    _logStreamSubscription?.cancel();
    _logReceivePort?.close();
    _logCallbackCallable?.close();
    _logStreamSubscription = null;
    _logReceivePort = null;
    _logCallbackCallable = null;
    _userLogCallback = null;

    // Cleanup camera callback resources
    _cameraStreamSubscription?.cancel();
    _cameraReceivePort?.close();
    _cameraBufferCallbackCallable?.close();
    _cameraStreamSubscription = null;
    _cameraReceivePort = null;
    _cameraBufferCallbackCallable = null;
    _userCameraCallback = null;
  }

  /// Gets the version of the MiniAV library.
  ({int major, int minor, int patch}) getVersion() {
    final majorPtr = calloc<ffi.Uint32>();
    final minorPtr = calloc<ffi.Uint32>();
    final patchPtr = calloc<ffi.Uint32>();

    try {
      // Call the top-level binding function
      final result = bindings.MiniAV_GetVersion(majorPtr, minorPtr, patchPtr);
      if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw MiniAVException('Failed to get version', result);
      }
      return (
        major: majorPtr.value,
        minor: minorPtr.value,
        patch: patchPtr.value,
      );
    } finally {
      calloc.free(majorPtr);
      calloc.free(minorPtr);
      calloc.free(patchPtr);
    }
  }

  /// Gets the version string of the MiniAV library.
  String getVersionString() {
    // Call the top-level binding function
    final ptr = bindings.MiniAV_GetVersionString();
    if (ptr == ffi.nullptr) {
      return "Unknown Version (null pointer returned)";
    }
    return ptr.cast<Utf8>().toDartString();
  }

  /// Releases a buffer previously obtained from a callback.
  void releaseBuffer(ffi.Pointer<bindings.MiniAVBuffer> buffer) {
    if (buffer.ref.internal_handle == ffi.nullptr) {
      return;
    }
    final result = bindings.MiniAV_ReleaseBuffer(buffer.ref.internal_handle);
    if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
      throw MiniAVException('Failed to release buffer', result);
    }
  }

  /// Frees memory allocated by MiniAV (e.g., for device lists or format lists if not handled by specific free functions).
  /// Use with caution, prefer specific free functions like freeDeviceList when available.
  void free(ffi.Pointer<ffi.Void> ptr) {
    final result = bindings.MiniAV_Free(ptr);
    if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
      throw MiniAVException('Failed to free memory', result);
    }
  }

  /// Frees a list of MiniAVDeviceInfo structures.
  /// This is typically called internally by enumeration methods that return Dart lists.
  void _freeDeviceList(
    ffi.Pointer<bindings.MiniAVDeviceInfo> devices,
    int count,
  ) {
    final result = bindings.MiniAV_FreeDeviceList(devices, count);
    if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
      // Log or handle error, but might not always want to throw from a free function
      // depending on context, as it could mask a primary error.
      // For now, we'll throw as it indicates a problem with the free operation itself.
      throw MiniAVException('Failed to free device list', result);
    }
  }

  /// Frees a list of format structures.
  /// This is typically called internally by getSupportedFormats methods.
  /// The `formats` pointer is void* because the actual format type varies (video, audio).
  void _freeFormatList(ffi.Pointer<ffi.Void> formats, int count) {
    final result = bindings.MiniAV_FreeFormatList(formats, count);
    if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
      // Similar to _freeDeviceList, consider error handling strategy.
      throw MiniAVException('Failed to free format list', result);
    }
  }

  /// Sets the log callback function.
  void setLogCallback(
    UserDartMiniAVLogCallbackFunction dartCallback, {
    ffi.Pointer<ffi.Void>? userData,
  }) {}

  /// Sets the log level.
  void setLogLevel(bindings.MiniAVLogLevel level) {
    // Call the top-level binding function
    final result = bindings.MiniAV_SetLogLevel(level);
    if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
      throw MiniAVException('Failed to set log level', result);
    }
  }

  /// Gets the error string for a given result code.
  String getErrorString(bindings.MiniAVResultCode code) {
    // Call the top-level binding function
    final ptr = bindings.MiniAV_GetErrorString(code);
    if (ptr == ffi.nullptr) {
      return "Unknown error or null pointer for error string";
    }
    return ptr.cast<Utf8>().toDartString();
  }

  // --- Camera Functions ---

  /// Enumerates available camera devices.
  List<DeviceInfo> cameraEnumerateDevices() {
    final devicesPtrPtr = calloc<ffi.Pointer<bindings.MiniAVDeviceInfo>>();
    final countPtr = calloc<ffi.Uint32>();

    try {
      final result = bindings.MiniAV_Camera_EnumerateDevices(
        devicesPtrPtr,
        countPtr,
      );
      if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw MiniAVException('Failed to enumerate camera devices', result);
      }

      final devicesArrayPtr = devicesPtrPtr.value;
      final count = countPtr.value;

      if (devicesArrayPtr == ffi.nullptr || count == 0) {
        return [];
      }

      final deviceList = <DeviceInfo>[];
      for (int i = 0; i < count; i++) {
        deviceList.add(DeviceInfo.fromNative((devicesArrayPtr + i).ref));
      }

      _freeDeviceList(devicesArrayPtr, count); // Free the native list

      return deviceList;
    } finally {
      calloc.free(devicesPtrPtr);
      calloc.free(countPtr);
    }
  }

  /// Gets supported video formats for a given camera device.
  List<VideoFormatInfo> cameraGetSupportedFormats(String deviceId) {
    final deviceIdPtr = deviceId.toNativeUtf8();
    final outParamPointerToFormatArray =
        calloc<ffi.Pointer<bindings.MiniAVVideoFormatInfo>>();

    final countPtr = calloc<ffi.Uint32>();

    try {
      final result = bindings.MiniAV_Camera_GetSupportedFormats(
        deviceIdPtr.cast(),
        outParamPointerToFormatArray,
        countPtr,
      );
      if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw MiniAVException(
          'Failed to get camera supported formats for $deviceId',
          result,
        );
      }

      final ffi.Pointer<bindings.MiniAVVideoFormatInfo> firstStructPtr =
          outParamPointerToFormatArray.value;
      final count = countPtr.value;

      if (firstStructPtr == ffi.nullptr || count == 0) {
        // Important: If C returned a valid pointer but count is 0,
        // we still need to free firstStructPtr if it's not null.
        // The _freeFormatList function should handle nullptr gracefully.
        if (firstStructPtr != ffi.nullptr) {
          _freeFormatList(firstStructPtr.cast<ffi.Void>(), count);
        }
        return [];
      }

      final formatList = <VideoFormatInfo>[];
      for (int i = 0; i < count; i++) {
        // Perform pointer arithmetic to get the i-th struct from the array
        // and then dereference it with .ref.
        final bindings.MiniAVVideoFormatInfo currentNativeStruct =
            (firstStructPtr + i).ref;
        formatList.add(VideoFormatInfo.fromNative(currentNativeStruct));
      }

      // Free the entire array of structs allocated by C.
      // MiniAV_FreeFormatList expects a void* (which is the MiniAVVideoFormatInfo*) and count.
      _freeFormatList(firstStructPtr.cast<ffi.Void>(), count);
      return formatList;
    } finally {
      calloc.free(deviceIdPtr);
      calloc.free(outParamPointerToFormatArray);
      calloc.free(countPtr);
    }
  }

  /// Creates a camera capture context.
  bindings.MiniAVCameraContextHandle cameraCreateContext() {
    final contextPtr = calloc<bindings.MiniAVCameraContextHandle>();
    try {
      final result = bindings.MiniAV_Camera_CreateContext(contextPtr);
      if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw MiniAVException('Failed to create camera context', result);
      }
      return contextPtr.value;
    } finally {
      calloc.free(contextPtr);
    }
  }

  /// Destroys a camera capture context.
  void cameraDestroyContext(bindings.MiniAVCameraContextHandle context) {
    if (context == ffi.nullptr) return;
    final result = bindings.MiniAV_Camera_DestroyContext(context);
    if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
      throw MiniAVException('Failed to destroy camera context', result);
    }
  }

  /// Configures a camera capture context.
  /// The `format` should be a pointer to a `MiniAVVideoFormatInfo` struct.
  /// For simplicity, this wrapper expects a `VideoFormatInfo` Dart object and converts it.
  /// A more direct mapping would take `ffi.Pointer<bindings.MiniAVVideoFormatInfo>`.
  void cameraConfigure(
    bindings.MiniAVCameraContextHandle context,
    String deviceId,
    VideoFormatInfo format,
  ) {
    final deviceIdPtr = deviceId.toNativeUtf8();
    // Allocate and populate the native format struct
    final nativeFormatPtr = calloc<bindings.MiniAVVideoFormatInfo>();
    nativeFormatPtr.ref.width = format.width;
    nativeFormatPtr.ref.height = format.height;
    nativeFormatPtr.ref.pixel_formatAsInt =
        format.pixelFormat.value; // Use value for enum
    nativeFormatPtr.ref.frame_rate_numerator = format.frameRateNumerator;
    nativeFormatPtr.ref.frame_rate_denominator = format.frameRateDenominator;
    nativeFormatPtr.ref.output_preferenceAsInt =
        format.outputPreference.value; // Use value for enum

    try {
      final result = bindings.MiniAV_Camera_Configure(
        context,
        deviceIdPtr.cast(),
        nativeFormatPtr.cast(),
      );
      if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
        throw MiniAVException('Failed to configure camera', result);
      }
    } finally {
      calloc.free(deviceIdPtr);
      calloc.free(nativeFormatPtr);
    }
  }

  /// Starts camera capture.
  ///
  /// [context] The camera context handle.
  /// [dartCallback] The Dart function to call when a buffer is received.
  /// [userData] Optional user data to pass to the callback.
  void cameraStartCapture(
    bindings.MiniAVCameraContextHandle context,
    bindings.DartMiniAVBufferCallbackFunction dartCallback, {
    ffi.Pointer<ffi.Void>? userData,
  }) {
    if (context == ffi.nullptr) {
      throw ArgumentError.value(context, 'context', 'Context cannot be null.');
    }

    _cameraStreamSubscription?.cancel();
    _cameraReceivePort?.close();
    _cameraBufferCallbackCallable?.close();
    _userCameraCallback = null;

    _userCameraCallback = dartCallback;
    _cameraReceivePort = ReceivePort();
    final sendPort = _cameraReceivePort!.sendPort;

    // This is the function that C will call. It runs in a native thread context.
    // Its only job is to send a message (containing pointer addresses) to the SendPort.
    // The signature of this Dart function must match MiniAVBufferCallbackFunction
    void nativeBufferCallbackEntry(
      ffi.Pointer<bindings.MiniAVBuffer> nativeBuffer,
      ffi.Pointer<ffi.Void> cbUserDataFromC,
    ) {
      sendPort.send([nativeBuffer.address, cbUserDataFromC.address]);
    }

    // Use NativeCallable.listener with the correct FFI function signature typedef
    _cameraBufferCallbackCallable =
        ffi.NativeCallable<bindings.MiniAVBufferCallbackFunction>.listener(
          nativeBufferCallbackEntry,
        );

    _cameraStreamSubscription = _cameraReceivePort!.listen((message) {
      if (_userCameraCallback == null) return;

      final List<dynamic> msgList = message as List<dynamic>;
      final bufferAddress = msgList[0] as int;
      final cbUserDataAddress = msgList[1] as int;

      final bufferPtr = ffi.Pointer<bindings.MiniAVBuffer>.fromAddress(
        bufferAddress,
      );
      final cbUserDataPtr = ffi.Pointer<ffi.Void>.fromAddress(
        cbUserDataAddress,
      );

      _userCameraCallback!(bufferPtr, cbUserDataPtr);
    });

    final result = bindings.MiniAV_Camera_StartCapture(
      context,
      // Pass the nativeFunction pointer from the NativeCallable
      _cameraBufferCallbackCallable!.nativeFunction,
      userData ?? ffi.nullptr,
    );

    if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
      _cameraStreamSubscription?.cancel();
      _cameraReceivePort?.close();
      _cameraBufferCallbackCallable!.close();
      _cameraStreamSubscription = null;
      _cameraReceivePort = null;
      _cameraBufferCallbackCallable = null;
      _userCameraCallback = null;
      throw MiniAVException('Failed to start camera capture', result);
    }
  }

  /// Stops camera capture.
  ///
  /// [context] The camera context handle.
  void cameraStopCapture(bindings.MiniAVCameraContextHandle context) {
    if (context == ffi.nullptr) {
      return;
    }

    final result = bindings.MiniAV_Camera_StopCapture(context);

    // Clean up resources associated with the callback for this instance
    _cameraStreamSubscription?.cancel();
    _cameraReceivePort?.close();
    _cameraBufferCallbackCallable
        ?.close(); // Important: close the NativeCallable

    _cameraStreamSubscription = null;
    _cameraReceivePort = null;
    _cameraBufferCallbackCallable = null;
    _userCameraCallback = null;

    if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
      throw MiniAVException('Failed to stop camera capture', result);
    }
  }
}
