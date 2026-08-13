// End-to-end audio playback through `MiniavPlayer.openSource`: container bytes
// in, decoded PCM out, end-of-stream signalled.
//
// This is the seam the package had no coverage for at all. Every existing test
// here is a unit test of a helper (clock, scheduler, YUV reference, MSE probe);
// nothing opened a player, and nothing decoded a byte. The tests that DID exist
// downstack asserted which backend won a negotiation — which a backend that
// wins and then cannot decode passes perfectly.
//
// So the assertion here is deliberately starvation-shaped: real, non-silent PCM
// must reach the player's audio path BEFORE `onEnded` completes. A container
// that opens, reports a duration, routes to a plausible backend and then plays
// nothing fails.
//
// Observability: `MiniavPlayer.debugOnDecodedAudio` (see player.dart). The
// output sink's counters are NOT usable as the oracle — they are zero on a
// machine with no audio output device, and a decoder emitting digital silence
// increments them exactly like a decoder emitting a tone.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:miniav_player/miniav_player.dart';
import 'package:miniav_tools_codecs/miniav_tools_codecs.dart'
    show AdtsMuxer, Mp4Muxer, OggMuxer, WavMuxer;

const _rate = 48000;
const _channels = 2;
const _opusFrame = 960; // 20 ms @ 48 kHz

/// Shared asset dir of the codecs package (fixtures live next to the codec
/// that produces them; duplicating them here would let the two drift).
///
/// Everything in there is GENERATED (ffmpeg CLI — see the fixture step in
/// .github/workflows/dart-ci.yml) and gitignored, so a fresh clone has none of
/// it: every read must skip, not throw, or the missing fixture reads as a
/// product failure.
final _assets = File.fromUri(
  Directory.current.uri.resolve('../miniav_tools_codecs/test/assets/'),
).path;

Uint8List? _asset(String name) {
  final f = File('$_assets/$name');
  if (!f.existsSync()) {
    markTestSkipped('$name fixture absent (generate with the ffmpeg CLI — '
        'see .github/workflows/dart-ci.yml)');
    return null;
  }
  return Uint8List.fromList(f.readAsBytesSync());
}

/// Interleaved f32 sine — real audio, so "played silence" is a failure.
Float32List _sineF32(int startFrame, int frameCount, {int rate = _rate}) {
  final out = Float32List(frameCount * _channels);
  for (var i = 0; i < frameCount; i++) {
    final v = math.sin(2 * math.pi * 440.0 * (startFrame + i) / rate) * 0.4;
    for (var c = 0; c < _channels; c++) {
      out[i * _channels + c] = v;
    }
  }
  return out;
}

Int16List _sineS16(int startFrame, int frameCount) {
  final f = _sineF32(startFrame, frameCount);
  final out = Int16List(f.length);
  for (var i = 0; i < f.length; i++) {
    out[i] = (f[i] * 32000).round();
  }
  return out;
}

/// Collects decoded audio and answers the two questions the tests ask:
/// did anything audible arrive, and did it arrive before end-of-stream.
class _AudioProbe {
  int frames = 0;
  double peak = 0;
  int sampleRate = 0;
  int channels = 0;
  bool sawAudibleBeforeEnd = false;
  bool ended = false;

  void install() {
    MiniavPlayer.debugOnDecodedAudio = (chunk) {
      frames += chunk.frameCount;
      sampleRate = chunk.sampleRate;
      channels = chunk.channels;
      for (final s in chunk.samples) {
        final a = s.abs();
        if (a > peak) peak = a;
      }
      if (!ended && peak > 0.05) sawAudibleBeforeEnd = true;
    };
  }

  void remove() => MiniavPlayer.debugOnDecodedAudio = null;
}

/// 0.5 s of a 440 Hz tone as 16-bit PCM in a WAV container.
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
  const total = _rate ~/ 2;
  const block = 4800;
  for (var off = 0; off < total; off += block) {
    final pcm = _sineS16(off, block);
    await mux.writePacket(EncodedPacket(
      data: pcm.buffer.asUint8List(),
      ptsUs: (off * 1000000) ~/ _rate,
      dtsUs: (off * 1000000) ~/ _rate,
    ));
  }
  await mux.finish();
  return Uint8List.fromList(mux.getBytes()!);
}

