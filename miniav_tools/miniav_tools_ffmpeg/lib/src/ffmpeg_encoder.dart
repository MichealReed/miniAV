/// Software FFmpeg encoder (libavcodec) — Phase A.
///
/// Wraps `avcodec_send_frame` / `avcodec_receive_packet` for a single
/// video stream. Accepts CPU frames (rgba/bgra/rgb/bgr/i420/nv12) and
/// converts them to YUV420P before submission.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

import 'ffmpeg_ffi.dart';
import 'ffmpeg_muxer.dart' show FfmpegEncoderBridge;
import 'pixel_convert.dart';

/// Codec id selection for the FFmpeg encoder MVP.
int _videoCodecToAvId(VideoCodec codec) {
  switch (codec) {
    case VideoCodec.h264:
      return AVCodecId.h264;
    case VideoCodec.hevc:
      return AVCodecId.hevc;
    case VideoCodec.mjpeg:
      return AVCodecId.mjpeg;
    case VideoCodec.vp8:
      return AVCodecId.vp8;
    case VideoCodec.vp9:
      return AVCodecId.vp9;
    case VideoCodec.av1:
      return AVCodecId.av1;
    default:
      throw CodecInitException(
        'ffmpeg',
        'Encoder: unsupported VideoCodec.$codec for software path',
      );
  }
}

/// Preferred encoder name for a given codec (libx264 > h264, etc.).
String? _preferredEncoderName(VideoCodec codec) {
  switch (codec) {
    case VideoCodec.h264:
      return 'libx264';
    case VideoCodec.hevc:
      return 'libx265';
    case VideoCodec.vp8:
      return 'libvpx';
    case VideoCodec.vp9:
      return 'libvpx-vp9';
    case VideoCodec.av1:
      return 'libsvtav1';
    case VideoCodec.mjpeg:
      return 'mjpeg';
    default:
      return null;
  }
}

class FfmpegSoftwareEncoder implements PlatformEncoder, FfmpegEncoderBridge {
  FfmpegSoftwareEncoder._(
    this._ff,
    this._cfg,
    this._codecCtx,
    this._frame,
    this._packet,
  );

  final Ffmpeg _ff;
  final EncoderConfig _cfg;
  final Pointer<AVCodecContext> _codecCtx;
  final Pointer<AVFrame> _frame;
  final Pointer<AVPacket> _packet;

  bool _closed = false;
  int _nextPts = 0;
  CodecExtraData? _extraData;
  bool _forceKeyframe = false;

  /// Build + open an encoder. Throws [CodecInitException] on any failure.
  static FfmpegSoftwareEncoder open(EncoderConfig cfg) {
    final ff = Ffmpeg.instance();
    if (ff == null) {
      throw const CodecInitException(
        'ffmpeg',
        'FFmpeg not loaded — call ensureFFmpegLoaded() first',
      );
    }

    final codec = _findEncoder(ff, cfg);
    final codecCtx = ff.avcodecAllocContext3(codec);
    if (codecCtx == address(0)) {
      throw const CodecInitException(
        'ffmpeg',
        'avcodec_alloc_context3 returned NULL',
      );
    }

    try {
      _configureCtx(ff, codecCtx, cfg);
      final ret = ff.avcodecOpen2(codecCtx, codec, nullptr);
      if (ret < 0) {
        throw CodecInitException(
          'ffmpeg',
          'avcodec_open2 failed: ${ff.strError(ret)} ($ret)',
        );
      }

      final frame = ff.avFrameAlloc();
      final packet = ff.avPacketAlloc();
      if (frame == address(0) || packet == address(0)) {
        throw const CodecInitException(
          'ffmpeg',
          'av_frame_alloc / av_packet_alloc returned NULL',
        );
      }
      // Configure frame dimensions / format up front.
      frame.ref
        ..width = cfg.width
        ..height = cfg.height
        ..format = AVPixelFormat.yuv420p;

      final r = ff.avFrameGetBuffer(frame, 32);
      if (r < 0) {
        throw CodecInitException(
          'ffmpeg',
          'av_frame_get_buffer failed: ${ff.strError(r)}',
        );
      }

      return FfmpegSoftwareEncoder._(ff, cfg, codecCtx, frame, packet)
        .._loadExtraData();
    } catch (_) {
      // Free codec context on configuration failure.
      final ptr = calloc<Pointer<AVCodecContext>>()..value = codecCtx;
      ff.avcodecFreeContext(ptr);
      calloc.free(ptr);
      rethrow;
    }
  }

