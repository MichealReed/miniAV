/// Web build: there is no filesystem, so a `FileMuxerOutput` cannot be honoured.
///
/// Returns false rather than throwing so the caller can report the situation
/// once, in its own words, instead of every muxer growing a platform check.
library;

Future<bool> writeMuxerFileParts(String path, List<List<int>> parts) async =>
    false;
