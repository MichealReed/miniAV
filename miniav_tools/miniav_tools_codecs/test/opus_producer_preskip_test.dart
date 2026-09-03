// The PRODUCER side of Opus pre-skip: what OpusAudioEncoder actually writes
// into the OpusHead it hands downstream, and whether a file built from it plays
// back time-aligned with the audio that went in.
//
// opus_preskip_test.dart synthesises its own header, so it can only prove the
// DECODER honours a pre-skip it is given. It cannot see the encoder emitting 0.
@TestOn('vm')
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';
import 'package:miniav_tools_codecs/src/codecs_native.dart';
import 'package:miniav_tools_codecs/src/opus/opus_bitstream.dart';
import 'package:test/test.dart';

/// libopus's lookahead for an encoder at [sampleRate], asked for through a
/// SEPARATE encoder instance — independent of anything OpusAudioEncoder does.
int _nativeLookahead(int sampleRate, int channels) {
  final h = opusEncCreate(sampleRate, channels, 96000, kOpusApplicationAudio);
  final la = opusEncLookahead(h);
  opusEncDestroy(h);
  return la;
}

Future<OpusAudioEncoder> _encoder(int sampleRate, int channels) async {
  final enc = await OpusAudioEncoder.open(AudioEncoderConfig(
    codec: AudioCodec.opus,
    sampleRate: sampleRate,
    channels: channels,
    bitrateBps: 96000,
  ));
  return enc!;
}

/// A linear chirp 300 Hz → 6 kHz: unlike a pure tone its autocorrelation has a
/// single sharp peak, so a lag search cannot be fooled by periodicity.
Float32List _chirp(int frames, int channels, int sampleRate) {
  final out = Float32List(frames * channels);
  const f0 = 300.0, f1 = 6000.0;
  for (var i = 0; i < frames; i++) {
    final t = i / sampleRate;
    final dur = frames / sampleRate;
    final phase = 2 * math.pi * (f0 * t + (f1 - f0) * t * t / (2 * dur));
    final v = 0.3 * math.sin(phase);
    for (var c = 0; c < channels; c++) {
      out[i * channels + c] = v;
    }
  }
  return out;
}

Future<List<EncodedPacket>> _encodeAll(
    OpusAudioEncoder enc, Float32List pcm, int frames) async {
  return [
    ...await enc.encode(
      pcm: Uint8List.view(pcm.buffer),
      format: MiniAVAudioFormat.f32,
      frameCount: frames,
      ptsUs: 0,
    ),
    ...await enc.flush(),
  ];
}

/// Decode [pkts] with [head] as the OpusHead and return channel 0.
Future<Float32List> _decodeCh0(
    List<EncodedPacket> pkts, Uint8List head, int channels) async {
  final dec = await OpusAudioDecoder.open(AudioDecoderConfig(
    codec: AudioCodec.opus,
    sampleRate: 48000,
    channels: channels,
    extraData: head,
  ));
  final acc = <double>[];
  for (final p in pkts) {
    for (final d in await dec!.decode(p)) {
      final f = d.samples.buffer.asFloat32List(
        d.samples.offsetInBytes,
        d.samples.lengthInBytes ~/ 4,
      );
      for (var i = 0; i < d.frameCount; i++) {
        acc.add(f[i * channels]);
      }
    }
  }
  await dec!.close();
  return Float32List.fromList(acc);
}

/// Lag (in samples) of [got] relative to [want] that maximises normalised
/// correlation, searched over [-lo, hi].
int _bestLag(Float32List want, Float32List got, int lo, int hi) {
  // Skip the first 2000 samples of the reference: the chirp's lowest
  // frequencies carry the least correlation information per sample.
  const from = 2000, len = 20000;
  var best = -2.0, bestLag = 0;
  for (var lag = -lo; lag <= hi; lag++) {
    var num = 0.0, ea = 0.0, eb = 0.0;
    for (var i = 0; i < len; i++) {
      final gi = from + i + lag;
      if (gi < 0 || gi >= got.length) continue;
      final a = want[from + i], b = got[gi];
      num += a * b;
      ea += a * a;
      eb += b * b;
    }
    if (ea <= 0 || eb <= 0) continue;
    final r = num / math.sqrt(ea * eb);
    if (r > best) {
      best = r;
      bestLag = lag;
    }
  }
  return bestLag;
}

