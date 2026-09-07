/// Recorder runtime: opens encoders + muxers, wires capture sources to
/// encoders, fans encoded packets out to every sink, and drains cleanly
/// on stop.
library;

import 'dart:async';
import 'dart:ffi' show Pointer, Void;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:miniav/miniav.dart';
import 'package:miniav_tools/miniav_tools.dart';
import 'package:miniav_tools_codecs/miniav_tools_codecs.dart'
    show
        ContainerFramingBackend,
        MfVideoEncoder,
        Mp4ConfigChange,
        registerFirstPartyBackends;
import 'package:miniav_tools_ffmpeg/miniav_tools_ffmpeg.dart';
import 'package:minigpu/minigpu.dart';

import 'adaptive_gpu_throttle.dart';
import 'bounded_write_queue.dart';
import 'capture_recovery.dart';
import 'finalize_progress.dart';
import 'mux_sink.dart';
import '../workers/mux_worker.dart'
    show muxPhaseClosing, muxPhaseWritingIndex;
import 'worker_mux_sink.dart';
import 'container_utils.dart';
import 'frame_pacer.dart';
import 'gpu_screen_processor.dart';
import 'recorder_log.dart';
import 'recorder_sink.dart';
import 'recorder_source.dart';
import 'track_chunk.dart';

export 'finalize_progress.dart';
export 'recorder_log.dart' show RecorderLogLevel, RecorderLogSource;

/// Run [build], destroying everything it registered in [debris] if it throws.
///
/// A half-finished build has already created native objects — a capture
/// context, an encoder — and dropping the reference does not release them.
/// One-off at start, where the recorder fails to start anyway; a leak PER
/// ATTEMPT in [Recorder.rebuildVideoStage], which runs the same builder every
/// few seconds for the whole length of an outage.
///
/// Newest first, because the later objects were built against the earlier
/// ones: an encoder bound to a capture context has to go before the context
/// does. A destroy that throws is expected — after a device reset every
/// teardown fails — and must not strand the ones behind it.
///
/// [debris] is cleared either way: on success the returned runtime owns them
/// and disposes them itself.
Future<T> buildGuarded<T>(
  List<Future<void> Function()> debris,
  Future<T> Function() build,
) async {
  debris.clear();
  try {
    final built = await build();
    debris.clear();
    return built;
  } catch (_) {
    for (final destroy in debris.reversed) {
      try {
        await destroy();
      } catch (_) {
        // Already-dead objects are the normal case here.
      }
    }
    debris.clear();
    rethrow;
  }
}

/// Why a display no longer looks like the one a quiet capture is attached to,
/// or null when it still does.
///
/// The one question that separates a still desktop from a dead capture: both
/// deliver nothing, and only one of them is bound to a display that has since
/// changed shape or gone away. [deliveredW]/[deliveredH] are what the platform
/// last handed over — NOT the encoder's dimensions, which are pinned by what
/// the container already declared and would differ from the monitor on any
/// recording that downscales.
///
/// Deliberately conservative. Everything it cannot establish is null, leaving
/// the decision to the silence window, because a wrong "yes" here re-acquires
/// a capture that was working. Pure, so the comparison that decides is
/// exercised without a monitor to re-route.
String? displayDriftReason({
  required String display,
  required bool attached,
  required int deliveredW,
  required int deliveredH,
  required int currentW,
  required int currentH,
}) {
  if (!attached) return 'display $display is no longer attached';
  // Nothing delivered yet, so there is nothing to compare against.
  if (deliveredW <= 0 || deliveredH <= 0) return null;
  if (currentW <= 0 || currentH <= 0) {
    return 'display $display reports no size at all';
  }
  if (currentW != deliveredW || currentH != deliveredH) {
    return 'display $display is now ${currentW}x$currentH but the capture is '
        'still delivering ${deliveredW}x$deliveredH';
  }
  return null;
}

/// The capture target a track was built for is not present right now.
///
/// Distinct from a failure because it is the EXPECTED answer for the whole
/// length of the outage this recorder recovers from: a display that has been
/// re-routed by Win+P or undocked is absent for as long as the user leaves it
/// that way, and every attempt in between is supposed to come back empty.
///
/// Separating it earns two things. A re-acquire can wait through it quietly
/// instead of printing an identical error and stack trace every few seconds —
/// which is what buries the one line that says something is wrong. And an
/// application that gets this from [Recorder.start] learns something it can act
/// on: the display it asked for is not attached, so ask the user for a
/// different one, rather than "MINIAV_ERROR_SYSTEM_CALL_FAILED".
class CaptureTargetUnavailable implements Exception {
  const CaptureTargetUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The device id that names [requestedId]'s device in [devices] right now.
///
/// Returns [requestedId] when that id is still live, a DIFFERENT id when the
/// same device is present under a new one, and null when no single device
/// answers to it.
///
/// **A device id can be a live platform handle rather than a name.** The
/// clearest case is a display: on Windows the id is literally an HMONITOR
/// pointer (`HMONITOR:0x...`), and Windows destroys its monitor objects and
/// issues new ones whenever the desktop topology changes -- Win+P,
/// dock/undock, a mode change, an RDP transition. The old handle does not come
/// back. `GetMonitorInfo` on it fails, so the capture reports 0x0, and
/// `CreateForMonitor` on it fails, and will keep failing for as long as anyone
/// retries.
///
/// That is precisely the family of losses [CaptureLossPolicy.reacquire] exists
/// for, so re-acquiring against the stored id could never have worked. What
/// survives is the platform's device NAME (`\\.\DISPLAY1` on Windows) -- the
/// same key an application matches on when it picks a device to record.
///
/// Applied to every device class, not only displays. Audio endpoint ids and
/// camera symbolic links are far more stable than an HMONITOR, so they take
/// the first branch and behave exactly as before; the cost of asking is one
/// enumeration per re-acquire attempt, and the benefit is that a class whose
/// ids turn out NOT to be stable -- on some driver, on some platform -- is
/// already handled rather than discovered in a field log.
///
/// Two limits of the name identity, since this leans on it:
///
/// * A name can follow a PORT rather than a thing. `\\.\DISPLAY1` names an
///   adapter output: unplug one monitor and plug a different one into the same
///   port and the name follows the port. Within the transient family -- the
///   device goes away and the same setup comes back -- it is exact, and that
///   is the case this recovers.
/// * A still-live id always wins, so a class whose ids are already stable
///   (a portal token, a CGDirectDisplayID, an MMDevice endpoint id) never
///   reaches the name path at all.
///
/// Pure, so the transitions it exists for can be exercised directly: all of
/// them are statements about what the enumeration says, and none of them need
/// a device to physically unplug.
String? resolveDeviceTarget({
  required String requestedId,
  required String? knownName,
  required List<MiniAVDeviceInfo> devices,
}) {
  for (final d in devices) {
    if (d.deviceId == requestedId) return requestedId;
  }
  if (knownName == null || knownName.isEmpty) {
    // Never seen alive, so there is nothing to re-resolve BY. Hand the id back
    // and let the configure attempt produce the platform's own error rather
    // than inventing a target here.
    return requestedId;
  }
  MiniAVDeviceInfo? match;
  for (final d in devices) {
    if (d.name != knownName) continue;
    // Two devices under one name: the name has stopped identifying a single
    // device, and picking one of them would be choosing a recording target on
    // the user's behalf. Wait instead.
    if (match != null) return null;
    match = d;
  }
  return match?.deviceId;
}

/// Run-time state of an open [Recorder].
/// Live health of one capture source, readable at any point during a
/// recording.
///
/// [Recorder.captureIssues] only exists once [Recorder.stop] has run, which is
/// too late for the case this was built for: a long session where the operator
/// could have intervened if anything had told them the screen stopped being
/// recorded forty minutes ago. Poll this instead.
class RecorderCaptureStatus {
  const RecorderCaptureStatus({
    required this.label,
    required this.lost,
    required this.ended,
    required this.lossCount,
    required this.recoveryCount,
    required this.rebuildCount,
    required this.secondsMissing,
  });

  /// The source this describes, e.g. `screen[HMONITOR:0x…]`.
  final String label;

  /// The capture target is gone right now and a re-acquire is in progress.
  /// Frames are not being recorded for this source while this holds.
  final bool lost;

  /// This source has stopped for good — its target never came back, or the
  /// policy said not to wait. Every other track keeps recording, and the file
  /// stays valid; it simply has no more video after this point.
  final bool ended;

  /// How many times the target has disappeared this session.
  final int lossCount;

  /// How many of those were recovered.
  final int recoveryCount;

  /// Recoveries that needed the whole GPU stage rebuilt rather than the
  /// capture re-configured — a graphics device reset rather than a display
  /// being re-routed. Worth reporting separately: it points at a driver.
  final int rebuildCount;

  /// Total seconds of this source missing from the recording, including an
  /// outage that is still open.
  final double secondsMissing;

  /// Nothing has gone wrong with this source.
  bool get healthy => !lost && !ended && lossCount == 0;

  @override
  String toString() => healthy
      ? '$label: ok'
      : '$label: ${ended ? "ENDED" : lost ? "LOST (recovering)" : "recovered"}'
          ' — $lossCount loss(es), $recoveryCount recovered'
          '${rebuildCount > 0 ? " ($rebuildCount via device rebuild)" : ""},'
          ' ${secondsMissing.toStringAsFixed(1)}s missing';
}

enum RecorderState { idle, starting, running, stopping, stopped, errored }

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

  /// Set in [_prepare]: at least one file sink can only be written by
  /// `FfmpegMuxer`, so this recording's audio must be FFmpeg-encoded. See
  /// [recordingRequiresFfmpegMuxer] for why that coupling exists and
  /// [_audioBackendPreference] for what it does.
  bool _ffmpegMuxerRequired = false;

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
  final List<TrackRuntime> _tracks = [];

  // Per-file-sink muxer; stream sinks have no muxer, just a callback.
  final List<_SinkRuntime> _sinks = [];

  Object? _lastError;
  Object? get lastError => _lastError;

  // -----------------------------------------------------------------------
  // Warmup
  // -----------------------------------------------------------------------

  /// Warm up every registered tools backend ahead of the first [start] —
  /// for the FFmpeg backend that means downloading + loading the shared
  /// libraries (a one-time multi-MB download on a fresh machine).
  ///
  /// Registers the FFmpeg backend first, so this works from `main()` /
  /// `initState` with only a `miniav_recorder` import. Calling
  /// `MiniAVTools.warmup()` directly does NOT do that: backend registration
  /// otherwise happens lazily inside [start], so a too-early warmup would
  /// silently skip FFmpeg and the download would still hit the first
  /// recording.
  ///
  /// Same stream contract as [MiniAVTools.warmup]: emits [WarmupProgress]
  /// events (`fraction` is the download progress), never errors — failures
  /// arrive as events with `error` set — and completes when all backends
  /// are warm. Safe to call repeatedly; a no-op when everything is cached.
  ///
  /// ```dart
  /// await Recorder.warmup().last; // block until warm
  /// ```
  static Stream<WarmupProgress> warmup() {
    registerFfmpegBackend();
    return MiniAVTools.warmup();
  }

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
      // Same story for the first-party backends, and they go in FIRST so the
      // negotiation below is a real contest rather than "whatever was loaded".
      // This is what makes the FFmpeg-free path — Media Foundation hardware
      // H.264/HEVC, OS AAC, first-party MP4 framing — the default for recording
      // apps without a line of per-app setup. It does not force the outcome:
      // each backend reports capability honestly and FFmpeg still wins where it
      // is genuinely the better path (see registerFirstPartyBackends).
      registerFirstPartyBackends();

      // Route BEFORE anything is negotiated: which muxer each file sink needs
      // constrains which backend may encode this recording's audio. Registering
      // the first-party backends above makes OS AAC (priority 55) outbid FFmpeg
      // (50) for AAC, and FfmpegMuxer cannot describe an audio track it did not
      // encode — so for a sink only FFmpeg can write, the audio negotiation has
      // to be pinned to FFmpeg too. Deciding it here, from the configs, is the
      // only place the answer can still change anything.
      _ffmpegMuxerRequired = recordingRequiresFfmpegMuxer(
        fileSinks: [
          for (final s in _sinkConfigs)
            if (s is FileRecorderSink) (container: s.container, path: s.path),
        ],
        videoCodecs: _configuredVideoCodecs(),
        audioCodecs: _configuredAudioCodecs(),
        audioTracks: _configuredAudioTrackCount(),
      );
      if (_ffmpegMuxerRequired) _checkFfmpegAudioReachable();

      await ensureFFmpegLoaded();

      // Lazily try to bring up the shared GPU device for zero-copy. Only
      // worth doing on Windows when the user opted in. On any failure we
      // silently fall back to the CPU upload path — the rest of the
      // recorder is fully functional without it.
      await _maybeInitSharedGpu();

      // 1. Build each track (open encoder + record capture config).
      for (var i = 0; i < _sourceConfigs.length; i++) {
        final cfg = _sourceConfigs[i];
        final track = await guardedBuild(() => _buildTrack(i, cfg));
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
    // Where the time goes. Every phase below does synchronous FFI — closing
    // encoders, destroying capture contexts, building a sample index over
    // hundreds of thousands of samples — on whatever isolate called stop,
    // which in a Flutter app is the one drawing the UI. A shutdown that runs
    // long is a visible freeze, and which phase did it is not guessable from
    // the outside.
    final phases = <String, int>{};
    final sw = Stopwatch()..start();
    _finalizeClock = sw;
    _emitPhase(RecorderFinalizePhase.stoppingCapture);
    var lastMs = 0;
    void mark(String phase) {
      final now = sw.elapsedMilliseconds;
      phases[phase] = now - lastMs;
      lastMs = now;
    }

    // 1. Stop captures (so no more frames arrive).
    for (final t in _tracks) {
      try {
        await t.stopCapture();
      } catch (e) {
        _log('stopCapture(${t.label}): $e', RecorderLogLevel.error);
      }
    }
    _masterClock.stop();
    mark('stop capture');
    _emitPhase(RecorderFinalizePhase.draining);

    // Collect capture-level problems BEFORE _tracks is cleared below. A file
    // that is short because its display went away is not distinguishable from
    // a file that is short because the user stopped early - not from the
    // output, and not from a stop() that returned normally. This is the only
    // place that difference is still knowable.
    for (final t in _tracks) {
      for (final issue in t.captureLossSummaries) {
        _captureIssues.add(issue);
        _log(issue, RecorderLogLevel.warning);
      }
    }

    // 2. Wait for any in-flight encode operations.
    for (final t in _tracks) {
      await t.drainInFlight();
    }
    mark('drain');
    _emitPhase(RecorderFinalizePhase.flushing);

    // 3. Flush encoders + push trailing packets to every sink.
    for (final t in _tracks) {
      try {
        await t.flushAndDispatch(this);
      } catch (e) {
        _log('flush(${t.label}): $e', RecorderLogLevel.error);
      }
    }
    mark('flush');
    // The worker announces the index phase itself for the file it is writing.
    // This covers the in-process fallback, where nothing else will.
    if (_sinks.every((s) => s is! _FileSinkRuntime)) {
      _emitPhase(RecorderFinalizePhase.writingIndex);
    }

    // 4. Finish + close every muxer.
    for (final s in _sinks) {
      try {
        await s.finish();
      } catch (e) {
        _log('finish sink: $e', RecorderLogLevel.error);
      }
    }
    // Writing the container index. Synchronous, and proportional to the SAMPLE
    // COUNT rather than the file size — an hour of 30fps video plus AAC is
    // roughly a quarter of a million entries across stts/stsz/stco/ctts.
    mark('write index');
    _emitPhase(RecorderFinalizePhase.closing);

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
    mark('dispose');
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

    final total = sw.elapsedMilliseconds;
    final breakdown =
        phases.entries.map((e) => '${e.key} ${e.value}ms').join(', ');
    _log(
      'shutdown took ${total}ms ($breakdown)',
      // A third of a second is roughly where a freeze stops being deniable.
      total >= 333 ? RecorderLogLevel.warning : RecorderLogLevel.info,
    );
    _emitPhase(RecorderFinalizePhase.done);
    _finalizeClock = null;
  }

  // -----------------------------------------------------------------------
  // Static GPU lifecycle (process-global)
  // -----------------------------------------------------------------------

  /// Bind the process-global GPU context to the adapter driving the PRIMARY
  /// display (Windows), so screen capture → GPU processing → HW encode all
  /// stay on one adapter (same-adapter zero-copy). On hybrid systems where a
  /// discrete GPU is also present this routes the pipeline through the
  /// display GPU — e.g. an AMD/Intel iGPU showing the desktop — which is the
  /// only topology where that iGPU's HW encoder (AMF/QSV) can be fed
  /// zero-copy.
  ///
  /// MUST be called before ANY minigpu use in the process (including
  /// unrelated features such as audio visualizers): the native context is
  /// created once per process and its adapter cannot change afterwards.
  /// Returns `true` when the hint was applied before the context existed;
  /// `false` (with a warning log) when it was too late or the platform has
  /// no adapter selection.
  ///
  /// Trade-off: ALL of this process's minigpu compute then runs on the
  /// display adapter. The `MGPU_ADAPTER_NAME` env var overrides this hint.
  static bool preferCaptureAdapter({bool enable = true}) {
    if (!Platform.isWindows) return false;
    final applied = Minigpu.preferDisplayAdapter(enable);
    if (!applied && enable) {
      _log(
        'preferCaptureAdapter: GPU context already initialized — the hint '
        'must be set before any minigpu use (call this at app startup). '
        'Current adapter kept; capture may take the cross-adapter path.',
        RecorderLogLevel.warning,
      );
    }
    return applied;
  }

  /// Idempotently initialise the process-global shared [Minigpu] + Dawn
  /// `ID3D11Device`. Returns once the singleton is ready (or no-ops on
  /// non-Windows / when zero-copy is unsupported).
  ///
  /// Safe to call multiple times concurrently — overlapping calls share
  /// the same in-flight init future. Idempotent across recorder lifecycles:
  /// `start()` / `stop()` no longer re-create or destroy the GPU device.
  ///
  /// After calling this, use [sharedGpu] to obtain the [Minigpu] instance
  /// (null if GPU is unsupported on this platform).
  static Future<void> ensureSharedGpu() async {
    if (!Platform.isWindows) return;
    if (_sharedGpuUnsupported) return;
    if (_sharedGpu != null && _sharedD3d11Device != 0) return;
    _sharedGpuInitFuture ??= _initSharedGpuOnce();
    await _sharedGpuInitFuture;
  }

  /// The process-global [Minigpu] instance, or `null` when GPU is
  /// unsupported / not yet initialised. Call [ensureSharedGpu] first.
  static Minigpu? get sharedGpu => _sharedGpu;

  /// Whether the loaded minigpu native binary contains the event-drain fix,
  /// or `null` when it cannot be asked (non-native, or minigpu < 1.5.8).
  ///
  /// Exposed so an app can surface this in a diagnostics screen; the recorder
  /// checks it itself at GPU init and warns once.
  static bool? get gpuDrainFixPresent {
    final budget = Minigpu.drainSpinBudgetMs;
    return budget == null ? null : budget > 0;
  }

  static bool _drainFixChecked = false;

  /// Warns once if the loaded minigpu binary predates the event-drain fix.
  ///
  /// Without it every GPU wait rounds up to the Windows timer quantum
  /// (~15.6 ms). The per-frame GPU stage takes several such waits, so at 60 fps
  /// (16.67 ms budget) the stage overruns on its own, [AdaptiveGpuThrottle]
  /// reads that as a saturated GPU and steps the live capture rate down — i.e.
  /// a stale native artifact presents as recording stutter with no error
  /// anywhere. This is a mistake that is otherwise silent: the DLL is bundled
  /// as a build artifact and a stale one loads perfectly happily.
  static void _assertDrainFixPresent() {
    if (_drainFixChecked) return;
    _drainFixChecked = true;
    final budget = Minigpu.drainSpinBudgetMs;
    if (budget == null) {
      _log(
        'minigpu drain-fix check unavailable (Minigpu.drainSpinBudgetMs is '
        'null) — the loaded native binary predates minigpu 1.5.8, or the '
        'symbol is missing. If recordings stutter, rebuild the native asset: '
        'rm -rf .dart_tool/hooks_runner && dart pub get.',
        RecorderLogLevel.warning,
      );
    } else if (budget <= 0) {
      _log(
        'minigpu event drain is running in PRE-FIX mode (spin budget '
        '${budget}ms) — every GPU wait costs a ~15.6 ms timer quantum and '
        'recordings WILL stutter. Unset MGPU_DRAIN_SPIN_MS (it is an A/B '
        'measurement mode, not a setting).',
        RecorderLogLevel.error,
      );
    }
  }

  static Future<void> _initSharedGpuOnce() async {
    try {
      final gpu = Minigpu();
      await gpu.init();
      _assertDrainFixPresent();
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
  /// Pass `null` to remove the callback; all logs will fall back to the
  /// console via `print` (the default behaviour — deliberately not
  /// `dart:io` `stderr`, which throws an uncatchable async error in
  /// console-less Windows GUI apps).
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
    recorderLogCallback = callback;
    _applyLogging();
  }

  /// Configure log verbosity for every native subsystem used by the recorder:
  ///
  /// - **MiniAV** (camera / screen / audio C library) — level + callback routing
  /// - **FFmpeg** (encoder / muxer) — AV_LOG_* level + callback routing via
  ///   shim, plus the miniav_tools_ffmpeg Dart layer (downloader, encoder
  ///   selection, vendor probing)
  /// - **minigpu / Dawn** — level + callback routing via mgpuSetLogCallback
  ///
  /// If [setLogCallback] has been called, that callback receives the messages.
  /// Otherwise, messages are forwarded to the console via `print`.
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

    // Every bridge below funnels into [recorderLog], which forwards to the
    // callback installed via [setLogCallback] or to the safe `print` default.

    // 1. MiniAV capture library.
    MiniAV.setLogLevel(miniavLogLevelFor(level));
    if (level == RecorderLogLevel.quiet) {
      // Install a no-op callback rather than null. Passing null to
      // MiniAV_SetLogCallback removes the Dart bridge and causes the C
      // library to fall back to its own built-in stderr logger
      // ("[MiniAV C - DEBUG]: ..."). A no-op callback absorbs messages
      // on the Dart side so the native default logger is never activated.
      MiniAV.setLogCallback((_, __) {});
    } else {
      MiniAV.setLogCallback(
        (miniavLevel, msg) => recorderLog(
          RecorderLogSource.miniav,
          _fromMiniAVLevel(miniavLevel),
          msg.trimRight(),
        ),
      );
    }

    // 2. FFmpeg encoder / muxer (via shim — no-op if shim is not loaded yet;
    //    call setLogLevel again after ensureFFmpegLoaded() if needed).
    final shim = FfmpegShim.tryLoad();
    if (shim != null) {
      shim.setFfmpegLogLevel(avLogLevelFor(level));
      if (level == RecorderLogLevel.quiet) {
        // No-op callback for the same reason as MiniAV above: passing null
        // may re-enable FFmpeg's own av_log default handler (stderr).
        shim.setFfmpegLogCallback((_, __) {});
      } else {
        shim.setFfmpegLogCallback((int avLevel, String msg) {
          if (msg.isEmpty) return;
          recorderLog(
            RecorderLogSource.ffmpeg,
            _fromAvLevel(avLevel),
            msg.trimRight(),
          );
        });
      }
    }

    // 2b. miniav_tools_ffmpeg Dart layer (downloader, encoder selection,
    //     vendor probing). Unlike the shim bridge above, this is available
    //     before FFmpeg is loaded — auto-download diagnostics are captured.
    setFfmpegToolsLogLevel(miniavLogLevelFor(level));
    if (level == RecorderLogLevel.quiet) {
      setFfmpegToolsLogCallback(null); // level `none` silences everything
    } else {
      setFfmpegToolsLogCallback(
        (l, msg) =>
            recorderLog(RecorderLogSource.ffmpeg, _fromMiniAVLevel(l), msg),
      );
    }

    // 3. minigpu / Dawn native GPU layer.
    final mgpuLevel = minigpuLevelFor(level);
    if (level == RecorderLogLevel.quiet) {
      Minigpu.setLogCallback(null, level: -1);
    } else {
      Minigpu.setLogCallback((mgpuLvl, msg) {
        if (msg.isEmpty) return;
        recorderLog(
          RecorderLogSource.minigpu,
          _fromMgpuLevel(mgpuLvl),
          msg.trimRight(),
        );
      }, level: mgpuLevel);
    }
  }

  /// Route a recorder-internal log line through the callback installed via
  /// [setLogCallback] (if set) or to the console via `print`. All
  /// `[recorder]` messages in this file go through here.
  static void _log(
    String message, [
    RecorderLogLevel level = RecorderLogLevel.info,
  ]) => recorderLog(RecorderLogSource.recorder, level, message);

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
    // A screen or camera source is a candidate for D3D11 zero-copy: the camera
    // MF backend produces GPU shared NT handles under GPU output preference,
    // exactly as the screen capture path does. Anything else (audio-only) needs
    // no shared GPU device.
    final hasGpuVideoSource = _sourceConfigs.any(
      (s) => s is ScreenRecorderSource || s is CameraRecorderSource,
    );
    if (!hasGpuVideoSource) return;
    await ensureSharedGpu();
    final gpu = _sharedGpu;
    if (gpu == null) {
      _backendContext = null;
      return;
    }

    // Re-acquire the D3D11 device handle from Dawn on every recording session.
    //
    // After system sleep/resume (or a GPU TDR reset), Dawn internally
    // recreates its D3D11 device. The process-global [_sharedD3d11Device]
    // would still hold the OLD (stale) handle. The GpuScreenProcessor uses
    // Dawn's NEW device to produce textures, while the encoder is opened
    // with the OLD device — causing a cross-device error that silently drops
    // every video frame while audio continues normally, manifesting as an
    // apparent A/V sync offset on the 2nd+ recording session after a long gap.
    //
    // Calling createD3D11DeviceOnDawnAdapter() on each session gives us the
    // device currently in use by Dawn.  If the pointer changed (device was
    // recreated), we release the old COM AddRef and adopt the new handle so
    // both the GpuScreenProcessor and the encoder always share the same device.
    final freshDev = gpu.createD3D11DeviceOnDawnAdapter();
    if (freshDev == 0) {
      _backendContext = null;
      return;
    }

    // Synchronise the process-global handle with Dawn's current device.
    // FfmpegShim is guaranteed non-null here: ensureFFmpegLoaded() ran before
    // this method in _prepare().
    final shim = FfmpegShim.tryLoad();
    final prevDev = _sharedD3d11Device;
    if (freshDev != prevDev) {
      // Dawn is now on a different device (e.g. after GPU reset / wake-up).
      // Release our AddRef on the old handle and adopt the new one.
      if (shim != null && prevDev != 0) {
        shim.d3d11Release(Pointer<Void>.fromAddress(prevDev));
      }
      _sharedD3d11Device = freshDev;
      _log(
        'zero-copy GPU device refreshed: 0x${freshDev.toRadixString(16)} '
        '(was 0x${prevDev.toRadixString(16)} — Dawn device was recreated, '
        'likely after sleep/resume or GPU reset)',
      );
    } else {
      // Same device — release the extra AddRef from this call to keep the
      // COM refcount balanced.
      shim?.d3d11Release(Pointer<Void>.fromAddress(freshDev));
    }

