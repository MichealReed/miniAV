/// Recorder runtime: opens encoders + muxers, wires capture sources to
/// encoders, fans encoded packets out to every sink, and drains cleanly
/// on stop.
library;

import 'dart:async';
import 'dart:io';

import 'package:miniav/miniav.dart';
import 'package:miniav_tools/miniav_tools.dart';
import 'package:miniav_tools_ffmpeg/miniav_tools_ffmpeg.dart';
import 'package:minigpu/minigpu.dart';

import 'gpu_downscaler.dart'; // provides GpuScreenProcessor
import 'recorder_sink.dart';
import 'recorder_source.dart';
import 'track_chunk.dart';

/// Run-time state of an open [Recorder].
enum RecorderState { idle, starting, running, stopping, stopped, errored }

class Recorder {
  Recorder.internal({
    required List<RecorderSource> sources,
    required List<RecorderSink> sinks,
    required this.defaultVideoBitrate,
    required this.defaultAudioBitrate,
    required this.defaultFrameRate,
    required this.backendPreference,
    required this.preferZeroCopy,
  }) : _sourceConfigs = sources,
       _sinkConfigs = sinks;

  final List<RecorderSource> _sourceConfigs;
  final List<RecorderSink> _sinkConfigs;
  final int defaultVideoBitrate;
  final int defaultAudioBitrate;
  final int defaultFrameRate;
  final BackendPreference backendPreference;

  /// When true, the recorder lazily spins up a shared [Minigpu] + Dawn
  /// `ID3D11Device` and passes them to backends via [BackendContext], so
  /// the FFmpeg backend can open a D3D11VA zero-copy encoder when the
  /// host supports it (Windows + NVENC/AMF/QSV/MF). Has no effect on
  /// non-Windows or when no source benefits.
  final bool preferZeroCopy;

  /// Lazily-allocated GPU runtime. Owned by this [Recorder]; destroyed in
  /// [_shutdown]. `null` outside Windows or when zero-copy is disabled.
  Minigpu? _minigpu;

  /// Cached shared context handed to every backend factory call.
  /// Carries the [_minigpu] instance and its borrowed Dawn `ID3D11Device*`
  /// (as int). Re-used per encoder so backends can opt into a zero-copy path.
  BackendContext? _backendContext;

  RecorderState _state = RecorderState.idle;
  RecorderState get state => _state;

  /// Master clock — set when [start] completes; all packet timestamps are
  /// relative to this in microseconds.
  final Stopwatch _masterClock = Stopwatch();

  // Resolved tracks (encoders + capture handles), in source-declaration order.
  final List<_TrackRuntime> _tracks = [];

  // Per-file-sink muxer; stream sinks have no muxer, just a callback.
  final List<_SinkRuntime> _sinks = [];

  Object? _lastError;
  Object? get lastError => _lastError;

  // -----------------------------------------------------------------------
  // Lifecycle
  // -----------------------------------------------------------------------

  Future<void> start() async {
    if (_state != RecorderState.idle) {
      throw StateError('Recorder.start: already $_state');
    }
    _state = RecorderState.starting;
    try {
      // Make sure FFmpeg is loaded (needed for both encoders + muxers).
      // Also ensure the FFmpeg backend is registered with the platform —
      // the auto-register top-level final only fires when something in the
      // library reads it; here we trigger it explicitly so callers don't
      // have to add a stray import-side-effect line.
      registerFfmpegBackend();
      await ensureFFmpegLoaded();

      // Lazily try to bring up the shared GPU device for zero-copy. Only
      // worth doing on Windows when the user opted in. On any failure we
      // silently fall back to the CPU upload path — the rest of the
      // recorder is fully functional without it.
      await _maybeInitSharedGpu();

      // 1. Build each track (open encoder + record capture config).
      for (var i = 0; i < _sourceConfigs.length; i++) {
        final cfg = _sourceConfigs[i];
        final track = await _buildTrack(i, cfg);
        _tracks.add(track);
      }

      // 2. Build each sink runtime (open muxer for file sinks).
      for (final sink in _sinkConfigs) {
        _sinks.add(await _buildSink(sink));
      }

      // 3. Start all capture contexts. Master clock starts now.
      _masterClock.start();
      for (final t in _tracks) {
        await t.startCapture(this);
      }

      _state = RecorderState.running;
    } catch (e) {
      _lastError = e;
      _state = RecorderState.errored;
      await _shutdown(force: true);
      rethrow;
    }
  }

