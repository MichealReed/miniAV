/// Decode at heights the codec cannot code exactly: the decoder must crop to
/// the bitstream's display aperture instead of returning the block-padded
/// CODED frame.
///
/// H.264 codes in 16x16 macroblocks (200 -> 208) and HEVC in 32/64-px CTUs
/// (216 -> 224); both carry a crop window (frame cropping / conformance
/// window) that says how much of the coded frame is picture. Returning the
/// coded size hands the caller decoder garbage as extra rows — the common real
/// case being 1920x1080 arriving as 1088.
///
/// Three independent checks, because any one alone is weak:
///   * the reported dimensions and the mapped buffer LENGTH match the encoded
///     size exactly (a padded frame is longer);
///   * the LUMA still has its marker bands at the very top and very bottom
///     rows, so a crop taken from the wrong origin (or padding kept at one end)
///     is caught even if the length happens to work out;
///   * the CHROMA carries its own top/bottom markers. The UV plane lives after
///     ALL the CODED luma rows in the same texture, so it is addressed off the
///     coded height while the luma is addressed off the display height —
///     mixing the two reads padding luma as chroma and is invisible to any
///     luma-only assertion.
///
/// Skips when the machine lacks the encoder MFT or a hardware decoder MFT.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:miniav_tools/miniav_tools.dart';
import 'package:miniav_tools_codecs/miniav_tools_codecs.dart'
    show MfDecodeBackend, MfEncodeBackend;
import 'package:miniav_tools_codecs/src/codecs_native.dart'
    show mfdecHasHardware, mfencHasMft;
import 'package:test/test.dart';

const int kFps = 30;
const int kTopY = 235; // top marker band
const int kBottomY = 16; // bottom marker band
const int kMidY = 128; // background
const int kBand = 8; // marker band height, in rows
const int kNeutral = 128; // neutral chroma
const int kMarkC = 200; // marker chroma: U in the top band, V in the bottom

/// NV12 frame: an 8-row bright band at the very top, an 8-row dark band at the
/// very bottom, a mid-grey field between them with a moving bar (so inter
/// frames carry residual). The two bands are also COLOURED — the top is
/// U-heavy, the bottom V-heavy — so the chroma plane can be crop-checked the
/// same way the luma is.
Uint8List _nv12(int w, int h, int frame) {
  final ySize = w * h;
  final buf = Uint8List(ySize + ySize ~/ 2);
  final barX = (frame * 4) % (w - 32);
  for (var y = 0; y < h; y++) {
    final row = y * w;
    final int base;
    if (y < kBand) {
      base = kTopY;
    } else if (y >= h - kBand) {
      base = kBottomY;
    } else {
      base = kMidY;
    }
    for (var x = 0; x < w; x++) {
      final inBar = y >= 2 * kBand &&
          y < h - 2 * kBand &&
          x >= barX &&
          x < barX + 32;
      buf[row + x] = inBar ? 200 : base;
    }
  }
  // Interleaved UV: one row per two luma rows, [U V U V ...] across the row.
  for (var cy = 0; cy < h ~/ 2; cy++) {
    final row = ySize + cy * w;
    final ly = cy * 2;
    final u = ly < kBand ? kMarkC : kNeutral;
    final v = ly >= h - kBand ? kMarkC : kNeutral;
    for (var cx = 0; cx < w ~/ 2; cx++) {
      buf[row + 2 * cx] = u;
      buf[row + 2 * cx + 1] = v;
    }
  }
  return buf;
}

/// Mean luma of row [y] in a tightly packed I420 buffer.
double _rowMean(List<int> i420, int w, int y) {
  var sum = 0;
  for (var x = 0; x < w; x++) {
    sum += i420[y * w + x];
  }
  return sum / w;
}

/// Mean of chroma row [cy] of plane [plane] (0 = U, 1 = V) in a tightly packed
/// I420 buffer of display size [w]x[h].
double _chromaRowMean(List<int> i420, int w, int h, int plane, int cy) {
  final cW = w ~/ 2, cH = h ~/ 2;
  final off = w * h + plane * cW * cH + cy * cW;
  var sum = 0;
  for (var x = 0; x < cW; x++) {
    sum += i420[off + x];
  }
  return sum / cW;
}

