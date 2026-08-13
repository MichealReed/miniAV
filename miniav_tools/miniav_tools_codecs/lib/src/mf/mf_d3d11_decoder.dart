/// Media Foundation hardware H.264/HEVC decoder producing D3D11 NV12 textures
/// (Windows only). Drives the FFmpeg-free `native/mf_decoder.c` via the
/// standalone `codecs_native` asset — no FFmpeg dependency.
///
/// Each decoded frame is a GPU-resident NV12 texture (exposed via
/// [DecodedFrame.outputKind] == `d3d11Texture` + [DecodedFrame.gpuHandle]); the
/// player imports the shared handle straight into Dawn (no CPU readback).
/// [DecodedFrame.readBytes] maps it to CPU (NV12→I420) as a software fallback.
///
/// **Frame-size contract.** [DecodedFrame.width]/[DecodedFrame.height] are the
/// DISPLAY size — the bitstream's crop window (H.264 frame cropping / HEVC
/// conformance window). Video codes in macroblocks/CTUs, so the decoder's
/// surface is the CODED size, padded up (240 → 256 in HEVC, 1080 → 1088, 200 →
/// 208 in H.264) with decoder garbage in the padding.
///
///  * `readBytes()` returns the display region only, padding excluded:
///    `width * height + 2 * ceil(width / 2) * ceil(height / 2)`, i.e. exactly
///    `width * height * 3 / 2` for the even display sizes 4:2:0 crop windows
///    can express.
///  * The D3D11 texture behind [DecodedFrame.gpuHandle] stays CODED size, with
///    the valid region at the top-left (the crop origin is 0,0 for every
///    stream a codec can produce; a non-zero origin is honoured by the CPU map
///    but would need a source offset in a GPU consumer). Import it with the
///    frame's `width`/`height`, NOT the texture's own dimensions: NV12 plane
///    views are addressed from the top-left, so the reported size selects the
///    valid region. Copying the texture wholesale would show the padding.
///
/// Only ever constructed when a hardware decoder MFT exists — [open] returns
/// `null` otherwise (and on a non-MTA/STA thread), so the facade negotiator
/// falls back to the software decoder for free.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

import '../codecs_native.dart';
import '../framing/annexb.dart' show hevcCodedSizeFromAnnexB, isAnnexB;

int? _codecId(VideoCodec codec) => switch (codec) {
  VideoCodec.h264 => 0,
  VideoCodec.hevc => 1,
  _ => null,
};

class MfD3d11Decoder implements PlatformDecoder {
  final Pointer<Void> _session;
  final Pointer<MiniAVMfDecFrame> _out;

  /// avcC/hvcC parameter sets converted to Annex-B, prepended to keyframes when
  /// the bitstream is length-prefixed (`null` = feed packets verbatim).
  final Uint8List? _annexBHeaders;
  final int _lengthSize; // 0 = Annex-B (feed raw); >0 = length-prefixed NALs

  bool _closed = false;
  bool _sentHeaders = false;

  MfD3d11Decoder._(
    this._session,
    this._out,
    this._annexBHeaders,
    this._lengthSize,
  );

