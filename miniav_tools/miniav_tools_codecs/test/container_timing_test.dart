// Container-reported time has to be TRUE, not a default assumed at write time:
// Ogg/Opus with non-20 ms packets, MP4's last sample, and ADTS's duration.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';
import 'package:test/test.dart';

// --- Ogg -------------------------------------------------------------------

/// A bare Opus packet whose TOC declares [ms] per frame in CELT fullband mode
/// (configs 28-31 = 2.5/5/10/20 ms) or SILK wideband (8-11 = 10/20/40/60 ms).
/// The payload is filler — nothing here decodes it, only times it.
Uint8List _opusPacket(int ms, {int payload = 8}) {
  final config = switch (ms) {
    10 => 8, // SILK WB 10 ms
    20 => 9, // SILK WB 20 ms
    40 => 10, // SILK WB 40 ms
    60 => 11, // SILK WB 60 ms
    _ => throw ArgumentError('unhandled $ms ms'),
  };
  final b = Uint8List(1 + payload);
  b[0] = (config << 3) | 0; // code 0 = one frame in this packet
  for (var i = 1; i < b.length; i++) {
    b[i] = i & 0xFF;
  }
  return b;
}

Uint8List _oggWith(int ms, int count) {
  final mux = OggMuxer.open(MuxerConfig(
    container: Container.ogg,
    output: MuxerOutput.bytes(),
    tracks: const [
      AudioTrackInfo(codec: AudioCodec.opus, sampleRate: 48000, channels: 2),
    ],
  ));
  return () {
    mux.writeHeader();
    for (var i = 0; i < count; i++) {
      mux.writePacket(EncodedPacket(
        data: _opusPacket(ms),
        ptsUs: i * ms * 1000,
        dtsUs: i * ms * 1000,
      ));
    }
    mux.finish();
    return Uint8List.fromList(mux.getBytes()!);
  }();
}

/// [count] packets of [ms] each, behind an OpusHead declaring [preSkip]
/// priming samples (48 kHz) — what a real encoder's own header carries.
Uint8List _oggPreSkip(int ms, int count, int preSkip) {
  final head = Uint8List(19)
    ..setRange(0, 8, 'OpusHead'.codeUnits)
    ..[8] = 1
    ..[9] = 2;
  final bd = ByteData.sublistView(head);
  bd.setUint16(10, preSkip, Endian.little);
  bd.setUint32(12, 48000, Endian.little);

  final mux = OggMuxer.open(MuxerConfig(
    container: Container.ogg,
    output: MuxerOutput.bytes(),
    tracks: [
      AudioTrackInfo(
        codec: AudioCodec.opus,
        sampleRate: 48000,
        channels: 2,
        extraData: CodecExtraData.audio(AudioCodec.opus, head),
      ),
    ],
  ));
  mux.writeHeader();
  for (var i = 0; i < count; i++) {
    mux.writePacket(EncodedPacket(
      data: _opusPacket(ms),
      ptsUs: i * ms * 1000,
      dtsUs: i * ms * 1000,
    ));
  }
  mux.finish();
  return Uint8List.fromList(mux.getBytes()!);
}

