/// A `FileMuxerOutput` must be refused on web at CREATE time.
///
/// Run with:
///   dart test -p chrome test/mp4_web_file_output_test.dart
///
/// The browser has no filesystem, so a file destination can never be honoured.
/// The old failure shape was to accept the config anyway, buffer the entire
/// recording, and only admit it at `finish()` — by which point the caller has
/// spent the memory, the recording is over, and there is nothing left to fall
/// back to. Failing at `createMuxer` is the difference between "pick a
/// different output" and "your recording is gone".
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:miniav_tools_codecs/web.dart';
import 'package:test/test.dart';

void main() {
  test('createMuxer rejects FileMuxerOutput on web', () async {
    await expectLater(
      ContainerFramingBackend().createMuxer(const MuxerConfig(
        container: Container.m4a,
        output: FileMuxerOutput('/nope/out.m4a'),
        tracks: [
          AudioTrackInfo(codec: AudioCodec.aac, sampleRate: 48000, channels: 2),
        ],
      )),
      throwsA(isA<CodecInitException>()),
    );
  });

  test('BytesMuxerOutput still works on web and produces an ISO-BMFF file',
      () async {
    final m = await ContainerFramingBackend().createMuxer(const MuxerConfig(
      container: Container.m4a,
      output: BytesMuxerOutput(),
      tracks: [
        AudioTrackInfo(codec: AudioCodec.aac, sampleRate: 48000, channels: 2),
      ],
    ));
    expect(m, isNotNull);
    await m!.writeHeader();
    for (var i = 0; i < 4; i++) {
      await m.writePacket(EncodedPacket(
        data: Uint8List.fromList(List.filled(32, 0x5A)),
        ptsUs: i * 21333,
        dtsUs: i * 21333,
        isKeyframe: true,
      ));
    }
    await m.finish();
    final bytes = m.getBytes()!;
    await m.close();
    expect(bytes.length, greaterThan(0));
    expect(String.fromCharCodes(bytes.sublist(4, 8)), 'ftyp');
  });
}
