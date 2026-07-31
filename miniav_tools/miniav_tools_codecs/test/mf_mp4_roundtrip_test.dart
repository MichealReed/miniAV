/// End-to-end: first-party MF hardware encode → first-party MP4 mux → demux.
///
/// The unit tests in `annexb_test.dart` pin the byte layout against
/// hand-written parameter sets. This one runs the same code over a REAL NVENC /
/// OS-MFT bitstream, which is the only way to catch a record that is
/// self-consistently wrong — e.g. an SPS whose Exp-Golomb chain drifts, or
/// emulation-prevention bytes mishandled in a stream that actually contains
/// them. A broken avcC/hvcC here means MP4 files that some players silently
/// reject, so this is the gate before the MF encoder can ship as primary.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';

import 'package:test/test.dart';

const _w = 640, _h = 480;

Uint8List _nv12(int seed) {
  final y = _w * _h;
  final b = Uint8List(y + y ~/ 2);
  for (var i = 0; i < y; i++) {
    b[i] = ((i ~/ _w) + seed * 7) & 0xFF; // moving gradient — real work to encode
  }
  b.fillRange(y, b.length, 128);
  return b;
}

void main() {
  for (final (codec, label, box) in [
    (VideoCodec.h264, 'H.264', 'avcC'),
    (VideoCodec.hevc, 'HEVC', 'hvcC'),
  ]) {
    test('$label: MF encode → MP4 mux produces a parsable $box', () async {
      final enc = await MfVideoEncoder.open(EncoderConfig(
        codec: codec,
        width: _w,
        height: _h,
        bitrateBps: 4000000,
        frameRateNumerator: 30,
        frameRateDenominator: 1,
        gopLength: 15,
      ));
      expect(enc, isNotNull, reason: '$label encoder failed to open');

      final packets = <EncodedPacket>[];
      for (var i = 0; i < 30; i++) {
        final p = await enc!.encode(FrameSource.cpu(
          bytes: _nv12(i),
          pixelFormat: MiniAVPixelFormat.nv12,
          width: _w,
          height: _h,
          timestampUs: i * 33333,
        ));
        if (p != null) packets.add(p);
      }
      packets.addAll(await enc!.flush());
      expect(packets, isNotEmpty);

      // The encoder must hand back parameter sets one way or another — from
      // MF_MT_MPEG_SEQUENCE_HEADER, or harvested from the first keyframe. A
      // null here fails the whole recording at mux time.
      final extra = enc.extraData;
      expect(extra, isNotNull,
          reason: '$label produced no parameter sets; Mp4Muxer would reject '
              'the track');
      expect(isAnnexB(extra!.bytes), isTrue,
          reason: 'MF is expected to emit Annex-B parameter sets');
      await enc.close();

      final m = Mp4Muxer.open(MuxerConfig(
        container: Container.mp4,
        output: MuxerOutput.bytes(),
        tracks: [
          VideoTrackInfo(
            codec: codec,
            width: _w,
            height: _h,
            frameRateNumerator: 30,
            frameRateDenominator: 1,
            extraData: extra,
          ),
        ],
      ));
      await m.writeHeader();
      for (final p in packets) {
        await m.writePacket(p);
      }
      await m.finish();
      final mp4 = Uint8List.fromList(m.getBytes()!);
      await m.close();

      final d = Mp4Demuxer.open(mp4);
      final v = d.tracks.whereType<VideoTrackInfo>().single;
      expect(v.codec, codec);
      expect(v.width, _w);
      expect(v.height, _h);

      final rec = v.extraData!.bytes;
      expect(rec[0], 1, reason: 'configurationVersion — a $box, not Annex-B');
      expect(rec.length, greaterThan(codec == VideoCodec.hevc ? 23 : 7));
      if (codec == VideoCodec.hevc) {
        expect(rec[21] & 0x03, 3, reason: 'lengthSizeMinusOne');
        expect(rec[22], greaterThan(0), reason: 'numOfArrays: VPS/SPS/PPS');
        // Chroma/bit-depth come out of the SPS bit reader; NVENC encodes our
        // NV12 input as 8-bit 4:2:0, so a drifted parse shows up right here.
        expect(rec[16] & 0x03, 1, reason: 'chroma_format_idc = 4:2:0');
        expect(rec[17] & 0x07, 0, reason: 'bit_depth_luma_minus8 = 0 (8-bit)');
        expect(rec[18] & 0x07, 0, reason: 'bit_depth_chroma_minus8 = 0');
      } else {
        expect(rec[4] & 0x03, 3, reason: 'lengthSizeMinusOne');
        expect(rec[1], isNot(0), reason: 'AVCProfileIndication from the SPS');
        expect(rec[3], isNot(0), reason: 'AVCLevelIndication from the SPS');
        expect(rec[5] & 0x1F, greaterThan(0), reason: 'at least one SPS');
      }

      // Every sample must be a well-formed chain of 4-byte-length-prefixed
      // NALs that exactly consumes the sample — the check that catches an
      // Annex-B payload written into mdat verbatim.
      var samples = 0, keyframes = 0;
      for (var p = await d.readPacket(); p != null; p = await d.readPacket()) {
        final s = p.data;
        expect(isAnnexB(s), isFalse, reason: 'sample $samples is still Annex-B');
        // Positive control: the muxer really rewrote this sample — it is not
        // the encoder's bytes, and it is exactly what the converter produces.
        final src = packets[samples].data;
        expect(s, isNot(equals(src)),
            reason: 'sample $samples went into mdat unconverted');
        expect(
            s,
            annexBToLengthPrefixed(Uint8List.fromList(src),
                hevc: codec == VideoCodec.hevc));
        var o = 0;
        while (o + 4 <= s.length) {
          final len = (s[o] << 24) | (s[o + 1] << 16) | (s[o + 2] << 8) | s[o + 3];
          expect(len, greaterThan(0), reason: 'zero-length NAL in sample $samples');
          o += 4 + len;
          expect(o, lessThanOrEqualTo(s.length),
              reason: 'NAL length overruns sample $samples');
        }
        expect(o, s.length, reason: 'sample $samples is not NAL-aligned');
        if (p.isKeyframe) keyframes++;
        samples++;
      }
      await d.close();
      expect(samples, packets.length);
      expect(keyframes, greaterThan(0), reason: 'no keyframe survived the mux');
    });
  }
}
