/// WebCodecs decode, hosted on a worker.
///
/// Runs in a real browser against a real compiled payload, because that is the
/// only place the thing under test exists — there is no `VideoDecoder` on the
/// VM, so a green VM run would prove nothing.
///
/// The premise being tested is that a decoded `VideoFrame` can be TRANSFERRED
/// out of a worker and presented on the main thread. If that did not hold, the
/// whole seam would be a frame copy per frame and not worth having, so every
/// video test here ends by reading the pixels back and comparing them to what
/// the in-process decoder produced from the same bitstream.
///
/// VP8 and Opus, not H.264 and AAC: libvpx and libopus are compiled into every
/// Chrome, while H.264/AAC ride on platform codecs that a headless CI container
/// may not have. This suite is about the transport, so it uses the codecs that
/// cannot be the reason it fails.
@TestOn('browser')
@Tags(<String>['browser'])
library;

import 'dart:math';
import 'dart:typed_data';

// Not the package barrel: it reaches native-only backends (dart:ffi) that
// cannot compile to JS. Import only the web code under test.
import 'package:miniav_tools_codecs/src/web/web_capability.dart';
import 'package:miniav_tools_codecs/src/web/web_codecs_audio_decoder.dart';
import 'package:miniav_tools_codecs/src/web/web_codecs_audio_encoder.dart';
import 'package:miniav_tools_codecs/src/web/web_codecs_decoder.dart';
import 'package:miniav_tools_codecs/src/web/web_codecs_encoder.dart';
import 'package:miniav_tools_codecs/src/web/worker_decoder.dart';
import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';
import 'package:spawn/spawn.dart';
import 'package:test/test.dart';

/// The payload, addressed relative to the test page.
///
/// Copied under test/ by the CI step rather than referenced in lib/: the test
/// runner serves the package under a random per-run prefix and only exposes the
/// test tree, so lib/ is not reachable from a browser test.
final workerEntry = SpawnEntry.split(
  codecWorkerEntryPoint,
  asset: './workers/build/codec_worker.dart.js',
);

/// Worker decode is off by default (it measured no faster than in process —
/// see `workerDecodeRequested`), so every test that wants one asks for it.
const Map<String, String> _optIn = <String, String>{'worker': 'true'};

const int _kWidth = 64;
const int _kHeight = 64;
const int _kFrames = 10;
const int _kStepUs = 33333; // ~30 fps

/// A moving gradient — enough inter-frame change that the encoder emits real
/// delta frames rather than collapsing the whole clip into one keyframe.
///
/// Deliberately gentle: the ramp shifts by one step per frame, so nothing here
/// flashes or strobes.
Uint8List _rgbaFrame(int index) {
  final bytes = Uint8List(_kWidth * _kHeight * 4);
  for (var y = 0; y < _kHeight; y++) {
    for (var x = 0; x < _kWidth; x++) {
      final o = (y * _kWidth + x) * 4;
      bytes[o] = (x * 4 + index * 3) & 0xff;
      bytes[o + 1] = (y * 4 + index * 2) & 0xff;
      bytes[o + 2] = (x + y + index) & 0xff;
      bytes[o + 3] = 0xff;
    }
  }
  return bytes;
}

/// Encodes [_kFrames] synthetic frames to VP8 and returns the bitstream.
Future<List<EncodedPacket>> _vp8Packets() async {
  final encoder = await WebCodecsVideoEncoder.create(
    const EncoderConfig(
      codec: VideoCodec.vp8,
      width: _kWidth,
      height: _kHeight,
      bitrateBps: 400000,
    ),
  );
  final packets = <EncodedPacket>[];
  for (var i = 0; i < _kFrames; i++) {
    final packet = await encoder.encode(
      FrameSource.cpu(
        bytes: _rgbaFrame(i),
        pixelFormat: MiniAVPixelFormat.rgba32,
        width: _kWidth,
        height: _kHeight,
        timestampUs: i * _kStepUs,
      ),
    );
    if (packet != null) packets.add(packet);
  }
  packets.addAll(await encoder.flush());
  await encoder.close();
  return packets;
}

