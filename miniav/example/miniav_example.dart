import 'package:miniav/miniav.dart';
import 'dart:async';

void main() async {
  print('🎥 MiniAV Example - Opening all stream types');

  // Set log level for debugging
  MiniAV.setLogLevel(MiniAVLogLevel.info);

  // Storage for contexts to clean up later
  final contexts = <String, dynamic>{};

  try {
    // 1. Camera Stream
    await setupCameraStream(contexts);

    // 2. Screen Capture Stream
    // await setupScreenStream(contexts);

    // 3. Audio Input Stream
    // await setupAudioInputStream(contexts);

    // 4. Loopback Audio Stream
    //  await setupLoopbackStream(contexts);

    print('\n✅ All streams started successfully!');
    print('🔄 Capturing for 10 seconds...\n');

    // Let it run for 10 seconds
    await Future.delayed(Duration(seconds: 10));
  } catch (e, stackTrace) {
    print('❌ Error: $e');
    print('Stack trace: $stackTrace');
  } finally {
    // Clean up all contexts
    await cleanupAllStreams(contexts);
    print('\n🧹 All streams cleaned up');
    MiniAV.dispose();
  }
}

Future<void> setupCameraStream(Map<String, dynamic> contexts) async {
  print('📹 Setting up camera stream...');

  try {
    // Enumerate camera devices
    final cameras = await MiniCamera.enumerateDevices();
    if (cameras.isEmpty) {
      print('⚠️  No cameras found');
      return;
    }

    print('📱 Found ${cameras.length} camera(s):');
    for (int i = 0; i < cameras.length; i++) {
      final camera = cameras[i];
      print(
        '  $i: ${camera.name} (${camera.deviceId}) ${camera.isDefault ? '[DEFAULT]' : ''}',
      );
    }

    // Use first camera
    final selectedCamera = cameras[1];
    final format = await MiniCamera.getDefaultFormat(selectedCamera.deviceId);

    print('🎯 Using camera: ${selectedCamera.name}');
    print(
      '📐 Format: ${format.width}x${format.height} @ ${format.frameRateNumerator}/${format.frameRateDenominator} FPS',
    );

    // Create and configure context
    final context = await MiniCamera.createContext();
    await context.configure(selectedCamera.deviceId, format);
    contexts['camera'] = context;

    // Start capture
    int frameCount = 0;
    await context.startCapture((buffer, userData) {
      frameCount++;
      print(
        '📹 Camera frame #$frameCount - ${buffer.dataSizeBytes} bytes - ${buffer.timestampUs}µs',
      );
      MiniAV.releaseBuffer(buffer); // Release buffer after processing
    });

    print('✅ Camera stream started');
  } catch (e) {
    print('❌ Camera setup failed: $e');
  }
}

Future<void> setupScreenStream(Map<String, dynamic> contexts) async {
  print('\n🖥️  Setting up screen capture stream...');

  try {
    // Enumerate displays
    final displays = await MiniScreen.enumerateDisplays();
    if (displays.isEmpty) {
      print('⚠️  No displays found');
      return;
    }

    print('🖥️  Found ${displays.length} display(s):');
    for (int i = 0; i < displays.length; i++) {
      final display = displays[i];
      print(
        '  $i: ${display.name} (${display.deviceId}) ${display.isDefault ? '[DEFAULT]' : ''}',
      );
    }

    // Use first display
    final selectedDisplay = displays.first;
    final formats = await MiniScreen.getDefaultFormats(
      selectedDisplay.deviceId,
    );
    var videoFormat = formats.$1; // Video format
    final audioFormat = formats.$2; // Audio format (may be null)

    print('🎯 Using display: ${selectedDisplay.name}');
    print(
      '📐 Format: ${videoFormat.width}x${videoFormat.height} @ ${videoFormat.frameRateNumerator}/${videoFormat.frameRateDenominator} FPS',
    );
    if (audioFormat != null) {
      print(
        '🔊 Audio: ${audioFormat.channels}ch ${audioFormat.sampleRate}Hz ${audioFormat.format}',
      );
    }

    // Create and configure context
    final context = await MiniScreen.createContext();
    MiniAVVideoInfo newFormat = MiniAVVideoInfo(
      width: videoFormat.width,
      height: videoFormat.height,
      frameRateNumerator: videoFormat.frameRateNumerator,
      frameRateDenominator: videoFormat.frameRateDenominator,
      pixelFormat: videoFormat.pixelFormat,
      outputPreference: MiniAVOutputPreference.gpu,
    );
    await context.configureDisplay(
      selectedDisplay.deviceId,
      newFormat,
      captureAudio: audioFormat != null,
    );
    contexts['screen'] = context;

    // Start capture
    int screenFrameCount = 0;
    int audioFrameCount = 0;
    await context.startCapture((buffer, userData) {
      if (buffer.type == MiniAVBufferType.video) {
        screenFrameCount++;
        print(
          '🖥️  Screen frame #$screenFrameCount - ${buffer.dataSizeBytes} bytes - ${buffer.timestampUs}µs',
        );
        final rawData = (buffer.data as MiniAVVideoBuffer).planes[0];
        print(
          '  Raw data: ${rawData!.length} bytes, first 10 bytes: ${rawData.take(10).join(', ')}',
        );
        MiniAV.releaseBuffer(buffer); // Release video buffer after processing
      } else if (buffer.type == MiniAVBufferType.audio) {
        audioFrameCount++;
        print(
          '🔊 Screen audio frame #$audioFrameCount - ${buffer.dataSizeBytes} bytes - ${buffer.timestampUs}µs',
        );
      }
    });

    print('✅ Screen capture started');
  } catch (e) {
    print('❌ Screen capture setup failed: $e');
  }
}