  /// Open a hardware MF decode session for [config]. Returns `null` when the
  /// codec isn't H.264/HEVC, the native codecs asset isn't loadable, no
  /// hardware MFT exists, the calling thread is STA (MF needs MTA), or the
  /// codec is HEVC and no frame size can be established — neither from
  /// [DecoderConfig.width]/[DecoderConfig.height] nor from the SPS in
  /// [DecoderConfig.extraData] (see below). Each of those makes the facade
  /// negotiator fall back.
  static Future<MfD3d11Decoder?> open(DecoderConfig config) async {
    if (!Platform.isWindows) return null;
    final codec = _codecId(config.codec);
    if (codec == null) return null;

    // The codecs_native asset is FFmpeg-free; a hardware check that throws
    // (asset not loadable) or returns false → SW fallback.
    try {
      if (!mfdecHasHardware(codec)) return null;
    } catch (_) {
      return null;
    }

    // Decide the bitstream framing from the extradata. avcC/hvcC (first byte
    // 0x01) means length-prefixed NAL units — convert to Annex-B on the fly.
    final extra = config.extraData;
    var lengthSize = 0;
    Uint8List? headers;
    if (extra != null && extra.isNotEmpty && extra[0] == 1) {
      final parsed = config.codec == VideoCodec.hevc
          ? _parseHvcc(extra)
          : _parseAvcc(extra);
      if (parsed != null) {
        lengthSize = parsed.lengthSize;
        headers = parsed.annexBHeaders;
      }
    }

    var width = config.width ?? 0;
    var height = config.height ?? 0;

    // The HEVC decoder MFT REQUIRES MF_MT_FRAME_SIZE on its input type
    // (mf_decoder.c/mfdec_configure_input): without it, it cannot propose an
    // output type and rejects EVERY ProcessInput with
    // MF_E_TRANSFORM_TYPE_NOT_SET — but mfdecCreate still succeeds, so the
    // negotiator would commit to a decoder that only ever returns null, and the
    // caller gets a black screen with no error. (H.264 is untouched throughout:
    // its MFT parses the SPS in-band and needs no hint.)
    //
    // When the caller has no dims but did carry parameter sets, the size is in
    // them — harvest the CODED size from the SPS and hint with that. Coded, not
    // display: the input type describes the CTU grid, and the MFT still derives
    // the display aperture from the conformance window itself, so the frames
    // this decoder reports stay cropped exactly as before.
    //
    // `headers` covers the hvcC case (a demuxer's out-of-band record); raw
    // Annex-B extradata (what the MF encoder's sequence header is) carries the
    // same SPS and is read directly — it is left out of `headers` only because
    // that path feeds packets verbatim.
    if (config.codec == VideoCodec.hevc && (width <= 0 || height <= 0)) {
      final paramSets = headers ??
          (extra != null && isAnnexB(extra) ? extra : null);
      final coded =
          paramSets == null ? null : hevcCodedSizeFromAnnexB(paramSets);
      if (coded != null) {
        width = coded.width;
        height = coded.height;
      }
    }

    // Still no size (no extradata, or an SPS that did not parse) → decline, so
    // the facade falls through to the software decoder, which reads the dims
    // out of the bitstream itself.
    if (config.codec == VideoCodec.hevc && (width <= 0 || height <= 0)) {
      return null;
    }

    // Let the session create its own hardware D3D11 device (nullptr) on the
    // primary adapter — the player's Dawn is on the same adapter, so the shared
    // handle opens there. Coded-dims hint: required by the HEVC decoder MFT
    // (frame size on the input type), harmless for H.264.
    final session = mfdecCreate(nullptr, codec, nullptr, 0,
        width: width, height: height);
    if (session == nullptr) return null;

    final out = calloc<MiniAVMfDecFrame>();
    return MfD3d11Decoder._(session, out, headers, lengthSize);
  }

  @override
  Future<DecodedFrame?> decode(EncodedPacket packet) async {
    _checkOpen();
    final annexB = _toAnnexB(packet.data, packet.isKeyframe);
    final buf = calloc<Uint8>(annexB.length);
    buf.asTypedList(annexB.length).setAll(0, annexB);
    try {
      mfdecSend(
        _session,
        buf,
        annexB.length,
        packet.ptsUs,
        packet.isKeyframe,
      );
    } finally {
      calloc.free(buf);
    }
    final rc = mfdecReceive(_session, _out);
    if (rc != 1) return null; // buffering / need more input
    return _frameFromOut();
  }

  @override
  Future<List<DecodedFrame>> flush() async {
    _checkOpen();
    mfdecDrain(_session);
    final frames = <DecodedFrame>[];
    // Drain-collected frames were queued native-side; poll them out.
    for (var guard = 0; guard < 8192; guard++) {
      final rc = mfdecReceive(_session, _out);
      if (rc != 1) break;
      frames.add(_frameFromOut());
    }
    return frames;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    mfdecDestroy(_session);
    calloc.free(_out);
  }