  Future<void> stop() async {
    if (_state != RecorderState.running) {
      // Idempotent for repeated stop / stop-after-error.
      return;
    }
    _state = RecorderState.stopping;
    await _shutdown(force: false);
    _state = RecorderState.stopped;
  }

  Future<void> _shutdown({required bool force}) async {
    // 1. Stop captures (so no more frames arrive).
    for (final t in _tracks) {
      try {
        await t.stopCapture();
      } catch (e) {
        stderr.writeln('[recorder] stopCapture(${t.label}): $e');
      }
    }
    _masterClock.stop();

    // 2. Wait for any in-flight encode operations.
    for (final t in _tracks) {
      await t.drainInFlight();
    }

    // 3. Flush encoders + push trailing packets to every sink.
    for (final t in _tracks) {
      try {
        await t.flushAndDispatch(this);
      } catch (e) {
        stderr.writeln('[recorder] flush(${t.label}): $e');
      }
    }

    // 4. Finish + close every muxer.
    for (final s in _sinks) {
      try {
        await s.finish();
      } catch (e) {
        stderr.writeln('[recorder] finish sink: $e');
      }
    }

    // 5. Close encoders + capture contexts.
    for (final t in _tracks) {
      try {
        await t.dispose();
      } catch (_) {}
    }
    for (final s in _sinks) {
      try {
        await s.dispose();
      } catch (_) {}
    }
    if (!force) {
      _tracks.clear();
      _sinks.clear();
    }

    // 6. Tear down the shared GPU device last — encoders may still hold
    //    refcounts on the underlying ID3D11Device until close() returns.
    final gpu = _minigpu;
    _minigpu = null;
    _backendContext = null;
    if (gpu != null) {
      try {
        // Minigpu has no explicit destroy() in the public API — dropping
        // the reference releases native resources via its finalizer when
        // the GC runs. That's fine for the recorder lifecycle.
      } catch (_) {}
    }
  }

  // -----------------------------------------------------------------------
  // Shared GPU bring-up (for zero-copy encoder paths)
  // -----------------------------------------------------------------------

  Future<void> _maybeInitSharedGpu() async {
    if (!preferZeroCopy) return;
    if (!Platform.isWindows) return;
    // No screen source means no candidate for D3D11 zero-copy today.
    final hasScreen = _sourceConfigs.any((s) => s is ScreenRecorderSource);
    if (!hasScreen) return;
    try {
      final gpu = Minigpu();
      await gpu.init();
      if (!gpu.isExternalContentTypeSupported(
        ExternalContentType.d3d11SharedHandle,
      )) {
        return;
      }
      final dev = gpu.createD3D11DeviceOnDawnAdapter();
      if (dev == 0) {
        return;
      }
      _minigpu = gpu;
      _backendContext = BackendContext(
        sharedGpu: gpu,
        d3d11DeviceHandle: dev,
        preferZeroCopy: true,
      );
      stderr.writeln('[recorder] zero-copy GPU device ready (Dawn D3D11).');
    } catch (e) {
      stderr.writeln(
        '[recorder] zero-copy GPU init failed ($e) — using CPU upload path.',
      );
      _minigpu = null;
      _backendContext = null;
    }
  }

  // -----------------------------------------------------------------------
  // Build helpers
  // -----------------------------------------------------------------------

