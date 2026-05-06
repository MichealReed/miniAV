/// FFmpeg libavformat muxer (Phase C).
///
/// MVP scope:
///   - File output ([FileMuxerOutput]) only — bytes/callback outputs require
///     a custom AVIOContext and are deferred.
///   - Single video track per file (most common case for MP4 from a single
///     encoder). Audio + multi-track come later.
///   - Stream time_base = 1/1_000_000 (microseconds), so packet pts/dts pass
///     through directly without rescaling.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

import 'ffmpeg_encoder.dart';
import 'ffmpeg_ffi.dart';

/// Tiny bridge interface implemented by both [FfmpegSoftwareEncoder] and
/// [FfmpegNvencEncoder] so the muxer can pull `extradata` (SPS/PPS) and
/// codec parameters straight from the encoder's `AVCodecContext`.
abstract class FfmpegEncoderBridge {
  Pointer<AVCodecContext> get nativeCodecContext;
}

/// Map our [Container] enum to an FFmpeg short-name string for
/// `avformat_alloc_output_context2`.
String _containerName(Container c) {
  switch (c) {
    case Container.mp4:
      return 'mp4';
    case Container.fmp4:
      return 'mp4'; // fragmented mode controlled via movflags option
    case Container.mkv:
      return 'matroska';
    case Container.webm:
      return 'webm';
    case Container.mpegts:
      return 'mpegts';
    case Container.ogg:
      return 'ogg';
    case Container.wav:
      return 'wav';
    case Container.raw:
      return 'mpegts'; // not really right; raw needs codec-specific fmt
  }
}

/// Map our [VideoCodec] enum to AVCodecID.
int _videoCodecToId(VideoCodec c) {
  switch (c) {
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
      throw CodecInitException('ffmpeg', 'muxer: unsupported VideoCodec.$c');
  }
}

const int _avMediaTypeVideo = 0;
const int _avMediaTypeAudio = 1;

class FfmpegMuxer implements PlatformMuxer {
  FfmpegMuxer._(
    this._ff,
    this._cfg,
    this._fmtCtx,
    this._streams,
    this._extradataAllocs,
  );

  final Ffmpeg _ff;
  final MuxerConfig _cfg;
  Pointer<AVFormatContext> _fmtCtx;
  final List<Pointer<AVStream>> _streams;
  final List<Pointer<Uint8>> _extradataAllocs;

  /// Tracked AVIOContext so we can close it explicitly on tear-down.
  Pointer<AVIOContext> _avio = nullptr;

  bool _headerWritten = false;
  bool _trailerWritten = false;
  bool _closed = false;