void _nonAlignedTest({
  required String name,
  required VideoCodec codec,
  required int encCodecId,
  required int w,
  required int h,
}) {
  test(name, () async {
    if (!Platform.isWindows) {
      markTestSkipped('MF is Windows-only');
      return;
    }
    if (mfencHasMft(encCodecId) == 0) {
      markTestSkipped('no ${codec.name} encoder MFT');
      return;
    }
    if (!mfdecHasHardware(encCodecId)) {
      markTestSkipped('no hardware ${codec.name} decoder MFT');
      return;
    }

    final enc = await MfEncodeBackend().createEncoder(EncoderConfig(
      codec: codec,
      width: w,
      height: h,
      bitrateBps: 4000000,
      gopLength: kFps,
      frameRateNumerator: kFps,
      frameRateDenominator: 1,
      hwAccel: HwAccelPreference.forbidden,
    ));
    expect(enc, isNotNull, reason: '${codec.name} encoder failed to open');

    final packets = <EncodedPacket>[];
    for (var i = 0; i < 45; i++) {
      final pkt = await enc!.encode(CpuFrameSource(
        bytes: _nv12(w, h, i),
        pixelFormat: MiniAVPixelFormat.nv12,
        width: w,
        height: h,
        timestampUs: (i * 1000000) ~/ kFps,
      ));
      if (pkt != null) packets.add(pkt);
    }
    packets.addAll(await enc!.flush());
    final extra = enc.extraData?.bytes;
    await enc.close();
    expect(packets, isNotEmpty, reason: 'encoder produced no packets');

    final dec = await MfDecodeBackend().createDecoder(DecoderConfig(
      codec: codec,
      extraData: extra,
      width: w,
      height: h,
      backendOptions: const {'sw_isolate': '0'}, // in-isolate (dart test MTA)
    ));
    expect(dec, isNotNull, reason: '${codec.name} decoder failed to open');

    final frames = <DecodedFrame>[];
    for (final p in packets) {
      final f = await dec!.decode(p);
      if (f != null) frames.add(f);
    }
    frames.addAll(await dec!.flush());
    expect(frames, isNotEmpty, reason: 'decoder produced no frames');

    final first = frames.first;
    expect(first.width, w, reason: 'reported width must be the display width');
    expect(first.height, h,
        reason: 'reported height must be the display height, not the '
            'macroblock/CTU-padded coded height');

    final i420 = await first.readBytes();
    expect(i420.length, w * h + 2 * ((w ~/ 2) * (h ~/ 2)),
        reason: 'mapped buffer must hold the display region only');

    // Content: the marker bands must still sit at the first and last rows.
    // Padding rows replicate the edge, so length alone cannot prove the crop
    // came off the right end — these means can.
    expect(_rowMean(i420, w, 2), greaterThan(180),
        reason: 'top row is not the bright band — crop origin is wrong');
    expect(_rowMean(i420, w, h - 3), lessThan(70),
        reason: 'last row is not the dark band — padding rows were kept or the '
            'crop came off the wrong end');
    expect(_rowMean(i420, w, h ~/ 2), inInclusiveRange(90, 180),
        reason: 'centre row is not the mid-grey field');

    // Chroma: the UV plane starts after ALL CODED luma rows, so it needs the
    // coded height where the luma needs the display height. Reading it off the
    // display height instead lands in the padding luma rows — which no luma
    // assertion above can see.
    final cH = h ~/ 2;
    expect(_chromaRowMean(i420, w, h, 0, 1), greaterThan(170),
        reason: 'top chroma rows are not U-heavy — the UV plane base is off '
            '(coded vs display height) or the chroma crop origin is wrong');
    expect(_chromaRowMean(i420, w, h, 1, 1), inInclusiveRange(100, 156),
        reason: 'top chroma rows should be V-neutral');
    expect(_chromaRowMean(i420, w, h, 1, cH - 2), greaterThan(170),
        reason: 'bottom chroma rows are not V-heavy — the UV plane base is off '
            'or padding chroma rows were kept');
    expect(_chromaRowMean(i420, w, h, 0, cH - 2), inInclusiveRange(100, 156),
        reason: 'bottom chroma rows should be U-neutral');
    expect(_chromaRowMean(i420, w, h, 0, cH ~/ 2), inInclusiveRange(100, 156),
        reason: 'centre chroma rows should be neutral');
    expect(_chromaRowMean(i420, w, h, 1, cH ~/ 2), inInclusiveRange(100, 156),
        reason: 'centre chroma rows should be neutral');

    for (final f in frames) {
      f.close();
    }
    await dec.close();
  });
}

void main() {
  group('MF decode at non-block-aligned sizes', () {
    _nonAlignedTest(
      name: 'H.264 320x200 (coded 208) reports and maps 200 rows',
      codec: VideoCodec.h264,
      encCodecId: 0,
      w: 320,
      h: 200,
    );
    _nonAlignedTest(
      name: 'HEVC 320x216 (coded 224) reports and maps 216 rows',
      codec: VideoCodec.hevc,
      encCodecId: 1,
      w: 320,
      h: 216,
    );
  });
}
