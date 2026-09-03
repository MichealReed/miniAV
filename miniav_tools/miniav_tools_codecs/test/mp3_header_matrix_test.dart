/// EXHAUSTIVE header matrix: every valid (MPEG version) x (bitrate index) x
/// (sample-rate index) x (padding) combination is synthesised, walked, and
/// checked against frame lengths derived from tables typed out here BY HAND.
///
/// Why the tables are duplicated on purpose: the demuxer has its own copy and
/// the fixture synthesiser has a second copy, and a transposition shared by
/// both would cancel out — a synthesised stream would be "wrong" in exactly the
/// way the parser expects, and every existing test would still pass. These
/// constants are a THIRD, independent transcription from ISO/IEC 11172-3
/// (MPEG-1) and ISO/IEC 13818-3 (MPEG-2) Layer III, so all three must agree.
///
/// The gap this closes: the original fixtures all sat at sample-rate index 0
/// (44100 / 22050), which left the other two rate columns of every version
/// unexercised.
@TestOn('vm')
library;

import 'package:miniav_tools_codecs/src/framing/mp3_container.dart';
import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';
import 'package:test/test.dart';

import 'mp3_fixtures.dart';

// --- ISO tables, hand-transcribed (do NOT import these from anywhere) -------

/// MPEG-1 Layer III, kbps by bitrate index 1..14.
const _isoMpeg1Layer3 = <int, int>{
  1: 32, 2: 40, 3: 48, 4: 56, 5: 64, 6: 80, 7: 96,
  8: 112, 9: 128, 10: 160, 11: 192, 12: 224, 13: 256, 14: 320, //
};

/// MPEG-2 / MPEG-2.5 (LSF) Layer III, kbps by bitrate index 1..14.
const _isoMpeg2Layer3 = <int, int>{
  1: 8, 2: 16, 3: 24, 4: 32, 5: 40, 6: 48, 7: 56,
  8: 64, 9: 80, 10: 96, 11: 112, 12: 128, 13: 144, 14: 160, //
};

/// Sample rate by version bits then rate index.
const _isoRates = <int, List<int>>{
  3: [44100, 48000, 32000], // MPEG-1
  2: [22050, 24000, 16000], // MPEG-2
  0: [11025, 12000, 8000], // MPEG-2.5
};

const _versionNames = <int, String>{3: 'MPEG-1', 2: 'MPEG-2', 0: 'MPEG-2.5'};

Future<List<EncodedPacket>> _readAll(PlatformDemuxer d) async {
  final out = <EncodedPacket>[];
  for (var p = await d.readPacket(); p != null; p = await d.readPacket()) {
    out.add(p);
  }
  return out;
}

