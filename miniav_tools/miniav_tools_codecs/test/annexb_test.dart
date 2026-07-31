// Annex-B → avcC/hvcC configuration records + length-prefixed sample rewriting.
//
// These are byte-layout conversions where a wrong field produces a file that
// some players accept and others silently reject, so the assertions here are
// on exact bytes and offsets, not on "it produced something".
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';
import 'package:test/test.dart';

/// An H.264 Main profile SPS (profile_idc 77 = 0x4D, level_idc 30 = 3.0) with
/// its NAL header byte.
final _h264Sps = Uint8List.fromList([
  0x67, 0x4D, 0x40, 0x1E, 0x9A, 0x66, 0x0A, 0x0F, 0xDF, 0xF8, 0x00, 0x02, //
  0x00, 0x03, 0x00, 0x3C, 0x0F, 0x16, 0x2E, 0x48,
]);
final _h264Pps = Uint8List.fromList([0x68, 0xEB, 0xE3, 0xCB, 0x22, 0xC0]);

/// An HEVC 1280x720 Main profile SPS (level_idc 93 = 3.1, 4:2:0, 8-bit) with
/// its 2-byte NAL header, and the matching VPS/PPS. Note the `00 00 03`
/// emulation-prevention bytes inside it — the parser has to strip them before
/// bit reading, while the record stores the NAL with them intact.
final _hevcVps = Uint8List.fromList([
  0x40, 0x01, 0x0C, 0x01, 0xFF, 0xFF, 0x01, 0x60, 0x00, 0x00, 0x03, 0x00, //
  0x90, 0x00, 0x00, 0x03, 0x00, 0x00, 0x03, 0x00, 0x5D, 0x95, 0x98, 0x09,
]);
final _hevcSps = Uint8List.fromList([
  0x42, 0x01, 0x01, 0x01, 0x60, 0x00, 0x00, 0x03, 0x00, 0x90, 0x00, 0x00, //
  0x03, 0x00, 0x00, 0x03, 0x00, 0x5D, 0xA0, 0x02, 0x80, 0x80, 0x2D, 0x16,
  0x59, 0x59, 0xA4, 0x93, 0x2B, 0xC0, 0x5A, 0x70, 0x80, 0x00, 0x01, 0xF4,
  0x80, 0x00, 0x3A, 0x98, 0x04,
]);
final _hevcPps = Uint8List.fromList([0x44, 0x01, 0xC1, 0x72, 0xB4, 0x62, 0x40]);

Uint8List _annexB(List<Uint8List> nals) {
  final b = BytesBuilder(copy: false);
  for (final n in nals) {
    b.add(const [0, 0, 0, 1]);
    b.add(n);
  }
  return b.toBytes();
}

