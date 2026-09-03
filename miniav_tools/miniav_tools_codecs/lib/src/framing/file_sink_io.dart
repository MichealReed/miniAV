/// VM/native build: write the assembled container to disk.
library;

import 'dart:io';
import 'dart:typed_data';

import 'muxer_file_sink.dart';

/// This build can honour a `FileMuxerOutput`.
const bool muxerFileSinkAvailable = true;

/// Writes [parts] in order, streaming through an [IOSink].
///
/// Takes pieces rather than one buffer on purpose: the muxers assemble a
/// container as ftyp / mdat-header / mdat / moov, and joining those just to
/// hand the result to a write is a full extra copy of the whole file. For a
/// multi-minute clip that is hundreds of megabytes allocated for no reason.
Future<bool> writeMuxerFileParts(String path, List<List<int>> parts) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  final sink = f.openWrite();
  var ok = false;
  try {
    for (final p in parts) {
      sink.add(p);
    }
    await sink.flush();
    ok = true;
  } finally {
    if (ok) {
      await sink.close();
    } else {
      // A failed flush almost always makes close() fail the same way, and an
      // exception thrown out of a `finally` REPLACES the one already in flight
      // — the caller would get the second, less informative error and never see
      // what actually went wrong.
      try {
        await sink.close();
      } on Object {
        // ignored on purpose: the original error is the one worth reporting.
      }
    }
  }
  return true;
}

/// Open [path] for streaming container output, creating parent directories.
Future<MuxerFileSink> openMuxerFileSink(String path) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  final raf = await f.open(mode: FileMode.write);
  return _IoMuxerFileSink(raf);
}

class _IoMuxerFileSink implements MuxerFileSink {
  _IoMuxerFileSink(this._raf);

  final RandomAccessFile _raf;
  int _length = 0;
  bool _closed = false;

  @override
  int get length => _length;

  @override
  Future<void> add(List<int> bytes) async {
    if (bytes.isEmpty) return;
    await _raf.writeFrom(bytes);
    _length += bytes.length;
  }

  @override
  Future<void> patchU64(int offset, int value) async {
    final b = Uint8List(8);
    for (var i = 0; i < 8; i++) {
      b[7 - i] = (value >> (8 * i)) & 0xff;
    }
    await _raf.setPosition(offset);
    await _raf.writeFrom(b);
    // Back to the end: everything after a patch is still an append.
    await _raf.setPosition(_length);
  }

  @override
  Future<void> patchU32Le(int offset, int value) async {
    final b = Uint8List(4);
    for (var i = 0; i < 4; i++) {
      b[i] = (value >> (8 * i)) & 0xff;
    }
    await _raf.setPosition(offset);
    await _raf.writeFrom(b);
    await _raf.setPosition(_length);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _raf.flush();
    await _raf.close();
  }
}
