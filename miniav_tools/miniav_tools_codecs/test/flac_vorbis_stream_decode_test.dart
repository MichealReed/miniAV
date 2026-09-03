// Streaming FLAC + Vorbis through the NEGOTIATED decoder — the twin of
// mp3_decode_roundtrip_test's streaming group, for the two codecs sw_audio used
// to claim and could never deliver.
//
// sw_audio sat at priority 55 (above ffmpeg's 50) claiming flac + vorbis, and
// SwAudioDecoder.open can NEVER return null, so it won the negotiation and
// there was no fall-through. But its native entry points (drflac_open_memory /
// stb_vorbis_open_memory) want a whole CONTAINER, and the decoder never reads
// config.extraData — where the demuxer put the STREAMINFO / Vorbis setup
// headers it stripped. Every demuxed batch therefore threw
// CodecRuntimeException, i.e. streamed flac/vorbis had never worked at all.
//
// Nothing caught it because the repo's selection tests assert backend NAMES
// without decoding a byte. This one decodes: it feeds real fixture packets ONE
// AT A TIME through whatever the negotiator picks and insists PCM comes out
// during decode, not only at flush. Re-add flac/vorbis to SwAudioBackend and
// both cases fail with "SW decode failed".
@TestOn('vm')
library;

import 'dart:io';

import 'package:miniav_tools/miniav_tools.dart';
import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';
import 'package:miniav_tools_ffmpeg/miniav_tools_ffmpeg.dart'
    show registerFfmpegBackend;
import 'package:test/test.dart';

void main() {
  // The player's real registration (backend_register_native.dart), so the
  // negotiator sees exactly the field's backend set.
  setUpAll(() {
    registerMfDecodeBackend();
    registerOpusBackend();
    registerPcmBackend();
    registerSwAudioBackend();
    registerAacBackend();
    registerContainerFramingBackend();
    registerFfmpegBackend();
  });

  // (codec, fixture, minimum packets the fixture frames into). The fixtures are
  // the 0.25 s 440 Hz stereo tones sw_audio_test decodes whole-file.
  final cases = <(AudioCodec, String, int)>[
    (AudioCodec.flac, 'test/assets/tone.flac', 3),
    (AudioCodec.vorbis, 'test/assets/tone.ogg', 10),
  ];

  for (final (codec, path, minPackets) in cases) {
    test('${codec.name}: demuxed packets decode to PCM through the negotiated '
        'backend', () async {
      final bytes = File(path).readAsBytesSync();

      final dm = await MiniAVTools.createDemuxer(
        DemuxerConfig(input: DemuxerInput.bytes(bytes)), // no container hint
      );
      final track = dm.tracks.whereType<AudioTrackInfo>().first;
      expect(track.codec, codec);

      final packets = <EncodedPacket>[];
      for (var p = await dm.readPacket(); p != null; p = await dm.readPacket()) {
        packets.add(p);
      }
      await dm.close();
      expect(packets.length, greaterThanOrEqualTo(minPackets),
          reason: 'the fixture must arrive as a packet STREAM, not one blob — '
              'otherwise this asserts nothing about streaming');

      final dec = await MiniAVTools.createAudioDecoder(AudioDecoderConfig(
        codec: track.codec,
        sampleRate: track.sampleRate,
        channels: track.channels,
        extraData: track.extraData?.bytes,
      ));
      // The capability claim under test. sw_audio must not win these: it cannot
      // decline later, so winning is the bug.
      expect(dec.backendName, 'ffmpeg',
          reason: 'sw_audio has no header synthesis for a demuxed '
              '${codec.name} stream, so it must not claim the codec');

      var emissionsDuringDecode = 0;
      final chunks = <DecodedAudio>[];
      for (final p in packets) {
        final out = await dec.decode(p);
        if (out.isNotEmpty) emissionsDuringDecode++;
        chunks.addAll(out);
      }
      chunks.addAll(await dec.flush());
      await dec.close();

      expect(emissionsDuringDecode, greaterThan(1),
          reason: 'a streaming consumer must get audio before EOF');

      var frames = 0;
      var maxAbs = 0.0;
      for (final c in chunks) {
        frames += c.frameCount;
        expect(c.sampleRate, 48000);
        expect(c.channels, 2);
        for (final s in c.samples) {
          final a = s.abs();
          if (a > maxAbs) maxAbs = a;
        }
      }
      // ~0.25 s @ 48 kHz = 12000 sample-frames; Vorbis carries a little lapping
      // padding, so this is an order-of-magnitude floor, not an exact count.
      expect(frames, greaterThan(8000));
      // The fixtures are a 440 Hz tone at ~-21 dB (ffmpeg's sine default,
      // ≈0.088 peak) — clearly non-silent, well below clip.
      expect(maxAbs, greaterThan(0.05), reason: 'a tone, not silence');
      expect(maxAbs, lessThanOrEqualTo(1.01));
    });
  }

  test('without FFmpeg registered there is NO flac/vorbis decoder — that is '
      'the documented consequence, not a surprise', () async {
    // What a reader of the capability table does: excludes FFmpeg on the
    // strength of an "FFmpeg-free FLAC/Vorbis" claim. The claim is gone from
    // both READMEs; this pins what actually happens so the docs cannot drift
    // back to promising a path that does not exist.
    for (final codec in [AudioCodec.flac, AudioCodec.vorbis]) {
      await expectLater(
        MiniAVTools.createAudioDecoder(
          AudioDecoderConfig(codec: codec),
          preference: BackendPreference.excluded({'ffmpeg'}),
        ),
        throwsA(isA<NoBackendForCodecException>()),
        reason: '${codec.name} decode requires miniav_tools_ffmpeg',
      );
    }
    // mp3 is the control: there the FFmpeg-free claim is real.
    final dec = await MiniAVTools.createAudioDecoder(
      const AudioDecoderConfig(codec: AudioCodec.mp3),
      preference: BackendPreference.excluded({'ffmpeg'}),
    );
    expect(dec.backendName, 'sw_audio');
    await dec.close();
  });

  test('sw_audio still owns mp3 — un-claiming flac/vorbis is not a retreat',
      () async {
    final dec = await MiniAVTools.createAudioDecoder(
      const AudioDecoderConfig(codec: AudioCodec.mp3),
    );
    expect(dec.backendName, 'sw_audio');
    await dec.close();

    final b = SwAudioBackend();
    expect(b.supportsAudioDecode(AudioCodec.mp3), isTrue);
    expect(b.supportsAudioDecode(AudioCodec.flac), isFalse);
    expect(b.supportsAudioDecode(AudioCodec.vorbis), isFalse);
    // Nothing here ever encoded; the honest claim is still none.
    for (final c in AudioCodec.values) {
      expect(b.supportsAudioEncode(c), isFalse);
    }
  });
}