  /// Bridge: optionally pre-bind an encoder (software or NVENC) to a track
  /// index so the muxer can pull extradata directly from its native codec
  /// context (preserves SPS/PPS for libx264/NVENC with global_header set).
  ///
  /// Otherwise the muxer relies on [VideoTrackInfo.extraData].
  static FfmpegMuxer open(
    MuxerConfig cfg, {
    Map<int, FfmpegEncoderBridge>? encoderForTrack,
  }) {
    final ff = Ffmpeg.instance();
    if (ff == null) {
      throw const CodecInitException(
        'ffmpeg',
        'FFmpeg not loaded — call ensureFFmpegLoaded() first',
      );
    }
    if (!ff.hasAvformat) {
      throw const CodecInitException(
        'ffmpeg',
        'libavformat not loaded — muxing requires the avformat shared lib',
      );
    }
    final out = cfg.output;
    if (out is! FileMuxerOutput) {
      throw CodecInitException(
        'ffmpeg',
        'FfmpegMuxer MVP only supports FileMuxerOutput; got ${out.runtimeType}',
      );
    }

    // 1. avformat_alloc_output_context2(&fmtCtx, NULL, fmtName, filename)
    final pFmtCtx = calloc<Pointer<AVFormatContext>>();
    final fmtName = _containerName(cfg.container).toNativeUtf8();
    final filename = out.path.toNativeUtf8();
    final extradataAllocs = <Pointer<Uint8>>[];
    final streams = <Pointer<AVStream>>[];
    Pointer<AVFormatContext> fmtCtx = nullptr;
    try {
      final ret = ff.avformatAllocOutputContext2(
        pFmtCtx,
        nullptr,
        fmtName,
        filename,
      );
      if (ret < 0 || pFmtCtx.value == nullptr) {
        throw CodecInitException(
          'ffmpeg',
          'avformat_alloc_output_context2 failed: ${ff.strError(ret)} ($ret)',
        );
      }
      fmtCtx = pFmtCtx.value;

      // 2. For each track: avformat_new_stream + populate codecpar.
      for (var i = 0; i < cfg.tracks.length; i++) {
        final track = cfg.tracks[i];
        final stream = ff.avformatNewStream(fmtCtx, nullptr);
        if (stream == nullptr) {
          throw const CodecInitException(
            'ffmpeg',
            'avformat_new_stream returned NULL',
          );
        }
        streams.add(stream);

        // Stream time_base = microseconds.
        stream.ref
          ..timeBaseNum = 1
          ..timeBaseDen = 1000000;

        final codecpar = stream.ref.codecpar;
        if (codecpar == nullptr) {
          throw const CodecInitException('ffmpeg', 'AVStream.codecpar is NULL');
        }

        // Prefer pulling parameters straight from the encoder context
        // (preserves extradata + correct codec_tag for the format).
        final boundEnc = encoderForTrack?[i];
        if (boundEnc != null) {
          final r = ff.avcodecParametersFromContext(
            codecpar,
            boundEnc.nativeCodecContext,
          );
          if (r < 0) {
            throw CodecInitException(
              'ffmpeg',
              'avcodec_parameters_from_context failed: ${ff.strError(r)} ($r)',
            );
          }
          // Reset codec_tag — let the muxer pick the right tag for this
          // container (e.g. avc1 for mp4/h264).
          codecpar.ref.codecTag = 0;
        } else {
          _fillCodecparFromTrack(ff, codecpar, track, extradataAllocs);
        }
      }

      return FfmpegMuxer._(ff, cfg, fmtCtx, streams, extradataAllocs);
    } catch (_) {
      if (fmtCtx != nullptr) {
        ff.avformatFreeContext(fmtCtx);
      }
      for (final p in extradataAllocs) {
        calloc.free(p);
      }
      rethrow;
    } finally {
      calloc.free(pFmtCtx);
      calloc.free(fmtName);
      calloc.free(filename);
    }
  }

  static void _fillCodecparFromTrack(
    Ffmpeg ff,
    Pointer<AVCodecParameters> codecpar,
    TrackInfo track,
    List<Pointer<Uint8>> extradataAllocs,
  ) {
    final ref = codecpar.ref;
    if (track is VideoTrackInfo) {
      ref
        ..codecType = _avMediaTypeVideo
        ..codecId = _videoCodecToId(track.codec)
        ..codecTag = 0
        ..width = track.width
        ..height = track.height
        ..format = AVPixelFormat.yuv420p
        ..frNum = track.frameRateNumerator
        ..frDen = track.frameRateDenominator;
      final ed = track.extraData;
      if (ed != null && ed.bytes.isNotEmpty) {
        // FFmpeg requires extradata buffer to have AV_INPUT_BUFFER_PADDING_SIZE
        // (=64) bytes of zero padding. We over-allocate accordingly.
        const pad = 64;
        final buf = calloc<Uint8>(ed.bytes.length + pad);
        buf.asTypedList(ed.bytes.length).setAll(0, ed.bytes);
        ref
          ..extradata = buf
          ..extradataSize = ed.bytes.length;
        extradataAllocs.add(buf);
      }
    } else if (track is AudioTrackInfo) {
      // Audio tracks REQUIRE a bound encoder (passed via
      // FfmpegMuxer.open(encoderForTrack: ...)). The Dart-side
      // AVCodecParameters prefix doesn't expose sample_rate / channels /
      // ch_layout, so we can't synthesize codecpar for audio without
      // pulling it from a live AVCodecContext.
      throw const CodecInitException(
        'ffmpeg',
        'Audio tracks must be bound to a FfmpegAudioEncoder via '
            'FfmpegMuxer.open(..., encoderForTrack: {trackIndex: encoder}). '
            'Standalone AudioTrackInfo without a bound encoder is not '
            'supported because AVChannelLayout setup requires a live '
            'AVCodecContext.',
      );
    }
  }

