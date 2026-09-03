/// Where the web pipeline actually spends the main thread.
///
/// Tagged `bench`: it reports numbers rather than asserting them, so it is not
/// a CI gate — a shared runner's timings would be noise. Run it by hand:
///
///     dart test -p chrome test/worker_pipeline_bench_test.dart --tags bench
///
/// The metric is deliberately NOT throughput. Throughput cannot tell you what
/// a user feels: a stage can be fast and still make playback stutter by
/// holding the main thread in chunks longer than a frame budget. So a timer
/// ticks every 2 ms throughout and records how late each tick actually fired —
/// lateness IS main-thread occupancy, measured the way jank happens.
@TestOn('browser')
@Tags(<String>['bench'])
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:miniav_tools_codecs/src/framing/container_backend.dart'
    show ContainerFramingBackend;
import 'package:miniav_tools_codecs/src/framing/mp4_container.dart'
    show Mp4Muxer;
import 'package:miniav_tools_codecs/src/framing/worker_demuxer.dart';
import 'package:miniav_tools_codecs/src/web/web_codecs_audio_decoder.dart';
import 'package:miniav_tools_codecs/src/web/web_codecs_audio_encoder.dart';
import 'package:miniav_tools_codecs/src/web/web_codecs_decoder.dart';
import 'package:miniav_tools_codecs/src/web/web_codecs_encoder.dart';
import 'package:miniav_tools_codecs/src/web/worker_decoder.dart';
import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';
import 'package:spawn/spawn.dart';
import 'package:test/test.dart';

final demuxEntry = SpawnEntry.split(
  demuxWorkerEntryPoint,
  asset: './workers/build/demux_worker.dart.js',
  protocol: registerDemuxProtocol,
);
final codecEntry = SpawnEntry.split(
  codecWorkerEntryPoint,
  asset: './workers/build/codec_worker.dart.js',
);

const int _kWidth = 640;
const int _kHeight = 480;
const int _kFrames = 120;
const int _kStepUs = 33333;

/// Measures main-thread occupancy by how long a periodic timer is kept from
/// running. Every millisecond a tick is delayed is a millisecond the main
/// thread was busy and could not have drawn.
///
/// 8 ms, and gaps measured tick-to-tick rather than against a fixed schedule,
/// for one reason worth not rediscovering: dart2js compiles `Timer.periodic`
/// to chained `setTimeout`, and browsers CLAMP nested timeouts to 4 ms. A 2 ms
/// probe therefore fires ~4 ms apart no matter how idle the page is, so
/// cumulative lateness against its nominal schedule grows at ~50% of wall time
/// and every measurement reads "50% stalled" — an artefact of the clamp, not a
/// stall. Above the clamp, and differential, the number means something.
class _MainThread {
  static const double _period = 8;

  final List<double> _gaps = <double>[];
  final Stopwatch _clock = Stopwatch();
  Timer? _timer;
  double _previous = 0;

  void start() {
    _clock.start();
    _timer = Timer.periodic(
      const Duration(milliseconds: _period ~/ 1),
      (_) {
        final now = _clock.elapsedMicroseconds / 1000.0;
        _gaps.add(now - _previous);
        _previous = now;
      },
    );
  }

  /// (total ms the main thread was blocked, worst single block ms)
  (double, double) stop() {
    _timer?.cancel();
    _clock.stop();
    var total = 0.0;
    var worst = 0.0;
    for (final gap in _gaps) {
      final blocked = gap - _period;
      if (blocked <= 0) continue;
      total += blocked;
      if (blocked > worst) worst = blocked;
    }
    return (total, worst);
  }
}

Uint8List _rgbaFrame(int index) {
  final bytes = Uint8List(_kWidth * _kHeight * 4);
  for (var y = 0; y < _kHeight; y++) {
    final row = y * _kWidth * 4;
    for (var x = 0; x < _kWidth; x++) {
      final o = row + x * 4;
      bytes[o] = (x + index) & 0xff;
      bytes[o + 1] = (y + index) & 0xff;
      bytes[o + 2] = (x + y + index) & 0xff;
      bytes[o + 3] = 0xff;
    }
  }
  return bytes;
}

