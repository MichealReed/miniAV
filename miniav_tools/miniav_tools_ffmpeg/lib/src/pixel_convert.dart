/// CPU pixel-format helpers.
///
/// We only convert what the FFmpeg software encoder needs. For the MVP that
/// is RGBA/BGRA → YUV420P (BT.601 limited range) and a passthrough for
/// already-NV12/I420 inputs.
///
/// A real implementation would call libswscale; doing it in Dart keeps the
/// dependency surface small until we need scaling/cropping.
library;

import 'dart:typed_data';

import 'package:miniav_platform_interface/miniav_platform_types.dart';

/// Result of preparing a frame for an FFmpeg encoder.
///
/// Buffers are tightly packed in YUV420P plane order: Y (w*h), U (w*h/4),
/// V (w*h/4). [yStride], [uStride], [vStride] are equal to width, width/2,
/// width/2 respectively.
class PreparedYuv420p {
  final Uint8List y;
  final Uint8List u;
  final Uint8List v;
  final int width;
  final int height;

  const PreparedYuv420p({
    required this.y,
    required this.u,
    required this.v,
    required this.width,
    required this.height,
  });

  int get yStride => width;
  int get uStride => width ~/ 2;
  int get vStride => width ~/ 2;
}

/// Convert any supported source pixel format into tightly-packed YUV420P.
///
/// Supported sources (MVP):
///   - rgba32, bgra32 (8-bit, 4 bytes per pixel, no alpha in output)
///   - rgb24, bgr24
///   - i420 (passthrough; bytes assumed to be Y|U|V planes contiguous)
///   - nv12 (Y plane copied, UV deinterleaved)
PreparedYuv420p toYuv420p({
  required Uint8List src,
  required MiniAVPixelFormat format,
  required int width,
  required int height,
  List<int>? strides,
}) {
  if (width <= 0 || height <= 0 || width.isOdd || height.isOdd) {
    throw ArgumentError(
      'YUV420P requires even, positive dimensions; got ${width}x$height',
    );
  }

  switch (format) {
    case MiniAVPixelFormat.i420:
      return _splitI420(src, width, height);
    case MiniAVPixelFormat.nv12:
      return _nv12ToI420(src, width, height, strides);
    case MiniAVPixelFormat.yuy2:
      return _yuy2ToI420(src, width, height, strides);
    case MiniAVPixelFormat.rgba32:
      return _rgbaToYuv420p(
        src,
        width,
        height,
        srcBgrA: false,
        strides: strides,
      );
    case MiniAVPixelFormat.bgra32:
      return _rgbaToYuv420p(
        src,
        width,
        height,
        srcBgrA: true,
        strides: strides,
      );
    case MiniAVPixelFormat.rgb24:
      return _rgbToYuv420p(src, width, height, srcBgr: false);
    case MiniAVPixelFormat.bgr24:
      return _rgbToYuv420p(src, width, height, srcBgr: true);
    default:
      throw ArgumentError(
        'Unsupported source pixel format for FFmpeg encoder MVP: $format. '
        'Supported: rgba32, bgra32, rgb24, bgr24, i420, nv12. '
        'Convert via miniav_tools facade or libswscale.',
      );
  }
}

PreparedYuv420p _splitI420(Uint8List src, int w, int h) {
  final ySize = w * h;
  final cSize = (w * h) ~/ 4;
  if (src.length < ySize + 2 * cSize) {
    throw ArgumentError(
      'I420 source too small: have ${src.length}, need ${ySize + 2 * cSize}',
    );
  }
  return PreparedYuv420p(
    y: Uint8List.fromList(src.sublist(0, ySize)),
    u: Uint8List.fromList(src.sublist(ySize, ySize + cSize)),
    v: Uint8List.fromList(src.sublist(ySize + cSize, ySize + 2 * cSize)),
    width: w,
    height: h,
  );
}

