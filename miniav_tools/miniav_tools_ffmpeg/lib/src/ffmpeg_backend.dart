/// FFmpeg [MiniAVToolsBackend] implementation.
///
/// Phase A (current): software libx264 / libopenh264 / etc. via libavcodec.
/// Phase B (planned): NVENC / QSV / AMF hardware encoders with D3D11VA
///                    zero-copy from miniav GPU buffers.
/// Phase C (planned): MP4 / MKV muxer and demuxer via libavformat.
library;

import 'dart:async';
import 'dart:io';

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

import 'ffmpeg_audio_encoder.dart';
import 'ffmpeg_bindings.dart' as ffi;
import 'ffmpeg_d3d11_hw_encoder.dart';
import 'ffmpeg_decoder.dart';
import 'ffmpeg_encoder.dart';
import 'ffmpeg_hw_encoder.dart';
import 'ffmpeg_muxer.dart';

class FfmpegBackend extends MiniAVToolsBackend {
  static const String backendName = 'ffmpeg';

  /// FFmpeg generally has the broadest codec coverage, so it bids high by
  /// default. Users can lower this via
  /// [MiniAVToolsPlatform.setBackendPriority] if a more specialised backend
  /// (e.g. minigpu MJPEG, WebCodecs) should win.
  static const int defaultPriority = 50;

  @override
  String get name => backendName;

  @override
  int get priority => _priority;
  int _priority = defaultPriority;

  /// Mutable priority (used by tests + the registry).
  // ignore: use_setters_to_change_properties
  void setPriority(int p) => _priority = p;

  /// Lazily probe FFmpeg availability the first time we're asked.
  bool? _available;
  bool get _isAvailable => _available ??= ffi.tryLoadFFmpeg();

  /// Async ensure: triggers an auto-download if libs are not already
  /// resolvable. Throws [CodecInitException] when libs cannot be obtained.
  Future<void> _ensureAvailable() async {
    if (_isAvailable) return;
    final ok = await ffi.ensureFFmpegLoaded();
    _available = ok;
    if (!ok) {
      throw const CodecInitException(
        backendName,
        'FFmpeg shared libraries not found and auto-download did not '
        'succeed. Install FFmpeg, set FFMPEG_LIB_DIR, or check your '
        'network connection. Set MINIAV_TOOLS_FFMPEG_NO_AUTODOWNLOAD=1 '
        'to silence this attempt.',
      );
    }
  }

  // --- Warmup ---------------------------------------------------------------

  static const _kTaskFfmpegDownload = 'Downloading FFmpeg';

  @override
  Stream<WarmupProgress> warmup() {
    if (_isAvailable) return const Stream.empty();

    final ctrl = StreamController<WarmupProgress>();

    ffi
        .ensureFFmpegLoaded(
          onDownloadProgress: (int received, int total) {
            ctrl.add(
              WarmupProgress(
                backendName: name,
                task: _kTaskFfmpegDownload,
                isDone: false,
                bytesReceived: received,
                // Some HTTP responses omit Content-Length (-1 sentinel).
                totalBytes: total < 0 ? null : total,
              ),
            );
          },
        )
        .then(
          (ok) {
            _available = ok;
            ctrl.add(
              WarmupProgress(
                backendName: name,
                task: _kTaskFfmpegDownload,
                isDone: true,
                error: ok ? null : 'FFmpeg auto-download failed or is disabled',
              ),
            );
          },
          onError: (Object e) {
            ctrl.add(
              WarmupProgress(
                backendName: name,
                task: _kTaskFfmpegDownload,
                isDone: true,
                error: e,
              ),
            );
          },
        )
        .whenComplete(ctrl.close);

    return ctrl.stream;
  }

  // --- Capabilities ---------------------------------------------------------

  static const _swEncode = <VideoCodec>{
    VideoCodec.h264, // libx264
    VideoCodec.hevc, // libx265
    VideoCodec.vp9,
    VideoCodec.vp8,
    VideoCodec.av1, // libaom-av1 / libsvtav1
    VideoCodec.mjpeg,
    VideoCodec.prores,
  };

  static const _hwEncode = <VideoCodec>{
    VideoCodec.h264, // h264_nvenc, h264_qsv, h264_amf, h264_videotoolbox
    VideoCodec.hevc,
    VideoCodec.av1, // av1_nvenc on Ada+, av1_qsv on Arc+
  };

