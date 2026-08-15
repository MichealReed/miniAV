/// The user-facing player facade.
///
/// Packet-driven by design: the transport (WebTransport, QUIC, WebSocket,
/// an in-process recorder loopback, a future demuxer) owns the network; the
/// player owns decode → GPU convert → present → audio out → a/v pacing.
///
/// ```dart
/// final player = await MiniavPlayer.open(
///   video: VideoStreamSpec(
///     config: DecoderConfig(codec: VideoCodec.h264),
///   ),
///   audio: AudioStreamSpec(
///     config: AudioDecoderConfig(codec: AudioCodec.aac, extraData: asc),
///   ),
/// );
/// // In the widget tree:
/// //   MiniavPlayerView(player: player)
/// transport.onVideoPacket = player.submitVideoPacket;
/// transport.onAudioPacket = player.submitAudioPacket;
/// ```
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show kIsWeb, ValueListenable, visibleForTesting;
import 'package:miniav_tools/miniav_tools.dart';
import 'package:minigpu/minigpu.dart';
import 'package:minigpu_view/minigpu_view.dart';

// Platform-selected codec backend registration: FFmpeg on native (dart:ffi),
// WebCodecs on web (dart:js_interop). Keeps each platform's native-only
// imports out of the other's compilation.
import 'backend_register_native.dart'
    if (dart.library.js_interop) 'backend_register_web.dart';
// Platform-selected web VideoFrame → PreviewSource helper (web-only body).
import 'web_present_stub.dart'
    if (dart.library.js_interop) 'web_present.dart';
import 'worker_audio_stub.dart'
    if (dart.library.js_interop) 'worker_audio_web.dart';

import 'audio_output.dart';
import 'media_source.dart';
// Web MSE fallback (browser <video>) — real on web, unsupported stub on native.
import 'mse/mp4_init_scan.dart';
import 'mse/mse_controller_stub.dart'
    if (dart.library.js_interop) 'mse/mse_controller.dart';
import 'mse/mse_support_stub.dart'
    if (dart.library.js_interop) 'mse/mse_support.dart';
import 'player_clock.dart';
import 'player_config.dart';
import 'video_presenter.dart';
import 'video_scheduler.dart';

class MiniavPlayer {
  MiniavPlayer._({
    required PlayerClock clock,
    required this.latencyMode,
    required this.maxPendingVideoPackets,
    required BackendPreference preference,
    VideoStreamSpec? videoSpec,
    AudioStreamSpec? audioSpec,
    Decoder? videoDecoder,
    AudioDecoder? audioDecoder,
    Minigpu? gpu,
    required bool ownsGpu,
    MinigpuPreviewController? controller,
    required bool ownsController,
    VideoFramePresenter? presenter,
    PlayerAudioOutput? audioOutput,
    void Function(Object error, StackTrace stack)? onError,
  }) : _clock = clock,
       _preference = preference,
       _videoSpec = videoSpec,
       _audioSpec = audioSpec,
       _videoDecoder = videoDecoder,
       _audioDecoder = audioDecoder,
       _gpu = gpu,
       _ownsGpu = ownsGpu,
       _controller = controller,
       _ownsController = ownsController,
       _presenter = presenter,
       _audioOut = audioOutput,
       _onError = onError {
    // Build the present scheduler whenever there is a video track. The
    // present step branches by payload: native frames carry YUV420P bytes
    // (GPU-converted by the presenter); web frames carry a browser VideoFrame
    // presented directly. Payload release is owned by the scheduler.
    final controllerRef = _controller;
    if (_videoDecoder != null && controllerRef != null) {
      final presenterRef = _presenter; // null on web
      _scheduler = VideoScheduler(
        mode: latencyMode,
        clock: _clock,
        present: (f) async {
          final webFrame = f.webFrame;
          final d3d11 = f.d3d11SharedHandle;
          if (webFrame != null) {
            await controllerRef.present(
              makeWebVideoFramePreviewSource(webFrame, f.width, f.height),
            );
          } else if (d3d11 != null) {
            // Hardware path: import the shared NV12 texture + GPU NV12→RGBA.
            await presenterRef!.presentD3D11Nv12(d3d11, f.width, f.height);
          } else {
            await presenterRef!.presentYuv420p(
              f.yuv420p!,
              f.width,
              f.height,
              layout: f.yuvLayout,
              fullRange: f.yuvFullRange,
              matrix: f.yuvMatrix,
            );
          }
          if (!_firstFrame.isCompleted) _firstFrame.complete();
        },
        onPresentError: (e, s) {
          presentErrorCount++;
          _onError?.call(e, s);
        },
      );
    }
  }

  /// Open a player. At least one of [video] / [audio] is required.
  ///
  /// [gpu] — pass an app-owned (already `init()`ed) Minigpu to share one
  /// Dawn context (and to control `Minigpu.preferDisplayAdapter`, which must
  /// be called before ANY minigpu init); omitted → the player creates and
  /// owns one.
  ///
  /// [controller] — pass an existing [MinigpuPreviewController] to bind the
  /// player to a preview widget you already manage; omitted → the player
  /// creates one (see [previewController] / `MiniavPlayerView`).
  static Future<MiniavPlayer> open({
    VideoStreamSpec? video,
    AudioStreamSpec? audio,
    PlayerLatencyMode latency = PlayerLatencyMode.live,
    Minigpu? gpu,
    MinigpuPreviewController? controller,
    BackendPreference preference = BackendPreference.auto,
    int maxPendingVideoPackets = 4,
    void Function(Object error, StackTrace stack)? onError,
  }) async {
    if (video == null && audio == null) {
      throw ArgumentError('MiniavPlayer.open: need a video or audio spec');
    }
    registerPlayerBackends();

    Decoder? videoDecoder;
    AudioDecoder? audioDecoder;
    Minigpu? gpuRef = gpu;
    var ownsGpu = false;
    MinigpuPreviewController? controllerRef = controller;
    var ownsController = false;
    VideoFramePresenter? presenter;
    PlayerAudioOutput? audioOut;

    try {
      if (video != null) {
        videoDecoder = await MiniAVTools.createDecoder(
          video.config,
          preference: preference,
        );
        if (controllerRef == null) {
          controllerRef = MinigpuPreviewController();
          ownsController = true;
        }
        // Web decodes to a display-ready VideoFrame presented directly — no
        // minigpu compute context, no YUV→RGBA presenter. Native needs both.
        if (!kIsWeb) {
          if (gpuRef == null) {
            gpuRef = Minigpu();
            await gpuRef.init();
            ownsGpu = true;
          }
          presenter = VideoFramePresenter(gpuRef, controllerRef);
        }
      }
      if (audio != null) {
        audioDecoder = await MiniAVTools.createAudioDecoder(
          audio.config,
          preference: preference,
        );
        audioOut = PlayerAudioOutput(bufferMs: audio.bufferMs);
      }
    } catch (_) {
      await videoDecoder?.close();
      await audioDecoder?.close();
      presenter?.dispose();
      if (ownsController) await controllerRef?.dispose();
      if (ownsGpu) await gpuRef?.destroy();
      rethrow;
    }

    return MiniavPlayer._(
      clock: PlayerClock(),
      latencyMode: latency,
      maxPendingVideoPackets: maxPendingVideoPackets,
      preference: preference,
      videoSpec: video,
      audioSpec: audio,
      videoDecoder: videoDecoder,
      audioDecoder: audioDecoder,
      gpu: gpuRef,
      ownsGpu: ownsGpu,
      controller: controllerRef,
      ownsController: ownsController,
      presenter: presenter,
      audioOutput: audioOut,
      onError: onError,
    );
  }

