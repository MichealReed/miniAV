/// Recorder runtime: opens encoders + muxers, wires capture sources to
/// encoders, fans encoded packets out to every sink, and drains cleanly
/// on stop.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:miniav/miniav.dart';
import 'package:miniav_tools/miniav_tools.dart';
import 'package:miniav_tools_ffmpeg/miniav_tools_ffmpeg.dart';
import 'package:minigpu/minigpu.dart';

import 'container_utils.dart';
import 'gpu_screen_processor.dart';
import 'recorder_sink.dart';
import 'recorder_source.dart';
import 'track_chunk.dart';

/// Run-time state of an open [Recorder].
enum RecorderState { idle, starting, running, stopping, stopped, errored }

/// Log verbosity level for all native subsystems managed by [Recorder].
///
/// Maps to:
/// - MiniAV C library   → [MiniAVLogLevel]
/// - FFmpeg (av_log)    → AV_LOG_* constants
/// - minigpu / Dawn     → no native API; Dawn writes directly to native stderr
enum RecorderLogLevel {
  /// All internal debug output (very verbose — for deep diagnostics only).
  verbose,

  /// Informational messages (startup, encoder selection, device names).
  info,

  /// Warnings only (recoverable issues, dropped frames, fallbacks).
  warning,

  /// Errors only.
  error,

  /// Suppress all native log output.
  quiet,
}

/// Identifies which subsystem produced a log message delivered to the
/// callback installed via [Recorder.setLogCallback].
enum RecorderLogSource {
  /// Log from the Dart-layer recorder runtime (encoder selection, stats,
  /// errors surfaced from native callbacks).
  recorder,

  /// Log from the MiniAV C library (capture pipeline, device enumeration).
  miniav,

  /// Log from FFmpeg (encoder, muxer, codec messages via the shim bridge).
  ffmpeg,

  /// Log from the minigpu / Dawn native GPU layer (compute, texture import,
  /// D3D11 interop).
  minigpu,
}

