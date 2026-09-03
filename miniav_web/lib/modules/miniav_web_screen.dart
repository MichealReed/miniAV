part of '../miniav_web.dart';

/// Web implementation of [MiniScreenPlatformInterface]
class MiniAVWebScreenPlatform implements MiniScreenPlatformInterface {
  @override
  Future<List<MiniAVDeviceInfo>> enumerateDisplays() async {
    // Single logical screen option
    return [
      MiniAVDeviceInfo(deviceId: 'screen', name: 'Screen', isDefault: true),
    ];
  }

  @override
  Future<List<MiniAVDeviceInfo>> enumerateWindows() async {
    // Not supported on web
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
      // GPU is the intended route now (VideoFrame → GPUExternalTexture, the
      // same zero-readback path the camera has had); the canvas readback
      // below survives only as the fallback for browsers with neither
      // MediaStreamTrackProcessor nor a VideoFrame(<video>) constructor.
      outputPreference: MiniAVOutputPreference.gpu,
    );
    return (videoFormat, null); // no system audio
  }

  @override
  Future<MiniScreenContextPlatformInterface> createContext() async {
    return MiniAVWebScreenContext();
  }

  @override
  void Function() addDisplayChangeListener(
    MiniAVDeviceChangeListener listener,
  ) {
    // Web has no display hot-plug API; the single 'screen' device is fixed.
    return () {};
  }

  @override
  void Function() addWindowChangeListener(MiniAVDeviceChangeListener listener) {
    // Web does not enumerate windows.
    return () {};
  }

  @override
  Future<void> setIOSAppGroup(String appGroupId) =>
      throw UnsupportedError('setIOSAppGroup is only available on iOS.');
}

/// Web implementation of [MiniScreenContextPlatformInterface].
///
/// 🔴 THE CAPTURE IS ZERO-READBACK NOW. This module used to be a `<video>` →
/// canvas `drawImage` → full-frame `getImageData` loop per rAF — ~8.3 MB of
/// synchronous main-thread readback per 1080p frame, which the browser then
/// re-uploaded to the GPU — plus ~1.1 s of deliberate start-up sleeps
/// (a 60 ms settle and up to 2×540 ms of black-frame probing). The camera
/// module had the zero-copy route all along; this is the same pump:
/// `MediaStreamTrackProcessor(maxBufferSize: 1)` handing `VideoFrame`s
/// straight to the consumer, `requestVideoFrameCallback`-driven
/// `VideoFrame(<video>)` where the processor is missing, and the canvas
/// readback ONLY as the final fallback. The black-probe sleeps are gone
/// entirely: the frame callbacks fire when a real frame exists, which is the
/// edge the probing was busy-waiting for.
class MiniAVWebScreenContext implements MiniScreenContextPlatformInterface {
  // Lost listeners (S8): `getDisplayMedia` tracks END when the user clicks
  // the browser's own "Stop sharing" — the one screen-lost signal web has.
  final List<MiniAVContextLostListener> _lostListeners = [];

  @override
  void Function() addLostListener(MiniAVContextLostListener listener) {
    _lostListeners.add(listener);
    return () => _lostListeners.remove(listener);
  }

  void _fireLost(int reason) {
    for (final l in List.of(_lostListeners)) {
      try {
        l(reason);
      } catch (_) {}
    }
  }

  @override
  Future<void> setCaptureCursor(bool enabled) async {
    // getDisplayMedia includes the cursor by default and does not expose a
    // reliable post-hoc toggle here; accept the call so cross-platform code
    // works, but it is a no-op on web.
  }

  // Media
  web.MediaStream? _mediaStream;
  web.HTMLVideoElement? _video;
  web.HTMLCanvasElement? _canvas;
  web.CanvasRenderingContext2D? _ctx;

  MiniAVVideoInfo? _format;

  // Capture
  bool _capturing = false;
  bool _gpuMode = false;
  int? _rafId;
  int? _rvfcId;
  web.ReadableStreamDefaultReader? _frameReader;

  // Debug
  static const bool _debug = false;

