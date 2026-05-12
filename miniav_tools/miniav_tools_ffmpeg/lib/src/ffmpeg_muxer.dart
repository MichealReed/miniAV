/// FFmpeg libavformat muxer (Phase C).
///
/// MVP scope:
///   - File output ([FileMuxerOutput]) only — bytes/callback outputs require
///     a custom AVIOContext and are deferred.
///   - Single video track per file (most common case for MP4 from a single
///     encoder). Audio + multi-track come later.
///   - Input packet timestamps are always in microseconds (1/1_000_000).
///     avformat_write_header may change AVStream.time_base to a codec-native
///     value (e.g. 1/sample_rate for AAC, 1/12800 for H.264 in MP4). After
///     writeHeader we read back each stream's real time_base and use it to
///     manually rescale every packet's pts/dts/duration before calling
///     av_interleaved_write_frame. We do not rely on FFmpeg's automatic
///     rescale-from-pkt.time_base path because it is not honoured by all
///     mux implementations / builds.
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
    case Container.m4a:
      return 'ipod'; // libavformat's name for the MPEG-4 audio (.m4a) muxer
    case Container.mp3:
      return 'mp3';
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

  /// Per-stream time_base captured immediately after avformat_write_header.
  /// Indexed by stream / track index. Defaults to {1, 1_000_000} until the
  /// header is written.
  List<int> _streamTbNum = const [];
  List<int> _streamTbDen = const [];

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

      // Tell the muxer to shift any negative timestamps up to zero AND
      // emit an edit list (in MP4) so players skip the shifted-in preroll.
      // This lets us pass a GOP head with negative pts (the frames between
      // the keyframe and the actual clip start) and still get a precisely
      // trimmed visible duration.
      //   avoid_negative_ts: -1=auto 0=disabled 1=make_non_negative 2=make_zero
      {
        final optName = 'avoid_negative_ts'.toNativeUtf8();
        try {
          ff.avOptSetInt(fmtCtx.cast(), optName, 2, 0);
        } finally {
          calloc.free(optName);
        }
      }

      // For MP4/M4A: move the moov atom to the front of the file (faststart).
      // By default FFmpeg writes moov at the end, which means Windows Explorer
      // (and any tool that reads only the beginning) cannot show duration,
      // codec, or file-size metadata until a full seek to the end is done.
      // With +faststart, av_write_trailer rewrites the file so moov is first —
      // the OS sees full metadata immediately after the clip is saved.
      // NOTE: do NOT apply this to fmp4 (fragmented MP4) because fragmented
      // streams use a different movflags set and moov is written up-front
      // anyway via the fragment mechanism.
      if (cfg.container == Container.mp4 || cfg.container == Container.m4a) {
        final privData = fmtCtx.cast<AVFormatContextPrefix>().ref.privData;
        if (privData != nullptr) {
          final optName = 'movflags'.toNativeUtf8();
          final optVal = '+faststart'.toNativeUtf8();
          try {
            ff.avOptSet(privData, optName, optVal, 0);
          } finally {
            calloc.free(optName);
            calloc.free(optVal);
          }
        }
      }

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
        // (=64) bytes of zero padding AND it MUST be allocated by FFmpeg's
        // allocator (av_mallocz) — otherwise avformat_free_context will
        // av_free() a Dart-heap pointer and crash on Windows.
        const pad = 64;
        final buf = ff.avMallocZ(ed.bytes.length + pad);
        if (buf == nullptr) {
          throw const CodecInitException(
            'ffmpeg',
            'av_mallocz failed for extradata',
          );
        }
        buf.asTypedList(ed.bytes.length).setAll(0, ed.bytes);
        ref
          ..extradata = buf
          ..extradataSize = ed.bytes.length;
        // Ownership is now with libavformat; do NOT add to extradataAllocs.
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

    // Snapshot the actual per-stream time_bases. avformat_write_header may
    // have replaced our 1/1_000_000 with a codec-native value (e.g. 1/48000
    // for AAC, 1/12800 for H.264 in MP4). writePacket uses these to rescale.
    _streamTbNum = [for (final s in _streams) s.ref.timeBaseNum];
    _streamTbDen = [for (final s in _streams) s.ref.timeBaseDen];
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

    // Rescale timestamps from microseconds to the stream's real time_base.
    // Formula: out = us * tbDen / (1_000_000 * tbNum)
    // For the common case tbNum == 1: out = us * tbDen / 1_000_000.
    //
    // Worst-case overflow: 24h × 1_000_000 × 90_000 ≈ 7.8 × 10^15 < 2^63. ✓
    final si = packet.trackIndex;
    final tbNum = (si >= 0 && si < _streamTbNum.length) ? _streamTbNum[si] : 1;
    final tbDen = (si >= 0 && si < _streamTbDen.length)
        ? _streamTbDen[si]
        : 1000000;
    // Defensive: if read-back returned garbage (zero/negative) fall back
    // to microseconds so we still write *something* the player can consume.
    final safeTbNum = tbNum > 0 ? tbNum : 1;
    final safeTbDen = tbDen > 0 ? tbDen : 1000000;
    int rescaleUs(int us) {
      if (safeTbNum == 1 && safeTbDen == 1000000) return us;
      return us * safeTbDen ~/ (1000000 * safeTbNum);
    }

    final rawDts = packet.dtsUs;
    final ptsOut = rescaleUs(packet.ptsUs);
    final dtsOut = rescaleUs(rawDts);
    final durOut = rescaleUs(packet.durationUs);

    pkt.ref
      ..data = buf
      ..size = packet.data.length
      ..pts = ptsOut
      ..dts = dtsOut
      ..duration = durOut
      ..streamIndex = packet.trackIndex
      ..flags = packet.isKeyframe ? kPktFlagKey : 0
      // Match the stream time_base so any FFmpeg auto-rescale is a no-op.
      ..timeBaseNum = safeTbNum
      ..timeBaseDen = safeTbDen;

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
