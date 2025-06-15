part of '../miniav_web.dart';

/// Web implementation of [MiniCameraPlatformInterface]
class MiniAVWebCameraPlatform implements MiniCameraPlatformInterface {
  @override
  Future<List<MiniAVDeviceInfo>> enumerateDevices() async {
    try {
      final constraints = web.MediaStreamConstraints(video: true.toJS);

      // Request permission to access video devices
      await web.window.navigator.mediaDevices.getUserMedia(constraints).toDart;

      final devices = await web.window.navigator.mediaDevices
          .enumerateDevices()
          .toDart;
      final videoDevices = <MiniAVDeviceInfo>[];

      for (final device in devices.toDart) {
        if (device.kind == 'videoinput') {
          videoDevices.add(
            MiniAVDeviceInfo(
              deviceId: device.deviceId,
              name: device.label.isNotEmpty
                  ? device.label
                  : 'Camera ${videoDevices.length + 1}',
              isDefault: videoDevices.isEmpty, // First device as default
            ),
          );
        }
      }

      return videoDevices;
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<MiniAVVideoInfo>> getSupportedFormats(String deviceId) async {
    // Web doesn't provide detailed format enumeration
    // Return common web-supported formats
    return [
      MiniAVVideoInfo(
        width: 640,
        height: 480,
        pixelFormat: MiniAVPixelFormat.rgba32,
        frameRateNumerator: 30,
        frameRateDenominator: 1,
        outputPreference: MiniAVOutputPreference.cpu,
      ),
      MiniAVVideoInfo(
        width: 1280,
        height: 720,
        pixelFormat: MiniAVPixelFormat.rgba32,
        frameRateNumerator: 30,
        frameRateDenominator: 1,
        outputPreference: MiniAVOutputPreference.cpu,
      ),
      MiniAVVideoInfo(
        width: 1920,
        height: 1080,
        pixelFormat: MiniAVPixelFormat.rgba32,
        frameRateNumerator: 30,
        frameRateDenominator: 1,
        outputPreference: MiniAVOutputPreference.cpu,
      ),
    ];
  }

  @override
  Future<MiniAVVideoInfo> getDefaultFormat(String deviceId) async {
    return MiniAVVideoInfo(
      width: 640,
      height: 480,
      pixelFormat: MiniAVPixelFormat.rgba32,
      frameRateNumerator: 30,
      frameRateDenominator: 1,
      outputPreference: MiniAVOutputPreference.cpu,
    );
  }

  @override
  Future<MiniCameraContextPlatformInterface> createContext() async {
    return MiniAVWebCameraContext();
  }
}

/// Web implementation of [MiniCameraContextPlatformInterface]
class MiniAVWebCameraContext implements MiniCameraContextPlatformInterface {
  web.MediaStream? _mediaStream;
  web.HTMLVideoElement? _videoElement;
  web.HTMLCanvasElement? _canvas;
  web.CanvasRenderingContext2D? _context;
  Timer? _captureTimer;
  StreamController<MiniAVBuffer>? _bufferController;

  MiniAVVideoInfo? _currentFormat;

  @override
  Future<void> configure(String deviceId, MiniAVVideoInfo format) async {
    await destroy();

    // Create constraints using the proper web API types
    final constraints = web.MediaStreamConstraints(
      video: _createVideoConstraints(deviceId, format),
    );

    try {
      _mediaStream = await web.window.navigator.mediaDevices
          .getUserMedia(constraints)
          .toDart;

      // Create video element for capturing frames
      _videoElement =
          web.document.createElement('video') as web.HTMLVideoElement
            ..srcObject = _mediaStream
            ..autoplay = true
            ..muted = true;

      // Create canvas for frame extraction
      _canvas = web.document.createElement('canvas') as web.HTMLCanvasElement
        ..width = format.width
        ..height = format.height;
      _context = _canvas!.getContext('2d') as web.CanvasRenderingContext2D;

      // Wait for video to be ready
      final completer = Completer<void>();
      _videoElement!.onLoadedMetadata.listen((_) => completer.complete());
      await completer.future;

      _currentFormat = format;
    } catch (e) {
      throw Exception('Failed to configure camera: $e');
    }
  }

  JSAny _createVideoConstraints(String deviceId, MiniAVVideoInfo format) {
    final constraints = <String, dynamic>{
      'width': {'ideal': format.width},
      'height': {'ideal': format.height},
      'frameRate': {
        'ideal': format.frameRateNumerator / format.frameRateDenominator,
      },
    };

    if (deviceId.isNotEmpty) {
      constraints['deviceId'] = {'exact': deviceId};
    }

    return constraints.jsify()!;
  }

  @override
  Future<MiniAVVideoInfo> getConfiguredFormat() async {
    if (_currentFormat == null) {
      throw StateError('Camera context not configured');
    }
    return _currentFormat!;
  }

  @override
  Future<void> startCapture(
    void Function(MiniAVBuffer buffer, Object? userData) onData, {
    Object? userData,
  }) async {
    if (_mediaStream == null ||
        _videoElement == null ||
        _canvas == null ||
        _context == null) {
      throw StateError('Camera not configured');
    }

    await stopCapture(); // Clean up any previous capture

    _bufferController = StreamController<MiniAVBuffer>();

    // Capture frames at approximately 30 FPS
    _captureTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      _captureFrame(onData, userData);
    });
  }

  void _captureFrame(
    void Function(MiniAVBuffer buffer, dynamic userData) onData,
    dynamic userData,
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
        onData(buffer, userData);
      } catch (e, s) {
        print('Error in camera user callback: $e\n$s');
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
