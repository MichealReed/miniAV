// Mp4Demuxer.seek must land on a VIDEO keyframe at/before the target.
//
// Two shipped bugs, both invisible to a name-only selection test:
//
//  1. The scan considered EVERY track. Audio has no stss, so Mp4Demuxer marks
//     every audio sample keyframe:true — in an interleaved file the nearest
//     "keyframe" to any target is therefore almost always an audio sample, and
//     the video decoder got fed from the middle of a GOP (grey/blocky until the
//     next IDR).
//  2. The scan `break`ed on the first sample with ptsUs > target while
//     _samples is FILE-OFFSET ordered. B-frame reordering makes pts
//     non-monotonic in that order, so the scan stopped before reaching the real
//     seek point.
//
// bframes.mp4 (libx264 -bf 2) supplies genuine reordered pts; the interleaved
// case is built from it with Mp4Muxer, because no fixture has audio + video +
// several GOPs.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';
import 'package:test/test.dart';

const _asset = 'test/assets/bframes.mp4';

/// Video packets of [dm], in file order.
Future<List<EncodedPacket>> _drain(Mp4Demuxer dm) async {
  final out = <EncodedPacket>[];
  for (var p = await dm.readPacket(); p != null; p = await dm.readPacket()) {
    out.add(p);
  }
  return out;
}

/// bframes.mp4's 10 video packets repeated [gops] times on a 1 s stride, muxed
/// against a 48 kHz AAC track whose every sample is (legitimately) flagged as a
/// keyframe. Each repetition restarts at the fixture's IDR, so the result has
/// [gops] real sync samples and pts that runs backwards inside every one.
///
/// Written to a FILE on purpose: Mp4Muxer streams straight to a file sink in
/// call order, so the mdat comes out genuinely INTERLEAVED (audio and video
/// chunks alternating, as a recorder or ffmpeg produces). The bytes path
/// buffers per track and emits video-then-audio, which is the one layout in
/// which the old seek accidentally behaved.
Future<Uint8List> _interleaved(String path, int gops) async {
  final src = Mp4Demuxer.open(
      Uint8List.fromList(File(_asset).readAsBytesSync()));
  final video = src.tracks.whereType<VideoTrackInfo>().single;
  final base = await _drain(src);
  await src.close();

  const gopUs = 1000000;
  // The fixture's first dts is negative (-200000, the B-frame preroll); shift it
  // to zero so every composition offset stays non-negative.
  final dtsShift = -base.first.dtsUs;

  final packets = <EncodedPacket>[];
  for (var g = 0; g < gops; g++) {
    for (var j = 0; j < base.length; j++) {
      final p = base[j];
      packets.add(EncodedPacket(
        trackIndex: 0,
        data: p.data,
        ptsUs: p.ptsUs + g * gopUs,
        dtsUs: p.dtsUs + dtsShift + g * gopUs,
        durationUs: 100000,
        isKeyframe: j == 0,
      ));
    }
  }
  const audioStride = 1024 * 1000000 ~/ 48000; // one AAC frame
  for (var i = 0; i * audioStride < gops * gopUs; i++) {
    packets.add(EncodedPacket(
      trackIndex: 1,
      data: Uint8List.fromList(List.generate(24, (k) => (i + k) & 0xFF)),
      ptsUs: i * audioStride,
      dtsUs: i * audioStride,
      durationUs: audioStride,
      isKeyframe: true, // AAC really is all-sync; that is the trap
    ));
  }
  // Decode-order interleave, the way a recorder feeds a muxer.
  packets.sort((a, b) => a.dtsUs.compareTo(b.dtsUs));

  final m = Mp4Muxer.open(MuxerConfig(
    container: Container.mp4,
    output: MuxerOutput.file(path),
    tracks: [
      video,
      const AudioTrackInfo(
          codec: AudioCodec.aac, sampleRate: 48000, channels: 2),
    ],
  ));
  await m.writeHeader();
  for (final p in packets) {
    await m.writePacket(p);
  }
  await m.finish();
  await m.close();
  return Uint8List.fromList(File(path).readAsBytesSync());
}

