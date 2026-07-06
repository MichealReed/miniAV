/// Byte-parity test for [GpuYuv420Converter]: the minigpu RGBA→YUV420P (BT.601
/// limited, u8) compute shader must produce output byte-identical to the legacy
/// CPU per-pixel conversion in `miniav_tools_ffmpeg` (`_rgbaToYuv420p`).
///
/// Runs the real minigpu compute path headless on the VM. Skips gracefully if a
/// GPU/Dawn device is unavailable in the environment.
@TestOn('vm')
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:miniav_recorder/miniav_recorder.dart';
import 'package:miniav_recorder/src/gpu_yuv420_converter.dart';
import 'package:test/test.dart';

/// CPU reference — copied verbatim (RGBA path) from
/// miniav_tools_ffmpeg/lib/src/pixel_convert.dart `_rgbaToYuv420p`. BT.601
/// limited, ×8192 fixed-point. If that implementation changes, update this.
({Uint8List y, Uint8List u, Uint8List v}) _cpuYuv420(
  Uint8List rgba,
  int w,
  int h,
) {
  int c255(int x) => x < 0 ? 0 : (x > 255 ? 255 : x);
  final cw = w ~/ 2;
  final ch = h ~/ 2;
  final y = Uint8List(w * h);
  final u = Uint8List(cw * ch);
  final v = Uint8List(cw * ch);
  for (var row = 0; row < h; row++) {
    for (var col = 0; col < w; col++) {
      final p = (row * w + col) * 4;
      final r = rgba[p], g = rgba[p + 1], b = rgba[p + 2];
      y[row * w + col] =
          c255((2105 * r + 4128 * g + 803 * b + (16 << 13) + 4096) >> 13);
    }
  }
  for (var row = 0; row < ch; row++) {
    for (var col = 0; col < cw; col++) {
      final p0 = (row * 2 * w + col * 2) * 4;
      final p1 = p0 + 4;
      final p2 = ((row * 2 + 1) * w + col * 2) * 4;
      final p3 = p2 + 4;
      final r = (rgba[p0] + rgba[p1] + rgba[p2] + rgba[p3]) >> 2;
      final g = (rgba[p0 + 1] + rgba[p1 + 1] + rgba[p2 + 1] + rgba[p3 + 1]) >> 2;
      final b = (rgba[p0 + 2] + rgba[p1 + 2] + rgba[p2 + 2] + rgba[p3 + 2]) >> 2;
      u[row * cw + col] =
          c255((-1212 * r - 2384 * g + 3596 * b + (128 << 13) + 4096) >> 13);
      v[row * cw + col] =
          c255((3596 * r - 3015 * g - 581 * b + (128 << 13) + 4096) >> 13);
    }
  }
  return (y: y, u: u, v: v);
}

Uint8List _syntheticRgba(int w, int h) {
  final rgba = Uint8List(w * h * 4);
  final rng = math.Random(0xA51);
  int b255(num v) => v < 0 ? 0 : (v > 255 ? 255 : v.round());
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      rgba[i + 0] = b255(x * 255 / (w - 1) + (rng.nextDouble() - 0.5) * 8);
      rgba[i + 1] = b255(y * 255 / (h - 1) + (rng.nextDouble() - 0.5) * 8);
      rgba[i + 2] = b255((x + y) * 255 / (w + h - 2) + (rng.nextDouble() - 0.5) * 8);
      rgba[i + 3] = 255;
    }
  }
  // A few pure-color 2x2 cells so chroma averaging is exercised on hard edges.
  void cell(int cx, int cy, int r, int g, int b) {
    for (var dy = 0; dy < 2; dy++) {
      for (var dx = 0; dx < 2; dx++) {
        final i = ((cy + dy) * w + cx + dx) * 4;
        rgba[i] = r;
        rgba[i + 1] = g;
        rgba[i + 2] = b;
        rgba[i + 3] = 255;
      }
    }
  }

  cell(0, 0, 255, 0, 0);
  cell(10, 10, 0, 255, 0);
  cell(20, 20, 0, 0, 255);
  cell(40, 28, 255, 255, 255);
  cell(50, 4, 16, 16, 16);
  return rgba;
}

void main() {
  group('GpuYuv420Converter (minigpu BT.601)', () {
    test('GPU YUV420P is byte-identical to the CPU reference', () async {
      await Recorder.ensureSharedGpu();
      final gpu = Recorder.sharedGpu;
      if (gpu == null) {
        markTestSkipped('No GPU/Dawn device available in this environment');
        return;
      }

      const w = 64;
      const h = 32;
      final rgba = _syntheticRgba(w, h);
      final expected = _cpuYuv420(rgba, w, h);

      final conv = GpuYuv420Converter(gpu);
      final gotY = Uint8List(GpuYuv420Converter.ySize(w, h));
      final gotU = Uint8List(GpuYuv420Converter.uvSize(w, h));
      final gotV = Uint8List(GpuYuv420Converter.uvSize(w, h));
      try {
        await conv.convertFromBytes(
          rgba,
          w,
          h,
          outY: gotY,
          outU: gotU,
          outV: gotV,
        );

        expect(gotY, equals(expected.y), reason: 'Y plane mismatch');
        expect(gotU, equals(expected.u), reason: 'U plane mismatch');
        expect(gotV, equals(expected.v), reason: 'V plane mismatch');
      } finally {
        conv.dispose();
      }
    });

    test('rejects odd dimensions', () async {
      await Recorder.ensureSharedGpu();
      final gpu = Recorder.sharedGpu;
      if (gpu == null) {
        markTestSkipped('No GPU/Dawn device available in this environment');
        return;
      }
      final conv = GpuYuv420Converter(gpu);
      addTearDown(conv.dispose);
      expect(
        () => conv.convertFromBytes(
          Uint8List(63 * 32 * 4),
          63,
          32,
          outY: Uint8List(63 * 32),
          outU: Uint8List(31 * 16),
          outV: Uint8List(31 * 16),
        ),
        throwsArgumentError,
      );
    });
  });
}
