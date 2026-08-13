// End-to-end video playback through `MiniavPlayer.openSource`: container bytes
// in, hardware decode, GPU NV12→RGBA convert, frames out the present path.
//
// Everything below the Flutter platform channel is REAL: the first-party MP4
// demuxer, the Media Foundation D3D11 decoder, minigpu/Dawn, the shared output
// texture and the NV12 converter all run. Only `MethodChannel('minigpu_view')`
// is mocked, because the host plugin genuinely is not registered in a headless
// `flutter test` process — without the mock every present throws
// `UnsupportedPreviewException` and `onFirstFrame` can never complete.
//
// The HEVC case is the regression: `openSource` built its `DecoderConfig` from
// the container's codec + extradata and DROPPED the coded dimensions. The MF
// HEVC decoder MFT will not accept a single packet without a frame size on its
// input type, so HEVC through `openSource` opened a decode session that could
// never produce a frame — a black screen with no error and no fallback. Note
// what it takes to catch that: asserting the negotiated backend's NAME passes
// either way, and asserting "a frame appeared" passes either way once the
// decoder declines and FFmpeg picks it up. Both together are the test.
//
// The HEVC input is a COMMITTED base64 fixture, not an encode: building it with
// the MF HEVC *encoder* MFT gated the only regression test for that fix on an
// optional Windows component, on top of the hardware-decoder gate it already
// needs — so on most machines the guard evaporated into a skip.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miniav_player/miniav_player.dart';
import 'package:miniav_tools_codecs/miniav_tools_codecs.dart'
    show MfDecodeBackend;
import 'package:minigpu/minigpu.dart' show Minigpu;

import 'fixtures/hevc_mp4_fixture.dart';

/// Shared asset dir of the codecs package (fixtures live next to the codec
/// that produces them). Everything in there is generated (ffmpeg CLI, see
/// .github/workflows/dart-ci.yml) and gitignored, so every read is guarded.
final _assets = File.fromUri(
  Directory.current.uri.resolve('../miniav_tools_codecs/test/assets/'),
).path;

Uint8List? _asset(String name) {
  final f = File('$_assets/$name');
  if (!f.existsSync()) {
    markTestSkipped('$name fixture absent (generate with the ffmpeg CLI — '
        'see .github/workflows/dart-ci.yml)');
    return null;
  }
  return Uint8List.fromList(f.readAsBytesSync());
}

/// Does this machine expose a Media Foundation HARDWARE decoder MFT for
/// [codec]? Asked through the backend's public capability probe — the same
/// answer the negotiator acts on.
Future<bool> _hasMfHardwareDecode(VideoCodec codec) async {
  final caps = await MfDecodeBackend()
      .probe(CodecQuery.video(codec, CodecDirection.decode));
  return caps.isNotEmpty;
}

