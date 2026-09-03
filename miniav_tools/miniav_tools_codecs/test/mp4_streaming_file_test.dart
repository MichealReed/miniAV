/// Streaming file mode for the first-party ISO-BMFF writer.
///
/// The writer used to assemble the whole container in RAM and emit it at
/// `finish()`, which is why the recording sink stayed on FFmpeg: an hour of 4K
/// would sit in memory. Handed a `FileMuxerOutput` it now opens the file at
/// `writeHeader`, appends each sample as it arrives, and patches the reserved
/// 64-bit `mdat` largesize at the end — so only the sample tables are retained.
///
/// The contract that matters is that BOTH modes produce the same media: same
/// tracks, same samples, same timestamps. Byte identity is deliberately not
/// asserted — the streaming `mdat` header is the 16-byte largesize form and the
/// interleave differs — so everything goes through the demuxer instead.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';
import 'package:test/test.dart';

import 'mp4_box_probe.dart';

final _avcC = Uint8List.fromList([1, 0x64, 0, 0x1f, 0xff, 0xe1]);

VideoTrackInfo _videoTrack() => VideoTrackInfo(
      codec: VideoCodec.h264,
      width: 320,
      height: 240,
      frameRateNumerator: 30,
      frameRateDenominator: 1,
      extraData: CodecExtraData.video(VideoCodec.h264, _avcC),
    );

const _audioTrack =
    AudioTrackInfo(codec: AudioCodec.aac, sampleRate: 48000, channels: 2);

Uint8List _payload(int seed, int len) =>
    Uint8List.fromList(List.generate(len, (i) => (seed * 37 + i) & 0xFF));

/// A realistic interleave: video at 30fps with a keyframe every 5 frames, audio
/// in ~21ms frames, fed in PTS order the way a recorder does.
List<EncodedPacket> _feed() {
  final all = <EncodedPacket>[
    for (var i = 0; i < 24; i++)
      EncodedPacket(
        data: _payload(i, 40 + i),
        ptsUs: i * 33333,
        dtsUs: i * 33333,
        durationUs: 33333,
        isKeyframe: i % 5 == 0,
        trackIndex: 0,
      ),
    for (var i = 0; i < 37; i++)
      EncodedPacket(
        data: _payload(1000 + i, 16),
        ptsUs: i * 21333,
        dtsUs: i * 21333,
        durationUs: 21333,
        isKeyframe: true,
        trackIndex: 1,
      ),
  ];
  all.sort((a, b) => a.ptsUs.compareTo(b.ptsUs));
  return all;
}

Future<Map<int, List<EncodedPacket>>> _demuxByTrack(Uint8List mp4) async {
  final d = Mp4Demuxer.open(mp4);
  final out = <int, List<EncodedPacket>>{};
  for (var p = await d.readPacket(); p != null; p = await d.readPacket()) {
    (out[p.trackIndex] ??= []).add(p);
  }
  await d.close();
  return out;
}