  /// Capabilities are advertised optimistically: the FFmpeg backend can
  /// always satisfy these requests *given network access*. The actual lib
  /// load happens lazily inside `create*` via [_ensureAvailable].
  @override
  bool supportsEncode(VideoCodec codec, {bool hwAccel = false}) =>
      hwAccel ? _hwEncode.contains(codec) : _swEncode.contains(codec);

  @override
  bool supportsDecode(VideoCodec codec, {bool hwAccel = false}) => true;

  @override
  bool supportsAudioEncode(AudioCodec codec) =>
      codec == AudioCodec.aac || codec == AudioCodec.opus;

  @override
  bool supportsAudioDecode(AudioCodec codec) => true;

  @override
  bool supportsMux(Container container) => true;

  @override
  bool supportsDemux(Container container) => true;

  /// Frame sources we can consume directly. CPU and miniav-buffer-CPU work
  /// everywhere; the GPU-handle sources gate on platform because the
  /// underlying FFmpeg hwcontext is only meaningful on its native OS.
  ///
  /// - **Windows**: D3D11 NT-handle (Stage B zero-copy via NVENC/AMF/QSV/MF).
  /// - **macOS / iOS**: CVPixelBuffer (VideoToolbox zero-copy with IOSurface
  ///   passed through `data[3]` as `AV_PIX_FMT_VIDEOTOOLBOX`).
  /// - **Linux**: dmabuf FD (VAAPI / V4L2 M2M zero-copy).
  /// - **Android**: AHardwareBuffer (MediaCodec via `*_mediacodec` codecs).
  ///
  /// All zero-copy paths fall back to a CPU upload if the requested codec
  /// has no matching HW encoder in the loaded FFmpeg build.
  @override
  Set<FrameSourceKind> get acceptedFrameSources {
    final base = <FrameSourceKind>{
      FrameSourceKind.cpu,
      FrameSourceKind.miniavBufferCpu,
    };
    if (Platform.isWindows) {
      base.addAll(const {
        FrameSourceKind.miniavBufferD3D11,
        FrameSourceKind.d3d11Texture,
      });
    } else if (Platform.isMacOS || Platform.isIOS) {
      base.addAll(const {
        FrameSourceKind.miniavBufferMetal,
        FrameSourceKind.cvPixelBuffer,
      });
    } else if (Platform.isLinux) {
      base.addAll(const {
        FrameSourceKind.miniavBufferDmabuf,
        FrameSourceKind.dmabuf,
      });
    } else if (Platform.isAndroid) {
      base.add(FrameSourceKind.miniavBufferAHardwareBuffer);
    }
    return base;
  }

  // --- Factories ------------------------------------------------------------