    final dev = _sharedD3d11Device;
    if (dev == 0) {
      _backendContext = null;
      return;
    }
    _backendContext = BackendContext(
      sharedGpu: gpu,
      d3d11DeviceHandle: dev,
      preferZeroCopy: true,
    );
    // Fire a background warm-up so the Intel MF/QSV (and any other vendor)
    // SDK finishes its one-time driver-side initialisation before the
    // real compatibility probe runs in _buildScreenTrack.  Without this,
    // both pre-check attempts land within ~10 ms of GPU device ready, which
    // is too fast for the driver to finish MFStartup / DXVA session init —
    // both fail and the recorder falls back to CPU for the entire first
    // session.  The warm-up is unawaited; failures are silently ignored.
    ffmpegD3d11WarmUp(dev);
  }

  /// GPU-input capabilities of the negotiable encoders for [codec], probed once
  /// so the screen and camera track builders decide capture output preference
  /// and the per-frame encode path identically. [encWidth]/[encHeight] are the
  /// ENCODER (post-downscale) dimensions — codec promotion and the D3D11 probe
  /// must use them, not the raw capture size, or a 4K→1080p downscale asks
  /// "does HEVC work?" for an encoder that later opens as h264 at the small size.
  ///
  /// Returns `(effectiveCodec, hasD3d11Encoder, hasMinigpuGpuEncoder,
  /// hasSharedHandleEncoder)`. `useGpuOutput` is the OR of the three flags.
  Future<(VideoCodec, bool, bool, bool)> _detectVideoEncoderGpuCaps(
    VideoCodec codec, {
    required int encWidth,
    required int encHeight,
    required bool wantHw,
    required String label,
  }) async {
    final effectiveCodec = FfmpegBackend.bestCodecForResolution(
      width: encWidth,
      height: encHeight,
      hwAccel: wantHw,
      preferred: codec,
    );
    // (a) FFmpeg D3D11VA encoder that opens with the shared Dawn device (the
    // foreign-texture / shared-handle path). Probed, not just symbol-checked.
    final hasD3d11Encoder =
        _backendContext != null &&
        Platform.isWindows &&
        await ffmpegD3d11EncoderCompatibleWith(
          effectiveCodec,
          _backendContext!.d3d11DeviceHandle,
        );
    if (_backendContext != null &&
        Platform.isWindows &&
        !hasD3d11Encoder &&
        ffmpegD3d11EncoderAvailable(effectiveCodec)) {
      // Symbol check passed but the probe failed — a vendor is registered
      // (e.g. NVENC) but cannot open with the injected Dawn D3D11 device (Dawn
      // on an Intel iGPU while only NVENC/AMF are present). CPU output is used.
      Recorder._log(
        '$label: D3D11 zero-copy pre-check: no vendor opened with '
        'device=0x${_backendContext!.d3d11DeviceHandle.toRadixString(16)} — '
        '${effectiveCodec.name} vendors are registered but incompatible with '
        'this adapter. Falling back to CPU capture. '
        '(Check the log for per-vendor failure details.)',
        RecorderLogLevel.warning,
      );
    }
    // (b) A minigpu-style encoder that takes GPU buffer input (e.g.
    // MinigpuAv1Pipeline). A CAPABILITY question answered before the encoder
    // exists — NOT a prediction of who wins createEncoder (minigpu's priority 30
    // is below FFmpeg's 50). Requires a processor to produce the buffer, so it
    // only justifies GPU output on a track that has one (screen).
    final hasMinigpuGpuEncoder =
        _backendContext != null &&
        Platform.isWindows &&
        MiniAVToolsPlatform.instance.backends.any(
          (b) =>
              b.supportsEncode(effectiveCodec) &&
              b.acceptedFrameSources.contains(FrameSourceKind.gpuTexture),
        );
    // (c) A backend that takes a capture buffer's shared NT handle directly (the
    // MF encoder). This justifies GPU output even when the FFmpeg D3D11 probe
    // above failed — its direct-passthrough path opens the handle on its own
    // device and never touches Dawn, so that adapter mismatch does not apply.
    final hasSharedHandleEncoder =
        _backendContext != null &&
        Platform.isWindows &&
        MiniAVToolsPlatform.instance.backends.any(
          (b) =>
              b.supportsEncode(effectiveCodec) &&
              b.acceptedFrameSources.contains(
                FrameSourceKind.miniavBufferD3D11,
              ),
        );
    return (
      effectiveCodec,
      hasD3d11Encoder,
      hasMinigpuGpuEncoder,
      hasSharedHandleEncoder,
    );
  }

  // -----------------------------------------------------------------------
  // Build helpers
  // -----------------------------------------------------------------------

  /// Video codecs the declared sources are configured with (pre-negotiation).
  Set<VideoCodec> _configuredVideoCodecs() => {
    for (final s in _sourceConfigs)
      if (s is ScreenRecorderSource)
        s.codec
      else if (s is CameraRecorderSource)
        s.codec,
  };

  /// Audio codecs the declared sources are configured with (pre-negotiation).
  Set<AudioCodec> _configuredAudioCodecs() => {
    for (final s in _sourceConfigs)
      if (s is MicRecorderSource)
        s.codec
      else if (s is LoopbackRecorderSource)
        s.codec
      else if (s is MixedAudioRecorderSource)
        s.codec,
  };

  /// How many audio TRACKS the declared sources will produce. Not derivable
  /// from [_configuredAudioCodecs], which is a set — two mics on the same codec
  /// are one element there and two tracks here, and WAV/ADTS hold exactly one.
  int _configuredAudioTrackCount() => _sourceConfigs
      .where(
        (s) =>
            s is MicRecorderSource ||
            s is LoopbackRecorderSource ||
            s is MixedAudioRecorderSource,
      )
      .length;

  /// The preference audio encoders negotiate under.
  ///
  /// Normally [backendPreference] — the first-party OS AAC encoder outranks
  /// FFmpeg and winning is the point. When a file sink forces `FfmpegMuxer`,
  /// audio is PINNED to FFmpeg instead, because that muxer can only describe
  /// audio FFmpeg encoded (see [recordingRequiresFfmpegMuxer]).
  BackendPreference get _audioBackendPreference => _ffmpegMuxerRequired
      ? BackendPreference.pinned(FfmpegBackend.backendName)
      : backendPreference;

  /// Fail loudly when the caller's own backend preference makes the FFmpeg
  /// audio pin impossible — before a device is opened, and with the coupling
  /// spelled out. The alternative is the muxer throwing "Audio tracks must be
  /// bound to a FfmpegAudioEncoder" from inside writeHeader, which says nothing
  /// about the container choice that actually caused it.
  void _checkFfmpegAudioReachable() {
    // Capability before preference. The pin is CONTAINER-shaped — it only says
    // "FfmpegMuxer has to write this file" — so on its own it will happily pin
    // audio to a backend that has no encoder for the configured codec. The
    // negotiation then yields nothing and the caller sees
    // "No registered backend supports AudioCodec.pcmS16le", naming a codec
    // PcmBackend does in fact support. Ask the real question here.
    final ffmpegBackends = MiniAVToolsPlatform.instance.backends.where(
      (b) => b.name == FfmpegBackend.backendName,
    );
    final ffmpeg = ffmpegBackends.isEmpty ? null : ffmpegBackends.first;
    final unencodable = _configuredAudioCodecs()
        .where((c) => ffmpeg == null || !ffmpeg.supportsAudioEncode(c))
        .toList();
    if (unencodable.isNotEmpty) {
      final alternatives = ffmpeg == null
          ? const <String>[]
          : [
              for (final c in AudioCodec.values)
                if (ffmpeg.supportsAudioEncode(c)) c.name,
            ];
      throw CodecInitException(
        'recorder',
        'this recording has audio and at least one file sink whose container '
            'only FFmpeg can write, so FfmpegMuxer must write it — and that '
            'muxer can only describe audio FFmpeg itself encoded. FFmpeg has '
            'no encoder for ${unencodable.map((c) => c.name).join(", ")}'
            '${ffmpeg == null ? ' (the FFmpeg backend is not registered)' : ''}'
            ', so no backend choice satisfies both. Either record '
            '${alternatives.isEmpty ? 'a codec FFmpeg can encode' : alternatives.join('/')} '
            'for this container, or write one the first-party muxer handles — '
            'MP4/M4A for any mix, WAV for a single PCM track, ADTS (.aac) for '
            'a single AAC one — since it takes already-encoded packets from '
            'any backend.',
      );
    }

    final pref = backendPreference;
    final String restriction;
    if (pref is PinnedBackendPreference) {
      if (pref.backendName == FfmpegBackend.backendName) return;
      restriction = 'pinned the "${pref.backendName}" backend';
    } else if (pref is ExcludedBackendPreference &&
        pref.backendNames.contains(FfmpegBackend.backendName)) {
      restriction = 'excluded the "${FfmpegBackend.backendName}" backend';
    } else {
      return;
    }
    throw CodecInitException(
      'recorder',
      'this recording has audio and at least one file sink whose container '
          'only FFmpeg can write, so FfmpegMuxer must write it — and that muxer '
          'needs a live FFmpeg encoder per audio track (AVChannelLayout setup '
          'requires an AVCodecContext), so the audio must be FFmpeg-encoded. '
          'You $restriction. Either write MP4/M4A, WAV (single PCM track) or '
          'ADTS/.aac (single AAC track) — the first-party muxer takes '
          'already-encoded packets from any backend — or drop the restriction.',
    );
  }

  /// Native objects a track build has created but not yet handed to a runtime.
  ///
  /// A build that throws part way through used to orphan them. One-off at
  /// start; a leak PER ATTEMPT in [rebuildVideoStage], which runs every few
  /// seconds for the whole length of an outage — and each orphan is a capture
  /// context holding a graphics device.
  ///
  /// Not re-entrant, and does not need to be: builds are sequential, guarded
  /// by [_rebuilding] mid-session and by [_prepare] running before start.
  final List<Future<void> Function()> buildDebris = [];

  /// [buildGuarded] over this recorder's [buildDebris].
  Future<TrackRuntime> guardedBuild(Future<TrackRuntime> Function() build) =>
      buildGuarded(buildDebris, build);

  Future<TrackRuntime> _buildTrack(int index, RecorderSource cfg) async {
    switch (cfg) {
      case ScreenRecorderSource():
        return _buildScreenTrack(index, cfg);
      case CameraRecorderSource():
        return _buildCameraTrack(index, cfg);
      case MicRecorderSource():
        return _buildAudioTrack(
          index,
          deviceId: cfg.deviceId,
          deviceKind: 'microphone',
          codec: cfg.codec,
          bitrate: cfg.bitrateBps,
          sampleRate: cfg.sampleRate,
          channels: cfg.channels,
          lossPolicy: cfg.lossPolicy,
          reacquireLimit: cfg.reacquireLimit,
          enumerate: MiniAudioInput.enumerateDevices,
          factory: () async => MiniAudioInput.createContext(),
          configure: (ctx, id, fmt) =>
              (ctx as MiniAudioInputContext).configure(id, fmt),
          getDefault: MiniAudioInput.getDefaultFormat,
          lostListener: (ctx) => (ctx as MiniAudioInputContext).addLostListener,
          start: (ctx, cb) => (ctx as MiniAudioInputContext).startCapture(cb),
          stop: (ctx) => (ctx as MiniAudioInputContext).stopCapture(),
          destroy: (ctx) => (ctx as MiniAudioInputContext).destroy(),
          label: 'mic[${cfg.deviceId}]',
        );
      case LoopbackRecorderSource():
        return _buildAudioTrack(
          index,
          deviceId: cfg.deviceId,
          deviceKind: 'audio endpoint',
          codec: cfg.codec,
          bitrate: cfg.bitrateBps,
          sampleRate: cfg.sampleRate,
          channels: cfg.channels,
          lossPolicy: cfg.lossPolicy,
          reacquireLimit: cfg.reacquireLimit,
          enumerate: MiniLoopback.enumerateDevices,
          factory: () async => MiniLoopback.createContext(),
          configure: (ctx, id, fmt) =>
              (ctx as MiniLoopbackContext).configure(id, fmt),
          getDefault: MiniLoopback.getDefaultFormat,
          lostListener: (ctx) => (ctx as MiniLoopbackContext).addLostListener,
          start: (ctx, cb) => (ctx as MiniLoopbackContext).startCapture(cb),
          stop: (ctx) => (ctx as MiniLoopbackContext).stopCapture(),
          destroy: (ctx) => (ctx as MiniLoopbackContext).destroy(),
          label: 'loopback[${cfg.deviceId}]',
        );
      case MixedAudioRecorderSource():
        return _buildMixedAudioTrack(index, cfg);
    }
  }

  /// [lockedSize] pins the ENCODER's output dimensions instead of deriving
  /// them from the display's current format.
  ///
  /// Only used when rebuilding a track whose muxer entry already exists. A
  /// declared track's width and height are written into the file's header and
  /// cannot be revised, so a display that comes back at a different resolution
  /// must be rescaled to what the track already promised — which is work the
  /// GPU processor was already doing for every other reason.
  Future<TrackRuntime> _buildScreenTrack(
    int index,
    ScreenRecorderSource cfg, {
    (int, int)? lockedSize,
  }) async {
    // Resolve the display ID: accept whatever string enumerateDisplays()
    // returns, or null to mean "use the platform default display".
    //
    // Two ids, deliberately. The REQUESTED one is this track's identity and
    // never changes; the RESOLVED one is whatever handle names that display at
    // this instant, and on a rebuild after a topology change it is a different
    // string. Conflating them is what made re-acquire spend its whole life
    // asking for a monitor that no longer existed -- see [resolveDisplayTarget].
    String? requestedDisplayId = _pinnedDisplayIds[index] ?? cfg.displayId;
    if (requestedDisplayId == null && cfg.windowId == null) {
      final displays = await MiniScreen.enumerateDisplays();
      if (displays.isEmpty) {
        throw StateError('addScreen: no displays found on this platform');
      }
      final picked = displays.firstWhere(
        (d) => d.isDefault,
        orElse: () => displays.first,
      );
      requestedDisplayId = picked.deviceId;
      if (picked.name.isNotEmpty) {
        _deviceNames[_nameKey('display', picked.deviceId)] = picked.name;
      }
    }
    String? resolvedDisplayId = requestedDisplayId;
    if (requestedDisplayId != null) {
      _pinnedDisplayIds[index] = requestedDisplayId;
      resolvedDisplayId = await _resolveDisplayId(requestedDisplayId);
      if (resolvedDisplayId == null) {
        throw CaptureTargetUnavailable(
          'display ${describeDevice('display', requestedDisplayId)} '
          'is not attached',
        );
      }
    }
    final defaults = await MiniScreen.getDefaultFormats(
      resolvedDisplayId ?? cfg.windowId!,
    );
    var (videoFormat, _) = defaults;
    if (lockedSize != null &&
        (videoFormat.width <= 0 || videoFormat.height <= 0)) {
      // A rebuild knows this target had a size, so a 0x0 answer means the
      // handle names nothing any more and every dimension derived from it
      // would be a guess. Say that, instead of letting it surface four calls
      // later as MINIAV_ERROR_SYSTEM_CALL_FAILED.
      //
      // Only on a rebuild: 0x0 is a legal REQUEST on first configure, where
      // PipeWire uses it to mean "negotiate the native size".
      throw CaptureTargetUnavailable(
        'capture target ${resolvedDisplayId ?? cfg.windowId} reports a 0x0 '
        'size — its handle no longer names anything',
      );
    }
    // Pick output preference: GPU only when:
    //   (a) a BackendContext with a live D3D11 device is present, AND
    //   (b) a D3D11VA-capable encoder exists for the requested codec.
    // Without (b) the GPU processor produces D3D11TextureFrameSource frames that
    // FfmpegHwEncoder (Stage-A CPU path) cannot consume, crashing every frame.
    // Use the effective codec (after resolution-based promotion) to avoid
    // false-positives when H.264 at 4K+ is promoted to HEVC.
    //
    // IMPORTANT: codec promotion + the probe must use the **post-downscale**
    // (encoder) dimensions, not the raw capture dimensions.  Otherwise the
    // precheck asks "does HEVC work?" while the actual encoder later opens at
    // the smaller scaled size as plain h264 — and the false-fail forces CPU
    // capture into a path the encoder/processor were not configured for.
    final wantHwForGpuCheck =
        cfg.hwAccel == HwAccelPreference.preferred ||
        cfg.hwAccel == HwAccelPreference.required;
    final precheckTarget = cfg.scale.targetSize(
      videoFormat.width,
      videoFormat.height,
    );
    final (precheckW, precheckH) =
        precheckTarget ?? (videoFormat.width, videoFormat.height);
    final (
      effectiveCodecForGpuCheck,
      hasD3d11Encoder,
      hasMinigpuGpuEncoder,
      hasSharedHandleEncoder,
    ) = await _detectVideoEncoderGpuCaps(
      cfg.codec,
      encWidth: precheckW,
      encHeight: precheckH,
      wantHw: wantHwForGpuCheck,
      label: 'screen',
    );
    final useGpuOutput =
        hasD3d11Encoder || hasMinigpuGpuEncoder || hasSharedHandleEncoder;
    // The GPU processor (bilinear scale + effects chain) imports the capture's
    // D3D11 texture handle. So the capture must produce GPU output whenever a
    // processor will run — INCLUDING the CPU-readback path (useGpuOutput=false
    // but a scale policy or effects are configured). This was previously gated
    // on useGpuOutput alone, so on that path the capture was set to CPU output;
    // window (WGC) capture then hands back plain CPU buffers with no D3D11
    // handle, the processor can't import them, and the entire scale/effects
    // chain (e.g. censor boxes + crop) is silently skipped. Display (DXGI)
    // capture happened to still carry a handle, which is why this only bit
    // window capture.
    final hasGpuWork =
        cfg.scale.targetSize(videoFormat.width, videoFormat.height) != null ||
        cfg.effects.isNotEmpty;
    final captureUsesGpu =
        _backendContext != null && (useGpuOutput || hasGpuWork);
    // For the log label: minigpu GPU buffer path takes precedence over D3D11
    // when both are available (encoder priority already ensures minigpu wins).
    final captureLabel = !captureUsesGpu
        ? 'CPU'
        : useGpuOutput
        ? (hasMinigpuGpuEncoder ? 'GPU (minigpu buffer)' : 'GPU (D3D11 zero-copy)')
        : 'GPU (processor → CPU readback)';
    Recorder._log(
      'screen capture output: $captureLabel '
      '— backendContext=${_backendContext != null}, '
      'd3d11Encoder=$hasD3d11Encoder, '
      'sharedHandleEncoder=$hasSharedHandleEncoder, '
      'minigpuEncoder=$hasMinigpuGpuEncoder, '
      'gpuWork=$hasGpuWork, '
      'd3d11Device=0x${(_backendContext?.d3d11DeviceHandle ?? 0).toRadixString(16)}',
    );
    final outputPref = captureUsesGpu
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
    buildDebris.add(ctx.destroy);
    if (resolvedDisplayId != null) {
      await ctx.configureDisplay(resolvedDisplayId, videoFormat);
    } else {
      await ctx.configureWindow(cfg.windowId!, videoFormat);
    }

    // Resolve target (encoder) dimensions and GPU processor mode.
    //
    // There are three cases:
    //
    // (A) GPU zero-copy encode: _backendContext != null && useGpuOutput.
    //     GpuScreenProcessor handles scale + effects entirely on-GPU and
    //     returns a SharedOutputTexture for D3D11 hardware encoding.
    //     processorCpuReadback = false.
    //
    // (B) GPU downscale + CPU encode: _backendContext != null && !useGpuOutput
    //     but a scale policy or effects are active.  We still create a
    //     GpuScreenProcessor to run the expensive bilinear resize on the Intel
    //     iGPU (e.g. 4K→1080p), then read the smaller result back to CPU for
    //     NVENC or software encoding.  This avoids saturating the isolate with
    //     a 3840×2160 Dart bilinear rescale on every frame.
    //     processorCpuReadback = true.
    //
    // (C) No GPU context, or GPU context present but no scale/effects work to
    //     do: processor = null.  The encoder receives full-resolution CPU
    //     frames and uses its own internal rescale if dimensions mismatch.
    //     Warn at 4K without a scale policy so the user can set one.
    final (
      int encW,
      int encH,
      GpuScreenProcessor? processor,
      bool processorCpuReadback,
    ) = () {
      final target = cfg.scale.targetSize(
        videoFormat.width,
        videoFormat.height,
      );
      final (dstW, dstH) =
          lockedSize ?? target ?? (videoFormat.width, videoFormat.height);
      // Whether the GPU processor has anything to do. Asked as "does the size
      // actually change", not "is a scale policy set", so a locked size that
      // differs from a re-acquired display's new resolution engages the
      // rescale even with no scale policy configured — and a scale policy that
      // happens to return the source size correctly engages nothing.
      final needResize =
          dstW != videoFormat.width || dstH != videoFormat.height;
      final bc = _backendContext;

      if (bc == null) {
        // Case C – no GPU context at all.
        if (cfg.effects.isNotEmpty) {
          Recorder._log(
            'WARNING: ${cfg.effects.length} effect(s) configured but no GPU '
            'context is available — effects will be skipped.',
            RecorderLogLevel.warning,
          );
        }
        final megaPixels = (videoFormat.width * videoFormat.height) / 1e6;
        if (megaPixels >= 4.0 && !needResize) {
          Recorder._log(
            'WARNING: capturing ${videoFormat.width}x${videoFormat.height} '
            '(${megaPixels.toStringAsFixed(1)} MP) without GPU context and '
            'without a scale policy. CPU NV12 conversion at this size may '
            'stall the encode loop. Consider setting cfg.scale to e.g. 0.5×.',
            RecorderLogLevel.warning,
          );
        }
        return (dstW, dstH, null, false);
      }

      if (!useGpuOutput) {
        // Case B or C depending on whether there is GPU work to do.
        final hasWork = needResize || cfg.effects.isNotEmpty;
        if (hasWork) {
          // Case B: GPU downscale + CPU readback.
          Recorder._log(
            'screen downscale (GPU→CPU readback): '
            '${videoFormat.width}x${videoFormat.height} → ${dstW}x$dstH '
            '(${cfg.scale}) — GPU bilinear downscale, CPU encode',
          );
          if (cfg.effects.isNotEmpty) {
            Recorder._log(
              'screen effects: ${cfg.effects.length} effect(s) active '
              '(GPU→CPU readback path)',
            );
          }
          final p = GpuScreenProcessor(
            gpu: bc.sharedGpu! as Minigpu,
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
          return (p.outputWidth, p.outputHeight, p, true);
        }
        // Case C: GPU context present but no scale/effects work.
        final megaPixels = (videoFormat.width * videoFormat.height) / 1e6;
        if (megaPixels >= 4.0) {
          Recorder._log(
            'WARNING: capturing ${videoFormat.width}x${videoFormat.height} '
            '(${megaPixels.toStringAsFixed(1)} MP) without GPU output and '
            'without a scale policy. CPU NV12 conversion at this size may '
            'stall the encode loop and produce very large files with '
            'erratic frame timing. Consider setting cfg.scale to e.g. 0.5×.',
            RecorderLogLevel.warning,
          );
        }
        return (dstW, dstH, null, false);
      }

      // Case A: full GPU zero-copy path.
      if (needResize) {
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
        gpu: bc.sharedGpu! as Minigpu,
        srcWidth: videoFormat.width,
        srcHeight: videoFormat.height,
        dstWidth: dstW,
        dstHeight: dstH,
        effects: cfg.effects,
        // Depth-2 output ring so the pipelined runtime can run the GPU stage
        // of frame N+1 while the encoder still reads frame N's texture.
        sharedRingDepth: 2,
      );
      if (p.outputWidth != dstW || p.outputHeight != dstH) {
        Recorder._log(
          'effects resize: ${dstW}x$dstH → '
          '${p.outputWidth}x${p.outputHeight}',
        );
      }
      return (p.outputWidth, p.outputHeight, p, false);
    }();

    var encResult = await _openVideoEncoder(
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
      // Don't pass the D3D11 BackendContext when the pre-check determined that
      // zero-copy is not available (useGpuOutput=false).  Without this,
      // FfmpegBackend.createEncoder sees context.preferZeroCopy=true and tries
      // FfmpegD3d11HwEncoder.open again — which succeeds on session 2+ (warm
      // HW context from session 1), returns a D3D11 encoder, and the safety
      // net below (processor != null && no GPU-input capability) does NOT
      // fire because the encoder IS D3D11.  CPU-only frames then hit the
      // encoder and every frame fails with CodecRuntimeException[ffmpeg-d3d11].
      noContext: !useGpuOutput,
      // When GPU output is on AND there is scale/effects work, the processor
      // will hand the encoder a D3D11 texture. Only negotiate among backends
      // that take one — otherwise a higher-priority handle-only encoder wins
      // and immediately falls back to CPU readback, which is worse than the
      // backend it displaced.
      requiredFrameSource: (useGpuOutput && hasGpuWork)
          ? FrameSourceKind.d3d11Texture
          : null,
    );

    // Safety net: if a GPU zero-copy processor was created (GPU output configured)
    // but the encoder that was actually selected is NOT a D3D11-capable encoder,
    // the SharedOutputTexture frames it produces will crash the CPU-only encoder.
    // Reconfigure capture for CPU output and discard the processor.
    // NOTE: this does NOT apply to the CPU-readback path (processorCpuReadback=true)
    // because in that case the processor only produces CPU bytes, never D3D11 frames.
    // NOTE: the pre-check now uses ffmpegD3d11EncoderCompatibleWith (a real
    // device probe) so this branch should no longer fire in normal operation.
    var effectiveProcessor = processor;
    var effectiveCpuReadback = processorCpuReadback;
    // Detect which GPU mode the selected encoder supports. These are asked as
    // CAPABILITIES, not as `platform is FfmpegD3d11HwEncoder` — that concrete
    // type check silently forced every other GPU-capable encoder (e.g. the
    // first-party MF one) onto the CPU-readback path, adding a full frame
    // readback per frame even though the encoder could take the handle.
    //  - supportsD3d11TextureInput      → processor texture (Case A)
    //  - supportsD3d11SharedHandleInput → capture NT handle (Case A0)
    //  - supportsGpuBufferInput         → packed RGBA8 GPU buffer (Case C)
    //  - none → safety net fires, fall back to CPU readback
    final platform = encResult.encoder.platform;
    final isD3d11TextureEncoder = platform.supportsD3d11TextureInput;
    final isD3d11HandleEncoder = platform.supportsD3d11SharedHandleInput;
    final isGpuBufferEncoder = platform.supportsGpuBufferInput;
    final effectiveGpuBuffer =
        processor != null && !processorCpuReadback && isGpuBufferEncoder;
    // Zero-copy D3D11 sub-modes (see VideoTrackRuntime):
    //  - no GPU work (no scale/effects)  → direct BGRA passthrough: the capture
    //    NT handle goes straight to the encoder; zero shader-core work/frame.
    //  - GPU work present                → pipelined two-stage encode: GPU
    //    stage of frame N+1 overlaps the encode of frame N (ring depth 2).
    // (`hasGpuWork` computed above with the capture-output decision.)
    //
    // The two sub-modes need DIFFERENT encoder capabilities, so they are gated
    // separately: passthrough hands over a shared NT handle, the pipelined mode
    // a foreign-device texture pointer. An encoder that does the first but not
    // the second (the MF one) gets passthrough and falls back to CPU readback
    // only when there is actual GPU work to do.
    final gpuZeroCopyEligible =
        effectiveProcessor != null &&
        !effectiveCpuReadback &&
        !effectiveGpuBuffer;
    final canDirectPassthrough =
        gpuZeroCopyEligible && !hasGpuWork && isD3d11HandleEncoder;
    final canPipelinedZeroCopy =
        gpuZeroCopyEligible && hasGpuWork && isD3d11TextureEncoder;
    // Log the actual per-frame encode path now that the encoder is known.
    if (processor != null && !processorCpuReadback) {
      final backend = encResult.encoder.backendName;
      final pathLabel = effectiveGpuBuffer
          ? 'GPU buffer → $backend encodeFromGpuBuffer (zero CPU round-trip)'
          : canPipelinedZeroCopy
          ? 'D3D11 shared texture → $backend '
                '(zero-copy, pipelined GPU/encode stages)'
          : canDirectPassthrough
          ? 'capture NT handle → $backend '
                '(direct BGRA passthrough, no GPU processing)'
          : 'GPU processor → CPU → encoder (unexpected; safety net may fire)';
      Recorder._log('screen encode path: $pathLabel');
    }
    if (processor != null &&
        !processorCpuReadback &&
        !canDirectPassthrough &&
        !canPipelinedZeroCopy &&
        !isGpuBufferEncoder) {
      // The pre-check expected a GPU-capable encoder (D3D11 zero-copy or a
      // minigpu GPU-buffer encoder), so capture was configured for GPU output
      // and the processor for the zero-copy path. The encoder that actually
      // opened is a CPU-input encoder — e.g. the isolate-hosted software /
      // CPU-fed HW encoder, because zero-copy and the minigpu GPU encoder were
      // both unavailable on this adapter.
      //
      // Keep the GPU processor and switch it to the CPU-readback path — do NOT
      // drop it. The processor still imports the capture's D3D11 handle, runs
      // the bilinear downscale + the effects chain on the GPU, and reads the
      // result back to feed the CPU encoder. Nulling `effectiveProcessor` here
      // (the old behaviour) silently dropped the entire scale/effects pipeline.
      // Capture stays on GPU output (the processor needs the D3D11 handle), and
      // the already-selected encoder accepts CPU frames as-is, so there is no
      // need to reconfigure capture or reopen the encoder.
      Recorder._log(
        'screen: selected encoder is CPU-input (no D3D11 shared-texture / '
        'GPU-buffer support); keeping the GPU processor on the CPU-readback '
        'path so downscale + effects still apply.',
        RecorderLogLevel.warning,
      );
      effectiveCpuReadback = true;
    }

    // Captured by value for the re-acquire closure: `videoFormat` is a `var`
    // that the format-negotiation above reassigns, and a closure over it would
    // see later writes rather than the shape this track was built for.
    final reacquireDisplayId = requestedDisplayId;
    final reacquireFormat = videoFormat;
    final notAttached = _Counter();

    return VideoTrackRuntime(
      index: index,
      label: 'screen[${resolvedDisplayId ?? cfg.windowId}]',
      encoder: encResult.encoder,
      videoCodec: encResult.codec,
      width: encW,
      height: encH,
      frameRateNum: videoFormat.frameRateNumerator,
      frameRateDen: videoFormat.frameRateDenominator,
      captureCtx: ctx,
      processor: effectiveProcessor,
      processorCpuReadback: effectiveCpuReadback,
      processorGpuBuffer: effectiveGpuBuffer,
      idleFramePolicy: cfg.idleFramePolicy,
      adaptiveGpuThrottle: cfg.adaptiveGpuThrottle,
      cfrOutput: cfg.cfrOutput,
      directD3d11Passthrough: canDirectPassthrough,
      pipelinedZeroCopy: canPipelinedZeroCopy,
      startFn: (cb) => ctx.startCapture(cb),
      stopFn: () => ctx.stopCapture(),
      destroyFn: () => ctx.destroy(),
      addLostListenerFn: ctx.addLostListener,
      lossPolicy: cfg.lossPolicy,
      reacquireLimit: cfg.reacquireLimit,
      canRebuildStage: true,
      // Re-acquire is offered for a DISPLAY and not for a window, because the
      // platform means different things by the two losses.
      //
      // A display's capture item closes for reasons that undo themselves —
      // Win+P, dock/undock, lock, an RDP transition, a mode change. The
      // monitor is still a monitor. It does NOT still answer to the same
      // handle, though, which is why each attempt re-resolves the target
      // rather than reusing the id this track was built with; see
      // [resolveDisplayTarget].
      //
      // A window's item closes when the window is DESTROYED. The HWND is dead
      // and will not be reissued, so retrying is asking a question that can
      // only ever be answered no. Ending the track and saying so is the
      // honest response; picking a different window is the application's
      // decision to make with its user, not one to infer here.
      reacquireFn: reacquireDisplayId == null
          ? null
          // Which handle names this display NOW. The losses recovered here
          // are exactly the ones that invalidate the old one.
          : () => _reacquireDevice(
                label: 'screen[$reacquireDisplayId]',
                kind: 'display',
                requestedId: reacquireDisplayId,
                enumerate: MiniScreen.enumerateDisplays,
                configure: (id) =>
                    ctx.configureDisplay(id, reacquireFormat),
                notAttached: notAttached,
              ),
    );
  }

  Future<TrackRuntime> _buildCameraTrack(
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

    // Decide capture output preference the same way the screen builder does.
    // The camera has no scale/effects processor, so the only zero-copy shape
    // that applies is the DIRECT PASSTHROUGH — the capture's shared NT handle
    // straight to the encoder. A minigpu GPU-buffer encoder needs a processor
    // to produce the buffer and the FFmpeg foreign-texture path needs one to
    // rescale, so neither is a candidate here; only a shared-handle encoder
    // (the MF one) is. The passthrough itself is source-agnostic and lives in
    // _encodeOne above the processor gate, so the camera needs no processor.
    final wantHw =
        cfg.hwAccel == HwAccelPreference.preferred ||
        cfg.hwAccel == HwAccelPreference.required;
    final (_, _, _, hasSharedHandleEncoder) = await _detectVideoEncoderGpuCaps(
      cfg.codec,
      encWidth: format.width,
      encHeight: format.height,
      wantHw: wantHw,
      label: 'camera[${cfg.deviceId}]',
    );
    var useGpuOutput = hasSharedHandleEncoder;
    format = MiniAVVideoInfo(
      width: format.width,
      height: format.height,
      pixelFormat: format.pixelFormat,
      frameRateNumerator: format.frameRateNumerator,
      frameRateDenominator: format.frameRateDenominator,
      outputPreference: useGpuOutput
          ? MiniAVOutputPreference.gpu
          : MiniAVOutputPreference.cpu,
    );

    final cameraId = await _resolveDeviceId(
      'camera',
      cfg.deviceId,
      MiniCamera.enumerateDevices,
    );
    if (cameraId == null) {
      throw CaptureTargetUnavailable(
        'camera ${describeDevice('camera', cfg.deviceId)} is not attached',
      );
    }
    final ctx = await MiniCamera.createContext();
    buildDebris.add(ctx.destroy);
    await ctx.configure(cameraId, format);

    // Pass the BackendContext (D3D11 zero-copy device) only on the GPU path —
    // the camera MF backend delivers gpuD3D11Handle buffers only under GPU
    // output preference; for CPU output the context must be suppressed or a
    // D3D11 encoder opens and then throws on the CPU frames it receives.
    // requiredFrameSource biases negotiation toward a backend that takes the
    // shared handle, so we don't configure GPU capture and then discover the
    // winner only accepts CPU frames.
    var encResult = await _openVideoEncoder(
      format,
      cfg.codec,
      cfg.bitrateBps,
      cfg.hwAccel,
      quality: cfg.quality,
      encoderOptions: cfg.encoderOptions,
      noContext: !useGpuOutput,
      requiredFrameSource: useGpuOutput
          ? FrameSourceKind.miniavBufferD3D11
          : null,
    );

    // Confirm the negotiated encoder actually accepts the capture's shared NT
    // handle. If not, the camera has no processor to fall back on — a GPU buffer
    // has empty planes, so there is no CPU fallback and every frame would fail.
    // Reconfigure for CPU output and reopen without the D3D11 context.
    final directD3d11Passthrough = useGpuOutput &&
        encResult.encoder.platform.supportsD3d11SharedHandleInput;
    if (useGpuOutput && !directD3d11Passthrough) {
      Recorder._log(
        'camera[${cfg.deviceId}]: selected encoder does not accept the capture '
        'shared handle — reconfiguring for CPU output.',
        RecorderLogLevel.warning,
      );
      useGpuOutput = false;
      format = MiniAVVideoInfo(
        width: format.width,
        height: format.height,
        pixelFormat: format.pixelFormat,
        frameRateNumerator: format.frameRateNumerator,
        frameRateDenominator: format.frameRateDenominator,
        outputPreference: MiniAVOutputPreference.cpu,
      );
      await ctx.configure(cameraId, format);
      encResult = await _openVideoEncoder(
        format,
        cfg.codec,
        cfg.bitrateBps,
        cfg.hwAccel,
        quality: cfg.quality,
        encoderOptions: cfg.encoderOptions,
        noContext: true,
      );
    }

    Recorder._log(
      directD3d11Passthrough
          ? 'camera[${cfg.deviceId}] encode path: capture NT handle → '
                '${encResult.encoder.backendName} '
                '(direct passthrough, no GPU processing)'
          : 'camera[${cfg.deviceId}] encode path: CPU frames → '
                '${encResult.encoder.backendName}',
    );

    // Captured by value for the re-acquire closure: `format` is a var the
    // GPU/CPU negotiation above reassigns, and a closure over it would
    // re-configure into a shape this track was not built for.
    final reacquireFormat = format;
    final cameraNotAttached = _Counter();

    return VideoTrackRuntime(
      index: index,
      label: 'camera[${cfg.deviceId}]',
      encoder: encResult.encoder,
      videoCodec: encResult.codec,
      width: format.width,
      height: format.height,
      frameRateNum: format.frameRateNumerator,
      frameRateDen: format.frameRateDenominator,
      captureCtx: ctx,
      idleFramePolicy: cfg.idleFramePolicy,
      directD3d11Passthrough: directD3d11Passthrough,
      startFn: (cb) => ctx.startCapture(cb),
      stopFn: () => ctx.stopCapture(),
      destroyFn: () => ctx.destroy(),
      addLostListenerFn: ctx.addLostListener,
      lossPolicy: cfg.lossPolicy,
      reacquireLimit: cfg.reacquireLimit,
      // A camera IS re-acquirable, and until now nothing here said so: with
      // no re-acquire path a loss went straight to ending the track. A USB
      // device that is unplugged and pushed back in, or whose driver resets,
      // comes back under the same id — Media Foundation ends the sample
      // stream and the device is simply configured again.
      reacquireFn: () => _reacquireDevice(
        label: 'camera[${cfg.deviceId}]',
        kind: 'camera',
        requestedId: cfg.deviceId,
        enumerate: MiniCamera.enumerateDevices,
        configure: (id) => ctx.configure(id, reacquireFormat),
        notAttached: cameraNotAttached,
      ),
    );
  }

  /// [backendPreference], narrowed to backends that can actually consume
  /// [kind]. Returns the preference unchanged when [kind] is null, when the
  /// caller already pinned a backend, or when no backend would be left — a
  /// filter that excluded everything would turn a working (if slower) encode
  /// into no encode at all.
  BackendPreference _preferenceFor(FrameSourceKind? kind) {
    if (kind == null) return backendPreference;
    if (backendPreference is PinnedBackendPreference) return backendPreference;
    final all = MiniAVToolsPlatform.instance.backends;
    final unable = <String>{
      for (final b in all)
        if (!b.acceptedFrameSources.contains(kind)) b.name,
    };
    if (unable.isEmpty || unable.length == all.length) return backendPreference;
    if (backendPreference is ExcludedBackendPreference) {
      unable.addAll(
        (backendPreference as ExcludedBackendPreference).backendNames,
      );
    }
    Recorder._log(
      'encoder negotiation restricted to backends accepting ${kind.name} '
      '(excluding: ${unable.join(", ")})',
    );
    return BackendPreference.excluded(unable);
  }

  Future<({Encoder encoder, VideoCodec codec})> _openVideoEncoder(
    MiniAVVideoInfo format,
    VideoCodec codec,
    int? bitrate,
    HwAccelPreference hwAccel, {
    double? quality,
    Map<String, String> encoderOptions = const {},
    // When true the BackendContext (D3D11 zero-copy device) is NOT passed to
    // the encoder.  Used when retrying with CPU frames after a D3D11 fallback.
    bool noContext = false,
    // Frame-source kind the caller has already committed to producing. Backends
    // that cannot consume it are excluded from negotiation.
    //
    // Without this, a higher-priority encoder that accepts only *some* GPU
    // shapes wins the negotiation and then trips the safety net, silently
    // adding back the CPU readback the GPU path existed to avoid — a straight
    // downgrade from a lower-priority backend that could have taken the frame.
    // Ranking cannot see this: it compares hardware/zero-copy/priority, not
    // what the caller is actually about to hand over.
    FrameSourceKind? requiredFrameSource,
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
      preference: _preferenceFor(requiredFrameSource),
      context: noContext ? null : _backendContext,
    );
    final platform = enc.platform;
    String? vendorTag;
    try {
      // FfmpegD3d11HwEncoder exposes vendor + encoderName; surface them in
      // logs so users can tell which underlying vendor (nvenc / amf / qsv /
      // h264_mf) was actually selected. Done via dynamic to avoid a hard
      // dependency on the ffmpeg package from the recorder.
      final dyn = platform as dynamic;
      final vendor = dyn.vendor?.toString();
      final encoderName = dyn.encoderName?.toString();
      if (vendor != null && encoderName != null) {
        vendorTag = ' vendor=$encoderName';
      }
    } catch (_) {
      /* not a ffmpeg-d3d11 encoder */
    }
    // Whether the encoder ended up on the SAME device as the frame producer
    // decides whether GPU frames need importing at all. Reported here because
    // it is otherwise invisible, and a mismatch presents as every frame being
    // refused with no clue as to why.
    String deviceTag = '';
    if (platform is MfVideoEncoder) {
      final encDev = platform.boundD3d11Device;
      final ctxDev = _backendContext?.d3d11DeviceHandle ?? 0;
      deviceTag =
          ' device=0x${encDev.toRadixString(16)}'
          '${encDev == ctxDev && encDev != 0 ? " (shared with capture — no import needed)" : " MISMATCH vs capture 0x${ctxDev.toRadixString(16)} — GPU frames must be imported"}';
    }
    Recorder._log(
      'video encoder = ${enc.backendName} '
      '(${platform.runtimeType})${vendorTag ?? ''} for ${effectiveCodec.name} '
      '${format.width}x${format.height}'
      '${quality != null ? ' quality=$quality (${effectiveRc.name} $effectiveCrf)' : ''}'
      '$deviceTag',
    );
    return (encoder: enc, codec: effectiveCodec);
  }

  Future<AudioTrackRuntime> _buildAudioTrack(
    int index, {
    required String deviceId,
    // Which enumeration answers for [deviceId]. Also the word used when
    // telling someone their device is not there.
    required String deviceKind,
    required AudioCodec codec,
    required int? bitrate,
    required int? sampleRate,
    required int? channels,
    required CaptureLossPolicy lossPolicy,
    required Duration? reacquireLimit,
    required Future<List<MiniAVDeviceInfo>> Function() enumerate,
    required Future<Object> Function() factory,
    // Takes the id EXPLICITLY rather than closing over one: a re-acquire has
    // to configure onto whatever id names the device now, which is not
    // necessarily the id the caller asked for. See [resolveDeviceTarget].
    required Future<void> Function(Object ctx, String id, MiniAVAudioInfo fmt)
        configure,
    required Future<MiniAVAudioInfo> Function(String id) getDefault,
    required void Function() Function(MiniAVContextLostListener) Function(
      Object ctx,
    )
    lostListener,
    required Future<void> Function(
      Object ctx,
      void Function(MiniAVBuffer, Object?) cb,
    )
    start,
    required Future<void> Function(Object ctx) stop,
    required Future<void> Function(Object ctx) destroy,
    required String label,
  }) async {
    final startId = await _resolveDeviceId(deviceKind, deviceId, enumerate);
    if (startId == null) {
      throw CaptureTargetUnavailable(
        '$deviceKind ${describeDevice(deviceKind, deviceId)} is not attached',
      );
    }
    var format = await getDefault(startId);
    if (sampleRate != null || channels != null) {
      format = MiniAVAudioInfo(
        format: format.format,
        sampleRate: sampleRate ?? format.sampleRate,
        channels: channels ?? format.channels,
        numFrames: format.numFrames,
      );
    }

    final ctx = await factory();
    buildDebris.add(() => destroy(ctx));
    await configure(ctx, startId, format);

    final encoderConfig = AudioEncoderConfig(
      codec: codec,
      sampleRate: format.sampleRate,
      channels: format.channels,
      bitrateBps: bitrate ?? defaultAudioBitrate,
      backendOptions: const {'global_header': '1'},
    );
    final encoder = await MiniAVTools.createAudioEncoder(
      encoderConfig,
      preference: _audioBackendPreference,
      context: _backendContext,
    );
    Recorder._log(
      'audio encoder = ${encoder.backendName} '
      '(${encoder.platform.runtimeType}) for ${codec.name} '
      '${format.sampleRate}Hz/${format.channels}ch ($label)',
    );

    // Captured by value: `format` is a var the negotiation above reassigns,
    // and a closure over it would re-acquire into a shape this track was not
    // built for.
    final reacquireFormat = format;
    final notAttached = _Counter();

    return AudioTrackRuntime(
      index: index,
      label: label,
      encoder: encoder,
      encoderConfig: encoderConfig,
      audioCodec: codec,
      sampleRate: format.sampleRate,
      channels: format.channels,
      audioFormat: format.format,
      captureCtx: ctx,
      startFn: (cb) => start(ctx, cb),
      stopFn: () => stop(ctx),
      destroyFn: () => destroy(ctx),
      lossPolicy: lossPolicy,
      reacquireLimit: reacquireLimit,
      addLostListenerFn: lostListener(ctx),
      reacquireFn: () => _reacquireDevice(
        label: label,
        kind: deviceKind,
        requestedId: deviceId,
        enumerate: enumerate,
        configure: (id) => configure(ctx, id, reacquireFormat),
        notAttached: notAttached,
      ),
    );
  }

  Future<TrackRuntime> _buildMixedAudioTrack(
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
    final micId = await _resolveDeviceId(
      'microphone',
      cfg.micDeviceId,
      MiniAudioInput.enumerateDevices,
    );
    if (micId == null) {
      throw CaptureTargetUnavailable(
        'microphone ${describeDevice('microphone', cfg.micDeviceId)} '
        'is not attached',
      );
    }
    final micFmt = await MiniAudioInput.getDefaultFormat(micId);
    final micCtx = await MiniAudioInput.createContext();
    await micCtx.configure(micId, targetFormat);

    // 2. Loopback context.
    final loopId = await _resolveDeviceId(
      'audio endpoint',
      cfg.loopbackDeviceId,
      MiniLoopback.enumerateDevices,
    );
    if (loopId == null) {
      throw CaptureTargetUnavailable(
        'audio endpoint '
        '${describeDevice('audio endpoint', cfg.loopbackDeviceId)} '
        'is not attached',
      );
    }
    final loopFmt = await MiniLoopback.getDefaultFormat(loopId);
    final loopCtx = await MiniLoopback.createContext();
    await loopCtx.configure(loopId, targetFormat);

    final micNotAttached = _Counter();
    final loopNotAttached = _Counter();

    // 3. Single audio encoder.
    final encoderConfig = AudioEncoderConfig(
      codec: cfg.codec,
      sampleRate: targetSampleRate,
      channels: targetChannels,
      bitrateBps: cfg.bitrateBps ?? defaultAudioBitrate,
      backendOptions: const {'global_header': '1'},
    );
    final encoder = await MiniAVTools.createAudioEncoder(
      encoderConfig,
      preference: _audioBackendPreference,
      context: _backendContext,
    );

    Recorder._log(
      'mixed audio: mic[${cfg.micDeviceId}] '
      '(native ${micFmt.sampleRate}Hz/${micFmt.channels}ch/${micFmt.format.name}) '
      '+ loopback[${cfg.loopbackDeviceId}] '
      '(native ${loopFmt.sampleRate}Hz/${loopFmt.channels}ch/${loopFmt.format.name}) '
      '→ ${targetSampleRate}Hz/${targetChannels}ch f32 → ${cfg.codec.name}',
    );

    AudioEffectChain? chain(List<AudioEffect> fx) => fx.isEmpty
        ? null
        : AudioEffectChain(
            fx,
            sampleRate: targetSampleRate,
            channels: targetChannels,
          );

    return MixedAudioTrackRuntime(
      index: index,
      label: 'mixed[mic=${cfg.micDeviceId},loop=${cfg.loopbackDeviceId}]',
      encoder: encoder,
      encoderConfig: encoderConfig,
      audioCodec: cfg.codec,
      micCtx: micCtx,
      loopCtx: loopCtx,
      micGain: _dbToLinear(cfg.micGainDb),
      loopGain: _dbToLinear(cfg.loopbackGainDb),
      micChain: chain(cfg.micEffects),
      loopChain: chain(cfg.loopbackEffects),
      masterChain: chain(cfg.masterEffects),
      lossPolicy: cfg.lossPolicy,
      reacquireLimit: cfg.reacquireLimit,
      reacquireMicFn: () => _reacquireDevice(
        label: 'mixed mic',
        kind: 'microphone',
        requestedId: cfg.micDeviceId,
        enumerate: MiniAudioInput.enumerateDevices,
        configure: (id) => micCtx.configure(id, targetFormat),
        notAttached: micNotAttached,
      ),
      reacquireLoopFn: () => _reacquireDevice(
        label: 'mixed loopback',
        kind: 'audio endpoint',
        requestedId: cfg.loopbackDeviceId,
        enumerate: MiniLoopback.enumerateDevices,
        configure: (id) => loopCtx.configure(id, targetFormat),
        notAttached: loopNotAttached,
      ),
    );
  }

  /// Re-configure one capture context onto whatever id names its device now,
  /// or report that the device is not there.
  ///
  /// A RE-CONFIGURE, not a restart, for every device class. After a loss the
  /// platform's stop is a no-op — WASAPI cleared is_running when its capture
  /// thread exited, WGC's session is already gone — so a bare restart would
  /// re-arm handlers on something that no longer exists. Configure is the call
  /// that releases the dead objects and acquires them again.
  Future<bool> _reacquireDevice({
    required String label,
    required String kind,
    required String requestedId,
    required Future<List<MiniAVDeviceInfo>> Function() enumerate,
    required Future<void> Function(String id) configure,
    required _Counter notAttached,
  }) async {
    final live = await _resolveDeviceId(kind, requestedId, enumerate);
    if (live == null) {
      notAttached.value++;
      // Say so, and keep saying so. A recovery that is quietly waiting looks
      // exactly like one that is quietly broken.
      if (notAttached.value == 1 || notAttached.value % 12 == 0) {
        _log(
          '$label: $kind ${describeDevice(kind, requestedId)} is not '
          'attached — waiting for it to come back. Nothing is being recorded '
          'for this source meanwhile.',
          RecorderLogLevel.warning,
        );
      }
      return false;
    }
    notAttached.value = 0;
    await configure(live);
    return true;
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
  /// - video + audio → MP4 when the first-party writer takes the codec mix,
  ///   else MKV (handles any codec mix)
  /// - video only    → MP4
  /// - audio only    → M4A for AAC, MP3 for MP3, OGG for Opus, else MKV
  static Container _autoContainer(List<TrackInfo> tracks) {
    final videoCodecs = tracks.whereType<VideoTrackInfo>().map((t) => t.codec);
    final audioCodecs = tracks.whereType<AudioTrackInfo>().map((t) => t.codec);
    return containerForTrackMix(
      hasVideo: videoCodecs.isNotEmpty,
      hasAudio: audioCodecs.isNotEmpty,
      videoCodecs: videoCodecs.toSet(),
      audioCodecs: audioCodecs.toSet(),
    );
  }

  /// Re-open every audio track that has no FFmpeg bridge on the FFmpeg
  /// backend, so `FfmpegMuxer` can read codecpar out of a live AVCodecContext.
  ///
  /// The routing in [_prepare] answers this from the CONFIGS and gets it right
  /// whenever the first-party writer accepts the sink; this is the other case —
  /// it accepted the config but refused at open (e.g. an MF encoder that has no
  /// parameter sets until its first keyframe), which no config can predict.
  ///
  /// Failures are logged, not thrown: the caller re-derives the bridge map and
  /// reports the coupling with the sink and container in hand.
  Future<void> _repinAudioTracksToFfmpeg(
    String path,
    Container container,
  ) async {
    _ffmpegMuxerRequired = true;
    for (final t in _tracks) {
      try {
        if (!await t.repinAudioEncoderToFfmpeg(_backendContext)) continue;
        Recorder._log(
          'audio encoder for ${t.label} re-opened on '
          '${FfmpegBackend.backendName} so FfmpegMuxer can write $path as '
          '${container.name}',
        );
      } catch (e) {
        Recorder._log(
          're-opening ${t.label} on ${FfmpegBackend.backendName} failed: $e',
          RecorderLogLevel.error,
        );
      }
    }
  }

  Future<_SinkRuntime> _buildSink(RecorderSink sink) async {
    switch (sink) {
      case FileRecorderSink():
        // Build TrackInfo list + encoder bridge map. Track infos carry the
        // negotiated codecs, so the container heuristic and the first-party
        // capability check below both see what will actually be written.
        var tracks = <TrackInfo>[];
        var encoderForTrack = <int, FfmpegEncoderBridge>{};
        var audioWithoutBridge = <String>[];
        // Re-derivable: the FFmpeg fallback below may re-open audio encoders,
        // which changes every one of these three.
        void collectTracks() {
          tracks = <TrackInfo>[];
          encoderForTrack = <int, FfmpegEncoderBridge>{};
          audioWithoutBridge = <String>[];
          for (final t in _tracks) {
            final info = t.toTrackInfo();
            tracks.add(info);
            final bridge = t.encoderBridge;
            if (bridge != null) {
              encoderForTrack[t.index] = bridge;
            } else if (info is AudioTrackInfo) {
              audioWithoutBridge.add(t.label);
            }
          }
        }

        collectTracks();

        // Pick container: explicit override → extension sniff → track-mix heuristic.
        final container =
            sink.container ??
            _sniffContainer(sink.path) ??
            _autoContainer(tracks);

        MuxerConfig muxerConfig() => MuxerConfig(
          container: container,
          output: FileMuxerOutput(sink.path),
          tracks: tracks,
        );

        // First-party writers: ISO-BMFF for MP4/M4A, RIFF for WAV, raw framing
        // for ADTS. All three stream to the path as packets arrive (MP4 puts
        // ftyp + mdat up front, appends samples, and patches moov and the mdat
        // size at finish; WAV patches its two RIFF lengths; ADTS has nothing to
        // patch), so an open-ended recording costs sample-table memory rather
        // than the media — the whole-file-in-RAM behaviour that used to make
        // FFmpeg the only option here is gone. They also take already-encoded
        // packets from any backend, which is what frees audio to negotiate away
        // from FFmpeg at all — and for a PCM `.wav` it is the ONLY route, since
        // FFmpeg has no PCM encoder to bind a codecpar to.
        if (firstPartyMuxerCanWrite(
          container: container,
          videoCodecs: tracks.whereType<VideoTrackInfo>().map((t) => t.codec),
          audioCodecs: tracks.whereType<AudioTrackInfo>().map((t) => t.codec),
        )) {
          Muxer? opened;
          try {
            // On a worker where one can be had. Building the index is one
            // synchronous pass over every sample in the recording, and the
            // isolate calling stop() is the one drawing the UI.
            final hosted = await WorkerMuxSink.tryOpen(
              container: container,
              path: sink.path,
              tracks: tracks,
              onPhase: (phase) => _notePhase(phase, sink.path),
              onFatal: (error) => Recorder._log(
                'the worker writing ${sink.path} ended before the recording '
                'did${error == null ? '' : ': $error'}. Everything captured '
                'from here on is lost and the file will have no index — its '
                'media is still on disk and recoverable. Stop the recording.',
                RecorderLogLevel.error,
              ),
            );
            if (hosted != null) {
              Recorder._log(
                'muxer = ${hosted.backendName} for ${container.name} → '
                '${sink.path} (on a worker; finish will not block the caller)',
              );
              return _FileSinkRuntime(muxer: hosted, path: sink.path);
            }
            // PIN rather than negotiate: FFmpeg also muxes MP4, and this is a
            // routing decision, not a capability contest.
            opened = await MiniAVTools.createMuxer(
              muxerConfig(),
              preference: BackendPreference.pinned(
                ContainerFramingBackend.backendName,
              ),
            );
            await opened.writeHeader();
            Recorder._log(
              'muxer = ${opened.backendName} for ${container.name} → '
              '${sink.path} (in process — no worker was available, so stop() '
              'will block while the index is written)',
              RecorderLogLevel.warning,
            );
            return _FileSinkRuntime(
              muxer: InProcessMuxSink(opened),
              path: sink.path,
            );
          } catch (e) {
            // writeHeader() may have already opened the file. Release the
            // handle before FFmpeg tries to write the same path — on Windows a
            // live handle makes the fallback fail too.
            try {
              await opened?.close();
            } catch (_) {}
            // The negotiator reports "no backend" when the muxer declines; the
            // reason it declined (e.g. an H.264 track whose extraData carries
            // no usable SPS) is recorded by the backend itself. Log the real
            // cause — falling back silently is how a first-party path stays
            // broken.
            final cause = ContainerFramingBackend.lastMuxerInitFailure ?? e;
            Recorder._log(
              'first-party ${container.name} muxer unavailable for '
              '${sink.path}: $cause — falling back to FFmpeg',
              RecorderLogLevel.warning,
            );
          }
        }

        // FFmpeg for everything else (MKV/WebM/TS/…), and as the fallback
        // above. FfmpegMuxer needs a live AVCodecContext per audio track to
        // fill codecpar — ch_layout is not reachable through the Dart-side
        // AVCodecParameters prefix — so it can only mux audio FFmpeg encoded.
        // _prepare pins audio to FFmpeg when a sink is known up front to need
        // this muxer; reaching here with an unbound audio track means we got
        // here by fallback instead.
        //
        // Recover rather than fail. In the configuration the first-party route
        // is the DEFAULT for — Windows, MF H.264 + MF AAC → rec.mp4 — no track
        // has an FFmpeg bridge, so a refusal above would otherwise turn this
        // "fallback" into a hard start() failure and no recording at all. The
        // capture contexts are already open and nothing has been captured yet,
        // so re-opening the audio encoders on FFmpeg costs only the open.
        if (audioWithoutBridge.isNotEmpty) {
          await _repinAudioTracksToFfmpeg(sink.path, container);
          collectTracks();
        }
        if (audioWithoutBridge.isNotEmpty) {
          throw CodecInitException(
            'recorder',
            'cannot write ${sink.path} as ${container.name}: it needs '
                'FfmpegMuxer, which cannot mux audio it did not encode, '
                'track(s) ${audioWithoutBridge.join(", ")} are on a non-FFmpeg '
                'encoder, and re-opening them on FFmpeg did not succeed (the '
                'log above says why). If a first-party MP4/M4A/WAV/ADTS route '
                'was attempted for this sink, the warning above says why it '
                'was refused.',
          );
        }
        final muxer = Muxer(
          FfmpegMuxer.open(muxerConfig(), encoderForTrack: encoderForTrack),
          FfmpegBackend.backendName,
        );
        await muxer.writeHeader();
        return _FileSinkRuntime(
          muxer: InProcessMuxSink(muxer),
          path: sink.path,
        );

      case StreamRecorderSink():
        return _StreamSinkRuntime(onChunk: sink.onChunk);
    }
  }

  // -----------------------------------------------------------------------
  // Packet dispatch (called from track runtimes)
  // -----------------------------------------------------------------------

  Future<void> dispatchPacket(TrackRuntime track, EncodedPacket packet) async {
    // Liveness, recorded in the one place every track's output passes through
    // rather than at each of the ten sites that build a packet. See
    // [CaptureWatchdog]: a produced packet is the only proof a capture is
    // still alive that survives a static screen.
    track.notePacket(now());
    // The container may still be waiting for this track's configuration
    // record. A hardware H.264 MFT is allowed to withhold its sequence header
    // until it has produced output, and the muxer was built before any frame
    // was encoded — so for those encoders the record only exists now. It has
    // to land BEFORE the sample it describes.
    if (!track.configDelivered) {
      final cfg = track.currentConfigRecord;
      if (cfg != null && cfg.isNotEmpty) {
        track.configDelivered = true;
        await updateTrackConfig(track, cfg, firstRecord: true);
      }
    }
    final routed = packet.copyWith(trackIndex: track.index);
    for (final s in _sinks) {
      switch (s) {
        case _FileSinkRuntime():
          // Enqueue for asynchronous muxing; this returns immediately unless
          // the queue is full (back-pressure), so the libav write no longer
          // runs inline on the encode path.
          await s.enqueuePacket(routed);
        case _StreamSinkRuntime():
          try {
            s.onChunk(track.toChunk(routed));
          } catch (e) {
            Recorder._log('stream callback: $e', RecorderLogLevel.error);
          }
      }
    }
  }


  /// Rebuild a video track's whole GPU stage in place: Dawn's device, the
  /// screen processor, the encoder and the capture context.
  ///
  /// This is the recovery a GPU device reset needs and a lost capture item
  /// does not. A reset removes every D3D11 device on the adapter at once, so
  /// re-configuring the capture is not enough — the capture would come back on
  /// a device that no longer exists. Everything has to be replaced together,
  /// against the device Dawn recreated for itself.
  ///
  /// The container is what constrains this. A declared track's dimensions,
  /// codec and frame rate are already written; only the codec CONFIGURATION
  /// record may still change (see [updateTrackConfig]). So a rebuild that
  /// comes out a different shape is refused rather than spliced — a file whose
  /// header describes the first half is worse than a file that stops.
  ///
  /// Returns true when the track is running again on new hardware objects.
  Future<bool> rebuildVideoStage(VideoTrackRuntime track) async {
    if (_state != RecorderState.running) return false;
    if (track.index < 0 || track.index >= _sourceConfigs.length) return false;
    final cfg = _sourceConfigs[track.index];
    if (cfg is! ScreenRecorderSource) {
      // Only the screen path can rebuild today. A camera's context is built
      // the same way and could follow; nothing here assumes it cannot.
      return false;
    }
    // Single-flight across tracks: the device re-acquire below mutates
    // process-global state that every track's encoder is opened against, and
    // two tracks discovering the same reset at the same moment is the normal
    // case, not the exotic one.
    if (_rebuilding) return false;
    _rebuilding = true;
    try {
      // Is the target even there? Ask first, because during an outage this
      // runs every few seconds, and re-acquiring Dawn's device and warming
      // the encoder SDK for a display that is unplugged is expensive work
      // with nothing at the end of it.
      final pinned = _pinnedDisplayIds[track.index];
      if (pinned != null && await _resolveDisplayId(pinned) == null) {
        throw CaptureTargetUnavailable(
          'display ${describeDevice('display', pinned)} is not attached',
        );
      }

      // Re-read the D3D11 device Dawn is on NOW. Dawn recreates its own device
      // after a reset; the process-global handle still points at the removed
      // one, and an encoder opened against that would fail every frame while
      // reporting success at open. This is the same re-acquire every recording
      // session already does at prepare — it has simply never run mid-session.
      await _maybeInitSharedGpu();

      final fresh = await guardedBuild(
        () => _buildScreenTrack(
          track.index,
          cfg,
          lockedSize: (track.width, track.height),
        ),
      );
      if (fresh is! VideoTrackRuntime) return false;

      if (!track.canAdopt(fresh)) {
        _log(
          '${track.label} rebuild came out ${fresh.width}x${fresh.height} '
          '${fresh.videoCodec} where the container already declares '
          '${track.width}x${track.height} ${track.videoCodec} — refusing to '
          'splice it. The video track ends here rather than continuing under a '
          'header that describes something else.',
          RecorderLogLevel.error,
        );
        await VideoTrackRuntime.discardStage(fresh);
        return false;
      }

      await track.adoptStage(fresh);
      _log(
        '${track.label} GPU stage rebuilt (device, processor, encoder and '
        'capture all replaced) — recording continues in the same file.',
        RecorderLogLevel.warning,
      );
      _rebuildsWaiting = 0;
      return true;
    } on CaptureTargetUnavailable catch (e) {
      // Not a failure — the target is away, which is the whole reason this is
      // running. Say it on the first attempt and then rarely, because an
      // outage lasts minutes and an identical line every few seconds is how a
      // log stops being read.
      _rebuildsWaiting++;
      if (_rebuildsWaiting == 1 || _rebuildsWaiting % 12 == 0) {
        _log('${track.label} $e — still waiting for it to come back.',
            RecorderLogLevel.warning);
      }
      return false;
    } catch (e, st) {
      _log('${track.label} stage rebuild failed: $e\n$st',
          RecorderLogLevel.error);
      return false;
    } finally {
      _rebuilding = false;
    }
  }

  bool _rebuilding = false;
  int _rebuildsWaiting = 0;

  /// Platform device names, keyed by device class and the id the caller first
  /// asked for.
  ///
  /// Learned while the id is alive, because that is the only moment it can be
  /// learned: once the id goes stale there is nothing left to ask. Keyed by
  /// class as well as id so two classes cannot answer for each other.
  final Map<String, String> _deviceNames = {};

  String _nameKey(String kind, String id) => '$kind\u0000$id';

  /// The name last seen for [id], for a message a person has to read.
  String describeDevice(String kind, String id) =>
      _deviceNames[_nameKey(kind, id)] ?? id;

  /// The display each screen track is pinned to, by track index.
  ///
  /// A track built with no explicit display id picks the platform default
  /// ONCE. "The default display" is a question with a different answer after
  /// the topology changes, and re-asking it on a rebuild would let a recording
  /// quietly continue on a different monitor -- the one thing
  /// [CaptureLossPolicy] promises does not happen.
  final Map<int, String> _pinnedDisplayIds = {};

  /// [resolveDeviceTarget] against a fresh enumeration of [kind], remembering
  /// the device's name while it is still there to be read.
  Future<String?> _resolveDeviceId(
    String kind,
    String requestedId,
    Future<List<MiniAVDeviceInfo>> Function() enumerate,
  ) async {
    final key = _nameKey(kind, requestedId);
    final List<MiniAVDeviceInfo> devices;
    try {
      devices = await enumerate();
    } catch (_) {
      // Enumeration is a diagnostic here, not the operation. If it fails, hand
      // back what was asked for: the configure attempt reports the real error.
      return requestedId;
    }
    for (final d in devices) {
      if (d.deviceId == requestedId && d.name.isNotEmpty) {
        _deviceNames[key] = d.name;
        break;
      }
    }
    return resolveDeviceTarget(
      requestedId: requestedId,
      knownName: _deviceNames[key],
      devices: devices,
    );
  }

  /// The display equivalent, which is where this started and still the only
  /// class whose ids are known to go stale on ordinary use.
  Future<String?> _resolveDisplayId(String requestedId) =>
      _resolveDeviceId('display', requestedId, MiniScreen.enumerateDisplays);

  /// Why [track]'s display no longer looks like the one it is capturing, or
  /// null when it still does.
  ///
  /// The one question that separates a still desktop from a dead capture. Both
  /// deliver nothing; only one of them is attached to a display that has since
  /// changed shape or gone away. Asked only when the capture is already
  /// suspiciously quiet — see [CaptureWatchdog.probeSilenceUs] — so a healthy
  /// recording never pays for it.
  ///
  /// Deliberately conservative: anything it cannot establish returns null and
  /// leaves the decision to the silence window. A wrong "yes" here re-acquires
  /// a perfectly good capture.
  Future<String?> displayTargetDrifted(VideoTrackRuntime track) async {
    final requested = _pinnedDisplayIds[track.index];
    if (requested == null) return null; // a window or a camera; not this test
    final name = describeDevice('display', requested);
    final live = await _resolveDisplayId(requested);
    if (live == null) {
      return displayDriftReason(
        display: name,
        attached: false,
        deliveredW: track.sourceWidth,
        deliveredH: track.sourceHeight,
        currentW: 0,
        currentH: 0,
      );
    }
    if (track.sourceWidth <= 0 || track.sourceHeight <= 0) return null;
    final MiniAVVideoInfo now;
    try {
      final (video, _) = await MiniScreen.getDefaultFormats(live);
      now = video;
    } catch (_) {
      // The platform declined to answer; that is not evidence of anything.
      return null;
    }
    return displayDriftReason(
      display: name,
      attached: true,
      deliveredW: track.sourceWidth,
      deliveredH: track.sourceHeight,
      currentW: now.width,
      currentH: now.height,
    );
  }

  /// A track's encoder now emits [config] — its codec configuration record.
  ///
  /// Called after anything that could have reopened an encoder. Almost always
  /// a no-op: a reopened encoder with the same settings issues byte-identical
  /// parameter sets. When it does not, the container needs to know, because
  /// the record already committed to the file would otherwise be a claim
  /// about samples that were not encoded under it.
  /// [firstRecord] marks the record a track was opened WITHOUT — the deferred
  /// case, which is ordinary rather than a warning. A later `added` really is
  /// the encoder changing its mind mid-recording.
  Future<void> updateTrackConfig(
    TrackRuntime track,
    Uint8List config, {
    bool firstRecord = false,
  }) async {
    if (config.isEmpty) return;
    for (final s in _sinks) {
      if (s is! _FileSinkRuntime) continue;
      try {
        final change = await s.muxer.setTrackConfig(track.index, config);
        if (change == null) continue;
        if (change == Mp4ConfigChange.added && firstRecord) {
          _log(
            '${track.label} published its codec configuration record with the '
            'first frame — the container was opened without one and has it '
            'now. Normal for a hardware encoder that only fills its sequence '
            'header after the first output.',
            RecorderLogLevel.info,
          );
        } else if (change == Mp4ConfigChange.added) {
          _log(
            '${track.label} encoder came back with DIFFERENT parameter sets — '
            'a second sample entry was written and later frames point at it. '
            'Players that honour sample_description_index handle this; ones '
            'that read only the first entry will render the tail wrong.',
            RecorderLogLevel.warning,
          );
        }
      } catch (e) {
        _log('updateTrackConfig(${track.label}): $e', RecorderLogLevel.error);
      }
    }
  }

  /// Master-clock pts, in microseconds, at the moment this is called.
  int now() => _masterClock.elapsedMicroseconds;

  final StreamController<RecorderFinalizeProgress> _finalize =
      StreamController<RecorderFinalizeProgress>.broadcast();
  Stopwatch? _finalizeClock;

  /// What [stop] is doing, while it does it.
  ///
  /// Broadcast, and it only carries events during a stop — subscribe once at
  /// build time and leave it. Phases rather than a fraction: the expensive
  /// step is one call into a container writer that reports nothing while it
  /// runs, and a percentage over that would be a progress bar that lies.
  ///
  /// The writer runs on a worker where one could be started, so the isolate
  /// reading this stream stays responsive while [RecorderFinalizePhase
  /// .writingIndex] is in progress. Where no worker could be had it falls back
  /// to writing in process, says so in the log, and this stream still reports
  /// the phase — from an isolate that is blocked, so the event arrives before
  /// the freeze rather than during it.
  Stream<RecorderFinalizeProgress> get finalizeProgress => _finalize.stream;

  void _emitPhase(RecorderFinalizePhase phase, {String? path}) {
    if (_finalize.isClosed) return;
    _finalize.add(RecorderFinalizeProgress(
      phase: phase,
      elapsed: _finalizeClock?.elapsed ?? Duration.zero,
      path: path,
    ));
  }

  /// A phase reported by a worker-hosted writer, named in its own vocabulary.
  void _notePhase(String phase, String path) {
    switch (phase) {
      case muxPhaseWritingIndex:
        _emitPhase(RecorderFinalizePhase.writingIndex, path: path);
      case muxPhaseClosing:
        _emitPhase(RecorderFinalizePhase.closing, path: path);
    }
  }

  final List<String> _captureIssues = [];

  /// Live capture health, one entry per source that can report it.
  ///
  /// Safe to poll at any cadence — it reads counters, touches no hardware and
  /// allocates a handful of small objects. A UI that shows "recording" for
  /// ninety-five minutes when the screen stopped at minute fifty-four is the
  /// problem this exists to make impossible; polling this once a second is
  /// enough to catch it while someone can still act.
  ///
  /// Empty before [start].
  List<RecorderCaptureStatus> get captureStatus => [
        for (final t in _tracks) ...t.captureStatuses,
      ];

  /// True when every source that can report is capturing normally. Shorthand
  /// for the common check.
  bool get captureHealthy => captureStatus.every((s) => s.healthy);

  /// Capture problems this recording survived or ended on, populated at
  /// [stop]. Empty means every track captured start to finish.
  ///
  /// [stop] deliberately still returns normally when this is non-empty: the
  /// file is valid and everything that was captured is in it, so throwing
  /// would be a lie about the data. Read this to find out whether the
  /// recording covers the whole session.
  List<String> get captureIssues => List.unmodifiable(_captureIssues);
}

// =========================================================================
// Track runtime (one per source).
// =========================================================================

/// How a capture buffer is handed back to the platform.
///
/// A seam, not an abstraction: releasing the same buffer twice is a crash in
/// native code and releasing it never is a leak that only shows up under an
/// hour of recording. Both are worth being able to assert on, and neither is
/// observable through a real release.
///
/// Test-only override point; production never assigns it.
void Function(MiniAVBuffer buffer) releaseCaptureBuffer =
    MiniAV.releaseBufferSync;

abstract class TrackRuntime {
  TrackRuntime({required this.index, required this.label});
  final int index;
  final String label;

  /// Outstanding encode futures so [Recorder.stop] can wait before flush.
  final List<Future<void>> _inFlight = [];

  /// Master-clock µs at which this track last produced an encoded packet, or
  /// -1 before the first one.
  int lastPacketUs = -1;

  /// Encode or GPU-stage failures since that packet. Zeroed by every packet,
  /// so this is "has work been attempted and failed with nothing to show".
  int encodeErrorsSincePacket = 0;

  void notePacket(int nowUs) {
    lastPacketUs = nowUs;
    encodeErrorsSincePacket = 0;
  }

  /// Whether this track's codec configuration record has reached the
  /// container. False until the first packet for an encoder that publishes it
  /// late; already true at open for one that does not.
  bool configDelivered = false;

  /// The encoder's configuration record right now, or null if it has none yet.
  Uint8List? get currentConfigRecord {
    final bytes = encoderConfigRecord;
    return bytes == null || bytes.isEmpty ? null : bytes;
  }

  /// Per-runtime access to whatever holds the encoder. Null where the track
  /// has no codec-private data to publish.
  Uint8List? get encoderConfigRecord => null;

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

  // ---- Capture-target loss, for every kind of track ------------------------
  //
  // This machinery lived on the video runtime while video was the only path
  // with a loss signal wired to it. None of it is about pictures: a
  // subscription, a state machine, two counters. Mic, loopback and camera all
  // report device loss through the same platform callback, and a recorder that
  // hears it for one source and not the others is exactly as silent about the
  // session as one that hears nothing.

  /// Loss/re-acquire state, one per capture source this track owns.
  ///
  /// A list rather than a field because a mixed-audio track owns two devices
  /// that fail independently — an HDMI render endpoint dies with the monitor
  /// while the USB microphone beside it keeps working — and each has to come
  /// back on its own.
  final List<CaptureRecovery> recoveries = [];

  /// Platform unsubscribes, keyed by the recovery they feed.
  final Map<CaptureRecovery, void Function()> _lostUnsubs = {};

  /// The one recovery of a track that has exactly one capture source. Null for
  /// a track with none, and for one with several, where "the" recovery is not
  /// a question with an answer.
  CaptureRecovery? get soleRecovery =>
      recoveries.length == 1 ? recoveries.first : null;

  /// True while any of this track's targets is gone and has not given up.
  bool get captureLost => recoveries.any((r) => r.lost);

  /// True once this track is shutting down, so a loss reported during teardown
  /// does not start a re-acquire nothing will ever cancel.
  bool get captureStopping => false;

  /// Live capture health, one entry per source that can lose a target.
  List<RecorderCaptureStatus> get captureStatuses => [
        for (final r in recoveries)
          RecorderCaptureStatus(
            label: r.label,
            lost: r.lost,
            ended: r.ended,
            lossCount: r.lossCount,
            recoveryCount: r.recoveryCount,
            rebuildCount: r.hardRecoveryCount,
            secondsMissing: r.totalLostUs / 1000000,
          ),
      ];

  /// One line per source describing anything that happened to this track's
  /// CAPTURE that the output cannot show — a target that disappeared, an
  /// outage that was re-acquired. Empty when every capture ran start to
  /// finish.
  ///
  /// [Recorder.captureIssues] collects these at stop, so a session that lost
  /// its display for forty minutes says so instead of reporting success and
  /// leaving a short file to be discovered later.
  Iterable<String> get captureLossSummaries =>
      recoveries.map((r) => r.summary).whereType<String>();

  /// Point a platform capture-lost callback at [recovery], and register it as
  /// one of this track's recoveries.
  ///
  /// Called again after any rebuild that replaces the capture context, and
  /// that is not optional: the subscription belongs to the context, and a
  /// rebuild destroys the one it was made against. Leaving it would make a
  /// SECOND loss invisible — the recorder would recover once and then go quiet
  /// for the rest of the session, which is the exact failure this whole path
  /// exists to prevent.
  ///
  /// [subscribe] is null for a source whose platform cannot report its own
  /// death; the recovery is still registered, because a watchdog or an
  /// explicit call may declare the loss instead.
  void bindLostSubscription(
    CaptureRecovery recovery,
    void Function() Function(MiniAVContextLostListener)? subscribe, {
    void Function()? onLost,
  }) {
    if (!recoveries.contains(recovery)) recoveries.add(recovery);
    final previous = _lostUnsubs.remove(recovery);
    if (previous != null) {
      // The context this disposer belongs to may already be destroyed.
      try {
        previous();
      } catch (_) {}
    }
    if (subscribe == null) return;
    // The platform fires this from a capture thread and forbids synchronous
    // teardown from inside it, so the listener does nothing but hand the work
    // to the event loop.
    _lostUnsubs[recovery] = subscribe((int reason) {
      scheduleMicrotask(() {
        if (captureStopping) return;
        onLost?.call();
        recovery.noteLost(reason);
      });
    });
  }

  /// Stop every re-acquire and drop every platform subscription. Idempotent,
  /// because stop and dispose both reach it.
  void cancelRecoveries() {
    for (final r in recoveries) {
      r.cancel();
    }
    for (final unsub in _lostUnsubs.values) {
      try {
        unsub();
      } catch (_) {}
    }
    _lostUnsubs.clear();
  }

  /// Re-open this track's AUDIO encoder pinned to the FFmpeg backend, keeping
  /// the capture context, and return `true` when one was swapped.
  ///
  /// `false` for video tracks (FfmpegMuxer synthesises video codecpar from
  /// [VideoTrackInfo]) and for audio already on FFmpeg. Only safe before
  /// capture starts — the replaced encoder is closed without a flush — which is
  /// the only place [Recorder._buildSink] calls it from.
  Future<bool> repinAudioEncoderToFfmpeg(BackendContext? context) async =>
      false;
}

/// Keeps a video encoder's cache of IMPORTED PRODUCER TEXTURES in step with
/// the producer that owns them.
///
/// A D3D11 encoder that imports the producer's textures (the Media Foundation
/// one) caches them keyed on the texture POINTER and pins each one with a
/// reference. The pin is what makes a pointer a safe key: free a texture and
/// the next allocation may land on the same address, and a pointer-keyed hit
/// would then encode a stale picture forever with success reported at every
/// step. The price is that up to a handful of the producer's surfaces stay
/// resident in VRAM after the producer has finished with them — ~135 MB at 4K —
/// until something says they are dead. This is that something.
///
/// The capability is resolved as a method TEAR-OFF rather than as
/// `encoder is MfVideoEncoder` deliberately: the native invalidation was
/// already correct and covered by its own tests — what was missing was any
/// caller at all — and a concrete-type gate is exactly the shape that no test
/// double can satisfy, so the wiring would stay unprovable.
class EncoderImportCache {
  EncoderImportCache(this.encoder, {this.importsProducerTextures = true});

  /// The encoder whose imports this drops.
  final PlatformEncoder encoder;

  /// Whether the track that owns this cache ever hands the PRODUCER's own
  /// texture to [encoder].
  ///
  /// False for a video track that always goes through the GPU processor: what
  /// the encoder imports there is the processor's shared-OUTPUT ring, which is
  /// encoder-sized and untouched by a producer resize. Reporting a resize on
  /// such a track would drop a cache whose contents the geometry does not
  /// describe — and take the encoder's retained repeat source down with it —
  /// for nothing. True for direct passthrough (which feeds the capture's own
  /// texture whenever it is already encoder-sized) and for a track with no
  /// processor at all (a GPU-output camera), which is the case that actually
  /// pins producer surfaces frame after frame.
  final bool importsProducerTextures;

  /// The encoder's invalidation entry point, or `null` when it keeps no import
  /// cache (every encoder but the Media Foundation one). Resolved once —
  /// [noteProducerSize] is on the video hot path.
  late final int Function()? _invalidate = _probe();

  int Function()? _probe() {
    final Object? member;
    try {
      member = (encoder as dynamic).invalidateImports;
    } on NoSuchMethodError {
      return null; // no import cache — nothing to keep in step
    }
    return member is int Function() ? member : null;
  }

  /// Whether [encoder] keeps an import cache at all.
  bool get supported => _invalidate != null;

  /// Producer geometry the cached imports were taken from. Zero until the first
  /// frame: a first size is not a change.
  int _srcWidth = 0;
  int _srcHeight = 0;

  /// How many times the cache has actually been dropped. The call is otherwise
  /// invisible from outside the encoder.
  int get invalidations => _invalidations;
  int _invalidations = 0;

  /// Note a captured frame about to be encoded.
  ///
  /// Filters out everything that cannot have populated the cache — CPU frames,
  /// and tracks that never feed the encoder the producer's own texture (see
  /// [importsProducerTextures]) — then defers to [noteProducerSize]. Returns
  /// entries released, or -1 when nothing was done.
  ///
  /// A non-negative return is ALSO the caller's signal that the encoder's
  /// retained repeat source is gone: invalidation releases it (a duplicate of
  /// a pre-change picture would be stale), and nothing outside the encoder can
  /// observe that. Any recorder-side record of "a duplicate can still be
  /// emitted" has to be dropped with it, or a CFR idle filler claims a grid
  /// slot the encoder can no longer fill and leaves a permanent hole.
  int noteFrame(MiniAVBuffer buffer) {
    if (!importsProducerTextures) return -1;
    if (buffer.contentType != MiniAVBufferContentType.gpuD3D11Handle) return -1;
    final producer = buffer.data;
    if (producer is! MiniAVVideoBuffer) return -1;
    return noteProducerSize(producer.width, producer.height);
  }

  /// Note the geometry of a producer frame about to be encoded.
  ///
  /// A different size means the producer rebuilt its textures — a display mode
  /// change, a re-created capture pool — so everything imported from the old
  /// ones is dead weight. Returns the number of cache entries released, or -1
  /// when nothing was done (unchanged geometry, first frame, or no cache).
  int noteProducerSize(int width, int height) {
    if (width == _srcWidth && height == _srcHeight) return -1;
    final first = _srcWidth == 0 && _srcHeight == 0;
    _srcWidth = width;
    _srcHeight = height;
    return first ? -1 : invalidate();
  }

  /// Drop every imported producer texture unconditionally — for when the
  /// producer tore its textures down wholesale (ring rebuilt, source swapped)
  /// rather than merely resized. Returns entries released, or -1 for no cache.
  int invalidate() {
    final fn = _invalidate;
    if (fn == null) return -1;
    _invalidations++;
    return fn();
  }
}

/// A captured video frame waiting in [VideoTrackRuntime]'s bounded encode
/// queue. [captureUs] is the wall-clock acceptance time, captured at enqueue so
/// the emitted PTS reflects when the frame was *captured* (evenly spaced by the
/// throttle) rather than when the serialized encoder happened to reach it —
/// otherwise a brief encode stall would bunch several frames at near-identical
/// timestamps.
/// A mutable int, so a re-acquire closure and [Recorder._reacquireDevice] can
/// agree on how many times in a row the device has been missing — which is
/// what decides whether this attempt says anything.
class _Counter {
  int value = 0;
}

class _PendingVideoFrame {
  _PendingVideoFrame(this.buffer, this.captureUs);
  final MiniAVBuffer buffer;
  final int captureUs;
}

class VideoTrackRuntime extends TrackRuntime {
  VideoTrackRuntime({
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
    this.processorCpuReadback = false,
    this.processorGpuBuffer = false,
    this.idleFramePolicy = VideoIdleFramePolicy.duplicate,
    this.adaptiveGpuThrottle = true,
    this.directD3d11Passthrough = false,
    this.pipelinedZeroCopy = false,
    this.cfrOutput = false,
    this.reacquireFn,
    this.addLostListenerFn,
    this.lossPolicy = CaptureLossPolicy.reacquire,
    this.reacquireLimit,
    this.canRebuildStage = false,
  });

  // ---- The STAGE: everything a GPU device reset destroys -----------------
  //
  // A capture-item loss leaves all of this alone and only the capture target
  // is rebuilt. A device reset does not: it removes every D3D11 device on the
  // adapter, so Dawn's device, the GPU processor's resources, the encoder's
  // device and the capture context all die together and every one of them has
  // to be replaced in place. See [adoptStage].
  //
  // What is NOT here is deliberate. [index], [width], [height], [videoCodec]
  // and the frame rate are written into the container's track header before
  // the first frame and cannot be revised, so a rebuild must reproduce them
  // exactly or be refused. [_pacer] stays too, which is what keeps a CFR grid
  // continuous across the outage rather than restarting it.
  Encoder encoder;
  final VideoCodec videoCodec;
  final int width;
  final int height;
  final int frameRateNum;
  final int frameRateDen;
  Object captureCtx;
  Future<void> Function(void Function(MiniAVBuffer, Object?)) startFn;
  Future<void> Function() stopFn;
  Future<void> Function() destroyFn;

  /// Rebuild the capture target after it was lost, WITHOUT touching the
  /// encoder. On Windows Graphics Capture this is a re-configure: it drops
  /// the dead capture item, session and frame pool and builds a fresh item
  /// from the same display or window. A bare re-start would not do — after a
  /// loss the platform's stop is a no-op, so re-starting re-arms handlers on
  /// the item that already died.
  ///
  /// Returns false when the target is not there to be re-acquired (a display
  /// still absent, a window that is gone for good), which is a retry, not a
  /// fault. Throws for anything else.
  ///
  /// Null for sources with no re-acquire path; those end the track on loss.
  Future<bool> Function()? reacquireFn;

  /// Subscribe to the platform's capture-lost notification. A method tear-off
  /// rather than a type test on [captureCtx], for the reason spelled out on
  /// [EncoderImportCache]: a concrete-type gate is the one shape no test
  /// double can satisfy, so the wiring would be unprovable.
  void Function() Function(MiniAVContextLostListener)? addLostListenerFn;

  /// What to do when the capture target disappears. See
  /// [CaptureLossPolicy] — including why nothing here ever substitutes a
  /// different display for the one that went away.
  final CaptureLossPolicy lossPolicy;

  /// How long to keep re-acquiring before ending the track; null = for as
  /// long as the recording runs.
  final Duration? reacquireLimit;

  /// Whether [Recorder.rebuildVideoStage] will rebuild this track's whole GPU
  /// stage — the graphics device, the processor, the encoder and the capture
  /// context — rather than refuse it.
  ///
  /// True for the screen path only. A camera's stage is built the same way and
  /// could follow; until it does, this says so out loud instead of being
  /// inferred from something that merely correlated with it.
  final bool canRebuildStage;

  /// Optional GPU screen processor (downscale + effects chain). Non-null when:
  /// (a) the zero-copy GPU path is live — [processorCpuReadback] is false, and
  ///     [process] returns a [SharedOutputTexture] for D3D11 hardware encoding;
  /// (b) GPU context is available but hardware encoding is not —
  ///     [processorCpuReadback] is true, and [processToBytes] is used to run
  ///     GPU downscale and read the result back to CPU for software/CPU-HW encode.
  GpuScreenProcessor? processor;

  /// When true, [processor] runs GPU downscale + effects and returns CPU bytes
  /// via [processToBytes] rather than a D3D11 shared texture. This lets the GPU
  /// handle the expensive bilinear resize (e.g. 4K→1080p) even when the
  /// hardware D3D11 encoder is unavailable.
  bool processorCpuReadback;

  /// When true, [processor] stays on-GPU and the result is passed directly to
  /// the encoder as a GPU [Buffer] via [encodeFromGpuBuffer] (zero CPU
  /// round-trip).  Takes priority over [processorCpuReadback].
  bool processorGpuBuffer;

  /// Controls how the encoder fills gaps when the capture source delivers
  /// fewer frames than the configured fps. See [VideoIdleFramePolicy].
  final VideoIdleFramePolicy idleFramePolicy;

  /// When true (default), sustained GPU-stage overrun (the GPU is saturated by
  /// another workload and our downscale/effects/copy passes queue behind it)
  /// steps the LIVE capture rate down by a power-of-two divisor instead of
  /// letting frames pile into the encode queue and drop unevenly (`busy_drop`
  /// stutter). Throttle drops are evenly spaced and the frame duplicator keeps
  /// the encoded output at the target fps, so playback degrades smoothly.
  /// Restores automatically when GPU pressure clears. See [AdaptiveGpuThrottle].
  final bool adaptiveGpuThrottle;

  /// Pressure detector fed by [_gpuStage]; drives the live-rate divisor.
  final AdaptiveGpuThrottle _gpuAdapt = AdaptiveGpuThrottle();

  /// When true, the zero-copy D3D11 path has NO GPU work to do (no scale, no
  /// effects) and encoder-sized frames are fed to the D3D11 encoder as their
  /// capture NT handle directly ([FrameSource.miniavBuffer]). The encoder
  /// opens the handle on its own device and copies via the COPY engine — zero
  /// shader-core work per frame, so a saturated GPU has nothing to starve.
  /// Frames whose size mismatches the encoder (mid-stream mode change) fall
  /// back to the GPU processor, which rescales.
  bool directD3d11Passthrough;

  /// When true (zero-copy D3D11 path WITH GPU work), the per-frame GPU stage
  /// and the encode stage run as a two-stage pipeline: the GPU processing of
  /// frame N+1 overlaps the encode of frame N, each stage internally
  /// serialized. Requires the processor's shared-texture ring (depth ≥ 2) so
  /// the stage-1 write never touches the texture stage 2 is reading.
  bool pipelinedZeroCopy;

  /// When true, output PTS are quantized to the exact fps grid and every grid
  /// slot is filled exactly once — live frames claim their nearest slot,
  /// missed slots are backfilled with duplicates of the previous frame, and
  /// surplus frames are dropped. See [FramePacer] for the full semantics.
  /// Default false = VFR (frames keep capture timestamps; near-target source
  /// cadence passes through untouched).
  final bool cfrOutput;

  /// Pacing policy: near-target VFR tolerance + CFR grid slotting.
  late final FramePacer _pacer = FramePacer(
    frameRateNum: frameRateNum,
    frameRateDen: frameRateDen,
    cfr: cfrOutput,
  );

  /// Keeps the encoder's imported-producer-texture cache in step with the
  /// producer (see [EncoderImportCache]).
  late EncoderImportCache _imports = EncoderImportCache(
    encoder.platform,
    // Direct passthrough submits the capture's own texture; a track with no
    // processor (GPU-output camera) submits nothing else. Every other shape
    // only ever submits the processor's encoder-sized output ring, which a
    // producer resize does not touch.
    importsProducerTextures: directD3d11Passthrough || processor == null,
  );

  /// The buffer currently retained as the duplicator's source, if any.
  /// Readable and settable so a test can assert it is released exactly once —
  /// releasing a capture buffer twice is a crash inside native code, and never
  /// releasing it is a leak that only shows up after an hour of recording.
  MiniAVBuffer? get duplicatorSource => _lastDirectBuffer;
  set duplicatorSource(MiniAVBuffer? b) => _lastDirectBuffer = b;

  /// How many buffers are retired and awaiting release.
  int get retiredBufferCount => _retiredDirectBuffers.length;

  /// Give up on [buffer] as a duplicator source. It is released once in-flight
  /// encodes have drained, never before — an encode may still be reading it.
  ///
  /// Happens for two unrelated reasons, which is why it is a list and not a
  /// slot: the capture target died, or re-encoding this buffer failed. Both
  /// can occur before a single drain, and a slot would silently lose whichever
  /// came second.
  void retireDuplicatorSource(MiniAVBuffer buffer) =>
      _retiredDirectBuffers.add(buffer);

  /// Last live frame retained for the duplicator on the direct-passthrough
  /// path (swap-released when the next live frame lands; released on stop).
  MiniAVBuffer? _lastDirectBuffer;

  /// Pipelined mode: stage-1 (GPU) in-flight flag, and the handoff slot from
  /// stage 1 to stage 2 (at most one frame waits here; stage 1 stalls while
  /// it is occupied so the texture ring never wraps onto a texture the
  /// encoder is still reading).
  bool _gpuBusy = false;
  ({SharedOutputTexture tex, int captureUs})? _readyFrame;

  // Bounded encode queue (replaces the former depth-1 `_busy` single-flight
  // gate). A brief encode overrun no longer drops the next frame: frame N+1
  // waits here while frame N is in flight. The encode stage itself stays
  // strictly serialized — the encoder/muxer FFI is single-threaded, so exactly
  // one [_encodeOne] runs at a time, guarded by [_encoding]. On a SUSTAINED
  // overrun (queue full) the OLDEST pending frame is dropped (counted as
  // [_statsBusyDropped]) so we always favour the freshest frames.
  static const int _maxQueueDepth = 3;
  final List<_PendingVideoFrame> _frameQueue = [];
  bool _encoding = false;
  bool _stopping = false;
  bool _firstChunkSent = false;
  int _lastVideoPtsUs = -1;

  // -------- Frame duplicator (zero-copy GPU path only) ------------------
  //
  // DXGI / WGC / WASAPI's screen-capture callbacks deliver a frame only when
  // the source surface changes.  On a mostly-static screen (e.g. user is
  // reading text) the capture cadence collapses to a few fps, which we then
  // honour 1:1 — the encoded stream genuinely contains that few-fps cadence
  // and the muxer writes correspondingly long frame durations.  On playback
  // that segment shows up as a freeze-then-jump and is universally reported
  // as "laggy video".
  //
  // The duplicator fixes this by re-encoding the last shared-output texture
  // at the target frame interval when the capture pipeline goes idle.  Cost
  // is negligible: the GPU pre-process step is skipped (the texture already
  // holds the last computed pixels), and NVENC / FFmpeg encoders produce
  // tiny P/skip frames (often <100 bytes) for a static input.
  //
  // Only active for the zero-copy GPU path because that's the only path
  // where we own a long-lived, reusable GPU texture by the time the encode
  // returns.  CPU-readback and fallback paths drop their source buffer
  // immediately so there is nothing to duplicate from.
  Timer? _dupTimer;
  SharedOutputTexture? _lastSharedTex;
  Recorder? _recForDup;

  // ---- Capture-target loss and re-acquire --------------------------------
  //
  // Field report (miniav_recorder 0.5.9, session f2bb70b3): a WGC capture item
  // closed 54 minutes into a 95-minute session. Nothing was wrong with the
  // machine — an independent capture of the SAME desktop stayed connected for
  // the remaining 41 minutes and the audio tracks never stopped — but the
  // recorder had no way to hear that its target had gone, so it re-encoded the
  // dead capture buffer at the frame rate for the rest of the session and
  // reported success at stop. 1 in 6 sessions.
  //
  // Two separate defects made that possible and both are fixed here: nothing
  // subscribed to the platform's capture-lost notification, and a duplicate
  // whose encode failed never retired its source (see [_encodeDuplicateDirect]).

  CaptureWatchdog? _watchdog;

  /// This track's single recovery — see [TrackRuntime.recoveries]. Null until
  /// [startCapture]; it needs the recorder's master clock.
  CaptureRecovery? get _recovery => soleRecovery;

  /// Capture buffers retired as duplicator sources — because the target died,
  /// or because re-encoding one failed. Their shared handles no longer
  /// resolve, but an encode may still be reading them, so they are released
  /// only once in-flight work has drained.
  ///
  /// A list rather than a single slot: retirement can happen more than once
  /// between drains (a failed duplicate, a live frame re-arming the source, a
  /// second failed duplicate), and a single slot would silently drop every
  /// buffer after the first.
  final List<MiniAVBuffer> _retiredDirectBuffers = [];

  /// Watches for a capture that has gone silent WITHOUT the platform saying
  /// so — the case the lost-callback cannot cover. See [CaptureWatchdog].
  Timer? _watchdogTimer;
  int _captureStartedAtUs = -1;
  int _silentLosses = 0;

  /// The dimensions the capture source is currently delivering, or 0 before
  /// the first frame.
  ///
  /// Not [width]/[height], which are the ENCODER's and are pinned by what the
  /// container already declared. This is what the platform is handing over,
  /// and comparing it against what the display currently IS turns a silent
  /// capture from a guess into a fact.
  int sourceWidth = 0;
  int sourceHeight = 0;

  /// Master-clock µs of the last frame delivered by the CAPTURE SOURCE.
  ///
  /// Deliberately not [TrackRuntime.lastPacketUs], which the idle-frame
  /// duplicator also advances: a frozen capture keeps that one fresh at the
  /// full frame rate. This one only moves when the platform hands over a
  /// frame it actually captured.
  int lastSourceFrameUs = -1;

  @override
  bool get captureStopping => _stopping;

  @override
  Iterable<String> get captureLossSummaries {
    // Which detector fired matters: a platform-reported loss is a known
    // event, while a watchdog loss is one nothing else would have caught.
    if (_silentLosses == 0) return super.captureLossSummaries;
    return super.captureLossSummaries.map(
          (s) => '$s ($_silentLosses detected by the watchdog, not reported '
              'by the platform)',
        );
  }

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
  // Drop counters are split by cause. Throttle drops are BY DESIGN (capture
  // delivers faster than the target fps and we intentionally pace down) and are
  // benign. Busy drops mean the bounded encode queue overflowed — i.e. real
  // back-pressure, the symptom this pipeline work targets. A config that is
  // genuinely _busy-bound shows a non-zero busy-drop count; throttle drops
  // alone are expected. Logged separately by [_maybeLogStats].
  int _statsThrottleDropped = 0;
  int _statsBusyDropped = 0;
  // Duplicate frames emitted (idle fill + CFR backfill). Counted inside
  // _statsPacketsOut as well; shown separately as dup= when non-zero.
  int _statsDupFrames = 0;
  int _statsPacketsOut = 0;
  int _statsEncodeErrors = 0;
  int _statsMinPktBytes = 0x7fffffff;
  int _statsMaxPktBytes = 0;
  int _statsTotalPktBytes = 0;
  // Per-stage wall-clock timing (µs). The GPU stage is the processor call
  // (downscale/effects/YUV/shared-texture copy) — under GPU saturation by
  // another workload its duration balloons because our submissions queue
  // behind that workload, which is exactly the pressure signal the adaptive
  // throttle keys off. The encode stage is the encoder.encode() call.
  int _statsGpuUsSum = 0;
  int _statsGpuUsMax = 0;
  int _statsGpuSamples = 0;
  int _statsEncUsSum = 0;
  int _statsEncUsMax = 0;
  int _statsEncSamples = 0;
  Stopwatch? _statsSw;

  /// Times the GPU-processor stage of one frame, records it in the stats
  /// counters, and feeds the adaptive throttle (logging divisor transitions).
  Future<T> _gpuStage<T>(Future<T> Function() stage) async {
    final sw = Stopwatch()..start();
    try {
      return await stage();
    } finally {
      sw.stop();
      final us = sw.elapsedMicroseconds;
      _statsGpuUsSum += us;
      _statsGpuSamples++;
      if (us > _statsGpuUsMax) _statsGpuUsMax = us;
      if (adaptiveGpuThrottle) {
        final prev = _gpuAdapt.divisor;
        final d = _gpuAdapt.addSample(us, _minFrameIntervalUs);
        if (d != prev) {
          Recorder._log(
            d > prev
                ? '$label GPU stage avg '
                      '${(_gpuAdapt.emaUs / 1000).toStringAsFixed(1)}ms exceeds '
                      'the frame budget (GPU saturated) — live capture reduced '
                      'to 1/$d of target fps; the frame duplicator keeps the '
                      'output cadence.'
                : '$label GPU pressure cleared — live capture restored to '
                      '1/$d of target fps.',
            RecorderLogLevel.warning,
          );
        }
      }
    }
  }

  /// Times the encoder stage of one frame and records it in the stats counters.
  Future<T> _encStage<T>(Future<T> Function() stage) async {
    final sw = Stopwatch()..start();
    try {
      return await stage();
    } finally {
      sw.stop();
      final us = sw.elapsedMicroseconds;
      _statsEncUsSum += us;
      _statsEncSamples++;
      if (us > _statsEncUsMax) _statsEncUsMax = us;
    }
  }

  @override
  Future<void> startCapture(Recorder rec) async {
    _statsSw = Stopwatch()..start();
    _recForDup = rec;
    _subscribeCaptureLost(rec);
    _startDupTimer(rec);
    _startWatchdog(rec);
    await startFn(_onFrame(rec));
  }

  /// Poll for a capture that has stopped producing without saying so.
  ///
  /// One second is far below the silence window it is testing against, so the
  /// poll rate costs nothing and the detection latency is set by the window
  /// rather than by this.
  void _startWatchdog(Recorder rec) {
    armWatchdog(rec.now());
    if (_watchdog == null) return;
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(tickWatchdog(rec)),
    );
  }

  /// Build the silence watchdog and start its grace period at [nowUs].
  ///
  /// Separate from the timer that drives it so the DECISION and its
  /// consequences can be exercised without waiting a second per tick — the
  /// wiring between this and [CaptureRecovery] is the part that has been
  /// wrong before, not the arithmetic on either side of it.
  void armWatchdog(int nowUs) {
    _watchdog = CaptureWatchdog(
      frameIntervalUs: _minFrameIntervalUs,
      idleFillActive: idleFramePolicy != VideoIdleFramePolicy.none,
    );
    _captureStartedAtUs = nowUs;
  }

  /// The armed watchdog, so its widening state is observable.
  CaptureWatchdog? get watchdog => _watchdog;

  /// One watchdog tick, including the check that has to ask the platform a
  /// question. Returns true when it declared the capture lost.
  Future<bool> tickWatchdog(Recorder rec) async {
    if (checkWatchdog(rec.now())) return true;

    final wd = _watchdog;
    final recovery = _recovery;
    if (wd == null || recovery == null) return false;
    if (_stopping || recovery.lost || recovery.ended) return false;

    // Only ask when already suspicious. A capture delivering frames never
    // reaches this line, so the probe costs a healthy recording nothing.
    final nowUs = rec.now();
    final since =
        lastSourceFrameUs >= 0 ? lastSourceFrameUs : _captureStartedAtUs;
    if (since < 0 || nowUs - since < CaptureWatchdog.probeSilenceUs) {
      return false;
    }
    if (_probing) return false;
    _probing = true;
    final String? drifted;
    try {
      drifted = await rec.displayTargetDrifted(this);
    } finally {
      _probing = false;
    }
    if (drifted == null) return false;
    // Re-check: the probe awaited, and the world may have moved under it.
    if (_stopping || recovery.lost || recovery.ended) return false;
    if (lastSourceFrameUs > since) return false; // frames came back meanwhile

    _silentLosses++;
    Recorder._log(
      '$label: no frame for '
      '${((rec.now() - since) / 1000000).toStringAsFixed(1)}s and $drifted — '
      'the capture is stale, not idle. The platform never reported a loss, so '
      'this is the watchdog calling it. Re-acquiring.',
      RecorderLogLevel.warning,
    );
    _releaseDeadCaptureState();
    _captureStartedAtUs = rec.now();
    lastSourceFrameUs = -1;
    lastPacketUs = -1;
    encodeErrorsSincePacket = 0;
    recovery.noteLost(watchdogLossReason, sinceUs: since);
    return true;
  }

  /// A probe is in flight. It awaits the platform, and stacking them would put
  /// several enumerations per second on a machine that is already struggling.
  bool _probing = false;

  /// One watchdog tick. Returns true when it declared the capture lost.
  bool checkWatchdog(int nowUs) {
    final wd = _watchdog;
    final recovery = _recovery;
    if (wd == null || recovery == null) return false;
    // Recovery already owns the situation, or the recording is ending.
    if (_stopping || recovery.lost || recovery.ended) return false;

    final noOutput = wd.shouldDeclareLost(
      nowUs: nowUs,
      lastPacketUs: lastPacketUs,
      errorsSincePacket: encodeErrorsSincePacket,
      startedAtUs: _captureStartedAtUs,
    );
    // Two different silences. Output stopping means the pipeline died; the
    // SOURCE stopping while output continues means the duplicator is painting
    // over a capture that is already gone, which is the frozen-picture case
    // and the one nothing used to catch.
    final noFrames = !noOutput &&
        wd.sourceWentSilent(
          nowUs: nowUs,
          lastSourceFrameUs: lastSourceFrameUs,
          startedAtUs: _captureStartedAtUs,
        );
    if (!noOutput && !noFrames) {
      // Frames are arriving, so any widening of the source window has served
      // its purpose and the next real death should be caught quickly again.
      wd.noteSourceAlive();
      return false;
    }

    // When the capture actually went quiet, as opposed to when this noticed.
    // Whichever test fired owns the clock: with the duplicator running,
    // lastPacketUs is fresh at the very moment the picture is frozen, so
    // reading it for a SOURCE-silence loss would time the outage at zero.
    final quietSince = noFrames
        ? (lastSourceFrameUs >= 0 ? lastSourceFrameUs : _captureStartedAtUs)
        : (lastPacketUs >= 0 ? lastPacketUs : _captureStartedAtUs);

    _silentLosses++;
    if (noFrames) {
      final waited = (wd.sourceSilenceThresholdUs / 1000000).toStringAsFixed(0);
      Recorder._log(
        '$label: the capture source delivered no frame for ${waited}s while '
        'the idle-frame duplicator kept the output flowing — a frozen '
        'picture, not a still one. The platform never reported a loss, so '
        'this is the watchdog calling it. Re-acquiring.',
        RecorderLogLevel.warning,
      );
      // In case the screen really was just static: see [widenSourceSilence].
      wd.widenSourceSilence();
    } else {
      Recorder._log(
        '$label produced no packet for '
        '${(wd.silenceThresholdUs / 1000000).toStringAsFixed(1)}s '
        '($encodeErrorsSincePacket encode error(s) since) — the platform '
        'never reported a loss, so this is the watchdog calling it. '
        'Re-acquiring.',
        RecorderLogLevel.warning,
      );
    }
    _releaseDeadCaptureState();
    // Restart the clocks so a re-acquire that does not fix it re-fires on the
    // silence window rather than immediately.
    _captureStartedAtUs = nowUs;
    lastSourceFrameUs = -1;
    lastPacketUs = -1;
    encodeErrorsSincePacket = 0;
    recovery.noteLost(watchdogLossReason, sinceUs: quietSince);
    return true;
  }

  /// Reason code for a loss nobody reported. Distinct from any platform code
  /// so a log line says which detector fired.
  static const int watchdogLossReason = -1;

  /// The capture callback. A method rather than an inline closure so a
  /// re-acquire can hand the platform the same one (see [_attemptReacquire]).
  void Function(MiniAVBuffer, Object?) _onFrame(Recorder rec) =>
      (MiniAVBuffer buffer, Object? _) {
      if (_stopping || captureLost) {
        // Drop and release.
        releaseCaptureBuffer(buffer);
        return;
      }
      _statsFramesIn++;
      lastSourceFrameUs = rec.now();
      final delivered = buffer.data;
      if (delivered is MiniAVVideoBuffer) {
        sourceWidth = delivered.width;
        sourceHeight = delivered.height;
      }
      _maybeLogStats();
      // Wall-clock acceptance time. Used both for the pacer and, when the
      // frame is accepted, as its capture timestamp (see [_PendingVideoFrame]).
      final nowUs = rec.now();
      // Frame pacing (see [FramePacer]): in VFR mode the fps throttle engages
      // only when the source meaningfully outruns the target rate — a source
      // within ~15% of target (e.g. DXGI delivering ~31.4 fps against 30)
      // passes through untouched, because deleting frames from a near-target
      // cadence turns one frame per ~20 into a double-length presentation
      // hole: a metronomic visible stutter. In CFR mode this drops frames
      // whose output grid slot is already spoken for. Under sustained GPU
      // saturation the adaptive divisor (2, 4) thins live frames evenly
      // either way, and the duplicator/backfill keeps the output cadence.
      // Audio sync is unaffected: both tracks use master-clock µs timestamps.
      final divisor = adaptiveGpuThrottle ? _gpuAdapt.divisor : 1;
      final wasThrottling = _pacer.throttleActive;
      final drop = _pacer.shouldDropOnArrival(nowUs, divisor: divisor);
      if (_pacer.throttleActive != wasThrottling) {
        Recorder._log(
          _pacer.throttleActive
              ? '$label fps throttle engaged — source cadence '
                    '${_pacer.arrivalEmaMs.toStringAsFixed(1)}ms outruns the '
                    '${(_minFrameIntervalUs / 1000).toStringAsFixed(1)}ms '
                    'target; thinning evenly to the target rate.'
              : '$label fps throttle released — source cadence '
                    '${_pacer.arrivalEmaMs.toStringAsFixed(1)}ms ≈ target; '
                    'passing all frames through (VFR).',
          RecorderLogLevel.info,
        );
      }
      if (drop) {
        _statsThrottleDropped++; // surplus vs target rate (or slot taken)
        releaseCaptureBuffer(buffer);
        return;
      }
      // Bounded-queue back-pressure (replaces the depth-1 `_busy` gate). Enqueue
      // and let the serialized pump drain it. Only a SUSTAINED overrun (queue
      // already full) drops a frame, and then the OLDEST so the freshest frames
      // survive.
      _frameQueue.add(_PendingVideoFrame(buffer, nowUs));
      if (_frameQueue.length > _maxQueueDepth) {
        final dropped = _frameQueue.removeAt(0);
        _statsBusyDropped++; // real back-pressure — encode can't keep up
        releaseCaptureBuffer(dropped.buffer);
      }
      _pumpQueue(rec);
      };



  /// Whether [fresh] may replace this track's stage.
  ///
  /// The container is what constrains a rebuild. A declared track's
  /// dimensions, codec and frame rate are written into the file's header
  /// before the first frame and cannot be revised — only the codec
  /// CONFIGURATION record may still change, and [Recorder.updateTrackConfig]
  /// handles that. So a rebuild that comes out a different shape is refused:
  /// a file whose header describes only its first half is worse than one that
  /// stops honestly.
  bool canAdopt(VideoTrackRuntime fresh) =>
      fresh.width == width &&
      fresh.height == height &&
      fresh.videoCodec == videoCodec &&
      fresh.frameRateNum == frameRateNum &&
      fresh.frameRateDen == frameRateDen;

  /// Take over [fresh]'s capture, processor and encoder, and destroy this
  /// track's own — a device reset survived without the file noticing.
  ///
  /// [fresh] is a fully built track runtime that was never started. Only its
  /// stage is wanted; the shell is discarded by the caller. Building a whole
  /// runtime to harvest it is deliberate: the alternative is a second copy of
  /// four hundred lines of capability negotiation that would drift from the
  /// original the first time either changed.
  ///
  /// The old stage is torn down FIRST and its failures ignored. After a device
  /// reset every object in it is bound to a removed device, so closing them is
  /// expected to fail — and a throw there must not lose the working stage that
  /// has already been built.
  Future<void> adoptStage(VideoTrackRuntime fresh) async {
    // Nothing may be encoding while the encoder is swapped underneath it.
    await drainInFlight();
    _releaseDeadCaptureState();
    _releaseRetiredBuffers();

    try {
      await stopFn();
    } catch (_) {}
    try {
      await encoder.close();
    } catch (_) {}
    try {
      processor?.dispose();
    } catch (_) {}
    try {
      await destroyFn();
    } catch (_) {}

    encoder = fresh.encoder;
    processor = fresh.processor;
    captureCtx = fresh.captureCtx;
    startFn = fresh.startFn;
    stopFn = fresh.stopFn;
    destroyFn = fresh.destroyFn;
    reacquireFn = fresh.reacquireFn;
    addLostListenerFn = fresh.addLostListenerFn;
    // Capability flags come WITH the stage. A rebuild can legitimately land on
    // a different path — the GPU came back but zero-copy did not — and keeping
    // the old flags would send frames down a route the new encoder cannot
    // take, which fails silently rather than loudly.
    processorCpuReadback = fresh.processorCpuReadback;
    processorGpuBuffer = fresh.processorGpuBuffer;
    directD3d11Passthrough = fresh.directD3d11Passthrough;
    pipelinedZeroCopy = fresh.pipelinedZeroCopy;

    // The import cache pins textures on the OLD encoder's device. Rebuilt, not
    // invalidated: invalidating tells the old encoder to drop its pins, and
    // the old encoder no longer exists.
    _imports = EncoderImportCache(
      encoder.platform,
      importsProducerTextures: directD3d11Passthrough || processor == null,
    );
    _lastEncodeError = null;

    // The first frame from the new encoder should be a keyframe. Nothing
    // downstream can predict where an outage ended, so a seek landing just
    // after one would otherwise have to run back to the previous IDR — across
    // a discontinuity, through frames the new encoder never produced.
    try {
      await encoder.requestKeyframe();
    } catch (_) {
      // Not every backend can force one, and a P-frame here is cosmetic.
    }

    // The lost-callback belonged to the context that was just destroyed.
    final recovery = _recovery;
    if (recovery != null) bindLostListener(recovery);
  }

  /// Release [fresh]'s stage without ever having used it — the rebuild came
  /// out incompatible with what the container already promised.
  static Future<void> discardStage(VideoTrackRuntime fresh) async {
    try {
      await fresh.encoder.close();
    } catch (_) {}
    try {
      fresh.processor?.dispose();
    } catch (_) {}
    try {
      await fresh.destroyFn();
    } catch (_) {}
  }

  // ---- Capture-target loss and re-acquire ---------------------------------

  void _subscribeCaptureLost(Recorder rec) {
    final recovery = CaptureRecovery(
      label: label,
      policy: lossPolicy,
      reacquireLimit: reacquireLimit,
      nowUs: rec.now,
      log: (String message, {bool severe = false}) => Recorder._log(
        message,
        severe ? RecorderLogLevel.error : RecorderLogLevel.warning,
      ),
      quiesce: () => _quiesceLostCapture(rec),
      // The escalation, offered only where there is something to escalate TO.
      //
      // [Recorder.rebuildVideoStage] handles the screen path and refuses every
      // other, and escalation is ONE-WAY: three soft failures and the recovery
      // never tries the cheap repair again. Offering it to a track the rebuild
      // will refuse therefore does not merely waste attempts, it parks the
      // source on a path that always answers false — a camera that came back
      // after four attempts would never be picked up.
      hardReacquire: canRebuildStage
          ? () => rec.rebuildVideoStage(this)
          : null,
      restart: () async {
        await startFn(_onFrame(rec));
        // A re-acquired capture has produced nothing yet; without this the
        // watchdog would judge it on the outage it just recovered from.
        _captureStartedAtUs = rec.now();
        lastSourceFrameUs = -1;
        lastPacketUs = -1;
        encodeErrorsSincePacket = 0;
        // Re-read the encoder's configuration record. A capture-item loss
        // leaves the encoder untouched and this is a no-op, which is the
        // point: the check costs nothing and it is the one place a recovery
        // that DID have to rebuild the encoder (a device reset takes every
        // D3D11 device on the adapter with it) can tell the container before
        // the first frame under new parameter sets is written.
        final cfg = encoder.platform.extraData?.bytes;
        if (cfg != null && cfg.isNotEmpty) {
          await rec.updateTrackConfig(this, Uint8List.fromList(cfg));
        }
        // Re-arm the duplicator. The CFR grid needs nothing: claimPts caps
        // inline backfill at FramePacer.maxInlineBackfill and jumps the slot
        // cursor forward, so an outage of any length becomes a timeline hole
        // rather than a burst of catch-up frames -- already the pacer's
        // documented behaviour for a long stall, and an outage is exactly a
        // long stall.
        _startDupTimer(rec);
      },
      // Null when there is no path at all (a window), and late-bound when
      // there is, because [adoptStage] replaces the field. See
      // [CaptureRecovery.lateBound] for why both halves matter.
      reacquire: CaptureRecovery.lateBound(() => reacquireFn),
    );
    bindLostListener(recovery);
  }

  /// Re-point the platform's capture-lost callback at [recovery] after a
  /// rebuild replaced the capture context. See [bindLostSubscription].
  void bindLostListener(CaptureRecovery recovery) => bindLostSubscription(
        recovery,
        addLostListenerFn,
        // Drop everything tied to the capture that just died BEFORE the
        // recovery starts, so nothing downstream keeps using it.
        onLost: _releaseDeadCaptureState,
      );

  /// Drop everything tied to the capture that just died, so nothing downstream
  /// keeps using it. Runs synchronously the moment the loss is known — this is
  /// what stops the failure loop, because the duplicator would otherwise go on
  /// handing the encoder a shared handle that no longer resolves.
  void _releaseDeadCaptureState() {
    _dupTimer?.cancel();
    _dupTimer = null;
    _readyFrame = null;
    _lastSharedTex = null;
    _imports.invalidate();
    for (final pending in _frameQueue) {
      releaseCaptureBuffer(pending.buffer);
    }
    _frameQueue.clear();
    // NOT released here: an encode may still be reading it. _quiesceLostCapture
    // releases them once in-flight work has drained.
    final retained = _lastDirectBuffer;
    _lastDirectBuffer = null;
    if (retained != null) retireDuplicatorSource(retained);
  }

  /// Release every retired duplicator source. Only safe once in-flight encodes
  /// have drained — [Recorder._shutdown] and [_quiesceLostCapture] are the two
  /// places where that holds.
  void _releaseRetiredBuffers() {
    if (_retiredDirectBuffers.isEmpty) return;
    for (final b in _retiredDirectBuffers) {
      releaseCaptureBuffer(b);
    }
    _retiredDirectBuffers.clear();
  }

  /// Let in-flight encodes finish, then release the dead capture's buffers and
  /// stop the platform side, so a re-configure is legal.
  Future<void> _quiesceLostCapture(Recorder rec) async {
    await drainInFlight();
    _releaseRetiredBuffers();
    // After a loss the platform's stop is a no-op, but a lost-listener can
    // also fire for something the session survived, and there the stop is what
    // makes the re-configure legal.
    try {
      await stopFn();
    } catch (_) {}
  }

  /// Starts encoding the next queued frame iff the (strictly serialized) encode
  /// stage is idle. Re-invoked from each encode's completion so the queue
  /// drains in order without ever running two encodes concurrently.
  ///
  /// In [pipelinedZeroCopy] mode this instead drives the two-stage pipeline:
  /// [_pumpGpu] (stage 1) runs the GPU processor for frame N+1 while
  /// [_pumpEnc] (stage 2) encodes frame N — each stage internally serialized,
  /// handing off through the single [_readyFrame] slot.
  void _pumpQueue(Recorder rec) {
    if (pipelinedZeroCopy) {
      _pumpGpu(rec);
      _pumpEnc(rec);
      return;
    }
    if (_encoding || _stopping) return;
    if (_frameQueue.isEmpty) return;
    _encoding = true;
    final pending = _frameQueue.removeAt(0);
    final fut = _encodeOne(rec, pending.buffer, pending.captureUs);
    _inFlight.add(fut);
    fut.whenComplete(() {
      _inFlight.remove(fut);
      _encoding = false;
      _pumpQueue(rec);
    });
  }

  // ---- Pipelined zero-copy pumps (stage 1: GPU, stage 2: encode) --------
  //
  // Under GPU saturation the GPU stage balloons (our passes queue behind the
  // other workload); pipelining hides it behind the encode stage instead of
  // serializing the two. Stage 1 only starts when the handoff slot is empty,
  // so with the processor's shared-texture ring (depth 2) the texture being
  // written is never the one the encoder is reading:
  //   slot A: encoding (stage 2)   slot B: being written (stage 1)

  void _pumpGpu(Recorder rec) {
    if (_gpuBusy || _stopping) return;
    if (_readyFrame != null) return; // handoff occupied — stall stage 1
    if (_frameQueue.isEmpty) return;
    _gpuBusy = true;
    final pending = _frameQueue.removeAt(0);
    final fut = _gpuOne(rec, pending);
    _inFlight.add(fut);
    fut.whenComplete(() {
      _inFlight.remove(fut);
      _gpuBusy = false;
      _pumpEnc(rec);
      _pumpGpu(rec);
    });
  }

  Future<void> _gpuOne(Recorder rec, _PendingVideoFrame pending) async {
    final buffer = pending.buffer;
    try {
      final proc = processor;
      if (proc == null ||
          buffer.contentType != MiniAVBufferContentType.gpuD3D11Handle) {
        // Should not happen on the pipelined (GPU-output) path — e.g. a rare
        // per-frame CPU fallback from the capture layer. Surface it via the
        // rate-limited error counter rather than feeding a mismatched frame
        // to the D3D11 encoder.
        _statsEncodeErrors++;
      encodeErrorsSincePacket++;
        _lastEncodeError = 'non-D3D11 buffer on pipelined zero-copy path';
        return;
      }
      final tex = await _gpuStage(() => proc.process(buffer));
      if (tex == null) return; // processor logged the reason; drop frame
      assert(_readyFrame == null, 'handoff slot must be empty (pump gate)');
      _readyFrame = (tex: tex, captureUs: pending.captureUs);
    } catch (e, st) {
      _statsEncodeErrors++;
      encodeErrorsSincePacket++;
      _lastEncodeError = e;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (_lastErrorLogMs == 0 ||
          nowMs - _lastErrorLogMs > _errorLogIntervalMs) {
        _lastErrorLogMs = nowMs;
        Recorder._log(
          '$label GPU stage error: $e\n$st',
          RecorderLogLevel.error,
        );
      }
    } finally {
      // The pixels now live in the processor's shared texture (or the frame
      // was dropped) — the capture buffer is no longer needed either way.
      releaseCaptureBuffer(buffer);
    }
  }

  void _pumpEnc(Recorder rec) {
    if (_encoding || _stopping) return;
    final ready = _readyFrame;
    if (ready == null) return;
    _readyFrame = null;
    _encoding = true;
    final fut = _encOne(rec, ready);
    _inFlight.add(fut);
    fut.whenComplete(() {
      _inFlight.remove(fut);
      _encoding = false;
      _pumpGpu(rec); // the freed handoff slot may unblock stage 1
      _pumpEnc(rec);
    });
  }

  Future<void> _encOne(
    Recorder rec,
    ({SharedOutputTexture tex, int captureUs}) ready,
  ) async {
    try {
      final claim = _pacer.claimPts(ready.captureUs);
      if (claim == null) {
        // CFR: the frame's grid slot was filled while it waited in the
        // pipeline (idle filler race) — drop it.
        _statsThrottleDropped++;
        return;
      }
      // CFR: fill grid slots the capture missed with duplicates of the
      // PREVIOUS frame — must run before _lastSharedTex is updated below.
      await _emitBackfill(rec, claim.backfillPtsUs);
      var ptsUs = claim.ptsUs;
      if (ptsUs <= _lastVideoPtsUs) ptsUs = _lastVideoPtsUs + 1;
      _lastVideoPtsUs = ptsUs;
      final proc = processor!;
      final src = D3D11TextureFrameSource(
        texturePtr: ready.tex.d3d11TexturePtr,
        width: proc.outputWidth,
        height: proc.outputHeight,
        pixelFormat: MiniAVPixelFormat.rgba32,
      );
      final pkt = await _encStage(() => encoder.encode(src));
      // Retain as the duplicator source only AFTER the encode returns (see
      // _maybeDuplicateLast). The CFR idle filler treats a valid source as
      // proof it can fill the slot it is about to claim; a source whose encode
      // threw cannot fill one — repeatLastFrame has no last frame to repeat —
      // and the claimed slot would stay empty forever.
      _lastSharedTex = ready.tex;
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
      encodeErrorsSincePacket++;
      _lastEncodeError = e;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (_lastErrorLogMs == 0 ||
          nowMs - _lastErrorLogMs > _errorLogIntervalMs) {
        _lastErrorLogMs = nowMs;
        Recorder._log(
          '$label encode stage error: $e\n$st',
          RecorderLogLevel.error,
        );
      }
    }
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
    // Per-stage timing: avg/max ms for the GPU-processor stage and the encoder
    // stage. A gpu= figure well above the frame interval while encoded fps sags
    // means the GPU is saturated (the adaptive throttle logs when it engages —
    // shown here as adapt=÷N while a reduced live rate is active).
    final gpuStr = _statsGpuSamples > 0
        ? ' gpu=${(_statsGpuUsSum / _statsGpuSamples / 1000).toStringAsFixed(1)}'
              '/${(_statsGpuUsMax / 1000).toStringAsFixed(1)}ms'
        : '';
    final encStr = _statsEncSamples > 0
        ? ' enc=${(_statsEncUsSum / _statsEncSamples / 1000).toStringAsFixed(1)}'
              '/${(_statsEncUsMax / 1000).toStringAsFixed(1)}ms'
        : '';
    final adaptStr = _gpuAdapt.divisor > 1 ? ' adapt=÷${_gpuAdapt.divisor}' : '';
    final dupStr = _statsDupFrames > 0 ? ' dup=${_statsDupFrames}' : '';
    Recorder._log(
      '$label video stats over ${secs.toStringAsFixed(1)}s: '
      'in=${_statsFramesIn} (${(_statsFramesIn / secs).toStringAsFixed(1)} fps) '
      'thr_drop=${_statsThrottleDropped} busy_drop=${_statsBusyDropped} '
      'encoded=${_statsPacketsOut} '
      '(${(_statsPacketsOut / secs).toStringAsFixed(1)} fps) '
      'pkt=$pktRange$gpuStr$encStr$adaptStr$dupStr$errStr',
    );
    _statsFramesIn = 0;
    _statsThrottleDropped = 0;
    _statsBusyDropped = 0;
    _statsDupFrames = 0;
    _statsPacketsOut = 0;
    _statsEncodeErrors = 0;
    _statsMinPktBytes = 0x7fffffff;
    _statsMaxPktBytes = 0;
    _statsTotalPktBytes = 0;
    _statsGpuUsSum = 0;
    _statsGpuUsMax = 0;
    _statsGpuSamples = 0;
    _statsEncUsSum = 0;
    _statsEncUsMax = 0;
    _statsEncSamples = 0;
    sw.reset();
  }

  Future<void> _encodeOne(
    Recorder rec,
    MiniAVBuffer buffer, [
    int? captureUs,
  ]) async {
    // Set by the direct-passthrough branch: the buffer is retained as the
    // duplicator's source instead of being released in the finally below.
    var retainBuffer = false;
    try {
      // Keep the encoder's imported-producer-texture cache in step with the
      // producer before anything decides what to encode: a resize kills those
      // surfaces whether or not this particular frame makes it out. A drop
      // takes the encoder's retained repeat source with it, and that is
      // invisible from outside the encoder — so the duplicator's proof that a
      // repeat is still possible has to be cleared here too, or a CFR idle
      // slot gets claimed and never filled. See [EncoderImportCache.noteFrame].
      if (_imports.noteFrame(buffer) >= 0) _lastSharedTex = null;

      // PTS from the pacer: the capture-time timestamp recorded at enqueue in
      // VFR mode (falling back to now() if the frame was encoded outside the
      // queue), the claimed grid-slot time in CFR mode. This keeps PTS spacing
      // stable even when the serialized encoder briefly stalls and then
      // drains several queued frames back-to-back.
      final claim = _pacer.claimPts(captureUs ?? rec.now());
      if (claim == null) {
        // CFR: the frame's grid slot was filled while it waited in the
        // pipeline (idle filler race) — drop it (finally releases the buffer).
        _statsThrottleDropped++;
        return;
      }
      // CFR: fill grid slots the capture missed with duplicates of the
      // PREVIOUS frame — must run before the branches below update the
      // retained duplicator sources (_lastDirectBuffer / _lastSharedTex).
      await _emitBackfill(rec, claim.backfillPtsUs);
      var ptsUs = claim.ptsUs;
      // Guarantee strict monotonic increase even on sub-µs frame deltas.
      if (ptsUs <= _lastVideoPtsUs) ptsUs = _lastVideoPtsUs + 1;
      _lastVideoPtsUs = ptsUs;

      // --- Direct D3D11 passthrough (source-agnostic; no processor needed) ---
      // A GPU-handle frame that is already encoder-sized and whose encoder
      // accepts the capture's shared NT handle needs no processing at all: hand
      // the handle straight to the encoder, which opens it on its own device and
      // copies it with the COPY engine. This is IDENTICAL for a screen capture
      // with no scale/effects and for a GPU-output camera — neither needs a
      // GpuScreenProcessor. The check lives ABOVE the processor gate so a
      // processor-less source (camera) reaches it too. A size-mismatched frame
      // (a screen mid-stream display-mode change) falls through to the
      // processor's rescale below; a fixed-format source (camera) never makes
      // one. Passthrough is mutually exclusive with the readback / gpu-buffer
      // modes (the builder never sets it alongside them), so this cannot
      // intercept a frame one of those owns.
      final isGpuHandle =
          buffer.contentType == MiniAVBufferContentType.gpuD3D11Handle;
      if (directD3d11Passthrough && isGpuHandle) {
        final vb = buffer.data;
        if (vb is MiniAVVideoBuffer &&
            vb.width == width &&
            vb.height == height) {
          final src = FrameSource.miniavBuffer(buffer);
          final pkt = await _encStage(() => encoder.encode(src));
          // Retain this frame as the duplicator's source and release the
          // previously retained one. The NT handle + capture-side texture stay
          // valid until the buffer is released.
          final prev = _lastDirectBuffer;
          _lastDirectBuffer = buffer;
          retainBuffer = true;
          _lastSharedTex = null; // direct frame supersedes any old texture
          if (prev != null) releaseCaptureBuffer(prev);
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
        // Size mismatch → fall through to the processor rescale (screen); with
        // no processor the normal path below surfaces a rate-limited size error.
      }

      // --- GPU processor paths (scale/effects, readback, gpu-buffer) ---------
      // These genuinely need a GpuScreenProcessor and a D3D11-handle buffer.
      final proc = processor;
      if (proc != null && isGpuHandle) {
        if (processorGpuBuffer) {
          // (C) GPU buffer hot path: processor returns a packed RGBA8 GPU
          // Buffer that the minigpu encoder (e.g. MinigpuAv1Pipeline) consumes
          // directly without any CPU round-trip.
          final gpuBuf = await _gpuStage(() => proc.processToGpuBuffer(buffer));
          if (gpuBuf != null) {
            // encoder.platform is GpuCodecEncoder (from miniav_tools_codecs)
            // which we cannot import here (would create a circular dep).
            // Use dynamic dispatch — safe because processorGpuBuffer is only
            // ever set to true when encoder.platform.supportsGpuBufferInput=true.
            final pkt = await _encStage(
              // ignore: avoid_dynamic_calls
              () async =>
                  await (encoder.platform as dynamic).encodeFromGpuBuffer(
                        gpuBuf,
                        proc.outputWidth,
                        proc.outputHeight,
                        timestampUs: ptsUs,
                      )
                      as EncodedPacket?,
            );
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
          // processToGpuBuffer returned null — fall through to CPU path.
          final vb = buffer.data is MiniAVVideoBuffer
              ? buffer.data as MiniAVVideoBuffer
              : null;
          Recorder._log(
            '$label GPU processToGpuBuffer() returned null — dropping frame '
            '(${vb?.width}x${vb?.height} cannot be '
            'fed to ${width}x$height encoder).',
            RecorderLogLevel.warning,
          );
          return;
        } else if (!processorCpuReadback) {
          // (A) Zero-copy GPU encode WITH scale/effects, or the rescale path for
          // a passthrough frame whose size no longer matches the encoder (a
          // screen mid-stream mode change): the processor returns a
          // SharedOutputTexture the D3D11 hardware encoder reads directly — no
          // PCIe round-trip. The no-work, correctly-sized passthrough is handled
          // above, before the processor gate, so it also serves processor-less
          // sources (a GPU-output camera).
          final sharedTex = await _gpuStage(() => proc.process(buffer));
          if (sharedTex != null) {
            // A processor-produced texture supersedes any frame retained by
            // the direct-passthrough path (e.g. after a mode-change fallback).
            final staleDirect = _lastDirectBuffer;
            if (staleDirect != null) {
              _lastDirectBuffer = null;
              releaseCaptureBuffer(staleDirect);
            }
            final src = D3D11TextureFrameSource(
              texturePtr: sharedTex.d3d11TexturePtr,
              width: proc.outputWidth,
              height: proc.outputHeight,
              pixelFormat: MiniAVPixelFormat.rgba32,
            );
            final pkt = await _encStage(() => encoder.encode(src));
            // Remember for the frame duplicator: when capture goes idle on a
            // static screen, the duplicator re-encodes this same texture at
            // the target frame rate so playback stays smooth.  The processor
            // owns the texture; we just hold a reference and check isValid
            // before using it from the timer.
            //
            // Only AFTER a successful encode: the CFR idle filler reads this as
            // proof that the slot it is about to claim CAN be filled, and a
            // texture the encoder rejected would leave that slot permanently
            // empty (repeatLastFrame has nothing to repeat).
            _lastSharedTex = sharedTex;
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
          // GPU processor returned null (resource init failed, handle invalid,
          // or importVideoFrame threw — e.g. after a game full-screen resolution
          // change while DXGI re-acquires).  The encoder is sized for the
          // processor's output, so the raw D3D11 buffer cannot be fed directly.
          // Drop this frame.
          final vb = buffer.data is MiniAVVideoBuffer
              ? buffer.data as MiniAVVideoBuffer
              : null;
          Recorder._log(
            '$label GPU process() returned null — dropping frame '
            '(${vb?.width}x${vb?.height} cannot be '
            'fed to ${width}x$height encoder).',
            RecorderLogLevel.warning,
          );
          return;
        } else {
          // (B) GPU downscale + CPU readback: processor runs the expensive
          // bilinear resize on the GPU (e.g. 4K→1080p on the Intel iGPU),
          // then reads the smaller result back to CPU for NVENC or software
          // encoding. Avoids saturating the isolate with a full-resolution
          // Dart bilinear rescale on every frame.
          //
          // (B1) When the encoder consumes YUV420P natively (software path),
          // convert RGBA→YUV420P on the GPU and read back the ~2.7× smaller
          // planes — no RGBA read-back, no per-pixel CPU conversion.
          if (encoder.platform.acceptsYuv420pPlanes) {
            final yuv = await _gpuStage(() => proc.processToYuv420(buffer));
            if (yuv != null) {
              final src = FrameSource.yuv420p(
                yPlane: yuv.y,
                uPlane: yuv.u,
                vPlane: yuv.v,
                width: yuv.width,
                height: yuv.height,
              );
              final pkt = await _encStage(() => encoder.encode(src));
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
            // GPU YUV conversion failed — fall through to the RGBA read-back.
          }
          // (B2) RGBA read-back (CPU-fed HW encoders that want NV12/RGBA, or
          // the YUV fast-path fell through).
          final pixels = await _gpuStage(() => proc.processToBytes(buffer));
          if (pixels != null) {
            final src = FrameSource.cpu(
              bytes: pixels,
              pixelFormat: MiniAVPixelFormat.rgba32,
              width: proc.outputWidth,
              height: proc.outputHeight,
            );
            final pkt = await _encStage(() => encoder.encode(src));
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
          // processToBytes returned null — GPU import/dispatch failed (e.g.
          // device lost or handle revoked after a display mode change). Fall
          // through to the normal CPU path, which will receive the raw D3D11
          // handle — it will fail too, but the error will be rate-limited and
          // logged, and we avoid a silent frame drop here.
        }
      }

      // --- Normal / fallback path ----------------------------------------
      // Handles CPU buffers, D3D11 buffers when no GPU processor is
      // configured (processor == null), and the processToBytes() failure
      // fall-through above.
      final src = FrameSource.miniavBuffer(buffer);
      final pkt = await _encStage(() => encoder.encode(src));
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
      encodeErrorsSincePacket++;
      _lastEncodeError = e;
      // Rate-limit: log on first occurrence and at most every 5 seconds after.
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (_lastErrorLogMs == 0 ||
          nowMs - _lastErrorLogMs > _errorLogIntervalMs) {
        _lastErrorLogMs = nowMs;
        Recorder._log('$label encode error: $e\n$st', RecorderLogLevel.error);
      }
    } finally {
      if (!retainBuffer) releaseCaptureBuffer(buffer);
    }
  }

  @override
  Future<void> stopCapture() async {
    _stopping = true;
    cancelRecoveries();
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _dupTimer?.cancel();
    _dupTimer = null;
    _lastSharedTex = null;
    _readyFrame = null; // pipelined handoff slot (texture is processor-owned)
    // NOTE: _lastDirectBuffer is NOT released here — a duplicate encode may
    // still be in flight using it (Recorder._shutdown drains in-flight work
    // only AFTER stopCapture). It is released in [dispose].
    await stopFn();
    // The pump stops accepting work once _stopping is set, so any frames still
    // waiting in the queue would otherwise leak their native buffers. Release
    // them now (stopFn() has halted the source, so no new frames will enqueue).
    for (final pending in _frameQueue) {
      releaseCaptureBuffer(pending.buffer);
    }
    _frameQueue.clear();
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

  // ---- Frame duplicator implementation --------------------------------

  /// CFR backfill: emit a duplicate of the previous frame at each missed grid
  /// slot PTS (oldest first) so the output timeline has no presentation
  /// holes. Uses whichever duplicator source the active path retains; on
  /// paths that retain nothing (CPU readback / GPU-buffer encode) the slots
  /// are left unfilled — same scope as the idle duplicator, which is
  /// zero-copy-path only. Runs inside the already-serialized encode stage.
  Future<void> _emitBackfill(Recorder rec, List<int> ptsList) async {
    for (final pts in ptsList) {
      final directBuf = _lastDirectBuffer;
      if (directBuf != null) {
        await _encodeDuplicateDirect(rec, directBuf, pts);
        continue;
      }
      final tex = _lastSharedTex;
      if (tex != null && tex.isValid) {
        await _encodeDuplicate(rec, tex, pts);
        continue;
      }
      break; // nothing retained yet (first frames) — leave the hole
    }
  }

  void _startDupTimer(Recorder rec) {
    if (idleFramePolicy == VideoIdleFramePolicy.none) return;
    _recForDup = rec;
    final intervalUs = _minFrameIntervalUs;
    if (intervalUs <= 0) return;
    // Timer.periodic granularity is milliseconds.  Fire at ~the target
    // rate; the actual emit decision is gated on _lastVideoPtsUs so a
    // slightly faster timer just produces more no-op ticks.
    final intervalMs = math.max(1, intervalUs ~/ 1000);
    _dupTimer = Timer.periodic(
      Duration(milliseconds: intervalMs),
      (_) => _maybeDuplicateLast(),
    );
  }

  void _maybeDuplicateLast() {
    // Only duplicate when the live pipeline is genuinely idle: nothing is
    // encoding (either stage, in pipelined mode), no live frames are waiting
    // in the queue, and no processed frame is awaiting encode. Otherwise a
    // duplicate would compete with (and delay) real frames.
    if (_stopping ||
        _encoding ||
        _gpuBusy ||
        _readyFrame != null ||
        _frameQueue.isNotEmpty) {
      return;
    }
    final rec = _recForDup;
    if (rec == null) return;
    final intervalUs = _minFrameIntervalUs;
    if (intervalUs <= 0) return;
    // A retained texture the processor has destroyed took the whole shared-
    // output ring with it, so every slot the encoder imported is now a freed
    // address it is still holding a reference to. Unlike a resize this is not
    // visible in any frame's geometry — the ring is encoder-sized either way —
    // so it has to be said explicitly. Ahead of the policy branch on purpose:
    // the `black` policy never looks at the texture and would otherwise leave
    // the imports pinned for the rest of the recording.
    final retainedTex = _lastSharedTex;
    if (retainedTex != null && !retainedTex.isValid) {
      _lastSharedTex = null;
      _imports.invalidate();
    }
    final nowUs = rec.now();
    int fillPtsUs;
    if (cfrOutput) {
      // CFR: fill the next unfilled grid slot once its claim window has
      // passed (see FramePacer.claimIdleSlot). Check that a fill source
      // exists BEFORE claiming — a claimed slot we cannot fill would become
      // a permanent timeline hole.
      // _lastSharedTex is known valid here (dead ones were dropped above) and
      // is only ever set after an encode the encoder ACCEPTED, so it doubles
      // as proof that its retained repeat source exists.
      final hasSource =
          idleFramePolicy == VideoIdleFramePolicy.black ||
          _lastDirectBuffer != null ||
          _lastSharedTex != null;
      if (!hasSource) return;
      final slotPts = _pacer.claimIdleSlot(nowUs);
      if (slotPts == null) return;
      fillPtsUs = slotPts;
    } else {
      // VFR: only fill if a frame hasn't been emitted within ~1.5 intervals —
      // i.e. the live capture path is currently keeping up.
      if (_lastVideoPtsUs < 0 ||
          nowUs - _lastVideoPtsUs < (intervalUs * 3) ~/ 2) {
        return;
      }
      fillPtsUs = nowUs;
    }
    if (idleFramePolicy == VideoIdleFramePolicy.duplicate) {
      // Direct-passthrough mode retains the last live capture buffer instead
      // of a processor texture — re-encode it via its NT handle.
      final directBuf = _lastDirectBuffer;
      if (directBuf != null) {
        _encoding = true;
        final fut = _encodeDuplicateDirect(rec, directBuf, fillPtsUs);
        _inFlight.add(fut);
        fut.whenComplete(() {
          _inFlight.remove(fut);
          _encoding = false;
          _pumpQueue(rec);
        });
        return;
      }
      // Already checked for validity above, before the policy branch.
      final tex = _lastSharedTex;
      if (tex == null) return;
      _encoding = true;
      final fut = _encodeDuplicate(rec, tex, fillPtsUs);
      _inFlight.add(fut);
      fut.whenComplete(() {
        _inFlight.remove(fut);
        _encoding = false;
        // A live frame may have raced in while we were duplicating.
        _pumpQueue(rec);
      });
    } else if (idleFramePolicy == VideoIdleFramePolicy.black) {
      _encoding = true;
      final fut = _encodeBlack(rec, fillPtsUs);
      _inFlight.add(fut);
      fut.whenComplete(() {
        _inFlight.remove(fut);
        _encoding = false;
        _pumpQueue(rec);
      });
    }
  }

  // Pre-allocated all-zeros RGBA buffer for black frame fill.
  Uint8List? _blackFrameCache;
  Uint8List get _blackFrameData =>
      _blackFrameCache ??= Uint8List(width * height * 4);

  Future<void> _encodeDuplicate(
    Recorder rec,
    SharedOutputTexture tex,
    int nowUs,
  ) async {
    try {
      var ptsUs = nowUs;
      if (ptsUs <= _lastVideoPtsUs) ptsUs = _lastVideoPtsUs + 1;
      _lastVideoPtsUs = ptsUs;
      // Prefer asking the encoder to repeat its last frame. A duplicate is the
      // same picture with a new timestamp, and expressing that by re-importing
      // the producer's texture makes it depend on a surface lifetime we do not
      // own -- this timer fires precisely when the pipeline is idle, which is
      // when that surface is most likely to have been recycled. It also fails
      // outright when there is no GPU processor writing the texture at all
      // (direct passthrough, gpuWork=false), which is a configuration where the
      // duplicate has no business importing anything.
      final platform = encoder.platform;
      EncodedPacket? pkt;
      if (platform is MfVideoEncoder) {
        pkt = await platform.repeatLastFrame(ptsUs);
      } else {
        pkt = await encoder.encode(D3D11TextureFrameSource(
          texturePtr: tex.d3d11TexturePtr,
          width: tex.width,
          height: tex.height,
          pixelFormat: MiniAVPixelFormat.rgba32,
        ));
      }
      if (pkt != null) {
        _statsPacketsOut++;
        _statsDupFrames++;
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
      encodeErrorsSincePacket++;
      _lastEncodeError = e;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (_lastErrorLogMs == 0 ||
          nowMs - _lastErrorLogMs > _errorLogIntervalMs) {
        _lastErrorLogMs = nowMs;
        Recorder._log(
          '$label duplicate encode error: $e\n$st',
          RecorderLogLevel.error,
        );
      }
    }
  }

  /// Duplicate-encode for the direct-passthrough path: re-encodes the retained
  /// last live capture buffer via its NT handle (see [_lastDirectBuffer]).
  Future<void> _encodeDuplicateDirect(
    Recorder rec,
    MiniAVBuffer buf,
    int nowUs,
  ) async {
    try {
      var ptsUs = nowUs;
      if (ptsUs <= _lastVideoPtsUs) ptsUs = _lastVideoPtsUs + 1;
      _lastVideoPtsUs = ptsUs;
      final src = FrameSource.miniavBuffer(buf);
      final pkt = await encoder.encode(src);
      if (pkt != null) {
        _statsPacketsOut++;
        _statsDupFrames++;
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
      encodeErrorsSincePacket++;
      _lastEncodeError = e;
      // RETIRE the source. A duplicate is a re-encode of a buffer we retained
      // ourselves - if it fails, it will fail identically every time the idle
      // timer fires, because nothing about it changes. Keeping it made the
      // recorder re-encode a dead capture handle ~30 times a second for 41
      // minutes (see the capture-loss note above), reporting the same error
      // into a 5-second rate limiter so the log showed a trickle rather than
      // the flood it was. `_lastSharedTex` already has an isValid gate above;
      // the direct-passthrough buffer had nothing equivalent.
      //
      // Dropping the reference costs at most a duplicate: the next LIVE frame
      // re-arms it. If no live frame comes, there was nothing to duplicate.
      if (identical(_lastDirectBuffer, buf)) {
        _lastDirectBuffer = null;
        retireDuplicatorSource(buf);
      }
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (_lastErrorLogMs == 0 ||
          nowMs - _lastErrorLogMs > _errorLogIntervalMs) {
        _lastErrorLogMs = nowMs;
        Recorder._log(
          '$label direct duplicate encode error (source retired): $e\n$st',
          RecorderLogLevel.error,
        );
      }
    }
  }

  Future<void> _encodeBlack(Recorder rec, int nowUs) async {
    try {
      var ptsUs = nowUs;
      if (ptsUs <= _lastVideoPtsUs) ptsUs = _lastVideoPtsUs + 1;
      _lastVideoPtsUs = ptsUs;
      final src = FrameSource.cpu(
        bytes: _blackFrameData,
        pixelFormat: MiniAVPixelFormat.rgba32,
        width: width,
        height: height,
      );
      final pkt = await encoder.encode(src);
      if (pkt != null) {
        _statsPacketsOut++;
        _statsDupFrames++;
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
      encodeErrorsSincePacket++;
      _lastEncodeError = e;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (_lastErrorLogMs == 0 ||
          nowMs - _lastErrorLogMs > _errorLogIntervalMs) {
        _lastErrorLogMs = nowMs;
        Recorder._log(
          '$label black frame encode error: $e\n$st',
          RecorderLogLevel.error,
        );
      }
    }
  }

  @override
  Future<void> dispose() async {
    // Release the duplicator's retained direct-passthrough frame. Safe here:
    // Recorder._shutdown has already drained in-flight encodes (step 2), so
    // nothing can still be reading the buffer.
    final retained = _lastDirectBuffer;
    _lastDirectBuffer = null;
    if (retained != null) releaseCaptureBuffer(retained);
    // Anything retired that no re-acquire attempt got round to releasing.
    _releaseRetiredBuffers();
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
  @override
  Uint8List? get encoderConfigRecord => encoder.platform.extraData?.bytes;

  @override
  TrackInfo toTrackInfo() => VideoTrackInfo(
    codec: videoCodec,
    width: width,
    height: height,
    frameRateNumerator: frameRateNum,
    frameRateDenominator: frameRateDen,
    // Codec-private data (SPS/PPS) when the encoder exposes it at open time
    // (software encoders with global_header do). Lets FfmpegMuxer write the
    // track header without a live encoder bridge — required for the
    // isolate-hosted software encoder, whose AVCodecContext lives on a worker
    // isolate. Bridge-capable encoders (D3D11/HW) still provide their bridge
    // via [encoderBridge], which the muxer prefers.
    extraData: encoder.platform.extraData,
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

class AudioTrackRuntime extends TrackRuntime {
  AudioTrackRuntime({
    required super.index,
    required super.label,
    required this.encoder,
    required this.encoderConfig,
    required this.audioCodec,
    required this.sampleRate,
    required this.channels,
    required this.audioFormat,
    required this.captureCtx,
    required this.startFn,
    required this.stopFn,
    required this.destroyFn,
    this.lossPolicy = CaptureLossPolicy.reacquire,
    this.reacquireLimit,
    this.addLostListenerFn,
    this.reacquireFn,
  });

  /// Not final: [repinAudioEncoderToFfmpeg] swaps it during sink construction.
  AudioEncoder encoder;

  /// What to do when the capture DEVICE goes away — see [CaptureLossPolicy].
  final CaptureLossPolicy lossPolicy;
  final Duration? reacquireLimit;

  /// The platform's device-lost subscription, or null where the backend
  /// cannot report its own death.
  final void Function() Function(MiniAVContextLostListener)? addLostListenerFn;

  /// Re-configure this track's capture context onto whatever id names its
  /// device now. Null for a source with no re-acquire path.
  final ReacquireFn? reacquireFn;

  /// The config [encoder] was opened with, kept so it can be re-opened on a
  /// different backend without re-deriving the capture format.
  final AudioEncoderConfig encoderConfig;
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

  // Audio PTS is computed from cumulative sample count anchored to a single
  // epoch (captured on the first callback), NOT from rec.now() on every
  // callback.  Wall-clock PTSs jitter with the capture-callback delivery
  // time — when the Dart isolate is briefly blocked, several audio buffers
  // back up and then fire bunched within a few hundred microseconds, all
  // stamped with near-identical now() values.  The AAC muxer then either
  // collapses the timeline or inserts edit-list gaps, which is heard as
  // clicks / crackle.  Sample-count PTSs are monotonic, perfectly uniform,
  // and unaffected by isolate scheduling.
  int _samplesEmitted = 0;
  int _audioEpochUs = 0;
  bool _audioEpochSet = false;

  // Crystal-drift correction. The audio hardware oscillator and the CPU QPC
  // oscillator (Stopwatch) diverge at up to 100 ppm, causing the sample-count
  // PTS to drift away from the wall-clock PTS used by the video track. Over a
  // 30-minute recording at 100 ppm that is 180 ms — clearly audible.
  //
  // Two-tier correction:
  //   |drift| > [_driftSnapThresholdUs] → snap epoch to wall clock.
  //   |drift| > [_driftThresholdUs]     → nudge epoch by ±[_driftCorrectionUs].
  //
  // **Snap** handles the case where audio simply stops for a while (audio
  // device sleep, WASAPI exclusive-mode preemption, very long isolate stall,
  // app minimised long enough that loopback never fires).  When playback
  // resumes hundreds of ms / seconds later, the sample-count PTS is far
  // behind wall clock and slow ppm correction cannot catch up in finite time.
  // Snapping aligns the next PTS exactly to wall clock.
  //
  // **Nudge** handles steady-state ppm drift.  At ~100 callbacks/s the nudge
  // rate is 100 × 20 µs = 2 ms/s, two orders of magnitude above the worst
  // observed crystal drift (~10 µs/s = 100 ppm) and well below the 5 ms/s
  // (≈0.5%) audible pitch threshold.
  //
  // Snap threshold = 5 s: the snap is now a catastrophic-only fallback.
  // Genuine capture gaps are detected via capture timestamps and filled with
  // silence (see the capture-gap fields below), which keeps the encoder's
  // sample-count timeline correct — something an epoch snap cannot do. The
  // snap must be far above any plausible isolate stall, because a stall
  // delivers its backlog in a capture-contiguous burst whose arrival drift
  // looks like a gap; snapping on it would mislabel the whole burst.
  static const int _driftThresholdUs = 10000; // 10 ms — nudge boundary
  static const int _driftSnapThresholdUs = 5000000; // 5 s — catastrophic only
  static const int _driftCorrectionUs = 20; // 20 µs nudge cap per callback

  // ── Capture-gap silence fill (capture-timestamp based) ───────────────────
  // WASAPI loopback delivers NO buffers at all while the render endpoint is
  // idle (nothing playing) — not even SILENT-flagged ones. Because the AAC
  // encoder derives every output packet's PTS from the cumulative sample
  // COUNT fed to it (the wall-clock ptsUs we pass only slews its epoch at
  // ±50 µs/call), an unfilled gap makes ALL audio after it play early — a
  // growing A/V desync. When capture resumes we inject silence covering the
  // missing span.
  //
  // Detection uses buffer.timestampUs — the packet's CAPTURE time stamped on
  // the native thread (QPC for loopback, monotonic µs for mic). Only deltas
  // are used; the absolute value is boot-relative and never enters the PTS.
  // Wall-clock drift at ARRIVAL cannot be used to detect gaps: when the Dart
  // isolate stalls (GC / heavy GPU work), the native capture thread keeps
  // queueing packets, which then arrive late in a burst. Arrival drift looks
  // identical to an idle gap, but no samples are missing — filling (or
  // snapping) there inserts phantom silence AND pushes the sample count past
  // wall clock, desyncing everything after the stall. Capture timestamps
  // distinguish the two cases exactly: bursts are capture-contiguous, idle
  // gaps jump.
  static const int _captureGapThresholdUs = 30000; // 3 lost 10 ms packets
  // Cap one gap fill so a very long idle stretch (AFK for minutes) can't
  // encode an unbounded amount of silence in one callback; any remainder
  // beyond the cap is absorbed by the (catastrophic-only) epoch snap.
  static const int _maxGapFillUs = 60000000; // 60 s
  // Chunk size for the silence-fill loop — bounds transient PCM allocation.
  static const int _gapFillChunkUs = 1000000; // 1 s
  // Fallback when the platform doesn't stamp capture times (timestampUs == 0):
  // wall-clock-deficit fill. Cannot tell bursts from gaps, so it keeps the
  // conservative 100 ms threshold.
  static const int _wallGapFillThresholdUs = 100000; // 100 ms

  // Projected capture timestamp of the next buffer's first sample
  // (= last buffer's capture time + its duration).
  int _expectedCaptureUs = 0;
  bool _captureTsValid = false;

  /// Sequential encode chain. Every chunk — live or gap fill — is appended
  /// here, so the packets this track hands the muxer are always in the order
  /// their PTSs were assigned. See the note at the live-chunk enqueue for why
  /// arrival order and not just PTS order is what has to be guaranteed.
  Future<void> _encodeChain = Future<void>.value();

  @override
  bool get captureStopping => _stopping;

  @override
  Future<void> startCapture(Recorder rec) async {
    _subscribeCaptureLost(rec);
    await startFn(_onAudio(rec));
  }

  /// Wire the platform's device-lost callback to a re-acquire loop.
  ///
  /// No watchdog here, unlike the video path, and that is a decision rather
  /// than an omission: a WASAPI loopback endpoint delivers NOTHING at all
  /// while the render side is idle — not even silent buffers — so silence is
  /// evidence of a quiet room, not of a dead device. The platform callback is
  /// the only signal that means what it says.
  void _subscribeCaptureLost(Recorder rec) {
    final recovery = CaptureRecovery(
      label: label,
      policy: lossPolicy,
      reacquireLimit: reacquireLimit,
      nowUs: rec.now,
      log: (String message, {bool severe = false}) => Recorder._log(
        message,
        severe ? RecorderLogLevel.error : RecorderLogLevel.warning,
      ),
      // Nothing here holds a GPU surface. What must not overlap a
      // re-configure is an encode still reading the buffer that was in flight
      // when the device died.
      quiesce: drainInFlight,
      restart: () async {
        // The new device's capture timestamps are not a continuation of the
        // old one's. Comparing across them would read as one enormous gap (or
        // a negative one) and either fill minutes of silence or corrupt the
        // epoch. Dropping the anchor makes the next buffer re-seed it, and the
        // wall-clock drift correction — which is what covers a gap longer than
        // the fill cap anyway — carries the outage.
        _captureTsValid = false;
        await startFn(_onAudio(rec));
        lastPacketUs = -1;
        encodeErrorsSincePacket = 0;
      },
      reacquire: reacquireFn,
      // No escalation, because there is nothing left to escalate TO. The soft
      // path here is already a full platform rebuild: WASAPI's configure
      // releases the capture client, the audio client and the IMMDevice and
      // re-acquires all three, and miniaudio's re-inits the device. The video
      // equivalent only rebuilds the capture item, which is why that one needs
      // a second, heavier tier.
      hardReacquire: null,
    );
    bindLostSubscription(recovery, addLostListenerFn);
  }

  /// The capture callback as a value, so a re-acquire can re-register it on a
  /// freshly configured context without duplicating any of it.
  void Function(MiniAVBuffer, Object?) _onAudio(Recorder rec) {
    return (MiniAVBuffer buffer, Object? _) {
      if (_stopping) {
        unawaited(MiniAV.releaseBuffer(buffer));
        return;
      }
      final audio = buffer.data;
      if (audio is! MiniAVAudioBuffer) {
        unawaited(MiniAV.releaseBuffer(buffer));
        return;
      }
      if (!_audioEpochSet) {
        // Always anchor to the master clock (rec.now() = elapsed µs since
        // _launch()).  buffer.timestampUs is an absolute QPC value measured
        // from system boot — on a machine that has been on for 59 hours it
        // would be ~212 billion µs, making the container report a 59-hour
        // duration instead of the real 12-minute recording.
        _audioEpochUs = rec.now();
        _audioEpochSet = true;
      }
      // WASAPI delivers AUDCLNT_BUFFERFLAGS_SILENT buffers during quiet
      // stretches (game muted, menus, nothing playing) with data=NULL /
      // size 0 but a non-zero frame count, surfaced here as an empty
      // `audio.data`.  Encode explicit zero-filled silence for these rather
      // than dropping them: a dropped buffer leaves a HOLE in the AAC stream,
      // so any clip whose window overlaps the quiet stretch plays back with
      // broken audio — or no audio at all when the whole window is silent and
      // the clip ends up with zero audio packets.  The mixed mic+loopback
      // path already synthesises silence this way (see _onLoopbackChunk); this
      // keeps the loopback-only / mic-only path consistent.
      final frameCount = audio.frameCount;
      if (frameCount <= 0) {
        unawaited(MiniAV.releaseBuffer(buffer));
        return;
      }
      final Uint8List pcm;
      final MiniAVAudioFormat fmt;
      if (audio.data.isEmpty) {
        pcm = _silentPcm(frameCount);
        fmt = audioFormat;
      } else {
        pcm = audio.data;
        fmt = audio.info.format;
      }
      // Apply drift correction (or snap) BEFORE computing the PTS that we
      // emit, so this chunk goes out with the corrected epoch — not the next
      // one.  This matters most for snaps: after a gap we want THIS chunk
      // aligned to wall clock so the muxer sees the discontinuity correctly.
      //
      // Snap fires ONLY for negative drift (audio behind wall clock = gap
      // recovery). Snapping on positive drift would emit a PTS smaller than
      // the previous chunk's, violating muxer monotonicity. Sustained
      // positive drift is impossible with the 20 µs/cb nudge (corrects at
      // 2 ms/s, far above the worst ppm drift).
      final wallUs = rec.now();

      // Capture-gap fill (see field docs): detect missing capture spans via
      // the native capture timestamp, NOT arrival-time drift — bursts after
      // an isolate stall are capture-contiguous and must not be filled.
      final captureUs = buffer.timestampUs;
      if (captureUs > 0) {
        if (_captureTsValid) {
          final gapUs = captureUs - _expectedCaptureUs;
          if (gapUs > _captureGapThresholdUs) {
            final fillUs = gapUs > _maxGapFillUs ? _maxGapFillUs : gapUs;
            final gapFrames = fillUs * sampleRate ~/ 1000000;
            if (gapFrames > 0) {
              Recorder._log(
                '$label capture gap ${gapUs ~/ 1000} ms — '
                'filling ${fillUs ~/ 1000} ms with silence',
                RecorderLogLevel.info,
              );
              _emitSilenceFrames(rec, gapFrames);
            }
          }
        }
        _expectedCaptureUs = captureUs + frameCount * 1000000 ~/ sampleRate;
        _captureTsValid = true;
      } else {
        // No capture timestamps on this platform — fall back to wall-clock
        // deficit fill (cannot distinguish bursts; conservative threshold).
        final deficit =
            wallUs - (_audioEpochUs + _samplesEmitted * 1000000 ~/ sampleRate);
        if (deficit > _wallGapFillThresholdUs) {
          final fillUs = deficit > _maxGapFillUs ? _maxGapFillUs : deficit;
          final gapFrames = fillUs * sampleRate ~/ 1000000;
          if (gapFrames > 0) _emitSilenceFrames(rec, gapFrames);
        }
      }

      final preliminaryPts =
          _audioEpochUs + _samplesEmitted * 1000000 ~/ sampleRate;
      final drift = preliminaryPts - wallUs;
      if (drift < -_driftSnapThresholdUs) {
        // Catastrophic snap: only reached when a gap exceeded _maxGapFillUs
        // (the fill covered the cap; the epoch absorbs the remainder) or
        // capture timestamps went bogus.
        _audioEpochUs = wallUs - _samplesEmitted * 1000000 ~/ sampleRate;
      } else if (drift > _driftThresholdUs) {
        _audioEpochUs -= _driftCorrectionUs;
      } else if (drift < -_driftThresholdUs) {
        _audioEpochUs += _driftCorrectionUs;
      }
      final ptsUs = _audioEpochUs + _samplesEmitted * 1000000 ~/ sampleRate;
      _samplesEmitted += frameCount;
      // Chain, never fire-and-forget: the PTS above is monotonic by
      // construction, but the muxer is indexed on ARRIVAL order, and two
      // overlapping encodes reach dispatchPacket in whatever order their
      // futures happen to settle. That is not theoretical — [_emitSilenceFrames]
      // above launches a gap fill of up to a second immediately before this
      // 10 ms chunk, so the small one can easily overtake the large one and
      // hand the muxer a decode timestamp that steps backwards by the whole
      // gap. [MixedAudioTrackRuntime] has always chained for this reason;
      // this path was the one that did not.
      _encodeChain = _encodeChain.then<void>(
        (_) => _encodeAudio(rec, pcm, fmt, frameCount, ptsUs),
      );
      final fut = _encodeChain.whenComplete(() {
        unawaited(MiniAV.releaseBuffer(buffer));
      });
      _inFlight.add(fut);
      fut.whenComplete(() => _inFlight.remove(fut));
    };
  }

  Future<void> _encodeAudio(
    Recorder rec,
    Uint8List pcm,
    MiniAVAudioFormat format,
    int frameCount,
    int ptsUs,
  ) async {
    try {
      final pkts = await encoder.encode(
        pcm: pcm,
        format: format,
        frameCount: frameCount,
        ptsUs: ptsUs,
      );
      for (final p in pkts) {
        await rec.dispatchPacket(this, p);
      }
    } catch (e, st) {
      Recorder._log('$label encode: $e\n$st', RecorderLogLevel.error);
    }
  }

  // Reusable neutral-PCM buffer used to synthesise silence (WASAPI SILENT
  // buffers and idle-gap fill). Grown on demand and only ever filled with the
  // format's silence value, never overwritten with other content — so it is
  // safe for concurrent in-flight encodes to read (they always see identical,
  // stable bytes) and a smaller request just returns an exact-length view of
  // the front. encode() consumes the PCM synchronously before its future
  // settles, so a later grow (new allocation) never disturbs a running read.
  Uint8List _silence = Uint8List(0);

  Uint8List _silentPcm(int frameCount) {
    final bytes = frameCount * channels * _bytesPerSample(audioFormat);
    if (_silence.length < bytes) {
      _silence = Uint8List(bytes);
      // u8 PCM is unsigned — its silence value is 0x80, not 0x00.  Every other
      // supported format is signed/float where zeroed bytes already encode
      // silence.
      if (audioFormat == MiniAVAudioFormat.u8) {
        _silence.fillRange(0, bytes, 128);
      }
    }
    return bytes == _silence.length
        ? _silence
        : Uint8List.view(_silence.buffer, 0, bytes);
  }

  /// Feed [totalFrames] of silence to the encoder, advancing the PTS timeline,
  /// so the encoder's cumulative sample count tracks wall clock across an idle
  /// gap. Fed in bounded chunks so a multi-second gap doesn't allocate one huge
  /// PCM buffer. encode() buffers + drains each chunk before its future
  /// settles, so these silent frames stay ordered ahead of the resuming real
  /// audio.
  void _emitSilenceFrames(Recorder rec, int totalFrames) {
    final chunkFrames = _gapFillChunkUs * sampleRate ~/ 1000000;
    var remaining = totalFrames;
    while (remaining > 0) {
      final n = remaining < chunkFrames ? remaining : chunkFrames;
      final ptsUs = _audioEpochUs + _samplesEmitted * 1000000 ~/ sampleRate;
      final pcm = _silentPcm(n);
      _encodeChain = _encodeChain.then<void>(
        (_) => _encodeAudio(rec, pcm, audioFormat, n, ptsUs),
      );
      final fut = _encodeChain;
      _inFlight.add(fut);
      fut.whenComplete(() => _inFlight.remove(fut));
      _samplesEmitted += n;
      remaining -= n;
    }
  }

  static int _bytesPerSample(MiniAVAudioFormat fmt) => switch (fmt) {
    MiniAVAudioFormat.f32 => 4,
    MiniAVAudioFormat.s32 => 4,
    MiniAVAudioFormat.s16 => 2,
    MiniAVAudioFormat.u8 => 1,
    MiniAVAudioFormat.unknown => 4,
  };

  @override
  Future<void> stopCapture() async {
    _stopping = true;
    cancelRecoveries();
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
    // Codec-private data (OpusHead, AudioSpecificConfig) when the encoder
    // exposes it. Omitting it is not merely a lost optimisation: a muxer that
    // has to synthesise the header can only derive it from rate/channels, and
    // Opus's pre-skip — the encoder's own lookahead — is not in either, so the
    // file ships PreSkip = 0 and every sample plays late by the priming.
    extraData: encoder.extraData,
  );

  @override
  FfmpegEncoderBridge? get encoderBridge {
    final p = encoder.platform;
    return p is FfmpegEncoderBridge ? p as FfmpegEncoderBridge : null;
  }

  @override
  Future<bool> repinAudioEncoderToFfmpeg(BackendContext? context) async {
    if (encoderBridge != null) return false;
    final replacement = await MiniAVTools.createAudioEncoder(
      encoderConfig,
      preference: BackendPreference.pinned(FfmpegBackend.backendName),
      context: context,
    );
    final previous = encoder;
    encoder = replacement;
    try {
      await previous.close();
    } catch (_) {}
    return true;
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

class MixedAudioTrackRuntime extends TrackRuntime {
  MixedAudioTrackRuntime({
    required super.index,
    required super.label,
    required this.encoder,
    required this.encoderConfig,
    required this.audioCodec,
    required this.micCtx,
    required this.loopCtx,
    required this.micGain,
    required this.loopGain,
    this.micChain,
    this.loopChain,
    this.masterChain,
    this.lossPolicy = CaptureLossPolicy.reacquire,
    this.reacquireLimit,
    this.reacquireMicFn,
    this.reacquireLoopFn,
  });

  /// What to do when either input's device goes away.
  final CaptureLossPolicy lossPolicy;
  final Duration? reacquireLimit;

  /// Re-configure one input onto whatever id names its device now. Separate
  /// functions because the two inputs are separate devices with separate
  /// enumerations, and only one of them is usually gone.
  final ReacquireFn? reacquireMicFn;
  final ReacquireFn? reacquireLoopFn;

  /// Not final: [repinAudioEncoderToFfmpeg] swaps it during sink construction.
  AudioEncoder encoder;

  /// The config [encoder] was opened with, kept so it can be re-opened on a
  /// different backend without re-deriving the mix format.
  final AudioEncoderConfig encoderConfig;
  final AudioCodec audioCodec;
  final MiniAudioInputContext micCtx;
  final MiniLoopbackContext loopCtx;
  final double micGain;
  final double loopGain;

  /// Optional DSP chains: [micChain]/[loopChain] run per source before the
  /// sum, [masterChain] on the summed mix before the safety clip. State
  /// (filter history, gain envelopes) lives for the whole recording.
  final AudioEffectChain? micChain;
  final AudioEffectChain? loopChain;
  final AudioEffectChain? masterChain;

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

  // Running count of output frames — also serves as the cumulative sample
  // count from which audio PTS is derived (see _onLoopbackChunk).  The
  // mixer's output rate is hardware-constant 48 kHz so sample-count → µs
  // is exact and immune to isolate-scheduling jitter.
  int _framesOut = 0;

  // Audio PTS epoch in master-clock µs, anchored on the first chunk.
  // _audioEpochSet guards first-callback initialization; using a bool rather
  // than an _audioEpochUs < 0 sentinel prevents the crystal-drift correction
  // from accidentally re-initializing the epoch if corrections drive it to a
  // slightly negative value.
  int _audioEpochUs = 0;
  bool _audioEpochSet = false;

  // Crystal-drift correction — same semantics as
  // AudioTrackRuntime._driftThresholdUs / _driftSnapThresholdUs /
  // _driftCorrectionUs.  See that field's comment for full rationale
  // (snap is a catastrophic-only fallback; capture gaps are silence-filled).
  static const int _driftThresholdUs = 10000; // 10 ms — nudge boundary
  static const int _driftSnapThresholdUs = 5000000; // 5 s — catastrophic only
  static const int _driftCorrectionUs = 20; // 20 µs nudge cap per callback

  // Capture-gap silence fill — same rationale as AudioTrackRuntime's fields
  // of the same name. This mixer is driven solely by the loopback callback,
  // so when the render endpoint goes idle (WASAPI delivers nothing) the fed
  // sample count falls behind and everything after plays early. Gaps are
  // detected on the loopback buffers' native capture timestamps — NEVER on
  // arrival drift, which cannot tell an idle gap from a delivery burst after
  // an isolate stall (bursts are capture-contiguous; filling them corrupts
  // the timeline).
  static const int _captureGapThresholdUs = 30000; // 3 lost 10 ms packets
  static const int _maxGapFillUs = 60000000; // 60 s
  static const int _gapFillChunkUs = 1000000; // 1 s
  static const int _wallGapFillThresholdUs = 100000; // no-timestamp fallback

  // Projected capture timestamp of the next loopback buffer's first sample.
  int _expectedCaptureUs = 0;
  bool _captureTsValid = false;

  bool _stopping = false;
  bool _firstChunkSent = false;

  // Sequential encode chain — chunks are always processed in arrival order.
  // Using a chain of futures guarantees that no 10 ms window is ever
  // silently discarded.
  Future<void> _encodeChain = Future<void>.value();

  // Counters for silent-drop diagnostics, logged at most every 5 s.
  int _micBacklogDrops = 0;
  int _lastMicBacklogLogMs = 0;
  static const int _mixDropLogIntervalMs = 5000;

  // Reusable scratch buffer — sized to the largest loopback chunk we've
  // seen so we don't allocate a Float32List per callback.
  Float32List _scratch = Float32List(0);

  // Pool of PCM byte buffers recycled across loopback chunks (~100/s). A buffer
  // is checked out at enqueue (see [_acquirePcm]) and returned by [_encodeMix]
  // once the encoder has consumed it. Capped so a stalled encode chain can't
  // grow it unbounded; over the cap, extra buffers are simply left to the GC.
  final List<Uint8List> _pcmPool = [];
  static const int _pcmPoolMax = 8;

  Uint8List _acquirePcm(int bytes) {
    for (var i = _pcmPool.length - 1; i >= 0; i--) {
      if (_pcmPool[i].length == bytes) return _pcmPool.removeAt(i);
    }
    return Uint8List(bytes);
  }

  void _releasePcm(Uint8List pcm) {
    if (_pcmPool.length < _pcmPoolMax) _pcmPool.add(pcm);
  }

  @override
  bool get captureStopping => _stopping;

  @override
  Future<void> startCapture(Recorder rec) async {
    _rec = rec;
    _wallClock = Stopwatch()..start();
    _lastMicSamplesMs = _wallClock!.elapsedMilliseconds;
    _subscribeCaptureLost(rec);
    await micCtx.startCapture(_onMic());
    await loopCtx.startCapture(_onLoopback());
  }

  /// One re-acquire loop per input. See [TrackRuntime.recoveries] for why this
  /// is a list rather than a field.
  void _subscribeCaptureLost(Recorder rec) {
    void log(String message, {bool severe = false}) => Recorder._log(
          message,
          severe ? RecorderLogLevel.error : RecorderLogLevel.warning,
        );

    final mic = CaptureRecovery(
      label: '$label mic',
      policy: lossPolicy,
      reacquireLimit: reacquireLimit,
      nowUs: rec.now,
      log: log,
      // The mic feeds a ring the loopback callback drains; nothing in flight
      // is reading the buffer that died.
      quiesce: () async {},
      restart: () => micCtx.startCapture(_onMic()),
      reacquire: reacquireMicFn,
    );

    final loop = CaptureRecovery(
      label: '$label loopback',
      policy: lossPolicy,
      reacquireLimit: reacquireLimit,
      nowUs: rec.now,
      log: log,
      quiesce: drainInFlight,
      restart: () async {
        // The new endpoint's capture timestamps do not continue the old
        // one's, and this track detects gaps on exactly those. See the same
        // reset in [AudioTrackRuntime].
        _captureTsValid = false;
        await loopCtx.startCapture(_onLoopback());
        lastPacketUs = -1;
        encodeErrorsSincePacket = 0;
      },
      reacquire: reacquireLoopFn,
    );

    bindLostSubscription(mic, micCtx.addLostListener);
    bindLostSubscription(loop, loopCtx.addLostListener);
  }

  /// Mic: convert to target f32 stereo, apply gain + effects, push to ring.
  /// Gain and effects run here (not at mix time) so the per-source DSP chain
  /// sees a contiguous post-gain mic stream.
  void Function(MiniAVBuffer, Object?) _onMic() {
    return (MiniAVBuffer buffer, Object? _) {
      try {
        if (_stopping) return;
        final audio = buffer.data;
        if (audio is! MiniAVAudioBuffer) return;
        final f32 = _toTargetF32(audio);
        if (micGain != 1.0) {
          for (var i = 0; i < f32.length; i++) {
            f32[i] *= micGain;
          }
        }
        micChain?.process(f32, f32.length);
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
    };
  }

  /// Loopback: drives encoding. Each callback delivers ~10 ms of audio at
  /// 48 kHz f32 stereo (the WASAPI default). We mix mic in-place and feed the
  /// encoder once. No timers, no extra allocations.
  void Function(MiniAVBuffer, Object?) _onLoopback() {
    return (MiniAVBuffer buffer, Object? _) {
      try {
        if (_stopping) return;
        final audio = buffer.data;
        if (audio is! MiniAVAudioBuffer) return;
        _onLoopbackChunk(audio, buffer.timestampUs);
      } finally {
        unawaited(MiniAV.releaseBuffer(buffer));
      }
    };
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
  ///
  /// [captureUs] is the buffer's native capture timestamp (QPC-derived µs,
  /// boot-relative — deltas only) used for capture-gap detection; 0 when the
  /// platform doesn't stamp capture times.
  void _onLoopbackChunk(MiniAVAudioBuffer audio, int captureUs) {
    final loopFrames = audio.frameCount;
    final loopCh = audio.info.channels;
    final loopSr = audio.info.sampleRate;
    final loopFmt = audio.info.format;

    // WASAPI sends AUDCLNT_BUFFERFLAGS_SILENT packets with data=NULL and
    // data_size_bytes=0 but a non-zero frame count.  The Dart FFI layer
    // exposes these as audio.data being an empty Uint8List.  Calling
    // asFloat32List() on an empty buffer with a positive length throws a
    // RangeError, which propagates out of the FFI callback and kills the
    // loopback capture — exactly why game audio disappears.
    // Synthesise silence: advance the PTS counter and encode a
    // zero-filled block so the timeline stays continuous.
    Float32List loopStereo;
    if (audio.data.isEmpty) {
      loopStereo = Float32List(loopFrames * _outChannels); // all zeros
    } else if (loopFmt == MiniAVAudioFormat.f32 &&
        loopCh == _outChannels &&
        loopSr == _outSampleRate) {
      // Fast path: native 48 kHz / 2ch / f32 (the Windows default).
      // Reinterpret the bytes directly — no copy, no resample.
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

    // Apply loopback gain into scratch, then the loopback DSP chain.
    if (loopGain == 1.0) {
      mix.setRange(0, outSamples, loopStereo);
      // Zero the tail if scratch is bigger than this chunk.
      for (var i = outSamples; i < mix.length; i++) mix[i] = 0;
    } else {
      for (var i = 0; i < outSamples; i++) mix[i] = loopStereo[i] * loopGain;
    }
    loopChain?.process(mix, outSamples);

    // Mix mic on top — only if recent samples have been received and the
    // ring has at least this many frames; otherwise pad with silence.
    // Mic gain + effects were already applied in the mic capture callback.
    final nowMs = _wallClock?.elapsedMilliseconds ?? 0;
    final micAlive = (nowMs - _lastMicSamplesMs) <= _silenceTimeoutMs;
    if (micAlive && _micRing.frames >= outFrames) {
      final mic = _micRing.take(outFrames);
      for (var i = 0; i < outSamples; i++) {
        mix[i] += mic[i];
      }
    } else if (micAlive) {
      // Mic is alive but ring is short (e.g. capture just started or mic
      // is running slightly slower than loopback). Take what we can.
      final avail = _micRing.frames;
      if (avail > 0) {
        final mic = _micRing.take(avail);
        final n = avail * _outChannels;
        for (var i = 0; i < n; i++) {
          mix[i] += mic[i];
        }
      }
    }

    // Master chain on the summed mix (e.g. a limiter), then the hard clip
    // below stays as a last-resort safety net.
    masterChain?.process(mix, outSamples);

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
    // callback. Copy is `outSamples * 4` bytes — ~4 KB for 10 ms. The byte
    // buffer is drawn from a small pool and returned by [_encodeMix], and the
    // copy uses setRange (no intermediate sublist allocation).
    final pcm = _acquirePcm(outSamples * 4);
    pcm.buffer.asFloat32List(0, outSamples).setRange(0, outSamples, mix);

    // PTS is anchored to the master clock on the first chunk and then
    // advanced by cumulative output sample count.  See AudioTrackRuntime
    // for why wall-clock PTS per callback produces crackly playback when
    // the isolate is briefly blocked.  The mixer's output rate is a
    // hardware-constant 48 kHz so the sample-count → µs conversion is
    // exact.
    if (!_audioEpochSet) {
      _audioEpochUs = _rec?.now() ?? 0;
      _audioEpochSet = true;
    }
    // Apply drift correction BEFORE computing the PTS so this chunk goes out
    // with the corrected epoch.  Snap fires ONLY for negative drift (audio
    // behind wall clock) — the gap-recovery case (loopback silent with no
    // callbacks, app minimised, audio device sleep, isolate stall ≥ 100 ms).
    // Snapping on positive drift would emit a PTS smaller than the previous
    // chunk's and the muxer would reject it.
    final wallUs = _rec?.now() ?? 0;

    // Capture-gap fill (see field docs): detect missing capture spans via the
    // loopback buffer's native capture timestamp, NOT arrival drift — bursts
    // after an isolate stall are capture-contiguous and must not be filled.
    if (captureUs > 0) {
      if (_captureTsValid) {
        final gapUs = captureUs - _expectedCaptureUs;
        if (gapUs > _captureGapThresholdUs) {
          final fillUs = gapUs > _maxGapFillUs ? _maxGapFillUs : gapUs;
          final gapFrames = fillUs * _outSampleRate ~/ 1000000;
          if (gapFrames > 0) {
            Recorder._log(
              '$label capture gap ${gapUs ~/ 1000} ms — '
              'filling ${fillUs ~/ 1000} ms with silence',
              RecorderLogLevel.info,
            );
            _emitSilenceFrames(gapFrames);
          }
        }
      }
      // Project the next buffer's capture time from THIS buffer's own frame
      // count at its SOURCE rate (the mixer may resample to 48 kHz).
      final srcRate = loopSr > 0 ? loopSr : _outSampleRate;
      _expectedCaptureUs = captureUs + loopFrames * 1000000 ~/ srcRate;
      _captureTsValid = true;
    } else {
      // No capture timestamps on this platform — fall back to wall-clock
      // deficit fill (cannot distinguish bursts; conservative threshold).
      final deficit =
          wallUs - (_audioEpochUs + _framesOut * 1000000 ~/ _outSampleRate);
      if (deficit > _wallGapFillThresholdUs) {
        final fillUs = deficit > _maxGapFillUs ? _maxGapFillUs : deficit;
        final gapFrames = fillUs * _outSampleRate ~/ 1000000;
        if (gapFrames > 0) _emitSilenceFrames(gapFrames);
      }
    }

    final preliminaryPts =
        _audioEpochUs + _framesOut * 1000000 ~/ _outSampleRate;
    final drift = preliminaryPts - wallUs;
    if (drift < -_driftSnapThresholdUs) {
      _audioEpochUs = wallUs - _framesOut * 1000000 ~/ _outSampleRate;
    } else if (drift > _driftThresholdUs) {
      _audioEpochUs -= _driftCorrectionUs;
    } else if (drift < -_driftThresholdUs) {
      _audioEpochUs += _driftCorrectionUs;
    }
    final ptsUs = _audioEpochUs + _framesOut * 1000000 ~/ _outSampleRate;
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

  Future<void> _encodeMix(
    Uint8List pcm,
    int frameCount,
    int ptsUs, {
    bool recycle = true,
  }) async {
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
    } finally {
      // The encoder has consumed `pcm` by the time encode() returned; recycle
      // pool-drawn hot-path buffers. Idle-gap silence buffers are allocated
      // fresh (recycle: false) so their large 1 s size never evicts the small
      // per-callback buffers the pool exists to recycle.
      if (recycle) _releasePcm(pcm);
    }
  }

  /// Append [totalFrames] of gap fill to the encode chain, advancing
  /// _framesOut, so the encoder's cumulative sample count tracks capture time
  /// across a span where the loopback callback stopped firing. Fed in bounded
  /// chunks with freshly-allocated PCM (kept out of the recycling pool — see
  /// [_encodeMix]) so a multi-second gap can't grow one huge buffer.
  ///
  /// The mic kept capturing during the gap, so its audio for that span is
  /// sitting in [_micRing] (bounded to the most recent ~1 s by the backlog
  /// cap). Mix it into the TAIL of the fill — that is where it belongs on the
  /// timeline — instead of leaving it queued, which would delay every
  /// post-gap mic sample by the backlog length for the rest of the session.
  void _emitSilenceFrames(int totalFrames) {
    final ringFrames = _micRing.frames < totalFrames
        ? _micRing.frames
        : totalFrames;
    final leadZeros = totalFrames - ringFrames;
    final chunkFrames = _gapFillChunkUs * _outSampleRate ~/ 1000000;
    var pos = 0;
    while (pos < totalFrames) {
      final remaining = totalFrames - pos;
      final n = remaining < chunkFrames ? remaining : chunkFrames;
      final pcm = Uint8List(n * _outChannels * 4); // f32 zeros = silence
      // Portion of this chunk overlapping the mic-backed tail region
      // [leadZeros, totalFrames).
      final overlapStart = pos > leadZeros ? pos : leadZeros;
      final overlapEnd = pos + n;
      if (overlapStart < overlapEnd) {
        final mic = _micRing.take(overlapEnd - overlapStart);
        final f32 = pcm.buffer.asFloat32List(0, n * _outChannels);
        final base = (overlapStart - pos) * _outChannels;
        for (var i = 0; i < mic.length; i++) {
          var s = mic[i];
          if (s > 1.0) s = 1.0;
          if (s < -1.0) s = -1.0;
          f32[base + i] = s;
        }
      }
      final ptsUs = _audioEpochUs + _framesOut * 1000000 ~/ _outSampleRate;
      _encodeChain = _encodeChain.then<void>(
        (_) => _encodeMix(pcm, n, ptsUs, recycle: false),
      );
      _framesOut += n;
      pos += n;
    }
  }

  @override
  Future<void> stopCapture() async {
    _stopping = true;
    cancelRecoveries();
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
    // See AudioTrackRuntime.toTrackInfo: without this the muxer synthesises a
    // header, and a synthesised OpusHead carries PreSkip = 0.
    extraData: encoder.extraData,
  );

  @override
  FfmpegEncoderBridge? get encoderBridge {
    final p = encoder.platform;
    return p is FfmpegEncoderBridge ? p as FfmpegEncoderBridge : null;
  }

  @override
  Future<bool> repinAudioEncoderToFfmpeg(BackendContext? context) async {
    if (encoderBridge != null) return false;
    final replacement = await MiniAVTools.createAudioEncoder(
      encoderConfig,
      preference: BackendPreference.pinned(FfmpegBackend.backendName),
      context: context,
    );
    final previous = encoder;
    encoder = replacement;
    try {
      await previous.close();
    } catch (_) {}
    return true;
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
  int get frames => _totalSamples ~/ MixedAudioTrackRuntime._outChannels;

  void add(Float32List samples) {
    if (samples.isEmpty) return;
    _chunks.add(samples);
    _totalSamples += samples.length;
  }

  /// Remove [frames] frames and return them as interleaved stereo f32.
  Float32List take(int frames) {
    final wanted = frames * MixedAudioTrackRuntime._outChannels;
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
  _FileSinkRuntime({required this.muxer, required this.path})
    : _muxQueue = BoundedWriteQueue<EncodedPacket>(
        muxer.writePacket,
        maxDepth: 64,
        onError: (e, _, pkt) => Recorder._log(
          'mux write track=${pkt.trackIndex}: $e',
          RecorderLogLevel.error,
        ),
      );
  /// The container writer, which may be running on a worker. The sink does
  /// not care which backend writes the container -- it only needs
  /// writePacket/finish/close -- and typing it concretely was what forced the
  /// FFmpeg muxer on paths the first-party writer handles better.
  final MuxSink muxer;
  final String path;

  // Decoupled mux-write queue: [enqueuePacket] chains each encoded packet onto
  // a serial future and (in the common case) returns WITHOUT awaiting the libav
  // write, so the per-frame encode gate is no longer inflated by muxing —
  // video+audio muxing now overlaps the next encode instead of blocking it.
  // FIFO preserves per-track packet order (libav's interleaved writer handles
  // cross-track ordering by DTS); a sustained backlog applies back-pressure
  // rather than dropping already-encoded data.
  final BoundedWriteQueue<EncodedPacket> _muxQueue;

  /// Chains [packet] onto the async mux-write queue. Returns immediately unless
  /// the queue is full, in which case it awaits until a write frees space.
  Future<void> enqueuePacket(EncodedPacket packet) => _muxQueue.add(packet);

  @override
  Future<void> finish() async {
    // Drain every queued packet to the muxer BEFORE writing the trailer.
    await _muxQueue.drain();
    _report(await muxer.finish());
  }

  /// Say so when the container had to repair this recording's decode order.
  ///
  /// The muxer rescues the file either way, which is the right call — but a
  /// rescued file means a PRODUCER handed packets over out of order, and that
  /// bug is invisible from the output. Without this line the only symptom is a
  /// few frames of skew somewhere in a multi-gigabyte file, which nobody will
  /// ever trace back. With it, the session that did it says so at stop.
  void _report(MuxFinishReport report) {
    for (final index in report.tracksMissingConfig) {
      Recorder._log(
        'track $index in $path was never given a codec configuration record — '
        'its samples are all in the file but it has no sample entry, so it '
        'will not decode. Every other track is sound; the media is '
        'recoverable from mdat.',
        RecorderLogLevel.error,
      );
    }
    for (final r in report.timingRepairs) {
      Recorder._log(
        'mux timing repaired in $path — $r',
        RecorderLogLevel.warning,
      );
    }
  }

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