/// Waits until the demux pump is in its END-OF-STREAM TAIL: the container is
/// exhausted (no packet read for 200 ms) while ≥2 decoded frames are still
/// queued for the screen and [isEnded] has not fired. That is the window where
/// pause/seek used to wedge the tail waits.
///
/// The window is wide on this fixture: frames the decoder holds for B-frame
/// reordering count against NEITHER decode-ahead bound, so the demuxer reaches
/// EOF almost immediately and the tail is most of the file's ~1 s of pacing.
/// Wide or not it is POLLED for and reported, never assumed — a caller that
/// misses it retries with a fresh player instead of asserting on a state it
/// never reached.
Future<bool> _waitForTail(MiniavPlayer player, bool Function() isEnded,
    {Duration limit = const Duration(seconds: 20)}) async {
  final deadline = DateTime.now().add(limit);
  var lastPackets = -1;
  var stableMs = 0;
  while (DateTime.now().isBefore(deadline)) {
    final s = player.stats;
    if (s.videoPacketsSubmitted == lastPackets) {
      stableMs += 10;
    } else {
      stableMs = 0;
      lastPackets = s.videoPacketsSubmitted;
    }
    if (stableMs >= 200 && s.videoQueueDepth >= 2 && !isEnded()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return false;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  // One app-owned GPU for the whole file. Each player owning its own would
  // destroy the Dawn device on close(); a device created afterwards in the
  // same process can no longer allocate shared output textures, and the
  // presenter silently degrades to the CPU fallback — which cannot accept the
  // decoder's D3D11 handle at all. Sharing one is also the documented way to
  // run several players.
  Minigpu? gpu;
  var gpuError = '';

  setUpAll(() async {
    // The capability probes below and any fixture built through the
    // `MiniAVTools` facade negotiate over the GLOBAL registry, which nothing
    // populates implicitly — `openSource` registers as a side effect, so
    // without this every test but the first depends on test ORDER and running
    // one test with `--plain-name` reports a missing codec that is installed.
    registerPlayerBackends();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('minigpu_view'),
      (call) async {
        if (call.method != 'present') return null;
        final args = (call.arguments as Map).cast<String, Object?>();
        return <String, Object?>{
          'textureId': 1,
          'width': args['width'] ?? 0,
          'height': args['height'] ?? 0,
          'presentedAtUs': DateTime.now().microsecondsSinceEpoch,
        };
      },
    );
    try {
      final g = Minigpu();
      await g.init();
      gpu = g;
    } catch (e) {
      gpuError = '$e';
    }
  });

  tearDownAll(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('minigpu_view'),
      null,
    );
    await gpu?.destroy();
  });

  /// Skips (loudly) rather than failing when the test harness cannot bring up
  /// a GPU — the pipeline under test is genuinely unexercisable then.
  bool requireGpu() {
    if (gpu != null) return true;
    // ignore: avoid_print
    print('SKIP: minigpu/Dawn did not initialise in this harness: $gpuError');
    markTestSkipped('no GPU in this test harness: $gpuError');
    return false;
  }

  /// Waits until [test] holds or [limit] elapses. Playback is pts-paced, so
  /// frames arrive on the media clock, not immediately.
  Future<void> waitFor(bool Function() test,
      {Duration limit = const Duration(seconds: 15)}) async {
    final deadline = DateTime.now().add(limit);
    while (!test() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  group('openSource video', () {
    test('h264 mp4 decodes and reaches the present path', () async {
      if (!requireGpu()) return;
      final bytes = _asset('bframes.mp4');
      if (bytes == null) return;
      final errors = <Object>[];
      final player = await MiniavPlayer.openSource(
        MediaSource.bytes(bytes),
        enableAudio: false,
        gpu: gpu,
        onError: (e, _) => errors.add(e),
      );
      try {
        // The fix itself, asserted where it is observable on every platform:
        // the container's coded dims reach the decoder's config.
        expect(player.videoDecoderConfig?.width, isNotNull,
            reason: 'openSource dropped the container coded width');
        expect(player.videoDecoderConfig!.width, greaterThan(0));
        expect(player.videoDecoderConfig!.height, greaterThan(0));
        // Setting the dims also sets MF_MT_FRAME_SIZE on the H.264 MFT's INPUT
        // type, which it never carried before. If that makes SetInputType fail
        // the MF decoder returns null and FFmpeg silently takes over — every
        // other assertion here still passes, so the backend name is the only
        // witness.
        if (await _hasMfHardwareDecode(VideoCodec.h264)) {
          expect(player.videoDecoderBackend, 'mf_decode',
              reason: 'H.264 fell off the hardware decoder on a machine that '
                  'has an MF H.264 decoder MFT');
        }
        var first = true;
        await player.onFirstFrame
            .timeout(const Duration(seconds: 30), onTimeout: () => first = false);
        expect(first, isTrue,
            reason: 'no frame ever reached the present path '
                '(backend ${player.videoDecoderBackend}, errors $errors)');
        expect(player.usingCpuFallback, isFalse,
            reason: 'zero-copy present unavailable — this machine cannot '
                'exercise the path under test');
        expect(player.duration, isNotNull);
        await waitFor(() => player.stats.videoFramesPresented > 5);
        expect(player.stats.videoFramesPresented, greaterThan(5));
        expect(player.videoFramesDecoded, greaterThan(5));
        expect(player.videoDecodeErrorCount, 0);
        expect(player.presentErrorCount, 0);
        expect(errors, isEmpty, reason: 'player reported errors: $errors');
      } finally {
        await player.close();
      }
    }, timeout: const Timeout(Duration(seconds: 180)));

    test('hevc mp4 carries the container dims into the DecoderConfig',
        () async {
      // Runs wherever ANY HEVC decoder exists (hardware MF or FFmpeg
      // software): the dims plumbing is platform-independent even though the
      // decoder that needs it is not.
      if (!requireGpu()) return;
      final MiniavPlayer player;
      try {
        player = await MiniavPlayer.openSource(
          MediaSource.bytes(hevc320x240Mp4()),
          enableAudio: false,
          gpu: gpu,
        );
      } on NoBackendForCodecException {
        markTestSkipped('no HEVC decoder on this machine');
        return;
      }
      try {
        expect(player.videoDecoderConfig?.width, hevcFixtureWidth);
        expect(player.videoDecoderConfig?.height, hevcFixtureHeight);
      } finally {
        await player.close();
      }
    }, timeout: const Timeout(Duration(seconds: 180)));

    test('hevc mp4 lands on the hardware decoder AND produces frames',
        () async {
      if (!requireGpu()) return;
      if (!await _hasMfHardwareDecode(VideoCodec.hevc)) {
        markTestSkipped('no hardware HEVC decoder MFT');
        return;
      }
      final errors = <Object>[];
      final player = await MiniavPlayer.openSource(
        MediaSource.bytes(hevc320x240Mp4()),
        enableAudio: false,
        gpu: gpu,
        onError: (e, _) => errors.add(e),
      );
      try {
        // Half the bug: without the container's dims the MF decoder declines
        // (it cannot configure its input type) and FFmpeg quietly takes over,
        // losing the hardware path.
        expect(player.videoDecoderBackend, 'mf_decode',
            reason: 'HEVC fell off the hardware decoder — openSource is not '
                'passing the container dims the MF HEVC MFT requires');
        // The other half: before mf_decoder declined, it accepted the config
        // WITHOUT dims and then swallowed every packet forever.
        var first = true;
        await player.onFirstFrame
            .timeout(const Duration(seconds: 30), onTimeout: () => first = false);
        expect(first, isTrue,
            reason: 'the HEVC decoder produced no frame at all '
                '(errors: $errors)');
        expect(player.usingCpuFallback, isFalse);
        await waitFor(() => player.stats.videoFramesPresented > 5);
        expect(player.stats.videoFramesPresented, greaterThan(5));
        expect(player.videoDecodeErrorCount, 0);
        expect(player.presentErrorCount, 0);
      } finally {
        await player.close();
      }
    }, timeout: const Timeout(Duration(seconds: 300)));

    test('hevc mp4 plays with FFmpeg excluded', () async {
      // Name-free form of the same guard: with no software fallback in the
      // registry, dropping the dims leaves NO decoder for HEVC and openSource
      // throws outright.
      if (!requireGpu()) return;
      if (!await _hasMfHardwareDecode(VideoCodec.hevc)) {
        markTestSkipped('no hardware HEVC decoder MFT');
        return;
      }
      final player = await MiniavPlayer.openSource(
        MediaSource.bytes(hevc320x240Mp4()),
        enableAudio: false,
        gpu: gpu,
        preference: BackendPreference.excluded({'ffmpeg'}),
      );
      try {
        var first = true;
        await player.onFirstFrame
            .timeout(const Duration(seconds: 30), onTimeout: () => first = false);
        expect(first, isTrue);
        expect(player.videoDecodeErrorCount, 0);
      } finally {
        await player.close();
      }
    }, timeout: const Timeout(Duration(seconds: 300)));

    test('onEnded waits for the video tail to reach the screen', () async {
      // `onEnded` used to complete as soon as the drain handed the tail
      // FRAMES to the scheduler — which then spent the rest of the file's
      // media time pacing them to the screen. An app that closed the player
      // (or tore down the view) on `onEnded` cut the ending off.
      if (!requireGpu()) return;
      final bytes = _asset('bframes.mp4');
      if (bytes == null) return;
      final errors = <Object>[];
      final player = await MiniavPlayer.openSource(
        MediaSource.bytes(bytes),
        enableAudio: false,
        gpu: gpu,
        onError: (e, _) => errors.add(e),
      );
      try {
        var timedOut = false;
        await player.onEnded.timeout(const Duration(seconds: 60),
            onTimeout: () => timedOut = true);
        // Sample the counters with NO await in between: a single suspension
        // here would let an in-flight present land and hide the bug.
        final stats = player.stats;
        final decoded = player.videoFramesDecoded;
        final settled = stats.videoFramesPresented +
            stats.videoFramesDroppedLate +
            stats.videoFramesDroppedSuperseded;
        // ignore: avoid_print
        print('[tail] decoded=$decoded presented=${stats.videoFramesPresented} '
            'droppedLate=${stats.videoFramesDroppedLate} '
            'queueDepth=${stats.videoQueueDepth}');
        expect(timedOut, isFalse, reason: 'onEnded never completed');
        expect(player.presentErrorCount, 0);
        expect(errors, isEmpty, reason: 'player reported errors: $errors');
        // Not a tautology: the counters below are also satisfied by a file
        // that decoded nothing.
        expect(decoded, greaterThan(5));
        expect(stats.videoFramesPresented, greaterThan(5),
            reason: 'the tail was dropped rather than shown');
        // Every decoded frame is accounted for — presented or deliberately
        // dropped. Anything missing is a frame still in flight, which is
        // exactly what onEnded now promises has finished.
        expect(settled, decoded,
            reason: '$decoded frames decoded but only $settled reached the '
                'screen or a drop counter at onEnded — the tail was still '
                'being paced');
        expect(stats.videoQueueDepth, 0);
      } finally {
        await player.close();
      }
    }, timeout: const Timeout(Duration(seconds: 180)));

    test('close before end-of-stream completes onEnded', () async {
      // `onEnded` is what an app awaits to advance a playlist. The native path
      // only completed it from the end-of-stream branch of the demux pump, and
      // close() makes that loop exit at the top — so stopping playback early
      // left the awaiting future hanging forever (the MSE path completed it).
      if (!requireGpu()) return;
      final bytes = _asset('bframes.mp4');
      if (bytes == null) return;
      final player = await MiniavPlayer.openSource(
        MediaSource.bytes(bytes),
        enableAudio: false,
        gpu: gpu,
      );
      var endedBeforeClose = false;
      unawaited(player.onEnded.then((_) => endedBeforeClose = true));
      await player.onFirstFrame.timeout(const Duration(seconds: 30));
      // Not a tautology: the file is still playing, so this close really is
      // the early one the bug was about.
      expect(endedBeforeClose, isFalse,
          reason: 'the stream already ended — nothing early was closed');
      await player.close();
      var timedOut = false;
      await player.onEnded.timeout(const Duration(seconds: 10),
          onTimeout: () => timedOut = true);
      expect(timedOut, isFalse,
          reason: 'onEnded never completed after close(): an app awaiting it '
              'to advance a playlist hangs forever');
    }, timeout: const Timeout(Duration(seconds: 180)));

    test('a pause during the tail holds onEnded until resume', () async {
      // A pause freezes the media clock, so the queued tail cannot present and
      // the paused decode pump cannot drain its packet queue. The tail waits
      // used to mistake that for "not due yet" and time out into a FALSE
      // completion: onEnded fired on a paused player with frames still queued.
      if (!requireGpu()) return;
      final bytes = _asset('bframes.mp4');
      if (bytes == null) return;
      var caught = false;
      for (var attempt = 0; attempt < 3 && !caught; attempt++) {
        final player = await MiniavPlayer.openSource(
          MediaSource.bytes(bytes),
          enableAudio: false,
          gpu: gpu,
        );
        try {
          var ended = false;
          unawaited(player.onEnded.then((_) => ended = true));
          await player.onFirstFrame.timeout(const Duration(seconds: 30));
          if (!await _waitForTail(player, () => ended)) continue;
          caught = true;
          player.pause();
          // Must outlast the scheduler's ABSOLUTE backstop (30 s): that bound
          // is exactly where the false completion happened, so a shorter hold
          // would pass either way.
          await Future<void>.delayed(const Duration(seconds: 34));
          final depth = player.stats.videoQueueDepth;
          expect(ended, isFalse,
              reason: 'onEnded completed while paused with $depth frames still '
                  'queued — the tail never reached the screen');
          player.resume();
          var timedOut = false;
          await player.onEnded.timeout(const Duration(seconds: 30),
              onTimeout: () => timedOut = true);
          final stats = player.stats;
          final decoded = player.videoFramesDecoded;
          final settled = stats.videoFramesPresented +
              stats.videoFramesDroppedLate +
              stats.videoFramesDroppedSuperseded;
          expect(timedOut, isFalse,
              reason: 'onEnded never completed on resume');
          expect(decoded, greaterThan(5));
          expect(settled, decoded,
              reason: '$decoded decoded but only $settled settled at onEnded');
          expect(stats.videoQueueDepth, 0);
          expect(player.videoDecodeErrorCount, 0,
              reason: 'decode errors after the paused tail — the decoders were '
                  'flushed with packets still queued');
        } finally {
          await player.close();
        }
      }
      expect(caught, isTrue,
          reason: 'never observed the end-of-stream tail in 3 passes — the '
              'timing this test targets was not exercised');
    }, timeout: const Timeout(Duration(seconds: 300)));

    test('a seek during the tail is not held by the tail wait', () async {
      // seek() quiesces the pumps before touching decoders/queues. The pump
      // sat in the end-of-stream present-wait, which watched neither `seeking`
      // nor the queue it would need cleared — so the quiesce poll burned its
      // whole 1 s bound and then tore the decoders down with the pump still
      // live, on EVERY seek in the tail window.
      if (!requireGpu()) return;
      final bytes = _asset('bframes.mp4');
      if (bytes == null) return;
      var caught = false;
      for (var attempt = 0; attempt < 3 && !caught; attempt++) {
        final player = await MiniavPlayer.openSource(
          MediaSource.bytes(bytes),
          enableAudio: false,
          gpu: gpu,
        );
        try {
          var ended = false;
          unawaited(player.onEnded.then((_) => ended = true));
          await player.onFirstFrame.timeout(const Duration(seconds: 30));
          if (!await _waitForTail(player, () => ended)) continue;
          caught = true;
          final decodedBefore = player.videoFramesDecoded;
          final presentedBefore = player.stats.videoFramesPresented;
          final depthBefore = player.stats.videoQueueDepth;
          final sw = Stopwatch()..start();
          await player.seek(Duration.zero);
          sw.stop();
          final presentedDuring =
              player.stats.videoFramesPresented - presentedBefore;
          // ignore: avoid_print
          print('[tail-seek] seek took ${sw.elapsedMilliseconds} ms, '
              'presented $presentedDuring of $depthBefore queued during it');
          // Timing-free statement of the same defect: the pump sat in the
          // tail's present-wait, so the seek could not start until the WHOLE
          // queued tail had been paced to the screen — the frames it is about
          // to discard, one media-clock frame interval each.
          expect(presentedDuring, lessThanOrEqualTo(1),
              reason: 'the seek waited for $presentedDuring queued frames to '
                  'present before it could quiesce the pump — the tail wait '
                  'ignored the seek');
          // …and playback really restarted from the top.
          await waitFor(
              () => player.videoFramesDecoded > decodedBefore,
              limit: const Duration(seconds: 10));
          expect(player.videoFramesDecoded, greaterThan(decodedBefore),
              reason: 'nothing decoded after seeking out of the tail');
          expect(player.videoDecodeErrorCount, 0);
        } finally {
          await player.close();
        }
      }
      expect(caught, isTrue,
          reason: 'never observed the end-of-stream tail in 3 passes — the '
              'timing this test targets was not exercised');
    }, timeout: const Timeout(Duration(seconds: 300)));

    test('seek lands at the target and playback resumes', () async {
      if (!requireGpu()) return;
      final bytes = _asset('bframes.mp4');
      if (bytes == null) return;
      final errors = <Object>[];
      final player = await MiniavPlayer.openSource(
        MediaSource.bytes(bytes),
        enableAudio: false,
        gpu: gpu,
        onError: (e, _) => errors.add(e),
      );
      try {
        await player.onFirstFrame.timeout(const Duration(seconds: 30));
        expect(player.isSeekable, isTrue);
        // bframes.mp4 is 1 s at 10 fps: ten frames, 100 ms apart, one GOP
        // (ffmpeg -f lavfi -i testsrc=duration=1:rate=10 -bf 2 -g 10).
        final total = player.duration!;
        expect(total.inMilliseconds, greaterThan(200));

        // Let the first pass play out — presentation is paced on the media
        // clock, so this takes real time.
        await Future<void>.delayed(total + const Duration(milliseconds: 500));
        final presentedBefore = player.stats.videoFramesPresented;
        final decodeErrorsBefore = player.videoDecodeErrorCount;
        final presentErrorsBefore = player.presentErrorCount;
        expect(presentedBefore, greaterThan(4));

        final target = total ~/ 2;
        await player.seek(target);
        await Future<void>.delayed(total + const Duration(milliseconds: 500));
        final tail = player.stats.videoFramesPresented - presentedBefore;
        // ignore: avoid_print
        print('[seek] duration=$total pass1=$presentedBefore tail=$tail '
            'position=${player.position}');

        // Playback resumed…
        expect(tail, greaterThan(1),
            reason: 'no frames presented after seeking to $target');
        // …at the TARGET: half the fixture is ~5 frames, restarting from the
        // landing keyframe instead of the requested position replays all ten.
        // Bounded absolutely on the fixture, NOT as a ratio of the first
        // pass — the scheduler is free to drop late frames under load, so a
        // correct seek could otherwise fail on a slow/loaded machine.
        expect(tail, lessThanOrEqualTo(6),
            reason: 'presented $tail frames after seeking to the midpoint of a '
                'ten-frame file — playback restarted from the top instead of '
                'from $target');
        // Media time is anchored by the first frame actually SHOWN, so it
        // reads back the pts the seek really resumed at.
        expect(player.position, isNotNull);
        expect(player.position!, greaterThanOrEqualTo(target),
            reason: 'media time is behind the seek target — the first frame '
                'shown came from before $target');
        // A mid-GOP landing is what shows up as a smeared first frame; here it
        // would mean decoding P/B frames with no reference.
        expect(player.videoDecodeErrorCount, decodeErrorsBefore,
            reason: 'decode errors after the seek — the demuxer did not land '
                'on a keyframe');
        expect(player.presentErrorCount, presentErrorsBefore);
        expect(errors, isEmpty, reason: 'player reported errors: $errors');
      } finally {
        await player.close();
      }
    }, timeout: const Timeout(Duration(seconds: 180)));
  });
}
