/// Web build: there is no filesystem, so a `FileMuxerOutput` cannot be honoured.
///
/// [writeMuxerFileParts] returns false rather than throwing so the caller can
/// report the situation once, in its own words, instead of every muxer growing
/// a platform check. [muxerFileSinkAvailable] lets the caller find that out
/// *before* a recording has been buffered rather than at `finish()`.
library;

import 'muxer_file_sink.dart';

/// This build cannot honour a `FileMuxerOutput`.
const bool muxerFileSinkAvailable = false;

Future<bool> writeMuxerFileParts(String path, List<List<int>> parts) async =>
    false;

Future<MuxerFileSink> openMuxerFileSink(String path) async =>
    throw UnsupportedError(
        'no filesystem on this platform — cannot stream a container to $path');
