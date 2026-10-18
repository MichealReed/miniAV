// A track's codec configuration can change part-way through a recording.
//
// The case: a GPU device reset removes every D3D11 device on the adapter, so
// the encoder must be reopened, and a reopened encoder issues its own
// parameter sets. The record already committed to the file is then a claim
// about samples that were not encoded under it — and writing those samples
// anyway gives a file that decodes wrong or not at all, reporting success at
// every step. Same class of failure as a missing moov, and just as invisible.
//
// This is only possible because `moov` is built at finish(): the sample entry
// a reader sees is chosen when the index is built, not when the muxer opened.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';
import 'package:test/test.dart';

import 'mp4_box_probe.dart';

/// avcC records that differ only in a byte no parser rejects — enough to be a
/// different configuration without being an invalid one.
Uint8List _avcC(int levelIdc) =>
    Uint8List.fromList([1, 0x64, 0, levelIdc, 0xff, 0xe1]);

VideoTrackInfo _track(int levelIdc) => VideoTrackInfo(
      codec: VideoCodec.h264,
      width: 320,
      height: 240,
      frameRateNumerator: 30,
      frameRateDenominator: 1,
      extraData: CodecExtraData.video(VideoCodec.h264, _avcC(levelIdc)),
    );

Mp4Muxer _open() => Mp4Muxer.open(MuxerConfig(
      container: Container.mp4,
      output: MuxerOutput.bytes(),
      tracks: [_track(0x1f)],
    ));

Future<void> _write(Mp4Muxer m, int count, {int from = 0}) async {
  for (var i = from; i < from + count; i++) {
    await m.writePacket(EncodedPacket(
      data: Uint8List.fromList([i & 0xFF, 1, 2, 3, 4, 5, 6, 7]),
      ptsUs: i * 33333,
      dtsUs: i * 33333,
      durationUs: 33333,
      isKeyframe: i == 0,
    ));
  }
}

/// `stsc` as [first_chunk, samples_per_chunk, sample_description_index] rows.
List<List<int>> _stsc(Uint8List mp4) {
  final box = findAll(mp4, 'stsc').single;
  final d = ByteData.sublistView(mp4);
  final n = d.getUint32(box.payloadStart + 4, Endian.big);
  return [
    for (var i = 0; i < n; i++)
      [
        d.getUint32(box.payloadStart + 8 + i * 12, Endian.big),
        d.getUint32(box.payloadStart + 12 + i * 12, Endian.big),
        d.getUint32(box.payloadStart + 16 + i * 12, Endian.big),
      ]
  ];
}

int _stsdEntryCount(Uint8List mp4) {
  final box = findAll(mp4, 'stsd').single;
  return ByteData.sublistView(mp4).getUint32(box.payloadStart + 4, Endian.big);
}

