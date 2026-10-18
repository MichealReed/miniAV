/// Consumer side of the capture mirror ring written by
/// `MiniAV_Audio_SetCaptureMirror` (see `audio_context.c` for the producer and
/// the header layout).
///
/// PURE ON PURPOSE. The web wrapper owns the SharedArrayBuffer views and the
/// atomic cursor load; everything that can be got WRONG — wrap-safe occupancy,
/// the split copy across the ring seam, overrun accounting — lives here where
/// a VM test can execute it. The bug this whole path exists to fix was found
/// only after two speculative fixes to code nobody could run.
library;

import 'dart:typed_data';

/// u32 header slots, mirroring `MINIAV_MIRROR_HEADER_U32` in the C producer.
class MirrorHeader {
  static const int writeCursor = 0;
  static const int readCursor = 1;
  static const int capacityFrames = 2;
  static const int channels = 3;
  static const int overrunFrames = 4;
  static const int sampleRate = 5;
  static const int slots = 8;
}

/// What one drain produced.
class MirrorDrain {
  const MirrorDrain(this.frames, this.overrunFrames);

  /// Interleaved f32 frames copied out. Empty when the ring had nothing.
  final Float32List frames;

  /// Frames the PRODUCER dropped since the last drain because we fell behind.
  /// 🔴 Non-zero is microphone input that no longer exists — not latency.
  final int overrunFrames;

  bool get isEmpty => frames.isEmpty;
}

/// Reads the mirror. One instance per capture; SINGLE CONSUMER by contract —
/// the producer's cursor protocol is SPSC and two readers would both advance
/// the read cursor, each stealing frames the other already claimed.
class CaptureMirrorReader {
  CaptureMirrorReader({
    required this.header,
    required this.samples,
    required this.capacityFrames,
    required this.channels,
  });

  final Uint32List header;
  final Float32List samples;
  final int capacityFrames;
  final int channels;

  int _lastOverrun = 0;

  /// Frames currently readable, given a write cursor read atomically by the
  /// caller. Unsigned wrap-safe: both cursors are monotonic frame counts, so
  /// their difference stays correct across a 2^32 wrap and there is no
  /// ambiguous full-vs-empty state to disambiguate with a loop flag.
  int available(int writeCursor) {
    final r = header[MirrorHeader.readCursor];
    final used = (writeCursor - r) & 0xFFFFFFFF;
    // A producer that lapped us cannot hand back more than the ring holds.
    return used > capacityFrames ? capacityFrames : used;
  }

  /// Copy out everything readable and advance the read cursor.
  ///
  /// [writeCursor] MUST come from an atomic (acquire) load by the caller — the
  /// samples it advertises are only guaranteed visible through that load.
  MirrorDrain drain(int writeCursor, {int? maxFrames}) {
    var n = available(writeCursor);
    if (maxFrames != null && maxFrames >= 0 && n > maxFrames) n = maxFrames;

    final totalOverrun = header[MirrorHeader.overrunFrames];
    final newOverrun = (totalOverrun - _lastOverrun) & 0xFFFFFFFF;
    _lastOverrun = totalOverrun;

    if (n == 0) return MirrorDrain(Float32List(0), newOverrun);

    final r = header[MirrorHeader.readCursor];
    final off = r % capacityFrames;
    final first = (off + n > capacityFrames) ? capacityFrames - off : n;

    final out = Float32List(n * channels);
    out.setRange(0, first * channels, samples, off * channels);
    if (first < n) {
      out.setRange(first * channels, n * channels, samples, 0);
    }

    header[MirrorHeader.readCursor] = (r + n) & 0xFFFFFFFF;
    return MirrorDrain(out, newOverrun);
  }
}