PreparedYuv420p _nv12ToI420(Uint8List src, int w, int h, List<int>? strides) {
  final ySize = w * h;
  final yStride = (strides != null && strides.isNotEmpty) ? strides[0] : w;
  final uvStride = (strides != null && strides.length >= 2) ? strides[1] : w;
  // Validate enough bytes for tight or strided layout.
  final need = yStride * h + uvStride * (h ~/ 2);
  if (src.length < need) {
    throw ArgumentError(
      'NV12 source too small: have ${src.length}, '
      'need at least $need (yStride=$yStride, uvStride=$uvStride)',
    );
  }
  final y = Uint8List(ySize);
  for (var row = 0; row < h; row++) {
    y.setRange(row * w, (row + 1) * w, src, row * yStride);
  }
  final cw = w ~/ 2;
  final ch = h ~/ 2;
  final u = Uint8List(cw * ch);
  final v = Uint8List(cw * ch);
  final uvBase = yStride * h;
  for (var row = 0; row < ch; row++) {
    final srcRow = uvBase + row * uvStride;
    final dstRow = row * cw;
    for (var col = 0; col < cw; col++) {
      u[dstRow + col] = src[srcRow + col * 2];
      v[dstRow + col] = src[srcRow + col * 2 + 1];
    }
  }
  return PreparedYuv420p(y: y, u: u, v: v, width: w, height: h);
}

/// YUY2 (YUYV422) → I420. YUY2 packs 2 pixels in 4 bytes: Y0 U Y1 V.
/// Chroma is 4:2:2 horizontally; we vertically average pairs of rows to
/// produce 4:2:0.
PreparedYuv420p _yuy2ToI420(Uint8List src, int w, int h, List<int>? strides) {
  final yStride = (strides != null && strides.isNotEmpty) ? strides[0] : w * 2;
  final need = yStride * h;
  if (src.length < need) {
    throw ArgumentError(
      'YUY2 source too small: have ${src.length}, '
      'need at least $need (stride=$yStride)',
    );
  }
  final cw = w ~/ 2;
  final ch = h ~/ 2;
  final y = Uint8List(w * h);
  final u = Uint8List(cw * ch);
  final v = Uint8List(cw * ch);

  // Y plane: pick byte 0 and 2 of each YUYV quartet.
  for (var row = 0; row < h; row++) {
    final srcRow = row * yStride;
    final dstRow = row * w;
    for (var col = 0; col < cw; col++) {
      final p = srcRow + col * 4;
      y[dstRow + col * 2] = src[p];
      y[dstRow + col * 2 + 1] = src[p + 2];
    }
  }
  // U/V: average the two source rows that share a chroma row.
  for (var row = 0; row < ch; row++) {
    final srcRow0 = (row * 2) * yStride;
    final srcRow1 = (row * 2 + 1) * yStride;
    final dstRow = row * cw;
    for (var col = 0; col < cw; col++) {
      final p0 = srcRow0 + col * 4;
      final p1 = srcRow1 + col * 4;
      u[dstRow + col] = (src[p0 + 1] + src[p1 + 1] + 1) >> 1;
      v[dstRow + col] = (src[p0 + 3] + src[p1 + 3] + 1) >> 1;
    }
  }
  return PreparedYuv420p(y: y, u: u, v: v, width: w, height: h);
}

