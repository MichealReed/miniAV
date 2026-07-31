/// Multi-track MP4: two real H.264 video tracks plus two audio tracks, muxed
/// together and read back.
///
/// The recorder writes clips with video + microphone + loopback, so the
/// multi-track path is the normal case rather than an exotic one. A muxer that
/// loops over `config.tracks` LOOKS multi-track without being correct: the
/// hazards are all in the shared `mdat` — per-track sample tables that index
/// into one interleaved blob, chunk offsets that must survive the moov being
/// prepended, and per-track timescales. Every one of those produces a file that
/// still parses while playing back wrong, so this demuxes and checks that each
/// packet came back on the track it went in on, byte-for-byte.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';
import 'package:test/test.dart';

const _w = 320, _h = 240;

Uint8List _nv12(int seed) {
  final y = _w * _h;
  final b = Uint8List(y + y ~/ 2);
  for (var i = 0; i < y; i++) {
    b[i] = ((i ~/ _w) + seed * 7) & 0xFF;
  }
  b.fillRange(y, b.length, 128);
  return b;
}

/// Distinct, track-identifiable payload so a mis-routed packet is obvious.
Uint8List _audio(int track, int i) =>
    Uint8List.fromList(List.generate(32 + i, (k) => (track * 100 + i + k) & 0xFF));

void main() {
  test('video + 2 audio tracks survive a mux/demux round trip', () async {
    final enc = await MfVideoEncoder.open(const EncoderConfig(
      codec: VideoCodec.h264,
      width: _w,
      height: _h,
      bitrateBps: 2000000,
      frameRateNumerator: 30,
      frameRateDenominator: 1,
      gopLength: 15,
    ));
    if (enc == null) {
      markTestSkipped('no MF H.264 encoder on this machine');
      return;
    }
    final video = <EncodedPacket>[];
    for (var i = 0; i < 20; i++) {
      final p = await enc.encode(FrameSource.cpu(
        bytes: _nv12(i),
        pixelFormat: MiniAVPixelFormat.nv12,
        width: _w,
        height: _h,
        timestampUs: i * 33333,
      ));
      if (p != null) video.add(p);
    }
    video.addAll(await enc.flush());
    final extra = enc.extraData;
    await enc.close();
    expect(video, isNotEmpty);
    expect(extra, isNotNull);

    final m = Mp4Muxer.open(MuxerConfig(
      container: Container.mp4,
      output: MuxerOutput.bytes(),
      tracks: [
        VideoTrackInfo(
          codec: VideoCodec.h264,
          width: _w,
          height: _h,
          frameRateNumerator: 30,
          frameRateDenominator: 1,
          extraData: extra,
        ),
        // Two audio tracks: mic + loopback, the shape the recorder produces.
        // Different sample rates on purpose — a single hard-coded timescale
        // would still parse and would still be wrong.
        const AudioTrackInfo(
            codec: AudioCodec.aac, sampleRate: 48000, channels: 2),
        const AudioTrackInfo(
            codec: AudioCodec.aac, sampleRate: 44100, channels: 1),
        // A SECOND video track — two screens, or screen + camera. The muxer is
        // generic over tracks, but two video traks means two sync-sample
        // tables, which is where a shared-state bug would show.
        VideoTrackInfo(
          codec: VideoCodec.h264,
          width: _w,
          height: _h,
          frameRateNumerator: 30,
          frameRateDenominator: 1,
          extraData: extra,
        ),
      ],
    ));
    await m.writeHeader();

    // Interleave by PTS, the way a recorder actually feeds a muxer.
    final sent = <int, List<EncodedPacket>>{0: [], 1: [], 2: [], 3: []};
    final all = <EncodedPacket>[
      ...video,
      // Same bitstream on track 3; the container does not care that the bytes
      // repeat, and it still needs its own sample + sync tables.
      ...video.map((p) => EncodedPacket(
            trackIndex: 3,
            data: p.data,
            ptsUs: p.ptsUs,
            dtsUs: p.dtsUs,
            durationUs: p.durationUs,
            isKeyframe: p.isKeyframe,
          )),
    ];
    for (var i = 0; i < 20; i++) {
      all.add(EncodedPacket(
        trackIndex: 1,
        data: _audio(1, i),
        ptsUs: i * 21333,
        dtsUs: i * 21333,
        durationUs: 21333,
        isKeyframe: true,
      ));
      all.add(EncodedPacket(
        trackIndex: 2,
        data: _audio(2, i),
        ptsUs: i * 23219,
        dtsUs: i * 23219,
        durationUs: 23219,
        isKeyframe: true,
      ));
    }
    all.sort((a, b) => a.ptsUs.compareTo(b.ptsUs));
    for (final p in all) {
      sent[p.trackIndex]!.add(p);
      await m.writePacket(p);
    }
    await m.finish();
    final mp4 = Uint8List.fromList(m.getBytes()!);
    await m.close();

    // ---- read back ----
    final d = Mp4Demuxer.open(mp4);
    expect(d.tracks.length, 4, reason: 'expected 4 traks in the moov');
    expect(d.tracks.whereType<VideoTrackInfo>().length, 2);
    final audios = d.tracks.whereType<AudioTrackInfo>().toList();
    expect(audios.length, 2);
    expect(audios.map((a) => a.sampleRate).toList(), [48000, 44100],
        reason: 'per-track timescale did not survive');
    expect(audios.map((a) => a.channels).toList(), [2, 1]);

    final got = <int, List<EncodedPacket>>{0: [], 1: [], 2: [], 3: []};
    while (true) {
      final p = await d.readPacket();
      if (p == null) break;
      got[p.trackIndex]!.add(p);
    }
    await d.close();

    for (final t in [0, 1, 2, 3]) {
      expect(got[t]!.length, sent[t]!.length,
          reason: 'track $t: packet count changed across the round trip');
    }
    // Payloads must match exactly, in order — this is what catches a sample
    // table that points at the wrong offsets in the shared mdat.
    for (final t in [1, 2]) {
      for (var i = 0; i < sent[t]!.length; i++) {
        expect(got[t]![i].data, orderedEquals(sent[t]![i].data),
            reason: 'track $t packet $i came back with different bytes — '
                'sample offsets are crossed between tracks');
      }
    }
    for (final t in [0, 3]) {
      expect(got[t]!.first.isKeyframe, isTrue,
          reason: 'track $t sync sample table (stss) is wrong');
    }
    // Video is NOT compared against what went in: the muxer deliberately
    // reframes Annex-B into length-prefixed samples, so the bytes are expected
    // to differ. The invariant that does hold is that the two video tracks were
    // fed the identical bitstream, so they must come back identical to EACH
    // OTHER -- which is what a crossed sample table between them would break.
    expect(got[3]!.length, got[0]!.length);
    for (var i = 0; i < got[0]!.length; i++) {
      expect(got[3]![i].data, orderedEquals(got[0]![i].data),
          reason: 'the two video tracks diverged at packet $i - their sample '
              'tables are reading overlapping ranges in the shared mdat');
      expect(got[0]![i].data.length, greaterThan(4));
    }
  });
}