Future<void> _run(PlatformMuxer m, List<EncodedPacket> packets) async {
  await m.writeHeader();
  for (final p in packets) {
    await m.writePacket(p);
  }
  await m.finish();
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('mp4_stream'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('streaming to a file and building in memory agree sample-for-sample',
      () async {
    final packets = _feed();
    final path = '${tmp.path}/streamed.mp4';

    final streamed = Mp4Muxer.open(MuxerConfig(
      container: Container.mp4,
      output: FileMuxerOutput(path),
      tracks: [_videoTrack(), _audioTrack],
    ));
    expect(streamed.ownsFileOutput, isTrue,
        reason: 'a FileMuxerOutput on the VM must take the streaming path');
    await _run(streamed, packets);
    await streamed.close();

    // Nothing was buffered for the caller: the bytes went to the file.
    expect(streamed.outputParts, isNull);
    expect(streamed.getBytes(), isNull);

    final memory = Mp4Muxer.open(MuxerConfig(
      container: Container.mp4,
      output: MuxerOutput.bytes(),
      tracks: [_videoTrack(), _audioTrack],
    ));
    expect(memory.ownsFileOutput, isFalse);
    await _run(memory, packets);

    final fromFile = File(path).readAsBytesSync();
    final fromMemory = Uint8List.fromList(memory.getBytes()!);
    await memory.close();

    final a = Mp4Demuxer.open(fromFile);
    final b = Mp4Demuxer.open(fromMemory);
    expect(a.tracks.length, b.tracks.length);
    for (var i = 0; i < a.tracks.length; i++) {
      final ta = a.tracks[i], tb = b.tracks[i];
      expect(ta.runtimeType, tb.runtimeType);
      if (ta is VideoTrackInfo && tb is VideoTrackInfo) {
        expect(ta.codec, tb.codec);
        expect(ta.width, tb.width);
        expect(ta.height, tb.height);
        expect(ta.extraData!.bytes, tb.extraData!.bytes);
      } else if (ta is AudioTrackInfo && tb is AudioTrackInfo) {
        expect(ta.codec, tb.codec);
        expect(ta.sampleRate, tb.sampleRate);
        expect(ta.channels, tb.channels);
      }
    }
    await a.close();
    await b.close();

    final gotFile = await _demuxByTrack(fromFile);
    final gotMem = await _demuxByTrack(fromMemory);
    expect(gotFile.keys.toSet(), gotMem.keys.toSet());
    for (final t in gotFile.keys) {
      final f = gotFile[t]!, m = gotMem[t]!;
      expect(f.length, m.length, reason: 'track $t sample count');
      for (var i = 0; i < f.length; i++) {
        expect(f[i].data, m[i].data, reason: 'track $t sample $i bytes');
        expect(f[i].ptsUs, m[i].ptsUs, reason: 'track $t sample $i pts');
        expect(f[i].dtsUs, m[i].dtsUs, reason: 'track $t sample $i dts');
        expect(f[i].isKeyframe, m[i].isKeyframe,
            reason: 'track $t sample $i keyframe flag');
      }
    }

    // ...and against what actually went in.
    final sent = <int, List<EncodedPacket>>{};
    for (final p in packets) {
      (sent[p.trackIndex] ??= []).add(p);
    }
    for (final t in sent.keys) {
      expect(gotFile[t]!.map((p) => p.data).toList(),
          sent[t]!.map((p) => p.data).toList());
      expect(gotFile[t]!.map((p) => p.ptsUs).toList(),
          sent[t]!.map((p) => p.ptsUs).toList());
    }
  });

  test('the streamed mdat carries a patched 64-bit largesize', () async {
    final path = '${tmp.path}/large.mp4';
    final m = Mp4Muxer.open(MuxerConfig(
      container: Container.m4a,
      output: FileMuxerOutput(path),
      tracks: const [_audioTrack],
    ));
    await _run(m, [
      for (var i = 0; i < 8; i++)
        EncodedPacket(
          data: _payload(i, 64),
          ptsUs: i * 21333,
          dtsUs: i * 21333,
          isKeyframe: true,
        ),
    ]);
    await m.close();

    final bytes = File(path).readAsBytesSync();
    final top = boxesIn(bytes, 0, bytes.length);
    expect(top.map((b) => b.type).toList(), ['ftyp', 'mdat', 'moov'],
        reason: 'moov-at-end (non-faststart), same layout as FFmpeg default');

    // The mdat header is the size==1 largesize form, and the largesize was
    // patched to the real total — an unpatched 0 would read as "to EOF" and
    // swallow the moov.
    final d = ByteData.sublistView(bytes);
    final mdatStart = top[0].payloadEnd;
    expect(d.getUint32(mdatStart, Endian.big), 1);
    expect(String.fromCharCodes(bytes.sublist(mdatStart + 4, mdatStart + 8)),
        'mdat');
    final largesize = (d.getUint32(mdatStart + 8, Endian.big) << 32) |
        d.getUint32(mdatStart + 12, Endian.big);
    expect(largesize, 16 + 8 * 64);
    expect(mdatStart + largesize, top[1].payloadEnd);
  });

  test('the same M1-M4 fixes apply in streaming mode', () async {
    final path = '${tmp.path}/fixes.mp4';
    const dts = [-66666, -33333, 0, 33333, 66666, 99999];
    const pts = [0, 99999, 33333, 66666, 166665, 133332];
    final m = Mp4Muxer.open(MuxerConfig(
      container: Container.mp4,
      output: FileMuxerOutput(path),
      tracks: [_videoTrack(), _audioTrack],
    ));
    await _run(m, [
      for (var i = 0; i < dts.length; i++)
        EncodedPacket(
          data: _payload(i, 20),
          ptsUs: 400000 + pts[i],
          dtsUs: 400000 + dts[i],
          isKeyframe: i == 0,
          trackIndex: 0,
        ),
      for (var i = 0; i < 8; i++)
        EncodedPacket(
          data: _payload(500 + i, 12),
          ptsUs: i * 21333,
          dtsUs: i * 21333,
          isKeyframe: true,
          trackIndex: 1,
        ),
    ]);
    await m.close();

    final bytes = File(path).readAsBytesSync();
    expect(findAll(bytes, 'ctts'), hasLength(1), reason: 'M1: B-frame offsets');
    expect(findAll(bytes, 'elst'), hasLength(1), reason: 'M3: A/V start offset');
    expect(findAll(bytes, 'stss'), hasLength(1),
        reason: 'M4: one video track has a real mix of sync/non-sync samples');

    final got = await _demuxByTrack(bytes);
    expect(got[1]!.first.ptsUs, 0);
    // 400000us later than the audio origin, offsets intact.
    expect(got[0]!.map((p) => p.ptsUs).toList(),
        [for (final p in pts) 400000 + p]);
  });

  test('a long interleaved recording opens in linear time', () async {
    // Streaming mode coalesces only CONSECUTIVE same-track samples, so a real
    // A/V interleave opens a chunk per packet, and stsc's run-length encoding
    // gains an entry every time the audio run length changes — tens of
    // thousands of both. Resolving sample offsets by rescanning the stsc table
    // for every chunk is quadratic in that, and open() appears to hang on a
    // recording of any length. The in-memory writer emitted one chunk and one
    // stsc entry per track, so nothing here was ever exercised at scale.
    const videoFrames = 40000; // ~22 minutes at 30fps
    final packets = <EncodedPacket>[
      for (var i = 0; i < videoFrames; i++)
        EncodedPacket(
          data: _payload(i, 24),
          ptsUs: i * 33333,
          dtsUs: i * 33333,
          durationUs: 33333,
          isKeyframe: i % 30 == 0,
          trackIndex: 0,
        ),
      for (var i = 0; i < videoFrames * 33333 ~/ 21333; i++)
        EncodedPacket(
          data: _payload(1000 + i, 8),
          ptsUs: i * 21333,
          dtsUs: i * 21333,
          durationUs: 21333,
          isKeyframe: true,
          trackIndex: 1,
        ),
    ]..sort((a, b) => a.ptsUs.compareTo(b.ptsUs));

    final path = '${tmp.path}/long.mp4';
    final m = Mp4Muxer.open(MuxerConfig(
      container: Container.mp4,
      output: FileMuxerOutput(path),
      tracks: [_videoTrack(), _audioTrack],
    ));
    await _run(m, packets);
    await m.close();

    final bytes = File(path).readAsBytesSync();
    final sw = Stopwatch()..start();
    final d = Mp4Demuxer.open(bytes);
    sw.stop();
    expect(d.tracks, hasLength(2));
    await d.close();
    expect(sw.elapsedMilliseconds, lessThan(250),
        reason: 'Mp4Demuxer.open took ${sw.elapsedMilliseconds}ms on a '
            '22-minute file — linear parsing is ~40ms and the quadratic stsc '
            'rescan is ~1.8s, so this is that rescan back');

    // The offsets the fast path produces are still the right ones.
    final got = await _demuxByTrack(bytes);
    expect(got[0]!, hasLength(videoFrames));
    for (final t in got.keys) {
      final first = got[t]!.first, last = got[t]!.last;
      final want = packets.where((p) => p.trackIndex == t).toList();
      expect(first.data, want.first.data, reason: 'track $t first sample');
      expect(last.data, want.last.data, reason: 'track $t last sample');
      expect(got[t]![got[t]!.length ~/ 2].data,
          want[want.length ~/ 2].data, reason: 'track $t middle sample');
    }
  });

  test('writePacket after finish throws in streaming mode too', () async {
    final path = '${tmp.path}/sealed.mp4';
    final m = Mp4Muxer.open(MuxerConfig(
      container: Container.m4a,
      output: FileMuxerOutput(path),
      tracks: const [_audioTrack],
    ));
    await _run(m, [
      EncodedPacket(
          data: _payload(0, 8), ptsUs: 0, dtsUs: 0, isKeyframe: true),
    ]);
    await expectLater(
      m.writePacket(EncodedPacket(
          data: _payload(1, 8), ptsUs: 21333, dtsUs: 21333, isKeyframe: true)),
      throwsA(isA<CodecRuntimeException>()),
    );
    await m.close();
    // The packet that threw must not have reached the file.
    final got = await _demuxByTrack(File(path).readAsBytesSync());
    expect(got[0], hasLength(1));
  });

  test('close() without finish() releases the file handle', () async {
    final path = '${tmp.path}/aborted.mp4';
    final m = Mp4Muxer.open(MuxerConfig(
      container: Container.m4a,
      output: FileMuxerOutput(path),
      tracks: const [_audioTrack],
    ));
    await m.writeHeader();
    await m.writePacket(
        EncodedPacket(data: _payload(0, 8), ptsUs: 0, dtsUs: 0));
    await m.close();
    // On Windows a still-open handle makes this throw.
    File(path).deleteSync();
    expect(File(path).existsSync(), isFalse);
  });

  group('backend wiring', () {
    test('createMuxer hands back the streaming muxer, unwrapped', () async {
      final path = '${tmp.path}/backend.mp4';
      final m = await ContainerFramingBackend().createMuxer(MuxerConfig(
        container: Container.m4a,
        output: FileMuxerOutput(path),
        tracks: const [_audioTrack],
      ));
      expect(m, isA<Mp4Muxer>(),
          reason: 'wrapping it in the collect-then-save adapter would put the '
              'whole recording back in RAM');
      await _run(m!, [
        for (var i = 0; i < 5; i++)
          EncodedPacket(
              data: _payload(i, 32),
              ptsUs: i * 21333,
              dtsUs: i * 21333,
              isKeyframe: true),
      ]);
      await m.close();
      final f = File(path);
      expect(f.existsSync(), isTrue);
      expect(f.lengthSync(), greaterThan(0));
      expect(String.fromCharCodes(f.readAsBytesSync().sublist(4, 8)), 'ftyp');
    });

    test('a non-streaming container still goes through the file adapter',
        () async {
      // Ogg is the one that still buffers — see _FileWritingMuxer's doc.
      final path = '${tmp.path}/out.opus';
      final m = await ContainerFramingBackend().createMuxer(MuxerConfig(
        container: Container.ogg,
        output: FileMuxerOutput(path),
        tracks: const [
          AudioTrackInfo(
              codec: AudioCodec.opus, sampleRate: 48000, channels: 2),
        ],
      ));
      expect(m, isNotNull);
      expect(m, isNot(isA<OggMuxer>()),
          reason: 'it has no file mode of its own, so it must be wrapped');
      await _run(m!, [
        EncodedPacket(data: _payload(0, 64), ptsUs: 0, dtsUs: 0),
      ]);
      await m.close();
      expect(File(path).existsSync(), isTrue);
    });
  });
}