  /// Open a player driven by a container [source] (file / bytes / live byte
  /// stream): tracks are probed, decoders auto-configured from the container
  /// (codec + avcC/ASC extradata), and an internal demux pump feeds the
  /// pipeline with decode-ahead backpressure.
  ///
  /// Defaults to [PlayerLatencyMode.paced] (pts-clocked playback — the right
  /// mode for files/VOD); pass [PlayerLatencyMode.live] for realtime feeds.
  /// Seek/position/duration are available for seekable sources.
  ///
  /// ```dart
  /// final player = await MiniavPlayer.openSource(
  ///   MediaSource.file('movie.mp4'),
  /// );
  /// // or: MediaSource.byteStream(httpResponseStream) for live fMP4
  /// await player.onFirstFrame;
  /// ```
  static Future<MiniavPlayer> openSource(
    MediaSource source, {
    PlayerLatencyMode latency = PlayerLatencyMode.paced,
    bool enableVideo = true,
    bool enableAudio = true,
    Minigpu? gpu,
    MinigpuPreviewController? controller,
    BackendPreference preference = BackendPreference.auto,
    void Function(Object error, StackTrace stack)? onError,
  }) async {
    registerPlayerBackends();

    // Web fallback: when the browser has no WebCodecs video decoder, hand the
    // whole container to a `<video>` element via MSE and let the browser do
    // everything. `mseFallbackRecommended()` is always false off-web, so this
    // branch is web-only. Video is required to justify the fallback.
    if (enableVideo && mseFallbackRecommended()) {
      return _openMse(
        source,
        latency: latency,
        enableAudio: enableAudio,
        preference: preference,
        onError: onError,
      );
    }

    final demuxer = await MiniAVTools.createDemuxer(
      DemuxerConfig(input: source.toDemuxerInput()),
      preference: preference,
    );

    var videoTrack = -1;
    var audioTrack = -1;
    VideoTrackInfo? videoInfo;
    AudioTrackInfo? audioInfo;
    for (var i = 0; i < demuxer.tracks.length; i++) {
      final t = demuxer.tracks[i];
      if (enableVideo && videoInfo == null && t is VideoTrackInfo) {
        videoInfo = t;
        videoTrack = i;
      } else if (enableAudio && audioInfo == null && t is AudioTrackInfo) {
        audioInfo = t;
        audioTrack = i;
      }
    }
    if (videoInfo == null && audioInfo == null) {
      await demuxer.close();
      throw StateError(
        'MiniavPlayer.openSource: no playable tracks '
        '(container tracks: ${demuxer.tracks})',
      );
    }

    final MiniavPlayer player;
    try {
      player = await open(
        video: videoInfo != null
            ? VideoStreamSpec(
                config: DecoderConfig(
                  codec: videoInfo.codec,
                  extraData: videoInfo.extraData?.bytes,
                  // The container's coded dims are not a hint for every
                  // decoder: the MF HEVC decoder MFT rejects input until its
                  // input media type carries a frame size, so dropping these
                  // opens a session that can never produce a frame.
                  width: videoInfo.width > 0 ? videoInfo.width : null,
                  height: videoInfo.height > 0 ? videoInfo.height : null,
                ),
              )
            : null,
        audio: audioInfo != null
            ? AudioStreamSpec(
                config: AudioDecoderConfig(
                  codec: audioInfo.codec,
                  extraData: audioInfo.extraData?.bytes,
                  sampleRate: audioInfo.sampleRate > 0
                      ? audioInfo.sampleRate
                      : null,
                  channels: audioInfo.channels > 0 ? audioInfo.channels : null,
                ),
              )
            : null,
        latency: latency,
        gpu: gpu,
        controller: controller,
        preference: preference,
        onError: onError,
      );
    } catch (_) {
      await demuxer.close();
      rethrow;
    }
    player._demuxer = demuxer;
    player._srcVideoTrack = videoTrack;
    player._srcAudioTrack = audioTrack;
    player._rotationDegrees = videoInfo?.rotationDegrees ?? 0;
    await player._tryWorkerAudio(source, audioInfo);
    player._pumpSource();
    return player;
  }

  /// Web MSE fallback for [openSource]: no demuxer/decoder/GPU pipeline — the
  /// browser plays the container itself. Whole in-memory containers go through
  /// a progressive Blob URL. Byte streams are probed (bounded by
  /// [ByteStreamMediaSource.bufferBytes]): fragmented MP4 (`mvex` in `moov`)
  /// streams LIVE through MSE per-segment appends; a plain progressive MP4 is
  /// collected to end-of-stream (cap-enforced — never an unbounded hang) and
  /// played as a Blob.
  static Future<MiniavPlayer> _openMse(
    MediaSource source, {
    required PlayerLatencyMode latency,
    required bool enableAudio,
    required BackendPreference preference,
    void Function(Object error, StackTrace stack)? onError,
  }) async {
    if (source is BytesMediaSource) {
      final mime = blobMimeForBytes(source.bytes) ?? 'video/mp4';
      return _mseFromController(
        MseController.blob(source.bytes, mimeType: mime),
        enableAudio: enableAudio,
        latency: latency,
        preference: preference,
        onError: onError,
      );
    }
    if (source is ByteStreamMediaSource) {
      return _openMseStream(
        source,
        enableAudio: enableAudio,
        latency: latency,
        preference: preference,
        onError: onError,
      );
    }
    // FileMediaSource is native-only; this path is web-only, so it can't occur.
    throw UnsupportedError(
      'MSE fallback needs an in-memory or streamed container, not a file',
    );
  }