PreparedYuv420p _rgbaToYuv420p(
  Uint8List src,
  int w,
  int h, {
  required bool srcBgrA,
  List<int>? strides,
}) {
  // Source row stride in bytes. Capture APIs (DXGI, V4L2) often return
  // rows padded to an alignment > w*4. When `strides` is provided, honor
  // it; otherwise assume tightly packed.
  final srcStride = (strides != null && strides.isNotEmpty && strides[0] > 0)
      ? strides[0]
      : w * 4;
  if (src.length < srcStride * h) {
    throw ArgumentError(
      'BGRA/RGBA source too small: have ${src.length}, '
      'need ${srcStride * h} (stride=$srcStride, h=$h)',
    );
  }

  final ySize = w * h;
  final cw = w ~/ 2;
  final ch = h ~/ 2;
  final y = Uint8List(ySize);
  final u = Uint8List(cw * ch);
  final v = Uint8List(cw * ch);

  // BT.601 limited-range coefficients (×8192 for fixed-point).
  // Y =  0.257 R + 0.504 G + 0.098 B + 16
  // U = -0.148 R - 0.291 G + 0.439 B + 128
  // V =  0.439 R - 0.368 G - 0.071 B + 128
  for (var row = 0; row < h; row++) {
    final srcRow = row * srcStride;
    final dstRow = row * w;
    for (var col = 0; col < w; col++) {
      final p = srcRow + col * 4;
      final r = srcBgrA ? src[p + 2] : src[p];
      final g = src[p + 1];
      final b = srcBgrA ? src[p] : src[p + 2];
      y[dstRow +
          col] = ((2105 * r + 4128 * g + 803 * b + (16 << 13) + 4096) >> 13)
          .clamp(0, 255);
    }
  }
  // Subsample U/V (simple 2x2 average then convert).
  for (var row = 0; row < ch; row++) {
    for (var col = 0; col < cw; col++) {
      final p0 = row * 2 * srcStride + col * 2 * 4;
      final p1 = p0 + 4;
      final p2 = (row * 2 + 1) * srcStride + col * 2 * 4;
      final p3 = p2 + 4;
      final r = srcBgrA
          ? (src[p0 + 2] + src[p1 + 2] + src[p2 + 2] + src[p3 + 2]) >> 2
          : (src[p0] + src[p1] + src[p2] + src[p3]) >> 2;
      final g = (src[p0 + 1] + src[p1 + 1] + src[p2 + 1] + src[p3 + 1]) >> 2;
      final b = srcBgrA
          ? (src[p0] + src[p1] + src[p2] + src[p3]) >> 2
          : (src[p0 + 2] + src[p1 + 2] + src[p2 + 2] + src[p3 + 2]) >> 2;
      u[row * cw +
          col] = ((-1212 * r - 2384 * g + 3596 * b + (128 << 13) + 4096) >> 13)
          .clamp(0, 255);
      v[row * cw +
          col] = ((3596 * r - 3015 * g - 581 * b + (128 << 13) + 4096) >> 13)
          .clamp(0, 255);
    }
  }
  return PreparedYuv420p(y: y, u: u, v: v, width: w, height: h);
}

PreparedYuv420p _rgbToYuv420p(
  Uint8List src,
  int w,
  int h, {
  required bool srcBgr,
}) {
  // Reuse the RGBA path by widening (cheap for an MVP).
  final wide = Uint8List(w * h * 4);
  for (var i = 0, j = 0; i < w * h; i++, j += 3) {
    final base = i * 4;
    wide[base] = src[j];
    wide[base + 1] = src[j + 1];
    wide[base + 2] = src[j + 2];
    wide[base + 3] = 255;
  }
  return _rgbaToYuv420p(wide, w, h, srcBgrA: srcBgr);
}

/// Convert a decoded YUV420P plane set back into RGBA (for tests + previews).
Uint8List yuv420pToRgba({
  required Uint8List y,
  required Uint8List u,
  required Uint8List v,
  required int width,
  required int height,
  int yStride = 0,
  int uStride = 0,
  int vStride = 0,
}) {
  final ys = yStride == 0 ? width : yStride;
  final us = uStride == 0 ? width ~/ 2 : uStride;
  final vs = vStride == 0 ? width ~/ 2 : vStride;
  final out = Uint8List(width * height * 4);
  for (var row = 0; row < height; row++) {
    for (var col = 0; col < width; col++) {
      final yv = y[row * ys + col] - 16;
      final uv = u[(row >> 1) * us + (col >> 1)] - 128;
      final vv = v[(row >> 1) * vs + (col >> 1)] - 128;
      final c = 1192 * yv;
      final r = (c + 1634 * vv) >> 10;
      final g = (c - 401 * uv - 833 * vv) >> 10;
      final b = (c + 2066 * uv) >> 10;
      final p = (row * width + col) * 4;
      out[p] = r.clamp(0, 255);
      out[p + 1] = g.clamp(0, 255);
      out[p + 2] = b.clamp(0, 255);
      out[p + 3] = 255;
    }
  }
  return out;
}

/// Convert YUY2 / NV12 / I420 (or pass through RGBA/BGRA) to tightly-packed
/// BGRA32 (b, g, r, 0xff per pixel). Used by HW encoders that take a packed
/// 4-byte RGB layout (NVENC's `bgr0`, AMF, etc.) when the source is YUV.
///
/// Returns [src] unchanged when [format] is already BGRA32 — caller can
/// detect by reference-equality and skip work. RGBA32 is byte-swapped.
Uint8List toBgra32({
  required Uint8List src,
  required MiniAVPixelFormat format,
  required int width,
  required int height,
  List<int>? strides,
}) {
  switch (format) {
    case MiniAVPixelFormat.bgra32:
      return src;
    case MiniAVPixelFormat.rgba32:
      return _swapRb(src, width, height);
    case MiniAVPixelFormat.yuy2:
      return _yuy2ToBgra32(src, width, height, strides);
    case MiniAVPixelFormat.nv12:
      return _nv12ToBgra32(src, width, height, strides);
    case MiniAVPixelFormat.i420:
      return _i420ToBgra32(src, width, height);
    default:
      throw ArgumentError(
        'Unsupported source pixel format for toBgra32: $format. '
        'Supported: rgba32, bgra32, yuy2, nv12, i420.',
      );
  }
}