  static Pointer<AVCodec> _findEncoder(Ffmpeg ff, EncoderConfig cfg) {
    final preferred = _preferredEncoderName(cfg.codec);
    if (preferred != null) {
      final namePtr = preferred.toNativeUtf8();
      try {
        final codec = ff.avcodecFindEncoderByName(namePtr);
        if (codec != address(0)) return codec;
      } finally {
        calloc.free(namePtr);
      }
    }
    final byId = ff.avcodecFindEncoder(_videoCodecToAvId(cfg.codec));
    if (byId == address(0)) {
      throw CodecInitException(
        'ffmpeg',
        'No encoder found for ${cfg.codec} (tried "$preferred" and id '
            '${_videoCodecToAvId(cfg.codec)})',
      );
    }
    return byId;
  }

  static void _configureCtx(
    Ffmpeg ff,
    Pointer<AVCodecContext> ctx,
    EncoderConfig cfg,
  ) {
    final ctxV = ctx.cast<Void>();
    void setStr(String key, String val) {
      final k = key.toNativeUtf8();
      final v = val.toNativeUtf8();
      try {
        ff.avOptSet(ctxV, k, v, 0);
      } finally {
        calloc.free(k);
        calloc.free(v);
      }
    }

    void setQ(String key, int num, int den) {
      final k = key.toNativeUtf8();
      final r = calloc<AVRational>();
      r.ref
        ..num = num
        ..den = den;
      try {
        final ret = ff.avOptSetQ(ctxV, k, r.ref, 0);
        if (ret < 0) {
          throw CodecInitException(
            'ffmpeg',
            'av_opt_set_q($key=$num/$den) failed: ${ff.strError(ret)} ($ret)',
          );
        }
      } finally {
        calloc.free(k);
        calloc.free(r);
      }
    }

    void setIntStrict(String key, int val) {
      final k = key.toNativeUtf8();
      try {
        final r = ff.avOptSetInt(ctxV, k, val, 0);
        if (r < 0) {
          throw CodecInitException(
            'ffmpeg',
            'av_opt_set_int($key=$val) failed: ${ff.strError(r)} ($r)',
          );
        }
      } finally {
        calloc.free(k);
      }
    }

    setStr('video_size', '${cfg.width}x${cfg.height}');
    setStr('pixel_format', 'yuv420p');
    setIntStrict('b', cfg.bitrateBps);
    if (cfg.gopLength > 0) {
      setIntStrict('g', cfg.gopLength);
    }
    // bFrameCount is always honoured (0 = no B-frames; muxers + low-latency
    // pipelines often require this).
    setIntStrict('bf', cfg.bFrameCount);
    setQ('time_base', cfg.frameRateDenominator, cfg.frameRateNumerator);
    // framerate is informational; ignore if encoder doesn't expose it.
    final fr = calloc<AVRational>();
    fr.ref
      ..num = cfg.frameRateNumerator
      ..den = cfg.frameRateDenominator;
    final frKey = 'framerate'.toNativeUtf8();
    ff.avOptSetQ(ctxV, frKey, fr.ref, 0);
    calloc.free(frKey);
    calloc.free(fr);

    // Global-header flag (required for MP4 / fragmented MP4 muxing —
    // SPS/PPS go in extradata, not inline). Opt-in via backendOptions.
    if (cfg.backendOptions['global_header'] == '1') {
      setStr('flags', '+global_header');
    }

    // CRF mode (libx264/libx265 + libvpx accept it)
    if (cfg.rateControl == RateControl.crf && cfg.crfQuality != null) {
      setStr('crf', cfg.crfQuality!.toString());
    }

    // Backend-specific options pass-through (skip ones we already consumed).
    cfg.backendOptions.forEach((k, v) {
      if (k == 'global_header') return;
      setStr(k, v);
    });
  }

