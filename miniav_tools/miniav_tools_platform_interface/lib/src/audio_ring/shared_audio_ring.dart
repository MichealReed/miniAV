/// A lock-free SPSC ring of interleaved f32 PCM, in memory two threads share.
///
/// This is the piece that takes the main thread out of the audio path. The
/// browser's audio callback runs on a real realtime thread (an `AudioWorklet`);
/// if the thread that FILLS its buffer is the same thread that builds Flutter
/// frames, then every long frame is a chance for the buffer to run dry, and a
/// dry audio buffer is not a dropped frame you might not notice — it is a click.
/// Put the samples in a `SharedArrayBuffer` and the producer can be a Worker,
/// so the main thread being busy stops mattering at all.
///
/// ## Single producer, single consumer — and no exceptions
///
/// Exactly one thread may write and exactly one may read. That is what lets
/// both run without a lock: each cursor has one writer, so neither side can
/// lose an update. TWO producers would silently interleave and corrupt the
/// audio, so the producer must be handed over deliberately, never shared.
///
/// ## Layout
///
/// One buffer, control block first so the sample data stays 4-byte aligned:
///
/// ```text
///   int32[0]  write   frames ever written   (producer writes, consumer reads)
///   int32[1]  read    frames ever consumed  (consumer writes, producer reads)
///   int32[2]  capacityFrames
///   int32[3]  channels
///   int32[4]  sampleRate
///   int32[5]  underruns  consumer-side count of frames it wanted and
///                        could not have — the number that says the producer
///                        is not keeping up
///   int32[6..15]         reserved, zero
///   float32[...]         capacityFrames * channels interleaved samples
/// ```
///
/// The cursors are MONOTONIC frame counts, not positions: `write - read` is the
/// fill level with no ambiguity between full and empty (a bare position pair
/// cannot tell those apart without wasting a slot). They are int32 and do wrap
/// — after ~12 hours at 48 kHz — which is why every comparison goes through
/// [_signed32]: two's-complement difference stays correct across the wrap as
/// long as the ring holds less than 2^31 frames, and it holds a fraction of a
/// second.
library;

import 'dart:typed_data';

import 'ring_sync_stub.dart'
    if (dart.library.js_interop) 'ring_sync_web.dart'
    as sync;

/// Control-block slot indices.
const int _kWrite = 0;
const int _kRead = 1;
const int _kCapacity = 2;
const int _kChannels = 3;
const int _kSampleRate = 4;
const int _kUnderruns = 5;

/// Control-block size, in int32 slots. Sixteen rather than six so the sample
/// data starts well clear of the cursors: a producer and a consumer hammering
/// two adjacent int32s on different cores share a cache line and slow each
/// other down for no reason (false sharing).
const int kControlSlots = 16;

/// Byte offset of the sample data.
const int kDataOffsetBytes = kControlSlots * 4;

/// A ring of interleaved f32 PCM in shared memory.
///
/// Create one with [allocate] on the thread that owns the sink, hand
/// [shareable] to the producer, and rebuild it there with [attach].
class SharedAudioRing {
  SharedAudioRing._(this._buffer, this._control, this._samples);

  final ByteBuffer _buffer;
  final Int32List _control;
  final Float32List _samples;

  /// Allocates a ring holding [capacityFrames] frames of [channels]-channel
  /// audio.
  ///
  /// Depth is the whole safety margin: the producer may be stalled for as long
  /// as the ring holds audio and nothing is heard. A few hundred milliseconds
  /// costs a few hundred kilobytes.
  factory SharedAudioRing.allocate({
    required int capacityFrames,
    required int channels,
    required int sampleRate,
  }) {
    if (capacityFrames <= 0) {
      throw ArgumentError.value(capacityFrames, 'capacityFrames', 'must be > 0');
    }
    if (channels <= 0) {
      throw ArgumentError.value(channels, 'channels', 'must be > 0');
    }
    final bytes = kDataOffsetBytes + capacityFrames * channels * 4;
    final ring = SharedAudioRing._attach(sync.allocateRingBuffer(bytes));
    ring._control[_kCapacity] = capacityFrames;
    ring._control[_kChannels] = channels;
    ring._control[_kSampleRate] = sampleRate;
    return ring;
  }