  Future<_TrackRuntime> _buildTrack(int index, RecorderSource cfg) async {
    switch (cfg) {
      case ScreenRecorderSource():
        return _buildScreenTrack(index, cfg);
      case CameraRecorderSource():
        return _buildCameraTrack(index, cfg);
      case MicRecorderSource():
        return _buildAudioTrack(
          index,
          deviceId: cfg.deviceId,
          codec: cfg.codec,
          bitrate: cfg.bitrateBps,
          sampleRate: cfg.sampleRate,
          channels: cfg.channels,
          factory: () async => MiniAudioInput.createContext(),
          configure: (ctx, fmt) =>
              (ctx as MiniAudioInputContext).configure(cfg.deviceId, fmt),
          getDefault: () => MiniAudioInput.getDefaultFormat(cfg.deviceId),
          start: (ctx, cb) => (ctx as MiniAudioInputContext).startCapture(cb),
          stop: (ctx) => (ctx as MiniAudioInputContext).stopCapture(),
          destroy: (ctx) => (ctx as MiniAudioInputContext).destroy(),
          label: 'mic[${cfg.deviceId}]',
        );
      case LoopbackRecorderSource():
        return _buildAudioTrack(
          index,
          deviceId: cfg.deviceId,
          codec: cfg.codec,
          bitrate: cfg.bitrateBps,
          sampleRate: cfg.sampleRate,
          channels: cfg.channels,
          factory: () async => MiniLoopback.createContext(),
          configure: (ctx, fmt) =>
              (ctx as MiniLoopbackContext).configure(cfg.deviceId, fmt),
          getDefault: () => MiniLoopback.getDefaultFormat(cfg.deviceId),
          start: (ctx, cb) => (ctx as MiniLoopbackContext).startCapture(cb),
          stop: (ctx) => (ctx as MiniLoopbackContext).stopCapture(),
          destroy: (ctx) => (ctx as MiniLoopbackContext).destroy(),
          label: 'loopback[${cfg.deviceId}]',
        );
    }
  }

  Future<_TrackRuntime> _buildScreenTrack(
    int index,
    ScreenRecorderSource cfg,
  ) async {
    final displayId = cfg.displayId;
    if (displayId == null && cfg.windowId == null) {
      throw StateError(
        'addScreen: either displayId or windowId must be supplied',
      );
    }
    final defaults = await MiniScreen.getDefaultFormats(
      displayId ?? cfg.windowId!,
    );
    var (videoFormat, _) = defaults;
    // Pick output preference: GPU when the recorder's zero-copy context
    // is live (so we can hand D3D11 textures straight to the encoder),
    // CPU otherwise (Stage A HW upload + libx264 SW both need plane bytes).
    final useGpuOutput = _backendContext != null;
    final outputPref = useGpuOutput
        ? MiniAVOutputPreference.gpu
        : MiniAVOutputPreference.cpu;
    if (cfg.width != null &&
        cfg.height != null &&
        (cfg.width != videoFormat.width || cfg.height != videoFormat.height)) {
      videoFormat = MiniAVVideoInfo(
        width: cfg.width!,
        height: cfg.height!,
        pixelFormat: videoFormat.pixelFormat,
        frameRateNumerator: cfg.fps ?? videoFormat.frameRateNumerator,
        frameRateDenominator: videoFormat.frameRateDenominator,
        outputPreference: outputPref,
      );
    } else if (cfg.fps != null) {
      videoFormat = MiniAVVideoInfo(
        width: videoFormat.width,
        height: videoFormat.height,
        pixelFormat: videoFormat.pixelFormat,
        frameRateNumerator: cfg.fps!,
        frameRateDenominator: 1,
        outputPreference: outputPref,
      );
    } else {
      videoFormat = MiniAVVideoInfo(
        width: videoFormat.width,
        height: videoFormat.height,
        pixelFormat: videoFormat.pixelFormat,
        frameRateNumerator: videoFormat.frameRateNumerator,
        frameRateDenominator: videoFormat.frameRateDenominator,
        outputPreference: outputPref,
      );
    }

    final ctx = await MiniScreen.createContext();
    if (displayId != null) {
      await ctx.configureDisplay(displayId, videoFormat);
    } else {
      await ctx.configureWindow(cfg.windowId!, videoFormat);
    }

    // Resolve target (encoder) dimensions: apply the scale policy on top of
    // the capture format. When a GPU processor is live the encoder is sized
    // to the smaller target; without GPU the encoder receives the full frame.
    final (int encW, int encH, GpuScreenProcessor? processor) = () {
      if (_backendContext == null) {
        if (cfg.effects.isNotEmpty) {
          stderr.writeln(
            '[recorder] WARNING: ${cfg.effects.length} effect(s) configured '
            'but no GPU context is available — effects will be skipped.',
          );
        }
        return (videoFormat.width, videoFormat.height, null);
      }
      final target = cfg.scale.targetSize(
        videoFormat.width,
        videoFormat.height,
      );
      final (dstW, dstH) = target ?? (videoFormat.width, videoFormat.height);
      if (target == null && cfg.effects.isEmpty) {
        // No scale and no effects: skip GPU processor entirely.
        return (videoFormat.width, videoFormat.height, null);
      }
      if (target != null) {
        stderr.writeln(
          '[recorder] screen downscale: '
          '${videoFormat.width}x${videoFormat.height} → ${dstW}x$dstH '
          '(${cfg.scale})',
        );
      }
      if (cfg.effects.isNotEmpty) {
        stderr.writeln(
          '[recorder] screen effects: ${cfg.effects.length} effect(s) active',
        );
      }
      final p = GpuScreenProcessor(
        gpu: _backendContext!.sharedGpu! as Minigpu,
        srcWidth: videoFormat.width,
        srcHeight: videoFormat.height,
        dstWidth: dstW,
        dstHeight: dstH,
        effects: cfg.effects,
      );
      return (dstW, dstH, p);
    }();

    final encResult = await _openVideoEncoder(
      MiniAVVideoInfo(
        width: encW,
        height: encH,
        pixelFormat: videoFormat.pixelFormat,
        frameRateNumerator: videoFormat.frameRateNumerator,
        frameRateDenominator: videoFormat.frameRateDenominator,
        outputPreference: videoFormat.outputPreference,
      ),
      cfg.codec,
      cfg.bitrateBps,
      cfg.hwAccel,
    );

    return _VideoTrackRuntime(
      index: index,
      label: 'screen[${displayId ?? cfg.windowId}]',
      encoder: encResult.encoder,
      videoCodec: encResult.codec,
      width: encW,
      height: encH,
      frameRateNum: videoFormat.frameRateNumerator,
      frameRateDen: videoFormat.frameRateDenominator,
      captureCtx: ctx,
      processor: processor,
      startFn: (cb) => ctx.startCapture(cb),
      stopFn: () => ctx.stopCapture(),
      destroyFn: () => ctx.destroy(),
    );
  }