void main() {
  setUpAll(registerFirstPartyBackends);

  test('emitted OpusHead pre-skip is libopus\'s real lookahead, not 0', () async {
    final enc = await _encoder(48000, 2);
    final head = enc.extraData!.bytes;
    await enc.close();

    final lookahead = _nativeLookahead(48000, 2);
    expect(lookahead, greaterThan(0),
        reason: 'OPUS_GET_LOOKAHEAD must report a real encoder delay');
    expect(opusHeadPreSkip(head), lookahead,
        reason: 'at 48 kHz pre-skip IS the lookahead');
    expect(opusHeadPreSkip(head), isNot(0));
  });

  test('pre-skip is expressed at 48 kHz, not at the encoder rate', () async {
    // The scaling is the part a copied constant gets wrong: at 24 kHz libopus
    // reports HALF as many samples of lookahead, but the field is defined at
    // 48 kHz, so the header value must be unchanged.
    final at48 = _nativeLookahead(48000, 2);
    final at24 = _nativeLookahead(24000, 2);
    expect(at24, lessThan(at48), reason: 'lookahead is in encoder-rate samples');

    final enc = await _encoder(24000, 2);
    final head = enc.extraData!.bytes;
    await enc.close();
    expect(opusHeadPreSkip(head), at24 * 48000 ~/ 24000);
    expect(opusHeadPreSkip(head), at48);
  });

  test('decoded output aligns with the input once the pre-skip is honoured',
      () async {
    const sr = 48000, ch = 2, frames = 48000;
    final src = _chirp(frames, ch, sr);
    final enc = await _encoder(sr, ch);
    final head = enc.extraData!.bytes;
    final pkts = await _encodeAll(enc, src, frames);
    await enc.close();

    final ref = Float32List(frames);
    for (var i = 0; i < frames; i++) {
      ref[i] = src[i * ch];
    }

    final aligned = await _decodeCh0(pkts, head, ch);
    final lag = _bestLag(ref, aligned, 64, 900);
    expect(lag.abs(), lessThanOrEqualTo(8),
        reason: 'the emitted header should place output on top of input');

    // Positive control on the measurement itself: the SAME packets read with a
    // pre-skip-0 header land late by exactly the priming.
    final untrimmed = await _decodeCh0(
        pkts, buildOpusHead(ch, sr, 0), ch);
    final lagUntrimmed = _bestLag(ref, untrimmed, 64, 900);
    expect(lagUntrimmed, closeTo(opusHeadPreSkip(head), 8),
        reason: 'without the pre-skip the stream is late by the lookahead');
  });

  test('the muxers carry the encoder pre-skip through to the file', () async {
    const sr = 48000, ch = 2, frames = 9600;
    final enc = await _encoder(sr, ch);
    final head = enc.extraData!.bytes;
    final preSkip = opusHeadPreSkip(head);
    expect(preSkip, isNot(0), reason: 'nothing to carry if the encoder wrote 0');
    final pkts = await _encodeAll(enc, _chirp(frames, ch, sr), frames);
    await enc.close();

    final track = AudioTrackInfo(
      codec: AudioCodec.opus,
      sampleRate: sr,
      channels: ch,
      extraData: CodecExtraData.audio(AudioCodec.opus, head),
    );

    // Ogg: the OpusHead goes out verbatim as the BOS page.
    final ogg = OggMuxer.open(MuxerConfig(
      container: Container.ogg,
      output: MuxerOutput.bytes(),
      tracks: [track],
    ));
    await ogg.writeHeader();
    for (final p in pkts) {
      await ogg.writePacket(p);
    }
    await ogg.finish();
    final oggTrack =
        OggDemuxer.open(Uint8List.fromList(ogg.getBytes()!)).tracks.single
            as AudioTrackInfo;
    expect(opusHeadPreSkip(oggTrack.extraData!.bytes), preSkip);

    // MP4: OpusHead → dOps (big-endian PreSkip) → OpusHead on read-back.
    final mp4 = Mp4Muxer.open(MuxerConfig(
      container: Container.mp4,
      output: MuxerOutput.bytes(),
      tracks: [track],
    ));
    await mp4.writeHeader();
    for (final p in pkts) {
      await mp4.writePacket(p);
    }
    await mp4.finish();
    final mp4Bytes = Uint8List.fromList(mp4.getBytes()!);
    final mp4Track = Mp4Demuxer.open(mp4Bytes).tracks.single as AudioTrackInfo;
    expect(opusHeadPreSkip(mp4Track.extraData!.bytes), preSkip);

    // And the dOps field itself, read straight out of the bytes (BE), so this
    // does not merely re-test the demuxer's own reconstruction.
    final dops = _findBox(mp4Bytes, 'dOps');
    expect(dops, isNotNull, reason: 'audio sample entry must carry dOps');
    expect((dops![2] << 8) | dops[3], preSkip);
  });
}

/// Payload of the first box named [type], scanned flat over the file (box
/// headers are 4-byte size + 4cc, so a flat scan finds nested boxes too).
Uint8List? _findBox(Uint8List b, String type) {
  final t = type.codeUnits;
  for (var i = 0; i + 8 <= b.length; i++) {
    if (b[i + 4] == t[0] &&
        b[i + 5] == t[1] &&
        b[i + 6] == t[2] &&
        b[i + 7] == t[3]) {
      final size = (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
      if (size >= 8 && i + size <= b.length) {
        return Uint8List.sublistView(b, i + 8, i + size);
      }
    }
  }
  return null;
}
