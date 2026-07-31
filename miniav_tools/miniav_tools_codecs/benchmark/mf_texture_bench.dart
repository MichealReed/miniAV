/// Per-frame cost of the MF zero-copy texture path (the recorder's
/// scale/effects route: foreign D3D11 texture → VideoProcessor → NV12 → MFT).
///
/// This path runs synchronously inside the capture callback, so its cost is
/// frame-pacing budget, not throughput. At 60 fps the whole frame is 16.7 ms and
/// the encoder is only one tenant of it — anything approaching a millisecond
/// here shows up to the user as stutter rather than as a slow recording.
///
/// Reports the DISTRIBUTION, not just the mean. Jitter is the symptom being
/// hunted: a path that averages 0.4 ms but spikes to 20 ms drops frames, and a
/// mean alone hides exactly that.
///
///   dart run benchmark/mf_texture_bench.dart [width] [height] [frames]
library;

import 'dart:ffi';

import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';
import 'package:miniav_tools_codecs/src/codecs_native.dart';

Future<void> main(List<String> args) async {
  final w = args.isNotEmpty ? int.parse(args[0]) : 2560;
  final h = args.length > 1 ? int.parse(args[1]) : 1440;
  final n = args.length > 2 ? int.parse(args[2]) : 600;
  // Pacing matters more than it looks. Fed flat out, this measures how fast the
  // MFT can consume — `mfenc_submit_texture` blocks for NeedInput credit, so the
  // number converges on encoder throughput and says nothing about our overhead.
  // A real recording arrives at the capture rate with the encoder mostly idle,
  // and THAT is the cost that competes with the frame budget. 0 = flat out.
  final fps = args.length > 3 ? int.parse(args[3]) : 0;

  final enc = await MfVideoEncoder.open(EncoderConfig(
    codec: VideoCodec.h264,
    width: w,
    height: h,
    bitrateBps: 12000000,
    frameRateNumerator: 60,
    frameRateDenominator: 1,
    gopLength: 120,
  ));
  if (enc == null) {
    print('MF H.264 encoder failed to open');
    return;
  }
  if (!enc.supportsD3d11Input) {
    print('no D3D11 device bound (software MFT) — nothing to measure');
    await enc.close();
    return;
  }
  print('${w}x$h  encoder="${enc.encoderName}"  hardware=${enc.isHardware}');

  // Two sources, alternated. One texture would let a cache answer every frame
  // from the same entry; the real producer cycles a shallow ring, and the point
  // is to measure that.
  final texA = mfencTestSharedBgra(w, h, 1);
  final texB = mfencTestSharedBgra(w, h, 0);
  if (texA == nullptr || texB == nullptr) {
    print('could not create shared BGRA sources');
    await enc.close();
    return;
  }

  // Time the two halves separately. `encode()` is submit-then-drain, and those
  // have completely different characters: submit is our VideoProcessor work,
  // drain is waiting on the encoder. Reporting only the total would leave it
  // ambiguous which one to optimise.
  final total = <int>[], send = <int>[];
  final sw = Stopwatch(), swSend = Stopwatch();
  var encoded = 0;
  for (var i = 0; i < n; i++) {
    final tex = i.isEven ? texA : texB;
    sw
      ..reset()
      ..start();
    swSend
      ..reset()
      ..start();
    final r = mfencSendD3d11Texture(enc.nativeHandleForTest,
        Pointer<Void>.fromAddress(tex.address), i * 16667, i == 0 ? 1 : 0);
    swSend.stop();
    if (r < 0) {
      print('send failed at frame $i');
      break;
    }
    encoded += enc.drainForTest();
    sw.stop();
    if (i >= 30) {
      total.add(sw.elapsedMicroseconds);
      send.add(swSend.elapsedMicroseconds);
    }
    if (fps > 0) {
      final slack = 1000000 ~/ fps - sw.elapsedMicroseconds;
      if (slack > 0) await Future<void>.delayed(Duration(microseconds: slack));
    }
  }
  encoded += (await enc.flush()).length;

  String dist(List<int> v) {
    final s = List.of(v)..sort();
    double at(double q) =>
        s[(s.length * q).clamp(0, s.length - 1).toInt()] / 1000.0;
    final mean = s.reduce((a, b) => a + b) / s.length / 1000.0;
    return 'mean=${mean.toStringAsFixed(3)}  '
        'p50=${at(0.5).toStringAsFixed(3)}  '
        'p95=${at(0.95).toStringAsFixed(3)}  '
        'p99=${at(0.99).toStringAsFixed(3)}  '
        'max=${(s.last / 1000.0).toStringAsFixed(3)}';
  }

  print('feed=${fps > 0 ? '$fps fps (paced)' : 'flat out'}  '
      'frames in=$n encoded=$encoded  (a large gap means dropped frames)');
  print('ms  submit (blt+VP+ProcessInput)  ${dist(send)}');
  print('ms  submit+drain (full encode)    ${dist(total)}');
  print('budget at 60 fps = 16.667 ms/frame');

  mfencTestTextureRelease(texA);
  mfencTestTextureRelease(texB);
  await enc.close();
}
