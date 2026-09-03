/// Streaming file mode for the WAV and ADTS writers.
///
/// Both used to be whole-file builders: every byte of a recording sat in a
/// BytesBuilder until `finish()`, so an open-ended capture grew without bound
/// and only then got written. Handed a `FileMuxerOutput` they now append as
/// they go — WAV patching its two RIFF lengths at the end, ADTS patching
/// nothing because it has no length fields at all.
///
/// The contract is BYTE identity with the in-memory mode: the file must be
/// exactly what `getBytes()` would have produced.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';
import 'package:test/test.dart';

const _pcmTrack =
    AudioTrackInfo(codec: AudioCodec.pcmS16le, sampleRate: 48000, channels: 2);
const _aacTrack =
    AudioTrackInfo(codec: AudioCodec.aac, sampleRate: 48000, channels: 2);

Uint8List _payload(int seed, int len) =>
    Uint8List.fromList(List.generate(len, (i) => (seed * 31 + i * 7) & 0xFF));

/// Packets shaped like a multi-minute recording: 4 KiB of PCM per 21 ms is
/// ~48 kHz stereo s16, so 6000 packets is a bit over two minutes.
List<EncodedPacket> _feed(int count, int bytes) => [
      for (var i = 0; i < count; i++)
        EncodedPacket(
          data: _payload(i, bytes),
          ptsUs: i * 21333,
          dtsUs: i * 21333,
          durationUs: 21333,
          isKeyframe: true,
        ),
    ];

