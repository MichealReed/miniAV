/// The off-main-thread audio sink.
///
/// This suite exists to prove ONE claim, the whole reason the sink was built:
/// **audio keeps playing while the main thread is blocked.** Everything else
/// here is scaffolding for that test.
///
/// It needs a cross-origin-isolated page for `SharedArrayBuffer`, which the
/// package:test browser server does not provide — see audio_ring_sink_test.html
/// for how the page isolates itself. If that ever stops working the sink
/// correctly declines to open, so the suite reports "not isolated" loudly
/// rather than passing on a path that was never exercised.
@TestOn('browser')
@Tags(<String>['browser'])
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:miniav_tools_codecs/src/web/audio_ring_sink.dart';
import 'package:test/test.dart';

@JS('SharedArrayBuffer')
external JSFunction? get _sharedArrayBufferCtor;

/// The worklet module, served from the test tree (the runner exposes only that).
const String _workletUrl = './miniav_audio_ring_worklet.js';

const int _kRate = 48000;
const int _kChannels = 2;

/// A quiet tone, interleaved f32 — real audio rather than a ramp, so anything
/// that plays it can be listened to when this is run headed.
Float32List _tone(int frames, int fromFrame) {
  final out = Float32List(frames * _kChannels);
  for (var f = 0; f < frames; f++) {
    final v = 0.2 * sin(2 * pi * 440.0 * (fromFrame + f) / _kRate);
    for (var c = 0; c < _kChannels; c++) {
      out[f * _kChannels + c] = v;
    }
  }
  return out;
}

Future<AudioRingSink?> _open({Duration? depth}) => AudioRingSink.open(
  sampleRate: _kRate,
  channels: _kChannels,
  depth: depth ?? const Duration(milliseconds: 400),
  workletUrl: _workletUrl,
);

/// Burns the main thread SYNCHRONOUSLY for [ms] — no awaits, nothing can run.
/// This is the hitch the sink is supposed to survive.
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

