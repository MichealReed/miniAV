part of '../miniav_web.dart';

/// Web implementation of [MiniAudioInputPlatformInterface] backed by the miniav
/// WASM module (miniaudio compiled to WebAssembly). Capture goes through
/// miniaudio's Web Audio (ScriptProcessorNode) backend into an internal f32
/// ring; Dart drains it on a poll timer — the same first-party miniaudio path
/// used natively, replacing the previous hand-rolled Web-Audio-API capture.
///
/// Device enumeration still uses the browser (getUserMedia + enumerateDevices)
/// so apps can list microphones, but note miniaudio's web backend always
/// captures the system DEFAULT input — per-device selection is not routable on
/// web, so [MiniAVWebAudioInputContext.configure]'s deviceId is advisory.
class MiniAVWebAudioInputPlatform implements MiniAudioInputPlatformInterface {
  @override
  Future<List<MiniAVDeviceInfo>> enumerateDevices() async {
    try {
      final constraints = web.MediaStreamConstraints(audio: true.toJS);
      // Prompt for permission so device labels are populated.
      await web.window.navigator.mediaDevices.getUserMedia(constraints).toDart;

      final devices =
          await web.window.navigator.mediaDevices.enumerateDevices().toDart;
      final audioDevices = <MiniAVDeviceInfo>[];
      for (final device in devices.toDart) {
        if (device.kind == 'audioinput') {
          audioDevices.add(
            MiniAVDeviceInfo(
              deviceId: device.deviceId,
              name: device.label.isNotEmpty
                  ? device.label
                  : 'Microphone ${audioDevices.length + 1}',
              isDefault: audioDevices.isEmpty,
            ),
          );
        }
      }
      return audioDevices;
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<MiniAVAudioInfo>> getSupportedFormats(String deviceId) async {
    // miniaudio's web backend delivers f32; report the common rates.
    return [
      MiniAVAudioInfo(
        format: MiniAVAudioFormat.f32,
        sampleRate: 48000,
        channels: 1,
        numFrames: 256,
      ),
      MiniAVAudioInfo(
        format: MiniAVAudioFormat.f32,
        sampleRate: 48000,
        channels: 2,
        numFrames: 256,
      ),
      MiniAVAudioInfo(
        format: MiniAVAudioFormat.f32,
        sampleRate: 44100,
        channels: 1,
        numFrames: 256,
      ),
      MiniAVAudioInfo(
        format: MiniAVAudioFormat.f32,
        sampleRate: 44100,
        channels: 2,
        numFrames: 256,
      ),
    ];
  }

  @override
  Future<MiniAVAudioInfo> getDefaultFormat(String deviceId) async {
    return MiniAVAudioInfo(
      format: MiniAVAudioFormat.f32,
      sampleRate: 48000,
      channels: 1,
      // Low-latency default: on the worklet the device runs at the 128-frame
      // quantum regardless; on the ScriptProcessor fallback this is the period.
      numFrames: 256,
    );
  }

  @override
  Future<MiniAudioInputContextPlatformInterface> createContext() async {
    await wasm.MiniavWasm.instance.ensureLoaded();
    final handle = wasm.MiniavWasm.instance.createInput();
    if (handle == 0) {
      throw Exception('Failed to create audio input context (wasm).');
    }
    return MiniAVWebAudioInputContext._(handle);
  }

  static final _WebDeviceChangeWatcher _watcher = _WebDeviceChangeWatcher(
    kind: 'audioinput',
    deviceFactory: (info, isDefault) => MiniAVDeviceInfo(
      deviceId: info.deviceId,
      name: info.label.isNotEmpty ? info.label : 'Microphone',
      isDefault: isDefault,
    ),
  );

  @override
  void Function() addDeviceChangeListener(
    MiniAVDeviceChangeListener listener,
  ) => _watcher.add(listener);
}

/// Web implementation of [MiniAudioInputContextPlatformInterface].
class MiniAVWebAudioInputContext
    implements MiniAudioInputContextPlatformInterface {
  MiniAVWebAudioInputContext._(this._handle);

  /// How often the ring is drained, in milliseconds. See [startCapture] for
  /// why this is a drain cadence and not a capture one, and why 5 ms (the
  /// browser's timer clamp) was the wrong number.
  static const int _kPollMs = 10;

  int _handle;
  bool _destroyed = false;

  int _sampleRate = 48000;
  int _channels = 1;
  int _numFrames = 256; // requested buffer size (frames per callback)
  MiniAVAudioInfo? _format;

  Timer? _pollTimer;

  /// The capture mirror, when one is open: a region of the SHARED wasm heap
  /// the audio callback writes into so a worker can drain it. See
  /// [openCaptureMirror].
  int _mirrorPtr = 0;
  int _mirrorFrames = 0;

  /// Whether a mirror is the delivery path. While true the poll below does not
  /// run — two consumers of one capture would each get half the audio.
  bool get _mirrored => _mirrorPtr != 0;

  // ---- capture-health instrumentation -------------------------------------
  //
  // This drain is the ONLY delivery path for captured audio on web, it runs on
  // the MAIN THREAD, and the ring behind it holds ~200 ms. A main thread held
  // longer than that does not make audio late, it DESTROYS it: the ring wraps
  // and those samples never existed as far as the app is concerned. From the
  // outside that is indistinguishable from a network problem, which is exactly
  // how it got misdiagnosed - "stutters, occasional bursts" reads as transport
  // loss and is actually the UI thread starving this timer.
  //
  // So measure it. Delivered frames vs elapsed wall-clock is the unambiguous
  // signal: a healthy capture delivers sampleRate frames per second, and any
  // shortfall IS lost microphone input.
  int _healthStartMs = 0;
  int _healthLastTickMs = 0;
  int _healthLastReportMs = 0;
  int _healthTicks = 0;
  int _healthWorstGapMs = 0;
  int _healthPeakAvail = 0;
  int _healthFramesDelivered = 0;

  /// Approximate depth of the C-side ring (`enableBufferedCapture(_, 0)`).
  /// A gap wider than this loses frames UNRECOVERABLY.
  int get _ringFramesApprox => (_sampleRate * 200) ~/ 1000;

  void _resetCaptureHealth() {
    _healthStartMs = DateTime.now().millisecondsSinceEpoch;
    _healthLastTickMs = _healthStartMs;
    _healthLastReportMs = _healthStartMs;
    _healthTicks = 0;
    _healthWorstGapMs = 0;
    _healthPeakAvail = 0;
    _healthFramesDelivered = 0;
  }

  void _noteCaptureTick(int avail) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final gap = now - _healthLastTickMs;
    _healthLastTickMs = now;
    _healthTicks++;
    if (gap > _healthWorstGapMs) _healthWorstGapMs = gap;
    if (avail > _healthPeakAvail) _healthPeakAvail = avail;

    if (now - _healthLastReportMs < 5000) return;
    _healthLastReportMs = now;
    final elapsedMs = now - _healthStartMs;
    if (elapsedMs <= 0) return;
    final expected = (_sampleRate * elapsedMs) ~/ 1000;
    final lostPct = expected <= 0
        ? 0.0
        : (100.0 * (expected - _healthFramesDelivered)) / expected;
    final avgGap = _healthTicks == 0 ? 0.0 : elapsedMs / _healthTicks;
    final peakMs = (_healthPeakAvail * 1000) ~/ _sampleRate;
    final ringMs = (_ringFramesApprox * 1000) ~/ _sampleRate;
    final verdict = _healthWorstGapMs > ringMs
        ? '🔴 a gap EXCEEDED the ring - that speech is gone, not late'
        : 'gaps stayed inside the ring';
    // ignore: avoid_print
    print('[miniav-audio] capture drain: tick avg='
        '${avgGap.toStringAsFixed(1)} ms worst=$_healthWorstGapMs ms '
        '(asked for 5) | delivered=$_healthFramesDelivered of $expected '
        'frames (${lostPct.toStringAsFixed(1)}% LOST) | ring peak='
        '$_healthPeakAvail frames (~$peakMs ms of ~$ringMs) | $verdict');
  }
  void Function(MiniAVBuffer buffer, Object? userData)? _onData;
  Object? _userData;

  wasm.MiniavWasm get _w => wasm.MiniavWasm.instance;

  @override
  void Function() addLostListener(MiniAVContextLostListener listener) => () {};

  @override
  Future<void> configure(String deviceId, MiniAVAudioInfo format) async {
    if (_destroyed) throw StateError('Audio input context destroyed.');
    _sampleRate = format.sampleRate;
    _channels = format.channels;
    // Requested buffer size (frames per callback). This becomes the device
    // period so callbacks arrive at the requested rate — otherwise miniaudio's
    // Web Audio backend defaults to ~2048 frames (~42.7 ms), halving the
    // callback rate. 0 => a sane default.
    _numFrames = format.numFrames > 0 ? format.numFrames : 256;

    // miniaudio's web backend captures the default device; deviceId is
    // advisory (not routable on web). Force f32 to match the ring ABI.
    final cfg = _w.configureInput(
      _handle,
      MiniAVAudioFormat.f32.index,
      _sampleRate,
      _channels,
      _numFrames,
    );
    if (cfg != wasm.kSuccess) {
      throw Exception('Failed to configure audio input (wasm): $cfg');
    }
    final en = _w.enableBufferedCapture(_handle, 0); // 0 => ~200 ms ring
    if (en != wasm.kSuccess) {
      throw Exception('Failed to enable buffered capture (wasm): $en');
    }
    _format = MiniAVAudioInfo(
      format: MiniAVAudioFormat.f32,
      sampleRate: _sampleRate,
      channels: _channels,
      numFrames: _numFrames,
    );
  }

  @override
  Future<MiniAVAudioInfo> getConfiguredFormat() async {
    final f = _format;
    if (f == null) throw StateError('Audio input not configured.');
    return f;
  }

  @override
  Future<void> startCapture(
    void Function(MiniAVBuffer buffer, Object? userData) onData, {
    Object? userData,
  }) async {
    if (_destroyed) throw StateError('Audio input context destroyed.');
    await stopCapture(); // idempotent restart

    // Gesture-critical: prime the mic permission from THIS call stack (which
    // should be a user gesture) BEFORE the C StartCapture. This grants the
    // origin permission; miniaudio's own internal getUserMedia then succeeds
    // without a second prompt. We immediately release our priming stream so we
    // don't hold a redundant capture.
    try {
      final stream = await web.window.navigator.mediaDevices
          .getUserMedia(web.MediaStreamConstraints(audio: true.toJS))
          .toDart;
      for (final track in stream.getTracks().toDart) {
        track.stop();
      }
    } catch (e) {
      throw Exception('Microphone permission denied or unavailable: $e');
    }

    _onData = onData;
    _userData = userData;

    // Under the AudioWorklet build this suspends until the worklet thread is up
    // (ASYNCIFY), so it is awaited. The mic then warms up asynchronously.
    final res = await _w.startCapture(_handle);
    if (res != wasm.kSuccess) {
      _onData = null;
      _userData = null;
      throw Exception('Failed to start audio capture (wasm): $res');
    }

    // Poll the ring and deliver whatever has accumulated, in buffers of the
    // configured size. The AudioWorklet fills the ring off the main thread, so
    // this poll is a DRAIN CADENCE, not a capture cadence: nothing is lost
    // between ticks and nothing is synthesised — the ring is empty for the
    // first few ms (mic warm-up) and we deliver nothing until frames appear.
    //
    // 🔴 It was 5 ms, which is the browser's nested-timer CLAMP (~4 ms) — i.e.
    // "as often as possible" rather than a number anything needed. That is 200
    // wake-ups a second on the thread that also reads the socket, paints and
    // encodes, and the pipeline cannot use the granularity: consumers slice
    // this into 20 ms Opus frames, and the C ring is ~200 ms deep, so a late
    // tick costs nothing (the loop below drains to EMPTY every time).
    //
    // At [_kPollMs] there are still two drains per encoded frame, so the
    // uplink cadence stays even — going to 20 ms would align one poll to one
    // frame and turn ordinary timer jitter into alternating 0-frame and
    // 2-frame ticks. What it costs is up to one period of extra delay before
    // capture is drained: ~5 ms on average, against a mouth-to-ear budget
    // measured in hundreds.
    final chunk = _numFrames > 0 ? _numFrames : 256;
    _resetCaptureHealth();
    // A mirror IS the delivery path — see [openCaptureMirror]. Starting the
    // drain as well would hand half the audio to each consumer.
    if (_mirrored) return;
    _pollTimer = Timer.periodic(const Duration(milliseconds: _kPollMs), (_) {
      if (_destroyed || _onData == null) return;
      _noteCaptureTick(_w.availableCaptureFrames(_handle));
      // Drain to empty each tick so a slow tick can't leave a backlog.
      while (true) {
        final avail = _w.availableCaptureFrames(_handle);
        if (avail == 0) break;
        final want = avail < chunk ? avail : chunk;
        final f32 = _w.readCaptureFrames(_handle, want, _channels);
        final frames = f32.isEmpty ? 0 : f32.length ~/ _channels;
        if (frames == 0) break;
        _healthFramesDelivered += frames;
        try {
          _onData!(_buildBuffer(f32, frames), _userData);
        } catch (e, s) {
          print('Error in audio input user callback: $e\n$s');
        }
        if (frames < want) break; // fully drained
      }
    });
  }

  MiniAVBuffer _buildBuffer(Float32List f32, int frames) {
    final info = MiniAVAudioInfo(
      format: MiniAVAudioFormat.f32,
      sampleRate: _sampleRate,
      channels: _channels,
      numFrames: frames,
    );
    final audio = MiniAVAudioBuffer(
      frameCount: frames,
      info: info,
      data: Uint8List.view(
        f32.buffer,
        f32.offsetInBytes,
        frames * _channels * 4,
      ),
    );
    return MiniAVBuffer(
      type: MiniAVBufferType.audio,
      contentType: MiniAVBufferContentType.cpu,
      timestampUs: _WebUtils._getCurrentTimestampUs(),
      data: audio,
      dataSizeBytes: frames * _channels * 4,
    );
  }

  @override
  Future<MiniAVCaptureMirrorHandle?> openCaptureMirror({
    int capacityFrames = 0,
  }) async {
    if (_destroyed) return null;
    if (_format == null) {
      // `MiniAV_Audio_SetCaptureMirror` reads the configured channel count and
      // refuses before `configure`; failing here says so, rather than letting
      // it come back as an opaque error code.
      throw StateError('configure() before openCaptureMirror()');
    }
    if (_mirrored) return _handle0();

    // Default depth deliberately generous: the mirror's whole job is to
    // survive a consumer that was descheduled, and an overrun is LOST
    // MICROPHONE INPUT rather than latency. 400 ms of mono f32 at 48 kHz is
    // 76 kB.
    final frames = capacityFrames > 0
        ? capacityFrames
        : ((_sampleRate * 400) ~/ 1000);
    final ch = _channels <= 0 ? 1 : _channels;
    // `MINIAV_MIRROR_HEADER_U32 * 4 + frames * ch * sizeof(float)`.
    //
    // ⚠️ The 8 is stated here AND in the reader (`CaptureMirror` in
    // `miniav_tools_platform_interface`), because the two live in packages
    // that cannot import each other — this one is a Flutter plugin and the
    // reader has to compile into a plain dart2js worker. `audio_context.c`'s
    // `MINIAV_MIRROR_HEADER_U32` is the authority for both. A mismatch is not
    // silent: the reader validates the region against the geometry it reads
    // back out of the header.
    const headerBytes = 8 * 4;
    final bytes = headerBytes + frames * ch * 4;
    final ptr = _w.allocateHeap(bytes);
    if (ptr == 0) return null;

    final res = _w.setCaptureMirror(_handle, ptr, frames);
    if (res != wasm.kSuccess) {
      _w.releaseHeap(ptr);
      return null;
    }
    _mirrorPtr = ptr;
    _mirrorFrames = frames;

    // Capture may already be running — the mirror can be attached at any
    // point, and the C side publishes the geometry before the cursors so a
    // consumer never sees a live cursor beside a zero capacity. What must
    // stop is OUR drain.
    _pollTimer?.cancel();
    _pollTimer = null;
    return _handle0();
  }

  MiniAVCaptureMirrorHandle _handle0() => MiniAVCaptureMirrorHandle(
        memory: _w.heapBuffer,
        baseOffset: _mirrorPtr,
        capacityFrames: _mirrorFrames,
        channels: _channels <= 0 ? 1 : _channels,
        sampleRate: _sampleRate,
      );

  @override
  Future<void> closeCaptureMirror() async {
    if (!_mirrored) return;
    // DETACH FIRST. The audio callback writes through this pointer, so freeing
    // it while the C side still holds it is a write into freed heap on a
    // realtime thread.
    if (!_destroyed) _w.setCaptureMirror(_handle, 0, 0);
    _w.releaseHeap(_mirrorPtr);
    _mirrorPtr = 0;
    _mirrorFrames = 0;
  }

  @override
  Future<void> stopCapture() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _onData = null;
    _userData = null;
    if (!_destroyed) _w.stopCapture(_handle);
  }

  @override
  Future<void> destroy() async {
    if (_destroyed) return;
    _destroyed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    _onData = null;
    _userData = null;
    _w.destroyInput(_handle);
    _handle = 0;
  }
}
