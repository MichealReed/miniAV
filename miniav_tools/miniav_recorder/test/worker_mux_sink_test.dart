/// The container writer, moved off the isolate that calls stop().
///
/// `finish()` builds the sample index in one synchronous pass — for a two-hour
/// recording, over half a million entries. On the recorder's normal path the
/// isolate paying for that is the one drawing the UI, so the app freezes at
/// exactly the moment somebody is waiting to be told their session was saved.
///
/// Driven through `spawnLocal`, which runs the handler on this thread behind
/// the REAL Worker protocol — every frame, request and event goes through the
/// same code an isolate would use, so the protocol is genuinely under test
/// and the assertions do not need a second thread to be deterministic.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:miniav_recorder/src/worker_mux_sink.dart';
import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';
import 'package:spawn/spawn.dart';
import 'package:test/test.dart';

/// Annex-B SPS+PPS, the shape a Media Foundation encoder hands over.
final _annexB = Uint8List.fromList([
  0, 0, 0, 1, //
  0x67, 0x64, 0x00, 0x1f, 0xac, 0xd9, 0x40, 0x50, 0x05, 0xbb, 0x01, 0x6a,
  0x02, 0x02, 0x02, 0x80, 0x00, 0x00, 0x03, 0x00, 0x80, 0x00, 0x00, 0x1e,
  0x07, 0x8c, 0x18, 0xcb,
  0, 0, 0, 1, //
  0x68, 0xeb, 0xec, 0xb2, 0x2c,
]);

Uint8List _idr() => Uint8List.fromList([
      ...[0, 0, 0, 1],
      0x65, 0x88, 0x84, 0x00, 0x10, 0xff, 0xfe, 0xf6, 0xf0,
    ]);

VideoTrackInfo _video({Uint8List? extra}) => VideoTrackInfo(
      codec: VideoCodec.h264,
      width: 640,
      height: 480,
      frameRateNumerator: 30,
      frameRateDenominator: 1,
      extraData:
          extra == null ? null : CodecExtraData.video(VideoCodec.h264, extra),
    );