Uint8List _swapRb(Uint8List src, int w, int h) {
  final out = Uint8List(w * h * 4);
  for (var i = 0; i < out.length; i += 4) {
    out[i] = src[i + 2];
    out[i + 1] = src[i + 1];
    out[i + 2] = src[i];
    out[i + 3] = src[i + 3];
  }
  return out;
}

// BT.601 limited-range YUV → RGB (×8192 fixed-point).
//   R = 1.164*(Y-16)               + 1.596*(V-128)
//   G = 1.164*(Y-16) - 0.392*(U-128) - 0.813*(V-128)
//   B = 1.164*(Y-16) + 2.017*(U-128)
void _yuvToBgraPixel(int y, int u, int v, Uint8List out, int p) {
  final c = (y - 16) * 9539; // 1.164 * 8192
  final d = u - 128;
  final e = v - 128;
  final r = (c + 13074 * e + 4096) >> 13;
  final g = (c - 3210 * d - 6660 * e + 4096) >> 13;
  final b = (c + 16525 * d + 4096) >> 13;
  out[p] = b < 0 ? 0 : (b > 255 ? 255 : b);
  out[p + 1] = g < 0 ? 0 : (g > 255 ? 255 : g);
  out[p + 2] = r < 0 ? 0 : (r > 255 ? 255 : r);
  out[p + 3] = 0xff;
}

Uint8List _yuy2ToBgra32(Uint8List src, int w, int h, List<int>? strides) {
  final yStride = (strides != null && strides.isNotEmpty) ? strides[0] : w * 2;
  final out = Uint8List(w * h * 4);
  for (var row = 0; row < h; row++) {
    final srcRow = row * yStride;
    final dstRow = row * w * 4;
    for (var col = 0; col < w; col += 2) {
      final p = srcRow + col * 2;
      final y0 = src[p];
      final u = src[p + 1];
      final y1 = src[p + 2];
      final v = src[p + 3];
      _yuvToBgraPixel(y0, u, v, out, dstRow + col * 4);
      _yuvToBgraPixel(y1, u, v, out, dstRow + (col + 1) * 4);
    }
  }
  return out;
}

Uint8List _nv12ToBgra32(Uint8List src, int w, int h, List<int>? strides) {
  final yStride = (strides != null && strides.isNotEmpty) ? strides[0] : w;
  final uvStride = (strides != null && strides.length >= 2) ? strides[1] : w;
  // For miniav buffers, planes are separately allocated; for tightly packed
  // input, UV starts at `yStride * h`.
  final yPlane = src;
  final uvBase = yStride * h;
  final out = Uint8List(w * h * 4);
  for (var row = 0; row < h; row++) {
    final yRow = row * yStride;
    final uvRow = uvBase + (row ~/ 2) * uvStride;
    final dstRow = row * w * 4;
    for (var col = 0; col < w; col++) {
      final y = yPlane[yRow + col];
      final u = src[uvRow + (col & ~1)];
      final v = src[uvRow + (col & ~1) + 1];
      _yuvToBgraPixel(y, u, v, out, dstRow + col * 4);
    }
  }
  return out;
}

Uint8List _i420ToBgra32(Uint8List src, int w, int h) {
  final ySize = w * h;
  final cw = w ~/ 2;
  final cSize = cw * (h ~/ 2);
  final out = Uint8List(w * h * 4);
  for (var row = 0; row < h; row++) {
    final yRow = row * w;
    final cRow = (row ~/ 2) * cw;
    final dstRow = row * w * 4;
    for (var col = 0; col < w; col++) {
      final y = src[yRow + col];
      final u = src[ySize + cRow + (col ~/ 2)];
      final v = src[ySize + cSize + cRow + (col ~/ 2)];
      _yuvToBgraPixel(y, u, v, out, dstRow + col * 4);
    }
  }
  return out;
}
