# miniav

A Flutter library for cross-platform audio and video capture with high-performance buffer management and GPU integration support.

## Three Things to Know

1. Native assets compilation can take time, especially on first build. Run with -v to see build progress and errors.

2. This package uses dart native assets.
For flutter, you must be on the master channel and run
`flutter config --enable-native-assets`
For dart, each run must contain the
`--enable-experiment=native-assets` flag.

3. Platform-specific permissions are required for camera, microphone, and screen capture. See the Permissions section below for detailed setup instructions.

### Platform Support

| Module | Windows | Linux | macOS | Web | Android | iOS |
|--------|---------|-------|-------|-----|---------|-----|
| **Camera** | ✅ | ✅ | ✅ | ✅ | 🚧 | 🚧 |
| **Screen Capture** | ✅ | ✅ | ✅ | ✅ | 🚧 | 🚧 |
| **Audio Input** | ✅ | ✅ | ✅ | ✅ | 🚧 | 🚧 |
| **Audio Loopback** | ✅ | ✅ | ✅ 15+ | ❌ | ❌ | ❌ |

**Legend:** ✅ Supported • ❌ Not Available • 🚧 Planned

### Installation

Add the following to your `pubspec.yaml`:

```yaml
dependencies:
  miniav: ^0.1.0
```

Then run:

```shell
dart pub get
```

## Getting Started

```console
 git clone https://github.com/yourusername/miniav.git
 dart --enable-experiment=native-assets test

 dart:
 cd miniav
 dart --enable-experiment=native-assets example/miniav_example.dart

 flutter:
 cd miniav/example
 flutter config --enable-native-assets
 flutter run -d chrome/windows/linux
```

## Example

```dart
import 'package:miniav/miniav.dart';

Future<void> captureCamera() async {
  // Initialize MiniAV
  MiniAV.setLogLevel(MiniAVLogLevel.info);
  
  // Enumerate camera devices
  final cameras = await MiniCamera.enumerateDevices();
  if (cameras.isEmpty) {
    print('No cameras found');
    return;
  }
  
  // Use first camera
  final selectedCamera = cameras.first;
  final format = await MiniCamera.getDefaultFormat(selectedCamera.deviceId);
  
  print('Using camera: ${selectedCamera.name}');
  print('Format: ${format.width}x${format.height} @ ${format.frameRateNumerator}/${format.frameRateDenominator} FPS');
  
  // Create and configure context
  final context = await MiniCamera.createContext();
  await context.configure(selectedCamera.deviceId, format);
  
  // Start capture with callback
  int frameCount = 0;
  await context.startCapture((buffer, userData) {
    frameCount++;
    print('Camera frame #$frameCount - ${buffer.dataSizeBytes} bytes');
    
    // Process video data here
    if (buffer.type == MiniAVBufferType.video) {
      final videoBuffer = buffer.data as MiniAVVideoBuffer;
      final rawData = videoBuffer.planes[0];
      // Use raw pixel data for computer vision, GPU upload, etc.
    }
    
    // IMPORTANT: Release buffer when done
    MiniAV.releaseBuffer(buffer);
  });
  
  // Capture for 10 seconds
  await Future.delayed(Duration(seconds: 10));
  
  // Stop and cleanup
  await context.stopCapture();
  await context.destroy();
  MiniAV.dispose();
}
```

## Features

### Multi-Stream Capture

MiniAV supports simultaneous capture from multiple sources:

- **Camera**: Access webcams and external cameras
- **Screen**: Capture displays and windows with optional audio
- **Audio Input**: Record from microphones and audio devices  
- **Loopback Audio**: Capture system audio output (platform dependent)

### High-Performance Buffers

- **Zero-Copy Design**: Direct access to native buffers where possible
- **GPU Integration**: Ready for use with compute shaders and WebGPU
- **Explicit Release**: Manual buffer management prevents resource leaks
- **Multiple Formats**: Support for RGB, YUV, and compressed formats

### Cross-Platform APIs

```dart
// Camera capture
final cameras = await MiniCamera.enumerateDevices();
final context = await MiniCamera.createContext();

// Screen capture with audio
final displays = await MiniScreen.enumerateDisplays();
final screenContext = await MiniScreen.createContext();

// Audio input
final audioDevices = await MiniAudioInput.enumerateDevices();
final audioContext = await MiniAudioInput.createContext();

// System audio loopback (where supported)
final loopbackDevices = await MiniLoopback.enumerateDevices();
final loopbackContext = await MiniLoopback.createContext();
```