  // ---------------- Configuration ----------------
  @override
  Future<void> configureDisplay(
    String screenId,
    MiniAVVideoInfo format, {
    bool captureAudio = false,
  }) async {
    await destroy();

    if (_debug) {
      print(
        '[MiniAV][screen][configure] request ${format.width}x${format.height} '
        'fps=${format.frameRateNumerator / format.frameRateDenominator} audio=$captureAudio',
      );
    }

    // Build constraints (DisplayMediaStreamOptions via package:web)
    final videoConstraints = <String, dynamic>{
      'width': {'ideal': format.width},
      'height': {'ideal': format.height},
      'frameRate': {
        'ideal': format.frameRateNumerator / format.frameRateDenominator,
      },
    }.jsify()!;
    final options = web.DisplayMediaStreamOptions(
      video: videoConstraints,
      audio: (captureAudio ? true : false).toJS,
    );

    try {
      final t0 = DateTime.now();
      _mediaStream = await web.window.navigator.mediaDevices
          .getDisplayMedia(options)
          .toDart;
      if (_debug) {
        print(
          '[MiniAV][screen][configure] getDisplayMedia in '
          '${DateTime.now().difference(t0).inMilliseconds}ms',
        );
      }

      // The user clicking the browser's own "Stop sharing" bar ends the
      // track — surface it as context-lost (reason 1: source ended) instead
      // of frames silently stopping under a live share flag.
      final vTracks = _mediaStream!.getVideoTracks().toDart;
      if (vTracks.isNotEmpty) {
        vTracks.first.addEventListener(
          'ended',
          ((web.Event _) => _fireLost(1)).toJS,
        );
      }

      _video = web.HTMLVideoElement()
        ..autoplay = true
        ..muted = true
        ..playsInline = true
        ..setAttribute('playsinline', 'true')
        // Keep a tiny visible footprint to avoid compositor discard.
        ..style.position = 'absolute'
        ..style.left = '0'
        ..style.top = '0'
        ..style.width = '1px'
        ..style.height = '1px'
        ..style.opacity = '0'
        ..style.pointerEvents = 'none';

      if (_video!.parentNode == null) {
        web.document.body?.append(_video!);
      }
      _video!.srcObject = _mediaStream;

      // Explicit play (helps some autoplay edge cases)
      try {
        await _video!.play().toDart;
      } catch (e) {
        if (_debug) print('[MiniAV][screen][configure] play() error: $e');
      }

      // Wait for workable dimensions — bounded, and the ONLY wait left: the
      // 60 ms settle sleep and the black-probe loops that used to follow are
      // gone (the frame callbacks below fire when a real frame exists, which
      // is the edge the probing busy-waited for).
      await _waitFor(
        () {
          if (_video == null) return true;
          return _video!.videoWidth > 0 &&
              _video!.videoHeight > 0 &&
              _video!.readyState >= 2;
        },
        timeoutMs: 4000,
        pollMs: 40,
      );

      final vw = _video!.videoWidth > 0 ? _video!.videoWidth : format.width;
      final vh = _video!.videoHeight > 0 ? _video!.videoHeight : format.height;

      _format = MiniAVVideoInfo(
        width: vw,
        height: vh,
        pixelFormat: MiniAVPixelFormat.rgba32,
        frameRateNumerator: format.frameRateNumerator,
        frameRateDenominator: format.frameRateDenominator,
        outputPreference: MiniAVOutputPreference.gpu,
      );

      if (_debug) {
        print(
          '[MiniAV][screen][configure] final format ${vw}x$vh '
          'readyState=${_video!.readyState}',
        );
      }
    } catch (e) {
      if (_debug) {
        print('[MiniAV][screen][configure] ERROR: $e');
      }
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

  // ---------------- Capture Control ----------------
  @override
  Future<ScreenFormatDefaults> getConfiguredFormats() async {
    final f = _format;
    if (f == null) throw StateError('Screen context not configured');
    return (f, null);
  }

  @override
  Future<void> startCapture(
    void Function(MiniAVBuffer buffer, Object? userData) onFrame, {
    Object? userData,
  }) async {
    if (_mediaStream == null || _video == null || _format == null) {
      throw StateError('Screen capture not configured');
    }

    await stopCapture();

    _capturing = true;

    // Route 1: track processor (Chrome/Edge) — frames straight off the
    // track, nothing on the CPU. Route 2: rVFC + VideoFrame(<video>). Route
    // 3: the canvas readback, kept only for browsers with neither.
    final hasProcessor =
        (web.window as JSObject).has('MediaStreamTrackProcessor');
    if (hasProcessor) {
      _gpuMode = true;
      unawaited(_pumpVideoFrames(onFrame, userData));
      return;
    }
    final el = _video! as JSObject;
    if (el.has('requestVideoFrameCallback') &&
        (web.window as JSObject).has('VideoFrame')) {
      _gpuMode = true;
      _startVideoElementFrames(onFrame, userData);
      return;
    }
    _gpuMode = false;
    _startCanvasLoop(onFrame, userData);
  }

  @override
  Future<void> stopCapture() async {
    _capturing = false;
    if (_rafId != null) {
      web.window.cancelAnimationFrame(_rafId!);
      _rafId = null;
    }
    if (_rvfcId != null && _video != null) {
      try {
        _video!.cancelVideoFrameCallback(_rvfcId!);
      } catch (_) {}
      _rvfcId = null;
    }
    final reader = _frameReader;
    _frameReader = null;
    if (reader != null) {
      try {
        await reader.cancel().toDart;
      } catch (_) {}
    }
  }

  // ---------------- Zero-copy routes (mirrors miniav_web_camera) ----------

  /// `MediaStreamTrackProcessor(maxBufferSize: 1)` — one frame in flight,
  /// stale frames dropped by the browser, which is what a live encoder
  /// wants. The consumer must release each buffer (closing the frame) or the
  /// reader stops producing.
  Future<void> _pumpVideoFrames(
    void Function(MiniAVBuffer buffer, Object? userData) onData,
    Object? userData,
  ) async {
    final tracks = _mediaStream!.getVideoTracks().toDart;
    if (tracks.isEmpty) {
      _gpuMode = false;
      return;
    }
    final web.ReadableStreamDefaultReader reader;
    try {
      final processor = web.MediaStreamTrackProcessor(
        web.MediaStreamTrackProcessorInit(
            track: tracks.first, maxBufferSize: 1),
      );
      reader =
          processor.readable.getReader() as web.ReadableStreamDefaultReader;
    } catch (e) {
      // Feature-detected above, so this is a browser that has the
      // constructor and still refused. Not fatal and NOT silent.
      _gpuMode = false;
      print('[MiniAV][screen] MediaStreamTrackProcessor failed ($e) — '
          'falling back to the canvas readback path');
      _startCanvasLoop(onData, userData);
      return;
    }
    _frameReader = reader;

    while (_capturing) {
      final web.ReadableStreamReadResult result;
      try {
        result = await reader.read().toDart;
      } catch (_) {
        break; // reader cancelled by stopCapture, or the track ended
      }
      if (result.done) break;
      final frame = result.value as web.VideoFrame?;
      // Close it even on the way out — see the camera pump for the leak this
      // prevents ("A VideoFrame was garbage collected without being closed").
      if (!_capturing) {
        frame?.close();
        break;
      }
      if (frame == null) continue;

      final w = frame.displayWidth;
      final h = frame.displayHeight;
      if (w > 0 &&
          h > 0 &&
          (w != _format!.width || h != _format!.height)) {
        _format = MiniAVVideoInfo(
          width: w,
          height: h,
          pixelFormat: _format!.pixelFormat,
          frameRateNumerator: _format!.frameRateNumerator,
          frameRateDenominator: _format!.frameRateDenominator,
          outputPreference: MiniAVOutputPreference.gpu,
        );
      }

      onData(
        MiniAVBuffer(
          type: MiniAVBufferType.video,
          contentType: MiniAVBufferContentType.gpuWebVideoFrame,
          timestampUs: frame.timestamp.toInt(),
          data: MiniAVVideoBuffer(
            width: w,
            height: h,
            // The GPUExternalTexture the importer builds is opaque and
            // handles YUV internally; rgba32 is what the consumer sees.
            pixelFormat: MiniAVPixelFormat.rgba32,
            planes: const [],
            strideBytes: const [],
            nativeHandles: [frame],
          ),
          dataSizeBytes: 0,
        ),
        userData,
      );
    }

    try {
      await reader.cancel().toDart;
    } catch (_) {}
    _frameReader = null;
  }

  /// Route 2: wrap each COMPOSITED frame in a `VideoFrame` — rVFC fires once
  /// per new frame, so there is no duplicate wrapping and no probing.
  void _startVideoElementFrames(
    void Function(MiniAVBuffer buffer, Object? userData) onData,
    Object? userData,
  ) {
    void emit(num nowMs) {
      if (!_capturing || _video == null) return;
      if (_video!.readyState < 2) return;
      final w = _video!.videoWidth;
      final h = _video!.videoHeight;
      if (w <= 0 || h <= 0) return;

      final web.VideoFrame frame;
      try {
        frame = web.VideoFrame(
          _video! as JSObject,
          // Required: the constructor throws without a timestamp for a
          // <video> source.
          web.VideoFrameInit(timestamp: (nowMs * 1000).round()),
        );
      } catch (e) {
        _gpuMode = false;
        print('[MiniAV][screen] VideoFrame(<video>) failed ($e) — falling '
            'back to the canvas readback path');
        _startCanvasLoop(onData, userData);
        return;
      }

      if (w != _format!.width || h != _format!.height) {
        _format = MiniAVVideoInfo(
          width: w,
          height: h,
          pixelFormat: _format!.pixelFormat,
          frameRateNumerator: _format!.frameRateNumerator,
          frameRateDenominator: _format!.frameRateDenominator,
          outputPreference: MiniAVOutputPreference.gpu,
        );
      }

      onData(
        MiniAVBuffer(
          type: MiniAVBufferType.video,
          contentType: MiniAVBufferContentType.gpuWebVideoFrame,
          timestampUs: frame.timestamp.toInt(),
          data: MiniAVVideoBuffer(
            width: w,
            height: h,
            pixelFormat: MiniAVPixelFormat.rgba32,
            planes: const [],
            strideBytes: const [],
            nativeHandles: [frame],
          ),
          dataSizeBytes: 0,
        ),
        userData,
      );
    }

    void rvfc(JSNumber now, JSObject meta) {
      if (!_capturing) return;
      emit(now.toDartDouble);
      if (_capturing && _gpuMode && _video != null) {
        _rvfcId = _video!.requestVideoFrameCallback(rvfc.toJS);
      }
    }

    _rvfcId = _video!.requestVideoFrameCallback(rvfc.toJS);
  }

  // ---------------- Fallback: canvas readback loop --------------------------
  void _startCanvasLoop(
    void Function(MiniAVBuffer buffer, Object? userData) onData,
    Object? userData,
  ) {
    // Lazily built — the zero-copy routes never touch a canvas.
    // `willReadFrequently` matters here: this path IS the read-frequently
    // case, and without the hint some browsers keep the canvas on the GPU
    // and stall on every getImageData.
    _canvas ??= web.HTMLCanvasElement()
      ..width = _format!.width
      ..height = _format!.height;
    _ctx ??= _canvas!.getContext(
      '2d',
      <String, dynamic>{'willReadFrequently': true}.jsify(),
    ) as web.CanvasRenderingContext2D?;

    void frameCb(num _) {
      if (!_capturing) return;
      _captureFrame(onData, userData);
      _rafId = web.window.requestAnimationFrame(frameCb.toJS);
    }

    _rafId = web.window.requestAnimationFrame(frameCb.toJS);
  }

  void _captureFrame(
    void Function(MiniAVBuffer buffer, Object? userData) emit,
    Object? userData,
  ) {
    if (!_capturing ||
        _video == null ||
        _canvas == null ||
        _ctx == null ||
        _format == null) {
      return;
    }

    // Ensure video has data
    if (_video!.readyState < 2 ||
        _video!.videoWidth == 0 ||
        _video!.videoHeight == 0) {
      return;
    }

    // Adjust canvas if display size changes
    final vw = _video!.videoWidth;
    final vh = _video!.videoHeight;
    if ((vw != _canvas!.width || vh != _canvas!.height) && vw > 0 && vh > 0) {
      _canvas!
        ..width = vw
        ..height = vh;
      _format = MiniAVVideoInfo(
        width: vw,
        height: vh,
        pixelFormat: _format!.pixelFormat,
        frameRateNumerator: _format!.frameRateNumerator,
        frameRateDenominator: _format!.frameRateDenominator,
        outputPreference: MiniAVOutputPreference.cpu,
      );
    }

    try {
      _ctx!.drawImage(_video!, 0, 0);
      final img = _ctx!.getImageData(0, 0, _canvas!.width, _canvas!.height);
      final bytes = _imageDataToBytes(img);

      final videoBuffer = MiniAVVideoBuffer(
        width: _format!.width,
        height: _format!.height,
        pixelFormat: MiniAVPixelFormat.rgba32,
        planes: [bytes],
        strideBytes: [_format!.width * 4],
      );

      final buf = MiniAVBuffer(
        type: MiniAVBufferType.video,
        contentType: MiniAVBufferContentType.cpu,
        timestampUs: DateTime.now().microsecondsSinceEpoch,
        data: videoBuffer,
        dataSizeBytes: bytes.length,
      );

      emit(buf, userData);
    } catch (e) {
      if (_debug) {
        print('[MiniAV][screen][capture] ERROR: $e');
      }
    }
  }

  Uint8List _imageDataToBytes(web.ImageData img) {
    final dynamic raw = img.data.toDart;
    if (raw is Uint8List) return raw;
    if (raw is List<int>) return Uint8List.fromList(raw);
    return Uint8List.fromList(List<int>.from(raw as Iterable));
  }

  Future<void> _waitFor(
    bool Function() ready, {
    required int timeoutMs,
    required int pollMs,
  }) async {
    final start = DateTime.now().millisecondsSinceEpoch;
    while (true) {
      if (ready()) return;
      if (DateTime.now().millisecondsSinceEpoch - start > timeoutMs) return;
      await Future.delayed(Duration(milliseconds: pollMs));
    }
  }

  // ---------------- Destroy ----------------
  @override
  Future<void> destroy() async {
    await stopCapture();
    _mediaStream?.getTracks().toDart.forEach((t) => t.stop());
    _mediaStream = null;
    _video
      ?..pause()
      ..srcObject = null
      ..remove();
    _video = null;
    _canvas = null;
    _ctx = null;
    _format = null;
    if (_debug) print('[MiniAV][screen][destroy]');
  }
}
