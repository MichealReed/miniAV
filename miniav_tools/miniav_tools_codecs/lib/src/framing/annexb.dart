/// Annex-B ⇄ ISO-BMFF bitstream conversion for H.264 / HEVC.
///
/// Encoders (Media Foundation, libx264, NVENC) emit **Annex-B**: NAL units
/// separated by `00 00 01` / `00 00 00 01` start codes, with the parameter sets
/// repeated in-band on every IDR. MP4 needs the opposite — **length-prefixed**
/// NAL units in `mdat`, and the parameter sets stored once, out-of-band, in an
/// `avcC` / `hvcC` configuration record in the sample entry.
///
/// This module is the bridge. [buildAvcC] / [buildHvcC] turn an Annex-B
/// parameter-set blob (the MF sequence header / FFmpeg `extradata`) into the
/// configuration record; [annexBToLengthPrefixed] rewrites a coded frame.
///
/// The inverse (record → Annex-B, for feeding a decoder) lives in
/// `mf/mf_d3d11_decoder.dart`.
library;

import 'dart:typed_data';

/// `true` when [d] looks like Annex-B — i.e. it opens with a start code.
///
/// Framing should be decided **once**, from the parameter-set blob (an
/// `avcC`/`hvcC` record always starts with `0x01`), and then applied to every
/// packet. Sniffing each packet independently is unreliable: a length-prefixed
/// NAL of exactly one byte is encoded as `00 00 00 01`, which is
/// indistinguishable from a 4-byte start code.
bool isAnnexB(List<int> d) {
  if (d.length < 4) return false;
  if (d[0] != 0 || d[1] != 0) return false;
  return d[2] == 1 || (d[2] == 0 && d[3] == 1);
}

/// Split an Annex-B buffer into NAL units, dropping the start codes.
///
/// NAL payloads are returned verbatim — including any trailing zero bytes.
/// Trimming them would be wrong: `cabac_zero_word` padding is part of the NAL,
/// and a slice can legitimately end in `0x00`. The zero that *does* belong to a
/// following 4-byte start code is already excluded, because [_nextStartCode]
/// anchors on the `00 00 00 01` sequence rather than the first zero it sees.
List<Uint8List> splitAnnexB(Uint8List d) {
  final out = <Uint8List>[];
  final n = d.length;

  // Locate the first start code; bytes before it (if any) are not a NAL.
  var p = _nextStartCode(d, 0);
  while (p < n) {
    final scLen = (p + 2 < n && d[p + 2] == 1) ? 3 : 4;
    final start = p + scLen;
    if (start >= n) break;
    final end = _nextStartCode(d, start);
    if (end > start) out.add(Uint8List.sublistView(d, start, end));
    p = end;
  }
  return out;
}

/// Index of the next `00 00 01` or `00 00 00 01`, or [d].length if none.
int _nextStartCode(Uint8List d, int from) {
  final n = d.length;
  for (var i = from; i + 2 < n; i++) {
    if (d[i] != 0 || d[i + 1] != 0) continue;
    if (d[i + 2] == 1) return i;
    if (d[i + 2] == 0 && i + 3 < n && d[i + 3] == 1) return i;
  }
  return n;
}

/// H.264 NAL types that belong in `avcC`, not in a sample.
const int _h264Sps = 7;
const int _h264Pps = 8;

/// HEVC NAL types that belong in `hvcC`, not in a sample.
const int _hevcVps = 32;
const int _hevcSps = 33;
const int _hevcPps = 34;

int _h264Type(Uint8List nal) => nal[0] & 0x1F;
int _hevcType(Uint8List nal) => (nal[0] >> 1) & 0x3F;

bool _isH264ParamSet(Uint8List nal) {
  final t = _h264Type(nal);
  return t == _h264Sps || t == _h264Pps;
}

bool _isHevcParamSet(Uint8List nal) {
  final t = _hevcType(nal);
  return t == _hevcVps || t == _hevcSps || t == _hevcPps;
}