void main() {
  group('splitAnnexB', () {
    test('handles 3- and 4-byte start codes', () {
      final buf = Uint8List.fromList([
        0, 0, 0, 1, 0x67, 0xAA, // 4-byte SC
        0, 0, 1, 0x68, 0xBB, // 3-byte SC
      ]);
      final nals = splitAnnexB(buf);
      expect(nals.length, 2);
      expect(nals[0], [0x67, 0xAA]);
      expect(nals[1], [0x68, 0xBB]);
    });

    test('keeps a NAL byte that a 4-byte start code could be mistaken for', () {
      // `.. 0xAA 0x00 | 00 00 00 01 ..` — the 0x00 is the NAL's own last byte
      // (cabac_zero_word padding, or just a payload ending in zero), not part
      // of the start code. Trimming it corrupts the sample.
      final buf = Uint8List.fromList([
        0, 0, 0, 1, 0x41, 0xAA, 0x00, //
        0, 0, 0, 1, 0x41, 0xBB,
      ]);
      final nals = splitAnnexB(buf);
      expect(nals.length, 2);
      expect(nals[0], [0x41, 0xAA, 0x00]);
      expect(nals[1], [0x41, 0xBB]);
    });

    test('isAnnexB rejects a length-prefixed buffer', () {
      // 4-byte length 0x00000006 followed by a 6-byte NAL.
      final avcc = Uint8List.fromList([0, 0, 0, 6, 0x65, 1, 2, 3, 4, 5]);
      expect(isAnnexB(avcc), isFalse);
      expect(isAnnexB(_annexB([_h264Sps])), isTrue);
    });
  });

  group('buildAvcC', () {
    test('emits a spec-shaped record with profile/level from the SPS', () {
      final rec = buildAvcC(_annexB([_h264Sps, _h264Pps]))!;

      expect(rec[0], 1, reason: 'configurationVersion');
      expect(rec[1], 0x4D, reason: 'AVCProfileIndication (Main) = sps[1]');
      expect(rec[2], 0x40, reason: 'profile_compatibility = sps[2]');
      expect(rec[3], 0x1E, reason: 'AVCLevelIndication (3.0) = sps[3]');
      expect(rec[4], 0xFF, reason: 'lengthSizeMinusOne = 3, reserved bits set');
      expect(rec[5], 0xE1, reason: '1 SPS + the three reserved bits');

      // SPS: u16 length then the NAL verbatim (emulation prevention intact).
      expect((rec[6] << 8) | rec[7], _h264Sps.length);
      expect(rec.sublist(8, 8 + _h264Sps.length), _h264Sps);

      final p = 8 + _h264Sps.length;
      expect(rec[p], 1, reason: 'numOfPictureParameterSets');
      expect((rec[p + 1] << 8) | rec[p + 2], _h264Pps.length);
      expect(rec.sublist(p + 3, p + 3 + _h264Pps.length), _h264Pps);
      expect(rec.length, p + 3 + _h264Pps.length, reason: 'no trailing slop');
    });

    test('returns null without an SPS', () {
      expect(buildAvcC(_annexB([_h264Pps])), isNull);
      expect(buildAvcC(Uint8List(0)), isNull);
    });
  });

  group('buildHvcC', () {
    test('emits the 23-byte fixed header then VPS/SPS/PPS arrays', () {
      final rec = buildHvcC(_annexB([_hevcVps, _hevcSps, _hevcPps]))!;

      expect(rec[0], 1, reason: 'configurationVersion');
      // profile_space(2)=0 | tier(1)=0 | profile_idc(5)=1 (Main)
      expect(rec[1], 0x01);
      // general_profile_compatibility_flags — bit for Main profile.
      expect(rec.sublist(2, 6), [0x60, 0x00, 0x00, 0x00]);
      expect(rec[12], 0x5D, reason: 'general_level_idc = 93 (level 3.1)');
      expect(rec[21] & 0x03, 3, reason: 'lengthSizeMinusOne = 3');
      expect(rec[22], 3, reason: 'numOfArrays = VPS + SPS + PPS');

      // chroma_format_idc 1 (4:2:0), 8-bit luma and chroma.
      expect(rec[16] & 0x03, 1, reason: 'chroma_format_idc');
      expect(rec[17] & 0x07, 0, reason: 'bit_depth_luma_minus8');
      expect(rec[18] & 0x07, 0, reason: 'bit_depth_chroma_minus8');

      // First array: array_completeness=1, NAL type 32 (VPS), 1 NAL.
      expect(rec[23], 0x80 | 32);
      expect((rec[24] << 8) | rec[25], 1);
      expect((rec[26] << 8) | rec[27], _hevcVps.length);
      expect(rec.sublist(28, 28 + _hevcVps.length), _hevcVps);
    });

    test('returns null when the SPS is absent or truncated', () {
      expect(buildHvcC(_annexB([_hevcVps, _hevcPps])), isNull);
      expect(buildHvcC(_annexB([Uint8List.fromList([0x42, 0x01])])), isNull);
    });
  });

  group('annexBToLengthPrefixed', () {
    test('rewrites start codes as 4-byte lengths and drops parameter sets', () {
      final idr = Uint8List.fromList([0x65, 0x88, 0x84, 0x00, 0x11]);
      final frame = _annexB([_h264Sps, _h264Pps, idr]);
      final out = annexBToLengthPrefixed(frame, hevc: false);

      // Only the IDR survives: SPS/PPS live in avcC (and hvc1 forbids them
      // in-band), so keeping them would duplicate or invalidate the track.
      expect(out.length, 4 + idr.length);
      expect(out.sublist(0, 4), [0, 0, 0, idr.length]);
      expect(out.sublist(4), idr);
    });

    test('preserves multiple slice NALs in order', () {
      final a = Uint8List.fromList([0x41, 0x9A, 0x01]);
      final b = Uint8List.fromList([0x41, 0x9A, 0x02, 0x03]);
      final out = annexBToLengthPrefixed(_annexB([a, b]), hevc: false);
      expect(out.length, 4 + a.length + 4 + b.length);
      expect(out.sublist(4, 4 + a.length), a);
      expect(out.sublist(8 + a.length), b);
    });

    test('drops HEVC VPS/SPS/PPS but keeps the coded slice', () {
      final slice = Uint8List.fromList([0x26, 0x01, 0xAF, 0x00]);
      final out = annexBToLengthPrefixed(
        _annexB([_hevcVps, _hevcSps, _hevcPps, slice]),
        hevc: true,
      );
      expect(out.length, 4 + slice.length);
      expect(out.sublist(4), slice);
    });
  });

  group('Mp4Muxer accepts Annex-B extraData', () {
    Future<Uint8List> mux(VideoCodec codec, Uint8List extra,
        List<Uint8List> frames) async {
      final m = Mp4Muxer.open(MuxerConfig(
        container: Container.mp4,
        output: MuxerOutput.bytes(),
        tracks: [
          VideoTrackInfo(
            codec: codec,
            width: 640,
            height: 360,
            frameRateNumerator: 30,
            frameRateDenominator: 1,
            extraData: CodecExtraData.video(codec, extra),
          ),
        ],
      ));
      await m.writeHeader();
      for (var i = 0; i < frames.length; i++) {
        await m.writePacket(EncodedPacket(
          data: frames[i],
          ptsUs: i * 33333,
          dtsUs: i * 33333,
          isKeyframe: i == 0,
        ));
      }
      await m.finish();
      return Uint8List.fromList(m.getBytes()!);
    }

    test('H.264: builds avcC and length-prefixes the samples', () async {
      final idr = Uint8List.fromList([0x65, 0x88, 0x84, 0x21]);
      final p = Uint8List.fromList([0x41, 0x9A, 0x02]);
      final mp4 = await mux(
        VideoCodec.h264,
        _annexB([_h264Sps, _h264Pps]),
        [_annexB([_h264Sps, _h264Pps, idr]), _annexB([p])],
      );

      // Demux it back: the config must arrive as a real avcC record and the
      // samples must be the length-prefixed forms, not the Annex-B input.
      final d = Mp4Demuxer.open(mp4);
      final v = d.tracks.whereType<VideoTrackInfo>().single;
      expect(v.extraData!.bytes[0], 1, reason: 'avcC, not Annex-B');
      expect(v.extraData!.bytes, buildAvcC(_annexB([_h264Sps, _h264Pps])));

      final packets = <EncodedPacket>[];
      for (var q = await d.readPacket(); q != null; q = await d.readPacket()) {
        packets.add(q);
      }
      expect(packets.length, 2);
      expect(
          packets[0].data,
          annexBToLengthPrefixed(_annexB([_h264Sps, _h264Pps, idr]),
              hevc: false));
      expect(packets[1].data,
          annexBToLengthPrefixed(_annexB([p]), hevc: false));
      await d.close();
    });

    test('HEVC: builds hvcC from VPS/SPS/PPS', () async {
      final idr = Uint8List.fromList([0x26, 0x01, 0xAF, 0x10]);
      final mp4 = await mux(
        VideoCodec.hevc,
        _annexB([_hevcVps, _hevcSps, _hevcPps]),
        [_annexB([_hevcVps, _hevcSps, _hevcPps, idr])],
      );
      final d = Mp4Demuxer.open(mp4);
      final v = d.tracks.whereType<VideoTrackInfo>().single;
      expect(v.extraData!.bytes[0], 1);
      expect(v.extraData!.bytes,
          buildHvcC(_annexB([_hevcVps, _hevcSps, _hevcPps])));
      await d.close();
    });

    test('an already-avcC track is passed through untouched', () async {
      // Remux (demux → mux) must not double-convert: the config already starts
      // with 0x01 and the samples are already length-prefixed.
      final avcC = buildAvcC(_annexB([_h264Sps, _h264Pps]))!;
      final sample = Uint8List.fromList([0, 0, 0, 4, 0x65, 1, 2, 3]);
      final mp4 = await mux(VideoCodec.h264, avcC, [sample]);
      final d = Mp4Demuxer.open(mp4);
      final v = d.tracks.whereType<VideoTrackInfo>().single;
      expect(v.extraData!.bytes, avcC);
      final packets = <EncodedPacket>[];
      for (var q = await d.readPacket(); q != null; q = await d.readPacket()) {
        packets.add(q);
      }
      expect(packets.single.data, sample);
      await d.close();
    });
  });
}