  @override
  CodecExtraData? get extraData => _extraData;

  @override
  Future<void> requestKeyframe() async {
    _forceKeyframe = true;
  }

  @override
  Future<EncodedPacket?> encode(FrameSource frame) async {
    _checkOpen();
    final yuv = _frameToYuv420p(frame);
    if (yuv.width != _cfg.width || yuv.height != _cfg.height) {
      throw CodecRuntimeException(
        'ffmpeg',
        'Frame size ${yuv.width}x${yuv.height} != encoder size '
            '${_cfg.width}x${_cfg.height}',
      );
    }

    // Make frame writable + copy plane data.
    final mw = _ff.avFrameMakeWritable(_frame);
    if (mw < 0) {
      throw CodecRuntimeException(
        'ffmpeg',
        'av_frame_make_writable: '
            '${_ff.strError(mw)}',
      );
    }
    final f = _frame.ref;
    _copyPlane(f.data0, f.linesize0, yuv.y, yuv.width, yuv.height);
    _copyPlane(f.data1, f.linesize1, yuv.u, yuv.width ~/ 2, yuv.height ~/ 2);
    _copyPlane(f.data2, f.linesize2, yuv.v, yuv.width ~/ 2, yuv.height ~/ 2);
    f.pts = _nextPts++;
    f.pictType = _forceKeyframe ? 1 /* AV_PICTURE_TYPE_I */ : 0;
    _forceKeyframe = false;

    final sendRet = _ff.avcodecSendFrame(_codecCtx, _frame);
    if (sendRet < 0 && sendRet != kAvErrorEAgain) {
      throw CodecRuntimeException(
        'ffmpeg',
        'avcodec_send_frame: ${_ff.strError(sendRet)} ($sendRet)',
      );
    }

    return _drainOne();
  }

  @override
  Future<List<EncodedPacket>> flush() async {
    _checkOpen();
    final ret = _ff.avcodecSendFrame(_codecCtx, nullptr);
    if (ret < 0 && ret != kAvErrorEof) {
      throw CodecRuntimeException(
        'ffmpeg',
        'avcodec_send_frame(NULL): ${_ff.strError(ret)}',
      );
    }
    final out = <EncodedPacket>[];
    while (true) {
      final pkt = _drainOne();
      if (pkt == null) break;
      out.add(pkt);
    }
    return out;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final fp = calloc<Pointer<AVFrame>>()..value = _frame;
    final pp = calloc<Pointer<AVPacket>>()..value = _packet;
    final cp = calloc<Pointer<AVCodecContext>>()..value = _codecCtx;
    try {
      _ff.avFrameFree(fp);
      _ff.avPacketFree(pp);
      _ff.avcodecFreeContext(cp);
    } finally {
      calloc.free(fp);
      calloc.free(pp);
      calloc.free(cp);
    }
  }

  // --- helpers --------------------------------------------------------------

  void _checkOpen() {
    if (_closed) {
      throw const CodecRuntimeException('ffmpeg', 'encoder closed');
    }
  }

  /// Internal accessor for the FFmpeg muxer (same package). Allows the muxer
  /// to call `avcodec_parameters_from_context` directly, preserving extradata
  /// (SPS/PPS) without round-tripping through bytes.
  @override
  Pointer<AVCodecContext> get nativeCodecContext => _codecCtx;

