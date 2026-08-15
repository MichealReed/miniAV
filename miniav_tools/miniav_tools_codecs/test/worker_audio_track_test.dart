/// The player-facing audio track: sink + worker + clock, as one object.
///
/// The pieces underneath are covered elsewhere (audio_ring_sink_test.dart,
/// audio_playback_worker_test.dart). What is only testable here is what the
/// player actually depends on: that [WorkerAudioTrack.positionUs] tracks what
/// the DEVICE has played, that a seek moves it, and that pause stops it — and
/// that all three survive a main thread that is not paying attention.
@TestOn('browser')
@Tags(<String>['browser'])
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:miniav_tools_codecs/src/framing/ogg_container.dart'
    show OggMuxer;
import 'package:miniav_tools_codecs/src/web/web_codecs_audio_encoder.dart';
import 'package:miniav_tools_codecs/src/web/worker_audio_track.dart';
import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';
import 'package:test/test.dart';

@JS('SharedArrayBuffer')
external JSFunction? get _sharedArrayBufferCtor;

const int _kRate = 48000;
const int _kChannels = 2;
const int _kPacketFrames = 960;
const int _kPackets = 250; // 5 s, so a seek has somewhere to go

/// A real Ogg/Opus file, encoded in the browser.
Future<Uint8List> _oggOpus() async {
  final encoder = await WebCodecsAudioEncoder.create(
    const AudioEncoderConfig(
      codec: AudioCodec.opus,
      sampleRate: _kRate,
      channels: _kChannels,
      bitrateBps: 96000,
    ),
  );
  final packets = <EncodedPacket>[];
  for (var i = 0; i < _kPackets; i++) {
    final samples = Float32List(_kPacketFrames * _kChannels);
    for (var f = 0; f < _kPacketFrames; f++) {
      final v = 0.2 * sin(2 * pi * 440.0 * (i * _kPacketFrames + f) / _kRate);
      for (var c = 0; c < _kChannels; c++) {
        samples[f * _kChannels + c] = v;
      }
    }
    packets.addAll(
      await encoder.encode(
        pcm: samples.buffer.asUint8List(),
        format: MiniAVAudioFormat.f32,
        frameCount: _kPacketFrames,
        ptsUs: i * _kPacketFrames * 1000000 ~/ _kRate,
      ),
    );
  }
  packets.addAll(await encoder.flush());
  await encoder.close();

  final muxer = OggMuxer.open(
    MuxerConfig(
      container: Container.ogg,
      output: MuxerOutput.bytes(),
      tracks: const <TrackInfo>[
        AudioTrackInfo(
          codec: AudioCodec.opus,
          sampleRate: _kRate,
          channels: _kChannels,
        ),
      ],
    ),
  );
  await muxer.writeHeader();
  for (final packet in packets) {
    await muxer.writePacket(packet);
  }
  await muxer.finish();
  return Uint8List.fromList(muxer.getBytes()!);
}

void _blockMainThread(int ms) {
  final clock = Stopwatch()..start();
  var sink = 0.0;
  while (clock.elapsedMilliseconds < ms) {
    for (var i = 0; i < 5000; i++) {
      sink += i * 1.000001;
    }
  }
  if (sink < 0) throw StateError('unreachable');
}