void main() {
  group('Ogg/Opus timing follows the TOC, not a 20 ms guess', () {
    test('40 ms packets report their real duration', () async {
      const ms = 40, count = 25; // 1.0 s of audio
      final d = OggDemuxer.open(_oggWith(ms, count));
      const truth = ms * count * 1000; // 1_000_000 µs
      expect((d.durationUs! - truth).abs(), lessThanOrEqualTo(ms * 1000),
          reason: 'duration must be within ONE packet of the truth; the old '
              'packetCount*20000 rule reported half of it');
      expect(d.durationUs, truth);
    });

    test('per-packet PTS advances by the packet duration', () async {
      const ms = 40, count = 10;
      final d = OggDemuxer.open(_oggWith(ms, count));
      final pts = <int>[], durs = <int>[];
      for (var p = await d.readPacket(); p != null; p = await d.readPacket()) {
        pts.add(p.ptsUs);
        durs.add(p.durationUs);
      }
      expect(pts, [for (var i = 0; i < count; i++) i * ms * 1000]);
      expect(durs, List.filled(count, ms * 1000));
    });

    test('seek(t) lands within one packet of t', () async {
      const ms = 40, count = 25;
      final d = OggDemuxer.open(_oggWith(ms, count));
      for (final targetUs in const [0, 100000, 399999, 400000, 640000]) {
        await d.seek(targetUs);
        final p = await d.readPacket();
        expect(p, isNotNull);
        expect(p!.ptsUs, lessThanOrEqualTo(targetUs));
        expect(targetUs - p.ptsUs, lessThan(ms * 1000),
            reason: 'seek to $targetUs µs landed on ${p.ptsUs} µs');
      }
    });

    test('10 ms and 60 ms packets are timed too', () async {
      for (final ms in const [10, 20, 60]) {
        final count = 600 ~/ ms; // 0.6 s each way
        final d = OggDemuxer.open(_oggWith(ms, count));
        expect(d.durationUs, ms * count * 1000, reason: '$ms ms packets');
      }
    });

    test('the pre-skip is subtracted from the playable length', () async {
      const ms = 20, count = 10;
      const preSkip = 312;
      final d = OggDemuxer.open(_oggPreSkip(ms, count, preSkip));
      const full = ms * count * 1000;
      expect(d.durationUs, full - preSkip * 1000000 ~/ 48000,
          reason: 'priming samples are not playable audio');
    });

    test('packet durations stay on the pre-skipped timeline', () async {
      // Pulling the starts back by the pre-skip while leaving every duration at
      // its full TOC length makes the emitted timeline contradict itself:
      // packet 0 would still run to 20 ms while packet 1 starts at 13.5 ms, and
      // the durations would sum past durationUs. A remuxer that builds its
      // sample table out of EncodedPacket.durationUs (MP4's stts) writes that
      // disagreement into the file.
      const ms = 20, count = 10, preSkip = 312;
      final d = OggDemuxer.open(_oggPreSkip(ms, count, preSkip));

      final pts = <int>[], durs = <int>[];
      for (var p = await d.readPacket(); p != null; p = await d.readPacket()) {
        pts.add(p.ptsUs);
        durs.add(p.durationUs);
      }
      expect(pts.length, count);
      for (var i = 0; i + 1 < count; i++) {
        expect(pts[i] + durs[i], pts[i + 1],
            reason: 'packet $i must end where packet ${i + 1} begins');
      }
      expect(durs.reduce((a, b) => a + b), d.durationUs,
          reason: 'the durations must add up to the playable length');
      expect(durs.first, lessThan(ms * 1000),
          reason: 'the trimmed priming is not part of packet 0');
      // Every other packet is untouched: only the head loses samples.
      expect(durs.sublist(1), List.filled(count - 1, ms * 1000));
    });
  });

  group('MP4 duration reaches the end of the last sample', () {
    Future<Uint8List> mux(List<EncodedPacket> pkts) async {
      final m = Mp4Muxer.open(MuxerConfig(
        container: Container.mp4,
        output: MuxerOutput.bytes(),
        tracks: const [
          AudioTrackInfo(
            codec: AudioCodec.aac,
            sampleRate: 48000,
            channels: 2,
          ),
        ],
      ));
      await m.writeHeader();
      for (final p in pkts) {
        await m.writePacket(p);
      }
      await m.finish();
      return Uint8List.fromList(m.getBytes()!);
    }

    test('duration is lastPts + lastDuration', () async {
      const step = 21333; // ~1024 samples @ 48 kHz
      const n = 20;
      final bytes = await mux([
        for (var i = 0; i < n; i++)
          EncodedPacket(
            data: Uint8List(16)..[0] = i,
            ptsUs: i * step,
            dtsUs: i * step,
            durationUs: step,
            isKeyframe: true,
          ),
      ]);
      final d = Mp4Demuxer.open(bytes);
      expect(d.durationUs, n * step,
          reason: 'the last sample plays for its own duration too');
    });

    test('a single-sample track is not zero-length', () async {
      const step = 40000;
      final bytes = await mux([
        EncodedPacket(
          data: Uint8List(16),
          ptsUs: 0,
          dtsUs: 0,
          durationUs: step,
          isKeyframe: true,
        ),
      ]);
      final d = Mp4Demuxer.open(bytes);
      expect(d.durationUs, step,
          reason: 'max(pts) alone reports 0 µs for a one-sample track');
    });
  });

  group('ADTS reports a real duration', () {
    /// [n] ADTS frames of [payload] bytes each at 44.1 kHz stereo.
    Uint8List adts(int n, {int payload = 32}) {
      final mux = AdtsMuxer.open(MuxerConfig(
        container: Container.adts,
        output: MuxerOutput.bytes(),
        tracks: const [
          AudioTrackInfo(
            codec: AudioCodec.aac,
            sampleRate: 44100,
            channels: 2,
          ),
        ],
      ));
      mux.writeHeader();
      for (var i = 0; i < n; i++) {
        mux.writePacket(EncodedPacket(
          data: Uint8List(payload)..[0] = i & 0xFF,
          ptsUs: 0,
          dtsUs: 0,
        ));
      }
      return Uint8List.fromList(mux.getBytes()!);
    }

    test('duration is frameCount * 1024 / sampleRate', () {
      const n = 431; // ~10 s at 44.1 kHz
      final d = AdtsDemuxer.open(adts(n));
      expect(d.durationUs, n * 1024 * 1000000 ~/ 44100);
    });

    test('reading the duration does not disturb the read cursor', () async {
      const n = 12;
      final d = AdtsDemuxer.open(adts(n));
      final first = await d.readPacket();
      expect(d.durationUs, n * 1024 * 1000000 ~/ 44100);
      final second = await d.readPacket();
      expect(second!.ptsUs, greaterThan(first!.ptsUs),
          reason: 'the duration walk must not consume packets');

      final rest = <int>[];
      for (var p = await d.readPacket(); p != null; p = await d.readPacket()) {
        rest.add(p.ptsUs);
      }
      expect(rest.length, n - 2);
    });

    test('durationUs is readable after close(), like every other demuxer',
        () async {
      // A player's `duration` getter reads demuxer.durationUs unguarded, and
      // close() does not null the demuxer — so a widget rebuild during teardown
      // would throw out of build() on an .aac source. The other three
      // containers' durationUs getters never throw.
      const n = 12;
      final d = AdtsDemuxer.open(adts(n));
      final want = d.durationUs;
      await d.close();
      expect(d.durationUs, want);

      final fresh = AdtsDemuxer.open(adts(n));
      await fresh.close();
      expect(fresh.durationUs, want,
          reason: 'even uncached, the walk only reads the in-memory buffer');
    });
  });
}
