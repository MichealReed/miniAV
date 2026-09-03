// Proves the WHOLE first-party audio + container stack is selectable over
// FFmpeg — and that what gets selected actually WORKS.
//
// Registers the EXACT set miniav_player's backend_register_native.dart
// registers (MF decode + Opus + PCM + sw_audio + OS AAC + framing + FFmpeg) and
// checks the negotiator routes every first-party codec/container to its
// first-party backend, both by default and with FFmpeg explicitly excluded.
//
// The original version of this file asserted `backendName` and nothing else. A
// backend that WINS the negotiation and then cannot decode a byte passes such a
// test perfectly — which is how sw_audio shipped claiming flac + vorbis it
// could never decode from a demuxed stream (it never reads extraData, and its
// native entry points want a whole container). So every route below now does
// real work on the thing it negotiated: demuxers must yield a packet, decoders
// must yield PCM, encoders must yield packets.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:miniav_tools/miniav_tools.dart';
import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';
import 'package:miniav_tools_ffmpeg/miniav_tools_ffmpeg.dart'
    show registerFfmpegBackend;
import 'package:test/test.dart';

const _rate = 48000;
const _channels = 2;
const _frame = 960; // 20 ms @ 48 kHz

/// Interleaved f32 sine — real audio, so "decoded to silence" is a failure.
Uint8List _sineF32(int startFrame, int frameCount) {
  final out = Float32List(frameCount * _channels);
  for (var i = 0; i < frameCount; i++) {
    final v = math.sin(2 * math.pi * 440.0 * (startFrame + i) / _rate) * 0.25;
    for (var c = 0; c < _channels; c++) {
      out[i * _channels + c] = v;
    }
  }
  return out.buffer.asUint8List();
}

double _peak(Iterable<DecodedAudio> chunks) {
  var maxAbs = 0.0;
  for (final c in chunks) {
    for (final s in c.samples) {
      final a = s.abs();
      if (a > maxAbs) maxAbs = a;
    }
  }
  return maxAbs;
}

/// Build a tiny valid Ogg/Opus stream (header pages + one dummy audio packet).
Future<Uint8List> _oggBytes() async {
  final mux = OggMuxer.open(MuxerConfig(
    container: Container.ogg,
    output: MuxerOutput.bytes(),
    tracks: const [
      AudioTrackInfo(codec: AudioCodec.opus, sampleRate: _rate, channels: 2),
    ],
  ));
  await mux.writeHeader();
  await mux.writePacket(
    EncodedPacket(data: Uint8List.fromList([0xFC, 1, 2, 3]), ptsUs: 0, dtsUs: 0),
  );
  await mux.finish();
  return Uint8List.fromList(mux.getBytes()!);
}

Future<Uint8List> _wavBytes() async {
  final mux = WavMuxer.open(MuxerConfig(
    container: Container.wav,
    output: MuxerOutput.bytes(),
    tracks: const [
      AudioTrackInfo(
          codec: AudioCodec.pcmS16le, sampleRate: _rate, channels: _channels),
    ],
  ));
  await mux.writeHeader();
  // 64 sample-frames of a real ramp: a demuxer that hands back an empty or
  // zero-length packet must not pass.
  final pcm = Uint8List(64 * _channels * 2);
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] = (i * 3) & 0xFF;
  }
  await mux.writePacket(EncodedPacket(data: pcm, ptsUs: 0, dtsUs: 0));
  await mux.finish();
  return Uint8List.fromList(mux.getBytes()!);
}