  @override
  Future<PlatformEncoder?> createEncoder(
    EncoderConfig config, {
    BackendContext? context,
  }) async {
    if (!_swEncode.contains(config.codec) &&
        !_hwEncode.contains(config.codec)) {
      return null;
    }
    await _ensureAvailable();

    // Stage A hardware path: try every supported vendor (NVENC > QSV > AMF
    // > VideoToolbox > MediaFoundation > V4L2) for h264 / hevc / av1 when
    // the user asked for hwAccel and an encoder is available in this
    // FFmpeg build. Falls back to software if hwAccel is `preferred`
    // (best-effort) and nothing matches. `required` propagates the failure.
    final wantHw =
        config.hwAccel == HwAccelPreference.preferred ||
        config.hwAccel == HwAccelPreference.required;
    if (wantHw && _hwEncode.contains(config.codec)) {
      // Stage B opt-in: caller asked for zero-copy via either:
      //   (a) `backendOptions['zerocopy'] == '1'` (legacy direct callers), or
      //   (b) a [BackendContext] with `preferZeroCopy: true` AND a non-zero
      //       `d3d11DeviceHandle` (the recorder uses this path).
      // When (b) is taken we hand the existing D3D11 device into the
      // encoder so its output texture lives on the same device as the
      // caller's GPU pipeline (Dawn) — that's what makes the path actually
      // zero-copy end-to-end (no `OpenSharedResource1` round-trip).
      final zerocopyOpt = config.backendOptions['zerocopy'] == '1';
      final ctxZeroCopy =
          context != null &&
          context.preferZeroCopy &&
          context.d3d11DeviceHandle != 0 &&
          Platform.isWindows;
      if (zerocopyOpt || ctxZeroCopy) {
        if (!ffmpegD3d11EncoderAvailable(config.codec)) {
          if (zerocopyOpt) {
            throw CodecInitException(
              backendName,
              'zerocopy=1 requested but no D3D11VA encoder is available for '
              '${config.codec} (need NVENC/AMF/QSV/MF in this FFmpeg build, '
              'plus the miniav_tools_ffmpeg shim).',
            );
          }
          // Context-driven zero-copy is best-effort — just fall through.
          stderr.writeln(
            '[ffmpeg] createEncoder: D3D11 zero-copy skipped — no D3D11VA '
            'encoder available for ${config.codec} in this FFmpeg build.',
          );
        } else {
          try {
            final enc = FfmpegD3d11HwEncoder.open(
              config,
              existingD3d11Device: ctxZeroCopy ? context.d3d11DeviceHandle : 0,
            );
            stderr.writeln(
              '[ffmpeg] createEncoder: D3D11 zero-copy encoder opened '
              '(${enc.runtimeType}) for ${config.codec} '
              '${config.width}x${config.height}'
              '${ctxZeroCopy ? " [injected device 0x${context.d3d11DeviceHandle.toRadixString(16)}]" : " [new device]"}',
            );
            return enc;
          } on CodecInitException catch (e) {
            // Strict opt-in (a) — propagate. Context opt-in (b) — fall back.
            if (zerocopyOpt) rethrow;
            stderr.writeln(
              '[ffmpeg] createEncoder: D3D11 zero-copy failed ($e) — '
              'falling back to Stage A NVENC/software.',
            );
          }
        }
      }
      if (ffmpegHwEncoderAvailable(config.codec)) {
        try {
          final enc = FfmpegHwEncoder.open(config);
          stderr.writeln(
            '[ffmpeg] createEncoder: Stage A HW encoder opened '
            '(${enc.runtimeType}) for ${config.codec} '
            '${config.width}x${config.height}',
          );
          return enc;
        } on CodecInitException catch (e) {
          if (config.hwAccel == HwAccelPreference.required) rethrow;
          // preferred: fall through to software.
          stderr.writeln(
            '[ffmpeg] createEncoder: Stage A HW encoder failed ($e) — '
            'falling back to software.',
          );
        }
      } else if (config.hwAccel == HwAccelPreference.required) {
        throw CodecInitException(
          backendName,
          'No hardware encoder for ${config.codec} present in the loaded '
          'FFmpeg build (hwAccel=required). Vendors checked: NVENC, QSV, '
          'AMF, VideoToolbox, MediaFoundation, V4L2.',
        );
      } else {
        stderr.writeln(
          '[ffmpeg] createEncoder: no HW encoder available for ${config.codec}'
          ' — using software.',
        );
      }
      // hwAccel=preferred: silently fall through to software.
    }

    final enc = FfmpegSoftwareEncoder.open(config);
    stderr.writeln(
      '[ffmpeg] createEncoder: software encoder opened '
      '(${enc.runtimeType}) for ${config.codec} '
      '${config.width}x${config.height}',
    );
    return enc;
  }

  /// Pick the best [VideoCodec] for the given resolution + HW preference.
  ///
  /// On HW paths, H.264 is capped at 4096px wide on every shipping vendor
  /// (NVENC, QSV, AMF, VT). For ultrawide / 4K+ captures we transparently
  /// promote to HEVC, which all of those vendors support up to 8192px.
  /// Caller can pass [preferred] to express intent (e.g. user explicitly
  /// asked for AV1).
  static VideoCodec bestCodecForResolution({
    required int width,
    required int height,
    required bool hwAccel,
    VideoCodec preferred = VideoCodec.h264,
  }) {
    if (!hwAccel) return preferred;
    if (preferred == VideoCodec.h264 && (width > 4096 || height > 4096)) {
      return VideoCodec.hevc;
    }
    return preferred;
  }

  @override
  Future<PlatformDecoder?> createDecoder(
    DecoderConfig config, {
    BackendContext? context,
  }) async {
    await _ensureAvailable();
    return FfmpegSoftwareDecoder.open(config);
  }

  @override
  Future<PlatformMuxer?> createMuxer(MuxerConfig config) async {
    await _ensureAvailable();
    return FfmpegMuxer.open(config);
  }

  @override
  Future<PlatformDemuxer?> createDemuxer(DemuxerConfig config) async {
    await _ensureAvailable();
    throw const CodecInitException(
      backendName,
      'FFmpeg demuxer implementation pending — scaffold only.',
    );
  }

  @override
  Future<PlatformAudioEncoder?> createAudioEncoder(
    AudioEncoderConfig config, {
    BackendContext? context,
  }) async {
    if (!supportsAudioEncode(config.codec)) return null;
    await _ensureAvailable();
    return FfmpegAudioEncoder.open(config);
  }
}