/// Rewrite one Annex-B coded frame as length-prefixed NAL units for `mdat`.
///
/// Parameter-set NALs are dropped: they live in the `avcC`/`hvcC` record, and
/// an `hvc1` sample entry (which is what the muxer writes) *requires* that
/// samples carry none — a stream with in-band parameter sets would have to be
/// signalled as `hev1` instead.
///
/// [lengthSize] must match `lengthSizeMinusOne + 1` in the configuration
/// record; both builders here emit 4.
Uint8List annexBToLengthPrefixed(Uint8List frame, {required bool hevc,
    int lengthSize = 4}) {
  final nals = splitAnnexB(frame);
  final keep = <Uint8List>[];
  var total = 0;
  for (final nal in nals) {
    if (nal.isEmpty) continue;
    if (hevc) {
      if (nal.length < 2 || _isHevcParamSet(nal)) continue;
    } else {
      if (_isH264ParamSet(nal)) continue;
    }
    keep.add(nal);
    total += lengthSize + nal.length;
  }
  final out = Uint8List(total);
  var o = 0;
  for (final nal in keep) {
    var len = nal.length;
    for (var i = lengthSize - 1; i >= 0; i--) {
      out[o + i] = len & 0xFF;
      len >>= 8;
    }
    o += lengthSize;
    out.setRange(o, o + nal.length, nal);
    o += nal.length;
  }
  return out;
}

/// Build an `avcC` (`AVCDecoderConfigurationRecord`) from Annex-B SPS/PPS.
///
/// Returns `null` when [annexB] carries no SPS — without one there is no
/// profile/level to advertise and the record would be meaningless.
///
/// The optional profile-extension tail (chroma_format / bit depths, present
/// only for profile_idc 100/110/122/144) is omitted, matching FFmpeg's
/// `ff_isom_write_avcc`; readers treat it as optional.
Uint8List? buildAvcC(Uint8List annexB) {
  final sps = <Uint8List>[];
  final pps = <Uint8List>[];
  for (final nal in splitAnnexB(annexB)) {
    if (nal.isEmpty) continue;
    switch (_h264Type(nal)) {
      case _h264Sps:
        if (nal.length >= 4) sps.add(nal);
      case _h264Pps:
        pps.add(nal);
    }
  }
  if (sps.isEmpty) return null;

  final b = BytesBuilder(copy: false);
  final s0 = sps.first;
  b.addByte(1); // configurationVersion
  b.addByte(s0[1]); // AVCProfileIndication
  b.addByte(s0[2]); // profile_compatibility
  b.addByte(s0[3]); // AVCLevelIndication
  b.addByte(0xFF); // '111111' + lengthSizeMinusOne = 3
  b.addByte(0xE0 | (sps.length & 0x1F)); // '111' + numOfSequenceParameterSets
  for (final s in sps) {
    b.addByte(s.length >> 8);
    b.addByte(s.length & 0xFF);
    b.add(s);
  }
  b.addByte(pps.length & 0xFF); // numOfPictureParameterSets
  for (final p in pps) {
    b.addByte(p.length >> 8);
    b.addByte(p.length & 0xFF);
    b.add(p);
  }
  return b.toBytes();
}

/// Build an `hvcC` (`HEVCDecoderConfigurationRecord`) from Annex-B VPS/SPS/PPS.
///
/// Returns `null` when [annexB] carries no parsable SPS — the record's
/// profile/tier/level and chroma/bit-depth fields come from it and have no
/// legal "unknown" encoding.
Uint8List? buildHvcC(Uint8List annexB) {
  final vps = <Uint8List>[];
  final sps = <Uint8List>[];
  final pps = <Uint8List>[];
  for (final nal in splitAnnexB(annexB)) {
    if (nal.length < 3) continue;
    switch (_hevcType(nal)) {
      case _hevcVps:
        vps.add(nal);
      case _hevcSps:
        sps.add(nal);
      case _hevcPps:
        pps.add(nal);
    }
  }
  if (sps.isEmpty) return null;
  final info = _parseHevcSps(sps.first);
  if (info == null) return null;

  final b = BytesBuilder(copy: false);
  b.addByte(1); // configurationVersion
  // general_profile_space(2) | general_tier_flag(1) | general_profile_idc(5)
  b.addByte((info.profileSpace << 6) | (info.tierFlag << 5) | info.profileIdc);
  b.add(info.profileCompatibilityFlags); // 4 bytes
  b.add(info.constraintIndicatorFlags); // 6 bytes
  b.addByte(info.levelIdc);
  // '1111' + min_spatial_segmentation_idc(12); 0 = unknown.
  b.addByte(0xF0);
  b.addByte(0x00);
  b.addByte(0xFC); // '111111' + parallelismType(2) = 0 (unknown)
  b.addByte(0xFC | (info.chromaFormatIdc & 0x03)); // '111111' + chroma_format
  b.addByte(0xF8 | (info.bitDepthLumaMinus8 & 0x07)); // '11111' + luma depth
  b.addByte(0xF8 | (info.bitDepthChromaMinus8 & 0x07)); // '11111' + chroma
  b.addByte(0); // avgFrameRate (16 bits) = 0, unspecified
  b.addByte(0);
  // constantFrameRate(2)=0 | numTemporalLayers(3) | temporalIdNested(1)
  // | lengthSizeMinusOne(2)=3
  b.addByte((info.numTemporalLayers << 3) |
      (info.temporalIdNested << 2) |
      0x03);

  final arrays = <MapEntry<int, List<Uint8List>>>[
    if (vps.isNotEmpty) MapEntry(_hevcVps, vps),
    if (sps.isNotEmpty) MapEntry(_hevcSps, sps),
    if (pps.isNotEmpty) MapEntry(_hevcPps, pps),
  ];
  b.addByte(arrays.length); // numOfArrays
  for (final a in arrays) {
    // array_completeness(1)=1 | reserved(1)=0 | NAL_unit_type(6). The set is
    // complete: every parameter set of this type is in the record, because the
    // muxer strips them from the samples.
    b.addByte(0x80 | a.key);
    b.addByte(a.value.length >> 8);
    b.addByte(a.value.length & 0xFF);
    for (final nal in a.value) {
      b.addByte(nal.length >> 8);
      b.addByte(nal.length & 0xFF);
      b.add(nal);
    }
  }
  return b.toBytes();
}