  /// Probe a container byte stream, then either stream it via MSE (fMP4) or
  /// collect-and-blob it (plain MP4 / unknown). Bounded by
  /// [ByteStreamMediaSource.bufferBytes] in BOTH phases so a live stream can
  /// never hang [openSource] forever or grow memory without limit.
  static Future<MiniavPlayer> _openMseStream(
    ByteStreamMediaSource source, {
    required PlayerLatencyMode latency,
    required bool enableAudio,
    required BackendPreference preference,
    void Function(Object error, StackTrace stack)? onError,
  }) async {
    final cap = source.bufferBytes;
    final probe = Mp4InitProbe();
    final probed = Completer<void>();
    var streamDone = false;

    late final StreamSubscription<List<int>> sub;
    sub = source.stream.listen(
      (chunk) {
        if (probed.isCompleted) return;
        probe.add(chunk);
        if (probe.moovComplete || probe.isIsoBmff == false) {
          sub.pause();
          probed.complete();
        } else if (probe.bufferedLength > cap) {
          sub.pause();
          probed.completeError(StateError(
            'MSE fallback: no complete MP4 init segment within bufferBytes '
            '(${probe.bufferedLength} > $cap). For live streams use '
            'fragmented MP4, or raise ByteStreamMediaSource.bufferBytes.',
          ));
        }
      },
      onError: (Object e) {
        if (!probed.isCompleted) probed.completeError(e);
      },
      onDone: () {
        streamDone = true;
        if (!probed.isCompleted) probed.complete();
      },
    );
    try {
      await probed.future;
    } catch (_) {
      await sub.cancel();
      rethrow;
    }

    final mime = probe.mimeCodecs;
    if (probe.moovComplete &&
        probe.fragmented &&
        mime != null &&
        MseController.isTypeSupported(mime)) {
      // fMP4 → true MSE streaming: append the buffered prefix, then feed each
      // chunk as it arrives. Works for LIVE streams (no end required).
      final mse = MseController.stream(mimeWithCodecs: mime);
      unawaited(mse.onReady.then((_) {
        unawaited(mse.appendBytes(probe.bufferedBytes));
      }).catchError((Object _) {
        // addSourceBuffer failure already surfaced via mse.onError.
      }));
      if (streamDone) {
        mse.endOfStream();
        await sub.cancel();
      } else {
        sub
          ..onData((chunk) => unawaited(
              mse.appendBytes(Uint8List.fromList(chunk))))
          ..onError((Object e) {
            unawaited(sub.cancel());
            mse.endOfStream();
          })
          ..onDone(mse.endOfStream)
          ..resume();
      }
      return _mseFromController(
        mse,
        enableAudio: enableAudio,
        latency: latency,
        preference: preference,
        onError: onError,
        onClose: () => unawaited(sub.cancel()),
      );
    }

    // Plain/progressive container: need the WHOLE file for a Blob. Keep
    // collecting to end-of-stream under the cap (cap → clear error, not a hang).
    if (!streamDone) {
      final collected = Completer<void>();
      sub
        ..onData((chunk) {
          probe.add(chunk);
          if (probe.bufferedLength > cap && !collected.isCompleted) {
            collected.completeError(StateError(
              'MSE fallback: container exceeded bufferBytes '
              '(${probe.bufferedLength} > $cap) while buffering for '
              'progressive playback. Live playback needs fragmented MP4.',
            ));
          }
        })
        ..onError((Object e) {
          if (!collected.isCompleted) collected.completeError(e);
        })
        ..onDone(() {
          if (!collected.isCompleted) collected.complete();
        })
        ..resume();
      try {
        await collected.future;
      } finally {
        await sub.cancel();
      }
    } else {
      await sub.cancel();
    }
    final bytes = probe.bufferedBytes;
    final mimeType = blobMimeForBytes(bytes) ?? 'video/mp4';
    return _mseFromController(
      MseController.blob(bytes, mimeType: mimeType),
      enableAudio: enableAudio,
      latency: latency,
      preference: preference,
      onError: onError,
    );
  }

  /// Wire an [MseController] into a player shell: real first-frame signal
  /// ('loadeddata', not just source-ready), error surfacing to [onError], and
  /// ended propagation.
  static MiniavPlayer _mseFromController(
    MseController mse, {
    required PlayerLatencyMode latency,
    required bool enableAudio,
    required BackendPreference preference,
    void Function(Object error, StackTrace stack)? onError,
    void Function()? onClose,
  }) {
    mse.muted = !enableAudio;
    final player = MiniavPlayer._(
      clock: PlayerClock(),
      latencyMode: latency,
      maxPendingVideoPackets: 4,
      preference: preference,
      ownsGpu: false,
      ownsController: false,
      onError: onError,
    );
    player._mse = mse;
    player._mseOnClose = onClose;
    mse.onFirstFrame.then((_) {
      if (!player._firstFrame.isCompleted) player._firstFrame.complete();
    }).catchError((Object e) {
      if (!player._firstFrame.isCompleted) player._firstFrame.completeError(e);
    });
    mse.onError.listen((e) {
      player.sourceErrorCount++;
      player._onError?.call(e, StackTrace.current);
    });
    mse.onEnded.listen((_) {
      if (!player._ended.isCompleted) player._ended.complete();
    });
    // Muted autoplay is universally allowed; un-muted may be rejected until a
    // user gesture — surfaced via onError, recoverable via resume().
    unawaited(mse.onReady.then((_) => mse.play()).catchError((Object e) {
      if (!player._firstFrame.isCompleted) player._firstFrame.completeError(e);
      return false;
    }));
    return player;
  }

  final PlayerLatencyMode latencyMode;

  /// Bound on undecoded video packets. Overflow = network outran decode:
  /// the backlog is dumped and decoding resumes at the next keyframe
  /// (standard live catch-up; the transport can watch
  /// [PlayerStats.videoPacketsDropped] to request one).
  final int maxPendingVideoPackets;

  final PlayerClock _clock;
  final BackendPreference _preference;
  final VideoStreamSpec? _videoSpec;
  final AudioStreamSpec? _audioSpec;

  /// Mutable: recreated on [seek] (libav decoders keep reference state that
  /// a container-level seek invalidates).
  Decoder? _videoDecoder;
  AudioDecoder? _audioDecoder;
  final Minigpu? _gpu;
  final bool _ownsGpu;
  final MinigpuPreviewController? _controller;
  final bool _ownsController;
  final VideoFramePresenter? _presenter;
  final PlayerAudioOutput? _audioOut;
  final void Function(Object, StackTrace)? _onError;
  VideoScheduler? _scheduler;

