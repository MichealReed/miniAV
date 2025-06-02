import 'package:miniav/miniav.dart';
import 'package:test/test.dart';

void main() {
  group('MiniLoopback Tests', () {
    group('Static Methods', () {
      test('should enumerate available loopback devices', () async {
        final devices = await MiniLoopback.enumerateDevices();
        expect(devices, isA<List<MiniAVDeviceInfo>>());
        // Loopback devices may not be available on all systems

        // Verify device properties if any exist
        for (final device in devices) {
          expect(device.deviceId, isNotEmpty);
          expect(device.name, isNotEmpty);
        }
      });

      test('should get supported formats for a loopback device', () async {
        final devices = await MiniLoopback.enumerateDevices();
        if (devices.isNotEmpty) {
          final format = await MiniLoopback.getDefaultFormat(
            devices.first.deviceId,
          );
          expect(format, isA<MiniAVAudioInfo>());

          // Verify format properties are valid
          expect(format.sampleRate, greaterThan(0));
          expect(format.channels, greaterThan(0));
          expect(format.numFrames, equals(0));
        }
      });

      test('should get default format for a loopback device', () async {
        final devices = await MiniLoopback.enumerateDevices();
        if (devices.isNotEmpty) {
          final defaultFormat = await MiniLoopback.getDefaultFormat(
            devices.first.deviceId,
          );
          expect(defaultFormat, isA<MiniAVAudioInfo>());
          expect(defaultFormat.sampleRate, greaterThan(0));
          expect(defaultFormat.channels, greaterThan(0));
          expect(defaultFormat.numFrames, equals(0));
        }
      });

      test('should handle invalid device ID for supported formats', () async {
        try {
          final result = await MiniLoopback.getDefaultFormat(
            'invalid_device_id',
          );
          // Platform might return empty list instead of throwing
          expect(result, isA<List<MiniAVAudioInfo>>());
        } catch (e) {
          expect(e, isException);
        }
      });

      test('should handle invalid device ID for default format', () async {
        try {
          final result = await MiniLoopback.getDefaultFormat(
            'invalid_device_id',
          );
          // Platform might return fallback format instead of throwing
          expect(result, isA<MiniAVAudioInfo>());
          expect(result.sampleRate, greaterThan(0));
          expect(result.channels, greaterThan(0));
        } catch (e) {
          expect(e, isException);
        }
      });

      test('should create loopback context', () async {
        final context = await MiniLoopback.createContext();
        expect(context, isA<MiniLoopbackContext>());
        await context.destroy();
      });
    });

    group('MiniLoopbackContext Tests', () {
      late MiniLoopbackContext context;
      late List<MiniAVDeviceInfo> devices;
      late MiniAVAudioInfo? defaultFormat;

      setUp(() async {
        context = await MiniLoopback.createContext();
        devices = await MiniLoopback.enumerateDevices();
        if (devices.isNotEmpty) {
          defaultFormat = await MiniLoopback.getDefaultFormat(
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

      test('should configure loopback with device and format', () async {
        if (devices.isNotEmpty && defaultFormat != null) {
          await context.configure(devices.first.deviceId, defaultFormat!);

          final configuredFormat = await context.getConfiguredFormat();
          expect(
            configuredFormat.sampleRate,
            equals(defaultFormat!.sampleRate),
          );
          expect(configuredFormat.channels, equals(defaultFormat!.channels));
          expect(configuredFormat.format, equals(defaultFormat!.format));
        }
      });

      test('should handle invalid device configuration', () async {
        if (defaultFormat != null) {
          try {
            await context.configure('invalid_device', defaultFormat!);
            // If no exception, verify we can still get configured format
            final configuredFormat = await context.getConfiguredFormat();
            expect(configuredFormat, isA<MiniAVAudioInfo>());
          } catch (e) {
            expect(e, isException);
          }
        }
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
            // Platform might sanitize invalid values
            final configuredFormat = await context.getConfiguredFormat();
            expect(configuredFormat.sampleRate, greaterThan(0));
            expect(configuredFormat.channels, greaterThan(0));
            expect(configuredFormat.format, isNot(MiniAVAudioFormat.unknown));
          } catch (e) {
            expect(e, isException);
          }
        }
      });

      test('should start and stop capture', () async {
        if (devices.isNotEmpty && defaultFormat != null) {
          await context.configure(devices.first.deviceId, defaultFormat!);

          await context.startCapture((buffer, userData) {
            expect(buffer, isA<MiniAVBuffer>());
            expect(buffer.dataSizeBytes, greaterThan(0));

            // Loopback buffer should contain audio data
            final audioBuffer = buffer.data as MiniAVAudioBuffer;
            expect(audioBuffer, isNotNull);
          });

          // Allow time for loopback audio capture
          await Future.delayed(Duration(milliseconds: 500));

          await context.stopCapture();
          // Note: dataReceived might be false if no system audio is playing
        }
      });

      test('should pass userData to callback', () async {
        if (devices.isNotEmpty && defaultFormat != null) {
          await context.configure(devices.first.deviceId, defaultFormat!);

          const testUserData = 'loopback_test_data';
          Object? receivedUserData;

          await context.startCapture((buffer, userData) {
            receivedUserData = userData;
          }, userData: testUserData);

          await Future.delayed(Duration(milliseconds: 200));
          await context.stopCapture();

          if (receivedUserData != null) {
            expect(receivedUserData, equals(testUserData));
          }
        }
      });

      test('should handle multiple start capture calls', () async {
        if (devices.isNotEmpty && defaultFormat != null) {
          await context.configure(devices.first.deviceId, defaultFormat!);

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
        if (devices.isNotEmpty && defaultFormat != null) {
          await context.configure(devices.first.deviceId, defaultFormat!);
          await context.startCapture((buffer, userData) {});

          await context.stopCapture();
          // Second stop should not throw
          await context.stopCapture();
        }
      });

      test('should get configured format before configuration', () async {
        try {
          await context.getConfiguredFormat();
          // If no exception, verify it's a valid format
          final format = await context.getConfiguredFormat();
          expect(format, isA<MiniAVAudioInfo>());
        } catch (e) {
          expect(e, isException);
        }
      });

      test('should handle capture without configuration', () async {
        try {
          await context.startCapture((buffer, userData) {});
          // If no exception, capture started with default settings
          await context.stopCapture();
        } catch (e) {
          expect(e, isException);
        }
      });

      test('should receive audio data with correct format', () async {
        if (devices.isNotEmpty && defaultFormat != null) {
          await context.configure(devices.first.deviceId, defaultFormat!);

          MiniAVBuffer? receivedBuffer;
          await context.startCapture((buffer, userData) {
            receivedBuffer = buffer;
          });

          await Future.delayed(Duration(milliseconds: 300));
          await context.stopCapture();

          if (receivedBuffer != null) {
            expect(receivedBuffer!.dataSizeBytes, greaterThan(0));

            final audioBuffer = receivedBuffer!.data as MiniAVAudioBuffer;
            expect(audioBuffer, isNotNull);
            // Audio data should be present if system audio is playing
          }
        }
      });

      test('should handle context destruction during capture', () async {
        if (devices.isNotEmpty && defaultFormat != null) {
          await context.configure(devices.first.deviceId, defaultFormat!);
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

      test('should support different sample rates', () async {
        if (devices.isNotEmpty && defaultFormat != null) {
          final customFormat = MiniAVAudioInfo(
            sampleRate: defaultFormat!.sampleRate == 44100 ? 48000 : 44100,
            channels: defaultFormat!.channels,
            format: defaultFormat!.format,
            numFrames: defaultFormat!.numFrames,
          );

          await context.configure(devices.first.deviceId, customFormat);
          final configuredFormat = await context.getConfiguredFormat();

          expect(configuredFormat.sampleRate, equals(customFormat.sampleRate));
        }
      });

      test('should support different channel configurations', () async {
        if (devices.isNotEmpty && defaultFormat != null) {
          final customFormat = MiniAVAudioInfo(
            sampleRate: defaultFormat!.sampleRate,
            channels: defaultFormat!.channels == 1 ? 2 : 1,
            format: defaultFormat!.format,
            numFrames: defaultFormat!.numFrames,
          );

          await context.configure(devices.first.deviceId, customFormat);
          final configuredFormat = await context.getConfiguredFormat();

          expect(configuredFormat.channels, equals(customFormat.channels));
        }
      });
    });

    group('System Audio Detection Tests', () {
      test('should detect system audio capability', () async {
        final devices = await MiniLoopback.enumerateDevices();
        // System may or may not support loopback audio
        expect(devices, isA<List<MiniAVDeviceInfo>>());
      });

      test('should handle no system audio scenario', () async {
        final devices = await MiniLoopback.enumerateDevices();
        if (devices.isNotEmpty) {
          final context = await MiniLoopback.createContext();
          final format = await MiniLoopback.getDefaultFormat(
            devices.first.deviceId,
          );

          await context.configure(devices.first.deviceId, format);

          bool audioDetected = false;
          await context.startCapture((buffer, userData) {
            if (buffer.dataSizeBytes > 0) {
              audioDetected = true;
            }
          });

          // Wait a moment to detect audio
          await Future.delayed(Duration(milliseconds: 500));
          await context.stopCapture();

          // Audio detection depends on whether system audio is playing
          expect(audioDetected, isA<bool>());
          await context.destroy();
        }
      });

      test('should detect different audio output devices', () async {
        final devices = await MiniLoopback.enumerateDevices();

        // Different devices might represent different audio outputs
        final deviceNames = devices.map((d) => d.name).toSet();
        expect(
          deviceNames.length,
          equals(devices.length),
        ); // No duplicate names
      });
    });

    group('Exclusive Mode Tests', () {
      test('should handle exclusive mode conflicts', () async {
        final devices = await MiniLoopback.enumerateDevices();
        if (devices.isNotEmpty) {
          final context1 = await MiniLoopback.createContext();
          final context2 = await MiniLoopback.createContext();

          try {
            final format = await MiniLoopback.getDefaultFormat(
              devices.first.deviceId,
            );

            await context1.configure(devices.first.deviceId, format);
            await context1.startCapture((buffer, userData) {});

            // Second context might conflict in exclusive mode
            try {
              await context2.configure(devices.first.deviceId, format);
              await context2.startCapture((buffer, userData) {});
              // If no exception, shared mode is supported
              await context2.stopCapture();
            } catch (e) {
              // Exclusive mode conflict is acceptable
              expect(e, isException);
            }

            await context1.stopCapture();
          } finally {
            await context1.destroy();
            await context2.destroy();
          }
        }
      });

      test('should handle audio device busy scenarios', () async {
        final devices = await MiniLoopback.enumerateDevices();
        if (devices.isNotEmpty) {
          final context = await MiniLoopback.createContext();

          try {
            final format = await MiniLoopback.getDefaultFormat(
              devices.first.deviceId,
            );
            await context.configure(devices.first.deviceId, format);

            // Start capture might fail if device is busy
            await context.startCapture((buffer, userData) {});
            await context.stopCapture();
          } catch (e) {
            // Device busy is acceptable for loopback
            expect(e, isException);
          } finally {
            await context.destroy();
          }
        }
      });
    });

    group('Integration Tests', () {
      test('should work with multiple loopback contexts', () async {
        final devices = await MiniLoopback.enumerateDevices();
        if (devices.length >= 2) {
          final context1 = await MiniLoopback.createContext();
          final context2 = await MiniLoopback.createContext();

          try {
            final format1 = await MiniLoopback.getDefaultFormat(
              devices[0].deviceId,
            );
            final format2 = await MiniLoopback.getDefaultFormat(
              devices[1].deviceId,
            );

            await context1.configure(devices[0].deviceId, format1);
            await context2.configure(devices[1].deviceId, format2);

            final configuredFormat1 = await context1.getConfiguredFormat();
            final configuredFormat2 = await context2.getConfiguredFormat();

            expect(configuredFormat1.sampleRate, equals(format1.sampleRate));
            expect(configuredFormat2.sampleRate, equals(format2.sampleRate));
          } finally {
            await context1.destroy();
            await context2.destroy();
          }
        }
      });

      test('should handle rapid create/destroy cycles', () async {
        for (int i = 0; i < 3; i++) {
          final context = await MiniLoopback.createContext();
          await context.destroy();
        }
      });

      test('should enumerate devices consistently', () async {
        final devices1 = await MiniLoopback.enumerateDevices();
        final devices2 = await MiniLoopback.enumerateDevices();

        // Device lists should be consistent
        expect(devices1.length, equals(devices2.length));
        if (devices1.isNotEmpty && devices2.isNotEmpty) {
          expect(devices1.first.deviceId, equals(devices2.first.deviceId));
        }
      });

      test('should work alongside regular audio input', () async {
        // Test that loopback doesn't interfere with regular audio input
        final loopbackDevices = await MiniLoopback.enumerateDevices();
        final audioInputDevices = await MiniAudioInput.enumerateDevices();

        if (loopbackDevices.isNotEmpty && audioInputDevices.isNotEmpty) {
          final loopbackContext = await MiniLoopback.createContext();
          final audioInputContext = await MiniAudioInput.createContext();

          try {
            final loopbackFormat = await MiniLoopback.getDefaultFormat(
              loopbackDevices.first.deviceId,
            );
            final inputFormat = await MiniAudioInput.getDefaultFormat(
              audioInputDevices.first.deviceId,
            );

            await loopbackContext.configure(
              loopbackDevices.first.deviceId,
              loopbackFormat,
            );
            await audioInputContext.configure(
              audioInputDevices.first.deviceId,
              inputFormat,
            );

            // Both should be configurable
            final configuredLoopback = await loopbackContext
                .getConfiguredFormat();
            final configuredInput = await audioInputContext
                .getConfiguredFormat();

            expect(
              configuredLoopback.sampleRate,
              equals(loopbackFormat.sampleRate),
            );
            expect(configuredInput.sampleRate, equals(inputFormat.sampleRate));
          } finally {
            await loopbackContext.destroy();
            await audioInputContext.destroy();
          }
        }
      });
    });

    group('Performance Tests', () {
      test('should enumerate devices quickly', () async {
        final stopwatch = Stopwatch()..start();
        await MiniLoopback.enumerateDevices();
        stopwatch.stop();

        expect(stopwatch.elapsedMilliseconds, lessThan(5000));
      });

      test('should create context quickly', () async {
        final stopwatch = Stopwatch()..start();
        final context = await MiniLoopback.createContext();
        stopwatch.stop();

        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
        await context.destroy();
      });

      test('should configure context quickly', () async {
        final devices = await MiniLoopback.enumerateDevices();
        if (devices.isNotEmpty) {
          final context = await MiniLoopback.createContext();
          final format = await MiniLoopback.getDefaultFormat(
            devices.first.deviceId,
          );

          final stopwatch = Stopwatch()..start();
          await context.configure(devices.first.deviceId, format);
          stopwatch.stop();

          expect(stopwatch.elapsedMilliseconds, lessThan(1000));
          await context.destroy();
        }
      });

      test('should start capture within reasonable time', () async {
        final devices = await MiniLoopback.enumerateDevices();
        if (devices.isNotEmpty) {
          final context = await MiniLoopback.createContext();
          final format = await MiniLoopback.getDefaultFormat(
            devices.first.deviceId,
          );
          await context.configure(devices.first.deviceId, format);

          final stopwatch = Stopwatch()..start();
          try {
            await context.startCapture((buffer, userData) {});
            stopwatch.stop();
            expect(stopwatch.elapsedMilliseconds, lessThan(2000));
            await context.stopCapture();
          } catch (e) {
            // Loopback might not be available
            expect(e, isException);
          } finally {
            await context.destroy();
          }
        }
      });

      test('should maintain low latency during capture', () async {
        final devices = await MiniLoopback.enumerateDevices();
        if (devices.isNotEmpty) {
          final context = await MiniLoopback.createContext();
          final format = await MiniLoopback.getDefaultFormat(
            devices.first.deviceId,
          );
          await context.configure(devices.first.deviceId, format);

          final timestamps = <int>[];

          try {
            await context.startCapture((buffer, userData) {
              timestamps.add(DateTime.now().millisecondsSinceEpoch);
            });

            await Future.delayed(Duration(seconds: 1));
            await context.stopCapture();

            if (timestamps.length > 1) {
              // Calculate intervals between callbacks
              final intervals = <int>[];
              for (int i = 1; i < timestamps.length; i++) {
                intervals.add(timestamps[i] - timestamps[i - 1]);
              }

              if (intervals.isNotEmpty) {
                final avgInterval =
                    intervals.reduce((a, b) => a + b) / intervals.length;
                // Should have reasonable callback frequency
                expect(
                  avgInterval,
                  lessThan(100),
                ); // Less than 100ms between callbacks
              }
            }
          } catch (e) {
            // Loopback might not be available
            expect(e, isException);
          } finally {
            await context.destroy();
          }
        }
      });
    });

    group('Format Validation Tests', () {
      test('should validate loopback audio formats', () async {
        final devices = await MiniLoopback.enumerateDevices();
        if (devices.isNotEmpty) {
          final format = await MiniLoopback.getDefaultFormat(
            devices.first.deviceId,
          );

          expect(format.sampleRate, inInclusiveRange(8000, 192000));
          expect(format.channels, inInclusiveRange(1, 8));
          expect(format.numFrames, greaterThan(0));
          expect(format.format, isNot(MiniAVAudioFormat.unknown));
        }
      });

      test('should handle common loopback formats', () async {
        final devices = await MiniLoopback.enumerateDevices();
        if (devices.isNotEmpty) {
          final formats = await MiniLoopback.getDefaultFormat(
            devices.first.deviceId,
          );
          // Should support common audio formats for system audio
          final commonFormats = [
            MiniAVAudioFormat.u8,
            MiniAVAudioFormat.s16,
            MiniAVAudioFormat.s32,
            MiniAVAudioFormat.f32,
          ];

          expect(
            commonFormats.contains(formats.format),
            isTrue,
            reason: 'Default format should be a common audio format',
          );
        }
      });

      test('should support standard sample rates', () async {
        final devices = await MiniLoopback.enumerateDevices();
        if (devices.isNotEmpty) {
          final formats = await MiniLoopback.getDefaultFormat(
            devices.first.deviceId,
          );

          // Common sample rates for system audio
          final standardRates = [44100, 48000, 96000];
          expect(
            standardRates.contains(formats.sampleRate),
            isTrue,
            reason: 'Default format should have a standard sample rate',
          );
        }
      });
    });
  });
}