  /// Best-effort: copy `AVCodecContext.extradata` (SPS/PPS for libx264 with
  /// global_header set) into [_extraData]. Safe to call even if extradata is
  /// empty — codecs without global headers (default libx264) just produce
  /// zero-length extradata.
  void _loadExtraData() {
    final params = _ff.avcodecParametersAlloc();
    if (params == address(0)) return;
    final pp = calloc<Pointer<AVCodecParameters>>()..value = params;
    try {
      final r = _ff.avcodecParametersFromContext(params, _codecCtx);
      if (r < 0) return;
      final ref = params.ref;
      if (ref.extradataSize > 0 && ref.extradata != address(0)) {
        final bytes = Uint8List(ref.extradataSize);
        bytes.setAll(0, ref.extradata.asTypedList(ref.extradataSize));
        _extraData = CodecExtraData.video(_cfg.codec, bytes);
      }
    } finally {
      _ff.avcodecParametersFree(pp);
      calloc.free(pp);
    }
  }

  EncodedPacket? _drainOne() {
    final ret = _ff.avcodecReceivePacket(_codecCtx, _packet);
    if (ret == kAvErrorEAgain || ret == kAvErrorEof) return null;
    if (ret < 0) {
      throw CodecRuntimeException(
        'ffmpeg',
        'avcodec_receive_packet: ${_ff.strError(ret)} ($ret)',
      );
    }
    final p = _packet.ref;
    final bytes = Uint8List(p.size);
    final src = p.data.asTypedList(p.size);
    bytes.setRange(0, p.size, src);

    // FFmpeg encoder time_base = 1/framerate (we set it above), so pts
    // is in frame units. Convert to microseconds.
    final usPerFrame =
        (1000000 * _cfg.frameRateDenominator) ~/ _cfg.frameRateNumerator;
    final pktOut = EncodedPacket(
      data: bytes,
      ptsUs: p.pts * usPerFrame,
      dtsUs: (p.dts == _avNoPts ? p.pts : p.dts) * usPerFrame,
      durationUs: p.duration * usPerFrame,
      isKeyframe: (p.flags & kPktFlagKey) != 0,
    );
    _ff.avPacketUnref(_packet);
    return pktOut;
  }

  PreparedYuv420p _frameToYuv420p(FrameSource src) {
    switch (src) {
      case CpuFrameSource():
        return toYuv420p(
          src: src.bytes,
          format: src.pixelFormat,
          width: src.width,
          height: src.height,
          strides: src.strideBytes,
        );
      case MiniAVBufferSource():
        // Extract the first plane's bytes for CPU buffers.
        final video = src.buffer.data;
        if (video is! MiniAVVideoBuffer) {
          throw const CodecRuntimeException('ffmpeg', 'expected video buffer');
        }
        final bytes = video.planes.isNotEmpty ? video.planes[0] : null;
        if (bytes == null) {
          throw const CodecRuntimeException(
            'ffmpeg',
            'MiniAVBufferSource: only CPU plane bytes are supported by '
                'the software encoder MVP (plane[0] was null — likely a '
                'GPU-backed buffer)',
          );
        }
        return toYuv420p(
          src: bytes,
          format: video.pixelFormat,
          width: video.width,
          height: video.height,
          strides: video.strideBytes,
        );
      default:
        throw CodecRuntimeException(
          'ffmpeg',
          'FfmpegSoftwareEncoder MVP only accepts CpuFrameSource or '
              'MiniAVBufferSource (CPU). Got: ${src.runtimeType}',
        );
    }
  }
}

/// Sentinel for AV_NOPTS_VALUE (INT64_MIN).
const int _avNoPts = -0x8000000000000000;

void _copyPlane(
  Pointer<Uint8> dst,
  int dstStride,
  Uint8List src,
  int width,
  int height,
) {
  final dstView = dst.asTypedList(dstStride * height);
  for (var row = 0; row < height; row++) {
    dstView.setRange(
      row * dstStride,
      row * dstStride + width,
      src,
      row * width,
    );
  }
}

/// Helper: returns a pointer literal at a fixed address. We use this to
/// compare opaque pointers to NULL in a way the analyzer doesn't flag.
Pointer<T> address<T extends NativeType>(int addr) =>
    Pointer<T>.fromAddress(addr);