void main() {
  // EXACTLY the player's registration order
  // (miniav_player/lib/src/backend_register_native.dart).
  setUpAll(() {
    registerMfDecodeBackend();
    registerOpusBackend();
    registerPcmBackend();
    registerSwAudioBackend();
    registerAacBackend();
    registerContainerFramingBackend();
    registerFfmpegBackend();
  });

  final excl = BackendPreference.excluded({'ffmpeg'});

  group('audio codecs route first-party AND work', () {
    test('Opus encode → decode round-trips through the opus backend', () async {
      final e = await MiniAVTools.createAudioEncoder(
        const AudioEncoderConfig(
          codec: AudioCodec.opus,
          sampleRate: _rate,
          channels: _channels,
          bitrateBps: 96000,
        ),
        preference: excl,
      );
      expect(e.backendName, 'opus');
      final packets = <EncodedPacket>[];
      for (var i = 0; i < 25; i++) {
        packets.addAll(await e.encode(
          pcm: _sineF32(i * _frame, _frame),
          format: MiniAVAudioFormat.f32,
          frameCount: _frame,
          ptsUs: (i * _frame * 1000000) ~/ _rate,
        ));
      }
      packets.addAll(await e.flush());
      final head = e.extraData?.bytes;
      await e.close();
      expect(packets, isNotEmpty, reason: 'the opus encoder produced nothing');

      final d = await MiniAVTools.createAudioDecoder(
        AudioDecoderConfig(
          codec: AudioCodec.opus,
          extraData: head,
          sampleRate: _rate,
          channels: _channels,
        ),
        preference: excl,
      );
      expect(d.backendName, 'opus');
      final chunks = <DecodedAudio>[];
      for (final p in packets) {
        chunks.addAll(await d.decode(p));
      }
      await d.close();
      expect(chunks, isNotEmpty, reason: 'the opus decoder produced no PCM');
      var frames = 0;
      for (final c in chunks) {
        frames += c.frameCount;
        expect(c.channels, _channels);
        expect(c.samples.length, c.frameCount * c.channels);
      }
      expect(frames, greaterThan(_frame * 10));
      expect(_peak(chunks), greaterThan(0.05), reason: 'a tone, not silence');
    });

    test('PCM decode + encode → pcm, with the samples intact', () async {
      // s16 ramp, so a decoder that returns silence or the wrong geometry is
      // visible.
      final src = Int16List(_frame * _channels);
      for (var i = 0; i < src.length; i++) {
        src[i] = ((i * 977) % 20000) - 10000;
      }
      final raw = src.buffer.asUint8List();

      for (final pref in [BackendPreference.auto, excl]) {
        final d = await MiniAVTools.createAudioDecoder(
          const AudioDecoderConfig(
            codec: AudioCodec.pcmS16le,
            sampleRate: _rate,
            channels: _channels,
          ),
          preference: pref,
        );
        expect(d.backendName, 'pcm');
        final out = await d.decode(
          EncodedPacket(data: raw, ptsUs: 0, dtsUs: 0),
        );
        await d.close();
        expect(out, isNotEmpty, reason: 'pcm decode produced nothing');
        final c = out.first;
        expect(c.frameCount, _frame);
        expect(c.channels, _channels);
        expect(c.samples.length, _frame * _channels);
        for (var i = 0; i < c.samples.length; i++) {
          expect(c.samples[i], closeTo(src[i] / 32768.0, 1e-4),
              reason: 'sample $i did not survive');
        }
      }

      final e = await MiniAVTools.createAudioEncoder(
        const AudioEncoderConfig(
          codec: AudioCodec.pcmF32le,
          sampleRate: _rate,
          channels: _channels,
          bitrateBps: 0,
        ),
      );
      expect(e.backendName, 'pcm');
      final enc = await e.encode(
        pcm: _sineF32(0, _frame),
        format: MiniAVAudioFormat.f32,
        frameCount: _frame,
        ptsUs: 0,
      );
      await e.close();
      expect(enc, isNotEmpty);
      expect(enc.first.data.length, _frame * _channels * 4);
    });

    test('MP3 decodes to audible PCM through sw_audio', () async {
      final bytes = File('test/assets/tone.mp3').readAsBytesSync();
      final dm = await MiniAVTools.createDemuxer(
        DemuxerConfig(input: DemuxerInput.bytes(bytes)),
        preference: excl,
      );
      expect(dm.backendName, 'container_framing');
      final track = dm.tracks.single as AudioTrackInfo;
      expect(track.codec, AudioCodec.mp3);

      final dec = await MiniAVTools.createAudioDecoder(
        AudioDecoderConfig(
          codec: track.codec,
          sampleRate: track.sampleRate,
          channels: track.channels,
        ),
        preference: excl,
      );
      expect(dec.backendName, 'sw_audio');

      final chunks = <DecodedAudio>[];
      var packets = 0;
      for (var p = await dm.readPacket(); p != null; p = await dm.readPacket()) {
        chunks.addAll(await dec.decode(p));
        packets++;
      }
      chunks.addAll(await dec.flush());
      await dec.close();
      await dm.close();
      expect(packets, greaterThan(4));
      expect(chunks, isNotEmpty, reason: 'sw_audio decoded no MP3 PCM');
      expect(_peak(chunks), greaterThan(0.05));
    });

    // The F1 guard. sw_audio must not claim these: it wins at priority 55 and
    // SwAudioDecoder.open can never return null, so a claim here is FINAL.
    // Re-add flac/vorbis to SwAudioBackend and this test throws
    // "CodecRuntimeException: SW decode failed".
    for (final (codec, asset) in [
      (AudioCodec.flac, 'test/assets/tone.flac'),
      (AudioCodec.vorbis, 'test/assets/tone.ogg'),
    ]) {
      test('${codec.name} decodes to PCM through whatever backend wins',
          () async {
        final bytes = File(asset).readAsBytesSync();
        final dm = await MiniAVTools.createDemuxer(
          DemuxerConfig(input: DemuxerInput.bytes(bytes)),
        );
        final track = dm.tracks.whereType<AudioTrackInfo>().first;
        expect(track.codec, codec);
        final packets = <EncodedPacket>[];
        for (var p = await dm.readPacket();
            p != null;
            p = await dm.readPacket()) {
          packets.add(p);
        }
        await dm.close();
        expect(packets.length, greaterThan(2),
            reason: 'this must be a packet STREAM, which is the case sw_audio '
                'could not handle');

        final dec = await MiniAVTools.createAudioDecoder(AudioDecoderConfig(
          codec: track.codec,
          sampleRate: track.sampleRate,
          channels: track.channels,
          extraData: track.extraData?.bytes,
        ));
        final chunks = <DecodedAudio>[];
        for (final p in packets) {
          chunks.addAll(await dec.decode(p));
        }
        chunks.addAll(await dec.flush());
        await dec.close();
        expect(chunks, isNotEmpty,
            reason: '${dec.backendName} won the ${codec.name} negotiation and '
                'produced no PCM at all');
        expect(_peak(chunks), greaterThan(0.05), reason: 'a tone, not silence');
      });
    }
  });

  group('containers route first-party AND parse', () {
    test('Ogg demux → container_framing, and it yields the packet', () async {
      final ogg = await _oggBytes();
      for (final pref in [BackendPreference.auto, excl]) {
        final dm = await MiniAVTools.createDemuxer(
          DemuxerConfig(
            container: Container.ogg,
            input: DemuxerInput.bytes(ogg),
          ),
          preference: pref,
        );
        expect(dm.backendName, 'container_framing');
        final t = dm.tracks.single as AudioTrackInfo;
        expect(t.codec, AudioCodec.opus);
        final p = await dm.readPacket();
        expect(p, isNotNull, reason: 'the ogg demuxer produced no packet');
        expect(p!.data, [0xFC, 1, 2, 3],
            reason: 'the audio packet did not survive the round trip');
        await dm.close();
      }
    });

    test('WAV demux → container_framing, and the samples come back', () async {
      final wav = await _wavBytes();
      final dm = await MiniAVTools.createDemuxer(
        DemuxerConfig(
          container: Container.wav,
          input: DemuxerInput.bytes(wav),
        ),
        preference: excl,
      );
      expect(dm.backendName, 'container_framing');
      final t = dm.tracks.single as AudioTrackInfo;
      expect(t.sampleRate, _rate);
      expect(t.channels, _channels);
      var bytes = 0;
      for (var p = await dm.readPacket(); p != null; p = await dm.readPacket()) {
        bytes += p.data.length;
      }
      await dm.close();
      expect(bytes, 64 * _channels * 2,
          reason: 'every PCM byte written must come back out');
    });

    test('Ogg mux → container_framing, and it emits a real stream', () async {
      final m = await MiniAVTools.createMuxer(
        MuxerConfig(
          container: Container.ogg,
          output: MuxerOutput.bytes(),
          tracks: const [
            AudioTrackInfo(
              codec: AudioCodec.opus,
              sampleRate: _rate,
              channels: _channels,
            ),
          ],
        ),
        preference: excl,
      );
      expect(m.backendName, 'container_framing');
      await m.writeHeader();
      await m.writePacket(EncodedPacket(
        data: Uint8List.fromList([0xFC, 9, 8, 7]),
        ptsUs: 0,
        dtsUs: 0,
      ));
      await m.finish();
      final out = m.getBytes();
      await m.close();
      expect(out, isNotNull);
      expect(out!.length, greaterThan(64));
      expect(out.sublist(0, 4), 'OggS'.codeUnits,
          reason: 'the muxer produced bytes that are not an Ogg stream');
    });

    test('MP4 demux + mux are both first-party, and round-trip (P2.3)',
        () async {
      final fw = ContainerFramingBackend();
      expect(fw.supportsDemux(Container.mp4), isTrue); // Mp4Demuxer
      expect(fw.supportsMux(Container.mp4), isTrue); // Mp4Muxer

      // Do the work, not just the claim: mux an AAC track and read it back.
      final m = await MiniAVTools.createMuxer(
        MuxerConfig(
          container: Container.mp4,
          output: MuxerOutput.bytes(),
          tracks: const [
            AudioTrackInfo(
              codec: AudioCodec.aac,
              sampleRate: _rate,
              channels: _channels,
            ),
          ],
        ),
        preference: excl,
      );
      expect(m.backendName, 'container_framing');
      await m.writeHeader();
      const stride = 1024 * 1000000 ~/ _rate;
      final sent = <Uint8List>[];
      for (var i = 0; i < 10; i++) {
        final data =
            Uint8List.fromList(List.generate(30, (k) => (i * 5 + k) & 0xFF));
        sent.add(data);
        await m.writePacket(EncodedPacket(
          data: data,
          ptsUs: i * stride,
          dtsUs: i * stride,
          durationUs: stride,
          isKeyframe: true,
        ));
      }
      await m.finish();
      final mp4 = Uint8List.fromList(m.getBytes()!);
      await m.close();

      final dm = await MiniAVTools.createDemuxer(
        DemuxerConfig(input: DemuxerInput.bytes(mp4)),
        preference: excl,
      );
      expect(dm.backendName, 'container_framing');
      final got = <Uint8List>[];
      for (var p = await dm.readPacket(); p != null; p = await dm.readPacket()) {
        got.add(p.data);
      }
      await dm.close();
      expect(got.length, sent.length);
      for (var i = 0; i < sent.length; i++) {
        expect(got[i], sent[i], reason: 'sample $i did not round-trip');
      }
    });
  });
}