  Future<_TrackRuntime> _buildCameraTrack(
    int index,
    CameraRecorderSource cfg,
  ) async {
    var format = await MiniCamera.getDefaultFormat(cfg.deviceId);
    if (cfg.width != null && cfg.height != null) {
      // Pick the closest supported format if user requested specific dims.
      final supported = await MiniCamera.getSupportedFormats(cfg.deviceId);
      MiniAVVideoInfo? best;
      var bestScore = double.infinity;
      for (final f in supported) {
        final dw = (f.width - cfg.width!).abs();
        final dh = (f.height - cfg.height!).abs();
        final df = cfg.fps != null
            ? (f.frameRateNumerator / f.frameRateDenominator -
                      cfg.fps!.toDouble())
                  .abs()
            : 0.0;
        final score = dw + dh + df * 100;
        if (score < bestScore) {
          bestScore = score;
          best = f;
        }
      }
      if (best != null) format = best;
    } else if (cfg.fps != null) {
      format = MiniAVVideoInfo(
        width: format.width,
        height: format.height,
        pixelFormat: format.pixelFormat,
        frameRateNumerator: cfg.fps!,
        frameRateDenominator: 1,
        outputPreference: format.outputPreference,
      );
    }

    final ctx = await MiniCamera.createContext();
    await ctx.configure(cfg.deviceId, format);

    final encResult = await _openVideoEncoder(
      format,
      cfg.codec,
      cfg.bitrateBps,
      cfg.hwAccel,
    );

    return _VideoTrackRuntime(
      index: index,
      label: 'camera[${cfg.deviceId}]',
      encoder: encResult.encoder,
      videoCodec: encResult.codec,
      width: format.width,
      height: format.height,
      frameRateNum: format.frameRateNumerator,
      frameRateDen: format.frameRateDenominator,
      captureCtx: ctx,
      startFn: (cb) => ctx.startCapture(cb),
      stopFn: () => ctx.stopCapture(),
      destroyFn: () => ctx.destroy(),
    );
  }

