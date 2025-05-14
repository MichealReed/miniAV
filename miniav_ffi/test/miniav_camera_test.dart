import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';
import 'package:miniav_ffi/miniav_ffi.dart';
import 'package:miniav_ffi/miniav_ffi_bindings.dart' as bindings;

void main() {
  late MiniAV miniAV;

  setUpAll(() {
    miniAV = MiniAV();

    miniAV.setLogCallback((level, messagePtr, userData) {
      final message = messagePtr.cast<Utf8>().toDartString();
      print('[MiniAV Test Log - $level]: $message');
    });
    miniAV.setLogLevel(bindings.MiniAVLogLevel.MINIAV_LOG_LEVEL_DEBUG);
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

    // TODO: Add tests for cameraStartCapture and cameraStopCapture
    // These will be more involved as they require handling callbacks and buffers.
  });
}