  /// Set only on the web MSE fallback path (no WebCodecs): the browser `<video>`
  /// demuxes+decodes+renders+plays audio, and the transport controls proxy here.
  /// Null on the normal WebCodecs/native decode path.
  MseController? _mse;

  /// True when this player is running the browser-native MSE `<video>` fallback
  /// ([MiniavPlayerView] renders its element instead of the GPU texture).
  bool get usingMse => _mse != null;

  int _rotationDegrees = 0;

  /// Container-declared display rotation (degrees clockwise: 0/90/180/270,
  /// from the MP4 tkhd matrix). Set by [openSource]; 0 for packet-driven
  /// playback. [MiniavPlayerView] applies it automatically; apps that present
  /// via their own [previewController] widget must apply it themselves. The
  /// MSE fallback ignores it (the browser honors the matrix natively).
  int get rotationDegrees => _rotationDegrees;

  /// The MSE controller when [usingMse]; null otherwise. Exposed so the view can
  /// host its `<video>` element.
  MseController? get mseController => _mse;

  /// Extra teardown for the MSE path (cancels the feeding stream subscription).
  void Function()? _mseOnClose;

  final List<EncodedPacket> _videoQueue = [];
  bool _videoPumping = false;
  bool _waitingForKeyframe = false;

  final List<EncodedPacket> _audioQueue = [];
  bool _audioPumping = false;

  /// Set when audio is running entirely off the main thread: a worker demuxes
  /// and decodes into shared memory and an AudioWorklet plays it on the audio
  /// thread (web + shared memory only; see [WorkerAudioTrack]).
  ///
  /// When this is set the player runs NO audio pump: `_audioQueue`,
  /// `_audioDecoder` and `_audioOut` are all unused, source packets for the
  /// audio track are not routed, and the media clock is re-anchored from what
  /// the audio device has actually played rather than from what was written.
  WorkerAudioTrack? _workerAudio;
  Timer? _workerAudioClock;

  /// True when audio plays without the main thread being involved at all.
  /// [PlayerStats.audioUnderruns] is then the number that matters.
  bool get usingWorkerAudio => _workerAudio != null;

  // --- source-driven playback (openSource) -----------------------------------
  Demuxer? _demuxer;
  int _srcVideoTrack = -1;
  int _srcAudioTrack = -1;
  bool _sourcePumping = false;
  bool _sourceEof = false;
  bool _seeking = false;
  final Completer<void> _ended = Completer<void>();

  /// Seek preroll: decoded output earlier than this is discarded (frames
  /// between the landing keyframe and the seek target).
  int? _dropVideoBeforeUs;
  int? _dropAudioBeforeUs;

  /// Decode-ahead bounds for the source pump (packets, per track).
  static const int _kSourceVideoAhead = 4;
  static const int _kSourceAudioAhead = 8;

  final Completer<void> _firstFrame = Completer<void>();
  bool _closed = false;
  bool _paused = false;

  /// Test observable for decoded audio, invoked for every chunk the audio
  /// decoder yields BEFORE it reaches the output sink. Static because
  /// [openSource] starts pumping before it returns a player to assign to.
  ///
  /// The sink's counters ([PlayerStats.audioFramesWritten]) cannot stand in
  /// for this: they stay 0 on a machine with no audio output device, and they
  /// cannot distinguish real PCM from silence — which is exactly what a
  /// backend that wins negotiation for a codec it cannot decode produces.
  @visibleForTesting
  static void Function(DecodedAudio chunk)? debugOnDecodedAudio;

  // --- stats -----------------------------------------------------------------
  int videoPacketsSubmitted = 0;
  int videoPacketsDropped = 0;
  int videoFramesDecoded = 0;
  int videoDecodeErrorCount = 0;
  int audioPacketsSubmitted = 0;
  int audioDecodeErrorCount = 0;
  int presentErrorCount = 0;

  /// Source-driven playback: demuxer/transport read failures.
  int sourceErrorCount = 0;
  double _lastDecodeMs = 0;

  /// The controller to hand to a `MiniavGpuPreview` / `MiniavPlayerView`.
  MinigpuPreviewController? get previewController => _controller;

  /// True when the platform/adapter has no zero-copy present and the player has
  /// fallen back to CPU YUV→RGBA (frames published via [videoFallbackImage]).
  /// Determined lazily on the first video frame; false on web / audio-only /
  /// zero-copy platforms.
  bool get usingCpuFallback => _presenter?.usingCpuFallback ?? false;

  /// In [usingCpuFallback] mode, the latest decoded frame as a `ui.Image` for a
  /// `RawImage` to paint (`MiniavPlayerView` does this automatically). Null when
  /// there is no CPU-fallback presenter (web / audio-only / zero-copy path).
  ValueListenable<ui.Image?>? get videoFallbackImage => _presenter?.fallbackImage;

  /// The backend name of the active video decoder — e.g. `'mf_decode'` for the
  /// Media Foundation hardware D3D11 path, `'ffmpeg'` for software. Null when
  /// there is no video track. Useful for diagnostics / HUDs.
  String? get videoDecoderBackend => _videoDecoder?.backendName;

  /// The backend name of the active audio decoder (e.g. `'ffmpeg'` for
  /// libopus/AAC), or null when there is no audio track.
  String? get audioDecoderBackend => _audioDecoder?.backendName;

  /// The config the video decoder was negotiated and opened with — for
  /// [openSource] this is what the container's track description compiled to
  /// (codec, extradata, coded dims). Null when there is no video track.
  ///
  /// Exposed because a decoder can accept a config that is missing a field it
  /// needs and then never produce a frame: the coded dims here are the only
  /// observable difference between a working and a stalled MF HEVC session.
  DecoderConfig? get videoDecoderConfig => _videoSpec?.config;

  /// Completes after the first video frame reaches the screen.
  Future<void> get onFirstFrame => _firstFrame.future;

  bool get isClosed => _closed;
  bool get isPaused => _paused;

  /// True when this machine has no usable audio output device and the player
  /// degraded to a silent sink: playback runs (and stays paced) but nothing is
  /// audible. Poll-able because it is a property of the machine, not an error
  /// in the stream — it is logged once, never raised to [onError] per chunk.
  bool get audioOutputUnavailable => _audioOut?.usingNullSink ?? false;