/// A quiet 440 Hz sine, as interleaved f32 bytes.
Uint8List _tone(int frames, int channels, int sampleRate, int startFrame) {
  final samples = Float32List(frames * channels);
  for (var i = 0; i < frames; i++) {
    final t = (startFrame + i) / sampleRate;
    final v = 0.25 * sin(2 * pi * 440.0 * t);
    for (var c = 0; c < channels; c++) {
      samples[i * channels + c] = v;
    }
  }
  return samples.buffer.asUint8List();
}

Future<List<EncodedPacket>> _opusPackets({
  required int sampleRate,
  required int channels,
}) async {
  final encoder = await WebCodecsAudioEncoder.create(
    AudioEncoderConfig(
      codec: AudioCodec.opus,
      sampleRate: sampleRate,
      channels: channels,
      bitrateBps: 64000,
    ),
  );
  const frames = 960; // 20 ms at 48 kHz
  final packets = <EncodedPacket>[];
  for (var i = 0; i < 12; i++) {
    packets.addAll(
      await encoder.encode(
        pcm: _tone(frames, channels, sampleRate, i * frames),
        format: MiniAVAudioFormat.f32,
        frameCount: frames,
        ptsUs: i * frames * 1000000 ~/ sampleRate,
      ),
    );
  }
  packets.addAll(await encoder.flush());
  await encoder.close();
  return packets;
}

/// Runs every packet through [decoder] and drains it, closing each frame after
/// recording what it held.
Future<List<({int pts, int width, int height, List<int> rgba})>> _decodeAll(
  PlatformDecoder decoder,
  List<EncodedPacket> packets,
) async {
  final out = <({int pts, int width, int height, List<int> rgba})>[];
  Future<void> take(DecodedFrame frame) async {
    out.add((
      pts: frame.ptsUs,
      width: frame.width,
      height: frame.height,
      rgba: await frame.readBytes(),
    ));
    frame.close();
  }

  for (final packet in packets) {
    final frame = await decoder.decode(packet);
    if (frame != null) await take(frame);
  }
  for (final frame in await decoder.flush()) {
    await take(frame);
  }
  return out;
}

