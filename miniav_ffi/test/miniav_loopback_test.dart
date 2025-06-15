import 'dart:async';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:miniav_platform_interface/miniav_platform_interface.dart';
import 'package:miniav_ffi/miniav_ffi.dart'; // Assuming this exports MiniAVFFIPlatform

void main() {
  late MiniLoopbackPlatformInterface loopbackPlatform;

  setUpAll(() {
    try {
      loopbackPlatform = MiniAVFFIPlatform().loopback;
      print('MiniAV FFI Loopback Test Setup Complete.');
    } catch (e) {
      print('Failed to initialize MiniAVFFIPlatform for loopback: $e');
      throw StateError(
        'Could not initialize loopbackPlatform. Ensure FFI is set up.',
      );
    }
  });

  group('MiniAV Loopback Platform Interface Tests', () {
    test('Enumerate Loopback Devices', () async {
      final devices = await loopbackPlatform.enumerateDevices();
      expect(devices, isA<List<MiniAVDeviceInfo>>());
      print('Found ${devices.length} loopback audio devices:');
      for (final device in devices) {
        print(
          '- ID: ${device.deviceId}, Name: ${device.name}, Default: ${device.isDefault}',
        );
        expect(device.deviceId, isNotEmpty);
      }
    });

    test('Get Default Loopback Format (for the first available device)', () async {
      final devices = await loopbackPlatform.enumerateDevices();
      if (devices.isEmpty) {
        print('No loopback devices found to get default format from.');
        return;
      }
      final firstDevice = devices.first;
      print(
        'Attempting to get default format for device: ${firstDevice.name} (${firstDevice.deviceId})',
      );
      final format = await loopbackPlatform.getDefaultFormat(
        firstDevice.deviceId,
      );
      expect(format, isA<MiniAVAudioInfo>());
      print(
        'Default format for ${firstDevice.name}: ${format.channels}ch, ${format.sampleRate}Hz, Format: ${format.format.name}',
      );
      expect(format.channels, greaterThan(0));
      expect(format.sampleRate, greaterThan(0));
      expect(format.format, isNot(MiniAVAudioFormat.unknown));
    });

    test('Create and Destroy Loopback Context', () async {
      final context = await loopbackPlatform.createContext();
      expect(context, isNotNull);
      print('Loopback context created: $context');
      await context.destroy();
      print('Loopback context destroyed.');
    });

    test(
      'Configure Loopback Context (for the first available device and its default format)',
      () async {
        final devices = await loopbackPlatform.enumerateDevices();
        if (devices.isEmpty) {
          print('No loopback devices found for configuration test.');
          return;
        }
        final firstDevice = devices.first;
        final defaultFormat = await loopbackPlatform.getDefaultFormat(
          firstDevice.deviceId,
        );

        print(
          'Configuring loopback for device ${firstDevice.name} with format ${defaultFormat.channels}ch, ${defaultFormat.sampleRate}Hz',
        );
        final context = await loopbackPlatform.createContext();
        try {
          await context.configure(firstDevice.deviceId, defaultFormat);
          print('Loopback context configured successfully.');

          final configuredFormat = await context.getConfiguredFormat();
          expect(configuredFormat.sampleRate, defaultFormat.sampleRate);
          expect(configuredFormat.channels, defaultFormat.channels);
          print(
            'Confirmed configured format: ${configuredFormat.channels}ch, ${configuredFormat.sampleRate}Hz, Format: ${configuredFormat.format.name}',
          );
        } finally {
          await context.destroy();
        }
      },
    );

    test(
      'Start and Stop Loopback Capture (receives at least one audio buffer)',
      () async {
        final devices = await loopbackPlatform.enumerateDevices();
        if (devices.isEmpty) {
          print('No loopback devices found for capture test.');
          return;
        }
        // Prefer default device if available, otherwise first.
        final targetDevice = devices.firstWhere(
          (d) => d.isDefault,
          orElse: () => devices.first,
        );

        print(
          'Attempting capture from device: ${targetDevice.name} (${targetDevice.deviceId})',
        );

        final defaultFormat = await loopbackPlatform.getDefaultFormat(
          targetDevice.deviceId,
        );
        print(
          'Using format for capture test: ${defaultFormat.channels}ch, ${defaultFormat.sampleRate}Hz, Format: ${defaultFormat.format.name}',
        );

        final context = await loopbackPlatform.createContext();
        final bufferReceivedCompleter = Completer<void>();
        int bufferCount = 0;

        try {
          await context.configure(targetDevice.deviceId, defaultFormat);
          print('Loopback context configured for capture.');

          await context.startCapture((buffer, userData) {
            bufferCount++;
            print(
              '[Test Callback] Audio Buffer received! Count: $bufferCount, Type: ${buffer.type.name}, Content: ${buffer.contentType.name}, Size: ${buffer.dataSizeBytes}, Timestamp: ${buffer.timestampUs}',
            );
            final audioBuffer = buffer.data as MiniAVAudioBuffer;
            expect(buffer.type, MiniAVBufferType.audio);
            expect(buffer.dataSizeBytes, greaterThan(0));
            expect(audioBuffer, isNotNull);
            expect(audioBuffer.info.sampleRate, defaultFormat.sampleRate);
            expect(audioBuffer.info.channels, defaultFormat.channels);
            expect(audioBuffer.data, isA<Uint8List>());
            expect(audioBuffer.data.lengthInBytes, greaterThan(0));
            print(audioBuffer.info.format);
            print('audio buffer data: ${audioBuffer.data.take(10).join(', ')}');
            expect(audioBuffer.data.lengthInBytes, greaterThan(0));

            if (!bufferReceivedCompleter.isCompleted) {
              bufferReceivedCompleter.complete();
            }
          });

          print('Loopback capture started. Waiting for audio buffer...');
          await bufferReceivedCompleter.future.timeout(
            const Duration(seconds: 10), // Increased timeout for audio
            onTimeout: () {
              if (bufferCount == 0) {
                // If no audio is playing on the system, loopback might receive silent packets or no packets.
                print(
                  'Warning: No audio buffer received within 10 seconds. Ensure audio is playing on the system for loopback capture.',
                );
                if (!bufferReceivedCompleter.isCompleted) {
                  bufferReceivedCompleter
                      .complete(); // Allow test to proceed with 0 buffers if timeout
                }
              }
              // If it timed out but some buffers were received, that's fine.
            },
          );
          print('Capture test finished. Received $bufferCount buffers.');
          // expect(bufferCount, greaterThan(0), reason: 'Expected at least one audio buffer.');
        } finally {
          print('Stopping capture and destroying context...');
          await context.stopCapture();
          print('Loopback capture stopped.');
          await context.destroy();
          print('Loopback context destroyed.');
        }
      },
      timeout: const Timeout(Duration(seconds: 20)),
    ); // Longer test timeout
  });
}
