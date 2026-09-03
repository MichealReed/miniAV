/// The container demuxer, hosted on a worker.
///
/// Runs in a real browser against a real compiled payload, because that is the
/// only place the thing under test exists: on the VM this path falls back to
/// in-process parsing, so a green VM run would prove nothing about the case it
/// was written for.
@TestOn('browser')
@Tags(<String>['browser'])
library;

import 'dart:typed_data';

// Not the package barrel: it reaches native-only backends (dart:ffi) that
// cannot compile to JS. Import only the framing code under test.
import 'package:miniav_tools_codecs/src/framing/container_backend.dart'
    show ContainerFramingBackend;
import 'package:miniav_tools_codecs/src/framing/mp4_container.dart'
    show Mp4Muxer;
import 'package:miniav_tools_codecs/src/framing/worker_demuxer.dart';
import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';
import 'package:spawn/spawn.dart';
import 'package:test/test.dart';

/// The payload, addressed relative to the test page.
///
/// Copied under test/ by the CI step rather than referenced in lib/: the test
/// runner serves the package under a random per-run prefix and only exposes
/// the test tree, so lib/ is not reachable from a browser test.
///
/// Deliberately `.split`, not `.inline`: a split entry can never fall back to
/// the main thread, so if the payload is missing this fails loudly instead of
/// quietly proving nothing.
final workerEntry = SpawnEntry.split(
  demuxWorkerEntryPoint,
  asset: './workers/build/demux_worker.dart.js',
  protocol: registerDemuxProtocol,
);

/// A small but real MP4: 20 AAC frames with plausible timing.
Future<Uint8List> _syntheticMp4() async {
  const step = 21333; // ~1024 samples @ 48 kHz
  final muxer = Mp4Muxer.open(
    MuxerConfig(
      container: Container.mp4,
      output: MuxerOutput.bytes(),
      tracks: const <TrackInfo>[
        AudioTrackInfo(codec: AudioCodec.aac, sampleRate: 48000, channels: 2),
      ],
    ),
  );
  await muxer.writeHeader();
  for (var i = 0; i < 20; i++) {
    await muxer.writePacket(
      EncodedPacket(
        data: Uint8List.fromList(List<int>.generate(64, (j) => (i + j) & 0xff)),
        ptsUs: i * step,
        dtsUs: i * step,
        durationUs: step,
        isKeyframe: true,
      ),
    );
  }
  await muxer.finish();
  return Uint8List.fromList(muxer.getBytes()!);
}

void main() {
  setUpAll(registerDemuxProtocol);

  group('worker-hosted container demuxer', () {
    test('matches the in-process parse, packet for packet', () async {
      final bytes = await _syntheticMp4();

      final inProcess = ContainerFramingBackend.openInProcess(
        Uint8List.fromList(bytes),
        null,
      );
      expect(inProcess, isNotNull, reason: 'fixture must parse in process');

      final worker = await WorkerDemuxer.tryOpen(
        Uint8List.fromList(bytes),
        entry: workerEntry,
      );
      expect(
        worker,
        isNotNull,
        reason: 'the compiled payload must load; run `dart run spawn:build`',
      );
      addTearDown(worker!.close);

      expect(worker.tracks.length, inProcess!.tracks.length);
      expect(worker.durationUs, inProcess.durationUs);
      expect(worker.isSeekable, inProcess.isSeekable);

      var compared = 0;
      for (var i = 0; i < 25; i++) {
        final expected = await inProcess.readPacket();
        final actual = await worker.readPacket();
        if (expected == null) {
          expect(actual, isNull, reason: 'both must end at the same packet');
          break;
        }
        expect(actual, isNotNull, reason: 'worker ended early at packet $i');
        expect(actual!.ptsUs, expected.ptsUs, reason: 'packet $i pts');
        expect(actual.dtsUs, expected.dtsUs, reason: 'packet $i dts');
        expect(actual.isKeyframe, expected.isKeyframe, reason: 'packet $i key');
        expect(actual.trackIndex, expected.trackIndex, reason: 'packet $i trk');
        expect(actual.data, expected.data, reason: 'packet $i bytes');
        compared++;
      }
      expect(compared, greaterThan(10), reason: 'should have compared packets');
      await inProcess.close();
    });

    test('the track list survives the wire encoding', () async {
      final worker = await WorkerDemuxer.tryOpen(
        await _syntheticMp4(),
        entry: workerEntry,
      );
      expect(worker, isNotNull);
      addTearDown(worker!.close);

      final track = worker.tracks.single;
      expect(track, isA<AudioTrackInfo>());
      expect((track as AudioTrackInfo).codec, AudioCodec.aac);
      expect(track.sampleRate, 48000);
      expect(track.channels, 2);
    });

    test('a closed demuxer refuses work instead of hanging', () async {
      final worker = await WorkerDemuxer.tryOpen(
        await _syntheticMp4(),
        entry: workerEntry,
      );
      expect(worker, isNotNull);
      await worker!.close();
      await expectLater(
        worker.readPacket(),
        throwsA(isA<CodecRuntimeException>()),
      );
      await worker.close(); // idempotent
    });

    test('an unparseable container reports no worker, not a crash', () async {
      final rubbish = Uint8List.fromList(List<int>.filled(4096, 0x5A));
      expect(
        await WorkerDemuxer.tryOpen(rubbish, entry: workerEntry),
        isNull,
      );
    });

    test('a missing payload degrades to null, never to a broken player',
        () async {
      final absent = SpawnEntry.split(
        demuxWorkerEntryPoint,
        asset: '../lib/workers/build/does_not_exist.dart.js',
      );
      expect(
        await WorkerDemuxer.tryOpen(
          await _syntheticMp4(),
          entry: absent,
          timeout: const Duration(seconds: 3),
        ),
        isNull,
      );
    });
  });
}
