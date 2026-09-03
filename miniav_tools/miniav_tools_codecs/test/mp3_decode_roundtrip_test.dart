// First-party MP3 END TO END, FFmpeg-free: Mp3Demuxer frames the file and the
// dr_mp3 SwAudioDecoder turns those frames into audible PCM.
//
// The point of this file is the JOIN, not either half: the demuxer emits one
// whole frame per packet (header included), and SwAudioDecoder accumulates
// packet bytes and decodes on flush — so per-frame packets must re-concatenate
// into exactly the elementary stream dr_mp3 expects. Nothing but a real decode
// proves that.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:miniav_tools/miniav_tools.dart';
import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';
import 'package:test/test.dart';

const _asset = 'test/assets/tone.mp3';

/// All chunks' samples end to end.
Float32List _concat(List<DecodedAudio> chunks) {
  var n = 0;
  for (final c in chunks) {
    n += c.samples.length;
  }
  final out = Float32List(n);
  var o = 0;
  for (final c in chunks) {
    out.setRange(o, o + c.samples.length, c.samples);
    o += c.samples.length;
  }
  return out;
}

void main() {
  setUpAll(() {
    registerSwAudioBackend();
    registerContainerFramingBackend();
  });

  test('demuxed frames decode to audible PCM through dr_mp3', () async {
    final bytes = File(_asset).readAsBytesSync();
    final dm = Mp3Demuxer.open(bytes);
    final track = dm.tracks.single as AudioTrackInfo;
    expect(track.codec, AudioCodec.mp3);

    final dec = await SwAudioDecoder.open(
      AudioDecoderConfig(
        codec: AudioCodec.mp3,
        sampleRate: track.sampleRate,
        channels: track.channels,
      ),
    );
    expect(dec, isNotNull);

    var packets = 0;
    for (var p = await dm.readPacket(); p != null; p = await dm.readPacket()) {
      // Every packet is a complete frame: dr_mp3 re-reads the header itself, so
      // a header-stripped payload would decode to nothing here.
      expect(p.data.length, greaterThan(4));
      await dec!.decode(p);
      packets++;
    }
    expect(packets, dm.frameCount);

    final out = await dec!.flush();
    await dec.close();
    await dm.close();

    expect(out, isNotEmpty, reason: 'per-frame packets must decode');
    final pcm = out.first;
    expect(pcm.sampleRate, 48000);
    expect(pcm.channels, 2);
    // 12 frames × 1152 samples = 13824. dr_mp3 may hold back or pad a frame at
    // the edges, so this asserts the right ORDER of magnitude, not an exact
    // count the decoder never promised.
    expect(pcm.frameCount, greaterThan(12 * 1152 - 1152));
    expect(pcm.frameCount, lessThanOrEqualTo(12 * 1152 + 1152));

    var maxAbs = 0.0;
    for (final s in pcm.samples) {
      final a = s.abs();
      if (a > maxAbs) maxAbs = a;
    }
    expect(maxAbs, greaterThan(0.05), reason: 'a 440 Hz tone, not silence');
    expect(maxAbs, lessThanOrEqualTo(1.01));
  });

  test('seeking the demuxer still yields decodable frames', () async {
    final bytes = File(_asset).readAsBytesSync();
    final dm = Mp3Demuxer.open(bytes);
    await dm.seek(dm.durationUs! ~/ 2);

    final dec = await SwAudioDecoder.open(
      const AudioDecoderConfig(
        codec: AudioCodec.mp3,
        sampleRate: 48000,
        channels: 2,
      ),
    );
    var packets = 0;
    for (var p = await dm.readPacket(); p != null; p = await dm.readPacket()) {
      await dec!.decode(p);
      packets++;
    }
    expect(packets, 6, reason: 'half of 12 frames');
    final out = await dec!.flush();
    await dec.close();
    await dm.close();
    // A mid-stream start is legal input for dr_mp3 — the bit reservoir may make
    // the first frame imperfect, it does not make the stream undecodable.
    expect(out, isNotEmpty);
    expect(out.first.frameCount, greaterThan(0));
  });

  group('streaming decode (the field regression)', () {
    // The reported failure: a long mp3 played "a fraction of a second of real
    // audio then end-of-stream". The demuxer was fine — SwAudioDecoder returned
    // NOTHING from every decode() and handed the entire track back in one chunk
    // at flush(), i.e. during the player's end-of-stream drain. A player writes
    // that chunk to the sink and reports EOS in the same breath.
    //
    // tone.mp3 is only 4.6 KB of audio, under one batch, so the stream is built
    // by repeating its frames — a concatenation of whole frames is a valid mp3
    // elementary stream, and it needs no new asset and no encoder.
    Future<(Uint8List, List<EncodedPacket>)> longStream(int repeats) async {
      final bytes = File(_asset).readAsBytesSync();
      final dm = Mp3Demuxer.open(bytes);
      final frames = <Uint8List>[];
      for (var p = await dm.readPacket(); p != null; p = await dm.readPacket()) {
        frames.add(p.data);
      }
      await dm.close();
      final b = BytesBuilder();
      for (var i = 0; i < repeats; i++) {
        for (final f in frames) {
          b.add(f);
        }
      }
      final stream = b.toBytes();
      final dm2 = Mp3Demuxer.open(stream);
      final pkts = <EncodedPacket>[];
      for (var p = await dm2.readPacket();
          p != null;
          p = await dm2.readPacket()) {
        pkts.add(p);
      }
      await dm2.close();
      return (stream, pkts);
    }

    test('audio arrives DURING decode, not only at flush', () async {
      final (_, pkts) = await longStream(100);
      expect(pkts.length, 1200);

      final dec = await SwAudioDecoder.open(
        const AudioDecoderConfig(codec: AudioCodec.mp3),
      );
      var emissionsDuringDecode = 0;
      var framesDuringDecode = 0;
      final chunks = <DecodedAudio>[];
      for (final p in pkts) {
        final out = await dec!.decode(p);
        if (out.isNotEmpty) emissionsDuringDecode++;
        for (final c in out) {
          framesDuringDecode += c.frameCount;
        }
        chunks.addAll(out);
      }
      final tail = await dec!.flush();
      chunks.addAll(tail);
      await dec.close();

      expect(emissionsDuringDecode, greaterThan(1),
          reason: 'a streaming consumer must get audio before EOF — this is '
              'the field bug: every decode() returned nothing');
      expect(framesDuringDecode, greaterThan(0));

      // Exact frame accounting: no frame may be lost at a batch seam. Decoding
      // each batch cold loses its first frame to the decoder's own sync, which
      // is why a batch carries the previous one's tail and is trimmed back.
      var total = 0;
      for (final c in chunks) {
        total += c.frameCount;
        expect(c.sampleRate, 48000);
        expect(c.channels, 2);
      }
      expect(total, pkts.length * 1152,
          reason: 'every frame decodes exactly once');

      // Timestamps track the packets, not 0 for every chunk.
      expect(chunks.first.ptsUs, 0);
      for (var i = 1; i < chunks.length; i++) {
        expect(chunks[i].ptsUs, greaterThan(chunks[i - 1].ptsUs),
            reason: 'chunk $i pts must advance');
      }

      var maxAbs = 0.0;
      for (final c in chunks) {
        for (final s in c.samples) {
          final a = s.abs();
          if (a > maxAbs) maxAbs = a;
        }
      }
      expect(maxAbs, greaterThan(0.05), reason: 'audible, not silence');
    });

    test('streamed PCM is identical to a whole-file decode', () async {
      final (stream, pkts) = await longStream(40);

      final s = await SwAudioDecoder.open(
        const AudioDecoderConfig(codec: AudioCodec.mp3),
      );
      final streamed = <DecodedAudio>[];
      for (final p in pkts) {
        streamed.addAll(await s!.decode(p));
      }
      streamed.addAll(await s!.flush());
      await s.close();

      final w = await SwAudioDecoder.open(
        const AudioDecoderConfig(codec: AudioCodec.mp3),
      );
      await w!.decode(EncodedPacket(data: stream, ptsUs: 0, dtsUs: 0));
      final whole = await w.flush();
      await w.close();

      final a = _concat(streamed);
      final b = _concat(whole);
      expect(b, isNotEmpty);
      // The whole-file decode drops the frames the decoder spends syncing, so
      // the streamed output legitimately starts earlier; past that offset the
      // two must agree EXACTLY — batching may not colour the audio.
      final offset = a.length - b.length;
      expect(offset, greaterThanOrEqualTo(0),
          reason: 'streaming must not lose audio');
      var differing = 0;
      for (var i = 0; i < b.length; i++) {
        if ((a[i + offset] - b[i]).abs() > 1e-6) differing++;
      }
      expect(differing, 0,
          reason: 'batched decode must be sample-identical to a whole-file one');
    });

    test('a whole-file feed keeps its original one-shot behaviour', () async {
      // sw_audio_test and every "feed the file, then flush" caller depend on
      // this: one packet in, nothing out until flush.
      final bytes = File(_asset).readAsBytesSync();
      final dec = await SwAudioDecoder.open(
        const AudioDecoderConfig(codec: AudioCodec.mp3),
      );
      final duringDecode =
          await dec!.decode(EncodedPacket(data: bytes, ptsUs: 0, dtsUs: 0));
      expect(duringDecode, isEmpty);
      final out = await dec.flush();
      await dec.close();
      expect(out, hasLength(1));
      expect(out.first.sampleRate, 48000);
      expect(out.first.frameCount, greaterThan(8000));
    });
  });

  group('facade negotiation (FFmpeg excluded)', () {
    test('mp3 bytes are sniffed and demuxed by container_framing', () async {
      final bytes = File(_asset).readAsBytesSync();
      final dm = await MiniAVTools.createDemuxer(
        DemuxerConfig(input: DemuxerInput.bytes(bytes)), // no container hint
        preference: BackendPreference.excluded({'ffmpeg'}),
      );
      expect(dm.backendName, 'container_framing');
      final t = dm.tracks.single as AudioTrackInfo;
      expect(t.codec, AudioCodec.mp3);
      expect(t.sampleRate, 48000);
      expect(t.channels, 2);
      expect(dm.isSeekable, isTrue);
      expect(dm.durationUs, 12 * 1152 * 1000000 ~/ 48000);
      expect((await dm.readPacket())!.ptsUs, 0);
      await dm.close();
    });

    test('an explicit Container.mp3 hint routes the same way', () async {
      final bytes = File(_asset).readAsBytesSync();
      final dm = await MiniAVTools.createDemuxer(
        DemuxerConfig(
          container: Container.mp3,
          input: DemuxerInput.bytes(bytes),
        ),
        preference: BackendPreference.excluded({'ffmpeg'}),
      );
      expect(dm.backendName, 'container_framing');
      expect(dm.capability?.container, Container.mp3);
      await dm.close();
    });

    test('mp3 decode lands on sw_audio, so the whole path is FFmpeg-free',
        () async {
      final dec = await MiniAVTools.createAudioDecoder(
        const AudioDecoderConfig(codec: AudioCodec.mp3),
        preference: BackendPreference.excluded({'ffmpeg'}),
      );
      expect(dec.backendName, 'sw_audio');
      await dec.close();
    });
  });

  group('sniffing tells mp3 and AAC apart', () {
    Future<String?> sniffBackend(Uint8List bytes) async {
      final backend = ContainerFramingBackend();
      final dm = await backend.createDemuxer(
        DemuxerConfig(input: DemuxerInput.bytes(bytes)),
      );
      if (dm == null) return null;
      final kind = (dm.tracks.single as AudioTrackInfo).codec.name;
      await dm.close();
      return kind;
    }

    test('an ID3-tagged mp3 sniffs as mp3', () async {
      final bytes = File(_asset).readAsBytesSync();
      expect(bytes.sublist(0, 3), 'ID3'.codeUnits);
      expect(await sniffBackend(bytes), 'mp3');
    });

    test('ADTS bytes still sniff as AAC', () async {
      final mux = AdtsMuxer.open(
        MuxerConfig(
          container: Container.adts,
          output: MuxerOutput.bytes(),
          tracks: [
            const AudioTrackInfo(
              codec: AudioCodec.aac,
              sampleRate: 44100,
              channels: 2,
            ),
          ],
        ),
      );
      await mux.writeHeader();
      await mux.writePacket(EncodedPacket(
        data: Uint8List.fromList(List.generate(64, (i) => i & 0x7F)),
        ptsUs: 0,
        dtsUs: 0,
      ));
      final adts = Uint8List.fromList(mux.getBytes()!);
      expect(isAdtsSync(adts[0], adts[1]), isTrue);
      expect(await sniffBackend(adts), 'aac');
    });

    test('bare mp3 frames no longer open as an AAC track', () async {
      // The shipped bug: FF FB passed the loose ADTS sync test, so mp3 bytes
      // produced an AAC track that died after a packet or two.
      final bytes = File(_asset).readAsBytesSync();
      final bare = bytes.sublist(44); // strip the ID3v2 tag → starts FF FB
      expect(bare[0], 0xFF);
      expect(isMp3Sync(bare[0], bare[1]), isTrue);
      expect(isAdtsSync(bare[0], bare[1]), isFalse);
      expect(await sniffBackend(bare), 'mp3');
      expect(() => AdtsDemuxer.open(bare), throwsA(isA<CodecInitException>()));
    });
  });
}