/// Waits for the position to reach [us], or gives up.
Future<bool> _waitForPosition(WorkerAudioTrack track, int us) async {
  for (var i = 0; i < 300; i++) {
    if ((track.positionUs ?? -1) >= us) return true;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return false;
}

void main() {
  late Uint8List ogg;

  setUpAll(() async {
    expect(
      _sharedArrayBufferCtor,
      isNotNull,
      reason: 'no shared memory: this suite cannot test what it claims to',
    );
    ogg = await _oggOpus();
  });

  Future<WorkerAudioTrack> start({
    Duration depth = const Duration(milliseconds: 400),
  }) async {
    final track = await WorkerAudioTrack.start(
      bytes: ogg,
      sampleRate: _kRate,
      channels: _kChannels,
      depth: depth,
      workletUrl: './miniav_audio_ring_worklet.js',
    );
    expect(track, isNotNull, reason: 'a shared-memory page must support this');
    return track!;
  }

  test('position tracks what the device has played, not what was written',
      () async {
    final track = await start();
    addTearDown(track.close);

    expect(track.positionUs, anyOf(isNull, 0), reason: 'nothing played yet');
    expect(await _waitForPosition(track, 50000), isTrue);

    final first = track.positionUs!;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final second = track.positionUs!;

    expect(second, greaterThan(first));
    // It is a real clock, so it advances at roughly real time — not at the
    // rate the worker can decode, which is far faster.
    final advanced = second - first;
    expect(
      advanced,
      inInclusiveRange(80000, 400000),
      reason: 'advanced ${advanced}us over ~200ms of wall time',
    );
  });

  test('position keeps advancing through a blocked main thread', () async {
    final track = await start();
    addTearDown(track.close);
    expect(await _waitForPosition(track, 50000), isTrue);

    final before = track.positionUs!;
    _blockMainThread(200);
    final after = track.positionUs!;

    expect(
      after - before,
      greaterThan(50000),
      reason:
          'the clock comes from the audio device, which does not stop because '
          'the main thread is busy — advanced ${after - before}us',
    );
    expect(track.underruns, 0, reason: 'and nothing went silent');
  });

  test('seek moves the clock to the target', () async {
    final track = await start();
    addTearDown(track.close);
    expect(await _waitForPosition(track, 50000), isTrue);

    const target = 3000000; // 3 s into a 5 s file
    await track.seek(target);

    final after = track.positionUs!;
    expect(
      after,
      inInclusiveRange(target, target + 500000),
      reason: 'position must restart from the seek target, got ${after}us',
    );

    // And it keeps running from there rather than freezing.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(track.positionUs!, greaterThan(after));
  });

  test('seek works while paused, and stays paused', () async {
    final track = await start();
    addTearDown(track.close);
    expect(await _waitForPosition(track, 50000), isTrue);

    await track.pause();
    await track.seek(2000000);
    // The producer sits on a full ring while paused; a seek must still get
    // through, which is why the fill wait is interruptible.
    final atSeek = track.positionUs!;
    expect(atSeek, inInclusiveRange(2000000, 2500000));

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(
      track.positionUs!,
      atSeek,
      reason: 'a paused track must not advance after a seek',
    );

    await track.resume();
    expect(await _waitForPosition(track, atSeek + 50000), isTrue);
  });

  test('pause stops the clock, resume restarts it', () async {
    final track = await start();
    addTearDown(track.close);
    expect(await _waitForPosition(track, 50000), isTrue);

    await track.pause();
    // Let anything already committed to the device drain out.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final paused = track.positionUs!;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(
      track.positionUs!,
      paused,
      reason: 'a suspended audio thread consumes nothing, so time stops',
    );

    await track.resume();
    expect(await _waitForPosition(track, paused + 50000), isTrue);
  });

  test('volume is a graph control, not a change to queued audio', () async {
    final track = await start();
    addTearDown(track.close);
    expect(track.volume, closeTo(1.0, 0.001));
    track.volume = 0.3;
    expect(track.volume, closeTo(0.3, 0.001));
    expect(await _waitForPosition(track, 50000), isTrue);
  });

  test('declines a container it cannot play, so the caller can fall back',
      () async {
    expect(
      await WorkerAudioTrack.start(
        bytes: Uint8List.fromList(List<int>.filled(4096, 0x5A)),
        sampleRate: _kRate,
        channels: _kChannels,
        depth: const Duration(milliseconds: 200),
        workletUrl: './miniav_audio_ring_worklet.js',
      ),
      isNull,
    );
  });

  test('reports the end only once the device has played everything', () async {
    // A short file, so end-of-stream arrives inside the test.
    final track = await start(depth: const Duration(milliseconds: 200));
    addTearDown(track.close);

    await track.seek(4500000); // near the end of the 5 s fixture
    var ended = false;
    for (var i = 0; i < 300; i++) {
      if (await track.isEnded()) {
        ended = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(ended, isTrue, reason: 'the tail must eventually report ended');
  });

  test('close is idempotent', () async {
    final track = await start();
    await track.close();
    await track.close();
    expect(track.positionUs, isNull);
  });
}