void main() {
  test('B-frame MP4: seek lands on a keyframe at/before the target', () async {
    final f = File(_asset);
    if (!f.existsSync()) {
      markTestSkipped('bframes.mp4 fixture absent (generate with ffmpeg CLI)');
      return;
    }
    final all = await _drain(
        Mp4Demuxer.open(Uint8List.fromList(f.readAsBytesSync())));
    // The property that broke the old scan: pts is NOT sorted in file order.
    var reordered = false;
    for (var i = 1; i < all.length; i++) {
      if (all[i].ptsUs < all[i - 1].ptsUs) reordered = true;
    }
    expect(reordered, isTrue,
        reason: 'fixture must actually carry reordered pts');

    for (final t in [0, 150000, 450000, 500000, 899999, 900000]) {
      final dm = Mp4Demuxer.open(Uint8List.fromList(f.readAsBytesSync()));
      await dm.seek(t);
      final first = await dm.readPacket();
      await dm.close();
      expect(first, isNotNull, reason: 'seek($t) left nothing to read');
      expect(first!.isKeyframe, isTrue,
          reason: 'seek($t) must start decoding at a keyframe');
      expect(first.ptsUs, lessThanOrEqualTo(t),
          reason: 'seek($t) must not overshoot the target');
    }
  });

  test('interleaved audio+video: seek lands on a VIDEO keyframe, not audio',
      () async {
    if (!File(_asset).existsSync()) {
      markTestSkipped('bframes.mp4 fixture absent');
      return;
    }
    final dir = Directory.systemTemp.createTempSync('mp4_seek_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final bytes = await _interleaved('${dir.path}/av.mp4', 4);

    // Sanity: the fixture really is what the test claims.
    final probe = Mp4Demuxer.open(bytes);
    expect(probe.tracks.whereType<VideoTrackInfo>().length, 1);
    expect(probe.tracks.whereType<AudioTrackInfo>().length, 1);
    final videoIdx = probe.tracks.indexWhere((t) => t is VideoTrackInfo);
    final probePkts = await _drain(probe);
    await probe.close();
    final videoKeys = probePkts
        .where((p) => p.trackIndex == videoIdx && p.isKeyframe)
        .map((p) => p.ptsUs)
        .toList();
    expect(videoKeys, [0, 1000000, 2000000, 3000000]);
    expect(probePkts.where((p) => p.trackIndex != videoIdx).length,
        greaterThan(100),
        reason: 'the audio track is what lures a naive seek');
    // The layout under test: tracks alternate in file order.
    var switches = 0;
    for (var i = 1; i < probePkts.length; i++) {
      if (probePkts[i].trackIndex != probePkts[i - 1].trackIndex) switches++;
    }
    expect(switches, greaterThan(20),
        reason: 'this must be an INTERLEAVED file, not track-grouped');

    // Mid-GOP targets: the correct answer is the GOP start, and the WRONG
    // answer (an audio sample, or an early-terminated scan) is a non-keyframe
    // video packet or a video packet from an earlier GOP.
    const targets = {
      1: 0,
      500000: 0,
      1000000: 1000000,
      1500000: 1000000,
      2400000: 2000000,
      3999999: 3000000,
    };
    for (final entry in targets.entries) {
      final dm = Mp4Demuxer.open(bytes);
      await dm.seek(entry.key);
      EncodedPacket? firstVideo;
      for (var p = await dm.readPacket();
          p != null && firstVideo == null;
          p = await dm.readPacket()) {
        if (p.trackIndex == videoIdx) firstVideo = p;
      }
      await dm.close();
      expect(firstVideo, isNotNull,
          reason: 'seek(${entry.key}) left no video to decode');
      expect(firstVideo!.isKeyframe, isTrue,
          reason: 'seek(${entry.key}) started the video mid-GOP');
      expect(firstVideo.ptsUs, entry.value,
          reason: 'seek(${entry.key}) picked the wrong GOP');
    }
  });

  test('audio-only MP4 still seeks (no video track to prefer)', () async {
    final m = Mp4Muxer.open(MuxerConfig(
      container: Container.mp4,
      output: MuxerOutput.bytes(),
      tracks: const [
        AudioTrackInfo(codec: AudioCodec.aac, sampleRate: 48000, channels: 2),
      ],
    ));
    await m.writeHeader();
    const stride = 1024 * 1000000 ~/ 48000;
    for (var i = 0; i < 60; i++) {
      await m.writePacket(EncodedPacket(
        data: Uint8List.fromList(List.generate(20, (k) => (i + k) & 0xFF)),
        ptsUs: i * stride,
        dtsUs: i * stride,
        durationUs: stride,
        isKeyframe: true,
      ));
    }
    await m.finish();
    final bytes = Uint8List.fromList(m.getBytes()!);
    await m.close();

    final dm = Mp4Demuxer.open(bytes);
    await dm.seek(30 * stride);
    final p = await dm.readPacket();
    await dm.close();
    expect(p, isNotNull);
    expect(p!.ptsUs, lessThanOrEqualTo(30 * stride));
    expect(p.ptsUs, greaterThanOrEqualTo(29 * stride),
        reason: 'an audio-only file must still land near the target');
  });
}
