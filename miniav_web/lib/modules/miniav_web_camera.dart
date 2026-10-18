part of '../miniav_web.dart';

/// Minimal ImageCapture interop (Chrome) using static interop (avoids conflict with dart:html ImageCapture)
@JS('ImageCapture')
@staticInterop
class _JSImageCapture {
  external factory _JSImageCapture(web.MediaStreamTrack track);
}

extension _JSImageCaptureExt on _JSImageCapture {
  external JSPromise grabFrame();
}

/// Whether this browser can stream camera frames as WebCodecs `VideoFrame`s
/// directly off the track. The best route: frame-accurate, with a drop-stale
/// queue. Chrome has it; Firefox and Safari do not (as of writing).
bool get _trackProcessorSupported =>
    web.window.has('MediaStreamTrackProcessor');

/// Whether this browser can construct a `VideoFrame` from an arbitrary image
/// source — which includes the `<video>` element we already have.
///
/// 🔴 THIS IS WHAT MAKES THE GPU PATH NEARLY UNIVERSAL. The obvious fallback —
/// importing the `HTMLVideoElement` straight into `importExternalTexture` — is
/// a TRAP: an external texture built from a video element EXPIRES AT THE END OF
/// THE CURRENT TASK, and the landing path awaits real GPU work, so the texture
/// can die mid-use. Nothing can "hold the task open"; a task ends when the
/// stack unwinds and the microtask checkpoint drains.
///
/// `new VideoFrame(videoElement, {timestamp})` sidesteps it completely: the
/// result is an ordinary VideoFrame with explicit open/close lifetime, exactly
/// like the track-processor path, so it composes with an async encoder.
///
/// And the coverage is effectively total, because WebGPU shipped LATER than
/// WebCodecs in every engine (Chrome 113 vs 94, Safari 26 vs 16.4, Firefox 141
/// vs 130). A browser that can use the GPU path at all can construct a
/// VideoFrame — so the canvas readback below is a floor for correctness, not a
/// path anyone with WebGPU is expected to land on.
bool get _videoFrameCtorSupported => web.window.has('VideoFrame');

/// Either zero-copy route.
bool get _zeroCopySupported =>
    _trackProcessorSupported || _videoFrameCtorSupported;

