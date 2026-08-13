// HEVC negotiated WITHOUT a frame size: where the size comes from, and what
// happens when there is none.
//
// `mf_decoder.c` (mfdec_configure_input) puts MF_MT_FRAME_SIZE on the input
// type only when the caller supplies dims, and the HEVC decoder MFT REQUIRES it:
// without it the MFT cannot propose an output type and rejects every
// ProcessInput with MF_E_TRANSFORM_TYPE_NOT_SET. But mfdecCreate still returns a
// valid session, so MfD3d11Decoder.open once handed the negotiator a decoder
// that swallowed every packet and returned no frame, forever — a black screen
// with no error and no fall-through.
//
// Now: when an hvcC is present, the coded size is HARVESTED from its SPS and the
// hardware MFT opens after all. Only a caller with neither dims nor a parsable
// hvcC gets the decline, which sends HEVC to the software decoder.
//
// H.264 is deliberately NOT affected either way: its MFT parses dims in-band.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:miniav_tools/miniav_tools.dart';
import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';
import 'package:miniav_tools_codecs/src/codecs_native.dart'
    show mfdecHasHardware, mfencHasMft;
import 'package:miniav_tools_codecs/src/framing/annexb.dart'
    show annexBToLengthPrefixed, buildHvcC, hevcCodedSizeFromAnnexB;
import 'package:miniav_tools_ffmpeg/miniav_tools_ffmpeg.dart'
    show registerFfmpegBackend;
import 'package:test/test.dart';

/// The height matters: the "coded hint did not leak into the display size"
/// assertions below only mean anything while the encoder's CODED height (what
/// gets harvested and hinted) differs from the display height. 216 codes as 224
/// here — but that is a property of the encoder MFT, not of the number, so the
/// hardware test ASSERTS the gap rather than trusting this comment.
const _w = 320, _h = 216, _fps = 30;

/// Moving NV12 gradient (Y shifts per frame; neutral chroma).
Uint8List _nv12(int frame) {
  final ySize = _w * _h;
  final buf = Uint8List(ySize + ySize ~/ 2);
  for (var j = 0; j < _h; j++) {
    for (var i = 0; i < _w; i++) {
      buf[j * _w + i] = (i + j + frame * 4) & 0xFF;
    }
  }
  buf.fillRange(ySize, buf.length, 128);
  return buf;
}

/// (packets, hvcC extraData) for a short real HEVC stream, or null when the
/// machine has no HEVC encoder MFT.
Future<(List<EncodedPacket>, Uint8List?)?> _encodeHevc() async {
  if (mfencHasMft(1) == 0) return null;
  final enc = await MfEncodeBackend().createEncoder(const EncoderConfig(
    codec: VideoCodec.hevc,
    width: _w,
    height: _h,
    bitrateBps: 1500000,
    gopLength: _fps,
    frameRateNumerator: _fps,
    frameRateDenominator: 1,
    hwAccel: HwAccelPreference.forbidden,
  ));
  if (enc == null) return null;
  final packets = <EncodedPacket>[];
  for (var i = 0; i < 30; i++) {
    final p = await enc.encode(CpuFrameSource(
      bytes: _nv12(i),
      pixelFormat: MiniAVPixelFormat.nv12,
      width: _w,
      height: _h,
      timestampUs: (i * 1000000) ~/ _fps,
    ));
    if (p != null) packets.add(p);
  }
  packets.addAll(await enc.flush());
  final extra = enc.extraData?.bytes;
  await enc.close();
  return (packets, extra);
}

/// Minimal but syntactically real HEVC SPS NAL (H.265 §7.3.2.2), unescaped.
///
/// Only the prefix the harvester reads is meaningful; everything after
/// bit_depth_chroma_minus8 is omitted, which is legal for a parser that stops
/// there and keeps this fixture free of scaling lists and short-term RPS.
/// profile_tier_level is left all-zero on purpose: that makes the stored form
/// require emulation-prevention escapes ahead of the dimension fields.
Uint8List _hevcSpsNal({
  required int picW,
  required int picH,
  required int confWinBottomChroma,
}) {
  final w = _BitWriter();
  w.u(4, 0); // sps_video_parameter_set_id
  w.u(3, 0); // sps_max_sub_layers_minus1 = 0 (no sub-layer PTL to write)
  w.u(1, 1); // sps_temporal_id_nesting_flag
  // profile_tier_level(1, 0): space/tier/idc, 32 compat flags, 48 constraint
  // bits, level_idc — 12 bytes, all zero.
  for (var i = 0; i < 12; i++) {
    w.u(8, 0);
  }
  w.ue(0); // sps_seq_parameter_set_id
  w.ue(1); // chroma_format_idc = 4:2:0
  w.ue(picW);
  w.ue(picH);
  if (confWinBottomChroma > 0) {
    w.u(1, 1); // conformance_window_flag
    w.ue(0); // left
    w.ue(0); // right
    w.ue(0); // top
    w.ue(confWinBottomChroma); // bottom, in chroma units
  } else {
    w.u(1, 0);
  }
  w.ue(0); // bit_depth_luma_minus8
  w.ue(0); // bit_depth_chroma_minus8
  w.u(1, 1); // rbsp_stop_one_bit
  // nuh: forbidden_zero(1)=0 | type(6)=33 | layer_id(6)=0 | tid_plus1(3)=1
  return Uint8List.fromList([0x42, 0x01, ...w.bytes()]);
}