  _MfD3d11Frame _frameFromOut() => _MfD3d11Frame(
    session: _session,
    sharedHandle: _out.ref.outSharedHandle,
    texturePtr: _out.ref.outTexturePtr,
    width: _out.ref.width,
    height: _out.ref.height,
    cropX: _out.ref.cropX,
    cropY: _out.ref.cropY,
    ptsUs: _out.ref.ptsUs,
  );

  /// Convert one packet to Annex-B. Length-prefixed input is rewritten to
  /// start-code framing; keyframes get the parameter sets prepended once.
  Uint8List _toAnnexB(Uint8List data, bool isKeyframe) {
    if (_lengthSize == 0) {
      // Already Annex-B (or the MFT will accept the raw feed). Prepend headers
      // to the first keyframe if we somehow have them out-of-band.
      if (_annexBHeaders != null && isKeyframe && !_sentHeaders) {
        _sentHeaders = true;
        return Uint8List.fromList([..._annexBHeaders, ...data]);
      }
      return data;
    }
    final out = BytesBuilder(copy: false);
    if (_annexBHeaders != null && isKeyframe && !_sentHeaders) {
      _sentHeaders = true;
      out.add(_annexBHeaders);
    }
    var i = 0;
    while (i + _lengthSize <= data.length) {
      var nalLen = 0;
      for (var k = 0; k < _lengthSize; k++) {
        nalLen = (nalLen << 8) | data[i + k];
      }
      i += _lengthSize;
      if (nalLen <= 0 || i + nalLen > data.length) break;
      out.add(const [0, 0, 0, 1]);
      out.add(data.sublist(i, i + nalLen));
      i += nalLen;
    }
    return out.toBytes();
  }

  void _checkOpen() {
    if (_closed) throw StateError('MfD3d11Decoder has been closed.');
  }
}

/// A decoded frame backed by a shareable D3D11 NV12 texture + NT handle.
class _MfD3d11Frame implements DecodedFrame {
  final Pointer<Void> _session;
  final int _sharedHandle;
  final int _texturePtr;

  /// Display-region origin inside the coded texture (0,0 in practice).
  final int _cropX;
  final int _cropY;
  bool _closed = false;

  @override
  final int width;
  @override
  final int height;
  @override
  final int ptsUs;

  _MfD3d11Frame({
    required Pointer<Void> session,
    required int sharedHandle,
    required int texturePtr,
    required this.width,
    required this.height,
    required int cropX,
    required int cropY,
    required this.ptsUs,
  }) : _session = session,
       _sharedHandle = sharedHandle,
       _texturePtr = texturePtr,
       _cropX = cropX,
       _cropY = cropY;

  @override
  FrameSourceKind get outputKind => FrameSourceKind.d3d11Texture;

  @override
  int get gpuHandle => _sharedHandle;

  @override
  int get subresourceIndex => 0;

  @override
  Object? get webVideoFrame => null;

  // GPU-resident (routed by outputKind/gpuHandle); readBytes converts to I420.
  @override
  DecodedPixelLayout get pixelLayout => DecodedPixelLayout.i420;
  @override
  bool get isFullRange => false;
  @override
  YuvColorMatrix get colorMatrix => YuvColorMatrix.bt601;

