/// A stream whose own parameter sets contradict the record it was opened with.
///
/// An encoder's published parameter sets are a claim about its stream; the
/// ones in front of a keyframe are the stream. AMD's H.264 Media Foundation
/// encoder publishes a sequence header whose SPS signals pic_order_cnt_type 0,
/// while every SPS it emits signals type 2. MP4 keeps only the record — the
/// muxer strips the in-band copies from the samples — so a record built from
/// the claim had every slice header parsed against the wrong SPS, and FFmpeg
/// decoded none of the frames. Nothing in the file could say so.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';
import 'package:miniav_tools_codecs/src/framing/annexb.dart'
    show carriesParamSets, configParamSets, leadingParamSets, mergeParamSets;
import 'package:test/test.dart';

import 'mp4_box_probe.dart';

Uint8List _hex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);

/// The SPS in AMD's published H.264 sequence header: pic_order_cnt_type 0,
/// colour description unspecified...
final _publishedSps = _hex(
  '674d041fe8a07809bf2ffe00020002840000090000030001000003003c8f08846580',
);

/// ...and the SPS in front of every IDR the same encoder emits:
/// pic_order_cnt_type 2, BT.709. Every other field is identical.
final _streamSps = _hex(
  '674d041fd940f0137e5ffc000400050808080a000003000200000300791e1108cb',
);

final _pps = Uint8List.fromList([0x68, 0xee, 0x3c, 0x80]);
final _otherPps = Uint8List.fromList([0x68, 0xce, 0x3c, 0x80]);
final _aud = Uint8List.fromList([0x09, 0xf0]);
final _idrSlice = Uint8List.fromList([
  0x65,
  0x88,
  0x84,
  0x00,
  0x10,
  0xff,
  0xfe,
  0xf6,
]);
final _pSlice = Uint8List.fromList([0x41, 0x9a, 0x02, 0x04, 0x13, 0x80]);

/// HEVC 1280x720 Main VPS/SPS/PPS (the `annexb_test.dart` fixtures), and an
/// SPS that differs only past the fields `hvcC` is built from.
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
final _hevcOtherSps = Uint8List.fromList([..._hevcSps]..last = 0x08);
final _hevcPps = Uint8List.fromList([0x44, 0x01, 0xC1, 0x72, 0xB4, 0x62, 0x40]);
final _hevcIdrSlice = Uint8List.fromList([0x26, 0x01, 0xAF, 0x06, 0xB8, 0x14]);
final _hevcTrailSlice = Uint8List.fromList([0x02, 0x01, 0xD0, 0x2A, 0x6B]);

Uint8List _annexB(List<Uint8List> nals) {
  final b = BytesBuilder(copy: false);
  for (final n in nals) {
    b.add(const [0, 0, 0, 1]);
    b.add(n);
  }
  return b.toBytes();
}

Mp4Muxer _open({List<Uint8List>? record, String? path, bool hevc = false}) {
  final codec = hevc ? VideoCodec.hevc : VideoCodec.h264;
  return Mp4Muxer.open(
    MuxerConfig(
      container: Container.mp4,
      output: path == null ? MuxerOutput.bytes() : MuxerOutput.file(path),
      tracks: [
        VideoTrackInfo(
          codec: codec,
          width: 960,
          height: 600,
          frameRateNumerator: 30,
          frameRateDenominator: 1,
          extraData: record == null
              ? null
              : CodecExtraData.video(codec, _annexB(record)),
        ),
      ],
    ),
  );
}

/// One GOP of [length] frames from frame [from]: an IDR carrying [sets]
/// in-band, then P frames.
Future<void> _gop(
  Mp4Muxer m,
  int from, {
  List<Uint8List> sets = const [],
  int length = 3,
  bool hevc = false,
}) async {
  for (var i = from; i < from + length; i++) {
    final key = i == from;
    final Uint8List data;
    if (hevc) {
      data = _annexB(key ? [...sets, _hevcIdrSlice] : [_hevcTrailSlice]);
    } else {
      data = _annexB(key ? [_aud, ...sets, _idrSlice] : [_aud, _pSlice]);
    }
    await m.writePacket(
      EncodedPacket(
        data: data,
        ptsUs: i * 33333,
        dtsUs: i * 33333,
        durationUs: 33333,
        isKeyframe: key,
        trackIndex: 0,
      ),
    );
  }
}

/// The configuration record of each `stsd` sample entry, in order.
List<Uint8List> _entryRecords(Uint8List mp4) {
  final stsd = findAll(mp4, 'stsd').single;
  // FullBox header + entry_count, then the entries; a visual sample entry
  // has 78 bytes of fixed fields before its child boxes.
  return [
    for (final e in boxesIn(mp4, stsd.payloadStart + 8, stsd.payloadEnd))
      for (final c in boxesIn(mp4, e.payloadStart + 78, e.payloadEnd))
        if (c.type == 'avcC' || c.type == 'hvcC')
          Uint8List.sublistView(mp4, c.payloadStart, c.payloadEnd),
  ];
}