  /// Playback volume (audio track only).
  ///
  /// On the worker path this is a `GainNode` on the audio graph rather than a
  /// scale applied to samples, so changing it costs the producer nothing and
  /// does not disturb audio already queued in the ring.
  double get volume => _workerAudio?.volume ?? _audioOut?.volume ?? 1.0;
  set volume(double v) {
    final worker = _workerAudio;
    if (worker != null) {
      worker.volume = v;
      return;
    }
    _audioOut?.volume = v;
  }

  PlayerStats get stats => PlayerStats(
    videoPacketsSubmitted: videoPacketsSubmitted,
    videoPacketsDropped: videoPacketsDropped,
    videoFramesDecoded: videoFramesDecoded,
    videoFramesPresented: _scheduler?.presentedCount ?? 0,
    videoFramesDroppedSuperseded: _scheduler?.droppedSupersededCount ?? 0,
    videoFramesDroppedLate: _scheduler?.droppedLateCount ?? 0,
    videoQueueDepth: _videoQueue.length + (_scheduler?.queueDepth ?? 0),
    audioPacketsSubmitted: audioPacketsSubmitted,
    audioFramesWritten: _audioOut?.writtenFrames ?? 0,
    audioFramesDropped: _audioOut?.droppedFrames ?? 0,
    audioUnderruns: _workerAudio?.underruns ?? 0,
    decodeMs: _lastDecodeMs,
    convertMs: _presenter?.timings.convertMs ?? 0,
    copyMs: _presenter?.timings.copyMs ?? 0,
    presentMs: _presenter?.timings.presentMs ?? 0,
  );

  // ---------------------------------------------------------------------------
  // Packet ingress
  // ---------------------------------------------------------------------------

  /// Feed one encoded video packet (any isolate-safe callsite on the UI
  /// isolate; never blocks — decode happens on the worker).
  void submitVideoPacket(EncodedPacket packet) {
    if (_closed || _videoDecoder == null) return;
    videoPacketsSubmitted++;
    if (_waitingForKeyframe && !packet.isKeyframe) {
      videoPacketsDropped++;
      return;
    }
    _waitingForKeyframe = false;
    if (_videoQueue.length >= maxPendingVideoPackets) {
      videoPacketsDropped += _videoQueue.length;
      _videoQueue.clear();
      if (!packet.isKeyframe) {
        // Reference chain broken — wait for the next sync point.
        _waitingForKeyframe = true;
        videoPacketsDropped++;
        return;
      }
    }
    _videoQueue.add(packet);
    _pumpVideo();
  }

  /// Feed one encoded audio packet.
  void submitAudioPacket(EncodedPacket packet) {
    if (_closed || _audioDecoder == null) return;
    audioPacketsSubmitted++;
    _audioQueue.add(packet);
    _pumpAudio();
  }

  Future<void> _pumpVideo() async {
    if (_videoPumping) return;
    _videoPumping = true;
    try {
      while (_videoQueue.isNotEmpty && !_closed && !_paused && !_seeking) {
        final pkt = _videoQueue.removeAt(0);
        final DecodedFrame? frame;
        final sw = Stopwatch()..start();
        try {
          frame = await _videoDecoder!.decode(pkt);
        } catch (e, s) {
          videoDecodeErrorCount++;
          // Corrupt/lossy input: resync from the next keyframe.
          _waitingForKeyframe = true;
          _onError?.call(e, s);
          continue;
        }
        _lastDecodeMs = sw.elapsedMicroseconds / 1000.0;
        if (frame == null) continue; // decoder buffering (priming/B-frames)
        videoFramesDecoded++;
        // Seek preroll: frames between the landing keyframe and the seek
        // target decode (they are references) but never display.
        final dropBefore = _dropVideoBeforeUs;
        if (dropBefore != null) {
          if (frame.ptsUs < dropBefore) {
            frame.close();
            continue;
          }
          _dropVideoBeforeUs = null;
        }
        await _submitDecodedFrame(frame);
      }
    } finally {
      _videoPumping = false;
    }
  }

  /// Route one decoded frame into the scheduler, by payload:
  ///  - web: the decoder yields a display-ready browser `VideoFrame`
  ///    ([DecodedFrame.webVideoFrame]) — carried through and released by the
  ///    scheduler (present or drop). No readback, no YUV convert.
  ///  - native: read the YUV420P planes now and free the decoder frame.
  Future<void> _submitDecodedFrame(DecodedFrame frame) async {
    final webFrame = frame.webVideoFrame;
    if (webFrame != null) {
      final sched = _scheduler;
      if (sched == null) {
        frame.close();
        return;
      }
      sched.submit(
        ScheduledVideoFrame(
          ptsUs: frame.ptsUs,
          width: frame.width,
          height: frame.height,
          webFrame: webFrame,
          onDone: frame.close, // scheduler releases the VideoFrame
        ),
      );
      return;
    }
    // Native hardware path: a GPU-resident NV12 D3D11 texture (MF decoder).
    // Carry the shared handle through to the presenter (import → NV12→RGBA →
    // present) with no CPU readback; the scheduler releases the decoder's
    // texture via onDone on present-or-drop.
    if (frame.outputKind == FrameSourceKind.d3d11Texture &&
        frame.gpuHandle != 0) {
      final sched = _scheduler;
      if (sched == null) {
        frame.close();
        return;
      }
      sched.submit(
        ScheduledVideoFrame(
          ptsUs: frame.ptsUs,
          width: frame.width,
          height: frame.height,
          d3d11SharedHandle: frame.gpuHandle,
          onDone: frame.close,
        ),
      );
      return;
    }
    final raw = await frame.readBytes();
    final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
    final layout = frame.pixelLayout;
    final fullRange = frame.isFullRange;
    final matrix = frame.colorMatrix;
    frame.close();
    _scheduler?.submit(
      ScheduledVideoFrame(
        ptsUs: frame.ptsUs,
        width: frame.width,
        height: frame.height,
        yuv420p: bytes,
        yuvLayout: layout,
        yuvFullRange: fullRange,
        yuvMatrix: matrix,
      ),
    );
  }

