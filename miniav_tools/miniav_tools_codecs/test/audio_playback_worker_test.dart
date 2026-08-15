/// The complete off-main-thread audio path.
///
/// A worker demuxes a real Ogg/Opus stream, decodes it with WebCodecs, and
/// writes PCM straight into shared memory; an `AudioWorklet` reads that memory
/// on the browser's realtime audio thread. Between those two the main thread
/// does nothing at all — which is the claim, and which is why the central test
/// here blocks the main thread solid and expects audio to carry on regardless.
///
/// Everything is built in the browser rather than fetched, so the fixture is a
/// genuine Opus bitstream in a genuine container and nothing is stubbed.
@TestOn('browser')
@Tags(<String>['browser'])
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:miniav_tools_codecs/src/framing/ogg_container.dart'
    show OggMuxer;
import 'package:miniav_tools_codecs/src/web/audio_ring_sink.dart';
import 'package:miniav_tools_codecs/src/web/web_codecs_audio_encoder.dart';
import 'package:miniav_tools_codecs/workers/audio_playback_worker.dart'
    show audioPlaybackWorker;
import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';
import 'package:spawn/spawn.dart';
import 'package:test/test.dart';

@JS('SharedArrayBuffer')
external JSFunction? get _sharedArrayBufferCtor;

const int _kRate = 48000;
const int _kChannels = 2;
const int _kPacketFrames = 960; // 20 ms
const int _kPackets = 100; // 2 s of audio

const String _workletUrl = './miniav_audio_ring_worklet.js';

final _workerEntry = SpawnEntry.split(
  audioPlaybackWorker,
  asset: './workers/build/audio_playback_worker.dart.js',
);

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
      // A gentle 440 Hz tone. Real audio, so a headed run is listenable.
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

/// Burns the main thread SYNCHRONOUSLY — no awaits, no callbacks, nothing on
/// this thread can run. The hitch the whole design exists to survive.
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

Future<Map<String, Object?>> _stats(Worker worker) async =>
    (await worker.request<Object?>('stats'))! as Map<String, Object?>;

/// Waits until the ring holds [frames] frames, or gives up.
Future<bool> _waitForAudio(AudioRingSink sink, int frames) async {
  for (var i = 0; i < 200; i++) {
    if (sink.ring.availableFrames >= frames) return true;
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
      reason:
          'no SharedArrayBuffer, so the worker and the audio thread cannot '
          'share a ring and none of this suite tests what it claims to',
    );
    ogg = await _oggOpus();
    expect(ogg.length, greaterThan(1000), reason: 'the fixture must encode');
  });

  Future<(AudioRingSink, Worker)> start({
    Duration depth = const Duration(milliseconds: 500),
  }) async {
    final sink = await AudioRingSink.open(
      sampleRate: _kRate,
      channels: _kChannels,
      depth: depth,
      workletUrl: _workletUrl,
    );
    expect(sink, isNotNull, reason: 'the sink must open on a shared-memory page');
    await sink!.resume();

    final worker = await spawn(
      _workerEntry,
      message: <String, Object?>{
        // SHARED, not transferred. spawn skips the transfer list for shared
        // memory precisely so this works.
        'ring': PlatformValue(sink.ring.shareable),
        'bytes': ogg,
      },
      timeout: const Duration(seconds: 10),
    );
    return (sink, worker);
  }

  test('a worker fills the ring with real decoded audio', () async {
    final (sink, worker) = await start();
    addTearDown(() async {
      await worker.close(force: true);
      await sink.close();
    });

    expect(
      await _waitForAudio(sink, _kRate ~/ 10),
      isTrue,
      reason: 'the worker must demux, decode and fill without any help',
    );

    final stats = await _stats(worker);
    expect(stats['error'], isNull, reason: 'the worker pump must not have died');
    expect(
      stats['framesWritten'] as int,
      greaterThan(_kRate ~/ 10),
      reason: 'the worker must have written real frames',
    );
  });

  // The claim, end to end: nothing on the main thread is involved in playback,
  // so blocking it solid changes nothing about what is heard.
  test('audio survives a blocked main thread, end to end', () async {
    final (sink, worker) = await start();
    addTearDown(() async {
      await worker.close(force: true);
      await sink.close();
    });

    // Let the worker get ahead and the audio thread start pulling.
    expect(await _waitForAudio(sink, _kRate ~/ 4), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // The MONOTONIC cursors, not the fill level. Fill level cannot answer
    // "did anything happen": a producer keeping perfect pace holds it steady,
    // and so does a pipeline that has stopped dead. These only move when work
    // is done.
    final consumedBefore = sink.ring.framesConsumed;
    final producedBefore = sink.ring.framesProduced;
    final underrunsBefore = sink.ring.underruns;
    final bufferedBefore = sink.ring.availableFrames;

    // 250 ms in which this thread cannot run a single callback.
    _blockMainThread(250);

    final consumed = sink.ring.framesConsumed - consumedBefore;
    final produced = sink.ring.framesProduced - producedBefore;

    expect(
      consumed,
      greaterThan(_kRate ~/ 20),
      reason:
          'the audio thread must have consumed at least 50 ms of audio while '
          'the main thread was blocked solid — consumed $consumed frames',
    );
    expect(
      produced,
      greaterThan(_kRate ~/ 20),
      reason:
          'and the WORKER must have kept decoding through the same stall — '
          'produced $produced frames',
    );
    expect(
      sink.ring.underruns,
      underrunsBefore,
      reason: 'nothing should have gone silent: no new underruns',
    );
    // The two threads kept pace with each other while the main thread was
    // dead: the fill level barely moved, which is what "unaffected" looks like.
    expect(
      (sink.ring.availableFrames - bufferedBefore).abs(),
      lessThan(_kRate ~/ 4),
      reason: 'producer and consumer should have stayed roughly in step',
    );

    // The worker kept working through the stall too, not just the audio thread.
    final after = await _stats(worker);
    expect(after['error'], isNull);
  });

  test('reports a container it cannot play instead of hanging', () async {
    final sink = await AudioRingSink.open(
      sampleRate: _kRate,
      channels: _kChannels,
      workletUrl: _workletUrl,
    );
    addTearDown(sink!.close);

    final worker = await spawn(
      _workerEntry,
      message: <String, Object?>{
        'ring': PlatformValue(sink.ring.shareable),
        'bytes': Uint8List.fromList(List<int>.filled(4096, 0x5A)),
      },
      timeout: const Duration(seconds: 10),
    );
    addTearDown(() => worker.close(force: true));

    // Give the pump a moment to fail.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final stats = await _stats(worker);
    expect(
      stats['error'],
      isNotNull,
      reason: 'an unplayable container must be reported, not silently ignored',
    );
    expect(sink.ring.availableFrames, 0);
  });

  test('stop halts the pump', () async {
    final (sink, worker) = await start();
    addTearDown(() async {
      await worker.close(force: true);
      await sink.close();
    });

    expect(await _waitForAudio(sink, _kRate ~/ 20), isTrue);
    await worker.request<Object?>('stop');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final a = (await _stats(worker))['framesWritten'] as int;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final b = (await _stats(worker))['framesWritten'] as int;
    expect(b, a, reason: 'a stopped pump must write nothing further');
  });
}
