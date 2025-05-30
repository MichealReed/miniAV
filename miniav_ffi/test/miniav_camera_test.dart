import 'dart:async';
import 'package:miniav_platform_interface/miniav_platform_types.dart';
import 'package:test/test.dart';
import 'package:miniav_platform_interface/miniav_platform_interface.dart'
    as platform;
import 'package:miniav_ffi/miniav_ffi.dart';

void main() {
  late platform.MiniCameraPlatformInterface camera;

  setUpAll(() {
    // Use the registered FFI instance
    camera = MiniAVFFIPlatform().camera;
    print('MiniAV FFI Camera Test Setup Complete.');
  });

  group('MiniAV Camera Platform Interface Tests', () {
    test('Enumerate Camera Devices', () async {
      final devices = await camera.enumerateDevices();
      expect(devices, isA<List<platform.MiniAVDeviceInfo>>());
      print('Found ${devices.length} camera devices:');
      for (final device in devices) {
        print(
          '- ID: ${device.deviceId}, Name: ${device.name}, Default: ${device.isDefault}',
        );
        expect(device.deviceId, isNotEmpty);
        expect(device.name, isNotEmpty);
      }
    });

    test('Get Supported Camera Formats (for the first available camera)', () async {
      final devices = await camera.enumerateDevices();
      if (devices.isEmpty) {
        print('No camera devices found to get formats from.');
        return;
      }
      final firstDevice = devices[0];
      print(
        'Attempting to get formats for device: ${firstDevice.name} (${firstDevice.deviceId})',
      );
      final formats = await camera.getSupportedFormats(firstDevice.deviceId);
      expect(formats, isA<List<MiniAVVideoInfo>>());
      print('Found ${formats.length} formats for ${firstDevice.name}:');
      for (final format in formats) {
        print(
          '- ${format.width}x${format.height} @ ${format.frameRateNumerator}/${format.frameRateDenominator}fps, PixelFormat: ${format.pixelFormat.name}, Preference: ${format.outputPreference.name}',
        );
        expect(format.width, greaterThan(0));
        expect(format.height, greaterThan(0));
      }
    });

    test('Create and Destroy Camera Context', () async {
      final context = await camera.createContext();
      expect(context, isNotNull);
      print('Camera context created: $context');
      await context.destroy();
      print('Camera context destroyed.');
    });

    test(
      'Configure Camera Context (for the first available camera and format)',
      () async {
        final devices = await camera.enumerateDevices();
        if (devices.isEmpty) {
          print('No camera devices found.');
          return;
        }
        final firstDevice = devices[0];
        final formats = await camera.getSupportedFormats(firstDevice.deviceId);
        if (formats.isEmpty) {
          print('No formats found for device ${firstDevice.deviceId}.');
          return;
        }
        final firstFormat = formats.first;
        print(
          'Configuring camera ${firstDevice.name} with format ${firstFormat.width}x${firstFormat.height}',
        );
        final context = await camera.createContext();
        try {
          await context.configure(firstDevice.deviceId, firstFormat);
          print('Camera configured successfully.');
        } finally {
          await context.destroy();
        }
      },
    );

    test('Start and Stop Camera Capture (receives at least one frame)', () async {
      final devices = await camera.enumerateDevices();
      if (devices.isEmpty) {
        print('No camera devices found.');
        return;
      }
      final firstDevice = devices[0];
      final formats = await camera.getSupportedFormats(firstDevice.deviceId);
      if (formats.isEmpty) {
        print('No formats found for device ${firstDevice.deviceId}.');
        return;
      }
      final formatToTest = formats.firstWhere(
        (f) => f.width == 640 && f.height == 480,
        orElse: () => formats.first,
      );
      print(
        'Selected format for capture test: ${formatToTest.width}x${formatToTest.height} @ ${formatToTest.frameRateNumerator}/${formatToTest.frameRateDenominator}fps, PixelFormat: ${formatToTest.pixelFormat.name}',
      );

      final context = await camera.createContext();
      final frameReceivedCompleter = Completer<void>();
      int frameCount = 0;

      await context.configure(firstDevice.deviceId, formatToTest);

      await context.startCapture((buffer, userData) {
        frameCount++;
        print(
          '[Test Callback] Frame received! Count: $frameCount, Type: ${buffer.runtimeType}, Size: ${buffer.dataSizeBytes}',
        );
        if (!frameReceivedCompleter.isCompleted) {
          frameReceivedCompleter.complete();
        }
      });

      print('Camera capture started. Waiting for frame...');
      await frameReceivedCompleter.future.timeout(
        const Duration(seconds: 15),
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

      await context.stopCapture();
      print('Camera capture stopped.');
      await context.destroy();
      print('Camera context destroyed.');
    });
  });

  group('MiniAV Camera Latency Test', () {
    test('Capture frames for 5 seconds and measure latency', () async {
      final devices = await camera.enumerateDevices();
      if (devices.isEmpty) {
        print('No camera devices found.');
        return;
      }
      final firstDevice = devices[0];
      final formats = await camera.getSupportedFormats(firstDevice.deviceId);
      if (formats.isEmpty) {
        print('No formats found for device ${firstDevice.deviceId}.');
        return;
      }
      final formatToTest = formats.firstWhere(
        (f) => f.width == 640 && f.height == 480,
        orElse: () => formats.first,
      );
      print(
        'Selected format for latency test: ${formatToTest.width}x${formatToTest.height} @ ${formatToTest.frameRateNumerator}/${formatToTest.frameRateDenominator}fps, PixelFormat: ${formatToTest.pixelFormat.name}',
      );

      final context = await camera.createContext();
      int frameCount = 0;
      final List<int> frameTimestamps = [];
      final List<int> frameLatencies = [];

      await context.configure(firstDevice.deviceId, formatToTest);

      await context.startCapture((buffer, userData) {
        frameCount++;
        final timestamp = DateTime.now().microsecondsSinceEpoch;
        frameTimestamps.add(timestamp);
        if (frameTimestamps.length > 1) {
          final latency =
              timestamp - frameTimestamps[frameTimestamps.length - 2];
          frameLatencies.add(latency);
        }
        print(
          '[Test Callback] Frame received! Count: $frameCount, Type: ${buffer.runtimeType}, Size: ${buffer.dataSizeBytes}',
        );
      });

      print('Camera capture started. Capturing for 5 seconds...');
      await Future.delayed(const Duration(seconds: 5));
      await context.stopCapture();
      print('Camera capture stopped.');

      if (frameLatencies.isNotEmpty) {
        final averageLatency =
            frameLatencies.reduce((a, b) => a + b) / frameLatencies.length;
        print('Frame Latencies (microseconds): $frameLatencies');
        print(
          'Average Frame Latency: ${(averageLatency / 1000).toStringAsFixed(2)} milliseconds',
        );
      } else {
        print('No frame latencies recorded.');
      }

      expect(
        frameCount,
        greaterThan(0),
        reason: 'Expected at least one frame to be received.',
      );
      await context.destroy();
      print('Camera context destroyed.');
    });
  });
}
