/// FFmpeg backend for miniav_tools.
///
/// This package provides codecs/muxers/demuxers backed by FFmpeg
/// (libavcodec, libavformat, libavutil, libswscale, libswresample).
///
/// Importing this library auto-registers the backend with
/// [MiniAVToolsPlatform]. To use it explicitly:
///
/// ```dart
/// import 'package:miniav_tools/miniav_tools.dart';
/// import 'package:miniav_tools_ffmpeg/miniav_tools_ffmpeg.dart';
///
/// final enc = await MiniAVTools.createEncoder(
///   const EncoderConfig(
///     codec: VideoCodec.h264,
///     width: 1920, height: 1080, bitrateBps: 8_000_000,
///   ),
///   preference: BackendPreference.pinned('ffmpeg'),
/// );
/// ```
library;

export 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';
export 'src/ffmpeg_backend.dart' show FfmpegBackend;
export 'src/ffmpeg_bindings.dart' show ensureFFmpegLoaded, tryLoadFFmpeg;
export 'src/ffmpeg_audio_encoder.dart' show FfmpegAudioEncoder;
export 'src/ffmpeg_encoder.dart' show FfmpegSoftwareEncoder;
export 'src/ffmpeg_muxer.dart' show FfmpegMuxer, FfmpegEncoderBridge;
export 'src/ffmpeg_nvenc_encoder.dart'
    show FfmpegNvencEncoder, ffmpegNvencAvailable;
export 'src/ffmpeg_hw_encoder.dart'
    show
        FfmpegHwEncoder,
        HwEncoderVendor,
        ffmpegHwEncoderAvailable,
        ffmpegHwVendorsAvailable;
export 'src/ffmpeg_d3d11_hw_encoder.dart'
    show
        FfmpegD3d11HwEncoder,
        D3d11HwVendor,
        D3d11HwSourceFormat,
        ffmpegD3d11EncoderAvailable,
        ffmpegD3d11VendorsAvailable;
export 'src/ffmpeg_downloader.dart'
    show
        FfmpegDownloader,
        FfmpegDownloadResult,
        kFfmpegReleaseTag,
        kFfmpegVersionSuffix;

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

import 'src/ffmpeg_backend.dart';

/// Top-level side-effect: registers [FfmpegBackend] on first import.
// ignore: unused_element
final _registered = registerFfmpegBackend();

/// Manually register the FFmpeg backend (idempotent).
bool registerFfmpegBackend() {
  final existing = MiniAVToolsPlatform.instance.backends.any(
    (b) => b.name == FfmpegBackend.backendName,
  );
  if (existing) return false;
  MiniAVToolsPlatform.instance.register(FfmpegBackend());
  return true;
}
