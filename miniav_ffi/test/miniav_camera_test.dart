import 'dart:async';
import 'dart:ffi';
import 'package:test/test.dart';
import 'package:miniav_ffi/miniav_ffi.dart';
import 'package:miniav_ffi/miniav_ffi_bindings.dart' as bindings;

late MiniAV miniAV;

void main() {
  setUpAll(() {
    miniAV = MiniAV();
    print('MiniAV Test Setup Complete. Version: ${miniAV.getVersionString()}');
  });

  group('MiniAV Camera Tests', () {
    test('Enumerate Camera Devices', () {
      try {
        final devices = miniAV.cameraEnumerateDevices();
        expect(devices, isA<List<DeviceInfo>>());
        print('Found ${devices.length} camera devices:');
        for (final device in devices) {
          print(
            '- ID: ${device.deviceId}, Name: ${device.name}, Default: ${device.isDefault}',
          );
          expect(device.deviceId, isNotEmpty);
          expect(device.name, isNotEmpty);
        }
        // Add more specific expectations if you know what to expect
        // e.g., expect(devices, isNotEmpty); if you know a camera should be present.
      } on MiniAVException catch (e) {
        fail('cameraEnumerateDevices failed: $e');
      }
    });

    test('Get Supported Camera Formats (for the first available camera)', () {
      List<DeviceInfo> devices;
      try {
        devices = miniAV.cameraEnumerateDevices();
      } on MiniAVException catch (e) {
        markTestSkipped(
          'Skipping format test: Failed to enumerate devices - $e',
        );
        return;
      }

      if (devices.isEmpty) {
        markTestSkipped(
          'Skipping format test: No camera devices found to get formats from.',
        );
        return;
      }

      // Test with the first available device
      final firstDevice = devices.first;
      print(
        'Attempting to get formats for device: ${firstDevice.name} (${firstDevice.deviceId})',
      );

      try {
        final formats = miniAV.cameraGetSupportedFormats(firstDevice.deviceId);

        expect(formats, isA<List<VideoFormatInfo>>());
        print('Found ${formats.length} formats for ${firstDevice.name}:');
        for (final format in formats) {
          print(
            '- ${format.width}x${format.height} @ ${format.frameRateNumerator}/${format.frameRateDenominator}fps, PixelFormat: ${format.pixelFormat.name}, Preference: ${format.outputPreference.name}',
          );
          expect(format.width, greaterThan(0));
          expect(format.height, greaterThan(0));
        }
        // Add more specific expectations if you know what to expect
        // e.g., expect(formats, isNotEmpty); if the camera should have formats.
      } on MiniAVException catch (e) {
        fail(
          'cameraGetSupportedFormats for device ${firstDevice.deviceId} failed: $e',
        );
      }
    });

    test('Create and Destroy Camera Context', () {
      bindings.MiniAVCameraContextHandle? contextHandle;
      try {
        contextHandle = miniAV.cameraCreateContext();
        expect(contextHandle, isNotNull);
        expect(contextHandle, isNot(nullptr));
        print('Camera context created: $contextHandle');
      } on MiniAVException catch (e) {
        fail('cameraCreateContext failed: $e');
      } finally {
        if (contextHandle != null && contextHandle != nullptr) {
          try {
            miniAV.cameraDestroyContext(contextHandle);
            print('Camera context destroyed: $contextHandle');
          } on MiniAVException catch (e) {
            fail('cameraDestroyContext failed: $e');
          }
        }
      }
    });

    test('Configure Camera Context (for the first available camera and format)', () {
      List<DeviceInfo> devices;
      try {
        devices = miniAV.cameraEnumerateDevices();
      } on MiniAVException catch (e) {
        markTestSkipped(
          'Skipping configure test: Failed to enumerate devices - $e',
        );
        return;
      }

      if (devices.isEmpty) {
        markTestSkipped('Skipping configure test: No camera devices found.');
        return;
      }
      final firstDevice = devices.first;

      List<VideoFormatInfo> formats;
      try {
        formats = miniAV.cameraGetSupportedFormats(firstDevice.deviceId);
      } on MiniAVException catch (e) {
        markTestSkipped(
          'Skipping configure test: Failed to get formats for device ${firstDevice.deviceId} - $e',
        );
        return;
      }

      if (formats.isEmpty) {
        markTestSkipped(
          'Skipping configure test: No formats found for device ${firstDevice.deviceId}.',
        );
        return;
      }
      final firstFormat = formats.first;

      print(firstFormat.toString());

      bindings.MiniAVCameraContextHandle? contextHandle;
      try {
        contextHandle = miniAV.cameraCreateContext();
        expect(contextHandle, isNotNull);
        expect(contextHandle, isNot(nullptr));

        print(
          'Configuring camera ${firstDevice.name} with format ${firstFormat.width}x${firstFormat.height}',
        );
        miniAV.cameraConfigure(
          contextHandle,
          firstDevice.deviceId,
          firstFormat,
        );
        print('Camera configured successfully.');
        // Add expectations here if configure has observable side effects or returns info
      } on MiniAVException catch (e) {
        fail(
          'Camera configure test failed for device ${firstDevice.deviceId} with format ${firstFormat.toString()}: $e',
        );
      } finally {
        if (contextHandle != null && contextHandle != nullptr) {
          miniAV.cameraDestroyContext(contextHandle);
        }
      }
    });
    test('Start and Stop Camera Capture (receives at least one frame)', () async {
      miniAV.setLogCallback((level, message, userData) {
        print('[MiniAV Test Log - $level]: $message');
      });
      miniAV.setLogLevel(bindings.MiniAVLogLevel.MINIAV_LOG_LEVEL_DEBUG);
      List<DeviceInfo> devices;
      try {
        devices = miniAV.cameraEnumerateDevices();
      } on MiniAVException catch (e) {
        markTestSkipped(
          'Skipping capture test: Failed to enumerate devices - $e',
        );
        return;
      }

      if (devices.isEmpty) {
        markTestSkipped('Skipping capture test: No camera devices found.');
        return;
      }
      final firstDevice = devices.first;

      List<VideoFormatInfo> formats;
      try {
        formats = miniAV.cameraGetSupportedFormats(firstDevice.deviceId);
      } on MiniAVException catch (e) {
        markTestSkipped(
          'Skipping capture test: Failed to get formats for ${firstDevice.deviceId} - $e',
        );
        return;
      }

      if (formats.isEmpty) {
        markTestSkipped(
          'Skipping capture test: No formats found for ${firstDevice.deviceId}.',
        );
        return;
      }
      // Try to find a common format, otherwise use the first available
      final formatToTest = formats.firstWhere(
        (f) => f.width == 640 && f.height == 480,
        orElse: () => formats.first,
      );
      print(
        'Selected format for capture test: ${formatToTest.width}x${formatToTest.height} @ ${formatToTest.frameRateNumerator}/${formatToTest.frameRateDenominator}fps, PixelFormat: ${formatToTest.pixelFormat.name}',
      );

      bindings.MiniAVCameraContextHandle? contextHandle;
      final frameReceivedCompleter = Completer<void>();
      int frameCount = 0;

      try {
        contextHandle = miniAV.cameraCreateContext();
        miniAV.cameraConfigure(
          contextHandle,
          firstDevice.deviceId,
          formatToTest,
        );
        print('Camera configured for capture test.');

        // Define the Dart callback that matches MiniAVBufferCallback
        // This function will be passed to miniAV.cameraStartCapture
        void myDartBufferCallback(
          Pointer<bindings.MiniAVBuffer> bufferPtr,
          Pointer<Void> userData, // userData passed from cameraStartCapture
        ) {
          if (bufferPtr == nullptr) {
            print('[Test Callback] Received NULL buffer pointer!');
            if (!frameReceivedCompleter.isCompleted) {
              frameReceivedCompleter.completeError(
                StateError('Received NULL buffer pointer from native code.'),
              );
            }
            return;
          }
          final buffer = bufferPtr.ref;

          frameCount++;
          print(
            '[Test Callback] Frame received! Count: $frameCount, Type: ${buffer.type.name}, TS: ${buffer.timestamp_us}, Size: ${buffer.data_size_bytes}',
          );

          if (buffer.type ==
              bindings.MiniAVBufferType.MINIAV_BUFFER_TYPE_VIDEO) {
            print(
              '  Video: ${buffer.data.video.width}x${buffer.data.video.height}, PixFmt: ${buffer.data.video.pixel_format.name}, Stride0: ${buffer.data.video.stride_bytes[0]}',
            );
          }

          // IMPORTANT: Release the buffer using its internal_handle
          // Assuming miniAV.releaseBuffer takes the internal_handle directly
          if (buffer.internal_handle != nullptr) {
            try {
              // Pass the whole buffer pointer, releaseBuffer will access internal_handle
              miniAV.releaseBuffer(bufferPtr);
            } on MiniAVException catch (e) {
              print("[Test Callback] Error releasing buffer: $e");
              // Decide if this should fail the completer
            }
          } else {
            print(
              '[Test Callback] Warning - buffer.internal_handle is NULL, cannot release.',
            );
          }

          if (!frameReceivedCompleter.isCompleted) {
            frameReceivedCompleter.complete();
          }
        }

        // Pass the Dart callback directly. MiniAV class handles NativeCallable.
        miniAV.cameraStartCapture(
          contextHandle,
          myDartBufferCallback,
          // Optional: userData: myCustomUserDataPointer,
        );
        print('Camera capture started. Waiting for frame...');

        await frameReceivedCompleter.future.timeout(
          const Duration(seconds: 15), // Adjust timeout as needed
          onTimeout: () {
            throw TimeoutException(
              'Timeout: No frame received within 15 seconds.',
            );
          },
        );

        expect(
          frameCount,
          greaterThan(0),
          reason: 'Expected at least one frame to be received.',
        );
        print('Capture test successful: Received $frameCount frames.');
      } on MiniAVException catch (e) {
        fail(
          'Camera capture test failed for device ${firstDevice.deviceId} with format ${formatToTest.toString()}: $e',
        );
      } on TimeoutException catch (e) {
        fail('Camera capture test failed: ${e.message}');
      } catch (e, s) {
        print('Stack trace for unexpected error in capture test: $s');
        fail('Camera capture test failed with unexpected error: $e');
      } finally {
        print('Cleaning up capture test resources...');
        if (contextHandle != null && contextHandle != nullptr) {
          try {
            // cameraStopCapture will also handle closing the internal NativeCallable
            miniAV.cameraStopCapture(contextHandle);
            print('Camera capture stopped.');
          } on MiniAVException catch (e) {
            // Log error during cleanup, but don't let it hide the original test failure
            print('Error stopping capture (during cleanup): $e');
          }
          try {
            miniAV.cameraDestroyContext(contextHandle);
            print('Camera context destroyed.');
          } on MiniAVException catch (e) {
            print('Error destroying context (during cleanup): $e');
          }
        }
        // The NativeCallable is now managed by the MiniAV instance,
        // so no need to close it explicitly here.
        // It will be closed by cameraStopCapture or miniAV.dispose().
      }
    });
  });
}