void main() {
  group('header matrix', () {
    const frames = 6;

    for (final versionBits in [3, 2, 0]) {
      final isMpeg1 = versionBits == 3;
      final bitrates = isMpeg1 ? _isoMpeg1Layer3 : _isoMpeg2Layer3;
      final samplesPerFrame = isMpeg1 ? 1152 : 576;
      final coefficient = isMpeg1 ? 144 : 72;

      for (final rateIndex in [0, 1, 2]) {
        final sampleRate = _isoRates[versionBits]![rateIndex];

        for (final bitrateIndex in bitrates.keys) {
          final kbps = bitrates[bitrateIndex]!;

          for (final padding in [false, true]) {
            final expectedLength =
                coefficient * (kbps * 1000) ~/ sampleRate + (padding ? 1 : 0);
            final name = '${_versionNames[versionBits]} ${sampleRate}Hz '
                '${kbps}kbps pad=${padding ? 1 : 0}';

            test(name, () async {
              final spec = Mp3FrameSpec(
                versionBits: versionBits,
                bitrateIndex: bitrateIndex,
                rateIndex: rateIndex,
                padding: padding,
              );

              // 1. The fixture synthesiser agrees with the ISO tables.
              expect(spec.sampleRate, sampleRate, reason: 'fixture rate');
              expect(spec.bitrateBps, kbps * 1000, reason: 'fixture bitrate');
              expect(spec.frameLength, expectedLength,
                  reason: 'fixture frame length');
              expect(spec.samplesPerFrame, samplesPerFrame);

              final bytes = mp3Stream(repeatSpec(spec, frames));
              expect(bytes.length, expectedLength * frames);

              // 2. The demuxer agrees with the ISO tables.
              final dm = Mp3Demuxer.open(bytes);
              final t = dm.tracks.single as AudioTrackInfo;
              expect(t.codec, AudioCodec.mp3);
              expect(t.sampleRate, sampleRate, reason: 'demuxed rate');
              expect(t.channels, 2);
              expect(dm.frameCount, frames, reason: 'every frame indexed');
              expect(dm.resyncCount, 0, reason: 'no frame may need a resync');
              expect(dm.vbrHeader, isNull);
              expect(dm.durationUs,
                  frames * samplesPerFrame * 1000000 ~/ sampleRate);

              // 3. Byte-exact framing and timing per packet.
              final pkts = await _readAll(dm);
              expect(pkts.length, frames);
              var consumed = 0;
              for (var i = 0; i < pkts.length; i++) {
                expect(pkts[i].data.length, expectedLength,
                    reason: 'packet $i length');
                expect(pkts[i].data[0], 0xFF);
                expect(isMp3Sync(pkts[i].data[0], pkts[i].data[1]), isTrue);
                expect(pkts[i].ptsUs,
                    i * samplesPerFrame * 1000000 ~/ sampleRate,
                    reason: 'packet $i pts');
                expect(pkts[i].durationUs,
                    samplesPerFrame * 1000000 ~/ sampleRate);
                consumed += pkts[i].data.length;
              }
              expect(consumed, bytes.length,
                  reason: 'the walk must consume every byte');

              // 4. Seek addresses the same grid.
              await dm.seek(pkts[frames - 2].ptsUs);
              expect((await dm.readPacket())!.ptsUs, pkts[frames - 2].ptsUs);
              await dm.close();
            });
          }
        }
      }
    }
  });

  group('mono + Xing across every sample rate', () {
    // A metadata frame sits at a version/channel-dependent offset, so it has to
    // be found at every rate too, not just the one the first fixtures used.
    for (final versionBits in [3, 2, 0]) {
      for (final rateIndex in [0, 1, 2]) {
        final sampleRate = _isoRates[versionBits]![rateIndex];
        test('${_versionNames[versionBits]} ${sampleRate}Hz mono + Info',
            () async {
          final spec = Mp3FrameSpec(
            versionBits: versionBits,
            bitrateIndex: 8,
            rateIndex: rateIndex,
            channelMode: 3, // mono
          );
          final bytes = concatBytes([
            id3v2Tag(bodySize: 96),
            mp3VbrFrame(spec, kind: 'Info', frameCount: 5),
            mp3Stream(repeatSpec(spec, 5)),
          ]);
          final dm = Mp3Demuxer.open(bytes);
          final t = dm.tracks.single as AudioTrackInfo;
          expect(t.sampleRate, sampleRate);
          expect(t.channels, 1);
          expect(dm.vbrHeader?.kind, 'Info');
          expect(dm.vbrHeader?.frameCount, 5);
          expect(dm.frameCount, 5);
          expect(dm.firstFrameOffset, 106);
          await dm.close();
        });
      }
    }
  });

  group('field-report shape (Lavf, 48 kHz stereo, ID3v2.4 + Info)', () {
    // The reported file: MPEG-1 Layer III, 48000 Hz stereo, an ID3v2.4 tag then
    // a `ff fb ..` sync. Both readings of the reported bitrate are covered:
    // index 11 = 192 kbps (`ff fb b4`, 576-byte frames) and index 12 = 224 kbps
    // (`ff fb c4`, 672-byte frames).
    for (final (bitrateIndex, kbps, frameLen, b2) in [
      (11, 192, 576, 0xB4),
      (12, 224, 672, 0xC4),
    ]) {
      test('$kbps kbps → $frameLen-byte frames, long stream', () async {
        const count = 4000; // ~96 s — well past "a fraction of a second"
        final spec = Mp3FrameSpec(
          bitrateIndex: bitrateIndex,
          rateIndex: 1, // 48000
        );
        expect(spec.frameLength, frameLen);

        final bytes = concatBytes([
          id3v2Tag(bodySize: 34),
          mp3VbrFrame(spec, kind: 'Info', frameCount: count),
          mp3Stream(repeatSpec(spec, count)),
        ]);
        // The exact header bytes from the field report.
        expect(bytes[44], 0xFF);
        expect(bytes[45], 0xFB);
        expect(bytes[46], b2);

        final dm = Mp3Demuxer.open(bytes);
        final t = dm.tracks.single as AudioTrackInfo;
        expect(t.sampleRate, 48000);
        expect(t.channels, 2);
        expect(dm.firstFrameOffset, 44);
        expect(dm.vbrHeader?.kind, 'Info');
        expect(dm.resyncCount, 0);
        expect(dm.frameCount, count, reason: 'the whole file must be indexed');
        expect(dm.durationUs, count * 1152 * 1000000 ~/ 48000);

        final pkts = await _readAll(dm);
        expect(pkts.length, count);
        expect(pkts.last.ptsUs, (count - 1) * 1152 * 1000000 ~/ 48000);
        expect(pkts.last.data.length, frameLen);
        await dm.close();
      });
    }
  });
}