  @override
  Future<void> writeHeader() async {
    _checkOpen();
    if (_headerWritten) return;
    final out = _cfg.output as FileMuxerOutput;

    // Open the output file via avio_open. (We only reach this for non-
    // AVFMT_NOFILE muxers — mp4/mkv/webm all need it.)
    final pIo = calloc<Pointer<AVIOContext>>();
    final fname = out.path.toNativeUtf8();
    try {
      final r = _ff.avioOpen(pIo, fname, kAvioFlagWrite);
      if (r < 0) {
        throw CodecInitException(
          'ffmpeg',
          'avio_open(${out.path}) failed: ${_ff.strError(r)} ($r)',
        );
      }
      _avio = pIo.value;
      // Wire the AVIOContext into AVFormatContext.pb directly (it's a
      // plain struct field, not an AVOption).
      _fmtCtx.cast<AVFormatContextPrefix>().ref.pb = _avio;
    } finally {
      calloc.free(fname);
      calloc.free(pIo);
    }

    final wr = _ff.avformatWriteHeader(_fmtCtx, nullptr);
    if (wr < 0) {
      throw CodecInitException(
        'ffmpeg',
        'avformat_write_header failed: ${_ff.strError(wr)} ($wr)',
      );
    }
    _headerWritten = true;
  }

  @override
  Future<void> writePacket(EncodedPacket packet) async {
    _checkOpen();
    if (!_headerWritten) {
      throw const CodecRuntimeException(
        'ffmpeg',
        'writePacket called before writeHeader',
      );
    }
    final pkt = _ff.avPacketAlloc();
    if (pkt == nullptr) {
      throw const CodecRuntimeException(
        'ffmpeg',
        'av_packet_alloc returned NULL',
      );
    }
    // Allocate a native buffer for the packet payload. FFmpeg requires
    // AV_INPUT_BUFFER_PADDING_SIZE (=64) bytes of zero padding.
    const pad = 64;
    final buf = calloc<Uint8>(packet.data.length + pad);
    buf.asTypedList(packet.data.length).setAll(0, packet.data);

    pkt.ref
      ..data = buf
      ..size = packet.data.length
      ..pts = packet.ptsUs
      ..dts = packet.dtsUs == 0 ? packet.ptsUs : packet.dtsUs
      ..duration = packet.durationUs
      ..streamIndex = packet.trackIndex
      ..flags = packet.isKeyframe ? kPktFlagKey : 0
      ..timeBaseNum = 1
      ..timeBaseDen = 1000000;

    try {
      final r = _ff.avInterleavedWriteFrame(_fmtCtx, pkt);
      if (r < 0) {
        throw CodecRuntimeException(
          'ffmpeg',
          'av_interleaved_write_frame failed: ${_ff.strError(r)} ($r)',
        );
      }
    } finally {
      // av_interleaved_write_frame takes ownership of *referenced* packets but
      // for our raw-buffer packet we must free both packet & buffer ourselves
      // after the call. Unref first, then free pkt struct.
      _ff.avPacketUnref(pkt);
      final pp = calloc<Pointer<AVPacket>>()..value = pkt;
      _ff.avPacketFree(pp);
      calloc.free(pp);
      calloc.free(buf);
    }
  }

  @override
  Future<void> finish() async {
    _checkOpen();
    if (!_headerWritten || _trailerWritten) return;
    // Flush interleaving queue.
    final fr = _ff.avInterleavedWriteFrame(_fmtCtx, nullptr);
    // Negative return on flush is non-fatal for some muxers — ignore.
    if (fr < 0 && fr != kAvErrorEof) {
      // best-effort; continue to write trailer
    }
    final r = _ff.avWriteTrailer(_fmtCtx);
    if (r < 0) {
      throw CodecRuntimeException(
        'ffmpeg',
        'av_write_trailer failed: ${_ff.strError(r)} ($r)',
      );
    }
    _trailerWritten = true;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (_avio != nullptr) {
      final pp = calloc<Pointer<AVIOContext>>()..value = _avio;
      try {
        _ff.avioClosep(pp);
      } finally {
        calloc.free(pp);
      }
      _avio = nullptr;
    }
    if (_fmtCtx != nullptr) {
      _ff.avformatFreeContext(_fmtCtx);
      _fmtCtx = nullptr;
    }
    for (final p in _extradataAllocs) {
      calloc.free(p);
    }
    _extradataAllocs.clear();
    _streams.clear();
  }

  @override
  List<int>? getBytes() => null;

  void _checkOpen() {
    if (_closed) {
      throw const CodecRuntimeException('ffmpeg', 'muxer closed');
    }
  }
}