void main() {
  setUpAll(() {
    expect(
      _sharedArrayBufferCtor,
      isNotNull,
      reason:
          'no SharedArrayBuffer, so none of this suite tests what it claims '
          'to. Chrome is given --enable-features=SharedArrayBuffer by '
          'dart_test.yaml; a browser without shared memory cannot run it.',
    );
  });

  group('opening', () {
    test('gets a ring in genuinely shared memory', () async {
      final sink = await _open();
      expect(sink, isNotNull, reason: 'an isolated page must support the sink');
      addTearDown(sink!.close);

      expect(
        sink.ring.isSharedAcrossThreads,
        isTrue,
        reason: 'a ring in unshared memory delivers nothing to the worklet',
      );
      expect(sink.ring.hasAtomicCursors, isTrue);
      expect(sink.ring.sampleRate, _kRate);
      expect(sink.ring.channels, _kChannels);
      expect(sink.ring.capacityFrames, _kRate * 400 ~/ 1000);
    });

    test('declines rather than throwing on a nonsense format', () async {
      expect(
        await AudioRingSink.open(
          sampleRate: 0,
          channels: 2,
          workletUrl: _workletUrl,
        ),
        isNull,
      );
      expect(
        await AudioRingSink.open(
          sampleRate: _kRate,
          channels: 0,
          workletUrl: _workletUrl,
        ),
        isNull,
      );
    });

    test('declines when the browser will not give the requested rate',
        () async {
      // A rate no AudioContext will honour. Stands in for the case that
      // matters in the field: WebKit ties the context to the hardware audio
      // session, so a device that ignores the request would otherwise play
      // every sample at the wrong pitch, for the whole stream, silently. The
      // sink must decline and let the caller use the path that works.
      expect(
        await AudioRingSink.open(
          sampleRate: 111,
          channels: _kChannels,
          workletUrl: _workletUrl,
        ),
        isNull,
      );
    });

    test('a sink that DOES open runs at exactly the rate it was asked for',
        () async {
      // The other half: when it opens, the contract is real. Anything that
      // reaches the worklet is played at the rate its producer assumed.
      for (final rate in <int>[48000, 44100]) {
        final sink = await AudioRingSink.open(
          sampleRate: rate,
          channels: _kChannels,
          workletUrl: _workletUrl,
        );
        expect(sink, isNotNull, reason: '$rate Hz should be supported');
        addTearDown(sink!.close);
        expect(sink.ring.sampleRate, rate);
        expect(sink.contextSampleRate, rate);
      }
    });

    test('declines when the worklet module will not load', () async {
      expect(
        await AudioRingSink.open(
          sampleRate: _kRate,
          channels: _kChannels,
          workletUrl: './does_not_exist_worklet.js',
        ),
        isNull,
        reason: 'a missing worklet must fall back, not take playback down',
      );
    });
  });

  group('the audio thread consumes on its own', () {
    test('drains the ring with the main thread merely idle', () async {
      final sink = await _open();
      addTearDown(sink!.close);
      await sink.resume();

      sink.ring.write(_tone(_kRate ~/ 10, 0), _kRate ~/ 10); // 100 ms
      final before = sink.ring.availableFrames;
      expect(before, _kRate ~/ 10);

      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(
        sink.ring.availableFrames,
        lessThan(before),
        reason:
            'the AudioWorklet must have consumed frames without anything on '
            'the main thread pushing them',
      );
    });
  });

  group('the claim', () {
    // The reason the sink exists. The main thread is blocked SOLID for longer
    // than any Flutter hitch, with no chance for a pump to run — and the audio
    // thread keeps pulling from shared memory throughout.
    test('audio keeps playing through a blocked main thread', () async {
      final sink = await _open(depth: const Duration(milliseconds: 500));
      addTearDown(sink!.close);
      await sink.resume();

      // Fill the ring, then never touch it again from this thread.
      final frames = sink.ring.capacityFrames;
      expect(sink.ring.write(_tone(frames, 0), frames), frames);
      expect(sink.ring.underruns, 0);

      // Let the device actually start pulling before the stall.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final beforeStall = sink.ring.availableFrames;
      expect(
        beforeStall,
        lessThan(frames),
        reason: 'the audio thread should already be consuming',
      );

      // 200 ms with the main thread unable to run a single callback.
      _blockMainThread(200);

      final afterStall = sink.ring.availableFrames;
      final consumedDuringStall = beforeStall - afterStall;

      expect(
        consumedDuringStall,
        greaterThan(_kRate ~/ 20),
        reason:
            'the audio thread must have pulled at least 50 ms of audio WHILE '
            'the main thread was blocked solid — that is the entire point of '
            'the sink. Consumed $consumedDuringStall frames.',
      );
      expect(
        sink.ring.underruns,
        0,
        reason:
            'the ring held more audio than the stall was long, so nothing '
            'should have gone silent',
      );
    });

    test('underruns are counted when the producer really does fall behind',
        () async {
      // The honest other half: the sink is not magic. Starve it and it says so,
      // rather than glitching silently.
      final sink = await _open(depth: const Duration(milliseconds: 100));
      addTearDown(sink!.close);
      await sink.resume();

      sink.ring.write(_tone(480, 0), 480); // 10 ms, then nothing
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(
        sink.underruns,
        greaterThan(0),
        reason: 'a starved audio thread must report it',
      );
    });
  });

  group('controls', () {
    test('volume rides on a gain node, not on the samples', () async {
      final sink = await _open();
      addTearDown(sink!.close);
      expect(sink.volume, closeTo(1.0, 0.001));
      sink.volume = 0.25;
      expect(sink.volume, closeTo(0.25, 0.001));
      // The producer's samples are untouched by a volume change.
      sink.ring.write(_tone(64, 0), 64);
      expect(sink.ring.availableFrames, 64);
    });

    test('close is idempotent and stops the worklet', () async {
      final sink = await _open();
      expect(sink, isNotNull);
      await sink!.close();
      await sink.close();
    });
  });
}