Future<void> setupAudioInputStream(Map<String, dynamic> contexts) async {
  print('\n🎤 Setting up audio input stream...');

  try {
    // Enumerate audio input devices
    final audioDevices = await MiniAudioInput.enumerateDevices();
    if (audioDevices.isEmpty) {
      print('⚠️  No audio input devices found');
      return;
    }

    print('🎤 Found ${audioDevices.length} audio input device(s):');
    for (int i = 0; i < audioDevices.length; i++) {
      final device = audioDevices[i];
      print(
        '  $i: ${device.name} (${device.deviceId}) ${device.isDefault ? '[DEFAULT]' : ''}',
      );
    }

    // Use first audio device
    final selectedDevice = audioDevices.first;
    final format = await MiniAudioInput.getDefaultFormat(
      selectedDevice.deviceId,
    );

    print('🎯 Using audio device: ${selectedDevice.name}');
    print(
      '🔊 Format: ${format.channels}ch ${format.sampleRate}Hz ${format.format} (${format.numFrames} frames)',
    );

    // Create and configure context
    final context = await MiniAudioInput.createContext();
    await context.configure(selectedDevice.deviceId, format);
    contexts['audioInput'] = context;

    // Start capture
    int bufferCount = 0;
    await context.startCapture((buffer, userData) {
      bufferCount++;

      print(
        '🎤 Audio buffer #$bufferCount - ${buffer.dataSizeBytes} bytes - ${buffer.timestampUs}µs',
      );
      MiniAV.releaseBuffer(buffer); // Release buffer after processing
    });

    print('✅ Audio input stream started');
  } catch (e) {
    print('❌ Audio input setup failed: $e');
  }
}

Future<void> setupLoopbackStream(Map<String, dynamic> contexts) async {
  print('\n🔄 Setting up loopback audio stream...');

  try {
    // Enumerate loopback devices
    final loopbackDevices = await MiniLoopback.enumerateDevices();
    if (loopbackDevices.isEmpty) {
      print(
        '⚠️  No loopback devices found (may not be supported on this platform)',
      );
      return;
    }

    print('🔄 Found ${loopbackDevices.length} loopback device(s):');
    for (int i = 0; i < loopbackDevices.length; i++) {
      final device = loopbackDevices[i];
      print(
        '  $i: ${device.name} (${device.deviceId}) ${device.isDefault ? '[DEFAULT]' : ''}',
      );
    }

    // Use first loopback device
    final selectedDevice = loopbackDevices[4];
    final format = await MiniLoopback.getDefaultFormat(selectedDevice.deviceId);

    print('🎯 Using loopback device: ${selectedDevice.name}');
    print(
      '🔊 Format: ${format.channels}ch ${format.sampleRate}Hz ${format.format} (${format.numFrames} frames)',
    );

    // Create and configure context
    final context = await MiniLoopback.createContext();
    await context.configure(selectedDevice.deviceId, format);
    contexts['loopback'] = context;

    // Start capture
    int bufferCount = 0;
    await context.startCapture((buffer, userData) {
      bufferCount++;
      print(
        '🔄 Loopback buffer #$bufferCount - ${buffer.dataSizeBytes} bytes - ${buffer.timestampUs}µs ',
      );
      //MiniAV.releaseBuffer(buffer); // Release buffer after processing
    });

    print('✅ Loopback stream started');
  } catch (e) {
    print('❌ Loopback setup failed: $e');
    if (e.toString().contains('UnsupportedError')) {
      print('ℹ️  Loopback capture is not supported on this platform');
    }
  }
}

Future<void> cleanupAllStreams(Map<String, dynamic> contexts) async {
  print('\n🛑 Stopping all streams...');

  final cleanupTasks = <Future>[];

  for (final entry in contexts.entries) {
    final name = entry.key;
    final context = entry.value;

    print('🛑 Stopping $name...');

    cleanupTasks.add(
      Future(() async {
        try {
          if (context is MiniCameraContext) {
            await context.stopCapture();
            await context.destroy();
          } else if (context is MiniScreenContext) {
            await context.stopCapture();
            await context.destroy();
          } else if (context is MiniAudioInputContext) {
            await context.stopCapture();
            await context.destroy();
          } else if (context is MiniLoopbackContext) {
            await context.stopCapture();
            await context.destroy();
          }
          print('✅ $name stopped');
        } catch (e) {
          print('❌ Error stopping $name: $e');
        }
      }),
    );
  }

  // Wait for all cleanup tasks to complete
  await Future.wait(cleanupTasks);
}
