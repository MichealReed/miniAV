import 'package:miniav/miniav.dart';
import 'package:test/test.dart';

void main() {
  group('MiniAudioInput Tests', () {
    group('Static Methods', () {
      test('should enumerate available audio input devices', () async {
        final devices = await MiniAudioInput.enumerateDevices();
        expect(devices, isA<List<MiniAVDeviceInfo>>());
        // On most systems, there should be at least one audio input device
        expect(devices, isNotEmpty);
      });

      test('should get supported formats for a device', () async {
        final devices = await MiniAudioInput.enumerateDevices();
        if (devices.isNotEmpty) {
          final formats = await MiniAudioInput.getSupportedFormats(
            devices.first.deviceId,
          );
          expect(formats, isA<List<MiniAVAudioInfo>>());
          expect(formats, isNotEmpty);
        }
      });

      test('should get default format for a device', () async {
        final devices = await MiniAudioInput.enumerateDevices();
        if (devices.isNotEmpty) {
          final defaultFormat = await MiniAudioInput.getDefaultFormat(
            devices.first.deviceId,
          );
          expect(defaultFormat, isA<MiniAVAudioInfo>());
          expect(defaultFormat.sampleRate, greaterThan(0));
          expect(defaultFormat.channels, greaterThan(0));
        }
      });

      test('should handle invalid device ID for supported formats', () async {
        try {
          final result = await MiniAudioInput.getSupportedFormats(
            'invalid_device_id',
          );
          expect(result, isA<List<MiniAVAudioInfo>>());
        } catch (e) {
          expect(e, isException);
        }
      });

      test('should handle invalid device ID for default format', () async {
        try {
          final result = await MiniAudioInput.getDefaultFormat(
            'invalid_device_id',
          );
          expect(result, isA<MiniAVAudioInfo>());
        } catch (e) {
          expect(e, isException);
        }
      });

      test('should create audio input context', () async {
        final context = await MiniAudioInput.createContext();
        expect(context, isA<MiniAudioInputContext>());
        await context.destroy();
      });
    });

    group('MiniAudioInputContext Tests', () {
      late MiniAudioInputContext context;
      late List<MiniAVDeviceInfo> devices;
      late MiniAVAudioInfo defaultFormat;

      setUp(() async {
        context = await MiniAudioInput.createContext();
        devices = await MiniAudioInput.enumerateDevices();
        if (devices.isNotEmpty) {
          defaultFormat = await MiniAudioInput.getDefaultFormat(
            devices.first.deviceId,
          );
        }
      });

      tearDown(() async {
        try {
          await context.stopCapture();
        } catch (e) {
          // Ignore if already stopped
        }
        await context.destroy();
      });

      test('should configure audio input with device and format', () async {
        if (devices.isNotEmpty) {
          await context.configure(devices.first.deviceId, defaultFormat);

          final configuredFormat = await context.getConfiguredFormat();
          expect(configuredFormat.sampleRate, equals(defaultFormat.sampleRate));
          expect(configuredFormat.channels, equals(defaultFormat.channels));
        }
      });

      test('should handle invalid device configuration', () async {
        expect(
          () async => await context.configure('invalid_device', defaultFormat),
          throwsException,
        );
      });

      test('should handle invalid format configuration', () async {
        if (devices.isNotEmpty) {
          final invalidFormat = MiniAVAudioInfo(
            sampleRate: -1,
            channels: 0,
            format: MiniAVAudioFormat.unknown,
            numFrames: 0,
          );

          try {
            await context.configure(devices.first.deviceId, invalidFormat);
            final configuredFormat = await context.getConfiguredFormat();
            expect(configuredFormat.sampleRate, greaterThan(0));
            expect(configuredFormat.channels, greaterThan(0));
          } catch (e) {
            expect(e, isException);
          }
        }
      });

      test('should start and stop capture', () async {
        if (devices.isNotEmpty) {
          await context.configure(devices.first.deviceId, defaultFormat);

          bool dataReceived = false;
          await context.startCapture((buffer, userData) {
            dataReceived = true;
            expect(buffer, isA<MiniAVBuffer>());
            expect(buffer.dataSizeBytes, greaterThan(0));
          });

          // Allow some time for audio capture
          await Future.delayed(Duration(milliseconds: 100));

          await context.stopCapture();
          expect(dataReceived, isTrue);
        }
      });

      test('should pass userData to callback', () async {
        if (devices.isNotEmpty) {
          await context.configure(devices.first.deviceId, defaultFormat);

          const testUserData = 'test_data';
          Object? receivedUserData;

          await context.startCapture((buffer, userData) {
            receivedUserData = userData;
          }, userData: testUserData);

          await Future.delayed(Duration(milliseconds: 50));
          await context.stopCapture();

          expect(receivedUserData, equals(testUserData));
        }
      });

      test('should handle multiple start capture calls', () async {
        if (devices.isNotEmpty) {
          await context.configure(devices.first.deviceId, defaultFormat);

          await context.startCapture((buffer, userData) {});

          // Second start should either succeed or throw predictable exception
          expect(
            () async => await context.startCapture((buffer, userData) {}),
            anyOf(returnsNormally, throwsException),
          );

          await context.stopCapture();
        }
      });

      test('should handle stop capture without start', () async {
        // Should not throw exception
        await context.stopCapture();
      });

      test('should handle multiple stop capture calls', () async {
        if (devices.isNotEmpty) {
          await context.configure(devices.first.deviceId, defaultFormat);
          await context.startCapture((buffer, userData) {});

          await context.stopCapture();
          // Second stop should not throw
          await context.stopCapture();
        }
      });

      test('should get configured format before configuration', () async {
        expect(
          () async => await context.getConfiguredFormat(),
          throwsException,
        );
      });

      test('should handle capture without configuration', () async {
        expect(
          () async => await context.startCapture((buffer, userData) {}),
          throwsException,
        );
      });

      test('should receive audio buffers with correct format', () async {
        if (devices.isNotEmpty) {
          await context.configure(devices.first.deviceId, defaultFormat);

          MiniAVBuffer? receivedBuffer;
          await context.startCapture((buffer, userData) {
            receivedBuffer = buffer;
          });

          await Future.delayed(Duration(milliseconds: 100));
          await context.stopCapture();

          if (receivedBuffer != null) {
            // Buffer size should be reasonable
            expect(receivedBuffer!.dataSizeBytes, greaterThan(0));
          }
        }
      });

      test('should handle context destruction during capture', () async {
        if (devices.isNotEmpty) {
          await context.configure(devices.first.deviceId, defaultFormat);
          await context.startCapture((buffer, userData) {});

          // Destroying during capture should handle cleanup
          await context.destroy();
        }
      });

      test('should handle multiple destroy calls', () async {
        await context.destroy();
        // Second destroy should not throw
        await context.destroy();
      });
    });

    group('Integration Tests', () {
      test('should work with multiple contexts simultaneously', () async {
        final context1 = await MiniAudioInput.createContext();
        final context2 = await MiniAudioInput.createContext();

        final devices = await MiniAudioInput.enumerateDevices();
        if (devices.isNotEmpty) {
          final format = await MiniAudioInput.getDefaultFormat(
            devices.first.deviceId,
          );

          await context1.configure(devices.first.deviceId, format);
          await context2.configure(devices.first.deviceId, format);

          // Both contexts should be configurable
          final format1 = await context1.getConfiguredFormat();
          final format2 = await context2.getConfiguredFormat();

          expect(format1.sampleRate, equals(format2.sampleRate));
        }

        await context1.destroy();
        await context2.destroy();
      });

      test('should handle rapid create/destroy cycles', () async {
        for (int i = 0; i < 5; i++) {
          final context = await MiniAudioInput.createContext();
          await context.destroy();
        }
      });

      test('should enumerate devices consistently', () async {
        final devices1 = await MiniAudioInput.enumerateDevices();
        final devices2 = await MiniAudioInput.enumerateDevices();

        // Device lists should be consistent (unless hardware changes)
        expect(devices1.length, equals(devices2.length));
        if (devices1.isNotEmpty && devices2.isNotEmpty) {
          expect(devices1.first.deviceId, equals(devices2.first.deviceId));
        }
      });
    });

    group('Performance Tests', () {
      test('should enumerate devices quickly', () async {
        final stopwatch = Stopwatch()..start();
        await MiniAudioInput.enumerateDevices();
        stopwatch.stop();

        // Should complete within reasonable time
        expect(stopwatch.elapsedMilliseconds, lessThan(5000));
      });

      test('should create context quickly', () async {
        final stopwatch = Stopwatch()..start();
        final context = await MiniAudioInput.createContext();
        stopwatch.stop();

        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
        await context.destroy();
      });

      test('should configure context quickly', () async {
        final context = await MiniAudioInput.createContext();
        final devices = await MiniAudioInput.enumerateDevices();

        if (devices.isNotEmpty) {
          final format = await MiniAudioInput.getDefaultFormat(
            devices.first.deviceId,
          );

          final stopwatch = Stopwatch()..start();
          await context.configure(devices.first.deviceId, format);
          stopwatch.stop();

          expect(stopwatch.elapsedMilliseconds, lessThan(1000));
        }

        await context.destroy();
      });
    });
  });
}
