import 'dart:async';
import 'package:test/test.dart';
import 'package:miniav_platform_interface/miniav_platform_interface.dart';
import 'package:miniav_ffi/miniav_ffi.dart';

void main() {
  late MiniAudioInputPlatformInterface audioInputPlatform;

  setUpAll(() {
    try {
      audioInputPlatform = MiniAVFFIPlatform().audioInput;
      print('MiniAV FFI Audio Input Test Setup Complete.');
    } catch (e) {
      print('Failed to initialize MiniAVFFIPlatform for audio input: $e');
      throw StateError(
        'Could not initialize audioInputPlatform. Ensure FFI is set up.',
      );
    }
  });

  group('MiniAV Audio Input Platform Interface Tests', () {
    test('Enumerate Audio Input Devices', () async {
      final devices = await audioInputPlatform.enumerateDevices();
      expect(devices, isA<List<MiniAVDeviceInfo>>());
      print('Found ${devices.length} audio input devices:');
      for (final device in devices) {
        print(
          '- ID: ${device.deviceId}, Name: ${device.name}, Default: ${device.isDefault}',
        );
        expect(device.deviceId, isNotEmpty);
        expect(device.name, isNotEmpty);
      }
      // It's common to have at least one microphone.
      expect(
        devices,
        isNotEmpty,
        reason: 'Expected at least one audio input device (microphone).',
      );
    });

    test(
      'Get Default Audio Input Format (for the first available device)',
      () async {
        final devices = await audioInputPlatform.enumerateDevices();
        if (devices.isEmpty) {
          print('No audio input devices found to get default format from.');
          return;
        }
        final firstDevice = devices.first;
        print(
          'Attempting to get default format for device: ${firstDevice.name} (${firstDevice.deviceId})',
        );
        final format = await audioInputPlatform.getDefaultFormat(
          firstDevice.deviceId,
        );
        expect(format, isA<MiniAVAudioInfo>());
        print(
          'Default format for ${firstDevice.name}: ${format.channels}ch, ${format.sampleRate}Hz, Format: ${format.format.name}',
        );
        expect(format.channels, greaterThan(0));
        expect(format.sampleRate, greaterThan(0));
        expect(format.format, isNot(MiniAVAudioFormat.unknown));
      },
    );

    test(
      'Get Supported Audio Input Formats (for the first available device)',
      () async {
        final devices = await audioInputPlatform.enumerateDevices();
        if (devices.isEmpty) {
          print('No audio input devices found to get supported formats from.');
          return;
        }
        final firstDevice = devices.first;
        print(
          'Attempting to get supported formats for device: ${firstDevice.name} (${firstDevice.deviceId})',
        );
        final formats = await audioInputPlatform.getSupportedFormats(
          firstDevice.deviceId,
        );
        expect(formats, isA<List<MiniAVAudioInfo>>());
        expect(
          formats,
          isNotEmpty,
          reason: 'Expected at least one supported format.',
        );
        print('Supported formats for ${firstDevice.name}:');
        for (final format in formats) {
          print(
            '- ${format.channels}ch, ${format.sampleRate}Hz, Format: ${format.format.name}',
          );
          expect(format.channels, greaterThan(0));
          expect(format.sampleRate, greaterThan(0));
          expect(format.format, isNot(MiniAVAudioFormat.unknown));
        }
      },
    );

    test('Create and Destroy Audio Input Context', () async {
      final context = await audioInputPlatform.createContext();
      expect(context, isNotNull);
      print('Audio input context created: $context');
      await context.destroy();
      print('Audio input context destroyed.');
    });

    test(
      'Configure Audio Input Context (for the first available device and its default format)',
      () async {
        final devices = await audioInputPlatform.enumerateDevices();
        if (devices.isEmpty) {
          print('No audio input devices found for configuration test.');
          return;
        }
        final firstDevice = devices.first;
        final defaultFormat = await audioInputPlatform.getDefaultFormat(
          firstDevice.deviceId,
        );

        print(
          'Configuring audio input for device ${firstDevice.name} with format ${defaultFormat.channels}ch, ${defaultFormat.sampleRate}Hz',
        );
        final context = await audioInputPlatform.createContext();
        try {
          await context.configure(firstDevice.deviceId, defaultFormat);
          print('Audio input context configured successfully.');

          final configuredFormat = await context.getConfiguredFormat();
          expect(configuredFormat.sampleRate, defaultFormat.sampleRate);
          expect(configuredFormat.channels, defaultFormat.channels);
          // Format might be slightly different due to system conversions,
          // but should be compatible or the same.
          print(
            'Confirmed configured format: ${configuredFormat.channels}ch, ${configuredFormat.sampleRate}Hz, Format: ${configuredFormat.format.name}',
          );
        } finally {
          await context.destroy();
        }
      },
    );

    test(
      'Start and Stop Audio Input Capture (receives at least one audio buffer)',
      () async {
        final devices = await audioInputPlatform.enumerateDevices();
        if (devices.isEmpty) {
          print('No audio input devices found for capture test.');
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

        final defaultFormat = await audioInputPlatform.getDefaultFormat(
          targetDevice.deviceId,
        );
        print(
          'Using format for capture test: ${defaultFormat.channels}ch, ${defaultFormat.sampleRate}Hz, Format: ${defaultFormat.format.name}',
        );

        final context = await audioInputPlatform.createContext();
        final bufferReceivedCompleter = Completer<void>();
        int bufferCount = 0;

        try {
          await context.configure(targetDevice.deviceId, defaultFormat);
          print('Audio input context configured for capture.');

          await context.startCapture((buffer, userData) {
            bufferCount++;
            print(
              '[Test Callback] Audio Buffer received! Count: $bufferCount, Type: ${buffer.type.name}, Content: ${buffer.contentType.name}, Size: ${buffer.dataSizeBytes}, Timestamp: ${buffer.timestampUs}',
            );
            final audioBuffer = buffer.data as MiniAVAudioBuffer;
            expect(buffer.type, MiniAVBufferType.audio);
            expect(buffer.dataSizeBytes, greaterThan(0));
            expect(audioBuffer.data, isNotNull);
            expect(audioBuffer.info.sampleRate, defaultFormat.sampleRate);
            expect(audioBuffer.info.channels, defaultFormat.channels);

            if (!bufferReceivedCompleter.isCompleted) {
              bufferReceivedCompleter.complete();
            }
          });

          print('Audio input capture started. Waiting for audio buffer...');
          // This timeout might need adjustment.
          await bufferReceivedCompleter.future.timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              if (bufferCount == 0) {
                print(
                  'Warning: No audio input buffer received within 5 seconds. Ensure a microphone is connected and unmuted.',
                );
              }
              // If it timed out but some buffers were received, that's fine.
              // If no buffers received, the expect(bufferCount > 0) will fail later.
            },
          );
          expect(
            bufferCount,
            greaterThan(0),
            reason: 'Expected at least one audio buffer from the microphone.',
          );
          print('Capture test finished. Received $bufferCount buffers.');
        } finally {
          print('Stopping capture and destroying context...');
          await context.stopCapture();
          print('Audio input capture stopped.');
          await context.destroy();
          print('Audio input context destroyed.');
        }
      },
      timeout: const Timeout(Duration(seconds: 15)),
    ); // Longer test timeout
  });
}
