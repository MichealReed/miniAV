/// Print an MP4's track list and per-track packet counts/sizes.
///
/// Written while diagnosing a clip that "saved" but played back with no
/// picture. The distinction that mattered was between a video track that was
/// present and corrupt and one that was never written at all, and file size
/// alone cannot tell you which -- an audio-only MP4 is perfectly valid.
///
///   dart run benchmark/mp4_inspect.dart <file.mp4>
library;

import 'dart:io';
import 'dart:typed_data';
import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';

void main(List<String> a) async {
  final bytes = File(a.first).readAsBytesSync();
  final d = Mp4Demuxer.open(bytes);
  print('file ${bytes.length} bytes, ${d.tracks.length} tracks');
  for (var i = 0; i < d.tracks.length; i++) {
    final t = d.tracks[i];
    if (t is VideoTrackInfo) {
      print('  [$i] VIDEO ${t.codec} ${t.width}x${t.height} '
          'extraData=${t.extraData?.bytes.length ?? 0}B '
          'first=${t.extraData?.bytes.take(6).toList()}');
    } else if (t is AudioTrackInfo) {
      print('  [$i] AUDIO ${t.codec} ${t.sampleRate}Hz ch=${t.channels}');
    }
  }
  final counts = <int, int>{}, sizes = <int, int>{};
  while (true) {
    final p = await d.readPacket();
    if (p == null) break;
    counts[p.trackIndex] = (counts[p.trackIndex] ?? 0) + 1;
    sizes[p.trackIndex] = (sizes[p.trackIndex] ?? 0) + p.data.length;
  }
  for (final k in counts.keys.toList()..sort()) {
    print('  track $k: ${counts[k]} packets, ${sizes[k]} bytes total, '
        'avg ${(sizes[k]! / counts[k]!).toStringAsFixed(0)} B');
  }
  await d.close();
}
