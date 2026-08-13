/// Platform-neutral handle for a container being written straight to disk.
///
/// Declared here rather than in either half of the `dart:io` conditional import
/// so both halves can name the same type: the streaming muxer holds a
/// `MuxerFileSink?` and stays web-safe, and only `file_sink_io.dart` knows what
/// a file is.
library;

/// A sequentially-written output file that can also be patched in place once.
///
/// Streaming ISO-BMFF needs exactly two things beyond "append bytes": the
/// running [length] (chunk offsets in `stco`/`co64` are absolute file offsets,
/// so a sample's offset is the file length at the moment it is written) and one
/// 64-bit patch at the end — the `mdat` largesize, which is only knowable after
/// the last sample has landed.
///
/// RIFF/WAVE needs the same shape one size down: two little-endian 32-bit
/// lengths ([patchU32]) that are only knowable at `finish()`. ADTS needs
/// neither — every byte it writes is final.
abstract class MuxerFileSink {
  /// Bytes written so far; equivalently, the offset the next [add] lands at.
  int get length;

  /// Append [bytes] at the end of the file.
  Future<void> add(List<int> bytes);

  /// Overwrite the 8 bytes at [offset] with [value] big-endian, then resume
  /// appending at the end of the file.
  Future<void> patchU64(int offset, int value);

  /// Overwrite the 4 bytes at [offset] with [value] LITTLE-endian (RIFF's byte
  /// order), then resume appending at the end of the file.
  Future<void> patchU32Le(int offset, int value);

  /// Flush and release the underlying handle. Safe to call more than once.
  Future<void> close();
}