Future<void> _run(PlatformMuxer m, List<EncodedPacket> packets) async {
  await m.writeHeader();
  for (final p in packets) {
    await m.writePacket(p);
  }
  await m.finish();
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('pcm_aac_stream'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('WAV', () {
    test('a streamed file is byte-identical to the in-memory build', () async {
      final packets = _feed(6000, 4096); // ~24 MB of PCM, >2 minutes
      final path = '${tmp.path}/streamed.wav';

      final streamed = WavMuxer.open(MuxerConfig(
        container: Container.wav,
        output: FileMuxerOutput(path),
        tracks: const [_pcmTrack],
      ));
      expect(streamed.ownsFileOutput, isTrue,
          reason: 'a FileMuxerOutput on the VM must take the streaming path');
      await _run(streamed, packets);
      await streamed.close();
      // Nothing was retained for the caller: the bytes went to the file.
      expect(streamed.getBytes(), isNull);

      final memory = WavMuxer.open(const MuxerConfig(
        container: Container.wav,
        output: BytesMuxerOutput(),
        tracks: [_pcmTrack],
      ));
      expect(memory.ownsFileOutput, isFalse);
      await _run(memory, packets);
      final fromMemory = Uint8List.fromList(memory.getBytes()!);
      await memory.close();

      final fromFile = File(path).readAsBytesSync();
      expect(fromFile.length, fromMemory.length);
      expect(fromFile, fromMemory);
    });

    test('the two RIFF lengths are patched, not left at 0', () async {
      final packets = _feed(50, 512);
      final path = '${tmp.path}/patched.wav';
      final m = WavMuxer.open(MuxerConfig(
        container: Container.wav,
        output: FileMuxerOutput(path),
        tracks: const [_pcmTrack],
      ));
      await _run(m, packets);
      await m.close();

      final bytes = File(path).readAsBytesSync();
      final d = ByteData.sublistView(bytes);
      const pcmLen = 50 * 512;
      expect(d.getUint32(4, Endian.little), 36 + pcmLen,
          reason: 'RIFF chunk size');
      expect(d.getUint32(40, Endian.little), pcmLen, reason: 'data chunk size');
      expect(bytes.length, 44 + pcmLen);
    });

    test('the streamed file demuxes back to the samples that went in',
        () async {
      final packets = _feed(40, 1024);
      final path = '${tmp.path}/roundtrip.wav';
      final m = WavMuxer.open(MuxerConfig(
        container: Container.wav,
        output: FileMuxerOutput(path),
        tracks: const [_pcmTrack],
      ));
      await _run(m, packets);
      await m.close();

      final d = WavDemuxer.open(File(path).readAsBytesSync());
      final got = BytesBuilder();
      for (var p = await d.readPacket(); p != null; p = await d.readPacket()) {
        got.add(p.data);
      }
      final want = BytesBuilder();
      for (final p in packets) {
        want.add(p.data);
      }
      expect(got.toBytes(), want.toBytes());
      expect(d.durationUs, 40 * 1024 ~/ 4 * 1000000 ~/ 48000);
    });

    test('streaming holds no packet memory', () async {
      // A direct memory assertion is flaky, so this asserts the mechanism:
      // getBytes() cannot reconstruct the container, because nothing was kept.
      final path = '${tmp.path}/nomem.wav';
      final m = WavMuxer.open(MuxerConfig(
        container: Container.wav,
        output: FileMuxerOutput(path),
        tracks: const [_pcmTrack],
      ));
      await m.writeHeader();
      await m.writePacket(_feed(1, 4096).single);
      expect(m.getBytes(), isNull);
      await m.finish();
      await m.close();
      expect(File(path).lengthSync(), 44 + 4096);
    });

    test('close() without finish() releases the file handle', () async {
      final path = '${tmp.path}/aborted.wav';
      final m = WavMuxer.open(MuxerConfig(
        container: Container.wav,
        output: FileMuxerOutput(path),
        tracks: const [_pcmTrack],
      ));
      await m.writeHeader();
      await m.writePacket(_feed(1, 64).single);
      await m.close();
      // On Windows a still-open handle makes this throw.
      File(path).deleteSync();
      expect(File(path).existsSync(), isFalse);
    });

    test('an interrupted recording still reads back the samples it holds',
        () async {
      // The shape streaming mode made possible: the process dies (or finish()
      // throws and the recorder swallows it), so the two RIFF lengths are never
      // patched and the header says "empty" over real PCM. open() cannot throw
      // here either — a valid-looking WavDemuxer stops the negotiator falling
      // through to a demuxer that WOULD recover the audio.
      final packets = _feed(200, 1024);
      final path = '${tmp.path}/interrupted.wav';
      final m = WavMuxer.open(MuxerConfig(
        container: Container.wav,
        output: FileMuxerOutput(path),
        tracks: const [_pcmTrack],
      ));
      await m.writeHeader();
      for (final p in packets) {
        await m.writePacket(p);
      }
      await m.close(); // no finish(): both lengths stay 0 on disk

      final bytes = File(path).readAsBytesSync();
      const pcmLen = 200 * 1024;
      expect(bytes.length, 44 + pcmLen);
      expect(ByteData.sublistView(bytes).getUint32(40, Endian.little), 0,
          reason: 'the premise: the data-chunk length was never patched');

      final d = WavDemuxer.open(bytes);
      final got = BytesBuilder();
      for (var p = await d.readPacket(); p != null; p = await d.readPacket()) {
        got.add(p.data);
      }
      final want = BytesBuilder();
      for (final p in packets) {
        want.add(p.data);
      }
      expect(got.length, pcmLen, reason: 'every recorded byte is still there');
      expect(got.toBytes(), want.toBytes());
      expect(d.durationUs, pcmLen ~/ 4 * 1000000 ~/ 48000);
    });

    test('getBytes() after close() still returns the recording', () async {
      // close() auto-finishes and getBytes() has no ordering guard, so dropping
      // the buffer at close turned this into a 44-byte silent WAVE that still
      // parses — no exception, no null, no audio.
      final packets = _feed(20, 512);
      final m = WavMuxer.open(const MuxerConfig(
        container: Container.wav,
        output: BytesMuxerOutput(),
        tracks: [_pcmTrack],
      ));
      await _run(m, packets);
      final before = Uint8List.fromList(m.getBytes()!);
      await m.close();
      final after = m.getBytes();
      expect(after, isNotNull);
      expect(Uint8List.fromList(after!), before);
      expect(after.length, 44 + 20 * 512);
    });

    test('the backend hands back the streaming muxer, unwrapped', () async {
      final path = '${tmp.path}/backend.wav';
      final m = await ContainerFramingBackend().createMuxer(MuxerConfig(
        container: Container.wav,
        output: FileMuxerOutput(path),
        tracks: const [_pcmTrack],
      ));
      expect(m, isA<WavMuxer>(),
          reason: 'wrapping it in the collect-then-save adapter would put the '
              'whole recording back in RAM');
      await _run(m!, _feed(10, 256));
      await m.close();
      expect(File(path).lengthSync(), 44 + 10 * 256);
    });
  });

  group('ADTS', () {
    test('a streamed file is byte-identical to the in-memory build', () async {
      final packets = _feed(6000, 700); // ~4 MB, >2 minutes of AAC
      final path = '${tmp.path}/streamed.aac';

      final streamed = AdtsMuxer.open(MuxerConfig(
        container: Container.adts,
        output: FileMuxerOutput(path),
        tracks: const [_aacTrack],
      ));
      expect(streamed.ownsFileOutput, isTrue);
      await _run(streamed, packets);
      await streamed.close();
      expect(streamed.getBytes(), isNull);

      final memory = AdtsMuxer.open(const MuxerConfig(
        container: Container.adts,
        output: BytesMuxerOutput(),
        tracks: [_aacTrack],
      ));
      expect(memory.ownsFileOutput, isFalse);
      await _run(memory, packets);
      final fromMemory = Uint8List.fromList(memory.getBytes()!);
      await memory.close();

      final fromFile = File(path).readAsBytesSync();
      expect(fromFile.length, fromMemory.length);
      expect(fromFile, fromMemory);
    });

    test('the streamed file demuxes back to the payloads that went in',
        () async {
      final packets = _feed(64, 300);
      final path = '${tmp.path}/roundtrip.aac';
      final m = AdtsMuxer.open(MuxerConfig(
        container: Container.adts,
        output: FileMuxerOutput(path),
        tracks: const [_aacTrack],
      ));
      await _run(m, packets);
      await m.close();

      final d = AdtsDemuxer.open(File(path).readAsBytesSync());
      final got = <Uint8List>[];
      for (var p = await d.readPacket(); p != null; p = await d.readPacket()) {
        got.add(p.data);
      }
      expect(got.length, packets.length);
      for (var i = 0; i < got.length; i++) {
        expect(got[i], packets[i].data, reason: 'frame $i');
      }
      expect(d.durationUs, 64 * 1024 * 1000000 ~/ 48000);
    });

    test('getBytes() after close() still returns the recording', () async {
      final packets = _feed(20, 128);
      final m = AdtsMuxer.open(const MuxerConfig(
        container: Container.adts,
        output: BytesMuxerOutput(),
        tracks: [_aacTrack],
      ));
      await _run(m, packets);
      final before = Uint8List.fromList(m.getBytes()!);
      await m.close();
      final after = m.getBytes();
      expect(after, isNotNull);
      expect(Uint8List.fromList(after!), before);
      expect(after.length, 20 * (128 + 7));
    });

    test('close() without finish() releases the file handle', () async {
      final path = '${tmp.path}/aborted.aac';
      final m = AdtsMuxer.open(MuxerConfig(
        container: Container.adts,
        output: FileMuxerOutput(path),
        tracks: const [_aacTrack],
      ));
      await m.writeHeader();
      await m.writePacket(_feed(1, 64).single);
      await m.close();
      File(path).deleteSync();
      expect(File(path).existsSync(), isFalse);
    });

    test('the backend hands back the streaming muxer, unwrapped', () async {
      final path = '${tmp.path}/backend.aac';
      final m = await ContainerFramingBackend().createMuxer(MuxerConfig(
        container: Container.adts,
        output: FileMuxerOutput(path),
        tracks: const [_aacTrack],
      ));
      expect(m, isA<AdtsMuxer>());
      await _run(m!, _feed(10, 128));
      await m.close();
      expect(File(path).lengthSync(), 10 * (128 + 7));
    });
  });
}