  /// Paced (VOD) write of one decoded chunk, where a pause HOLDS the samples
  /// instead of discarding them.
  ///
  /// The chunk in hand is the only copy: it has already been removed from the
  /// packet queue and decoded (a whole-file decoder hands over the entire
  /// stream in ONE chunk), so aborting the write on `_paused` — as the live
  /// path does, where the source keeps producing and dropping is the point —
  /// silently threw away everything after the pause and still completed
  /// `onEnded`. Only close and seek abort; both discard by definition.
  ///
  /// Returns false when the caller's loop should stop (closed / seeking).
  Future<bool> _writePacedHoldingPause(DecodedAudio chunk) async {
    while (_paused && !_closed && !_seeking) {
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
    if (_closed || _seeking) return false;
    await _audioOut!.writePaced(
      chunk,
      shouldAbort: () => _closed || _seeking,
    );
    return !_closed && !_seeking;
  }

  /// Re-anchors the media clock from the audio device's own consumed count.
  ///
  /// The ring knows exactly how many frames have been PLAYED, which is the true
  /// playback position; the ordinary path can only know what has been written,
  /// which runs ahead by whatever is still sitting in the device buffer. Video
  /// is paced against this clock, so sourcing it from the device is what keeps
  /// the two together.
  ///
  /// Periodic rather than continuous because `PlayerClock` is a wall clock and
  /// only needs correcting for drift between it and the audio device — a few
  /// parts per million, so a step every 250 ms is far below anything visible.
  void _startWorkerAudioClock() {
    _workerAudioClock?.cancel();
    _workerAudioClock = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) {
        if (_closed || _paused || _seeking) return;
        final us = _workerAudio?.positionUs;
        if (us != null) _clock.anchor(us);
      },
    );
  }

  Future<void> _pumpAudio() async {
    if (_audioPumping) return;
    _audioPumping = true;
    try {
      while (_audioQueue.isNotEmpty && !_closed && !_paused && !_seeking) {
        final pkt = _audioQueue.removeAt(0);
        final List<DecodedAudio> chunks;
        try {
          chunks = await _audioDecoder!.decode(pkt);
        } catch (e, s) {
          audioDecodeErrorCount++;
          _onError?.call(e, s);
          continue;
        }
        for (final chunk in chunks) {
          debugOnDecodedAudio?.call(chunk);
          // Seek preroll: skip chunks that end before the target.
          final dropBefore = _dropAudioBeforeUs;
          if (dropBefore != null) {
            if (chunk.ptsUs + chunk.durationUs <= dropBefore) continue;
            _dropAudioBeforeUs = null;
          }
          // Audio is the master clock when present: the first audible
          // sample anchors media time (re-anchoring by video is prevented
          // because this runs before its first frame in practice; if not,
          // a video anchor is only ~one frame off and audio re-anchors).
          if (!_clock.isAnchored) _clock.anchor(chunk.ptsUs);
          if (latencyMode == PlayerLatencyMode.paced) {
            // VOD: never drop — the ring-full wait is the decode-ahead
            // throttle that transitively pauses the demux pump.
            if (!await _writePacedHoldingPause(chunk)) return;
          } else {
            await _audioOut!.write(chunk);
          }
        }
      }
    } finally {
      _audioPumping = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Source-driven playback (openSource)
  // ---------------------------------------------------------------------------

  /// Demux pump: read → route → decode-ahead backpressure. Exits on pause /
  /// seek / close and is re-entered by resume()/seek()/openSource().
  Future<void> _pumpSource() async {
    if (_sourcePumping) return;
    _sourcePumping = true;
    try {
      final demuxer = _demuxer;
      if (demuxer == null) return;
      while (!_closed && !_paused && !_seeking && !_sourceEof) {
        // Decode-ahead bound: undecoded packets + unpresented frames. The
        // paced audio write self-throttles (ring-full waits), so bounding
        // the queues here transitively pauses demux at ~the ring depth.
        if (_videoQueue.length >= _kSourceVideoAhead ||
            (_scheduler?.queueDepth ?? 0) >= _kSourceVideoAhead ||
            _audioQueue.length >= _kSourceAudioAhead) {
          await Future<void>.delayed(const Duration(milliseconds: 4));
          continue;
        }
        final EncodedPacket? pkt;
        try {
          pkt = await demuxer.readPacket();
        } catch (e, s) {
          sourceErrorCount++;
          _onError?.call(e, s);
          break;
        }
        if (pkt == null) {
          _sourceEof = true;
          await _finishEndOfStream();
          break;
        }
        if (pkt.trackIndex == _srcVideoTrack && _videoDecoder != null) {
          videoPacketsSubmitted++;
          // Bypass submitVideoPacket's live catch-up dropper — the
          // decode-ahead gate above is the backpressure here.
          _videoQueue.add(pkt);
          _pumpVideo();
        } else if (pkt.trackIndex == _srcAudioTrack &&
            _audioDecoder != null &&
            _workerAudio == null) {
          // Skipped entirely when the worker owns audio: it has its own
          // demuxer over the same bytes and reads this track itself, so
          // routing here would decode every packet twice.
          audioPacketsSubmitted++;
          _audioQueue.add(pkt);
          _pumpAudio();
        }
      }
    } finally {
      _sourcePumping = false;
    }
  }

  /// Seek a seekable source (files / in-memory containers). Lands on the
  /// keyframe at/before [position], decodes forward, and discards output
  /// until [position] — so the first thing shown/heard is the target.
  Future<void> seek(Duration position) async {
    final mse = _mse;
    if (mse != null) {
      await mse.seek(position);
      return;
    }
    final demuxer = _demuxer;
    if (demuxer == null) {
      throw StateError('seek: player has no attached source');
    }
    if (!demuxer.isSeekable) {
      throw StateError('seek: source is not seekable (live stream)');
    }
    if (_closed || _seeking) return;
    _seeking = true;
    try {
      // Quiesce the decode/source pumps BEFORE touching decoders or queues —
      // setting _seeking makes their loops exit at the next iteration and
      // aborts any in-flight paced-audio ring wait; wait for the in-flight
      // decode to unwind so we never close a decoder mid-decode.
      await _quiesceDecodePumps();
      final targetUs = position.inMicroseconds;
      await demuxer.seek(targetUs);
      // Everything buffered predates the seek.
      _videoQueue.clear();
      _audioQueue.clear();
      _scheduler?.clear();
      _audioOut?.clear();
      _clock.reset();
      _waitingForKeyframe = false; // av_seek_frame lands on a keyframe
      _dropVideoBeforeUs = targetUs;
      _dropAudioBeforeUs = targetUs;
      _sourceEof = false;
      await _recreateDecoders();
      // The worker owns its own demuxer and decoder, so it seeks itself. It
      // suspends the audio thread across the operation, which is what makes
      // clearing the ring safe.
      await _workerAudio?.seek(targetUs);
    } finally {
      _seeking = false;
    }
    _pumpSource();
  }

  /// Moves the audio track onto a worker, if this page can host one.
  ///
  /// Everything about it is best effort. `WorkerAudioTrack.start` returns null
  /// on any page without shared memory, without an `AudioWorklet`, or without
  /// the compiled payload, and this leaves the ordinary audio pump running in
  /// every one of those cases — the same pump that has always been there. It is
  /// an upgrade, never a requirement.
  ///
  /// The worker opens its OWN demuxer over the same bytes and reads the audio
  /// track itself. That is a second parse of the container, which is cheap
  /// (a table walk, measured at ~8 ms for a 20 000-sample file) and buys the
  /// thing worth having: audio packets never cross a thread boundary, so the
  /// main thread is not in the audio path at any point.
  Future<void> _tryWorkerAudio(
    MediaSource source,
    AudioTrackInfo? audioInfo,
  ) async {
    if (audioInfo == null || _audioSpec == null) return;
    final input = source.toDemuxerInput();
    // Bytes-only: the worker is handed a container, not a stream to pull.
    if (input is! BytesDemuxerInput) return;
    final rate = audioInfo.sampleRate;
    final channels = audioInfo.channels;
    if (rate <= 0 || channels <= 0) return;

    final track = await WorkerAudioTrack.start(
      bytes: input.bytes,
      sampleRate: rate,
      channels: channels,
      depth: Duration(milliseconds: _audioSpec.bufferMs * 3),
      volume: _audioOut?.volume ?? 1.0,
    );
    if (track == null) return;

    _workerAudio = track;
    // The main-thread audio path is now dead weight, and leaving the decoder
    // in place would be worse than that: `_pumpSource` routes audio packets on
    // its presence, so every packet would be decoded twice and written to two
    // different sinks.
    try {
      await _audioDecoder?.close();
    } catch (_) {}
    _audioDecoder = null;
    _startWorkerAudioClock();
  }

  /// End-of-stream tail: finish decoding what is queued, flush the decoders,
  /// let the scheduler pace the result to the screen, then complete [onEnded].
  ///
  /// Every wait here is pause-aware, because a paused player can satisfy none
  /// of them: [_pumpVideo] exits on `_paused` (so the packet queue stops
  /// draining) and [pause] freezes the media clock (so the scheduler stops
  /// presenting). Holding for the resume — instead of timing the waits out and
  /// proceeding — is what keeps [drain] from flushing a decoder that still has
  /// queued packets, and what keeps [onEnded] from completing on a tail that is
  /// still queued. Seek/close abandon the tail instead: seek re-reaches EOF and
  /// runs this again, close completes [onEnded] itself.
  Future<void> _finishEndOfStream() async {
    // Packets can still be queued behind the decode-ahead gate at EOF; let
    // them decode before flushing (a flush racing an in-flight decode is also
    // how a frame goes missing).
    while (true) {
      if (!await _awaitResumed()) return;
      await _awaitVideoDecodeIdle();
      if (!_paused) break;
    }
    // A seek that landed while the queue was draining owns the decoders now
    // (it recreates them) — flushing them from here would race that.
    if (_closed || _seeking) return;
    await drain();
    // The tail is decoded, not shown: the scheduler is still pacing it to the
    // screen. onEnded promises presented, not decoded.
    while (true) {
      if (!await _awaitResumed()) return;
      await _scheduler?.waitUntilPresented(
        shouldAbort: () => _closed || _seeking || _paused,
      );
      if (!_paused) break;
    }
    if (_closed || _seeking) return;
    // Video is done. Audio may not be: the worker runs its own demuxer at its
    // own pace and the ring still holds whatever the device has not played.
    // `onEnded` promises the stream is over, and a file whose audio outlasts
    // its video — or an audio-only file, where the video side finishes
    // instantly — would otherwise report ended while still audibly playing.
    if (!await _awaitWorkerAudioEnded()) return;
    if (!_ended.isCompleted) _ended.complete();
  }

  /// Waits for worker-hosted audio to finish playing. True when it has (or
  /// when there is none); false when close/seek ended the wait.
  Future<bool> _awaitWorkerAudioEnded() async {
    final worker = _workerAudio;
    if (worker == null) return true;
    while (!_closed && !_seeking) {
      if (!await _awaitResumed()) return false;
      if (await worker.isEnded()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return false;
  }

  /// Block while the player is paused. False when close/seek ended the wait
  /// (the caller must abandon what it was doing), true when playback is live.
  Future<bool> _awaitResumed() async {
    while (_paused && !_closed && !_seeking) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return !_closed && !_seeking;
  }

  /// Poll until the video decode pump has consumed everything queued.
  /// Bounded so a wedged decoder cannot hang end-of-stream.
  Future<void> _awaitVideoDecodeIdle() async {
    for (var i = 0; i < 400; i++) {
      if (!_videoPumping && _videoQueue.isEmpty) return;
      // A paused/seeking/closed pump has stopped consuming the queue, so the
      // condition above is unsatisfiable until it restarts — returning lets
      // the caller wait on THAT instead of burning the bound here.
      if (_paused || _seeking || _closed) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  /// Poll until the decode + source pumps have exited their loops (they honor
  /// [_seeking]). Bounded so a wedged pump can't hang seek forever.
  Future<void> _quiesceDecodePumps() async {
    for (var i = 0; i < 200; i++) {
      if (!_videoPumping && !_audioPumping && !_sourcePumping) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  /// libav decoders carry reference state a container seek invalidates —
  /// reopen them from the stored specs.
  Future<void> _recreateDecoders() async {
    final videoSpec = _videoSpec;
    if (videoSpec != null) {
      try {
        await _videoDecoder?.close();
      } catch (_) {}
      _videoDecoder = await MiniAVTools.createDecoder(
        videoSpec.config,
        preference: _preference,
      );
    }
    final audioSpec = _audioSpec;
    if (audioSpec != null) {
      try {
        await _audioDecoder?.close();
      } catch (_) {}
      _audioDecoder = await MiniAVTools.createAudioDecoder(
        audioSpec.config,
        preference: _preference,
      );
    }
  }

  /// Container duration (seekable sources; null for live/packet-driven).
  Duration? get duration => _mse?.duration ?? _durationFromDemuxer();

  Duration? _durationFromDemuxer() {
    final us = _demuxer?.durationUs;
    return us != null ? Duration(microseconds: us) : null;
  }

  /// Current media time (what should be on screen / audible now), or null
  /// before the first frame/chunk anchors the clock.
  Duration? get position {
    final mse = _mse;
    if (mse != null) return mse.position;
    final us = _clock.mediaTimeUs();
    if (us == null) return null;
    return Duration(microseconds: us < 0 ? 0 : us);
  }

  /// Whether [seek] is available (source-driven + seekable input).
  /// The MSE `<video>` fallback is seekable once metadata is known.
  bool get isSeekable => usingMse || (_demuxer?.isSeekable ?? false);

  /// Completes when a source-driven player reaches end-of-stream AND the
  /// buffered tail has been drained. Specifically, at completion:
  ///
  ///  - every packet the container held has been decoded (including whatever
  ///    the decoders were still holding, released by [drain]);
  ///  - every decoded video frame has been PRESENTED — or dropped by the
  ///    scheduler — so nothing is still being paced to the screen. Video is
  ///    pts-clocked, so this is strictly later than "the last frame decoded";
  ///  - every decoded audio chunk [drain] produced has been written to the
  ///    output sink.
  ///
  /// It does NOT wait for the audio device to play out what is already in its
  /// ring (~`AudioStreamSpec.bufferMs`), nor for paced writes still in flight
  /// from the packet pump when the drain began. Both waits above are bounded:
  /// a wedged presenter delays end-of-stream, it never blocks it forever.
  ///
  /// While [pause]d the tail waits are HELD, not timed out — a paused player
  /// presents nothing, so completing would break the promise above. Resuming
  /// finishes the tail; [close] also completes this (an app awaiting it to
  /// advance a playlist would otherwise hang when the user stops playback
  /// before the end), so a completion means "nothing more will be presented",
  /// which end-of-stream and close both are.
  Future<void> get onEnded => _ended.future;

  // ---------------------------------------------------------------------------
  // Transport controls
  // ---------------------------------------------------------------------------

  void pause() {
    if (_closed) return;
    final mse = _mse;
    if (mse != null) {
      _paused = true;
      mse.pause();
      return;
    }
    if (_paused) return;
    _paused = true;
    _clock.pause();
    _audioOut?.pause();
    // Suspending the audio thread is the whole of pause for the worker path:
    // with nothing draining the ring, the worker blocks on backpressure.
    unawaited(_workerAudio?.pause() ?? Future<void>.value());
  }

  /// Resume playback. On the MSE path this ALWAYS retries `play()` (even when
  /// not [pause]d) — it is the documented recovery for an autoplay-policy
  /// rejection: call it from a user gesture.
  void resume() {
    if (_closed) return;
    final mse = _mse;
    if (mse != null) {
      _paused = false;
      unawaited(mse.play());
      return;
    }
    if (!_paused) return;
    _paused = false;
    _clock.resume();
    _audioOut?.resume();
    unawaited(_workerAudio?.resume() ?? Future<void>.value());
    _pumpVideo();
    _pumpAudio();
    _pumpSource();
  }

  /// End-of-stream: drain decoder-buffered frames/samples and present them.
  ///
  /// This path applies the same seek preroll as [_pumpVideo] / [_pumpAudio]:
  /// a decoder that only emits at `flush()` (a short single-GOP file, a
  /// whole-file audio decoder) delivers EVERY frame here, so skipping the
  /// preroll made a seek restart from the landing keyframe instead of the
  /// requested position.
  Future<void> drain() async {
    if (_closed) return;
    final videoDecoder = _videoDecoder;
    if (videoDecoder != null) {
      try {
        for (final frame in await videoDecoder.flush()) {
          videoFramesDecoded++;
          final dropBefore = _dropVideoBeforeUs;
          if (dropBefore != null) {
            if (frame.ptsUs < dropBefore) {
              frame.close();
              continue;
            }
            _dropVideoBeforeUs = null;
          }
          await _submitDecodedFrame(frame);
        }
      } catch (e, s) {
        videoDecodeErrorCount++;
        _onError?.call(e, s);
      }
    }
    final audioDecoder = _audioDecoder;
    if (audioDecoder != null) {
      try {
        final chunks = await audioDecoder.flush();
        for (final chunk in chunks) {
          debugOnDecodedAudio?.call(chunk);
          final dropBefore = _dropAudioBeforeUs;
          if (dropBefore != null) {
            if (chunk.ptsUs + chunk.durationUs <= dropBefore) continue;
            _dropAudioBeforeUs = null;
          }
          if (!_clock.isAnchored) _clock.anchor(chunk.ptsUs);
          // Same mode split as _pumpAudio. The flushed tail is often the
          // BIGGEST write of the stream (a whole-file decoder emits
          // everything here), and the live write() drops whatever the ring
          // cannot take right now — so draining it in live mode threw the
          // end of every paced/VOD stream away.
          if (latencyMode == PlayerLatencyMode.paced) {
            if (!await _writePacedHoldingPause(chunk)) return;
          } else {
            await _audioOut!.write(chunk);
          }
        }
      } catch (e, s) {
        audioDecodeErrorCount++;
        _onError?.call(e, s);
      }
    }
  }

  /// Discard everything buffered but not yet presented/audible (seek /
  /// stream restart). The next video packet must be a keyframe; the clock
  /// re-anchors from the next accepted chunk.
  void discardBuffered() {
    _videoQueue.clear();
    _audioQueue.clear();
    _scheduler?.clear();
    _audioOut?.clear();
    _waitingForKeyframe = true;
    _clock.reset();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    // A closed player will never present again, which is what onEnded means —
    // complete it on every path (the native one used to leave an awaiting
    // playlist advance hanging forever when the user stopped before EOF).
    if (!_ended.isCompleted) _ended.complete();
    // MSE fallback owns only its <video>/MediaSource — no decode/GPU pipeline.
    if (_mse != null) {
      _mseOnClose?.call();
      _mseOnClose = null;
      _mse!.dispose();
      _mse = null;
      return;
    }
    // Demuxer first: unblocks a starved live read so the pump exits.
    try {
      await _demuxer?.close();
    } catch (_) {}
    _videoQueue.clear();
    _audioQueue.clear();
    // Dispose the scheduler first so no NEW present is dispatched, then let
    // the presenter drain its in-flight present before GPU teardown.
    _scheduler?.dispose();
    try {
      await _videoDecoder?.close();
    } catch (_) {}
    try {
      await _audioDecoder?.close();
    } catch (_) {}
    _audioOut?.dispose();
    _workerAudioClock?.cancel();
    _workerAudioClock = null;
    try {
      await _workerAudio?.close();
    } catch (_) {}
    _workerAudio = null;
    // Unregister the texture from Flutter (owned controller) BEFORE destroying
    // the GPU textures, and await the presenter so its in-flight async copy /
    // present has finished — otherwise `destroy()` frees a texture still in
    // use (use-after-free).
    if (_ownsController) await _controller?.dispose();
    await _presenter?.dispose();
    if (_ownsGpu) await _gpu?.destroy();
  }
}
