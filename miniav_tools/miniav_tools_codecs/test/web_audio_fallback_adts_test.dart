/// ADTS synthesis for the decodeAudioData fallback — the piece that gives AAC
/// a decode path on WebKit before AudioDecoder shipped (iOS < 18.4).
///
///   dart test -p chrome --tags browser test/web_audio_fallback_adts_test.dart
///
/// Bit-level assertions are hand-derived from ISO 14496-3 (ASC) and the ADTS
/// header layout; the header test re-extracts every field from the packed
/// bytes rather than trusting the packer's own constants.
@TestOn('browser')
@Tags(['browser'])
library;

import 'dart:typed_data';

import 'package:miniav_tools_codecs/src/web/web_audio_fallback_decoder.dart';
import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';
import 'package:test/test.dart';

void main() {
  group('AdtsParams.fromAudioSpecificConfig', () {
    test('AAC-LC 44.1kHz stereo (the common MP4 case)', () {
      // AOT=2 (00010), freqIndex=4 (0100), channelConfig=2 (0010)
      // -> 00010 0100 0010 000 -> 0x12 0x10
      final p = AdtsParams.fromAudioSpecificConfig(
        Uint8List.fromList([0x12, 0x10]),
      );
      expect(p, isNotNull);
      expect(p!.profile, 1); // ADTS profile = AOT - 1
      expect(p.freqIndex, 4);
      expect(p.channelConfig, 2);
    });

    test('HE-AAC (AOT 5) is carried as its LC core', () {
      // AOT=5 (00101), coreFreqIndex=7/22050 (0111), channelConfig=2 (0010)
      // -> 00101 0111 0010 000 -> 0x2B 0x90
      final p = AdtsParams.fromAudioSpecificConfig(
        Uint8List.fromList([0x2B, 0x90]),
      );
      expect(p, isNotNull);
      expect(p!.profile, 1, reason: 'SBR rides on an LC core in ADTS');
      expect(p.freqIndex, 7, reason: 'the FIRST freq index is the core rate');
      expect(p.channelConfig, 2);
    });

    test('explicit 24-bit rate maps back onto the table', () {
      // AOT=2, freqIndex=15 (escape), rate=44100 (24 bits), channelConfig=2
      // 00010 1111 000000001010110001000100 0010 -> pad to bytes:
      // 00010111 10000000 01010110 00100010 00010(000)
      final p = AdtsParams.fromAudioSpecificConfig(
        Uint8List.fromList([0x17, 0x80, 0x56, 0x22, 0x10]),
      );
      expect(p, isNotNull);
      expect(p!.freqIndex, 4, reason: '44100 is table index 4');
      expect(p.channelConfig, 2);
    });

    test('an ER/xHE object type cannot be ADTS-wrapped', () {
      // AOT=23 (ER AAC LD): 10111 0100 0010 000 -> 0xBA 0x10
      expect(
        AdtsParams.fromAudioSpecificConfig(Uint8List.fromList([0xBA, 0x10])),
        isNull,
      );
    });

    test('truncated ASC is rejected, not misread', () {
      expect(AdtsParams.fromAudioSpecificConfig(Uint8List.fromList([0x12])),
          isNull);
    });
  });

  group('AdtsParams.headerFor', () {
    test('every field survives a round-trip through the packed bytes', () {
      const p = AdtsParams(1, 4, 2); // LC, 44.1kHz, stereo
      final h = p.headerFor(100);
      expect(h.length, 7);
      // syncword: 12 bits of 1s
      expect(h[0], 0xFF);
      expect(h[1] >> 4, 0xF);
      expect((h[1] >> 3) & 1, 0, reason: 'MPEG-4 ID');
      expect((h[1] >> 1) & 3, 0, reason: 'layer must be 00');
      expect(h[1] & 1, 1, reason: 'protection absent — header is 7 bytes');
      expect((h[2] >> 6) & 0x3, 1, reason: 'profile LC');
      expect((h[2] >> 2) & 0xF, 4, reason: 'freq index');
      final chan = ((h[2] & 0x1) << 2) | ((h[3] >> 6) & 0x3);
      expect(chan, 2, reason: 'channel config straddles bytes 2/3');
      final frameLen = ((h[3] & 0x3) << 11) | (h[4] << 3) | ((h[5] >> 5) & 0x7);
      expect(frameLen, 107, reason: 'payload 100 + 7 header bytes');
      final fullness = ((h[5] & 0x1F) << 6) | ((h[6] >> 2) & 0x3F);
      expect(fullness, 0x7FF, reason: 'VBR marker');
      expect(h[6] & 0x3, 0, reason: 'one raw data block');
    });

    test('mono 8-channel edge: channelConfig high bit lands in byte 2', () {
      const p = AdtsParams(1, 11, 7); // 8000Hz, 7.1 (config 7)
      final h = p.headerFor(1);
      final chan = ((h[2] & 0x1) << 2) | ((h[3] >> 6) & 0x3);
      expect(chan, 7);
    });
  });

  group('WebAudioFallbackDecoder AAC intake', () {
    test('raw AAC without ASC and without ADTS refuses loudly, not garbled',
        () async {
      final dec = WebAudioFallbackDecoder.create(
        const AudioDecoderConfig(codec: AudioCodec.aac),
      );
      expect(dec, isNotNull, reason: 'ADTS passthrough might still work');
      // 0x21 0x1A... — no 0xFFF syncword, no ASC to wrap with.
      expect(
        () => dec!.decode(EncodedPacket(
          data: Uint8List.fromList([0x21, 0x1A, 0x00, 0x00]),
          ptsUs: 0,
          dtsUs: 0,
        )),
        throwsA(isA<StateError>()),
      );
    });

    test('ADTS packets pass through even with no extraData', () async {
      final dec = WebAudioFallbackDecoder.create(
        const AudioDecoderConfig(codec: AudioCodec.aac),
      )!;
      final adtsFrame = Uint8List.fromList(
        [0xFF, 0xF1, 0x50, 0x80, 0x01, 0x3F, 0xFC, 0xAA],
      );
      final out = await dec.decode(
        EncodedPacket(data: adtsFrame, ptsUs: 0, dtsUs: 0),
      );
      expect(out, isEmpty, reason: 'whole-buffer decoder emits at flush');
    });

    test('mp3 create path is unchanged', () {
      expect(
        WebAudioFallbackDecoder.create(
          const AudioDecoderConfig(codec: AudioCodec.mp3, sampleRate: 44100),
        ),
        isNotNull,
      );
      expect(
        WebAudioFallbackDecoder.create(
          const AudioDecoderConfig(codec: AudioCodec.flac),
        ),
        isNull,
      );
    });
  });
}