// ---------------------------------------------------------------------------
// Process-global shared GPU singleton.
//
// The shared [Minigpu] + Dawn-allocated `ID3D11Device` are expensive to
// create and the underlying native Dawn context CANNOT be destroyed and
// re-created reliably in a single process — re-init can pick a different
// backend (D3D12 vs D3D11) than the first run, breaking the cross-API
// shared-texture path with errors like:
//
//   [wgpu] The D3D11 device of the texture and the D3D11 device of
//          [Device "MGPU.MainDevice"] must be same.
//   [minigpu_external] create_shared_output_texture: Dawn is not on D3D11
//          backend; cross-API path not implemented in this build.
//
// We therefore keep ONE [Minigpu] alive for the whole isolate. Stopping a
// recorder no longer tears it down. Tests / hot-restart hooks can call
// [Recorder.disposeSharedGpu] to explicitly release it.
// ---------------------------------------------------------------------------
Minigpu? _sharedGpu;
int _sharedD3d11Device = 0;
Future<void>? _sharedGpuInitFuture;
bool _sharedGpuUnsupported = false;

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

  /// Cached shared context handed to every backend factory call.
  /// Borrows the process-global [_sharedGpu] + Dawn `ID3D11Device*` (as int).
  /// Re-used per encoder so backends can opt into a zero-copy path.
  ///
  /// Never owns the GPU device — see the file-level singleton block above.
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
    await _prepare();
    await _launch();
  }

  /// Phase 1: load FFmpeg, initialise GPU, open encoders + muxers.
  /// After this returns the recorder is in [RecorderState.starting].
  /// Do not do significant async work between [_prepare] and [_launch] if
  /// you want tight clock synchronisation with other recorders.
  Future<void> _prepare() async {
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
    } catch (e) {
      _lastError = e;
      _state = RecorderState.errored;
      await _shutdown(force: true);
      rethrow;
    }
  }

  /// Phase 2: start the master clock and all capture sources.
  /// Should be called immediately after [_prepare].
  Future<void> _launch() async {
    if (_state != RecorderState.starting) {
      throw StateError('Recorder._launch: expected starting, got $_state');
    }
    try {
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
        _log('stopCapture(${t.label}): $e', RecorderLogLevel.error);
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
        _log('flush(${t.label}): $e', RecorderLogLevel.error);
      }
    }

    // 4. Finish + close every muxer.
    for (final s in _sinks) {
      try {
        await s.finish();
      } catch (e) {
        _log('finish sink: $e', RecorderLogLevel.error);
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

    // 6. Drop our reference to the shared backend context. The underlying
    //    [_sharedGpu] + Dawn-owned ID3D11Device are intentionally NOT torn
    //    down here — they live for the lifetime of the isolate so that a
    //    subsequent recorder can reuse them without re-initialising Dawn
    //    (which would risk picking a different backend on the second run).
    //    Use [Recorder.disposeSharedGpu] for explicit teardown.
    _backendContext = null;
  }

  // -----------------------------------------------------------------------
  // Static GPU lifecycle (process-global)
  // -----------------------------------------------------------------------

  /// Idempotently initialise the process-global shared [Minigpu] + Dawn
  /// `ID3D11Device`. Returns once the singleton is ready (or no-ops on
  /// non-Windows / when zero-copy is unsupported).
  ///
  /// Safe to call multiple times concurrently — overlapping calls share
  /// the same in-flight init future. Idempotent across recorder lifecycles:
  /// `start()` / `stop()` no longer re-create or destroy the GPU device.
  static Future<void> ensureSharedGpu() async {
    if (!Platform.isWindows) return;
    if (_sharedGpuUnsupported) return;
    if (_sharedGpu != null && _sharedD3d11Device != 0) return;
    _sharedGpuInitFuture ??= _initSharedGpuOnce();
    await _sharedGpuInitFuture;
  }

  static Future<void> _initSharedGpuOnce() async {
    try {
      final gpu = Minigpu();
      await gpu.init();
      if (!gpu.isExternalContentTypeSupported(
        ExternalContentType.d3d11SharedHandle,
      )) {
        _sharedGpuUnsupported = true;
        return;
      }
      final dev = gpu.createD3D11DeviceOnDawnAdapter();
      if (dev == 0) {
        _sharedGpuUnsupported = true;
        _log(
          'zero-copy GPU init: createD3D11DeviceOnDawnAdapter() '
          'returned 0 — Dawn backend may not be D3D11 or adapter not found.',
          RecorderLogLevel.warning,
        );
        return;
      }
      _sharedGpu = gpu;
      _sharedD3d11Device = dev;
      _log(
        'zero-copy GPU device ready '
        '(Dawn D3D11, device=0x${dev.toRadixString(16)}). '
        'Look for matching luid= in [shim] OpenSharedResource1 logs.',
      );
    } catch (e) {
      _log(
        'zero-copy GPU init failed ($e) — using CPU upload path.',
        RecorderLogLevel.warning,
      );
      _sharedGpuUnsupported = true;
    }
  }

  /// Explicitly release the process-global shared GPU resources.
  ///
  /// Call this from a Flutter hot-restart hook (`reassemble`) or app
  /// shutdown to avoid `Callback invoked after it has been deleted`
  /// crashes from native worker threads holding stale Dart callbacks.
  ///
  /// After this returns, the next [start] call (or [ensureSharedGpu]) will
  /// re-initialise the GPU. Callers should ensure no recorder is running.
  static Future<void> disposeSharedGpu() async {
    final gpu = _sharedGpu;
    _sharedGpu = null;
    _sharedD3d11Device = 0;
    _sharedGpuInitFuture = null;
    _sharedGpuUnsupported = false;
    if (gpu != null) {
      try {
        await gpu.destroy();
      } catch (_) {}
    }
  }

  // -----------------------------------------------------------------------
  // Unified log-level configuration
  // -----------------------------------------------------------------------

  /// Process-wide log callback installed via [setLogCallback].
  static void Function(
    RecorderLogSource source,
    RecorderLogLevel level,
    String message,
  )?
  _logCallback;

  /// Install a unified log callback that receives messages from every
  /// subsystem the recorder touches — all from a single import of
  /// `package:miniav_recorder/miniav_recorder.dart`.
  ///
  /// [callback] is invoked on the Dart event loop with:
  /// - `source` — which subsystem produced the message
  ///   ([RecorderLogSource.recorder], [RecorderLogSource.miniav], or
  ///   [RecorderLogSource.ffmpeg])
  /// - `level`   — severity, expressed as the closest [RecorderLogLevel]
  /// - `message` — the formatted, trimmed log line (no trailing newline)
  ///
  /// Pass `null` to remove the callback; all logs will fall back to Dart's
  /// `stderr` (the default behaviour).
  ///
  /// Call [setLogLevel] first (or after) to control the verbosity threshold
  /// on the native side — the callback receives only messages that pass that
  /// threshold.
  ///
  /// **minigpu / Dawn** logs are routed via [RecorderLogSource.minigpu].
  ///
  /// Example — write everything to a file:
  /// ```dart
  /// final sink = File('recorder.log').openWrite();
  /// Recorder.setLogCallback((source, level, msg) =>
  ///   sink.writeln('[${source.name}] ${level.name}: $msg'));
  /// Recorder.setLogLevel(RecorderLogLevel.verbose);
  /// ```
  static void setLogCallback(
    void Function(
      RecorderLogSource source,
      RecorderLogLevel level,
      String message,
    )?
    callback,
  ) {
    _logCallback = callback;
    _applyLogging();
  }

  /// Configure log verbosity for every native subsystem used by the recorder:
  ///
  /// - **MiniAV** (camera / screen / audio C library) — level + callback routing
  /// - **FFmpeg** (encoder / muxer) — AV_LOG_* level + callback routing via shim
  /// - **minigpu / Dawn** — level + callback routing via mgpuSetLogCallback
  ///
  /// If [setLogCallback] has been called, that callback receives the messages.
  /// Otherwise, messages are forwarded to Dart's `stderr`.
  ///
  /// Call before [start] (or as early as possible — before FFmpeg is loaded).
  /// Subsequent calls replace any previously installed callbacks.
  static void setLogLevel(RecorderLogLevel level) {
    _currentLevel = level;
    _applyLogging();
  }

  static RecorderLogLevel _currentLevel = RecorderLogLevel.info;

  static void _applyLogging() {
    final level = _currentLevel;
    final cb = _logCallback;

    // 1. MiniAV capture library.
    MiniAV.setLogLevel(miniavLogLevelFor(level));
    if (level == RecorderLogLevel.quiet) {
      MiniAV.setLogCallback(null);
    } else if (cb != null) {
      MiniAV.setLogCallback(
        (miniavLevel, msg) => cb(
          RecorderLogSource.miniav,
          _fromMiniAVLevel(miniavLevel),
          msg.trimRight(),
        ),
      );
    } else {
      MiniAV.installStderrLogger();
    }

    // 2. FFmpeg encoder / muxer (via shim — no-op if shim is not loaded yet;
    //    call setLogLevel again after ensureFFmpegLoaded() if needed).
    final shim = FfmpegShim.tryLoad();
    if (shim != null) {
      shim.setFfmpegLogLevel(avLogLevelFor(level));
      if (level == RecorderLogLevel.quiet) {
        shim.setFfmpegLogCallback(null);
      } else if (cb != null) {
        shim.setFfmpegLogCallback(
          (avLevel, msg) => cb(
            RecorderLogSource.ffmpeg,
            _fromAvLevel(avLevel),
            msg.trimRight(),
          ),
        );
      } else {
        shim.setFfmpegLogCallback((int avLevel, String msg) {
          if (msg.isEmpty) return;
          stderr.writeln('[ffmpeg] $msg');
        });
      }
    }

    // 3. minigpu / Dawn native GPU layer.
    final mgpuLevel = minigpuLevelFor(level);
    if (level == RecorderLogLevel.quiet) {
      Minigpu.setLogCallback(null, level: -1);
    } else if (cb != null) {
      Minigpu.setLogCallback(
        (mgpuLvl, msg) => cb(
          RecorderLogSource.minigpu,
          _fromMgpuLevel(mgpuLvl),
          msg.trimRight(),
        ),
        level: mgpuLevel,
      );
    } else {
      Minigpu.setLogCallback((_, msg) {
        if (msg.isEmpty) return;
        stderr.writeln('[minigpu] $msg');
      }, level: mgpuLevel);
    }
  }

  /// Route a recorder-internal log line through [_logCallback] (if set) or
  /// to [stderr]. All `[recorder]` messages in this file go through here.
  static void _log(
    String message, [
    RecorderLogLevel level = RecorderLogLevel.info,
  ]) {
    final cb = _logCallback;
    if (cb != null) {
      cb(RecorderLogSource.recorder, level, message);
    } else {
      stderr.writeln('[recorder] $message');
    }
  }

  // Private level-conversion helpers — intentionally not exposed; callers
  // use [miniavLogLevelFor] / [avLogLevelFor] for the forward direction.
  static RecorderLogLevel _fromMiniAVLevel(MiniAVLogLevel l) => switch (l) {
    MiniAVLogLevel.trace || MiniAVLogLevel.debug => RecorderLogLevel.verbose,
    MiniAVLogLevel.info => RecorderLogLevel.info,
    MiniAVLogLevel.warn => RecorderLogLevel.warning,
    MiniAVLogLevel.error => RecorderLogLevel.error,
    MiniAVLogLevel.none => RecorderLogLevel.quiet,
  };

  static RecorderLogLevel _fromAvLevel(int avLevel) {
    if (avLevel >= 48) return RecorderLogLevel.verbose; // AV_LOG_DEBUG+
    if (avLevel >= 32) return RecorderLogLevel.info; // AV_LOG_INFO/VERBOSE
    if (avLevel >= 24) return RecorderLogLevel.warning; // AV_LOG_WARNING
    if (avLevel >= 0) return RecorderLogLevel.error; // AV_LOG_ERROR/FATAL/PANIC
    return RecorderLogLevel.quiet; // AV_LOG_QUIET
  }

  /// Maps a [RecorderLogLevel] to the corresponding [MiniAVLogLevel].
  ///
  /// Exposed as a static so tests can assert the mapping without side effects.
  static MiniAVLogLevel miniavLogLevelFor(RecorderLogLevel level) =>
      switch (level) {
        RecorderLogLevel.verbose => MiniAVLogLevel.debug,
        RecorderLogLevel.info => MiniAVLogLevel.info,
        RecorderLogLevel.warning => MiniAVLogLevel.warn,
        RecorderLogLevel.error => MiniAVLogLevel.error,
        RecorderLogLevel.quiet => MiniAVLogLevel.none,
      };

  /// Maps a [RecorderLogLevel] to the corresponding FFmpeg `AV_LOG_*` level.
  ///
  /// Constants: `quiet=-8`, `error=16`, `warning=24`, `info=32`, `debug=48`.
  ///
  /// Exposed as a static so tests can assert the mapping without side effects.
  static int avLogLevelFor(RecorderLogLevel level) => switch (level) {
    RecorderLogLevel.verbose => 48, // AV_LOG_DEBUG
    RecorderLogLevel.info => 32, // AV_LOG_INFO
    RecorderLogLevel.warning => 24, // AV_LOG_WARNING
    RecorderLogLevel.error => 16, // AV_LOG_ERROR
    RecorderLogLevel.quiet => -8, // AV_LOG_QUIET
  };

  /// Maps a [RecorderLogLevel] to the corresponding mgpu log level int.
  ///
  /// mgpu levels: -1=none 0=debug 1=info 2=warn 3=error.
  ///
  /// Exposed as a static so tests can assert the mapping without side effects.
  static int minigpuLevelFor(RecorderLogLevel level) => switch (level) {
    RecorderLogLevel.verbose => 0, // LOG_DEBUG
    RecorderLogLevel.info => 1, // LOG_INFO
    RecorderLogLevel.warning => 2, // LOG_WARN
    RecorderLogLevel.error => 3, // LOG_ERROR
    RecorderLogLevel.quiet => -1, // LOG_NONE
  };

  /// Converts a native mgpu level int to [RecorderLogLevel].
  static RecorderLogLevel _fromMgpuLevel(int lvl) {
    if (lvl <= 0) return RecorderLogLevel.verbose; // LOG_DEBUG or below
    if (lvl == 1) return RecorderLogLevel.info; // LOG_INFO
    if (lvl == 2) return RecorderLogLevel.warning; // LOG_WARN
    return RecorderLogLevel.error; // LOG_ERROR
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
    await ensureSharedGpu();
    final gpu = _sharedGpu;
    final dev = _sharedD3d11Device;
    if (gpu == null || dev == 0) {
      _backendContext = null;
      return;
    }
    _backendContext = BackendContext(
      sharedGpu: gpu,
      d3d11DeviceHandle: dev,
      preferZeroCopy: true,
    );
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
      case MixedAudioRecorderSource():
        return _buildMixedAudioTrack(index, cfg);
    }
  }

  Future<_TrackRuntime> _buildScreenTrack(
    int index,
    ScreenRecorderSource cfg,
  ) async {
    // Resolve the display ID: accept whatever string enumerateDisplays()
    // returns, or null to mean "use the platform default display".
    String? resolvedDisplayId = cfg.displayId;
    if (resolvedDisplayId == null && cfg.windowId == null) {
      final displays = await MiniScreen.enumerateDisplays();
      if (displays.isEmpty) {
        throw StateError('addScreen: no displays found on this platform');
      }
      resolvedDisplayId = displays
          .firstWhere((d) => d.isDefault, orElse: () => displays.first)
          .deviceId;
    }
    final defaults = await MiniScreen.getDefaultFormats(
      resolvedDisplayId ?? cfg.windowId!,
    );
    var (videoFormat, _) = defaults;
    // Pick output preference: GPU when the recorder's zero-copy context
    // is live (so we can hand D3D11 textures straight to the encoder),
    // CPU otherwise (Stage A HW upload + libx264 SW both need plane bytes).
    final useGpuOutput = _backendContext != null;
    Recorder._log(
      'screen capture output: ${useGpuOutput ? "GPU (D3D11 zero-copy)" : "CPU"} '
      '— backendContext=${_backendContext != null}, '
      'd3d11Device=0x${(_backendContext?.d3d11DeviceHandle ?? 0).toRadixString(16)}',
    );
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
    if (resolvedDisplayId != null) {
      await ctx.configureDisplay(resolvedDisplayId, videoFormat);
    } else {
      await ctx.configureWindow(cfg.windowId!, videoFormat);
    }

    // Resolve target (encoder) dimensions: apply the scale policy on top of
    // the capture format. When a GPU processor is live the encoder is sized
    // to the smaller target; without GPU the encoder receives the full frame.
    final (int encW, int encH, GpuScreenProcessor? processor) = () {
      if (_backendContext == null) {
        if (cfg.effects.isNotEmpty) {
          Recorder._log(
            'WARNING: ${cfg.effects.length} effect(s) configured '
            'but no GPU context is available — effects will be skipped.',
            RecorderLogLevel.warning,
          );
        }
        return (videoFormat.width, videoFormat.height, null);
      }
      final target = cfg.scale.targetSize(
        videoFormat.width,
        videoFormat.height,
      );
      final (dstW, dstH) = target ?? (videoFormat.width, videoFormat.height);
      if (target != null) {
        Recorder._log(
          'screen downscale: '
          '${videoFormat.width}x${videoFormat.height} → ${dstW}x$dstH '
          '(${cfg.scale})',
        );
      }
      if (cfg.effects.isNotEmpty) {
        Recorder._log('screen effects: ${cfg.effects.length} effect(s) active');
      }
      final p = GpuScreenProcessor(
        gpu: _backendContext!.sharedGpu! as Minigpu,
        srcWidth: videoFormat.width,
        srcHeight: videoFormat.height,
        dstWidth: dstW,
        dstHeight: dstH,
        effects: cfg.effects,
      );
      if (p.outputWidth != dstW || p.outputHeight != dstH) {
        Recorder._log(
          'effects resize: ${dstW}x$dstH → '
          '${p.outputWidth}x${p.outputHeight}',
        );
      }
      return (p.outputWidth, p.outputHeight, p);
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
      quality: cfg.quality,
      encoderOptions: cfg.encoderOptions,
    );

    return _VideoTrackRuntime(
      index: index,
      label: 'screen[${resolvedDisplayId ?? cfg.windowId}]',
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
      quality: cfg.quality,
      encoderOptions: cfg.encoderOptions,
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
    HwAccelPreference hwAccel, {
    double? quality,
    Map<String, String> encoderOptions = const {},
  }) async {
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
      Recorder._log(
        '${format.width}x${format.height} exceeds H.264 HW cap; '
        'promoting ${codec.name} → ${effectiveCodec.name}',
        RecorderLogLevel.warning,
      );
    }

    // Map the normalized 0.0–1.0 quality knob to codec-specific CRF/ICQ.
    // The mapping inverts the scale (1.0 = best = lowest CRF number).
    RateControl effectiveRc = RateControl.vbr;
    int? effectiveCrf;
    if (quality != null) {
      final q = quality.clamp(0.0, 1.0);
      effectiveRc = wantHw ? RateControl.icq : RateControl.crf;
      if (wantHw) {
        // NVENC/QSV ICQ: 1 (best) – 51 (worst). Map 1.0→1, 0.0→51.
        effectiveCrf = 1 + ((1.0 - q) * 50).round();
      } else {
        // libx264/libx265 CRF: 0 (lossless) – 51 (worst). Map 1.0→10, 0.0→48.
        effectiveCrf = 10 + ((1.0 - q) * 38).round();
      }
    }

    // Base backend options, overridden by caller-supplied encoderOptions.
    final baseOptions = wantHw
        ? const {'preset': 'p4', 'tune': 'll', 'global_header': '1'}
        : const {
            'preset': 'ultrafast',
            'tune': 'zerolatency',
            'global_header': '1',
          };
    final mergedOptions = {...baseOptions, ...encoderOptions};

    final enc = await MiniAVTools.createEncoder(
      EncoderConfig(
        codec: effectiveCodec,
        width: format.width,
        height: format.height,
        bitrateBps: bitrate ?? defaultVideoBitrate,
        frameRateNumerator: format.frameRateNumerator,
        frameRateDenominator: format.frameRateDenominator,
        // Force a keyframe every ~2 seconds so a clip-buffer save can
        // always find an IDR within its window. Without this NVENC's
        // default GOP can be 250+ frames, which means a saveClip(N seconds)
        // call may begin mid-GOP and produce an MP4 with no decodable
        // video frames at the start (audio plays, video is missing).
        gopLength:
            (2 * format.frameRateNumerator) ~/
            (format.frameRateDenominator > 0 ? format.frameRateDenominator : 1),
        hwAccel: hwAccel,
        rateControl: effectiveRc,
        crfQuality: effectiveCrf,
        backendOptions: mergedOptions,
      ),
      preference: backendPreference,
      context: _backendContext,
    );
    Recorder._log(
      'video encoder = ${enc.backendName} '
      '(${enc.platform.runtimeType}) for ${effectiveCodec.name} '
      '${format.width}x${format.height}'
      '${quality != null ? ' quality=$quality (${effectiveRc.name} $effectiveCrf)' : ''}',
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
    Recorder._log(
      'audio encoder = ${encoder.backendName} '
      '(${encoder.platform.runtimeType}) for ${codec.name} '
      '${format.sampleRate}Hz/${format.channels}ch ($label)',
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

  Future<_TrackRuntime> _buildMixedAudioTrack(
    int index,
    MixedAudioRecorderSource cfg,
  ) async {
    // Fixed common format. Most Windows endpoints already deliver this
    // natively (WASAPI default for shared mode is 48 kHz f32 stereo), so
    // for the typical case the per-callback conversion is a no-op.
    const targetSampleRate = 48000;
    const targetChannels = 2;
    final targetFormat = MiniAVAudioInfo(
      format: MiniAVAudioFormat.f32,
      sampleRate: targetSampleRate,
      channels: targetChannels,
      numFrames: 1024,
    );

    // 1. Mic context.
    final micFmt = await MiniAudioInput.getDefaultFormat(cfg.micDeviceId);
    final micCtx = await MiniAudioInput.createContext();
    await micCtx.configure(cfg.micDeviceId, targetFormat);

    // 2. Loopback context.
    final loopFmt = await MiniLoopback.getDefaultFormat(cfg.loopbackDeviceId);
    final loopCtx = await MiniLoopback.createContext();
    await loopCtx.configure(cfg.loopbackDeviceId, targetFormat);

    // 3. Single audio encoder.
    final encoder = await MiniAVTools.createAudioEncoder(
      AudioEncoderConfig(
        codec: cfg.codec,
        sampleRate: targetSampleRate,
        channels: targetChannels,
        bitrateBps: cfg.bitrateBps ?? defaultAudioBitrate,
        backendOptions: const {'global_header': '1'},
      ),
      preference: backendPreference,
      context: _backendContext,
    );

    Recorder._log(
      'mixed audio: mic[${cfg.micDeviceId}] '
      '(native ${micFmt.sampleRate}Hz/${micFmt.channels}ch/${micFmt.format.name}) '
      '+ loopback[${cfg.loopbackDeviceId}] '
      '(native ${loopFmt.sampleRate}Hz/${loopFmt.channels}ch/${loopFmt.format.name}) '
      '→ ${targetSampleRate}Hz/${targetChannels}ch f32 → ${cfg.codec.name}',
    );

    return _MixedAudioTrackRuntime(
      index: index,
      label: 'mixed[mic=${cfg.micDeviceId},loop=${cfg.loopbackDeviceId}]',
      encoder: encoder,
      audioCodec: cfg.codec,
      micCtx: micCtx,
      loopCtx: loopCtx,
      micGain: _dbToLinear(cfg.micGainDb),
      loopGain: _dbToLinear(cfg.loopbackGainDb),
    );
  }

  /// Infer a [Container] from a file-path extension.
  ///
  /// Returns `null` for unrecognised extensions so callers can fall back to
  /// [_autoContainer].
  static Container? _sniffContainer(String path) => containerForExtension(path);

  /// Infer the best container for [tracks] when the caller did not specify one
  /// and the file extension offers no hint.
  ///
  /// Rules:
  /// - video + audio → MKV (handles any codec mix)
  /// - video only    → MP4
  /// - audio only    → M4A for AAC, MP3 for MP3, OGG for Opus, else MKV
  static Container _autoContainer(List<_TrackRuntime> tracks) {
    final hasVideo = tracks.any((t) => t is _VideoTrackRuntime);
    final hasAudio = tracks.any((t) => t is _AudioTrackRuntime);
    final audioCodecs = tracks
        .whereType<_AudioTrackRuntime>()
        .map((t) => t.audioCodec)
        .toSet();
    return containerForTrackMix(
      hasVideo: hasVideo,
      hasAudio: hasAudio,
      audioCodecs: audioCodecs,
    );
  }

  Future<_SinkRuntime> _buildSink(RecorderSink sink) async {
    switch (sink) {
      case FileRecorderSink():
        // Pick container: explicit override → extension sniff → track-mix heuristic.
        final container =
            sink.container ??
            _sniffContainer(sink.path) ??
            _autoContainer(_tracks);

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
            Recorder._log(
              'mux write track=${track.index}: $e',
              RecorderLogLevel.error,
            );
          }
        case _StreamSinkRuntime():
          try {
            s.onChunk(track.toChunk(routed));
          } catch (e) {
            Recorder._log('stream callback: $e', RecorderLogLevel.error);
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

  // Encode-error rate limiting: log the first error immediately, then at
  // most once every [_errorLogIntervalMs] ms, to avoid 30-per-second spam
  // drowning out other useful diagnostics.
  static const int _errorLogIntervalMs = 5000;
  int _lastErrorLogMs = 0;
  Object? _lastEncodeError;

  /// Minimum microseconds between encoded frames to enforce the configured fps.
  /// 0 means no throttle (device-controlled).
  int get _minFrameIntervalUs => frameRateDen > 0 && frameRateNum > 0
      ? (1000000 * frameRateDen) ~/ frameRateNum
      : 0;

  // Frame-rate diagnostics. Every ~2 seconds we log how many frames came in
  // from the capture callback, how many we dropped due to back-pressure, and
  // how many actually produced an encoded packet. This is invaluable when a
  // saved clip ends up with far fewer video frames than expected.
  int _statsFramesIn = 0;
  int _statsFramesDropped = 0;
  int _statsPacketsOut = 0;
  int _statsEncodeErrors = 0;
  int _statsMinPktBytes = 0x7fffffff;
  int _statsMaxPktBytes = 0;
  int _statsTotalPktBytes = 0;
  Stopwatch? _statsSw;

  @override
  Future<void> startCapture(Recorder rec) async {
    _statsSw = Stopwatch()..start();
    await startFn((MiniAVBuffer buffer, Object? _) {
      if (_stopping) {
        // Drop and release.
        unawaited(MiniAV.releaseBuffer(buffer));
        return;
      }
      _statsFramesIn++;
      _maybeLogStats();
      // SW fps throttle: drop frames arriving faster than the target rate.
      // Works even when the capture device ignores the fps hint (e.g. DXGI
      // always delivers at display refresh rate). Audio sync is not affected
      // because both tracks use independent wall-clock µs timestamps.
      final minInterval = _minFrameIntervalUs;
      if (minInterval > 0 && _lastVideoPtsUs >= 0) {
        final nowUs = rec.now();
        if (nowUs - _lastVideoPtsUs < minInterval) {
          _statsFramesDropped++;
          unawaited(MiniAV.releaseBuffer(buffer));
          return;
        }
      }
      if (_busy) {
        // Backpressure: drop this frame.
        _statsFramesDropped++;
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

  void _maybeLogStats() {
    final sw = _statsSw;
    if (sw == null) return;
    if (sw.elapsedMilliseconds < 2000) return;
    final secs = sw.elapsedMilliseconds / 1000.0;
    final avgPkt = _statsPacketsOut > 0
        ? (_statsTotalPktBytes / _statsPacketsOut).round()
        : 0;
    final pktRange = _statsPacketsOut > 0
        ? '${_statsMinPktBytes}..${_statsMaxPktBytes}B avg=${avgPkt}B'
        : 'none';
    final errStr = _statsEncodeErrors > 0
        ? ' ERRORS=${_statsEncodeErrors} (last: $_lastEncodeError)'
        : '';
    Recorder._log(
      '$label video stats over ${secs.toStringAsFixed(1)}s: '
      'in=${_statsFramesIn} (${(_statsFramesIn / secs).toStringAsFixed(1)} fps) '
      'dropped=${_statsFramesDropped} '
      'encoded=${_statsPacketsOut} '
      '(${(_statsPacketsOut / secs).toStringAsFixed(1)} fps) '
      'pkt=$pktRange$errStr',
    );
    _statsFramesIn = 0;
    _statsFramesDropped = 0;
    _statsPacketsOut = 0;
    _statsEncodeErrors = 0;
    _statsMinPktBytes = 0x7fffffff;
    _statsMaxPktBytes = 0;
    _statsTotalPktBytes = 0;
    sw.reset();
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
            width: proc.outputWidth,
            height: proc.outputHeight,
            pixelFormat: MiniAVPixelFormat.rgba32,
          );
          final pkt = await encoder.encode(src);
          if (pkt != null) {
            _statsPacketsOut++;
            _statsTotalPktBytes += pkt.data.length;
            if (pkt.data.length < _statsMinPktBytes)
              _statsMinPktBytes = pkt.data.length;
            if (pkt.data.length > _statsMaxPktBytes)
              _statsMaxPktBytes = pkt.data.length;
            await rec.dispatchPacket(
              this,
              pkt.copyWith(ptsUs: ptsUs, dtsUs: ptsUs),
            );
          }
          return;
        }
        // GPU processor returned null (resource init failed or handle invalid).
        // Fall through to the direct-encode path so the frame is not silently
        // dropped. The encoder may accept the D3D11 handle natively (e.g.
        // NVENC via AV_PIX_FMT_D3D11) without going through the GPU processor.
        Recorder._log(
          '$label GPU process() returned null — '
          'falling back to direct encode for this frame.',
          RecorderLogLevel.warning,
        );
      }

      // --- Normal / fallback path ----------------------------------------
      // Handles CPU buffers, and D3D11 buffers when the GPU processor is
      // absent or returned null above.
      final src = FrameSource.miniavBuffer(buffer);
      final pkt = await encoder.encode(src);
      if (pkt != null) {
        _statsPacketsOut++;
        _statsTotalPktBytes += pkt.data.length;
        if (pkt.data.length < _statsMinPktBytes)
          _statsMinPktBytes = pkt.data.length;
        if (pkt.data.length > _statsMaxPktBytes)
          _statsMaxPktBytes = pkt.data.length;
        await rec.dispatchPacket(
          this,
          pkt.copyWith(ptsUs: ptsUs, dtsUs: ptsUs),
        );
      }
    } catch (e, st) {
      _statsEncodeErrors++;
      _lastEncodeError = e;
      // Rate-limit: log on first occurrence and at most every 5 seconds after.
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (_lastErrorLogMs == 0 ||
          nowMs - _lastErrorLogMs > _errorLogIntervalMs) {
        _lastErrorLogMs = nowMs;
        Recorder._log('$label encode error: $e\n$st', RecorderLogLevel.error);
      }
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
    final isFirst = !_firstChunkSent;
    final extra = isFirst ? encoder.extraData?.bytes : null;
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
      videoWidth: isFirst ? width : null,
      videoHeight: isFirst ? height : null,
      videoFrameRateNum: isFirst ? frameRateNum : null,
      videoFrameRateDen: isFirst ? frameRateDen : null,
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
      Recorder._log('$label encode: $e\n$st', RecorderLogLevel.error);
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
    final isFirst = !_firstChunkSent;
    final extra = isFirst ? encoder.extraData?.bytes : null;
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
      sampleRate: isFirst ? sampleRate : null,
      channels: isFirst ? channels : null,
    );
  }
}

double _dbToLinear(double db) =>
    db == 0.0 ? 1.0 : math.pow(10.0, db / 20.0).toDouble();

class _MixedAudioTrackRuntime extends _TrackRuntime {
  _MixedAudioTrackRuntime({
    required super.index,
    required super.label,
    required this.encoder,
    required this.audioCodec,
    required this.micCtx,
    required this.loopCtx,
    required this.micGain,
    required this.loopGain,
  });

  final AudioEncoder encoder;
  final AudioCodec audioCodec;
  final MiniAudioInputContext micCtx;
  final MiniLoopbackContext loopCtx;
  final double micGain;
  final double loopGain;

  // Common output format. WASAPI shared-mode default on Windows is exactly
  // 48 kHz / stereo / f32, so for the typical case the per-callback work
  // is just a sum + soft-clip.
  static const int _outSampleRate = 48000;
  static const int _outChannels = 2;

  // Mic FIFO. The loopback callback drives encoding; mic samples wait here
  // until the loopback drains them.
  final _MixerRing _micRing = _MixerRing();

  // Watchdog: if mic stops producing we still want loopback to flow. Tracked
  // per drain tick so we don't pile up unbounded mic data on the ring.
  int _lastMicSamplesMs = 0;
  static const int _silenceTimeoutMs = 250;
  // Hard cap on mic backlog (~1 s of stereo f32 = ~384 KB). Stops the ring
  // from growing unboundedly if loopback is silent (e.g. nothing playing).
  static const int _maxMicBacklogFrames = _outSampleRate; // 1 s

  Recorder? _rec;
  Stopwatch? _wallClock;

  // Output frame counter (in frames). pts = framesOut * 1e6 / sr.
  int _framesOut = 0;

  bool _stopping = false;
  bool _firstChunkSent = false;

  // Sequential encode chain — chunks are always processed in arrival order.
  // Using a chain of futures (rather than the old _busyEncode drop pattern)
  // guarantees that no 10 ms window is ever silently discarded, which would
  // advance _framesOut without emitting audio and create a PTS hole heard
  // as a crackle.
  Future<void> _encodeChain = Future<void>.value();

  // Counters for silent-drop diagnostics, logged at most every 5 s.
  int _micBacklogDrops = 0;
  int _lastMicBacklogLogMs = 0;
  static const int _mixDropLogIntervalMs = 5000;

  // Reusable scratch buffer — sized to the largest loopback chunk we've
  // seen so we don't allocate a Float32List per callback.
  Float32List _scratch = Float32List(0);

  @override
  Future<void> startCapture(Recorder rec) async {
    _rec = rec;
    _wallClock = Stopwatch()..start();
    _lastMicSamplesMs = _wallClock!.elapsedMilliseconds;

    // Mic: lightweight — just convert to target f32 stereo and push to ring.
    await micCtx.startCapture((MiniAVBuffer buffer, Object? _) {
      try {
        if (_stopping) return;
        final audio = buffer.data;
        if (audio is! MiniAVAudioBuffer) return;
        final f32 = _toTargetF32(audio);
        _micRing.add(f32);
        _lastMicSamplesMs = _wallClock!.elapsedMilliseconds;
        // Drop oldest mic frames if loopback isn't draining (silent system).
        if (_micRing.frames > _maxMicBacklogFrames) {
          int dropped = 0;
          while (_micRing.frames > _maxMicBacklogFrames) {
            _micRing.take(_outSampleRate ~/ 10); // drop 100 ms
            dropped += _outSampleRate ~/ 10;
          }
          _micBacklogDrops += dropped;
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          if (_lastMicBacklogLogMs == 0 ||
              nowMs - _lastMicBacklogLogMs > _mixDropLogIntervalMs) {
            _lastMicBacklogLogMs = nowMs;
            Recorder._log(
              '$label mic ring overflow — dropped '
              '${_micBacklogDrops ~/ _outSampleRate * 1000}ms of mic audio '
              '(loopback silent or stalled)',
              RecorderLogLevel.warning,
            );
            _micBacklogDrops = 0;
          }
        }
      } finally {
        unawaited(MiniAV.releaseBuffer(buffer));
      }
    });

    // Loopback: drives encoding. Each callback delivers ~10 ms of audio at
    // 48 kHz f32 stereo (the WASAPI default). We mix mic in-place and feed
    // the encoder once. No timers, no extra allocations.
    await loopCtx.startCapture((MiniAVBuffer buffer, Object? _) {
      try {
        if (_stopping) return;
        final audio = buffer.data;
        if (audio is! MiniAVAudioBuffer) return;
        _onLoopbackChunk(audio);
      } finally {
        unawaited(MiniAV.releaseBuffer(buffer));
      }
    });
  }

  /// Convert mic capture buffer to interleaved f32 stereo at 48 kHz. This
  /// is the only allocation/conversion path for mic; loopback uses a
  /// reusable scratch buffer in `_onLoopbackChunk`.
  Float32List _toTargetF32(MiniAVAudioBuffer audio) {
    final inFmt = audio.info.format;
    final inCh = audio.info.channels;
    final inSr = audio.info.sampleRate;
    final inFrames = audio.frameCount;

    // 1. Decode interleaved input → float per-channel temp.
    final inSamples = inFrames * inCh;
    final flt = Float32List(inSamples);
    final src = audio.data;
    switch (inFmt) {
      case MiniAVAudioFormat.f32:
        final view = src.buffer.asFloat32List(src.offsetInBytes, inSamples);
        for (var i = 0; i < inSamples; i++) flt[i] = view[i];
      case MiniAVAudioFormat.s16:
        final view = src.buffer.asInt16List(src.offsetInBytes, inSamples);
        for (var i = 0; i < inSamples; i++) flt[i] = view[i] / 32768.0;
      case MiniAVAudioFormat.s32:
        final view = src.buffer.asInt32List(src.offsetInBytes, inSamples);
        for (var i = 0; i < inSamples; i++) flt[i] = view[i] / 2147483648.0;
      case MiniAVAudioFormat.u8:
        for (var i = 0; i < inSamples; i++) flt[i] = (src[i] - 128) / 128.0;
      case MiniAVAudioFormat.unknown:
        return Float32List(inFrames * _outChannels);
    }

    // 2. Channel mix → stereo.
    Float32List stereo;
    if (inCh == _outChannels) {
      stereo = flt;
    } else if (inCh == 1) {
      stereo = Float32List(inFrames * 2);
      for (var i = 0; i < inFrames; i++) {
        final s = flt[i];
        stereo[i * 2] = s;
        stereo[i * 2 + 1] = s;
      }
    } else {
      stereo = Float32List(inFrames * 2);
      for (var i = 0; i < inFrames; i++) {
        stereo[i * 2] = flt[i * inCh];
        stereo[i * 2 + 1] = flt[i * inCh + 1];
      }
    }

    // 3. Sample-rate convert (linear interpolation) → 48 kHz.
    if (inSr == _outSampleRate) return stereo;
    final ratio = _outSampleRate / inSr;
    final outFrames = (inFrames * ratio).floor();
    final out = Float32List(outFrames * 2);
    for (var i = 0; i < outFrames; i++) {
      final srcPos = i / ratio;
      final i0 = srcPos.floor();
      final i1 = (i0 + 1) < inFrames ? i0 + 1 : i0;
      final t = srcPos - i0;
      out[i * 2] = stereo[i0 * 2] * (1 - t) + stereo[i1 * 2] * t;
      out[i * 2 + 1] = stereo[i0 * 2 + 1] * (1 - t) + stereo[i1 * 2 + 1] * t;
    }
    return out;
  }

  /// Hot path. Called from the loopback capture thread for every chunk
  /// (~10 ms at 48 kHz f32 stereo on Windows). MUST be cheap.
  void _onLoopbackChunk(MiniAVAudioBuffer audio) {
    final loopFrames = audio.frameCount;
    final loopCh = audio.info.channels;
    final loopSr = audio.info.sampleRate;
    final loopFmt = audio.info.format;

    // Fast path: native 48 kHz / 2ch / f32 (the Windows default). Reinterpret
    // the bytes directly — no copy, no resample.
    Float32List loopStereo;
    if (loopFmt == MiniAVAudioFormat.f32 &&
        loopCh == _outChannels &&
        loopSr == _outSampleRate) {
      loopStereo = audio.data.buffer.asFloat32List(
        audio.data.offsetInBytes,
        loopFrames * _outChannels,
      );
    } else {
      // Slow path: same conversion as mic.
      loopStereo = _toTargetF32(audio);
    }

    final outFrames = loopStereo.length ~/ _outChannels;
    final outSamples = outFrames * _outChannels;

    // Reuse scratch buffer when possible.
    if (_scratch.length < outSamples) {
      _scratch = Float32List(outSamples);
    }
    final mix = _scratch;

    // Apply loopback gain into scratch.
    if (loopGain == 1.0) {
      mix.setRange(0, outSamples, loopStereo);
      // Zero the tail if scratch is bigger than this chunk.
      for (var i = outSamples; i < mix.length; i++) mix[i] = 0;
    } else {
      for (var i = 0; i < outSamples; i++) mix[i] = loopStereo[i] * loopGain;
    }

    // Mix mic on top — only if recent samples have been received and the
    // ring has at least this many frames; otherwise pad with silence.
    final nowMs = _wallClock?.elapsedMilliseconds ?? 0;
    final micAlive = (nowMs - _lastMicSamplesMs) <= _silenceTimeoutMs;
    if (micAlive && _micRing.frames >= outFrames) {
      final mic = _micRing.take(outFrames);
      if (micGain == 1.0) {
        for (var i = 0; i < outSamples; i++) mix[i] += mic[i];
      } else {
        for (var i = 0; i < outSamples; i++) mix[i] += mic[i] * micGain;
      }
    } else if (micAlive) {
      // Mic is alive but ring is short (e.g. capture just started or mic
      // is running slightly slower than loopback). Take what we can.
      final avail = _micRing.frames;
      if (avail > 0) {
        final mic = _micRing.take(avail);
        final n = avail * _outChannels;
        if (micGain == 1.0) {
          for (var i = 0; i < n; i++) mix[i] += mic[i];
        } else {
          for (var i = 0; i < n; i++) mix[i] += mic[i] * micGain;
        }
      }
    }

    // Soft-clip in-place.
    for (var i = 0; i < outSamples; i++) {
      final s = mix[i];
      if (s > 1.0) {
        mix[i] = 1.0;
      } else if (s < -1.0) {
        mix[i] = -1.0;
      }
    }

    // Hand the (still-scratch-backed) PCM to the encoder. We must copy here
    // because the encode is async and we will overwrite scratch on the next
    // callback. Copy is `outSamples * 4` bytes — ~4 KB for 10 ms.
    final pcm = Uint8List(outSamples * 4);
    pcm.buffer
        .asFloat32List(0, outSamples)
        .setAll(0, mix.sublist(0, outSamples));

    final ptsUs = _framesOut * 1000000 ~/ _outSampleRate;
    _framesOut += outFrames;

    // Chain this chunk onto the sequential encode queue so it is processed
    // in order and never dropped. If a previous encode+mux write is still
    // pending (e.g. the muxer's async future hasn't settled yet), this chunk
    // waits behind it rather than being discarded.
    _encodeChain = _encodeChain.then<void>(
      (_) => _encodeMix(pcm, outFrames, ptsUs),
    );
  }

  @override
  Future<void> drainInFlight() => _encodeChain;

  Future<void> _encodeMix(Uint8List pcm, int frameCount, int ptsUs) async {
    try {
      final pkts = await encoder.encode(
        pcm: pcm,
        format: MiniAVAudioFormat.f32,
        frameCount: frameCount,
        ptsUs: ptsUs,
      );
      final rec = _rec;
      if (rec == null) return;
      for (final p in pkts) {
        await rec.dispatchPacket(this, p);
      }
    } catch (e, st) {
      Recorder._log('$label mix encode: $e\n$st', RecorderLogLevel.error);
    }
  }

  @override
  Future<void> stopCapture() async {
    _stopping = true;
    try {
      await micCtx.stopCapture();
    } catch (_) {}
    try {
      await loopCtx.stopCapture();
    } catch (_) {}
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
      await micCtx.destroy();
    } catch (_) {}
    try {
      await loopCtx.destroy();
    } catch (_) {}
    try {
      await encoder.close();
    } catch (_) {}
  }

  @override
  TrackInfo toTrackInfo() => AudioTrackInfo(
    codec: audioCodec,
    sampleRate: _outSampleRate,
    channels: _outChannels,
  );

  @override
  FfmpegEncoderBridge? get encoderBridge {
    final p = encoder.platform;
    return p is FfmpegEncoderBridge ? p as FfmpegEncoderBridge : null;
  }

  @override
  TrackChunk toChunk(EncodedPacket pkt) {
    final isFirst = !_firstChunkSent;
    final extra = isFirst ? encoder.extraData?.bytes : null;
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
      sampleRate: isFirst ? _outSampleRate : null,
      channels: isFirst ? _outChannels : null,
    );
  }
}

/// Minimal FIFO of interleaved stereo float32 samples, in **frames**
/// (1 frame = `_outChannels` samples).
class _MixerRing {
  final List<Float32List> _chunks = [];
  int _headOffset = 0; // sample offset into _chunks[0]
  int _totalSamples = 0;

  /// Frames currently buffered.
  int get frames => _totalSamples ~/ _MixedAudioTrackRuntime._outChannels;

  void add(Float32List samples) {
    if (samples.isEmpty) return;
    _chunks.add(samples);
    _totalSamples += samples.length;
  }

  /// Remove [frames] frames and return them as interleaved stereo f32.
  Float32List take(int frames) {
    final wanted = frames * _MixedAudioTrackRuntime._outChannels;
    final out = Float32List(wanted);
    var written = 0;
    while (written < wanted) {
      final head = _chunks[0];
      final available = head.length - _headOffset;
      final take = (wanted - written) < available
          ? (wanted - written)
          : available;
      out.setRange(written, written + take, head, _headOffset);
      written += take;
      _headOffset += take;
      _totalSamples -= take;
      if (_headOffset >= head.length) {
        _chunks.removeAt(0);
        _headOffset = 0;
      }
    }
    return out;
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

// =========================================================================
// RecorderGroup — synchronised multi-recorder controller.
// =========================================================================

/// Holds multiple [Recorder] instances and starts/stops them with a
/// synchronised master clock.
///
/// The [start] implementation runs the slow prepare phase of every recorder
/// concurrently (opens encoders, muxers, GPU devices), then starts all master
/// clocks and capture sources in a tight sequential loop to minimise clock
/// skew between recorders.
///
/// Build your [Recorder] instances via [RecorderBuilder], then pass them in:
///
/// ```dart
/// final avRec  = (RecorderBuilder()
///       ..addScreen()                   // platform default display
///       ..addLoopback(deviceId: loopDev)
///       ..addFileOutput('av.mp4'))
///     .build();
/// final micRec = (RecorderBuilder()
///       ..addMic(deviceId: micDev, codec: AudioCodec.aac)
///       ..addFileOutput('mic.m4a'))     // auto-picks Container.m4a
///     .build();
///
/// final group = RecorderGroup([avRec, micRec]);
/// await group.start();
/// await Future.delayed(const Duration(seconds: 10));
/// await group.stop();
/// ```
class RecorderGroup {
  /// The individual [Recorder] instances managed by this group.
  final List<Recorder> recorders;

  /// Create a group from already-built [Recorder] instances.
  const RecorderGroup(this.recorders);

  /// Prepare all recorders concurrently (opens encoders, muxers, GPU), then
  /// launch all master clocks + capture sources in quick succession.
  Future<void> start() async {
    await Future.wait(recorders.map((r) => r._prepare()));
    for (final r in recorders) {
      await r._launch();
    }
  }

  /// Stop all recorders concurrently.
  Future<void> stop() => Future.wait(recorders.map((r) => r.stop()));
}