void main() {
  late Directory tmp;
  late List<String> phases;
  late List<Object?> fatals;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mux_worker');
    phases = [];
    fatals = [];
  });
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<WorkerMuxSink?> open(
    String name, {
    Uint8List? extra,
    List<TrackInfo>? tracks,
  }) =>
      WorkerMuxSink.tryOpen(
        container: Container.mp4,
        path: '${tmp.path}/$name',
        tracks: tracks ?? [_video(extra: extra)],
        onPhase: phases.add,
        onFatal: fatals.add,
        spawner: spawnLocal,
      );

  Future<void> feed(WorkerMuxSink sink, {int frames = 4}) async {
    for (var i = 0; i < frames; i++) {
      await sink.writePacket(EncodedPacket(
        data: _idr(),
        ptsUs: i * 33333,
        dtsUs: i * 33333,
        durationUs: 33333,
        isKeyframe: true,
        trackIndex: 0,
      ));
    }
  }

  test('a recording written on a worker is a playable file', () async {
    final path = '${tmp.path}/hosted.mp4';
    final sink = (await open('hosted.mp4', extra: _annexB))!;
    expect(sink.backendName, ContainerFramingBackend.backendName);
    await feed(sink);
    final report = await sink.finish();
    await sink.close();

    expect(report.isClean, isTrue);
    final bytes = File(path).readAsBytesSync();
    final d = Mp4Demuxer.open(bytes);
    expect(d.tracks, hasLength(1));
    final track = d.tracks.single as VideoTrackInfo;
    expect(track.codec, VideoCodec.h264);
    expect(track.width, 640);
    expect(await d.readPacket(), isNotNull);
    await d.close();
  });

  test('both phases reach the host, in order, before finish resolves',
      () async {
    final sink = (await open('phases.mp4', extra: _annexB))!;
    await feed(sink);
    expect(phases, isEmpty, reason: 'nothing to report while recording');
    await sink.finish();
    await sink.close();
    expect(phases, ['writingIndex', 'closing']);
    // NOT covered here: that `writingIndex` is sent before the index work
    // rather than after it. Both orderings put the same two events on the
    // wire ahead of the response, so from the host they are indistinguishable
    // — the property is real (an event describing a freeze that already
    // finished is useless) but it lives in the worker's statement order and
    // is held by reading, not by this test.
  });

  test('a config record supplied later crosses to the worker', () async {
    // The deferred case: a hardware encoder that only publishes its sequence
    // header with the first frame. The record has to reach the container that
    // is no longer on this isolate.
    final path = '${tmp.path}/deferred.mp4';
    final sink = (await open('deferred.mp4'))!;
    expect(await sink.setTrackConfig(0, _annexB), Mp4ConfigChange.added);
    await feed(sink);
    final report = await sink.finish();
    await sink.close();

    expect(report.tracksMissingConfig, isEmpty);
    final d = Mp4Demuxer.open(File(path).readAsBytesSync());
    expect((d.tracks.single as VideoTrackInfo).extraData, isNotNull);
    await d.close();
  });

  test('a repeated config record reports unchanged, not a second entry',
      () async {
    final sink = (await open('repeat.mp4'))!;
    expect(await sink.setTrackConfig(0, _annexB), Mp4ConfigChange.added);
    expect(await sink.setTrackConfig(0, _annexB), Mp4ConfigChange.unchanged);
    await feed(sink);
    await sink.finish();
    await sink.close();
  });

  test('a track that never got a record is reported across the boundary',
      () async {
    // The diagnostic has to survive the move, or a broken track becomes
    // silent purely because the writer changed address.
    final sink = (await open('noconfig.mp4'))!;
    await feed(sink);
    final report = await sink.finish();
    await sink.close();
    expect(report.tracksMissingConfig, [0]);
    expect(report.isClean, isFalse);
  });

  test('a worker that will not start answers null, not an exception',
      () async {
    // A worker that cannot be had should cost the UI a freeze at stop, never
    // the recording: the caller falls back to writing in process.
    final sink = await WorkerMuxSink.tryOpen(
      container: Container.mp4,
      path: '${tmp.path}/nostart.mp4',
      tracks: [_video(extra: _annexB)],
      onPhase: phases.add,
      onFatal: fatals.add,
      spawner: (entry, {Object? message, Duration timeout = Duration.zero}) =>
          Future.error(StateError('no isolate for you')),
    );
    expect(sink, isNull);
  });

  test('the same thing works on a REAL isolate, not just the local protocol',
      () async {
    // spawnLocal exercises the protocol; it does not exercise the boundary.
    // The init message, the packet bytes and the report all have to survive an
    // actual isolate send, and nothing above this line would notice if they
    // did not.
    final path = '${tmp.path}/isolate.mp4';
    final sink = await WorkerMuxSink.tryOpen(
      container: Container.mp4,
      path: path,
      tracks: [_video(extra: _annexB)],
      onPhase: phases.add,
      onFatal: fatals.add,
    );
    expect(sink, isNotNull, reason: 'an isolate could not be started');
    await feed(sink!, frames: 8);
    final report = await sink.finish();
    await sink.close();

    expect(report.isClean, isTrue);
    expect(phases, ['writingIndex', 'closing']);
    final d = Mp4Demuxer.open(File(path).readAsBytesSync());
    expect(d.tracks, hasLength(1));
    var packets = 0;
    while (await d.readPacket() != null) {
      packets++;
    }
    expect(packets, 8, reason: 'every packet crossed and landed');
    await d.close();
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('a worker that dies mid-recording reports itself, once', () async {
    // Otherwise every write after it fails into the per-packet error log —
    // thousands of identical lines — and finish() fails too, so the recording
    // ends with no index and nothing said when it actually broke.
    final sink = (await open('dies.mp4', extra: _annexB))!;
    await feed(sink, frames: 2);
    expect(fatals, isEmpty);

    await sink.killForTest();
    await Future<void>.delayed(Duration.zero);
    expect(fatals, hasLength(1), reason: 'said once, when it happened');

    // And the writes that follow fail rather than being quietly dropped.
    await expectLater(feed(sink, frames: 1), throwsA(isA<Object>()));
  });

  test('closing normally is NOT reported as the worker dying', () async {
    // The teardown path ends the worker too. Reporting that would make every
    // clean stop look like a failure.
    final sink = (await open('clean.mp4', extra: _annexB))!;
    await feed(sink);
    await sink.finish();
    await sink.close();
    await Future<void>.delayed(Duration.zero);
    expect(fatals, isEmpty);
  });

  test('a muxer that DECLINES the tracks throws, and is not swallowed',
      () async {
    // The routing signal. Answering null here would send the container to
    // FFmpeg for a reason nobody could see — which is exactly how a machine
    // ended up on a full-file rewrite at stop for months.
    await expectLater(
      open('declined.mp4', tracks: const [
        AudioTrackInfo(codec: AudioCodec.flac, sampleRate: 48000, channels: 2),
      ]),
      throwsA(isA<Object>()),
    );
  });
}