  /// Rebuilds a ring over memory [allocate] produced, on another thread.
  ///
  /// Takes whatever [shareable] handed over — a `SharedArrayBuffer` that
  /// crossed a worker boundary, or the buffer itself off-web. The geometry is
  /// read back out of that memory rather than passed alongside it, so the two
  /// sides cannot be configured differently.
  factory SharedAudioRing.attach(Object shareable) =>
      SharedAudioRing._attach(sync.bufferFromShareable(shareable));

  factory SharedAudioRing._attach(ByteBuffer buffer) {
    if (buffer.lengthInBytes <= kDataOffsetBytes) {
      throw ArgumentError.value(
        buffer.lengthInBytes,
        'buffer',
        'too small to hold a ring',
      );
    }
    final control = Int32List.view(buffer, 0, kControlSlots);
    final samples = Float32List.view(
      buffer,
      kDataOffsetBytes,
      (buffer.lengthInBytes - kDataOffsetBytes) ~/ 4,
    );
    return SharedAudioRing._(buffer, control, samples);
  }

  /// The backing store, to hand to a worker and rebuild there with [attach].
  ///
  /// SHARED, never transferred: a `SharedArrayBuffer` in a transfer list is a
  /// `DataCloneError`, and sharing is the whole point — both threads must end
  /// up pointing at this same memory.
  Object get shareable => sync.shareableBuffer(_buffer);

  /// The backing store as a Dart buffer. For hosts that keep their own views
  /// over it; prefer [shareable] + [attach] to cross a thread.
  ByteBuffer get buffer => _buffer;

  /// Whether the cursors are genuinely atomic.
  bool get hasAtomicCursors => sync.hasAtomics;

  /// Whether this ring is in memory two threads can genuinely share.
  ///
  /// FALSE means it is ordinary memory: it works perfectly within one thread
  /// and delivers nothing across two, because each thread would be looking at
  /// its own copy. A cross-thread consumer MUST check this before trusting the
  /// ring — the failure is otherwise silence, with the cursors sitting still
  /// and nothing to indicate why.
  bool get isSharedAcrossThreads => sync.isSharedBuffer(_buffer);

  int get capacityFrames => _control[_kCapacity];
  int get channels => _control[_kChannels];
  int get sampleRate => _control[_kSampleRate];

  /// Frames the consumer wanted and could not have. Non-zero means the
  /// producer is not keeping up — the number to look at when audio glitches.
  int get underruns => sync.loadCursor(_control, _kUnderruns);

  /// Frames the consumer has taken, ever. Monotonic.
  ///
  /// The honest measure of "is the audio thread actually running": fill level
  /// cannot answer that, because a producer keeping pace holds it steady and a
  /// stopped pair holds it steady too. This only moves when audio is consumed.
  int get framesConsumed => sync.loadCursor(_control, _kRead);

  /// Frames the producer has written, ever. Monotonic.
  int get framesProduced => sync.loadCursor(_control, _kWrite);

  /// Frames written but not yet consumed.
  int get availableFrames => _signed32(
    sync.loadCursor(_control, _kWrite) - sync.loadCursor(_control, _kRead),
  );

  /// Frames the producer may write right now.
  int get freeFrames => capacityFrames - availableFrames;

  /// How much audio the ring is holding — the margin a stalled producer has.
  Duration get buffered => sampleRate <= 0
      ? Duration.zero
      : Duration(microseconds: availableFrames * 1000000 ~/ sampleRate);

  // --- producer ------------------------------------------------------------

