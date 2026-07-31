/// A `FileMuxerOutput` must actually produce a file.
///
/// The first-party muxers are whole-file builders that expose their result
/// through `getBytes()`. Handed a `FileMuxerOutput` they used to ignore the
/// path entirely and report complete success — `writeHeader`, `writePacket`,
/// `finish` and `close` all returned normally and no file was created. That is
/// the worst shape a bug can take: the caller has nothing to check and reports
/// "saved" to the user.
///
/// So this asserts against the filesystem, not against the return values.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('mux_file_out'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('MP4 FileMuxerOutput writes a real file', () async {
    final path = '${tmp.path}/out.mp4';
    // A minimal AAC-only MP4 — no video, so the test needs no encoder at all
    // and stays a pure container test.
    final muxer = await ContainerFramingBackend().createMuxer(
      MuxerConfig(
        container: Container.m4a,
        output: FileMuxerOutput(path),
        tracks: const [
          AudioTrackInfo(codec: AudioCodec.aac, sampleRate: 48000, channels: 2),
        ],
      ),
    );
    expect(muxer, isNotNull, reason: 'backend refused an AAC m4a config');

    await muxer!.writeHeader();
    for (var i = 0; i < 10; i++) {
      await muxer.writePacket(EncodedPacket(
        trackIndex: 0,
        data: Uint8List.fromList(List.filled(64, 0x21)),
        ptsUs: i * 21333,
        dtsUs: i * 21333,
        durationUs: 21333,
        isKeyframe: true,
      ));
    }
    await muxer.finish();
    await muxer.close();

    final f = File(path);
    expect(f.existsSync(), isTrue,
        reason: 'finish() reported success but wrote no file');
    expect(f.lengthSync(), greaterThan(0), reason: 'file is empty');
    // ISO-BMFF: bytes 4..8 of the first box are the 'ftyp' type.
    expect(String.fromCharCodes(f.readAsBytesSync().sublist(4, 8)), 'ftyp');
  });

  test('BytesMuxerOutput is unaffected and still returns bytes', () async {
    final muxer = await ContainerFramingBackend().createMuxer(
      const MuxerConfig(
        container: Container.m4a,
        output: BytesMuxerOutput(),
        tracks: [
          AudioTrackInfo(codec: AudioCodec.aac, sampleRate: 48000, channels: 2),
        ],
      ),
    );
    expect(muxer, isNotNull);
    await muxer!.writeHeader();
    await muxer.writePacket(EncodedPacket(
      trackIndex: 0,
      data: Uint8List.fromList(List.filled(64, 0x21)),
      ptsUs: 0,
      dtsUs: 0,
      durationUs: 21333,
      isKeyframe: true,
    ));
    await muxer.finish();
    expect(muxer.getBytes(), isNotNull);
    expect(muxer.getBytes()!.length, greaterThan(0));
    await muxer.close();
  });
}