  Future<({Encoder encoder, VideoCodec codec})> _openVideoEncoder(
    MiniAVVideoInfo format,
    VideoCodec codec,
    int? bitrate,
    HwAccelPreference hwAccel,
  ) async {
    // HW H.264 encoders cap at 4096px on every shipping vendor (NVENC/QSV/
    // AMF/VT). Auto-promote to HEVC for ultrawide / 4K+ when HW is desired
    // — matches the screenshare_mp4 example's behaviour.
    final wantHw =
        hwAccel == HwAccelPreference.preferred ||
        hwAccel == HwAccelPreference.required;
    final effectiveCodec = FfmpegBackend.bestCodecForResolution(
      width: format.width,
      height: format.height,
      hwAccel: wantHw,
      preferred: codec,
    );
    if (effectiveCodec != codec) {
      stderr.writeln(
        '[recorder] ${format.width}x${format.height} exceeds H.264 HW cap; '
        'promoting ${codec.name} → ${effectiveCodec.name}',
      );
    }
    final enc = await MiniAVTools.createEncoder(
      EncoderConfig(
        codec: effectiveCodec,
        width: format.width,
        height: format.height,
        bitrateBps: bitrate ?? defaultVideoBitrate,
        frameRateNumerator: format.frameRateNumerator,
        frameRateDenominator: format.frameRateDenominator,
        hwAccel: hwAccel,
        backendOptions: wantHw
            ? const {'preset': 'p4', 'tune': 'll', 'global_header': '1'}
            : const {
                'preset': 'ultrafast',
                'tune': 'zerolatency',
                'global_header': '1',
              },
      ),
      preference: backendPreference,
      context: _backendContext,
    );
    stderr.writeln(
      '[recorder] video encoder = ${enc.backendName} '
      '(${enc.platform.runtimeType}) for ${effectiveCodec.name} '
      '${format.width}x${format.height}',
    );
    return (encoder: enc, codec: effectiveCodec);
  }

  Future<_AudioTrackRuntime> _buildAudioTrack(
    int index, {
    required String deviceId,
    required AudioCodec codec,
    required int? bitrate,
    required int? sampleRate,
    required int? channels,
    required Future<Object> Function() factory,
    required Future<void> Function(Object ctx, MiniAVAudioInfo fmt) configure,
    required Future<MiniAVAudioInfo> Function() getDefault,
    required Future<void> Function(
      Object ctx,
      void Function(MiniAVBuffer, Object?) cb,
    )
    start,
    required Future<void> Function(Object ctx) stop,
    required Future<void> Function(Object ctx) destroy,
    required String label,
  }) async {
    var format = await getDefault();
    if (sampleRate != null || channels != null) {
      format = MiniAVAudioInfo(
        format: format.format,
        sampleRate: sampleRate ?? format.sampleRate,
        channels: channels ?? format.channels,
        numFrames: format.numFrames,
      );
    }

    final ctx = await factory();
    await configure(ctx, format);

    final encoder = await MiniAVTools.createAudioEncoder(
      AudioEncoderConfig(
        codec: codec,
        sampleRate: format.sampleRate,
        channels: format.channels,
        bitrateBps: bitrate ?? defaultAudioBitrate,
        backendOptions: const {'global_header': '1'},
      ),
      preference: backendPreference,
      context: _backendContext,
    );

    return _AudioTrackRuntime(
      index: index,
      label: label,
      encoder: encoder,
      audioCodec: codec,
      sampleRate: format.sampleRate,
      channels: format.channels,
      audioFormat: format.format,
      captureCtx: ctx,
      startFn: (cb) => start(ctx, cb),
      stopFn: () => stop(ctx),
      destroyFn: () => destroy(ctx),
    );
  }

