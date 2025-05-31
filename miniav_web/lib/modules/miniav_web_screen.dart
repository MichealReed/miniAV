part of '../miniav_web.dart';

/// Web implementation of [MiniScreenPlatformInterface]
class MiniAVWebScreenPlatform implements MiniScreenPlatformInterface {
  @override
  Future<List<MiniAVDeviceInfo>> enumerateDisplays() async {
    // Web doesn't provide display enumeration
    // Return a generic display option
    return [
      MiniAVDeviceInfo(deviceId: 'screen', name: 'Screen', isDefault: true),
    ];
  }

  @override
  Future<List<MiniAVDeviceInfo>> enumerateWindows() async {
    // Web doesn't support window enumeration
    return [];
  }

  @override
  Future<ScreenFormatDefaults> getDefaultFormats(String displayId) async {
    final videoFormat = MiniAVVideoInfo(
      width: 1920,
      height: 1080,
      pixelFormat: MiniAVPixelFormat.rgba32,
      frameRateNumerator: 30,
      frameRateDenominator: 1,
      outputPreference: MiniAVOutputPreference.cpu,
    );

    // Web doesn't support system audio capture with screen sharing
    return (videoFormat, null);
  }

  @override
  Future<MiniScreenContextPlatformInterface> createContext() async {
    return MiniAVWebScreenContext();
  }
}

/// Web implementation of [MiniScreenContextPlatformInterface]
class MiniAVWebScreenContext implements MiniScreenContextPlatformInterface {
  web.MediaStream? _mediaStream;
  web.HTMLVideoElement? _videoElement;
  web.HTMLCanvasElement? _canvas;
  web.CanvasRenderingContext2D? _context;
  Timer? _captureTimer;
  StreamController<MiniAVBuffer>? _bufferController;

  MiniAVVideoInfo? _currentVideoFormat;

  @override
  Future<void> configureDisplay(
    String screenId,
    MiniAVVideoInfo format, {
    bool captureAudio = false,
  }) async {
    await destroy();

    // Create display media options using the proper web API types
    final options = web.DisplayMediaStreamOptions(
      video: _createVideoConstraints(format),
      audio: captureAudio.toJS,
    );

    try {
      _mediaStream =
          await web.window.navigator.mediaDevices
              .getDisplayMedia(options)
              .toDart;

      // Create video element for capturing frames
      _videoElement =
          web.document.createElement('video') as web.HTMLVideoElement
            ..srcObject = _mediaStream
            ..autoplay = true
            ..muted = true;

      // Create canvas for frame extraction
      _canvas =
          web.document.createElement('canvas') as web.HTMLCanvasElement
            ..width = format.width
            ..height = format.height;
      _context = _canvas!.getContext('2d') as web.CanvasRenderingContext2D;

      // Wait for video to be ready
      final completer = Completer<void>();
      _videoElement!.onLoadedMetadata.listen((_) => completer.complete());
      await completer.future;

      _currentVideoFormat = format;
    } catch (e) {
      throw Exception('Failed to configure display capture: $e');
    }
  }

  @override
  Future<void> configureWindow(
    String windowId,
    MiniAVVideoInfo format, {
    bool captureAudio = false,
  }) async {
    throw UnsupportedError('Window capture not supported on web');
  }

  JSAny _createVideoConstraints(MiniAVVideoInfo format) {
    final constraints = <String, dynamic>{
      'width': {'ideal': format.width},
      'height': {'ideal': format.height},
      'frameRate': {
        'ideal': format.frameRateNumerator / format.frameRateDenominator,
      },
    };

    return constraints.jsify()!;
  }

  @override
  Future<ScreenFormatDefaults> getConfiguredFormats() async {
    if (_currentVideoFormat == null) {
      throw StateError('Screen context not configured');
    }
    // Web doesn't support audio capture with screen sharing
    return (_currentVideoFormat!, null);
  }

  @override
  Future<void> startCapture(
    void Function(MiniAVBuffer buffer, Object? userData) onFrame, {
    Object? userData,
  }) async {
    if (_mediaStream == null ||
        _videoElement == null ||
        _canvas == null ||
        _context == null) {
      throw StateError('Screen capture not configured');
    }

    await stopCapture(); // Clean up any previous capture

    _bufferController = StreamController<MiniAVBuffer>();

    // Capture frames at approximately 30 FPS
    _captureTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      _captureFrame(onFrame, userData);
    });
  }

  void _captureFrame(
    void Function(MiniAVBuffer buffer, Object? userData) onFrame,
    Object? userData,
  ) {
    if (_videoElement == null || _canvas == null || _context == null) {
      return;
    }

    try {
      // Draw current video frame to canvas
      _context!.drawImage(
        _videoElement!,
        0,
        0,
        _canvas!.width,
        _canvas!.height,
      );

      // Get image data from canvas
      final imageData = _context!.getImageData(
        0,
        0,
        _canvas!.width,
        _canvas!.height,
      );

      // Convert to MiniAV buffer
      final videoBuffer = _WebUtils._createVideoBufferFromImageData(imageData);

      final buffer = MiniAVBuffer(
        type: MiniAVBufferType.video,
        contentType: MiniAVBufferContentType.cpu,
        timestampUs: _WebUtils._getCurrentTimestampUs(),
        data: videoBuffer,
        dataSizeBytes: videoBuffer.planes.first?.length ?? 0,
      );

      try {
        onFrame(buffer, userData);
      } catch (e, s) {
        print('Error in screen capture user callback: $e\n$s');
      }
    } catch (e) {
      // Handle capture errors silently or log them
    }
  }

  @override
  Future<void> stopCapture() async {
    _captureTimer?.cancel();
    _captureTimer = null;

    _bufferController?.close();
    _bufferController = null;
  }

  @override
  Future<void> destroy() async {
    _mediaStream?.getTracks().toDart.forEach((track) => track.stop());
    _mediaStream = null;
    _videoElement = null;
    _canvas = null;
    _context = null;
  }
}