/// Insert `00 00 03` emulation-prevention bytes into the NAL payload.
Uint8List _escape(Uint8List nal) {
  final out = <int>[nal[0], nal[1]];
  var zeros = 0;
  for (var i = 2; i < nal.length; i++) {
    final b = nal[i];
    if (zeros >= 2 && b <= 3) {
      out.add(3);
      zeros = 0;
    }
    out.add(b);
    zeros = (b == 0) ? zeros + 1 : 0;
  }
  return Uint8List.fromList(out);
}

Uint8List _annexB(Uint8List nal) => Uint8List.fromList([0, 0, 0, 1, ...nal]);

class _BitWriter {
  final _out = <int>[];
  int _cur = 0;
  int _n = 0;

  void u(int bits, int value) {
    for (var i = bits - 1; i >= 0; i--) {
      _cur = (_cur << 1) | ((value >> i) & 1);
      if (++_n == 8) {
        _out.add(_cur);
        _cur = 0;
        _n = 0;
      }
    }
  }

  /// Unsigned Exp-Golomb: (len-1) zeros, then value+1 in len bits.
  void ue(int value) {
    final v = value + 1;
    var len = 0;
    for (var t = v; t > 0; t >>= 1) {
      len++;
    }
    u(len - 1, 0);
    u(len, v);
  }

  List<int> bytes() => [..._out, if (_n > 0) _cur << (8 - _n)];
}