/// 0.5 s of a real Opus-encoded tone in an Ogg container.
Future<Uint8List> _oggOpusBytes() async {
  final enc = await MiniAVTools.createAudioEncoder(const AudioEncoderConfig(
    codec: AudioCodec.opus,
    sampleRate: _rate,
    channels: _channels,
    bitrateBps: 96000,
  ));
  final packets = <EncodedPacket>[];
  for (var i = 0; i < 25; i++) {
    packets.addAll(await enc.encode(
      pcm: _sineF32(i * _opusFrame, _opusFrame).buffer.asUint8List(),
      format: MiniAVAudioFormat.f32,
      frameCount: _opusFrame,
      ptsUs: (i * _opusFrame * 1000000) ~/ _rate,
    ));
  }
  packets.addAll(await enc.flush());
  final head = enc.extraData?.bytes;
  await enc.close();

  final mux = OggMuxer.open(MuxerConfig(
    container: Container.ogg,
    output: MuxerOutput.bytes(),
    tracks: [
      AudioTrackInfo(
        codec: AudioCodec.opus,
        sampleRate: _rate,
        channels: _channels,
        extraData:
            head == null ? null : CodecExtraData.audio(AudioCodec.opus, head),
      ),
    ],
  ));
  await mux.writeHeader();
  for (final p in packets) {
    await mux.writePacket(p);
  }
  await mux.finish();
  return Uint8List.fromList(mux.getBytes()!);
}

const _aacFrames = 24;
const _aacFrameSize = 1024;

/// A real AAC-encoded tone, or null when this machine has no AAC encoder (AAC
/// encode is the OS codec — Windows only). Only "no usable AAC encoder here"
/// is caught: any other failure is a bug, and swallowing it would report a
/// broken encoder as a missing platform component.
Future<({List<EncodedPacket> packets, Uint8List asc})?> _aacPackets() async {
  final AudioEncoder enc;
  try {
    enc = await MiniAVTools.createAudioEncoder(const AudioEncoderConfig(
      codec: AudioCodec.aac,
      sampleRate: _rate,
      channels: _channels,
      bitrateBps: 128000,
    ));
  } on NoBackendForCodecException {
    return null;
  } on CodecInitException {
    return null;
  }
  final packets = <EncodedPacket>[];
  for (var i = 0; i < _aacFrames; i++) {
    packets.addAll(await enc.encode(
      pcm: _sineF32(i * _aacFrameSize, _aacFrameSize).buffer.asUint8List(),
      format: MiniAVAudioFormat.f32,
      frameCount: _aacFrameSize,
      ptsUs: (i * _aacFrameSize * 1000000) ~/ _rate,
    ));
  }
  packets.addAll(await enc.flush());
  final asc = enc.extraData?.bytes;
  await enc.close();
  // An encoder that opened and then produced nothing is a FAILURE, not a
  // platform that lacks AAC — distinguishing the two is the difference
  // between a test that stopped running and a test that could not run.
  expect(packets, isNotEmpty,
      reason: '${enc.backendName} opened an AAC encoder and emitted no packets');
  expect(asc, isNotNull,
      reason: '${enc.backendName} produced no AudioSpecificConfig');
  return (packets: packets, asc: asc!);
}

/// 0.5 s of a real AAC-encoded tone in a bare ADTS stream.
Future<Uint8List?> _adtsBytes() async {
  final aac = await _aacPackets();
  if (aac == null) return null;
  final mux = AdtsMuxer.open(MuxerConfig(
    container: Container.adts,
    output: MuxerOutput.bytes(),
    tracks: [
      AudioTrackInfo(
        codec: AudioCodec.aac,
        sampleRate: _rate,
        channels: _channels,
        extraData: CodecExtraData.audio(AudioCodec.aac, aac.asc),
      ),
    ],
  ));
  await mux.writeHeader();
  for (final p in aac.packets) {
    await mux.writePacket(p);
  }
  await mux.finish();
  return Uint8List.fromList(mux.getBytes()!);
}

