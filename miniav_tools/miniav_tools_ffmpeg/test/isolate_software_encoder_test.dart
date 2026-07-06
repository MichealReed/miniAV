/// Tests for [IsolateSoftwareEncoder] — the worker-isolate host for the
/// software encoder (the fix for the recorder's software fallback freezing
/// the UI isolate). Exercises a REAL encode on the worker: open, extraData,
/// YUV420P-plane and RGBA-bytes inputs, keyframe request, flush, close.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:miniav_tools_ffmpeg/miniav_tools_ffmpeg.dart';
import 'package:test/test.dart';

const _w = 320, _h = 240;

Uint8List _rgba(int seed) {
  final b = Uint8List(_w * _h * 4);
  for (var i = 0; i < b.length; i += 4) {
    b[i] = (i + seed) & 0xff;
    b[i + 1] = (i >> 2) & 0xff;
    b[i + 2] = seed & 0xff;
    b[i + 3] = 255;
  }
  return b;
}

void main() {
  group('IsolateSoftwareEncoder', () {
    var ready = false;
    setUpAll(() async => ready = await ensureFFmpegLoaded());

    test('encodes AV1 frames on the worker isolate (yuv + rgba inputs)', () async {
      if (!ready) {
        print('SKIP: FFmpeg not available');
        return;
      }
      final enc = await IsolateSoftwareEncoder.open(
        const EncoderConfig(
          codec: VideoCodec.av1, // SVT-AV1 is in the LGPL build
          width: _w,
          height: _h,
          bitrateBps: 1_000_000,
          frameRateNumerator: 30,
          frameRateDenominator: 1,
          bFrameCount: 0,
          backendOptions: {'preset': '12'},
        ),
      );
      try {
        expect(enc.acceptsYuv420pPlanes, isTrue);

        var packets = 0, bytes = 0;
        // RGBA input (worker does the CPU conversion — off the main isolate).
        for (var i = 0; i < 3; i++) {
          final pkt = await enc.encode(
            FrameSource.cpu(
              bytes: _rgba(i),
              pixelFormat: MiniAVPixelFormat.rgba32,
              width: _w,
              height: _h,
              timestampUs: i * 33333,
            ),
          );
          if (pkt != null) {
            packets++;
            bytes += pkt.data.length;
          }
        }
        // Pre-converted YUV planes (the recorder's GPU-YUV path).
        final cw = _w ~/ 2, ch = _h ~/ 2;
        final y = Uint8List(_w * _h)..fillRange(0, _w * _h, 90);
        final u = Uint8List(cw * ch)..fillRange(0, cw * ch, 120);
        final v = Uint8List(cw * ch)..fillRange(0, cw * ch, 140);
        await enc.requestKeyframe();
        for (var i = 3; i < 6; i++) {
          final pkt = await enc.encode(
            FrameSource.yuv420p(
              yPlane: y,
              uPlane: u,
              vPlane: v,
              width: _w,
              height: _h,
              timestampUs: i * 33333,
            ),
          );
          if (pkt != null) {
            packets++;
            bytes += pkt.data.length;
          }
        }
        for (final p in await enc.flush()) {
          packets++;
          bytes += p.data.length;
        }
        expect(
          packets,
          greaterThanOrEqualTo(6),
          reason: '6 frames in → at least 6 packets across encode+flush',
        );
        expect(bytes, greaterThan(0));
        print('isolate AV1: $packets packets, $bytes bytes');
      } finally {
        await enc.close();
      }
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('open failure surfaces as CodecInitException (invalid size)', () async {
      if (!ready) {
        print('SKIP: FFmpeg not available');
        return;
      }
      await expectLater(
        () => IsolateSoftwareEncoder.open(
          const EncoderConfig(
            codec: VideoCodec.h264,
            width: -320, // invalid — avcodec_open2 must reject it in the worker
            height: _h,
            bitrateBps: 1_000_000,
            frameRateNumerator: 30,
            frameRateDenominator: 1,
          ),
        ),
        throwsA(isA<CodecInitException>()),
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('encode after close throws', () async {
      if (!ready) {
        print('SKIP: FFmpeg not available');
        return;
      }
      final enc = await IsolateSoftwareEncoder.open(
        const EncoderConfig(
          codec: VideoCodec.av1,
          width: _w,
          height: _h,
          bitrateBps: 1_000_000,
          frameRateNumerator: 30,
          frameRateDenominator: 1,
          backendOptions: {'preset': '12'},
        ),
      );
      await enc.close();
      expect(
        () => enc.encode(
          FrameSource.cpu(
            bytes: _rgba(0),
            pixelFormat: MiniAVPixelFormat.rgba32,
            width: _w,
            height: _h,
          ),
        ),
        throwsA(isA<CodecRuntimeException>()),
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