void main() {
  setUpAll(() {
    registerMfDecodeBackend();
    registerOpusBackend();
    registerPcmBackend();
    registerSwAudioBackend();
    registerAacBackend();
    registerContainerFramingBackend();
    registerFfmpegBackend();
  });

  test('MfD3d11Decoder declines HEVC with no dims AND no extradata, '
      'and keeps H.264', () async {
    if (!Platform.isWindows) {
      markTestSkipped('MF is Windows-only');
      return;
    }
    if (mfdecHasHardware(1)) {
      expect(
        await MfD3d11Decoder.open(const DecoderConfig(codec: VideoCodec.hevc)),
        isNull,
        reason: 'HEVC without a frame size can never produce a picture',
      );
      expect(
        await MfD3d11Decoder.open(
            const DecoderConfig(codec: VideoCodec.hevc, width: 0, height: 0)),
        isNull,
        reason: 'zero dims are "unknown", not a legal frame size',
      );
      // The backend's own factory must relay the decline, so the facade sees a
      // null and moves on rather than committing to this backend.
      expect(
        await MfDecodeBackend().createDecoder(const DecoderConfig(
          codec: VideoCodec.hevc,
          backendOptions: {'sw_isolate': '0'},
        )),
        isNull,
      );
      // An hvcC whose SPS parses but carries an out-of-Int32 size must decline
      // too. Passing it on would truncate to a negative in mfdecCreate, drop
      // MF_MT_FRAME_SIZE, and commit to a decoder that never emits.
      final absurd = buildHvcC(_annexB(_escape(
          _hevcSpsNal(picW: 3000000000, picH: 1080, confWinBottomChroma: 0))));
      expect(absurd, isNotNull, reason: 'the fixture must be a real hvcC');
      expect(
        await MfD3d11Decoder.open(DecoderConfig(
          codec: VideoCodec.hevc,
          extraData: absurd,
        )),
        isNull,
        reason: 'an implausible harvested size must decline to software',
      );
    }
    if (mfdecHasHardware(0)) {
      // H.264's MFT parses the SPS in-band; declining it would be a regression.
      final h264 = await MfD3d11Decoder.open(const DecoderConfig(
        codec: VideoCodec.h264,
      ));
      expect(h264, isNotNull,
          reason: 'H.264 needs no dims hint and must still open');
      await h264!.close();
    }
  });

  test('SPS harvest yields the CODED size, not the display size', () {
    // 1080 codes as 1088 with an 8-row conformance window. Harvesting the
    // display size would hand the MFT a frame size no CTU grid can hold.
    //
    // Hand-built SPS, so this holds on a machine with no HEVC encoder at all.
    final annexB = _annexB(_escape(_hevcSpsNal(picW: 1920, picH: 1088,
        confWinBottomChroma: 4))); // 1088 - 2*4 = 1080 displayed
    expect(hevcCodedSizeFromAnnexB(annexB), (width: 1920, height: 1088));

    // Same SPS reached through a real hvcC record built by this repo's own
    // writer, then unwrapped the way the decoder unwraps it — the shape a
    // demuxer actually hands over.
    final hvcC = buildHvcC(annexB);
    expect(hvcC, isNotNull);
    expect(hvcC![0], 1, reason: 'hvcC records start with configurationVersion');
  });

  test('emulation-prevention bytes inside the SPS do not corrupt the size', () {
    // profile_tier_level here is 10 zero bytes, so the stored NAL MUST carry
    // 0x03 escapes ahead of the dimension fields. A reader that does not strip
    // them desyncs by a bit before it ever reaches pic_width.
    final raw = _hevcSpsNal(picW: 768, picH: 768, confWinBottomChroma: 0);
    final escaped = _escape(raw);
    expect(escaped.length, greaterThan(raw.length),
        reason: 'the fixture must actually contain an escaped run');
    // The escaped (on-the-wire) and raw (syntax-level) forms must agree; they
    // only can if the escapes are being removed.
    expect(hevcCodedSizeFromAnnexB(_annexB(raw)), (width: 768, height: 768));
    expect(hevcCodedSizeFromAnnexB(_annexB(escaped)),
        (width: 768, height: 768));
  });

  test('an implausible SPS dimension harvests nothing', () {
    // This one PARSES — ue() reads a 33-bit value without complaint and it is
    // > 0, so a `<= 0` guard passes it straight through. mfdecCreate takes
    // Int32 and dart:ffi truncates silently: 3000000000 arrives native-side as
    // -1294967296, MF_MT_FRAME_SIZE is skipped as "no dims", and the session
    // still creates — the never-emits decoder this whole harvest exists to
    // avoid, this time with no fall-through because open() already committed.
    for (final huge in [
      _hevcSpsNal(picW: 3000000000, picH: 1080, confWinBottomChroma: 0),
      _hevcSpsNal(picW: 1920, picH: 3000000000, confWinBottomChroma: 0),
    ]) {
      expect(hevcCodedSizeFromAnnexB(_annexB(_escape(huge))), isNull,
          reason: 'an out-of-Int32 dimension must decline, not truncate');
    }
    // The bound must still admit the largest size anyone really ships.
    expect(
      hevcCodedSizeFromAnnexB(_annexB(
          _escape(_hevcSpsNal(picW: 7680, picH: 4320, confWinBottomChroma: 0)))),
      (width: 7680, height: 4320),
      reason: '8K is a legal HEVC size and must not be caught by the bound',
    );
  });

  test('a truncated / non-SPS parameter set harvests nothing', () {
    expect(hevcCodedSizeFromAnnexB(_annexB(Uint8List.fromList([0x42, 1]))),
        isNull, reason: 'SPS header with no payload');
    final raw = _hevcSpsNal(picW: 640, picH: 480, confWinBottomChroma: 0);
    expect(hevcCodedSizeFromAnnexB(_annexB(raw.sublist(0, 6))), isNull,
        reason: 'SPS cut off inside profile_tier_level');
    // VPS (type 32), not an SPS — must be ignored, not misread.
    expect(hevcCodedSizeFromAnnexB(_annexB(Uint8List.fromList(
        [0x40, 1, ...raw.sublist(2)]))), isNull);
  });

  test('negotiated HEVC without dims uses the HARDWARE decoder via hvcC',
      () async {
    if (!Platform.isWindows) {
      markTestSkipped('MF is Windows-only');
      return;
    }
    final encoded = await _encodeHevc();
    if (encoded == null) {
      markTestSkipped('no HEVC encoder MFT (HEVC Video Extensions absent)');
      return;
    }
    final (packets, annexBExtra) = encoded;
    expect(packets, isNotEmpty);
    expect(annexBExtra, isNotNull);

    // The MF encoder hands back an Annex-B sequence header; a container hands
    // back an hvcC — and an hvcC always comes with LENGTH-PREFIXED samples, so
    // the packets have to be reframed with it or the pairing is not a shape any
    // demuxer produces. Neither form carries width/height.
    final hvcC = buildHvcC(annexBExtra!);
    expect(hvcC, isNotNull, reason: 'encoder extradata must contain an SPS');

    // Precondition, asserted rather than assumed: the whole point of this test
    // is that the harvested CODED size is not what a frame reports, which is
    // only observable when the two differ. If some future encoder MFT codes
    // 216 exactly, every assertion below still passes while proving nothing —
    // so fail here instead, pointing at the fixture.
    final coded = hevcCodedSizeFromAnnexB(annexBExtra);
    expect(coded, isNotNull);
    expect(coded!.height, greaterThan(_h),
        reason: 'this encoder coded $_h exactly, so coded == display and the '
            'leak this test looks for cannot show up — pick a height its CTU '
            'grid must pad');

    for (final (label, extra, lengthPrefixed) in [
      ('hvcC record', hvcC!, true),
      ('Annex-B sequence header', annexBExtra, false),
    ]) {
      final dec = await MiniAVTools.createDecoder(DecoderConfig(
        codec: VideoCodec.hevc,
        extraData: extra,
        // No width/height — the case a demuxer that only carries hvcC produces.
        backendOptions: const {'sw_isolate': '0'},
      ));
      if (mfdecHasHardware(1)) {
        expect(dec.backendName, 'mf_decode',
            reason: '$label carries the size in its SPS, so the hardware '
                'decoder must be selected');
      }
      // Frames, not a name, are the real assertion: a decoder that accepts
      // every packet and produces nothing is exactly the bug this guards.
      final frames = <DecodedFrame>[];
      for (final p in packets) {
        final f = await dec.decode(lengthPrefixed
            ? EncodedPacket(
                data: annexBToLengthPrefixed(p.data, hevc: true),
                ptsUs: p.ptsUs,
                dtsUs: p.dtsUs,
                isKeyframe: p.isKeyframe,
                trackIndex: p.trackIndex)
            : p);
        if (f != null) frames.add(f);
      }
      frames.addAll(await dec.flush());
      expect(frames, isNotEmpty,
          reason: 'the negotiated HEVC decoder produced no frames at all for '
              '$label — ${dec.backendName} accepted every packet and returned '
              'nothing');
      // Display size, not the coded size the input type was hinted with: the
      // output aperture still governs what a frame reports.
      expect(frames.first.width, _w, reason: label);
      expect(frames.first.height, _h,
          reason: '$label reported the harvested CODED height '
              '(${coded.height}) instead of the display height');
      // And the PIXELS agree with the report: a frame that reports the display
      // height but maps the coded surface hands back the padding rows as
      // picture, which the dimension check alone cannot see.
      expect((await frames.first.readBytes()).length,
          _w * _h + 2 * ((_w ~/ 2) * (_h ~/ 2)),
          reason: '$label mapped more than the display region');
      for (final f in frames) {
        f.close();
      }
      await dec.close();
    }
  });

  test('with ffmpeg excluded, HEVC without dims fails LOUDLY', () async {
    if (!Platform.isWindows) {
      markTestSkipped('MF is Windows-only');
      return;
    }
    if (!mfdecHasHardware(1)) {
      markTestSkipped('no hardware HEVC decoder MFT');
      return;
    }
    // Nothing left that can honour it → a clear error beats a decoder that
    // silently never emits.
    await expectLater(
      MiniAVTools.createDecoder(
        const DecoderConfig(
          codec: VideoCodec.hevc,
          backendOptions: {'sw_isolate': '0'},
        ),
        preference: BackendPreference.excluded({'ffmpeg'}),
      ),
      throwsA(anyOf(
        isA<NoBackendForCodecException>(),
        isA<CodecInitException>(),
      )),
    );
  });

  test('dims present still selects mf_decode and produces frames', () async {
    if (!Platform.isWindows) {
      markTestSkipped('MF is Windows-only');
      return;
    }
    if (!mfdecHasHardware(1)) {
      markTestSkipped('no hardware HEVC decoder MFT');
      return;
    }
    final encoded = await _encodeHevc();
    if (encoded == null) {
      markTestSkipped('no HEVC encoder MFT (HEVC Video Extensions absent)');
      return;
    }
    final (packets, extra) = encoded;

    final dec = await MiniAVTools.createDecoder(DecoderConfig(
      codec: VideoCodec.hevc,
      extraData: extra,
      width: _w,
      height: _h,
      backendOptions: const {'sw_isolate': '0'},
    ));
    expect(dec.backendName, 'mf_decode');
    final frames = <DecodedFrame>[];
    for (final p in packets) {
      final f = await dec.decode(p);
      if (f != null) frames.add(f);
    }
    frames.addAll(await dec.flush());
    expect(frames, isNotEmpty);
    expect(frames.first.width, _w);
    expect(frames.first.height, _h);
    for (final f in frames) {
      f.close();
    }
    await dec.close();
  });
}