void main() {
  late List<EncodedPacket> vp8;

  setUpAll(() async {
    if (!WebCapability.hasVideoEncoder || !WebCapability.hasVideoDecoder) return;
    vp8 = await _vp8Packets();
  });

  group('worker-hosted video decoder', () {
    test('matches the in-process decode, pixel for pixel', () async {
      const config = DecoderConfig(
        codec: VideoCodec.vp8,
        backendOptions: _optIn,
      );

      final worker = await WorkerVideoDecoder.tryCreate(
        config,
        entry: workerEntry,
      );
      expect(
        worker,
        isNotNull,
        reason: 'the compiled payload must load; run `dart run spawn:build`',
      );
      final inProcess = await WebCodecsVideoDecoder.create(config);

      final fromWorker = await _decodeAll(worker!, vp8);
      final fromMain = await _decodeAll(inProcess, vp8);
      await worker.close();
      await inProcess.close();

      expect(
        fromWorker.length,
        fromMain.length,
        reason: 'both decoders see the same bitstream',
      );
      expect(fromWorker, isNotEmpty, reason: 'the fixture must decode');
      for (var i = 0; i < fromMain.length; i++) {
        expect(fromWorker[i].pts, fromMain[i].pts, reason: 'frame $i pts');
        expect(fromWorker[i].width, _kWidth, reason: 'frame $i width');
        expect(fromWorker[i].height, _kHeight, reason: 'frame $i height');
        // The point of the whole exercise: these pixels crossed a thread
        // boundary as a transferred handle, not as a copy.
        expect(fromWorker[i].rgba, fromMain[i].rgba, reason: 'frame $i pixels');
      }
    });

    test('a transferred frame is live, not a detached husk', () async {
      final worker = await WorkerVideoDecoder.tryCreate(
        const DecoderConfig(codec: VideoCodec.vp8, backendOptions: _optIn),
        entry: workerEntry,
      );
      addTearDown(worker!.close);

      DecodedFrame? first;
      for (final packet in vp8) {
        first = await worker.decode(packet);
        if (first != null) break;
      }
      expect(first, isNotNull, reason: 'the first packets must yield a frame');
      // A transferred-then-neutered frame reports zero dimensions and cannot
      // be copied out; a live one does both.
      expect(first!.width, _kWidth);
      expect(first.height, _kHeight);
      expect(first.webVideoFrame, isNotNull);
      expect(await first.readBytes(), hasLength(_kWidth * _kHeight * 4));
      first.close();
    });

    test('flush drains every buffered frame', () async {
      final worker = await WorkerVideoDecoder.tryCreate(
        const DecoderConfig(codec: VideoCodec.vp8, backendOptions: _optIn),
        entry: workerEntry,
      );
      addTearDown(worker!.close);

      var duringDecode = 0;
      for (final packet in vp8) {
        final frame = await worker.decode(packet);
        if (frame != null) {
          duringDecode++;
          frame.close();
        }
      }
      final drained = await worker.flush();
      for (final frame in drained) {
        frame.close();
      }
      expect(
        duringDecode + drained.length,
        vp8.length,
        reason: 'every encoded frame must come back exactly once',
      );
    });

    test('a closed decoder refuses work instead of hanging', () async {
      final worker = await WorkerVideoDecoder.tryCreate(
        const DecoderConfig(codec: VideoCodec.vp8, backendOptions: _optIn),
        entry: workerEntry,
      );
      await worker!.close();
      await expectLater(
        worker.decode(vp8.first),
        throwsA(isA<CodecRuntimeException>()),
      );
      expect(await worker.flush(), isEmpty);
      await worker.close(); // idempotent
    });

    test('a missing payload degrades to null, never to a broken player',
        () async {
      final absent = SpawnEntry.split(
        codecWorkerEntryPoint,
        asset: './workers/build/does_not_exist.dart.js',
      );
      expect(
        await WorkerVideoDecoder.tryCreate(
          const DecoderConfig(codec: VideoCodec.vp8, backendOptions: _optIn),
          entry: absent,
          timeout: const Duration(seconds: 3),
        ),
        isNull,
      );
    });

    test('a codec the browser cannot decode reports no worker', () async {
      expect(
        await WorkerVideoDecoder.tryCreate(
          // Not a WebCodecs codec at all: configure must fail in the worker
          // and be reported as "no worker", so the caller falls through to a
          // backend that can handle it rather than seeing a broken decoder.
          const DecoderConfig(codec: VideoCodec.mjpeg, backendOptions: _optIn),
          entry: workerEntry,
          timeout: const Duration(seconds: 5),
        ),
        isNull,
      );
    });

    test('decode stays in process unless asked for', () async {
      // The default. Measured neutral against in-process decode and ~63 ms
      // slower to start, so nothing gets a worker without opting in.
      expect(
        await WorkerVideoDecoder.tryCreate(
          const DecoderConfig(codec: VideoCodec.vp8),
          entry: workerEntry,
        ),
        isNull,
      );
      expect(
        await WorkerAudioDecoder.tryCreate(
          const AudioDecoderConfig(
            codec: AudioCodec.opus,
            sampleRate: 48000,
            channels: 2,
          ),
          entry: workerEntry,
        ),
        isNull,
      );
    });
  });

  group('in-process decoder', () {
    // Found by the worker port, but the bug was here all along: `decode`
    // returned an already-buffered frame BEFORE submitting the packet it was
    // handed. The caller has already taken that packet off its queue, so it was
    // gone — and a dropped packet is not one missing frame, it is every P frame
    // after it decoding against data that never arrived. It stayed hidden
    // because on the main thread the poll loop usually drained the queue before
    // the next call; the worker's separate event loop made it routine.
    test('submits every packet it is handed', () async {
      final decoder = await WebCodecsVideoDecoder.create(
        const DecoderConfig(codec: VideoCodec.vp8),
      );
      var duringDecode = 0;
      for (final packet in vp8) {
        final frame = await decoder.decode(packet);
        if (frame != null) {
          duringDecode++;
          frame.close();
        }
      }
      final drained = await decoder.flush();
      for (final frame in drained) {
        frame.close();
      }
      await decoder.close();
      expect(
        duringDecode + drained.length,
        vp8.length,
        reason: 'every encoded frame must come back exactly once',
      );
    });
  });

  group('decode waits on the callback, not on a timer', () {
    // A performance assertion, and a deliberate one: this guards an audible
    // defect, not a micro-optimisation.
    //
    // Both decoders used to wait for their output callback by polling
    // `await Future.delayed(Duration.zero)`. dart2js compiles that to
    // `setTimeout(0)`, and browsers CLAMP nested timeouts to 4 ms — so the
    // callback fired in ~0.1 ms and we did not look for another 4 ms. Measured
    // on the audio path: 5.0 ms median to decode a packet carrying 20 ms of
    // audio, a quarter of the sink's refill budget spent waiting on a timer
    // before anything else on the page competed. That is what underran the
    // audio ring and clicked.
    //
    // The bound is loose on purpose. Waiting on the callback measures ~0.1 ms
    // and the clamped-timer defect measures ~5 ms, so anything in between
    // separates them; a slow or contended runner moves both together and 2 ms
    // still catches a regression without being a flake.
    test('audio decode does not spend milliseconds per packet waiting',
        () async {
      const sampleRate = 48000;
      const channels = 2;
      final packets = await _opusPackets(
        sampleRate: sampleRate,
        channels: channels,
      );
      expect(packets.length, greaterThan(4), reason: 'need enough samples');

      final decoder = await WebCodecsAudioDecoder.create(
        const AudioDecoderConfig(
          codec: AudioCodec.opus,
          sampleRate: sampleRate,
          channels: channels,
        ),
      );
      final latencies = <double>[];
      final clock = Stopwatch();
      for (final packet in packets) {
        clock
          ..reset()
          ..start();
        await decoder.decode(packet);
        clock.stop();
        latencies.add(clock.elapsedMicroseconds / 1000.0);
      }
      await decoder.close();
      latencies.sort();
      final median = latencies[latencies.length ~/ 2];

      expect(
        median,
        lessThan(2.0),
        reason:
            'median decode took ${median.toStringAsFixed(2)} ms for a packet '
            'holding 20 ms of audio. That is the signature of waiting on a '
            'clamped setTimeout instead of the decoder output callback — it '
            'starves the audio ring and is audible.',
      );
    });
  });

  group('worker-hosted audio decoder', () {
    test('matches the in-process decode, sample for sample', () async {
      const sampleRate = 48000;
      const channels = 2;
      final packets = await _opusPackets(
        sampleRate: sampleRate,
        channels: channels,
      );
      expect(packets, isNotEmpty, reason: 'the fixture must encode');

      const config = AudioDecoderConfig(
        codec: AudioCodec.opus,
        sampleRate: sampleRate,
        channels: channels,
        backendOptions: _optIn,
      );
      final worker = await WorkerAudioDecoder.tryCreate(
        config,
        entry: workerEntry,
      );
      expect(worker, isNotNull);
      final inProcess = await WebCodecsAudioDecoder.create(config);

      Future<List<DecodedAudio>> run(PlatformAudioDecoder decoder) async {
        final out = <DecodedAudio>[];
        for (final packet in packets) {
          out.addAll(await decoder.decode(packet));
        }
        out.addAll(await decoder.flush());
        return out;
      }

      final fromWorker = await run(worker!);
      final fromMain = await run(inProcess);
      await worker.close();
      await inProcess.close();

      expect(fromWorker, isNotEmpty);
      expect(fromWorker.length, fromMain.length);
      for (var i = 0; i < fromMain.length; i++) {
        expect(fromWorker[i].ptsUs, fromMain[i].ptsUs, reason: 'chunk $i pts');
        expect(fromWorker[i].sampleRate, sampleRate, reason: 'chunk $i rate');
        expect(fromWorker[i].channels, channels, reason: 'chunk $i channels');
        expect(
          fromWorker[i].frameCount,
          fromMain[i].frameCount,
          reason: 'chunk $i frames',
        );
        expect(
          fromWorker[i].samples,
          fromMain[i].samples,
          reason: 'chunk $i samples',
        );
      }
    });
  });
}