/// Each `stsc` row's sample_description_index.
List<int> _stscEntries(Uint8List mp4) {
  final box = findAll(mp4, 'stsc').single;
  final d = ByteData.sublistView(mp4);
  final n = d.getUint32(box.payloadStart + 4, Endian.big);
  return [
    for (var i = 0; i < n; i++)
      d.getUint32(box.payloadStart + 16 + i * 12, Endian.big),
  ];
}

List<Uint8List> _sets(Uint8List record, {bool hevc = false}) =>
    configParamSets(record, hevc: hevc);

void main() {
  group('H.264: the parameter sets in the stream win', () {
    test(
      'a contradicting keyframe SPS replaces the open-time record',
      () async {
        final m = _open(record: [_publishedSps, _pps]);
        await m.writeHeader();
        await _gop(m, 0, sets: [_streamSps, _pps]);
        await _gop(m, 3, sets: [_streamSps, _pps]);
        await m.finish();

        final mp4 = Uint8List.fromList(m.getBytes()!);
        final records = _entryRecords(mp4);
        expect(
          records,
          hasLength(1),
          reason:
              'the published record described no sample, so it must not '
              'be in the file at all',
        );
        expect(_sets(records.single), [_streamSps, _pps]);
        expect(_stscEntries(mp4).every((e) => e == 1), isTrue);
        expect(m.trackConfigCount(0), 1);
      },
    );

    test('the streaming path writes the same single entry', () async {
      final dir = Directory.systemTemp.createTempSync('mp4inband');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/out.mp4';
      final m = _open(record: [_publishedSps, _pps], path: path);
      await m.writeHeader();
      await _gop(m, 0, sets: [_streamSps, _pps]);
      await _gop(m, 3, sets: [_streamSps, _pps]);
      await m.finish();

      final mp4 = File(path).readAsBytesSync();
      final records = _entryRecords(mp4);
      expect(records, hasLength(1));
      expect(_sets(records.single), [_streamSps, _pps]);
      expect(_stscEntries(mp4).every((e) => e == 1), isTrue);
    });

    test('parameter sets that agree with the record change nothing', () async {
      // NVIDIA's MFT, and any encoder whose header tells the truth: the file
      // is byte-identical to one whose samples never carried the sets.
      final inBand = _open(record: [_streamSps, _pps]);
      await inBand.writeHeader();
      await _gop(inBand, 0, sets: [_streamSps, _pps]);
      await _gop(inBand, 3, sets: [_streamSps, _pps]);
      await inBand.finish();

      final bare = _open(record: [_streamSps, _pps]);
      await bare.writeHeader();
      await _gop(bare, 0);
      await _gop(bare, 3);
      await bare.finish();

      expect(inBand.getBytes(), bare.getBytes());
    });

    test(
      'zero padding after an in-band set does not make it a new set',
      () async {
        // trailing_zero_8bits belong to the byte stream, not to the NAL.
        final padded = _open(record: [_streamSps, _pps]);
        await padded.writeHeader();
        await padded.writePacket(
          EncodedPacket(
            data: Uint8List.fromList([
              0, 0, 0, 1, ..._streamSps, 0, //
              0, 0, 0, 1, ..._pps, 0, 0,
              0, 0, 0, 1, ..._idrSlice,
            ]),
            ptsUs: 0,
            dtsUs: 0,
            durationUs: 33333,
            isKeyframe: true,
            trackIndex: 0,
          ),
        );
        await padded.finish();

        final plain = _open(record: [_streamSps, _pps]);
        await plain.writeHeader();
        await plain.writePacket(
          EncodedPacket(
            data: _annexB([_idrSlice]),
            ptsUs: 0,
            dtsUs: 0,
            durationUs: 33333,
            isKeyframe: true,
            trackIndex: 0,
          ),
        );
        await plain.finish();

        expect(padded.trackConfigCount(0), 1);
        expect(padded.getBytes(), plain.getBytes());
      },
    );

    test(
      'a track opened without a record takes the first keyframe\'s',
      () async {
        final m = _open();
        await m.writeHeader();
        await _gop(m, 0, sets: [_streamSps, _pps]);
        await m.finish();

        expect(m.tracksMissingConfig, isEmpty);
        final records = _entryRecords(Uint8List.fromList(m.getBytes()!));
        expect(records, hasLength(1));
        expect(_sets(records.single), [_streamSps, _pps]);
      },
    );

    test(
      'a keyframe that repeats only its SPS keeps the published PPS',
      () async {
        final m = _open(record: [_publishedSps, _pps]);
        await m.writeHeader();
        await _gop(m, 0, sets: [_streamSps]);
        await m.finish();

        final records = _entryRecords(Uint8List.fromList(m.getBytes()!));
        expect(records, hasLength(1));
        expect(_sets(records.single), [_streamSps, _pps]);
      },
    );

    test(
      'a mid-stream change gets its own entry; going back reuses the first',
      () async {
        final m = _open(record: [_streamSps, _pps]);
        await m.writeHeader();
        await _gop(m, 0, sets: [_streamSps, _pps]);
        await _gop(m, 3, sets: [_streamSps, _otherPps]);
        await _gop(m, 6, sets: [_streamSps, _pps]);
        await m.finish();

        final mp4 = Uint8List.fromList(m.getBytes()!);
        final records = _entryRecords(mp4);
        expect(records, hasLength(2));
        expect(_sets(records[0]), [_streamSps, _pps]);
        expect(_sets(records[1]), [_streamSps, _otherPps]);
        expect(_stscEntries(mp4), [1, 2, 1]);
        expect(m.trackConfigCount(0), 2);
      },
    );

    test('P frames stay under the record their keyframe chose', () async {
      // The check runs on every sample, and a sample with no parameter sets
      // must not move the track anywhere.
      final m = _open(record: [_streamSps, _pps]);
      await m.writeHeader();
      await _gop(m, 0, sets: [_streamSps, _otherPps], length: 5);
      await m.finish();

      final mp4 = Uint8List.fromList(m.getBytes()!);
      expect(_entryRecords(mp4), hasLength(1));
      expect(_sets(_entryRecords(mp4).single), [_streamSps, _otherPps]);
      final d = Mp4Demuxer.open(mp4);
      var samples = 0;
      for (var p = await d.readPacket(); p != null; p = await d.readPacket()) {
        samples++;
      }
      await d.close();
      expect(samples, 5);
    });
  });

  test('HEVC: a contradicting VPS/SPS/PPS group replaces the record', () async {
    final m = _open(record: [_hevcVps, _hevcSps, _hevcPps], hevc: true);
    await m.writeHeader();
    await _gop(m, 0, sets: [_hevcVps, _hevcOtherSps, _hevcPps], hevc: true);
    await m.finish();

    final records = _entryRecords(Uint8List.fromList(m.getBytes()!));
    expect(records, hasLength(1));
    expect(_sets(records.single, hevc: true), [
      _hevcVps,
      _hevcOtherSps,
      _hevcPps,
    ]);
  });

  group('parameter-set helpers', () {
    test('leadingParamSets stops at the first slice', () {
      final frame = _annexB([_aud, _streamSps, _pps, _idrSlice, _publishedSps]);
      expect(leadingParamSets(frame, hevc: false), [_streamSps, _pps]);
      expect(leadingParamSets(_annexB([_aud, _pSlice]), hevc: false), isEmpty);
    });

    test('leadingParamSets reads 3-byte start codes and refuses length '
        'prefixes', () {
      final frame = Uint8List.fromList([
        0, 0, 1, ..._streamSps, //
        0, 0, 1, ..._pps,
        0, 0, 1, ..._idrSlice,
      ]);
      expect(leadingParamSets(frame, hevc: false), [_streamSps, _pps]);
      final lengthPrefixed = Uint8List.fromList([
        0,
        0,
        0,
        _streamSps.length,
        ..._streamSps,
      ]);
      expect(leadingParamSets(lengthPrefixed, hevc: false), isEmpty);
    });

    test('configParamSets reads records and Annex-B blobs alike', () {
      final avc = _annexB([_streamSps, _pps]);
      expect(configParamSets(buildAvcC(avc)!, hevc: false), [_streamSps, _pps]);
      expect(configParamSets(avc, hevc: false), [_streamSps, _pps]);
      final hevc = _annexB([_hevcVps, _hevcSps, _hevcPps]);
      expect(configParamSets(buildHvcC(hevc)!, hevc: true), [
        _hevcVps,
        _hevcSps,
        _hevcPps,
      ]);
    });

    test('configParamSets of a truncated record is the part that parsed', () {
      final record = buildAvcC(_annexB([_streamSps, _pps]))!;
      final cut = Uint8List.sublistView(record, 0, record.length - 2);
      expect(configParamSets(cut, hevc: false), [_streamSps]);
      expect(configParamSets(Uint8List(0), hevc: false), isEmpty);
    });

    test('carriesParamSets is a subset test', () {
      expect(carriesParamSets([_streamSps, _pps], [_pps]), isTrue);
      expect(
        carriesParamSets([_publishedSps, _pps], [_streamSps, _pps]),
        isFalse,
      );
      expect(carriesParamSets(const [], [_pps]), isFalse);
    });

    test('mergeParamSets keeps the types the stream did not repeat', () {
      expect(
        mergeParamSets([_otherPps], [_streamSps, _pps], hevc: false),
        _annexB([_streamSps, _otherPps]),
        reason: 'SPS before PPS, whichever side each came from',
      );
      expect(
        mergeParamSets(
          [_streamSps, _pps],
          [_publishedSps, _otherPps],
          hevc: false,
        ),
        _annexB([_streamSps, _pps]),
      );
    });
  });
}