Future<List<EncodedPacket>> _encode() async {
  final encoder = await WebCodecsVideoEncoder.create(
    const EncoderConfig(
      codec: VideoCodec.vp8,
      width: _kWidth,
      height: _kHeight,
      bitrateBps: 2000000,
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

/// An MP4 carrying [packets] as an audio track — the container parser does the
/// same box walking either way, and this keeps the fixture to one muxer path.
Future<Uint8List> _mp4(int packetCount) async {
  final muxer = Mp4Muxer.open(
    MuxerConfig(
      container: Container.mp4,
      output: MuxerOutput.bytes(),
      tracks: const <TrackInfo>[
        AudioTrackInfo(codec: AudioCodec.aac, sampleRate: 48000, channels: 2),
      ],
    ),
  );
  await muxer.writeHeader();
  for (var i = 0; i < packetCount; i++) {
    await muxer.writePacket(
      EncodedPacket(
        data: Uint8List.fromList(
          List<int>.generate(1024, (j) => (i + j) & 0xff),
        ),
        ptsUs: i * 21333,
        dtsUs: i * 21333,
        durationUs: 21333,
        isKeyframe: true,
      ),
    );
  }
  await muxer.finish();
  return Uint8List.fromList(muxer.getBytes()!);
}

void report(String label, int items, double wallMs, (double, double) stall) {
  // ignore: avoid_print
  print(
    '  ${label.padRight(30)} wall ${wallMs.toStringAsFixed(1).padLeft(7)} ms   '
    'main-thread stalled ${stall.$1.toStringAsFixed(1).padLeft(7)} ms '
    '(${(stall.$1 / wallMs * 100).toStringAsFixed(0).padLeft(3)}%)   '
    'worst ${stall.$2.toStringAsFixed(1).padLeft(5)} ms   '
    '${(items / wallMs * 1000).toStringAsFixed(0).padLeft(5)}/s',
  );
}

Future<(double, (double, double))> timed(Future<void> Function() body) async {
  final probe = _MainThread()..start();
  final clock = Stopwatch()..start();
  await body();
  clock.stop();
  return (clock.elapsedMicroseconds / 1000.0, probe.stop());
}

void main() {
  test('decode: worker vs in process', () async {
    final packets = await _encode();
    // ignore: avoid_print
    print('\nDECODE — $_kFrames VP8 frames at ${_kWidth}x$_kHeight');

    Future<void> run(PlatformDecoder decoder) async {
      for (final packet in packets) {
        (await decoder.decode(packet))?.close();
      }
      for (final frame in await decoder.flush()) {
        frame.close();
      }
      await decoder.close();
    }

    const config = DecoderConfig(codec: VideoCodec.vp8);
    // Worker decode is opt-in now; the bench is what decides whether it should
    // ever stop being.
    const workerConfig = DecoderConfig(
      codec: VideoCodec.vp8,
      backendOptions: <String, String>{'worker': 'true'},
    );
    final direct = await WebCodecsVideoDecoder.create(config);
    final inProc = await timed(() => run(direct));
    report('in process', packets.length, inProc.$1, inProc.$2);

    final worker = await WorkerVideoDecoder.tryCreate(
      workerConfig,
      entry: codecEntry,
    );
    final onWorker = await timed(() => run(worker!));
    report('on a worker', packets.length, onWorker.$1, onWorker.$2);
  });

  test('demux: worker vs in process', () async {
    // Big enough that the in-process path runs for long enough to sample: at
    // ~130k packets/s a few hundred packets finish inside a single probe tick.
    const count = 4000;
    final bytes = await _mp4(count);
    // ignore: avoid_print
    print('\nDEMUX — $count packets from a ${bytes.length ~/ 1024} kB MP4');

    Future<void> drain(PlatformDemuxer demuxer) async {
      while (await demuxer.readPacket() != null) {}
      await demuxer.close();
    }

    final inProc = await timed(
      () => drain(
        ContainerFramingBackend.openInProcess(
          Uint8List.fromList(bytes),
          null,
        )!,
      ),
    );
    report('in process', count, inProc.$1, inProc.$2);

    final worker = await WorkerDemuxer.tryOpen(
      Uint8List.fromList(bytes),
      entry: demuxEntry,
    );
    final onWorker = await timed(() => drain(worker!));
    report('on a worker', count, onWorker.$1, onWorker.$2);
  });

  // Audio is where a stall is AUDIBLE. Video drops a frame; audio underruns the
  // sink's ring and clicks. The ring is refilled from the main thread (the
  // AudioContext is main-only), so what matters is not throughput but the
  // LATENCY of one decode call — if refilling a 20 ms chunk regularly takes
  // longer than 20 ms, the ring drains no matter how fast the decoder is.
  test('audio decode latency, per call', () async {
    const sampleRate = 48000;
    const channels = 2;
    final encoder = await WebCodecsAudioEncoder.create(
      const AudioEncoderConfig(
        codec: AudioCodec.opus,
        sampleRate: sampleRate,
        channels: channels,
        bitrateBps: 64000,
      ),
    );
    const frames = 960; // 20 ms
    final packets = <EncodedPacket>[];
    for (var i = 0; i < 200; i++) {
      final samples = Float32List(frames * channels);
      for (var s = 0; s < samples.length; s++) {
        samples[s] = 0.2 * ((s % 96) / 96 - 0.5);
      }
      packets.addAll(
        await encoder.encode(
          pcm: samples.buffer.asUint8List(),
          format: MiniAVAudioFormat.f32,
          frameCount: frames,
          ptsUs: i * frames * 1000000 ~/ sampleRate,
        ),
      );
    }
    packets.addAll(await encoder.flush());
    await encoder.close();

    // ignore: avoid_print
    print(
      '\nAUDIO DECODE LATENCY — ${packets.length} Opus packets, '
      '20 ms of audio each (so >20 ms per call drains the sink)',
    );

    final decoder = await WebCodecsAudioDecoder.create(
      const AudioDecoderConfig(
        codec: AudioCodec.opus,
        sampleRate: sampleRate,
        channels: channels,
      ),
    );
    final latencies = <double>[];
    final clock = Stopwatch();
    var chunks = 0;
    for (final packet in packets) {
      clock
        ..reset()
        ..start();
      chunks += (await decoder.decode(packet)).length;
      clock.stop();
      latencies.add(clock.elapsedMicroseconds / 1000.0);
    }
    await decoder.close();
    latencies.sort();

    double at(double q) {
      final i = (latencies.length * q).floor();
      return latencies[i < 0 ? 0 : (i >= latencies.length ? latencies.length - 1 : i)];
    }
    // ignore: avoid_print
    print(
      '  in process   p50 ${at(0.5).toStringAsFixed(2)} ms   '
      'p95 ${at(0.95).toStringAsFixed(2)} ms   '
      'max ${latencies.last.toStringAsFixed(2)} ms   '
      'total ${latencies.reduce((a, b) => a + b).toStringAsFixed(0)} ms '
      'for ${(packets.length * 20 / 1000).toStringAsFixed(1)} s of audio '
      '($chunks chunks)',
    );
  });

  // The case the whole plan was written for, and the one an idle page cannot
  // show: decode WHILE the main thread is busy. In process, the decoder's
  // bridge waits for its output callback by yielding the event loop — and a
  // yield on a contended thread goes to the back of the queue behind whatever
  // Flutter is building. On a worker it waits on an idle thread. If moving
  // decode is worth anything, it is worth it here.
  test('decode under main-thread load: worker vs in process', () async {
    final packets = await _encode();
    // ignore: avoid_print
    print('\nDECODE UNDER LOAD — a 16 ms cadence burning ~8 ms of main thread');

    // Stands in for Flutter's build+raster: a real computation (so it cannot
    // be optimised away) occupying the main thread in frame-sized chunks.
    Timer? load;
    void startLoad() {
      load = Timer.periodic(const Duration(milliseconds: 16), (_) {
        final until = Stopwatch()..start();
        var sink = 0.0;
        while (until.elapsedMicroseconds < 8000) {
          for (var i = 0; i < 2000; i++) {
            sink += i * 1.000001;
          }
        }
        if (sink < 0) throw StateError('unreachable');
      });
    }

    Future<void> run(PlatformDecoder decoder) async {
      for (final packet in packets) {
        (await decoder.decode(packet))?.close();
      }
      for (final frame in await decoder.flush()) {
        frame.close();
      }
      await decoder.close();
    }

    const config = DecoderConfig(codec: VideoCodec.vp8);
    // Worker decode is opt-in now; the bench is what decides whether it should
    // ever stop being.
    const workerConfig = DecoderConfig(
      codec: VideoCodec.vp8,
      backendOptions: <String, String>{'worker': 'true'},
    );
    final direct = await WebCodecsVideoDecoder.create(config);
    startLoad();
    final inProc = await timed(() => run(direct));
    load?.cancel();
    report('in process', packets.length, inProc.$1, inProc.$2);

    final worker = await WorkerVideoDecoder.tryCreate(
      workerConfig,
      entry: codecEntry,
    );
    startLoad();
    final onWorker = await timed(() => run(worker!));
    load?.cancel();
    report('on a worker', packets.length, onWorker.$1, onWorker.$2);
  });

  // Reading a packet is a table lookup; PARSING the tables is the work, and it
  // happens once, in one uninterruptible chunk. If the demux worker earns its
  // keep anywhere it is here — so measure open on its own, at a sample count a
  // real long file would have.
  test('demux open: worker vs in process', () async {
    // ignore: avoid_print
    print('\nDEMUX OPEN — the moov/stbl parse, by sample count');
    for (final count in <int>[2000, 20000]) {
      final bytes = await _mp4(count);

      final inProc = await timed(() async {
        ContainerFramingBackend.openInProcess(
          Uint8List.fromList(bytes),
          null,
        )!.close();
      });
      report('in process ($count samples)', 1, inProc.$1, inProc.$2);

      final onWorker = await timed(() async {
        final w = await WorkerDemuxer.tryOpen(
          Uint8List.fromList(bytes),
          entry: demuxEntry,
        );
        await w!.close();
      });
      report('on a worker ($count samples)', 1, onWorker.$1, onWorker.$2);
    }
  });
}