/// Largest luma dimension any HEVC level permits: `sqrt(8 * MaxLumaPs)` at
/// level 6.2 (H.265 §A.4.1, MaxLumaPs = 35651584).
const int _maxHevcDimension = 16888;

/// Coded luma size of the first HEVC SPS in an Annex-B parameter-set blob.
///
/// `pic_width_in_luma_samples` / `pic_height_in_luma_samples` — the CODED size,
/// before the conformance window is applied. That is deliberately the *coded*
/// size: it is what a decoder's input type wants (the MFT derives the display
/// aperture from the crop offsets itself), and cropping here would hand it a
/// frame size that no CTU grid can hold.
///
/// Returns `null` when [annexB] has no SPS, the SPS does not parse, or the
/// dimensions it carries are not plausible ([_maxHevcDimension]).
({int width, int height})? hevcCodedSizeFromAnnexB(Uint8List annexB) {
  for (final nal in splitAnnexB(annexB)) {
    if (nal.length < 3 || _hevcType(nal) != _hevcSps) continue;
    final info = _parseHevcSps(nal);
    if (info == null) continue;
    // The bound is load-bearing, not cosmetic: `ue()` parses values far beyond
    // 32 bits without complaint, and this size is handed to an `Int32` FFI
    // parameter, where dart:ffi truncates silently. A truncated-negative width
    // makes the native side skip MF_MT_FRAME_SIZE altogether and hand back the
    // decoder that accepts every packet and emits nothing — the exact failure
    // this harvest exists to prevent, minus the fall-through. Rejecting here
    // returns `null` instead, which declines to software.
    if (info.picWidthInLumaSamples <= 0 ||
        info.picHeightInLumaSamples <= 0 ||
        info.picWidthInLumaSamples > _maxHevcDimension ||
        info.picHeightInLumaSamples > _maxHevcDimension) {
      continue;
    }
    return (
      width: info.picWidthInLumaSamples,
      height: info.picHeightInLumaSamples,
    );
  }
  return null;
}

class _HevcSpsInfo {
  _HevcSpsInfo({
    required this.profileSpace,
    required this.tierFlag,
    required this.profileIdc,
    required this.profileCompatibilityFlags,
    required this.constraintIndicatorFlags,
    required this.levelIdc,
    required this.chromaFormatIdc,
    required this.bitDepthLumaMinus8,
    required this.bitDepthChromaMinus8,
    required this.numTemporalLayers,
    required this.temporalIdNested,
    required this.picWidthInLumaSamples,
    required this.picHeightInLumaSamples,
  });

  final int profileSpace;
  final int tierFlag;
  final int profileIdc;
  final Uint8List profileCompatibilityFlags; // 4 bytes
  final Uint8List constraintIndicatorFlags; // 6 bytes
  final int levelIdc;
  final int chromaFormatIdc;
  final int bitDepthLumaMinus8;
  final int bitDepthChromaMinus8;
  final int numTemporalLayers;
  final int temporalIdNested;

  /// Coded luma size — the conformance window is NOT applied.
  final int picWidthInLumaSamples;
  final int picHeightInLumaSamples;
}

