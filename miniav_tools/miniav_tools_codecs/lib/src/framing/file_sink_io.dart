/// VM/native build: write the assembled container to disk.
library;

import 'dart:io';

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
  try {
    for (final p in parts) {
      sink.add(p);
    }
    await sink.flush();
  } finally {
    await sink.close();
  }
  return true;
}
