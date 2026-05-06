/// Software FFmpeg decoder (libavcodec) — Phase A.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

import 'ffmpeg_encoder.dart' show address;
import 'ffmpeg_ffi.dart';

class FfmpegSoftwareDecoder implements PlatformDecoder {
  FfmpegSoftwareDecoder._(this._ff, this._codecCtx, this._frame, this._packet);

  final Ffmpeg _ff;
  final Pointer<AVCodecContext> _codecCtx;
  final Pointer<AVFrame> _frame;
  final Pointer<AVPacket> _packet;

  bool _closed = false;

  static FfmpegSoftwareDecoder open(DecoderConfig cfg) {
    final ff = Ffmpeg.instance();
    if (ff == null) {
      throw const CodecInitException(
        'ffmpeg',
        'FFmpeg not loaded — call ensureFFmpegLoaded() first',
      );
    }
    final codec = ff.avcodecFindDecoder(_videoCodecToAvId(cfg.codec));
    if (codec == address(0)) {
      throw CodecInitException(
        'ffmpeg',
        'No decoder registered for ${cfg.codec}',
      );
    }
    final codecCtx = ff.avcodecAllocContext3(codec);
    if (codecCtx == address(0)) {
      throw const CodecInitException(
        'ffmpeg',
        'avcodec_alloc_context3 returned NULL',
      );
    }
    try {
      // Pass extradata via av_opt where possible. For codecs that need it as
      // a raw buffer (H.264 avcC), users should call this with extraData
      // already prepended to the first packet (Annex-B style works).
      final ret = ff.avcodecOpen2(codecCtx, codec, nullptr);
      if (ret < 0) {
        throw CodecInitException(
          'ffmpeg',
          'avcodec_open2 (decoder): ${ff.strError(ret)}',
        );
      }
      final frame = ff.avFrameAlloc();
      final packet = ff.avPacketAlloc();
      return FfmpegSoftwareDecoder._(ff, codecCtx, frame, packet);
    } catch (_) {
      final ptr = calloc<Pointer<AVCodecContext>>()..value = codecCtx;
      ff.avcodecFreeContext(ptr);
      calloc.free(ptr);
      rethrow;
    }
  }

  @override
  Future<DecodedFrame?> decode(EncodedPacket packet) async {
    _checkOpen();
    final size = packet.data.length;
    final buf = calloc<Uint8>(size);
    try {
      buf.asTypedList(size).setRange(0, size, packet.data);
      _packet.ref
        ..data = buf
        ..size = size
        ..pts = packet.ptsUs
        ..dts = packet.dtsUs == 0 ? packet.ptsUs : packet.dtsUs
        ..flags = packet.isKeyframe ? kPktFlagKey : 0;
      final ret = _ff.avcodecSendPacket(_codecCtx, _packet);
      if (ret < 0 && ret != kAvErrorEAgain) {
        throw CodecRuntimeException(
          'ffmpeg',
          'avcodec_send_packet: ${_ff.strError(ret)}',
        );
      }
    } finally {
      // The packet is consumed by libavcodec immediately (or queued); we
      // can release our copy now since we always reset .data on next call.
      calloc.free(buf);
      _packet.ref.data = nullptr;
      _packet.ref.size = 0;
    }
    return _drainOne();
  }

  @override
  Future<List<DecodedFrame>> flush() async {
    _checkOpen();
    final ret = _ff.avcodecSendPacket(_codecCtx, nullptr);
    if (ret < 0 && ret != kAvErrorEof) {
      throw CodecRuntimeException(
        'ffmpeg',
        'avcodec_send_packet(NULL): ${_ff.strError(ret)}',
      );
    }
    final out = <DecodedFrame>[];
    while (true) {
      final f = _drainOne();
      if (f == null) break;
      out.add(f);
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

  void _checkOpen() {
    if (_closed) {
      throw const CodecRuntimeException('ffmpeg', 'decoder closed');
    }
  }

  DecodedFrame? _drainOne() {
    final ret = _ff.avcodecReceiveFrame(_codecCtx, _frame);
    if (ret == kAvErrorEAgain || ret == kAvErrorEof) return null;
    if (ret < 0) {
      throw CodecRuntimeException(
        'ffmpeg',
        'avcodec_receive_frame: ${_ff.strError(ret)}',
      );
    }
    final f = _frame.ref;
    // Copy out the YUV420P planes into Dart-owned bytes so the caller can
    // hold the frame past the next decode() call.
    final w = f.width;
    final h = f.height;
    final yLen = w * h;
    final cLen = (w * h) ~/ 4;
    final out = Uint8List(yLen + 2 * cLen);
    _copyPlaneOut(out, 0, f.data0, f.linesize0, w, h);
    _copyPlaneOut(out, yLen, f.data1, f.linesize1, w ~/ 2, h ~/ 2);
    _copyPlaneOut(out, yLen + cLen, f.data2, f.linesize2, w ~/ 2, h ~/ 2);
    final usPerFrame = (1000000 * 1) ~/ 30; // unknown FR; punt to 30 fps grid
    return _Yuv420pFrame(
      width: w,
      height: h,
      ptsUs: f.pts == _avNoPts ? 0 : f.pts * usPerFrame,
      bytes: out,
    );
  }
}

const int _avNoPts = -0x8000000000000000;

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
      throw CodecInitException('ffmpeg', 'unsupported decoder codec: $codec');
  }
}

void _copyPlaneOut(
  Uint8List dst,
  int dstOff,
  Pointer<Uint8> src,
  int srcStride,
  int w,
  int h,
) {
  final view = src.asTypedList(srcStride * h);
  for (var row = 0; row < h; row++) {
    dst.setRange(dstOff + row * w, dstOff + row * w + w, view, row * srcStride);
  }
}

class _Yuv420pFrame implements DecodedFrame {
  _Yuv420pFrame({
    required this.width,
    required this.height,
    required this.ptsUs,
    required Uint8List bytes,
  }) : _bytes = bytes;

  @override
  final int width;
  @override
  final int height;
  @override
  final int ptsUs;
  final Uint8List _bytes;

  @override
  Future<List<int>> readBytes() async => _bytes;

  @override
  void close() {}
}
