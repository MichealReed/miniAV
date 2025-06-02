import 'package:miniav/miniav.dart';
import 'package:test/test.dart';

void main() {
  group('MiniScreen Tests', () {
    group('Static Methods', () {
      test('should enumerate available display devices', () async {
        final displays = await MiniScreen.enumerateDisplays();
        expect(displays, isA<List<MiniAVDeviceInfo>>());
        // Most systems should have at least one display
        expect(displays, isNotEmpty);

        // Verify display properties
        for (final display in displays) {
          expect(display.deviceId, isNotEmpty);
          expect(display.name, isNotEmpty);
        }
      });

      test('should enumerate available windows', () async {
        final windows = await MiniScreen.enumerateWindows();
        expect(windows, isA<List<MiniAVDeviceInfo>>());
        // Windows enumeration might be empty or populated depending on system

        // Verify window properties if any exist
        for (final window in windows) {
          expect(window.deviceId, isNotEmpty);
          expect(window.name, isNotEmpty);
        }
      });

      test('should get default formats for a display', () async {
        final displays = await MiniScreen.enumerateDisplays();
        if (displays.isNotEmpty) {
          final defaultFormats = await MiniScreen.getDefaultFormats(
            displays.first.deviceId,
          );
          expect(defaultFormats, isA<ScreenFormatDefaults>());
          expect(defaultFormats.$1.width, greaterThan(0));
          expect(defaultFormats.$1.height, greaterThan(0));
          expect(defaultFormats.$1.frameRateNumerator, greaterThan(0));
          expect(defaultFormats.$1.frameRateDenominator, greaterThan(0));
        }
      });

      test('should handle invalid display ID for default formats', () async {
        try {
          final result = await MiniScreen.getDefaultFormats(
            'invalid_display_id',
          );
          // Platform might return fallback format instead of throwing
          expect(result, isA<ScreenFormatDefaults>());
          expect(result.$1.width, greaterThan(0));
          expect(result.$1.height, greaterThan(0));
        } catch (e) {
          expect(e, isException);
        }
      });

      test('should create screen context', () async {
        final context = await MiniScreen.createContext();
        expect(context, isA<MiniScreenContext>());
        await context.destroy();
      });
    });

    group('MiniScreenContext Tests', () {
      late MiniScreenContext context;
      late List<MiniAVDeviceInfo> displays;
      late List<MiniAVDeviceInfo> windows;
      late ScreenFormatDefaults defaultFormats;

      setUp(() async {
        context = await MiniScreen.createContext();
        displays = await MiniScreen.enumerateDisplays();
        windows = await MiniScreen.enumerateWindows();
        if (displays.isNotEmpty) {
          defaultFormats = await MiniScreen.getDefaultFormats(
            displays.first.deviceId,
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

      test('should configure display capture with format', () async {
        if (displays.isNotEmpty) {
          await context.configureDisplay(
            displays.first.deviceId,
            defaultFormats.$1,
          );

          final configuredFormats = await context.getConfiguredFormats();
          expect(configuredFormats.$1.width, equals(defaultFormats.$1.width));
          expect(configuredFormats.$1.height, equals(defaultFormats.$1.height));
          expect(
            configuredFormats.$1.frameRateNumerator,
            equals(defaultFormats.$1.frameRateNumerator),
          );
          expect(
            configuredFormats.$1.frameRateDenominator,
            equals(defaultFormats.$1.frameRateDenominator),
          );
        }
      });

      test('should configure display capture with audio', () async {
        if (displays.isNotEmpty) {
          await context.configureDisplay(
            displays.first.deviceId,
            defaultFormats.$1,
            captureAudio: true,
          );

          final configuredFormats = await context.getConfiguredFormats();
          expect(configuredFormats.$1.width, equals(defaultFormats.$1.width));
          // Audio format should be configured if supported
          if (configuredFormats.$2 != null) {
            expect(configuredFormats.$2!.sampleRate, greaterThan(0));
            expect(configuredFormats.$2!.channels, greaterThan(0));
          }
        }
      });

      test('should configure window capture with format', () async {
        if (windows.isNotEmpty && displays.isNotEmpty) {
          await context.configureWindow(
            windows.first.deviceId,
            defaultFormats.$1,
          );

          final configuredFormats = await context.getConfiguredFormats();
          expect(configuredFormats.$1.width, greaterThan(0));
          expect(configuredFormats.$1.height, greaterThan(0));
        }
      });

      test('should configure window capture with audio', () async {
        if (windows.isNotEmpty && displays.isNotEmpty) {
          await context.configureWindow(
            windows.first.deviceId,
            defaultFormats.$1,
            captureAudio: true,
          );

          final configuredFormats = await context.getConfiguredFormats();
          expect(configuredFormats.$1.width, greaterThan(0));
          expect(configuredFormats.$1.height, greaterThan(0));
        }
      });

      test('should handle invalid display configuration', () async {
        try {
          await context.configureDisplay('invalid_display', defaultFormats.$1);
          // If no exception, verify we can still get configured formats
          final configuredFormats = await context.getConfiguredFormats();
          expect(configuredFormats, isA<ScreenFormatDefaults>());
        } catch (e) {
          expect(e, isException);
        }
      });

      test('should handle invalid window configuration', () async {
        try {
          await context.configureWindow('invalid_window', defaultFormats.$1);
          // If no exception, verify we can still get configured formats
          final configuredFormats = await context.getConfiguredFormats();
          expect(configuredFormats, isA<ScreenFormatDefaults>());
        } catch (e) {
          expect(e, isException);
        }
      });

      test('should handle invalid format configuration', () async {
        if (displays.isNotEmpty) {
          final invalidFormat = MiniAVVideoInfo(
            width: -1,
            height: 0,
            pixelFormat: MiniAVPixelFormat.unknown,
            frameRateNumerator: 0,
            frameRateDenominator: 0,
            outputPreference: MiniAVOutputPreference.gpu,
          );

          try {
            await context.configureDisplay(
              displays.first.deviceId,
              invalidFormat,
            );
            // Platform might sanitize invalid values
            final configuredFormats = await context.getConfiguredFormats();
            expect(configuredFormats.$1.width, greaterThan(0));
            expect(configuredFormats.$1.height, greaterThan(0));
            expect(configuredFormats.$1.frameRateNumerator, greaterThan(0));
            expect(configuredFormats.$1.frameRateDenominator, greaterThan(0));
          } catch (e) {
            expect(e, isException);
          }
        }
      });

      test('should start and stop screen capture', () async {
        if (displays.isNotEmpty) {
          await context.configureDisplay(
            displays.first.deviceId,
            defaultFormats.$1,
          );

          bool frameReceived = false;
          await context.startCapture((buffer, userData) {
            frameReceived = true;
            expect(buffer, isA<MiniAVBuffer>());
            expect(buffer.dataSizeBytes, greaterThan(0));

            // Screen buffer should contain frame data
            final videoBuffer = buffer.data as MiniAVVideoBuffer;
            expect(videoBuffer, isNotNull);
          });

          // Allow time for screen capture to initialize and capture frames
          await Future.delayed(Duration(milliseconds: 500));

          await context.stopCapture();
          expect(frameReceived, isTrue);
        }
      });

      test('should pass userData to callback', () async {
        if (displays.isNotEmpty) {
          await context.configureDisplay(
            displays.first.deviceId,
            defaultFormats.$1,
          );

          const testUserData = 'screen_test_data';
          Object? receivedUserData;

          await context.startCapture((buffer, userData) {
            receivedUserData = userData;
          }, userData: testUserData);

          await Future.delayed(Duration(milliseconds: 200));
          await context.stopCapture();

          expect(receivedUserData, equals(testUserData));
        }
      });

      test('should handle multiple start capture calls', () async {
        if (displays.isNotEmpty) {
          await context.configureDisplay(
            displays.first.deviceId,
            defaultFormats.$1,
          );

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
        if (displays.isNotEmpty) {
          await context.configureDisplay(
            displays.first.deviceId,
            defaultFormats.$1,
          );
          await context.startCapture((buffer, userData) {});

          await context.stopCapture();
          // Second stop should not throw
          await context.stopCapture();
        }
      });

      test('should get configured formats before configuration', () async {
        try {
          await context.getConfiguredFormats();
          // If no exception, verify it's a valid format
          final formats = await context.getConfiguredFormats();
          expect(formats, isA<ScreenFormatDefaults>());
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

      test('should receive screen frames with correct format', () async {
        if (displays.isNotEmpty) {
          await context.configureDisplay(
            displays.first.deviceId,
            defaultFormats.$1,
          );

          MiniAVBuffer? receivedBuffer;
          await context.startCapture((buffer, userData) {
            receivedBuffer = buffer;
          });

          await Future.delayed(Duration(milliseconds: 300));
          await context.stopCapture();

          if (receivedBuffer != null) {
            expect(receivedBuffer!.dataSizeBytes, greaterThan(0));

            final videoBuffer = receivedBuffer!.data as MiniAVVideoBuffer;
            expect(videoBuffer, isNotNull);
            // Screen frame data should be substantial
            expect(receivedBuffer!.dataSizeBytes, greaterThan(1000));
          }
        }
      });

      test('should handle context destruction during capture', () async {
        if (displays.isNotEmpty) {
          await context.configureDisplay(
            displays.first.deviceId,
            defaultFormats.$1,
          );
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

      test('should support different display resolutions', () async {
        if (displays.length > 1) {
          // Test with different display if available
          final display1Formats = await MiniScreen.getDefaultFormats(
            displays[0].deviceId,
          );
          final display2Formats = await MiniScreen.getDefaultFormats(
            displays[1].deviceId,
          );

          await context.configureDisplay(
            displays[0].deviceId,
            display1Formats.$1,
          );
          final configuredFormats1 = await context.getConfiguredFormats();

          await context.configureDisplay(
            displays[1].deviceId,
            display2Formats.$1,
          );
          final configuredFormats2 = await context.getConfiguredFormats();

          expect(configuredFormats1.$1.width, equals(display1Formats.$1.width));
          expect(configuredFormats2.$1.width, equals(display2Formats.$1.width));
        }
      });

      test('should support different frame rates', () async {
        if (displays.isNotEmpty) {
          // Test with modified frame rate
          final customFormat = MiniAVVideoInfo(
            width: defaultFormats.$1.width,
            height: defaultFormats.$1.height,
            pixelFormat: defaultFormats.$1.pixelFormat,
            frameRateNumerator: 30,
            frameRateDenominator: 1,
            outputPreference: defaultFormats.$1.outputPreference,
          );

          await context.configureDisplay(displays.first.deviceId, customFormat);
          final configuredFormats = await context.getConfiguredFormats();

          expect(configuredFormats.$1.frameRateNumerator, equals(30));
          expect(configuredFormats.$1.frameRateDenominator, equals(1));
        }
      });
    });

    group('Screen Capture Permission Tests', () {
      test('should handle screen capture permission requirements', () async {
        // Screen capture often requires special permissions
        final displays = await MiniScreen.enumerateDisplays();
        if (displays.isNotEmpty) {
          final context = await MiniScreen.createContext();
          try {
            final formats = await MiniScreen.getDefaultFormats(
              displays.first.deviceId,
            );
            await context.configureDisplay(displays.first.deviceId, formats.$1);

            // Attempting to start capture might require permissions
            await context.startCapture((buffer, userData) {});
            await context.stopCapture();
          } catch (e) {
            // Permission denied or screen capture not available is acceptable
            expect(e, isException);
          } finally {
            await context.destroy();
          }
        }
      });

      test('should handle window capture permission requirements', () async {
        final windows = await MiniScreen.enumerateWindows();
        final displays = await MiniScreen.enumerateDisplays();
        if (windows.isNotEmpty && displays.isNotEmpty) {
          final context = await MiniScreen.createContext();
          try {
            final formats = await MiniScreen.getDefaultFormats(
              displays.first.deviceId,
            );
            await context.configureWindow(windows.first.deviceId, formats.$1);

            await context.startCapture((buffer, userData) {});
            await context.stopCapture();
          } catch (e) {
            // Permission issues are common with window capture
            expect(e, isException);
          } finally {
            await context.destroy();
          }
        }
      });
    });

    group('Multi-Display Tests', () {
      test('should handle multiple displays independently', () async {
        final displays = await MiniScreen.enumerateDisplays();

        for (final display in displays) {
          final formats = await MiniScreen.getDefaultFormats(display.deviceId);
          expect(formats.$1.width, greaterThan(0));
          expect(formats.$1.height, greaterThan(0));
        }
      });

      test('should detect display properties correctly', () async {
        final displays = await MiniScreen.enumerateDisplays();

        for (final display in displays) {
          expect(display.deviceId, isNotEmpty);
          expect(display.name, isNotEmpty);

          final formats = await MiniScreen.getDefaultFormats(display.deviceId);
          // Display resolutions should be reasonable
          expect(
            formats.$1.width,
            inInclusiveRange(640, 7680),
          ); // From VGA to 8K
          expect(formats.$1.height, inInclusiveRange(480, 4320));
        }
      });
    });

    group('Integration Tests', () {
      test('should work with multiple contexts simultaneously', () async {
        final displays = await MiniScreen.enumerateDisplays();
        if (displays.length >= 2) {
          final context1 = await MiniScreen.createContext();
          final context2 = await MiniScreen.createContext();

          try {
            final formats1 = await MiniScreen.getDefaultFormats(
              displays[0].deviceId,
            );
            final formats2 = await MiniScreen.getDefaultFormats(
              displays[1].deviceId,
            );

            await context1.configureDisplay(displays[0].deviceId, formats1.$1);
            await context2.configureDisplay(displays[1].deviceId, formats2.$1);

            final configuredFormats1 = await context1.getConfiguredFormats();
            final configuredFormats2 = await context2.getConfiguredFormats();

            expect(configuredFormats1.$1.width, equals(formats1.$1.width));
            expect(configuredFormats2.$1.width, equals(formats2.$1.width));
          } finally {
            await context1.destroy();
            await context2.destroy();
          }
        }
      });

      test('should handle rapid create/destroy cycles', () async {
        for (int i = 0; i < 3; i++) {
          final context = await MiniScreen.createContext();
          await context.destroy();
        }
      });

      test('should enumerate displays consistently', () async {
        final displays1 = await MiniScreen.enumerateDisplays();
        final displays2 = await MiniScreen.enumerateDisplays();

        // Display lists should be consistent
        expect(displays1.length, equals(displays2.length));
        if (displays1.isNotEmpty && displays2.isNotEmpty) {
          expect(displays1.first.deviceId, equals(displays2.first.deviceId));
        }
      });

      test('should enumerate windows consistently', () async {
        final windows1 = await MiniScreen.enumerateWindows();
        final windows2 = await MiniScreen.enumerateWindows();

        // Window lists might change but should be consistent within short timeframe
        expect(windows1, isA<List<MiniAVDeviceInfo>>());
        expect(windows2, isA<List<MiniAVDeviceInfo>>());
      });
    });

    group('Performance Tests', () {
      test('should enumerate displays quickly', () async {
        final stopwatch = Stopwatch()..start();
        await MiniScreen.enumerateDisplays();
        stopwatch.stop();

        expect(stopwatch.elapsedMilliseconds, lessThan(5000));
      });

      test('should enumerate windows quickly', () async {
        final stopwatch = Stopwatch()..start();
        await MiniScreen.enumerateWindows();
        stopwatch.stop();

        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(10000),
        ); // Windows enumeration can be slower
      });

      test('should create context quickly', () async {
        final stopwatch = Stopwatch()..start();
        final context = await MiniScreen.createContext();
        stopwatch.stop();

        expect(stopwatch.elapsedMilliseconds, lessThan(2000));
        await context.destroy();
      });

      test('should configure context quickly', () async {
        final displays = await MiniScreen.enumerateDisplays();
        if (displays.isNotEmpty) {
          final context = await MiniScreen.createContext();
          final formats = await MiniScreen.getDefaultFormats(
            displays.first.deviceId,
          );

          final stopwatch = Stopwatch()..start();
          await context.configureDisplay(displays.first.deviceId, formats.$1);
          stopwatch.stop();

          expect(stopwatch.elapsedMilliseconds, lessThan(2000));
          await context.destroy();
        }
      });

      test('should start capture within reasonable time', () async {
        final displays = await MiniScreen.enumerateDisplays();
        if (displays.isNotEmpty) {
          final context = await MiniScreen.createContext();
          final formats = await MiniScreen.getDefaultFormats(
            displays.first.deviceId,
          );
          await context.configureDisplay(displays.first.deviceId, formats.$1);

          final stopwatch = Stopwatch()..start();
          try {
            await context.startCapture((buffer, userData) {});
            stopwatch.stop();
            expect(
              stopwatch.elapsedMilliseconds,
              lessThan(5000),
            ); // Screen capture can be slower
            await context.stopCapture();
          } catch (e) {
            // Permission issues are acceptable
            expect(e, isException);
          } finally {
            await context.destroy();
          }
        }
      });
    });

    group('Format Validation Tests', () {
      test('should validate screen capture formats', () async {
        final displays = await MiniScreen.enumerateDisplays();
        if (displays.isNotEmpty) {
          final formats = await MiniScreen.getDefaultFormats(
            displays.first.deviceId,
          );

          // Screen capture resolutions should be reasonable
          expect(formats.$1.width, inInclusiveRange(640, 7680));
          expect(formats.$1.height, inInclusiveRange(480, 4320));
          expect(formats.$1.frameRateNumerator, inInclusiveRange(1, 120));
          expect(formats.$1.frameRateDenominator, greaterThan(0));
          expect(formats.$1.pixelFormat, isNot(MiniAVPixelFormat.unknown));
        }
      });

      test('should handle common screen formats', () async {
        final displays = await MiniScreen.enumerateDisplays();
        if (displays.isNotEmpty) {
          final formats = await MiniScreen.getDefaultFormats(
            displays.first.deviceId,
          );

          // Should support common screen capture formats
          final acceptableFormats = [
            MiniAVPixelFormat.rgb24,
            MiniAVPixelFormat.bgr24,
            MiniAVPixelFormat.rgba32,
            MiniAVPixelFormat.bgra32,
            MiniAVPixelFormat.nv12,
            MiniAVPixelFormat.yuv420_10bit,
          ];

          expect(acceptableFormats, contains(formats.$1.pixelFormat));
        }
      });
    });
  });
}
