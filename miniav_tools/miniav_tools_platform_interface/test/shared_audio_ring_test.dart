/// The shared PCM ring.
///
/// Deliberately NOT `@TestOn('vm')`: the logic must be identical on both
/// platforms, and on web it runs over real shared memory with real `Atomics`.
/// A ring that passes on the VM and drifts in a browser would be silent in
/// tests and audible in the product.
library;

import 'dart:typed_data';

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';
import 'package:test/test.dart';

SharedAudioRing _ring({int frames = 8, int channels = 2}) =>
    SharedAudioRing.allocate(
      capacityFrames: frames,
      channels: channels,
      sampleRate: 48000,
    );

/// Interleaved ramp: frame f, channel c → f * 10 + c. Makes an off-by-one in
/// the wrap show up as a wrong VALUE, not just a wrong count.
Float32List _ramp(int frames, int channels, {int from = 0}) {
  final out = Float32List(frames * channels);
  for (var f = 0; f < frames; f++) {
    for (var c = 0; c < channels; c++) {
      out[f * channels + c] = ((from + f) * 10 + c).toDouble();
    }
  }
  return out;
}

void main() {
  group('geometry', () {
    test('carries its own shape so the two sides cannot disagree', () {
      final ring = _ring(frames: 128, channels: 2);
      expect(ring.capacityFrames, 128);
      expect(ring.channels, 2);
      expect(ring.sampleRate, 48000);
      expect(ring.availableFrames, 0);
      expect(ring.freeFrames, 128);
    });

    test('rejects a nonsense shape instead of allocating it', () {
      expect(
        () => SharedAudioRing.allocate(
          capacityFrames: 0,
          channels: 2,
          sampleRate: 48000,
        ),
        throwsArgumentError,
      );
      expect(
        () => SharedAudioRing.allocate(
          capacityFrames: 8,
          channels: 0,
          sampleRate: 48000,
        ),
        throwsArgumentError,
      );
    });

    test('buffered reports the margin a stalled producer has', () {
      final ring = SharedAudioRing.allocate(
        capacityFrames: 4800,
        channels: 2,
        sampleRate: 48000,
      );
      ring.write(_ramp(2400, 2), 2400);
      expect(ring.buffered, const Duration(milliseconds: 50));
    });
  });

  group('write / read', () {
    test('round-trips samples in order', () {
      final ring = _ring(frames: 8);
      expect(ring.write(_ramp(4, 2), 4), 4);
      expect(ring.availableFrames, 4);

      final out = Float32List(4 * 2);
      expect(ring.read(out, 4), 4);
      expect(out, _ramp(4, 2));
      expect(ring.availableFrames, 0);
    });

    test('a full ring takes what fits and no more', () {
      final ring = _ring(frames: 8);
      expect(ring.write(_ramp(8, 2), 8), 8);
      expect(ring.freeFrames, 0);
      // Short write, not an exception: the producer waits for the consumer.
      expect(ring.write(_ramp(4, 2), 4), 0);
    });

    test('an empty ring reads nothing rather than stale samples', () {
      final ring = _ring(frames: 8);
      final out = Float32List(4 * 2);
      expect(ring.read(out, 4), 0);
      expect(out.every((s) => s == 0), isTrue);
    });

    test('a partial read leaves the rest', () {
      final ring = _ring(frames: 8);
      ring.write(_ramp(6, 2), 6);
      final out = Float32List(8 * 2);
      expect(ring.read(out, 8), 6, reason: 'only six were written');
      expect(out.sublist(0, 12), _ramp(6, 2));
    });
  });

  group('wrapping', () {
    test('a write that straddles the end lands contiguously on read', () {
      final ring = _ring(frames: 8);
      // Put the cursor near the end, then straddle it.
      ring.write(_ramp(6, 2), 6);
      final drain = Float32List(6 * 2);
      ring.read(drain, 6);

      expect(ring.write(_ramp(5, 2, from: 100), 5), 5);
      final out = Float32List(5 * 2);
      expect(ring.read(out, 5), 5);
      expect(
        out,
        _ramp(5, 2, from: 100),
        reason: 'the two halves of a wrapped write must rejoin in order',
      );
    });

    test('survives many laps without drifting', () {
      final ring = _ring(frames: 8, channels: 2);
      final out = Float32List(3 * 2);
      var next = 0;
      for (var lap = 0; lap < 200; lap++) {
        expect(ring.write(_ramp(3, 2, from: next), 3), 3);
        expect(ring.read(out, 3), 3);
        expect(out, _ramp(3, 2, from: next), reason: 'lap $lap');
        next += 3;
      }
    });

    test('a mono ring wraps as correctly as a stereo one', () {
      final ring = _ring(frames: 5, channels: 1);
      ring.write(_ramp(4, 1), 4);
      final drain = Float32List(4);
      ring.read(drain, 4);
      expect(ring.write(_ramp(4, 1, from: 50), 4), 4);
      final out = Float32List(4);
      expect(ring.read(out, 4), 4);
      expect(out, _ramp(4, 1, from: 50));
    });
  });

  group('underruns', () {
    test('count the frames the consumer wanted and could not have', () {
      final ring = _ring(frames: 8);
      final out = Float32List(4 * 2);
      expect(ring.underruns, 0);
      ring.read(out, 4);
      expect(ring.underruns, 4, reason: 'nothing was written');

      ring.write(_ramp(2, 2), 2);
      ring.read(out, 4);
      expect(ring.underruns, 6, reason: 'wanted four, had two');
    });

    test('stay at zero while the producer keeps up', () {
      final ring = _ring(frames: 16);
      final out = Float32List(4 * 2);
      for (var i = 0; i < 50; i++) {
        ring.write(_ramp(4, 2), 4);
        expect(ring.read(out, 4), 4);
      }
      expect(ring.underruns, 0);
    });
  });

  group('attach', () {
    test('a second view of the same memory sees the same audio', () {
      final producer = _ring(frames: 16);
      // What a worker does with the buffer it is handed.
      final consumer = SharedAudioRing.attach(producer.shareable);

      expect(consumer.capacityFrames, producer.capacityFrames);
      expect(consumer.channels, producer.channels);
      expect(consumer.sampleRate, producer.sampleRate);

      producer.write(_ramp(5, 2, from: 7), 5);
      expect(
        consumer.availableFrames,
        5,
        reason: 'the cursor must be visible through the other view',
      );
      final out = Float32List(5 * 2);
      expect(consumer.read(out, 5), 5);
      expect(out, _ramp(5, 2, from: 7));
      expect(
        producer.availableFrames,
        0,
        reason: "the consumer's read must be visible to the producer",
      );
    });

    test('refuses a buffer too small to be a ring', () {
      expect(
        () => SharedAudioRing.attach(Uint8List(8).buffer),
        throwsArgumentError,
      );
    });
  });

  group('clear', () {
    test('drops what is unconsumed without disturbing the consumer', () {
      final ring = _ring(frames: 16);
      ring.write(_ramp(8, 2), 8);
      expect(ring.availableFrames, 8);
      ring.clear();
      expect(ring.availableFrames, 0);
      // And the ring still works afterwards — a seek is a clear then a refill.
      expect(ring.write(_ramp(4, 2, from: 900), 4), 4);
      final out = Float32List(4 * 2);
      expect(ring.read(out, 4), 4);
      expect(out, _ramp(4, 2, from: 900));
    });
  });
}