  Future<_SinkRuntime> _buildSink(RecorderSink sink) async {
    switch (sink) {
      case FileRecorderSink():
        // Pick container: use override, else MKV if any audio track is
        // present (more permissive), else MP4.
        final hasAudio = _tracks.any((t) => t is _AudioTrackRuntime);
        final container =
            sink.container ?? (hasAudio ? Container.mkv : Container.mp4);

        // Build TrackInfo list + encoder bridge map.
        final tracks = <TrackInfo>[];
        final encoderForTrack = <int, FfmpegEncoderBridge>{};
        for (final t in _tracks) {
          tracks.add(t.toTrackInfo());
          final bridge = t.encoderBridge;
          if (bridge != null) encoderForTrack[t.index] = bridge;
        }

        final muxer = FfmpegMuxer.open(
          MuxerConfig(
            container: container,
            output: FileMuxerOutput(sink.path),
            tracks: tracks,
          ),
          encoderForTrack: encoderForTrack,
        );
        await muxer.writeHeader();
        return _FileSinkRuntime(muxer: muxer, path: sink.path);

      case StreamRecorderSink():
        return _StreamSinkRuntime(onChunk: sink.onChunk);
    }
  }

  // -----------------------------------------------------------------------
  // Packet dispatch (called from track runtimes)
  // -----------------------------------------------------------------------

  // ignore: library_private_types_in_public_api
  Future<void> dispatchPacket(_TrackRuntime track, EncodedPacket packet) async {
    final routed = packet.copyWith(trackIndex: track.index);
    for (final s in _sinks) {
      switch (s) {
        case _FileSinkRuntime():
          try {
            await s.muxer.writePacket(routed);
          } catch (e) {
            stderr.writeln('[recorder] mux write track=${track.index}: $e');
          }
        case _StreamSinkRuntime():
          try {
            s.onChunk(track.toChunk(routed));
          } catch (e) {
            stderr.writeln('[recorder] stream callback: $e');
          }
      }
    }
  }

  /// Master-clock pts, in microseconds, at the moment this is called.
  int now() => _masterClock.elapsedMicroseconds;
}

// =========================================================================
// Track runtime (one per source).
// =========================================================================

abstract class _TrackRuntime {
  _TrackRuntime({required this.index, required this.label});
  final int index;
  final String label;

  /// Outstanding encode futures so [Recorder.stop] can wait before flush.
  final List<Future<void>> _inFlight = [];

  Future<void> startCapture(Recorder rec);
  Future<void> stopCapture();
  Future<void> drainInFlight() async {
    while (_inFlight.isNotEmpty) {
      final batch = List<Future<void>>.from(_inFlight);
      _inFlight.clear();
      await Future.wait(batch);
    }
  }

  Future<void> flushAndDispatch(Recorder rec);
  Future<void> dispose();

  TrackInfo toTrackInfo();
  FfmpegEncoderBridge? get encoderBridge;
  TrackChunk toChunk(EncodedPacket pkt);
}

class _VideoTrackRuntime extends _TrackRuntime {
  _VideoTrackRuntime({
    required super.index,
    required super.label,
    required this.encoder,
    required this.videoCodec,
    required this.width,
    required this.height,
    required this.frameRateNum,
    required this.frameRateDen,
    required this.captureCtx,
    required this.startFn,
    required this.stopFn,
    required this.destroyFn,
    this.processor,
  });

  final Encoder encoder;
  final VideoCodec videoCodec;
  final int width;
  final int height;
  final int frameRateNum;
  final int frameRateDen;
  final Object captureCtx;
  final Future<void> Function(void Function(MiniAVBuffer, Object?)) startFn;
  final Future<void> Function() stopFn;
  final Future<void> Function() destroyFn;

  /// Optional GPU screen processor (downscale + effects chain). Non-null only
  /// for screen tracks when the zero-copy GPU path is live and at least one
  /// of scale policy or effects is active.
  final GpuScreenProcessor? processor;

  bool _busy = false;
  bool _stopping = false;
  bool _firstChunkSent = false;
  int _lastVideoPtsUs = -1;

