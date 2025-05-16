import 'dart:async';
import 'package:test/test.dart';
import 'package:miniav_platform_interface/miniav_platform_interface.dart';
import 'package:miniav_ffi/miniav_ffi.dart'; // Imports your FFI implementation

void main() {
  late MiniScreenPlatformInterface screen;

  setUpAll(() {
    screen = MiniAVFFIPlatform().screen;
    print('MiniAV FFI Screen Test Setup Complete.');
  });

  group('MiniAV Screen Platform Interface Tests', () {
    test('Enumerate Displays', () async {
      final displays = await screen.enumerateDisplays();
      expect(displays, isA<List<MiniAVDeviceInfo>>());
      print('Found ${displays.length} displays:');
      for (final display in displays) {
        print(
          '- ID: ${display.deviceId}, Name: ${display.name}, Default: ${display.isDefault}',
        );
        expect(display.deviceId, isNotEmpty);
        expect(display.name, isNotEmpty);
      }
    });

    test('Enumerate Windows', () async {
      final windows = await screen.enumerateWindows();
      expect(windows, isA<List<MiniAVDeviceInfo>>());
      print('Found ${windows.length} windows:');
      for (final window in windows) {
        print(
          '- ID: ${window.deviceId}, Name: ${window.name}, Default: ${window.isDefault}',
        );
        // Window IDs might be numeric handles, so isNotEmpty might not be the best check
        // depending on your C implementation. Name should ideally be non-empty.
        expect(window.deviceId, isNotNull); // Or isNotEmpty if it's a string
        expect(window.name, isNotEmpty);
      }
    });

    test('Get Default Formats (for the first available display)', () async {
      final displays = await screen.enumerateDisplays();
      if (displays.isEmpty) {
        print('No displays found to get default formats from.');
        return;
      }
      final firstDisplay = displays.first;
      print(
        'Attempting to get default formats for display: ${firstDisplay.name} (${firstDisplay.deviceId})',
      );

      final defaults = await screen.getDefaultFormats(firstDisplay.deviceId);
      expect(defaults, isA<ScreenFormatDefaults>());

      final videoFormat = defaults.$1;
      final audioFormat = defaults.$2;

      print('Default Video Format:');
      print(
        '- ${videoFormat.width}x${videoFormat.height} @ ${videoFormat.frameRateNumerator}/${videoFormat.frameRateDenominator}fps, PixelFormat: ${videoFormat.pixelFormat.name}, Preference: ${videoFormat.outputPreference.name}',
      );
      expect(videoFormat.width, greaterThan(0));
      expect(videoFormat.height, greaterThan(0));

      if (audioFormat != null) {
        print('Default Audio Format:');
        print(
          '- SampleRate: ${audioFormat.sampleRate}, Channels: ${audioFormat.channels}, Format: ${audioFormat.format.name}',
        );
        expect(audioFormat.sampleRate, greaterThan(0));
        expect(audioFormat.channels, greaterThan(0));
      } else {
        print(
          'No default audio format returned or audio capture not supported for this display.',
        );
      }
    });

    test('Create and Destroy Screen Context', () async {
      final context = await screen.createContext();
      expect(context, isNotNull);
      print('Screen context created: $context');
      await context.destroy();
      print('Screen context destroyed.');
    });

    group('Screen Context Operations', () {
      late MiniScreenContextPlatformInterface context;
      late List<MiniAVDeviceInfo> displays;
      late List<MiniAVDeviceInfo> windows;
      MiniAVVideoFormatInfo? defaultVideoFormat;

      setUp(() async {
        context = await screen.createContext();
        displays = await screen.enumerateDisplays();
        windows = await screen.enumerateWindows();
        if (displays.isNotEmpty) {
          final defaults = await screen.getDefaultFormats(
            displays.first.deviceId,
          );
          defaultVideoFormat = defaults.$1;
        }
      });

      tearDown(() async {
        await context.destroy();
      });

      test('Configure Display (first display, default format)', () async {
        if (displays.isEmpty) {
          print('No displays to configure.');
          return;
        }
        if (defaultVideoFormat == null) {
          print('No default video format to configure display with.');
          return;
        }
        final firstDisplay = displays.first;
        print(
          'Configuring display ${firstDisplay.name} with format ${defaultVideoFormat!.width}x${defaultVideoFormat!.height}',
        );

        await context.configureDisplay(
          firstDisplay.deviceId,
          defaultVideoFormat!,
          captureAudio: false, // Or true, if you want to test audio
        );
        print('Display configured successfully.');

        final configured = await context.getConfiguredFormats();
        expect(configured.$1.width, defaultVideoFormat!.width);
        expect(configured.$1.height, defaultVideoFormat!.height);
        // Add more checks for pixel format, etc. if necessary
      });

      test(
        'Configure Window (first window, default format from first display)',
        () async {
          if (windows.isEmpty) {
            print('No windows to configure.');
            return;
          }
          if (defaultVideoFormat == null) {
            print('No default video format to configure window with.');
            return;
          }
          final firstWindow = windows.first;
          print(
            'Configuring window ${firstWindow.name} (${firstWindow.deviceId}) with format ${defaultVideoFormat!.width}x${defaultVideoFormat!.height}',
          );

          await context.configureWindow(
            firstWindow.deviceId, // Window ID
            defaultVideoFormat!,
            captureAudio: false,
          );
          print('Window configured successfully.');

          final configured = await context.getConfiguredFormats();
          // Note: Window capture might resize to the window's actual dimensions,
          // so exact match with defaultVideoFormat might not always hold.
          // Check if width/height are reasonable.
          expect(configured.$1.width, greaterThan(0));
          expect(configured.$1.height, greaterThan(0));
        },
      );

      test(
        'Start and Stop Screen Capture (receives at least one frame)',
        () async {
          if (displays.isEmpty) {
            print('No displays to capture from.');
            return;
          }
          if (defaultVideoFormat == null) {
            print('No default video format to start capture with.');
            return;
          }

          final firstDisplay = displays.first;
          await context.configureDisplay(
            firstDisplay.deviceId,
            defaultVideoFormat!,
            captureAudio: false,
          );
          print(
            'Configured for display capture: ${defaultVideoFormat!.width}x${defaultVideoFormat!.height}',
          );

          final frameReceivedCompleter = Completer<void>();
          int frameCount = 0;

          await context.startCapture((buffer, userData) {
            frameCount++;
            print(
              '[Test Callback] Screen Frame received! Count: $frameCount, Type: ${buffer.type.name}, Content: ${buffer.contentType.name}, Size: ${buffer.dataSizeBytes}',
            );
            if (buffer.data is MiniAVVideoBuffer) {
              final videoData = buffer.data as MiniAVVideoBuffer;
              print(
                '  Video: ${videoData.width}x${videoData.height}, Format: ${videoData.pixelFormat.name}',
              );
            } else if (buffer.data is MiniAVAudioBuffer) {
              final audioData = buffer.data as MiniAVAudioBuffer;
              print(
                '  Audio: ${audioData.info.sampleRate}Hz, ${audioData.info.channels}ch, Frames: ${audioData.frameCount}',
              );
            }

            if (!frameReceivedCompleter.isCompleted) {
              frameReceivedCompleter.complete();
            }
          });

          print('Screen capture started. Waiting for frame...');
          await frameReceivedCompleter.future.timeout(
            const Duration(
              seconds: 15,
            ), // Screen capture can sometimes be slower to start
            onTimeout: () {
              throw TimeoutException(
                'Timeout: No screen frame received within 15 seconds.',
              );
            },
          );

          expect(
            frameCount,
            greaterThan(0),
            reason: 'Expected at least one screen frame to be received.',
          );
          print('Screen capture test successful: Received $frameCount frames.');

          await context.stopCapture();
          print('Screen capture stopped.');
        },
        timeout: const Timeout(Duration(seconds: 20)),
      ); // Longer timeout for the whole test
      test(
        'Start and Stop Screen Capture WITH AUDIO (receives video and audio frames)',
        () async {
          if (displays.isEmpty) {
            print('No displays to capture from for audio test.');
            return;
          }
          if (defaultVideoFormat == null) {
            print(
              'No default video format to start capture with for audio test.',
            );
            return;
          }

          final firstDisplay = displays.first;
          // IMPORTANT: Enable audio capture
          await context.configureDisplay(
            firstDisplay.deviceId,
            defaultVideoFormat!,
            captureAudio: true,
          );
          print(
            'Configured for display capture WITH AUDIO: ${defaultVideoFormat!.width}x${defaultVideoFormat!.height}',
          );

          final videoFrameReceivedCompleter = Completer<void>();
          final audioFrameReceivedCompleter = Completer<void>();
          int videoFrameCount = 0;
          int audioFrameCount = 0;

          await context.startCapture((buffer, userData) {
            print(
              '[Test Callback - Audio Test] Frame received! Type: ${buffer.type.name}, Content: ${buffer.contentType.name}, Size: ${buffer.dataSizeBytes}',
            );
            if (buffer.type == MiniAVBufferType.video) {
              videoFrameCount++;
              final videoData = buffer.data as MiniAVVideoBuffer;
              print(
                '  Video: ${videoData.width}x${videoData.height}, Format: ${videoData.pixelFormat.name}',
              );
              if (!videoFrameReceivedCompleter.isCompleted) {
                videoFrameReceivedCompleter.complete();
              }
            } else if (buffer.type == MiniAVBufferType.audio) {
              audioFrameCount++;
              final audioData = buffer.data as MiniAVAudioBuffer;
              print(
                '  Audio: ${audioData.info.sampleRate}Hz, ${audioData.info.channels}ch, Frames: ${audioData.frameCount}, Format: ${audioData.info.format.name}',
              );
              if (!audioFrameReceivedCompleter.isCompleted) {
                audioFrameReceivedCompleter.complete();
              }
            }
          });

          print('Screen capture WITH AUDIO started. Waiting for frames...');

          try {
            await Future.wait([
              videoFrameReceivedCompleter.future,
              audioFrameReceivedCompleter.future,
            ]).timeout(
              const Duration(seconds: 20), // Increased timeout for audio
              onTimeout: () {
                if (!videoFrameReceivedCompleter.isCompleted) {
                  print(
                    'Timeout: No VIDEO screen frame received within 20 seconds.',
                  );
                }
                if (!audioFrameReceivedCompleter.isCompleted) {
                  print(
                    'Timeout: No AUDIO screen frame received within 20 seconds.',
                  );
                }
                // Re-throw to make the test fail if not both are completed.
                // The specific error will depend on which completer timed out first
                // if Future.wait is used, or we can check individually.
                throw TimeoutException(
                  'Timeout: Did not receive both video and audio frames within 20 seconds. Video Frames: $videoFrameCount, Audio Frames: $audioFrameCount',
                );
              },
            );
          } catch (e) {
            print('Error during frame waiting: $e');
            if (videoFrameCount == 0) {
              fail('No video frames received. Error: $e');
            }
            if (audioFrameCount == 0) {
              // This is the key check for this test.
              // You might want to check your C++ logs if this fails.
              fail(
                'No audio frames received. Error: $e. Check C++ logs for loopback audio issues.',
              );
            }
            // If both are >0 but timeout still occurred (unlikely with Future.wait logic), rethrow.
            if (e is TimeoutException &&
                (videoFrameCount == 0 || audioFrameCount == 0)) {
              // Already handled by specific fails above.
            } else if (e is TimeoutException) {
              // This case means both completers finished but the overall Future.wait timed out,
              // which shouldn't happen if completers are the only await points.
              // Or, one completed and the other didn't, leading to the timeout.
              // The message in TimeoutException above should cover this.
            } else {
              rethrow; // Rethrow other unexpected errors
            }
          }

          expect(
            videoFrameCount,
            greaterThan(0),
            reason: 'Expected at least one video screen frame to be received.',
          );
          expect(
            audioFrameCount,
            greaterThan(0),
            reason:
                'Expected at least one audio screen frame to be received for audio test.',
          );
          print(
            'Screen capture WITH AUDIO test successful: Received $videoFrameCount video frames and $audioFrameCount audio frames.',
          );

          await context.stopCapture();
          print('Screen capture WITH AUDIO stopped.');
        },
        timeout: const Timeout(Duration(seconds: 25)),
      ); // Longer timeout for the whole test
    });
  });
}