/// Parse just enough of an HEVC SPS (ITU-T H.265 §7.3.2.2) to fill `hvcC`:
/// profile_tier_level, then chroma_format_idc and the bit depths. Everything
/// after `bit_depth_chroma_minus8` is ignored, which keeps this clear of the
/// genuinely hairy parts (scaling lists, short-term reference picture sets).
_HevcSpsInfo? _parseHevcSps(Uint8List nal) {
  // Skip the 2-byte NAL header, and undo emulation prevention before bit
  // reading — the stored NAL keeps its `00 00 03` bytes, but the syntax does
  // not see them.
  if (nal.length < 3) return null;
  final r = _BitReader(_removeEmulationPrevention(nal, 2));
  try {
    r.u(4); // sps_video_parameter_set_id
    final maxSubLayersMinus1 = r.u(3);
    final temporalIdNested = r.u(1);

    // profile_tier_level(profilePresentFlag = 1, maxSubLayersMinus1)
    final profileSpace = r.u(2);
    final tierFlag = r.u(1);
    final profileIdc = r.u(5);
    final compat = Uint8List(4);
    for (var i = 0; i < 4; i++) {
      compat[i] = r.u(8);
    }
    final constraint = Uint8List(6);
    for (var i = 0; i < 6; i++) {
      constraint[i] = r.u(8);
    }
    final levelIdc = r.u(8);

    final subProfile = <bool>[];
    final subLevel = <bool>[];
    for (var i = 0; i < maxSubLayersMinus1; i++) {
      subProfile.add(r.u(1) == 1);
      subLevel.add(r.u(1) == 1);
    }
    if (maxSubLayersMinus1 > 0) {
      for (var i = maxSubLayersMinus1; i < 8; i++) {
        r.u(2); // reserved_zero_2bits
      }
    }
    for (var i = 0; i < maxSubLayersMinus1; i++) {
      if (subProfile[i]) r.skip(88);
      if (subLevel[i]) r.skip(8);
    }

    r.ue(); // sps_seq_parameter_set_id
    final chromaFormatIdc = r.ue();
    if (chromaFormatIdc == 3) r.u(1); // separate_colour_plane_flag
    final picWidth = r.ue(); // pic_width_in_luma_samples
    final picHeight = r.ue(); // pic_height_in_luma_samples
    if (r.u(1) == 1) {
      r.ue(); // conf_win_left_offset
      r.ue(); // conf_win_right_offset
      r.ue(); // conf_win_top_offset
      r.ue(); // conf_win_bottom_offset
    }
    final bitDepthLuma = r.ue();
    final bitDepthChroma = r.ue();

    return _HevcSpsInfo(
      profileSpace: profileSpace,
      tierFlag: tierFlag,
      profileIdc: profileIdc,
      profileCompatibilityFlags: compat,
      constraintIndicatorFlags: constraint,
      levelIdc: levelIdc,
      chromaFormatIdc: chromaFormatIdc,
      bitDepthLumaMinus8: bitDepthLuma,
      bitDepthChromaMinus8: bitDepthChroma,
      numTemporalLayers: maxSubLayersMinus1 + 1,
      temporalIdNested: temporalIdNested,
      picWidthInLumaSamples: picWidth,
      picHeightInLumaSamples: picHeight,
    );
  } on _BitReaderOverrun {
    return null;
  }
}

/// Strip `00 00 03` emulation-prevention bytes from [d] starting at [from].
Uint8List _removeEmulationPrevention(Uint8List d, int from) {
  final out = BytesBuilder(copy: false);
  var zeros = 0;
  for (var i = from; i < d.length; i++) {
    final b = d[i];
    if (zeros >= 2 && b == 3) {
      zeros = 0;
      continue; // drop the emulation-prevention byte
    }
    out.addByte(b);
    zeros = (b == 0) ? zeros + 1 : 0;
  }
  return out.toBytes();
}

class _BitReaderOverrun implements Exception {
  const _BitReaderOverrun();
}

class _BitReader {
  _BitReader(this._d);
  final Uint8List _d;
  int _bit = 0;

  int u(int n) {
    var v = 0;
    for (var i = 0; i < n; i++) {
      final byte = _bit >> 3;
      if (byte >= _d.length) throw const _BitReaderOverrun();
      v = (v << 1) | ((_d[byte] >> (7 - (_bit & 7))) & 1);
      _bit++;
    }
    return v;
  }

  void skip(int n) {
    if (((_bit + n) >> 3) > _d.length) throw const _BitReaderOverrun();
    _bit += n;
  }

  /// Unsigned Exp-Golomb, ue(v).
  int ue() {
    var lead = 0;
    while (u(1) == 0) {
      lead++;
      if (lead > 32) throw const _BitReaderOverrun();
    }
    if (lead == 0) return 0;
    return (1 << lead) - 1 + u(lead);
  }
}