  @override
  Future<void> startCapture(Recorder rec) async {
    await startFn((MiniAVBuffer buffer, Object? _) {
      if (_stopping) {
        // Drop and release.
        unawaited(MiniAV.releaseBuffer(buffer));
        return;
      }
      if (_busy) {
        // Backpressure: drop this frame.
        unawaited(MiniAV.releaseBuffer(buffer));
        return;
      }
      _busy = true;
      final fut = _encodeOne(rec, buffer);
      _inFlight.add(fut);
      fut.whenComplete(() {
        _busy = false;
        _inFlight.remove(fut);
      });
    });
  }

  Future<void> _encodeOne(Recorder rec, MiniAVBuffer buffer) async {
    try {
      var ptsUs = rec.now();
      // Guarantee strict monotonic increase even on sub-µs frame deltas.
      if (ptsUs <= _lastVideoPtsUs) ptsUs = _lastVideoPtsUs + 1;
      _lastVideoPtsUs = ptsUs;

      // --- GPU downscale path -------------------------------------------
      // When a GpuScreenProcessor is present the buffer must be a D3D11 GPU
      // handle. The processor converts, scales, and applies effects entirely on
      // the GPU and returns a SharedOutputTexture at encoder dims.
      final proc = processor;
      if (proc != null &&
          buffer.contentType == MiniAVBufferContentType.gpuD3D11Handle) {
        final sharedTex = await proc.process(buffer);
        if (sharedTex != null) {
          final src = D3D11TextureFrameSource(
            texturePtr: sharedTex.d3d11TexturePtr,
            width: proc.dstWidth,
            height: proc.dstHeight,
            pixelFormat: MiniAVPixelFormat.rgba32,
          );
          final pkt = await encoder.encode(src);
          if (pkt != null) {
            await rec.dispatchPacket(
              this,
              pkt.copyWith(ptsUs: ptsUs, dtsUs: ptsUs),
            );
          }
        }
        return;
      }

      // --- Normal path (no downscale / CPU) --------------------------------
      final src = FrameSource.miniavBuffer(buffer);
      final pkt = await encoder.encode(src);
      if (pkt != null) {
        await rec.dispatchPacket(
          this,
          pkt.copyWith(ptsUs: ptsUs, dtsUs: ptsUs),
        );
      }
    } catch (e, st) {
      stderr.writeln('[recorder] $label encode: $e\n$st');
    } finally {
      await MiniAV.releaseBuffer(buffer);
    }
  }

  @override
  Future<void> stopCapture() async {
    _stopping = true;
    await stopFn();
  }

  @override
  Future<void> flushAndDispatch(Recorder rec) async {
    final pkts = await encoder.flush();
    for (final p in pkts) {
      var ptsUs = rec.now();
      if (ptsUs <= _lastVideoPtsUs) ptsUs = _lastVideoPtsUs + 1;
      _lastVideoPtsUs = ptsUs;
      await rec.dispatchPacket(this, p.copyWith(ptsUs: ptsUs, dtsUs: ptsUs));
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await destroyFn();
    } catch (_) {}
    try {
      await encoder.close();
    } catch (_) {}
    try {
      processor?.dispose();
    } catch (_) {}
  }

  @override
  TrackInfo toTrackInfo() => VideoTrackInfo(
    codec: videoCodec,
    width: width,
    height: height,
    frameRateNumerator: frameRateNum,
    frameRateDenominator: frameRateDen,
  );

  @override
  FfmpegEncoderBridge? get encoderBridge {
    final p = encoder.platform;
    return p is FfmpegEncoderBridge ? p as FfmpegEncoderBridge : null;
  }

  @override
  TrackChunk toChunk(EncodedPacket pkt) {
    final extra = !_firstChunkSent ? encoder.extraData?.bytes : null;
    _firstChunkSent = true;
    return TrackChunk(
      trackIndex: index,
      kind: TrackKind.video,
      videoCodec: videoCodec,
      ptsUs: pkt.ptsUs,
      dtsUs: pkt.dtsUs,
      durationUs: pkt.durationUs,
      bytes: pkt.data,
      isKeyframe: pkt.isKeyframe,
      extraData: extra,
    );
  }
}