  /// Writes up to [frameCount] frames of interleaved f32 from [source],
  /// returning how many were taken.
  ///
  /// A short write means the ring is full, which is normal and is the natural
  /// backpressure: the producer should wait rather than drop, because the
  /// consumer is a clock and will make room on its own schedule.
  ///
  /// PRODUCER THREAD ONLY.
  int write(Float32List source, int frameCount, {int sourceFrameOffset = 0}) {
    final ch = channels;
    final capacity = capacityFrames;
    var frames = frameCount;
    if (frames <= 0) return 0;

    final availableInSource =
        (source.length ~/ ch) - sourceFrameOffset;
    if (availableInSource <= 0) return 0;
    if (frames > availableInSource) frames = availableInSource;

    final write = sync.loadCursor(_control, _kWrite);
    final free = capacity - _signed32(write - sync.loadCursor(_control, _kRead));
    if (free <= 0) return 0;
    if (frames > free) frames = free;

    // Wrapping is two copies, never a per-sample loop: setRange is a memmove.
    final start = _modulo(write, capacity);
    final firstFrames = frames <= capacity - start ? frames : capacity - start;
    _samples.setRange(
      start * ch,
      (start + firstFrames) * ch,
      source,
      sourceFrameOffset * ch,
    );
    if (firstFrames < frames) {
      _samples.setRange(
        0,
        (frames - firstFrames) * ch,
        source,
        (sourceFrameOffset + firstFrames) * ch,
      );
    }
    // Publish LAST. Every sample above is visible to a consumer that sees this.
    sync.storeCursor(_control, _kWrite, _signed32(write + frames));
    return frames;
  }

  // --- consumer ------------------------------------------------------------

  /// Reads up to [frameCount] frames into [destination], returning how many
  /// were taken. The Dart consumer exists for tests and for native hosts; on
  /// web the consumer is the AudioWorklet, which implements this in JS.
  ///
  /// CONSUMER THREAD ONLY.
  int read(Float32List destination, int frameCount) {
    final ch = channels;
    final capacity = capacityFrames;
    var frames = frameCount;
    if (frames <= 0) return 0;
    if (frames > destination.length ~/ ch) frames = destination.length ~/ ch;

    final read = sync.loadCursor(_control, _kRead);
    final filled = _signed32(sync.loadCursor(_control, _kWrite) - read);
    if (filled <= 0) {
      _countUnderrun(frames);
      return 0;
    }
    if (frames > filled) {
      _countUnderrun(frames - filled);
      frames = filled;
    }

    final start = _modulo(read, capacity);
    final firstFrames = frames <= capacity - start ? frames : capacity - start;
    destination.setRange(0, firstFrames * ch, _samples, start * ch);
    if (firstFrames < frames) {
      destination.setRange(
        firstFrames * ch,
        frames * ch,
        _samples,
        0,
      );
    }
    sync.storeCursor(_control, _kRead, _signed32(read + frames));
    return frames;
  }

  void _countUnderrun(int frames) => sync.storeCursor(
    _control,
    _kUnderruns,
    _signed32(sync.loadCursor(_control, _kUnderruns) + frames),
  );

  /// Drops everything unconsumed. PRODUCER THREAD ONLY, and only when the
  /// consumer is stopped — a seek or a flush, never mid-playback.
  void clear() => sync.storeCursor(
    _control,
    _kWrite,
    sync.loadCursor(_control, _kRead),
  );

  @override
  String toString() =>
      'SharedAudioRing(${capacityFrames}f x ${channels}ch @ ${sampleRate}Hz, '
      '$availableFrames buffered, $underruns underruns)';
}

/// Two's-complement 32-bit, so cursor arithmetic stays right across the wrap.
int _signed32(int v) => v.toSigned(32);

/// Positive modulo: a cursor that has wrapped negative still indexes correctly.
int _modulo(int cursor, int capacity) {
  final m = cursor % capacity;
  return m < 0 ? m + capacity : m;
}