void main() {
  group('an unchanged configuration changes nothing', () {
    test('the identical record is a no-op, and the file is single-entry',
        () async {
      // The common case for a reopened encoder: same MFT, same resolution,
      // same profile and rate control give byte-identical parameter sets.
      final m = _open();
      await m.writeHeader();
      await _write(m, 10);
      expect(m.setTrackConfig(0, _avcC(0x1f)), Mp4ConfigChange.unchanged);
      await _write(m, 10, from: 10);
      await m.finish();

      final mp4 = Uint8List.fromList(m.getBytes()!);
      expect(_stsdEntryCount(mp4), 1);
      expect(m.trackConfigCount(0), 1);
      expect(_stsc(mp4).every((e) => e[2] == 1), isTrue);
    });

    test('a track that is never told anything writes exactly one entry',
        () async {
      final m = _open();
      await m.writeHeader();
      await _write(m, 20);
      await m.finish();
      expect(_stsdEntryCount(Uint8List.fromList(m.getBytes()!)), 1);
    });
  });

  group('a changed configuration gets its own sample entry', () {
    test('stsd gains an entry and later chunks point at it', () async {
      final m = _open();
      await m.writeHeader();
      await _write(m, 10);
      expect(m.setTrackConfig(0, _avcC(0x28)), Mp4ConfigChange.added);
      await _write(m, 10, from: 10);
      await m.finish();

      final mp4 = Uint8List.fromList(m.getBytes()!);
      expect(_stsdEntryCount(mp4), 2);

      final rows = _stsc(mp4);
      expect(rows.map((e) => e[2]).toSet(), {1, 2},
          reason: 'both configurations must be referenced');
      // 10 samples under each, in order.
      expect(rows.first[2], 1);
      expect(rows.last[2], 2);
      expect(rows.fold<int>(0, (a, e) => a + e[1]), 20,
          reason: 'no sample may be lost to the chunk split');
    });

    test('every sample still round-trips through the demuxer', () async {
      final m = _open();
      await m.writeHeader();
      await _write(m, 10);
      m.setTrackConfig(0, _avcC(0x28));
      await _write(m, 10, from: 10);
      await m.finish();

      final d = Mp4Demuxer.open(Uint8List.fromList(m.getBytes()!));
      final got = <int>[];
      for (var p = await d.readPacket(); p != null; p = await d.readPacket()) {
        got.add(p.data[0]);
      }
      expect(got, [for (var i = 0; i < 20; i++) i],
          reason: 'a config change must not disturb the sample table');
    });

    test('going back to a record already present reuses its entry', () async {
      // A device reset that comes back with the ORIGINAL parameter sets after
      // a spell on different ones. Appending a third identical entry would be
      // a lie about how many configurations the track has.
      final m = _open();
      await m.writeHeader();
      await _write(m, 5);
      expect(m.setTrackConfig(0, _avcC(0x28)), Mp4ConfigChange.added);
      await _write(m, 5, from: 5);
      expect(m.setTrackConfig(0, _avcC(0x1f)), Mp4ConfigChange.restored);
      await _write(m, 5, from: 10);
      await m.finish();

      final mp4 = Uint8List.fromList(m.getBytes()!);
      expect(_stsdEntryCount(mp4), 2, reason: 'two configs, used three times');
      expect(_stsc(mp4).map((e) => e[2]).toList(), [1, 2, 1]);
    });

    test('three chunks of five samples do not collapse into one run',
        () async {
      // The trap in stsc run-collapsing: chunks with the SAME sample count
      // look identical unless the description index is compared too, and a
      // collapsed run would silently claim the first config for all of them.
      final m = _open();
      await m.writeHeader();
      await _write(m, 5);
      m.setTrackConfig(0, _avcC(0x28));
      await _write(m, 5, from: 5);
      m.setTrackConfig(0, _avcC(0x1f));
      await _write(m, 5, from: 10);
      await m.finish();

      final rows = _stsc(Uint8List.fromList(m.getBytes()!));
      expect(rows.length, 3,
          reason: 'same samples_per_chunk, different config — three runs');
      expect(rows.map((e) => e[0]).toList(), [1, 2, 3]);
    });
  });

  group('the STREAMING path splits chunks too', () {
    // The in-memory layout builds chunks at finish, from the per-sample config
    // list. The streaming layout builds them as packets arrive and cannot look
    // back — a different code path, and the one a recorder actually uses,
    // since a recorder writes to a file rather than collecting bytes.
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('mp4cfg'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<Uint8List> streamed(void Function(Mp4Muxer) midway) async {
      final path = '${dir.path}/out.mp4';
      final m = Mp4Muxer.open(MuxerConfig(
        container: Container.mp4,
        output: MuxerOutput.file(path),
        tracks: [_track(0x1f)],
      ));
      await m.writeHeader();
      await _write(m, 5);
      midway(m);
      await _write(m, 5, from: 5);
      await m.finish();
      return File(path).readAsBytesSync();
    }

    test('a config change opens a new chunk pointing at the new entry',
        () async {
      final mp4 = await streamed((m) {
        expect(m.setTrackConfig(0, _avcC(0x28)), Mp4ConfigChange.added);
      });
      expect(_stsdEntryCount(mp4), 2);
      final rows = _stsc(mp4);
      expect(rows.map((e) => e[2]).toList(), [1, 2],
          reason: 'without a chunk boundary the whole track would claim the '
              'first configuration');
      expect(rows.fold<int>(0, (a, e) => a + e[1]), 10);
    });

    test('every sample survives the split, in order', () async {
      final mp4 = await streamed((m) => m.setTrackConfig(0, _avcC(0x28)));
      final d = Mp4Demuxer.open(mp4);
      final got = <int>[];
      for (var p = await d.readPacket(); p != null; p = await d.readPacket()) {
        got.add(p.data[0]);
      }
      expect(got, [for (var i = 0; i < 10; i++) i]);
    });

    test('no config change leaves the streaming layout exactly as it was',
        () async {
      final mp4 = await streamed((_) {});
      expect(_stsdEntryCount(mp4), 1);
      expect(_stsc(mp4).every((e) => e[2] == 1), isTrue);
    });
  });

  group('the API refuses what it cannot honour', () {
    test('after finish() there is nothing left to change', () async {
      final m = _open();
      await m.writeHeader();
      await _write(m, 5);
      await m.finish();
      expect(() => m.setTrackConfig(0, _avcC(0x28)),
          throwsA(isA<CodecRuntimeException>()));
    });

    test('an out-of-range track index is an error, not a silent no-op',
        () async {
      final m = _open();
      await m.writeHeader();
      expect(() => m.setTrackConfig(3, _avcC(0x28)),
          throwsA(isA<CodecRuntimeException>()));
      await m.finish();
    });

    test('empty bytes are refused', () async {
      final m = _open();
      await m.writeHeader();
      expect(() => m.setTrackConfig(0, Uint8List(0)),
          throwsA(isA<CodecRuntimeException>()));
      await m.finish();
    });

    test('Annex-B parameter sets are normalised, as they are at open',
        () async {
      // An encoder that hands back a start-code stream on reopen should not
      // have to be told which convention the muxer wanted.
      final annexB = Uint8List.fromList([
        0, 0, 0, 1, 0x67, 0x64, 0x00, 0x1f, 0xac, 0xd9, 0x40, //
        0x50, 0x05, 0xbb, 0x01, 0x6a, 0x02, 0x02, 0x02, 0x80,
        0, 0, 0, 1, 0x68, 0xeb, 0xe3, 0xcb, 0x22, 0xc0,
      ]);
      final m = _open();
      await m.writeHeader();
      await _write(m, 5);
      final r = m.setTrackConfig(0, annexB);
      expect(r, Mp4ConfigChange.added);
      await _write(m, 5, from: 5);
      await m.finish();

      expect(_stsdEntryCount(Uint8List.fromList(m.getBytes()!)), 2);
    });

    test('the normalised form is what gets stored, not the raw start codes',
        () async {
      // Behavioural proof rather than box archaeology: handing over the
      // Annex-B bytes and then their avcC equivalent must be recognised as the
      // SAME configuration. If the start codes were stored raw, the second
      // call would add a third entry for a configuration that is not new.
      final annexB = Uint8List.fromList([
        0, 0, 0, 1, 0x67, 0x64, 0x00, 0x1f, 0xac, 0xd9, 0x40, //
        0x50, 0x05, 0xbb, 0x01, 0x6a, 0x02, 0x02, 0x02, 0x80,
        0, 0, 0, 1, 0x68, 0xeb, 0xe3, 0xcb, 0x22, 0xc0,
      ]);
      final record = buildAvcC(annexB)!;

      final m = _open();
      await m.writeHeader();
      await _write(m, 5);
      expect(m.setTrackConfig(0, annexB), Mp4ConfigChange.added);
      expect(m.setTrackConfig(0, record), Mp4ConfigChange.unchanged,
          reason: 'Annex-B and its avcC are one configuration, not two');
      await _write(m, 5, from: 5);
      await m.finish();

      expect(m.trackConfigCount(0), 2);
    });
  });
}