/// Web implementation of [MiniCameraPlatformInterface]
class MiniAVWebCameraPlatform implements MiniCameraPlatformInterface {
  @override
  Future<List<MiniAVDeviceInfo>> enumerateDevices() async {
    try {
      // Prompt once so labels populate after permission.
      try {
        await web.window.navigator.mediaDevices
            .getUserMedia(web.MediaStreamConstraints(video: true.toJS))
            .toDart;
      } catch (_) {}
      final devices = await web.window.navigator.mediaDevices
          .enumerateDevices()
          .toDart;
      final out = <MiniAVDeviceInfo>[];
      for (final d in devices.toDart) {
        if (d.kind == 'videoinput') {
          out.add(
            MiniAVDeviceInfo(
              deviceId: d.deviceId,
              name: d.label.isNotEmpty ? d.label : 'Camera ${out.length + 1}',
              isDefault: out.isEmpty,
            ),
          );
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<MiniAVVideoInfo>> getSupportedFormats(String deviceId) async {
    // 🔴 ADVERTISE GPU WHEN THE BROWSER HAS IT. Every entry here hard-coded
    // `cpu`, which is what a caller reads to decide whether a zero-copy path
    // exists — so the honest answer used to be "there is none", and the SDK's
    // capture ladder correctly built a single CPU rung even on a browser that
    // could do better. `configure` re-checks and downgrades if the ask fails,
    // so advertising this is a claim the code below actually honours.
    final pref = _zeroCopySupported
        ? MiniAVOutputPreference.gpu
        : MiniAVOutputPreference.cpu;
    return [
      MiniAVVideoInfo(
        width: 640,
        height: 480,
        pixelFormat: MiniAVPixelFormat.rgba32,
        frameRateNumerator: 30,
        frameRateDenominator: 1,
        outputPreference: pref,
      ),
      MiniAVVideoInfo(
        width: 1280,
        height: 720,
        pixelFormat: MiniAVPixelFormat.rgba32,
        frameRateNumerator: 30,
        frameRateDenominator: 1,
        outputPreference: pref,
      ),
      MiniAVVideoInfo(
        width: 1920,
        height: 1080,
        pixelFormat: MiniAVPixelFormat.rgba32,
        frameRateNumerator: 30,
        frameRateDenominator: 1,
        outputPreference: pref,
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

  static final _WebDeviceChangeWatcher _watcher = _WebDeviceChangeWatcher(
    kind: 'videoinput',
    deviceFactory: (info, isDefault) => MiniAVDeviceInfo(
      deviceId: info.deviceId,
      name: info.label.isNotEmpty ? info.label : 'Camera',
      isDefault: isDefault,
    ),
  );

  @override
  void Function() addDeviceChangeListener(
    MiniAVDeviceChangeListener listener,
  ) => _watcher.add(listener);
}

/// Web implementation of [MiniCameraContextPlatformInterface]
class MiniAVWebCameraContext implements MiniCameraContextPlatformInterface {
  @override
  void Function() addLostListener(MiniAVContextLostListener listener) {
    // Web cameras can be revoked but we don't currently propagate that.
    return () {};
  }

  // Media & elements
  web.MediaStream? _mediaStream;
  web.HTMLVideoElement? _videoElement;
  web.HTMLCanvasElement? _canvas;
  web.CanvasRenderingContext2D? _context;

  // Capture
  bool _capturing = false;
  int? _rafId;
  Timer? _fallbackTimer; // optional fallback
  MiniAVVideoInfo? _currentFormat;

  /// ZERO-COPY MODE: deliver WebCodecs `VideoFrame`s straight from the track
  /// instead of drawing to a canvas and reading the pixels back.
  ///
  /// 🔴 The canvas path costs a FULL-FRAME `getImageData` per frame — 3.7 MB at
  /// 720p, ~110 MB/s at 30 fps, synchronously on the main thread, and the
  /// browser itself complains about it (`willReadFrequently`). It exists
  /// because it works everywhere; it is not the path to want when the consumer
  /// is a GPU encoder that will only upload the pixels again.
  bool _gpuMode = false;
  web.ReadableStreamDefaultReader? _frameReader;
  int? _rvfcId;


  // First-frame / warm-up
  bool _firstRealFrame = false;
  bool _attemptedImageCapture = false;

  // Debug
  static const bool _debug = false;
  int _frameCount = 0;
  DateTime? _captureStart;
  int _blackStreak = 0;

  // ---------------- Configuration ----------------
  @override
  Future<void> configure(String deviceId, MiniAVVideoInfo format) async {
    await destroy();

    if (_debug) {
      print(
        '[MiniAV][camera][configure] deviceId="$deviceId" request=${format.width}x${format.height}'
        ' fps=${format.frameRateNumerator / format.frameRateDenominator}',
      );
    }

    final constraints = web.MediaStreamConstraints(
      video: _buildVideoConstraints(deviceId, format),
    );

    try {
      final t0 = DateTime.now();
      _mediaStream = await web.window.navigator.mediaDevices
          .getUserMedia(constraints)
          .toDart;
      if (_debug) {
        print(
          '[MiniAV][camera][configure] getUserMedia in '
          '${DateTime.now().difference(t0).inMilliseconds}ms',
        );
      }

      _videoElement = web.HTMLVideoElement()
        ..autoplay = true
        ..muted = true
        ..playsInline = true
        ..setAttribute('playsinline', 'true')
        // Keep inside layout (Chrome may optimize far-offscreen)
        ..style.position = 'absolute'
        ..style.left = '0'
        ..style.top = '0'
        ..style.width = '1px'
        ..style.height = '1px'
        ..style.opacity = '0'
        ..style.pointerEvents = 'none';

      if (_videoElement!.parentNode == null) {
        web.document.body?.append(_videoElement!);
      }
      _videoElement!.srcObject = _mediaStream;

      _attachVideoDebugListeners();

      // Force play
      try {
        final p = _videoElement!.play();
        await p.toDart;
        if (_debug) print('[MiniAV][camera][configure] play() resolved');
      } catch (e) {
        if (_debug) print('[MiniAV][camera][configure] play() error: $e');
      }

      // Wait for dimensions
      await _waitForVideoDimensions(timeoutMs: 3000);
      // Small post-ready delay
      await Future.delayed(const Duration(milliseconds: 40));

      final vw = _videoElement!.videoWidth > 0
          ? _videoElement!.videoWidth
          : format.width;
      final vh = _videoElement!.videoHeight > 0
          ? _videoElement!.videoHeight
          : format.height;

      _canvas = web.HTMLCanvasElement()
        ..width = vw
        ..height = vh;
      _context = _canvas!.getContext('2d') as web.CanvasRenderingContext2D?;

      // The GPU path is taken only if the CALLER asked for it and this
      // browser has the API. Report back what was actually resolved, never
      // what was requested — a caller that reads `gpu` here and gets canvas
      // buffers would import garbage.
      _gpuMode = format.outputPreference == MiniAVOutputPreference.gpu &&
          _zeroCopySupported;

      _currentFormat = MiniAVVideoInfo(
        width: vw,
        height: vh,
        pixelFormat: MiniAVPixelFormat.rgba32,
        frameRateNumerator: format.frameRateNumerator,
        frameRateDenominator: format.frameRateDenominator,
        outputPreference: _gpuMode
            ? MiniAVOutputPreference.gpu
            : MiniAVOutputPreference.cpu,
      );

      _firstRealFrame = false;
      _attemptedImageCapture = false;

      if (_debug) {
        print(
          '[MiniAV][camera][configure] final format ${vw}x$vh readyState=${_videoElement!.readyState}',
        );
      }

      // Prime attempts (draw a few times) — CPU delivery only. The zero-copy
      // pump reads frames off the TRACK and never looks at this canvas, so
      // the prime would be eight synchronous `getImageData` readbacks (and
      // ~300 ms of waits) spent on a picture nothing consumes.
      if (!(_gpuMode && _trackProcessorSupported)) await _primeFirstFrame();
    } catch (e) {
      if (_debug) print('[MiniAV][camera][configure] ERROR: $e');
      throw Exception('Failed to configure camera: $e');
    }
  }

  JSAny _buildVideoConstraints(String deviceId, MiniAVVideoInfo format) {
    // Use 'ideal' constraints for flexibility; fallback size if device refuses.
    final map = <String, dynamic>{
      'width': {'ideal': format.width},
      'height': {'ideal': format.height},
      'frameRate': {
        'ideal': format.frameRateNumerator / format.frameRateDenominator,
      },
    };
    if (deviceId.isNotEmpty) {
      map['deviceId'] = {'exact': deviceId};
    }
    return map.jsify()!;
  }

  Future<void> _waitForVideoDimensions({required int timeoutMs}) async {
    final start = DateTime.now().millisecondsSinceEpoch;
    while (true) {
      if (_videoElement == null) return;
      if (_videoElement!.videoWidth > 0 &&
          _videoElement!.videoHeight > 0 &&
          _videoElement!.readyState >= 2) {
        if (_debug) {
          print(
            '[MiniAV][camera][configure] dimensions ready '
            '${_videoElement!.videoWidth}x${_videoElement!.videoHeight} '
            'readyState=${_videoElement!.readyState}',
          );
        }
        return;
      }
      if (DateTime.now().millisecondsSinceEpoch - start > timeoutMs) {
        if (_debug) print('[MiniAV][camera][configure] dimension wait timeout');
        return;
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> _primeFirstFrame() async {
    if (_videoElement == null || _context == null) return;
    for (int i = 0; i < 8 && !_firstRealFrame; i++) {
      if (_videoElement!.readyState >= 2) {
        _context!.drawImage(_videoElement!, 0, 0);
        if (_nonBlackSample(4, 4)) {
          _firstRealFrame = true;
          if (_debug) {
            print(
              '[MiniAV][camera][prime] first non-black during prime (i=$i)',
            );
          }
          break;
        }
      }
      await Future.delayed(const Duration(milliseconds: 35));
    }
    if (!_firstRealFrame) {
      // Try ImageCapture once
      try {
        final tracks = _mediaStream?.getVideoTracks().toDart;
        if (tracks != null && tracks.isNotEmpty) {
          final cap = _JSImageCapture(tracks.first);
          final bmp = await cap.grabFrame().toDart as web.ImageBitmap;
          _canvas!
            ..width = bmp.width
            ..height = bmp.height;
          _context!.drawImage(bmp, 0, 0);
          if (_nonBlackSample(4, 4)) {
            _firstRealFrame = true;
            if (_debug) {
              print('[MiniAV][camera][prime] non-black via ImageCapture');
            }
          }
          _attemptedImageCapture = true;
        }
      } catch (e) {
        if (_debug) {
          print('[MiniAV][camera][prime] ImageCapture warm-up failed: $e');
        }
      }
    }
  }

  bool _nonBlackSample(int w, int h) {
    if (_context == null) return false;
    final data = _context!.getImageData(0, 0, w, h).data.toDart;
    for (int i = 0; i < data.length; i += 4) {
      if (data[i] != 0 || data[i + 1] != 0 || data[i + 2] != 0) return true;
    }
    return false;
  }

  void _attachVideoDebugListeners() {
    if (!_debug || _videoElement == null) return;
    _videoElement!.onLoadedMetadata.listen((_) {
      print(
        '[MiniAV][camera][video] onLoadedMetadata '
        'rs=${_videoElement!.readyState} width=${_videoElement!.videoWidth} height=${_videoElement!.videoHeight}',
      );
    });
    _videoElement!.onPlaying.listen((_) {
      print(
        '[MiniAV][camera][video] onPlaying ct=${_videoElement!.currentTime.toStringAsFixed(3)}',
      );
    });
    _videoElement!.onCanPlay.listen((_) {
      print(
        '[MiniAV][camera][video] onCanPlay rs=${_videoElement!.readyState}',
      );
    });
    _videoElement!.onLoadedData.listen((_) {
      print(
        '[MiniAV][camera][video] onLoadedData rs=${_videoElement!.readyState}',
      );
    });
    _videoElement!.onError.listen((_) {
      print('[MiniAV][camera][video] ERROR ${_videoElement!.error?.message}');
    });
  }

  // ---------------- Query configured format ----------------
  @override
  Future<MiniAVVideoInfo> getConfiguredFormat() async {
    final f = _currentFormat;
    if (f == null) throw StateError('Camera context not configured');
    return f;
  }

  // ---------------- Start Capture ----------------
  @override
  Future<void> startCapture(
    void Function(MiniAVBuffer buffer, Object? userData) onData, {
    Object? userData,
  }) async {
    if (_mediaStream == null ||
        _videoElement == null ||
        _canvas == null ||
        _context == null ||
        _currentFormat == null) {
      throw StateError('Camera not configured');
    }

    await stopCapture();

    _capturing = true;
    _frameCount = 0;
    _blackStreak = 0;
    _captureStart = DateTime.now();

    if (_debug) {
      print(
        '[MiniAV][camera][startCapture] starting capture '
        'rs=${_videoElement!.readyState} firstReal=$_firstRealFrame',
      );
    }

    if (_gpuMode) {
      if (_trackProcessorSupported) {
        unawaited(_pumpVideoFrames(onData, userData));
      } else {
        _startVideoElementFrames(onData, userData);
      }
      return;
    }

    // If still black after prime, allow capture loop to find first real frame.
    void frameCb(num _) {
      if (!_capturing) return;
      _captureFrame(onData, userData);
      _rafId = web.window.requestAnimationFrame(frameCb.toJS);
    }

    _rafId = web.window.requestAnimationFrame(frameCb.toJS);
  }

  /// ZERO-COPY CAPTURE: read `VideoFrame`s off the track and hand each one
  /// straight to the consumer. No canvas, no `getImageData`, no pixels on the
  /// CPU at all.
  ///
  /// 🔴 ONE FRAME IS IN FLIGHT AT A TIME, on purpose. `maxBufferSize: 1` tells
  /// the browser to drop stale frames rather than queue them, which is the
  /// behaviour a live encoder wants — a backlog here would show up as latency
  /// that never recovers. The consumer must release each buffer (which closes
  /// the frame) or the reader stops producing; see
  /// [MiniAVBufferContentType.gpuWebVideoFrame].
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
        web.MediaStreamTrackProcessorInit(track: tracks.first, maxBufferSize: 1),
      );
      reader =
          processor.readable.getReader() as web.ReadableStreamDefaultReader;
    } catch (e) {
      // Feature-detected above, so this is a browser that has the constructor
      // and still refused. Not fatal and NOT silent: fall back to the canvas
      // path rather than delivering nothing.
      _gpuMode = false;
      print('[MiniAV][camera] MediaStreamTrackProcessor failed ($e) — '
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
      // 🔴 CLOSE IT EVEN ON THE WAY OUT. `read()` can return a frame in the
      // same turn `stopCapture` clears `_capturing`, and breaking here without
      // closing leaks exactly one frame per stop — which the browser reports
      // as "A VideoFrame was garbage collected without being closed". The
      // reader cancel below drops what is still QUEUED; this one is already
      // ours.
      if (!_capturing) {
        frame?.close();
        break;
      }
      if (frame == null) continue;

      final w = frame.displayWidth;
      final h = frame.displayHeight;
      if (w > 0 && h > 0 && (w != _currentFormat!.width || h != _currentFormat!.height)) {
        _currentFormat = MiniAVVideoInfo(
          width: w,
          height: h,
          pixelFormat: _currentFormat!.pixelFormat,
          frameRateNumerator: _currentFormat!.frameRateNumerator,
          frameRateDenominator: _currentFormat!.frameRateDenominator,
          outputPreference: MiniAVOutputPreference.gpu,
        );
      }

      _frameCount++;
      final videoBuffer = MiniAVVideoBuffer(
        width: w,
        height: h,
        // The GPUExternalTexture the importer builds is opaque and handles YUV
        // internally, so the frame's own layout never surfaces. rgba32 is what
        // the consumer effectively sees.
        pixelFormat: MiniAVPixelFormat.rgba32,
        planes: const [],
        strideBytes: const [],
        nativeHandles: [frame],
      );
      onData(
        MiniAVBuffer(
          type: MiniAVBufferType.video,
          contentType: MiniAVBufferContentType.gpuWebVideoFrame,
          timestampUs: frame.timestamp.toInt(),
          data: videoBuffer,
          dataSizeBytes: 0,
        ),
        userData,
      );
    }

    // Whoever is left holding a frame closes it; anything still queued in the
    // reader is dropped with the cancel below.
    try {
      await reader.cancel().toDart;
    } catch (_) {}
    _frameReader = null;
  }

  /// ZERO-COPY CAPTURE, ROUTE 2: wrap each displayed video frame in a
  /// `VideoFrame` and hand that over. No `MediaStreamTrackProcessor`, no
  /// canvas, no pixel readback.
  ///
  /// Driven by `requestVideoFrameCallback` where it exists — it fires once per
  /// COMPOSITED FRAME, so there is no guessing and no duplicate wrapping of a
  /// frame the camera has not replaced yet. rAF is the floor when it does not:
  /// it can wrap the same frame twice on a display faster than the camera,
  /// which costs a redundant encode but is never wrong.
  ///
  /// 🔴 `timestamp` IS REQUIRED. `new VideoFrame(image, init)` throws a
  /// TypeError without it for any source that is not already a VideoFrame —
  /// an `<video>` element included.
  void _startVideoElementFrames(
    void Function(MiniAVBuffer buffer, Object? userData) onData,
    Object? userData,
  ) {
    final el = _videoElement;
    if (el == null) {
      _gpuMode = false;
      return;
    }
    final hasRvfc = (el as JSObject).has('requestVideoFrameCallback');

    void emit(num nowMs) {
      if (!_capturing || _videoElement == null) return;
      if (_videoElement!.readyState < 2) return;
      final w = _videoElement!.videoWidth;
      final h = _videoElement!.videoHeight;
      if (w <= 0 || h <= 0) return;

      final web.VideoFrame frame;
      try {
        frame = web.VideoFrame(
          _videoElement! as JSObject,
          web.VideoFrameInit(timestamp: (nowMs * 1000).round()),
        );
      } catch (e) {
        // The constructor exists but refused this source. Not fatal and not
        // silent: drop to the canvas path rather than delivering nothing.
        _gpuMode = false;
        print('[MiniAV][camera] VideoFrame(<video>) failed ($e) — falling '
            'back to the canvas readback path');
        _startCanvasLoop(onData, userData);
        return;
      }

      if (w != _currentFormat!.width || h != _currentFormat!.height) {
        _currentFormat = MiniAVVideoInfo(
          width: w,
          height: h,
          pixelFormat: _currentFormat!.pixelFormat,
          frameRateNumerator: _currentFormat!.frameRateNumerator,
          frameRateDenominator: _currentFormat!.frameRateDenominator,
          outputPreference: MiniAVOutputPreference.gpu,
        );
      }

      _frameCount++;
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

    if (hasRvfc) {
      void rvfc(JSNumber now, JSObject meta) {
        if (!_capturing) return;
        emit(now.toDartDouble);
        if (_capturing && _gpuMode && _videoElement != null) {
          _rvfcId = _videoElement!.requestVideoFrameCallback(rvfc.toJS);
        }
      }

      _rvfcId = el.requestVideoFrameCallback(rvfc.toJS);
      return;
    }

    void raf(num now) {
      if (!_capturing) return;
      emit(now);
      if (_capturing && _gpuMode) {
        _rafId = web.window.requestAnimationFrame(raf.toJS);
      }
    }

    _rafId = web.window.requestAnimationFrame(raf.toJS);
  }

  void _startCanvasLoop(
    void Function(MiniAVBuffer buffer, Object? userData) onData,
    Object? userData,
  ) {
    void frameCb(num _) {
      if (!_capturing) return;
      _captureFrame(onData, userData);
      _rafId = web.window.requestAnimationFrame(frameCb.toJS);
    }

    _rafId = web.window.requestAnimationFrame(frameCb.toJS);
  }

  // ---------------- Frame Capture ----------------
  void _captureFrame(
    void Function(MiniAVBuffer buffer, Object? userData) onData,
    Object? userData,
  ) {
    if (!_capturing ||
        _videoElement == null ||
        _canvas == null ||
        _context == null ||
        _currentFormat == null)
      return;

    // Ensure video is producing
    if (_videoElement!.readyState < 2) return;

    // Resize canvas if stream renegotiated
    final vw = _videoElement!.videoWidth;
    final vh = _videoElement!.videoHeight;
    if (vw > 0 && vh > 0 && (vw != _canvas!.width || vh != _canvas!.height)) {
      _canvas!
        ..width = vw
        ..height = vh;
      _currentFormat = MiniAVVideoInfo(
        width: vw,
        height: vh,
        pixelFormat: _currentFormat!.pixelFormat,
        frameRateNumerator: _currentFormat!.frameRateNumerator,
        frameRateDenominator: _currentFormat!.frameRateDenominator,
        outputPreference: _currentFormat!.outputPreference,
      );
      if (_debug) {
        print('[MiniAV][camera][capture] canvas resize -> ${vw}x$vh');
      }
    }

    try {
      _context!.drawImage(_videoElement!, 0, 0);

      if (!_firstRealFrame) {
        // Sample small region
        if (_videoElement!.currentTime <= 0) return;
        if (!_nonBlackSample(8, 8)) {
          _blackStreak++;
          if (_debug && _blackStreak <= 5) {
            print(
              '[MiniAV][camera][capture] still black streak=$_blackStreak '
              'rs=${_videoElement!.readyState} ct=${_videoElement!.currentTime.toStringAsFixed(2)}',
            );
          }
          // One-time ImageCapture attempt if still black after some tries
          if (_blackStreak == 10 && !_attemptedImageCapture) {
            _attemptedImageCapture = true;
            _warmUpViaImageCapture();
          }
          return;
        }
        _firstRealFrame = true;
        if (_debug) {
          final ms = DateTime.now().difference(_captureStart!).inMilliseconds;
          print('[MiniAV][camera][capture] FIRST NON-BLACK after ${ms}ms');
        }
      }

      final img = _context!.getImageData(0, 0, _canvas!.width, _canvas!.height);
      final Uint8List bytes = _imageDataToBytes(img);

      final videoBuffer = MiniAVVideoBuffer(
        width: _currentFormat!.width,
        height: _currentFormat!.height,
        pixelFormat: MiniAVPixelFormat.rgba32,
        planes: [bytes],
        strideBytes: [_currentFormat!.width * 4],
      );

      final buffer = MiniAVBuffer(
        type: MiniAVBufferType.video,
        contentType: MiniAVBufferContentType.cpu,
        timestampUs: DateTime.now().microsecondsSinceEpoch,
        data: videoBuffer,
        dataSizeBytes: bytes.length,
      );

      _frameCount++;
      if (_debug && _frameCount <= 5) {
        final avgLum = _averageLum(
          bytes,
          _currentFormat!.width,
          _currentFormat!.height,
        );
        print(
          '[MiniAV][camera][capture] frame=$_frameCount size=${_currentFormat!.width}x${_currentFormat!.height} avgLum=${avgLum.toStringAsFixed(1)}',
        );
      } else if (_debug && _frameCount % 120 == 0) {
        final avgLum = _averageLum(
          bytes,
          _currentFormat!.width,
          _currentFormat!.height,
        );
        print(
          '[MiniAV][camera][capture] frame=$_frameCount periodic avgLum=${avgLum.toStringAsFixed(1)}',
        );
      }

      try {
        onData(buffer, userData);
      } catch (e, s) {
        if (_debug) print('[MiniAV][camera][callback] ERROR: $e\n$s');
      }
    } catch (e) {
      if (_debug) print('[MiniAV][camera][capture] EXCEPTION: $e');
    }
  }

  void _warmUpViaImageCapture() {
    if (_mediaStream == null) return;
    try {
      final tracks = _mediaStream!.getVideoTracks().toDart;
      if (tracks.isEmpty) return;
      final cap = _JSImageCapture(tracks.first);
      cap.grabFrame().toDart.then((bmpAny) {
        if (!_capturing || _context == null || _canvas == null) return;
        final bmp = bmpAny as web.ImageBitmap;
        _canvas!
          ..width = bmp.width
          ..height = bmp.height;
        _context!.drawImage(bmp, 0, 0);
        if (_nonBlackSample(8, 8)) {
          _firstRealFrame = true;
          if (_debug)
            print('[MiniAV][camera][warmUp] ImageCapture produced non-black');
        } else {
          if (_debug)
            print('[MiniAV][camera][warmUp] ImageCapture still black');
        }
      });
    } catch (e) {
      if (_debug) print('[MiniAV][camera][warmUp] ERROR: $e');
    }
  }

  double _averageLum(Uint8List rgba, int w, int h) {
    if (rgba.isEmpty) return 0;
    // Sample limited number of pixels for speed
    final step = (w * h / 4000).ceil().clamp(1, 50);
    int sum = 0;
    int count = 0;
    for (int i = 0; i < rgba.length; i += 4 * step) {
      final r = rgba[i];
      final g = rgba[i + 1];
      final b = rgba[i + 2];
      sum += (0.2126 * r + 0.7152 * g + 0.0722 * b).round();
      count++;
    }
    return count == 0 ? 0 : sum / count;
  }

  // ---------------- Stop & Destroy ----------------
  @override
  Future<void> stopCapture() async {
    _capturing = false;
    if (_rafId != null) {
      web.window.cancelAnimationFrame(_rafId!);
      _rafId = null;
    }
    if (_rvfcId != null) {
      _videoElement?.cancelVideoFrameCallback(_rvfcId!);
      _rvfcId = null;
    }
    // Unblocks the pump's pending `read()` so it can exit and cancel; without
    // this the loop sits on a future that only the next frame would complete.
    final reader = _frameReader;
    _frameReader = null;
    if (reader != null) {
      try {
        await reader.cancel().toDart;
      } catch (_) {}
    }
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
  }

  @override
  Future<void> destroy() async {
    await stopCapture();
    _mediaStream?.getTracks().toDart.forEach((t) => t.stop());
    _mediaStream = null;
    _videoElement
      ?..pause()
      ..srcObject = null
      ..remove();
    _videoElement = null;
    _canvas = null;
    _context = null;
    _currentFormat = null;
    _gpuMode = false;
    _firstRealFrame = false;
    _attemptedImageCapture = false;
    if (_debug) print('[MiniAV][camera][destroy]');
  }

  Uint8List _imageDataToBytes(web.ImageData img) {
    final dynamic raw = img.data.toDart;
    if (raw is Uint8List) return raw;
    if (raw is List<int>) return Uint8List.fromList(raw);
    // Fallback (e.g. List<num>)
    return Uint8List.fromList(List<int>.from(raw as Iterable));
  }
}