## Permissions

### macOS

Add to `macos/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app uses the camera for video capture</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app uses the microphone for audio recording</string>
```

For screen recording, manually enable in System Preferences > Security & Privacy > Privacy > Screen Recording.

### Windows

Camera and microphone access controlled via Windows 10+ Privacy Settings. Screen capture generally requires no special permissions for desktop applications.

### Linux

User must be in `video` and `audio` groups:

```bash
sudo usermod -a -G audio,video $USER
```

Install required development packages:

```bash
# Ubuntu/Debian
sudo apt install libasound2-dev libpulse-dev libpipewire-0.3-dev libv4l-dev

# Fedora
sudo dnf install alsa-lib-devel pulseaudio-libs-devel pipewire-devel libv4l-devel
```

### Web

Requires HTTPS for camera, microphone, and screen capture APIs. All capture requires user gesture and permission.

## Architecture

MiniAV follows a modular architecture:

- **miniav_platform_interface**: Abstract interface definitions
- **miniav_ffi**: Native implementation using FFI and C library
- **miniav_web**: Web implementation using browser APIs
- **miniav_c**: Core C library with platform-specific backends

### Buffer Management

MiniAV uses explicit buffer release for optimal performance:

```dart
await context.startCapture((buffer, userData) {
  // Process buffer data
  final videoData = buffer.data as MiniAVVideoBuffer;
  
  // Access raw pixel planes
  final plane0 = videoData.planes[0]; // Y plane for YUV, or RGB data
  final plane1 = videoData.planes[1]; // U plane for YUV
  final plane2 = videoData.planes[2]; // V plane for YUV
  
  // CRITICAL: Always release when done
  MiniAV.releaseBuffer(buffer);
});
```

### GPU Integration

Buffers can contain GPU handles for zero-copy workflows:

```dart
if (buffer.contentType == MiniAVBufferContentType.gpuD3D11Handle) {
  // Direct GPU texture handle (Windows)
  final gpuHandle = videoData.planes[0];
  // Pass to minigpu or other GPU library
}
```

## Advanced Usage

### Multiple Stream Synchronization

```dart
// Start multiple streams
await cameraContext.startCapture(onCameraFrame);
await audioContext.startCapture(onAudioFrame);

void synchronizeStreams(MiniAVBuffer cameraBuffer, MiniAVBuffer audioBuffer) {
  final timeDiff = cameraBuffer.timestampUs - audioBuffer.timestampUs;
  if (timeDiff.abs() < 16667) { // Within ~16ms for 60fps
    // Process synchronized frame
  }
}
```

### Custom Format Selection

```dart
final formats = await MiniCamera.getSupportedFormats(deviceId);
final preferredFormat = formats.firstWhere(
  (f) => f.width >= 1920 && f.pixelFormat == MiniAVPixelFormat.nv12,
  orElse: () => formats.first,
);
await context.configure(deviceId, preferredFormat);
```

### Error Handling

```dart
try {
  await context.startCapture(callback);
} on MiniAVException catch (e) {
  switch (e.code) {
    case MiniAVResultCode.errorNotSupported:
      // Handle unsupported operation
      break;
    case MiniAVResultCode.errorInvalidArg:
      // Handle invalid parameters
      break;
    default:
      print('Capture error: ${e.message}');
  }
}
```

## Performance Tips

1. **Release Buffers Promptly**: Delayed release can cause frame drops
2. **Use Appropriate Formats**: Choose formats matching your processing needs  
3. **Minimize Copies**: Prefer direct buffer access over copying data
4. **GPU Preference**: Set `outputPreference: gpu` for zero-copy workflows
5. **Background Processing**: Move heavy processing off the capture callback thread

## Dependencies

### Native Dependencies

- **Windows**: Media Foundation, DirectX 11, WASAPI
- **macOS**: AVFoundation, Core Graphics, Core Audio
- **Linux**: PipeWire

### Build Dependencies

- CMake 3.15+
- Platform-appropriate C++ compiler
- pkg-config (Linux)

## Troubleshooting

### Common Issues

**No devices found**: Check permissions and platform-specific requirements

**Frame drops**: Ensure timely buffer release and avoid blocking operations in callbacks

**Build failures**: Verify CMake version and platform dependencies are installed

**Permission denied**: Add user to required groups (Linux) or enable privacy settings

### Debug Logging

```dart
MiniAV.setLogLevel(MiniAVLogLevel.debug);
MiniAV.setLogCallback((level, message) {
  print('[$level] $message');
});
```