/// The same tone as AAC-in-MP4 (`.m4a`).
///
/// Synthesized rather than read from `test/assets/tone.m4a`: nothing in the
/// repo generates that file (not even the CI fixture step), so the fixture —
/// and therefore the whole m4a path — existed on exactly one machine.
Future<Uint8List?> _m4aBytes() async {
  final aac = await _aacPackets();
  if (aac == null) return null;
  final mux = Mp4Muxer.open(MuxerConfig(
    container: Container.mp4,
    output: MuxerOutput.bytes(),
    tracks: [
      AudioTrackInfo(
        codec: AudioCodec.aac,
        sampleRate: _rate,
        channels: _channels,
        extraData: CodecExtraData.audio(AudioCodec.aac, aac.asc),
      ),
    ],
  ));
  await mux.writeHeader();
  for (final p in aac.packets) {
    await mux.writePacket(p);
  }
  await mux.finish();
  return Uint8List.fromList(mux.getBytes()!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The fixture builders below negotiate over the GLOBAL codec registry, which
  // nothing populates implicitly — `openSource` registers as a side effect of
  // opening a player, so without this the registry's contents depend on which
  // test ran FIRST: running one test alone (`--plain-name`) then reports the
  // machine has no AAC/Opus encoder when it does.
  setUpAll(registerPlayerBackends);

  late _AudioProbe probe;
  setUp(() {
    probe = _AudioProbe()..install();
  });
  tearDown(() => probe.remove());

  /// Open [bytes] audio-only, play to end-of-stream, assert audible PCM
  /// arrived first, then let the buffered tail finish decoding. Returns the
  /// (closed) player for extra assertions.
  ///
  /// `onEnded` fires when the DEMUXER hits EOF and the decoders are flushed —
  /// the paced audio writes behind it are still draining into the device ring,
  /// so the decoded-frame count is only complete after it settles.
  Future<MiniavPlayer> playToEnd(
    Uint8List bytes, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final errors = <Object>[];
    final player = await MiniavPlayer.openSource(
      MediaSource.bytes(bytes),
      enableVideo: false,
      onError: (e, _) => errors.add(e),
    );
    try {
      var timedOut = false;
      await player.onEnded.timeout(timeout, onTimeout: () => timedOut = true);
      probe.ended = true;
      expect(timedOut, isFalse, reason: 'onEnded never completed');
      expect(probe.frames, greaterThan(0),
          reason: '${player.audioDecoderBackend} won the negotiation and '
              'decoded no PCM at all');
      expect(probe.sawAudibleBeforeEnd, isTrue,
          reason: '${player.audioDecoderBackend} produced no audible sample '
              'before end-of-stream (peak ${probe.peak})');
      // Settle: poll until the decoded count stops growing (bounded).
      var stable = 0;
      var last = probe.frames;
      for (var i = 0; i < 400 && stable < 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        if (probe.frames == last) {
          stable++;
        } else {
          stable = 0;
          last = probe.frames;
        }
      }
      expect(errors, isEmpty, reason: 'player reported errors: $errors');
      expect(player.audioDecodeErrorCount, 0);
      // ignore: avoid_print
      print('[${player.audioDecoderBackend}] decoded=${probe.frames} '
          'written=${player.stats.audioFramesWritten} '
          'dropped=${player.stats.audioFramesDropped} '
          'duration=${player.duration}');
      // VOD playback never discards audio: `writePaced` waits for the device
      // ring instead of dropping. A non-zero count here is the shape of
      // "decoded everything at end-of-stream and dumped it at the sink".
      expect(player.stats.audioFramesDropped, 0,
          reason: 'the sink dropped '
              '${player.stats.audioFramesDropped} sample-frames');
      expect(player.stats.audioFramesWritten, greaterThan(0),
          reason: 'nothing was ever handed to the audio device');
    } finally {
      await player.close();
    }
    return player;
  }

  /// Every sample-frame the container promises must actually get decoded —
  /// the "ended after a fraction of a second" regression shape.
  void expectDecodedWholeStream(MiniavPlayer player) {
    final d = player.duration;
    expect(d, isNotNull, reason: 'container declares a duration');
    expect(probe.sampleRate, greaterThan(0));
    final expected = d!.inMicroseconds * probe.sampleRate ~/ 1000000;
    expect(probe.frames, greaterThan((expected * 0.8).round()),
        reason: 'decoded ${probe.frames} of ~$expected sample-frames — '
            'playback stopped short of the declared duration $d');
  }

  group('openSource audio-only', () {
    test('wav / 16-bit PCM plays a tone and ends', () async {
      final player = await playToEnd(await _wavBytes());
      expect(player.duration, isNotNull,
          reason: 'WAV declares its length; the player must expose it');
      expect(player.duration!.inMilliseconds, closeTo(500, 60));
      expect(probe.sampleRate, _rate);
      expect(probe.channels, _channels);
      expectDecodedWholeStream(player);
    }, timeout: const Timeout(Duration(seconds: 120)));

    test('ogg / opus plays a tone and ends', () async {
      await playToEnd(await _oggOpusBytes());
      expect(probe.sampleRate, _rate);
      expect(probe.channels, _channels);
      // Ogg's duration comes from the last page's granule position; the
      // decoded length is the load-bearing number either way.
      expect(probe.frames, greaterThan(_rate ~/ 4),
          reason: 'decoded ${probe.frames} frames of a ~0.5 s opus stream');
    }, timeout: const Timeout(Duration(seconds: 120)));

    test('mp3 plays a tone and ends', () async {
      // Where the 0.2.3 and 0.2.4 regressions both showed up: the source
      // ended almost immediately and only a fraction of the audio played.
      final mp3 = _asset('tone.mp3');
      if (mp3 == null) return;
      expectDecodedWholeStream(await playToEnd(mp3));
    }, timeout: const Timeout(Duration(seconds: 120)));

    test('m4a / aac plays a tone and ends', () async {
      final m4a = await _m4aBytes();
      if (m4a == null) {
        markTestSkipped('no AAC encoder on this platform (OS codec)');
        return;
      }
      final player = await playToEnd(m4a);
      expect(probe.sampleRate, _rate);
      expect(probe.channels, _channels);
      expectDecodedWholeStream(player);
    }, timeout: const Timeout(Duration(seconds: 120)));

    test('adts / aac plays a tone and ends', () async {
      final adts = await _adtsBytes();
      if (adts == null) {
        markTestSkipped('no AAC encoder on this platform (OS codec)');
        return;
      }
      await playToEnd(adts);
      expect(probe.sampleRate, _rate);
      // ADTS has no container duration — assert against what was encoded
      // (24 × 1024 AAC frames, minus the encoder's priming delay).
      const encoded = _aacFrames * _aacFrameSize;
      expect(probe.frames, greaterThan((encoded * 0.8).round()),
          reason: 'decoded ${probe.frames} of ~$encoded sample-frames');
    }, timeout: const Timeout(Duration(seconds: 120)));

    // A machine with no audio output device is the normal case in CI and on a
    // server, and it used to take the whole player down: opening the device
    // threw out of `_pumpAudio`, which nothing awaits — an unhandled async
    // error, once per chunk, that no `onError` callback can see.
    test('no audio output device degrades to a silent sink and still ends',
        () async {
      final wav = await _wavBytes();
      // The failure is forced at the seam the real failure comes through, so
      // the catch under test is the one that runs on a device-less machine.
      PlayerAudioOutput.debugCreateContext = () async {
        throw StateError('no audio output device (forced by test)');
      };
      addTearDown(() => PlayerAudioOutput.debugCreateContext = null);

      final errors = <Object>[];
      final unhandled = <Object>[];
      MiniavPlayer? player;
      var timedOut = false;
      final elapsed = Stopwatch()..start();
      // Assertions stay OUTSIDE the guarded zone: an `expect` failure inside
      // it would be swallowed by the same handler that is collecting the
      // errors under test, and the test would pass by never running.
      await runZonedGuarded(() async {
        player = await MiniavPlayer.openSource(
          MediaSource.bytes(wav),
          enableVideo: false,
          onError: (e, _) => errors.add(e),
        );
        await player!.onEnded.timeout(const Duration(seconds: 30),
            onTimeout: () => timedOut = true);
      }, (e, _) => unhandled.add(e));
      probe.ended = true;
      final p = player;
      // Settle the paced writes still in flight BEHIND onEnded — it waits for
      // the drain's writes, not for the packet pump's (see MiniavPlayer.
      // onEnded). This doubles as the window in which a late unhandled error
      // lands in the handler above.
      var stable = 0;
      var last = p?.stats.audioFramesWritten ?? 0;
      for (var i = 0; i < 400 && stable < 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        final now = p?.stats.audioFramesWritten ?? 0;
        if (now == last) {
          stable++;
        } else {
          stable = 0;
          last = now;
        }
      }
      elapsed.stop();

      expect(p, isNotNull, reason: 'openSource never returned a player');
      try {
        expect(unhandled, isEmpty,
            reason: 'unhandled async errors escaped the audio pump: $unhandled');
        expect(timedOut, isFalse,
            reason: 'onEnded never completed without an audio device');
        expect(p!.audioOutputUnavailable, isTrue,
            reason: 'the forced device failure did not engage the null sink');
        expect(errors, isEmpty, reason: 'player reported errors: $errors');
        expect(p.audioDecodeErrorCount, 0);
        // Decode and the sink both kept running: a null sink that refused
        // writes would stall the paced write loop instead of ending.
        expect(probe.frames, greaterThan(0), reason: 'nothing decoded');
        expect(p.stats.audioFramesDropped, 0);
        // ignore: avoid_print
        print('[null sink] elapsed=${elapsed.elapsedMilliseconds}ms '
            'decoded=${probe.frames} written=${p.stats.audioFramesWritten}');
        // Nothing was quietly swallowed: the silent sink accepted every
        // sample-frame that was decoded.
        expect(p.stats.audioFramesWritten, greaterThanOrEqualTo(probe.frames),
            reason: 'decoded ${probe.frames} sample-frames but the null sink '
                'accounted for only ${p.stats.audioFramesWritten}');
        // And it still PACES. A sink that consumed the stream instantly would
        // remove the only backpressure paced playback has, and a 0.5 s file
        // would run to completion in the time it takes to decode (~20 ms
        // measured). Lower bound only — startup and the settle loop above can
        // only push this up.
        expect(elapsed.elapsedMilliseconds, greaterThanOrEqualTo(300),
            reason: 'a 0.5 s stream finished in '
                '${elapsed.elapsedMilliseconds}ms — the silent sink is not '
                'pacing by wall clock');
      } finally {
        await p?.close();
      }
    }, timeout: const Timeout(Duration(seconds: 120)));

    // "VOD never discards audio" has to survive a pause. A whole-file decoder
    // hands the player ONE chunk holding the entire stream, and a paced write
    // that abandons the chunk it is halfway through has thrown away the only
    // copy — the packet is already dequeued and the decoder already drained.
    // The failure is silent: `onEnded` completes as if it had all played.
    test('pause mid-write holds the audio instead of discarding it', () async {
      final mp3 = _asset('tone.mp3');
      if (mp3 == null) return;
      final errors = <Object>[];
      final player = await MiniavPlayer.openSource(
        MediaSource.bytes(mp3),
        enableVideo: false,
        onError: (e, _) => errors.add(e),
      );
      try {
        // Pause the moment audio exists — a paced write of a ~0.3 s chunk
        // takes ~0.3 s of real time, so this lands mid-write. (On a machine
        // slow enough to miss the window the write has already finished and
        // the assertions below hold trivially: this can go quiet, never red.)
        for (var i = 0; i < 400 && probe.frames == 0; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(probe.frames, greaterThan(0), reason: 'nothing decoded at all');
        player.pause();
        final writtenAtPause = player.stats.audioFramesWritten;
        // Held, not stopped dead: the write keeps filling the (now un-drained)
        // device ring and then waits on it, so this count may still climb by
        // up to the ring depth. What must NOT happen is the rest of the chunk
        // being abandoned.
        await Future<void>.delayed(const Duration(milliseconds: 300));

        player.resume();
        var timedOut = false;
        await player.onEnded.timeout(const Duration(seconds: 30),
            onTimeout: () => timedOut = true);
        probe.ended = true;
        expect(timedOut, isFalse, reason: 'onEnded never completed');
        // Settle the paced writes still draining behind onEnded.
        var stable = 0;
        var last = player.stats.audioFramesWritten;
        for (var i = 0; i < 400 && stable < 4; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          if (player.stats.audioFramesWritten == last) {
            stable++;
          } else {
            stable = 0;
            last = player.stats.audioFramesWritten;
          }
        }
        // ignore: avoid_print
        print('[pause/resume] decoded=${probe.frames} '
            'writtenAtPause=$writtenAtPause '
            'written=${player.stats.audioFramesWritten}');
        if (player.stats.audioFramesWritten == 0) {
          markTestSkipped('no audio output device (nothing is ever written)');
          return;
        }
        expect(player.stats.audioFramesWritten,
            greaterThanOrEqualTo(probe.frames),
            reason: 'decoded ${probe.frames} sample-frames but only '
                '${player.stats.audioFramesWritten} reached the device — the '
                'pause discarded the rest of the chunk being written');
        expect(player.stats.audioFramesDropped, 0);
        expect(errors, isEmpty, reason: 'player reported errors: $errors');
      } finally {
        await player.close();
      }
    }, timeout: const Timeout(Duration(seconds: 120)));
  });
}
