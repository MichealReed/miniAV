import 'dart:io';
import 'dart:typed_data';
import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';

/// Peak memory of assembling an MP4, relative to the media it contains.
///
/// Matters because the first-party writer is a WHOLE-FILE builder: it holds
/// every packet until finish(). That is fine for a bounded clip and wrong for
/// an open-ended recording, so the multiplier is the number that decides where
/// it can be used. Each packet gets its own allocation here -- reusing one
/// buffer makes the input look resident when it is not, and flatters the
/// result by more than 2x.
///
///   dart run benchmark/mp4_muxer_memory.dart [parts|concat]
///
/// `parts` streams the container as ordered pieces (current behaviour);
/// `concat` goes through getBytes(), which is what a sink that wants one buffer
/// costs. Measured at 300 MB of payload: 1.86x vs 4.85x.
void main(List<String> a) async {
  final mode = a.isEmpty ? 'parts' : a.first;
  const n = 1500, sz = 200 * 1024; // ~300 MB, each packet its OWN buffer
  final tmp = Directory.systemTemp.createTempSync('memprobe');
  final path = '${tmp.path}/big.m4a';

  final m = Mp4Muxer.open(MuxerConfig(
    container: Container.m4a,
    output: MuxerOutput.bytes(),
    tracks: const [
      AudioTrackInfo(codec: AudioCodec.aac, sampleRate: 48000, channels: 2),
    ],
  ));
  await m.writeHeader();
  for (var i = 0; i < n; i++) {
    await m.writePacket(EncodedPacket(
      trackIndex: 0,
      data: Uint8List(sz)..fillRange(0, sz, i & 0xFF), // distinct allocation
      ptsUs: i * 21333, dtsUs: i * 21333,
      durationUs: 21333, isKeyframe: true));
  }
  final held = ProcessInfo.currentRss;
  await m.finish();

  final sink = File(path).openWrite();
  if (mode == 'concat') {
    sink.add(m.getBytes()!);           // old: one concatenated blob
  } else {
    for (final p in m.outputParts!) {
      sink.add(p);                     // new: ordered pieces
    }
  }
  await sink.flush();
  await sink.close();
  final peak = ProcessInfo.maxRss;
  await m.close();

  const payload = n * sz;
  print('mode=$mode  payload=${(payload / 1e6).toStringAsFixed(0)} MB  '
      'file=${(File(path).lengthSync() / 1e6).toStringAsFixed(0)} MB');
  print('  rss holding packets = ${(held / 1e6).toStringAsFixed(0)} MB');
  print('  PEAK rss            = ${(peak / 1e6).toStringAsFixed(0)} MB  '
      '(${(peak / payload).toStringAsFixed(2)}x payload)');
  tmp.deleteSync(recursive: true);
}