class _AudioTrackRuntime extends _TrackRuntime {
  _AudioTrackRuntime({
    required super.index,
    required super.label,
    required this.encoder,
    required this.audioCodec,
    required this.sampleRate,
    required this.channels,
    required this.audioFormat,
    required this.captureCtx,
    required this.startFn,
    required this.stopFn,
    required this.destroyFn,
  });

  final AudioEncoder encoder;
  final AudioCodec audioCodec;
  final int sampleRate;
  final int channels;
  final MiniAVAudioFormat audioFormat;
  final Object captureCtx;
  final Future<void> Function(void Function(MiniAVBuffer, Object?)) startFn;
  final Future<void> Function() stopFn;
  final Future<void> Function() destroyFn;

  bool _stopping = false;
  bool _firstChunkSent = false;

  @override
  Future<void> startCapture(Recorder rec) async {
    await startFn((MiniAVBuffer buffer, Object? _) {
      if (_stopping) {
        unawaited(MiniAV.releaseBuffer(buffer));
        return;
      }
      final audio = buffer.data;
      if (audio is! MiniAVAudioBuffer) {
        unawaited(MiniAV.releaseBuffer(buffer));
        return;
      }
      final ptsUs = rec.now();
      final fut = _encodeAudio(rec, audio, ptsUs).whenComplete(() {
        unawaited(MiniAV.releaseBuffer(buffer));
      });
      _inFlight.add(fut);
      fut.whenComplete(() => _inFlight.remove(fut));
    });
  }

  Future<void> _encodeAudio(
    Recorder rec,
    MiniAVAudioBuffer audio,
    int ptsUs,
  ) async {
    try {
      final pkts = await encoder.encode(
        pcm: audio.data,
        format: audio.info.format,
        frameCount: audio.frameCount,
        ptsUs: ptsUs,
      );
      for (final p in pkts) {
        await rec.dispatchPacket(this, p);
      }
    } catch (e, st) {
      stderr.writeln('[recorder] $label encode: $e\n$st');
    }
  }

  @override
  Future<void> stopCapture() async {
    _stopping = true;
    await stopFn();
  }

  @override
  Future<void> flushAndDispatch(Recorder rec) async {
    final pkts = await encoder.flush();
    for (final p in pkts) {
      await rec.dispatchPacket(this, p);
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await destroyFn();
    } catch (_) {}
    try {
      await encoder.close();
    } catch (_) {}
  }

  @override
  TrackInfo toTrackInfo() => AudioTrackInfo(
    codec: audioCodec,
    sampleRate: sampleRate,
    channels: channels,
  );

  @override
  FfmpegEncoderBridge? get encoderBridge {
    final p = encoder.platform;
    return p is FfmpegEncoderBridge ? p as FfmpegEncoderBridge : null;
  }

  @override
  TrackChunk toChunk(EncodedPacket pkt) {
    final extra = !_firstChunkSent ? encoder.extraData?.bytes : null;
    _firstChunkSent = true;
    return TrackChunk(
      trackIndex: index,
      kind: TrackKind.audio,
      audioCodec: audioCodec,
      ptsUs: pkt.ptsUs,
      dtsUs: pkt.dtsUs,
      durationUs: pkt.durationUs,
      bytes: pkt.data,
      isKeyframe: true,
      extraData: extra,
    );
  }
}

// =========================================================================
// Sink runtime.
// =========================================================================

abstract class _SinkRuntime {
  Future<void> finish();
  Future<void> dispose();
}

class _FileSinkRuntime implements _SinkRuntime {
  _FileSinkRuntime({required this.muxer, required this.path});
  final FfmpegMuxer muxer;
  final String path;

  @override
  Future<void> finish() => muxer.finish();

  @override
  Future<void> dispose() => muxer.close();
}

class _StreamSinkRuntime implements _SinkRuntime {
  _StreamSinkRuntime({required this.onChunk});
  final void Function(Object) onChunk;

  @override
  Future<void> finish() async {}

  @override
  Future<void> dispose() async {}
}