  /// Map the NV12 texture to CPU and convert to I420 for the player's existing
  /// YUV→RGBA path (Milestone 1). Milestone 2 skips this via a GPU import.
  ///
  /// Only the display region is copied out — the texture is coded-size, so a
  /// whole-texture map would append the block-padding rows to the picture.
  @override
  Future<List<int>> readBytes() async {
    final needed = width * height + (width * ((height + 1) ~/ 2));
    final dst = calloc<Uint8>(needed);
    try {
      final n = mfdecMapNv12Region(
        _session,
        _texturePtr,
        _cropX,
        _cropY,
        width,
        height,
        dst,
        needed,
      );
      if (n < 0) {
        throw StateError('mfdec_map_nv12_region failed ($n)');
      }
      final nv12 = Uint8List.fromList(dst.asTypedList(n));
      return _nv12ToI420(nv12, width, height);
    } finally {
      calloc.free(dst);
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    mfdecReleaseFrame(_session, _sharedHandle, _texturePtr);
  }
}

/// NV12 (Y plane, then interleaved UV) → I420 (Y, U, V planes).
///
/// Chroma row/column counts are the same CEILING the native map uses
/// (`mfdec_map_region` writes `(h + 1) / 2` UV rows of `w` bytes); an odd
/// extent would otherwise leave the last row/column of the source unread and
/// the two halves of the round-trip disagreeing about the plane size.
Uint8List _nv12ToI420(Uint8List nv12, int w, int h) {
  final ySize = w * h;
  final cW = (w + 1) ~/ 2, cH = (h + 1) ~/ 2;
  final cSize = cW * cH;
  final out = Uint8List(ySize + 2 * cSize);
  out.setRange(0, ySize, nv12);
  var ui = ySize, vi = ySize + cSize;
  for (var row = 0; row < cH; row++) {
    final src = ySize + row * w; // one interleaved UV row is w bytes
    for (var c = 0; c < cW; c++) {
      out[ui++] = nv12[src + 2 * c]; // U
      final vIdx = src + 2 * c + 1;
      out[vi++] = vIdx < nv12.length ? nv12[vIdx] : 128; // V (odd w: no pair)
    }
  }
  return out;
}

class _ParsedParamSets {
  final int lengthSize;
  final Uint8List annexBHeaders;
  _ParsedParamSets(this.lengthSize, this.annexBHeaders);
}

const List<int> _startCode = [0, 0, 0, 1];

/// Parse an avcC record → (NAL length size, Annex-B SPS/PPS blob).
_ParsedParamSets? _parseAvcc(Uint8List a) {
  if (a.length < 7 || a[0] != 1) return null;
  final lengthSize = (a[4] & 0x03) + 1;
  final out = BytesBuilder(copy: false);
  var p = 5;
  final numSps = a[p++] & 0x1F;
  for (var i = 0; i < numSps; i++) {
    if (p + 2 > a.length) return null;
    final len = (a[p] << 8) | a[p + 1];
    p += 2;
    if (p + len > a.length) return null;
    out.add(_startCode);
    out.add(a.sublist(p, p + len));
    p += len;
  }
  if (p >= a.length) return _ParsedParamSets(lengthSize, out.toBytes());
  final numPps = a[p++];
  for (var i = 0; i < numPps; i++) {
    if (p + 2 > a.length) break;
    final len = (a[p] << 8) | a[p + 1];
    p += 2;
    if (p + len > a.length) break;
    out.add(_startCode);
    out.add(a.sublist(p, p + len));
    p += len;
  }
  return _ParsedParamSets(lengthSize, out.toBytes());
}

/// Parse an hvcC record → (NAL length size, Annex-B VPS/SPS/PPS blob).
_ParsedParamSets? _parseHvcc(Uint8List a) {
  if (a.length < 23 || a[0] != 1) return null;
  final lengthSize = (a[21] & 0x03) + 1;
  final out = BytesBuilder(copy: false);
  var p = 22;
  final numArrays = a[p++];
  for (var i = 0; i < numArrays; i++) {
    if (p + 3 > a.length) return null;
    p += 1; // array_completeness + NAL_unit_type
    final numNals = (a[p] << 8) | a[p + 1];
    p += 2;
    for (var j = 0; j < numNals; j++) {
      if (p + 2 > a.length) return null;
      final len = (a[p] << 8) | a[p + 1];
      p += 2;
      if (p + len > a.length) return null;
      out.add(_startCode);
      out.add(a.sublist(p, p + len));
      p += len;
    }
  }
  return _ParsedParamSets(lengthSize, out.toBytes());
}
