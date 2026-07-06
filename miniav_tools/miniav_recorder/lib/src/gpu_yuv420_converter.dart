/// GPU RGBA→YUV420P (planar, u8) color conversion via minigpu.
///
/// Replaces the per-pixel Dart RGBA→YUV420P loop on the software/CPU-encode
/// fallback path. The conversion runs as a minigpu compute shader and reads
/// back the three u8 planes directly — which is ~2.7× less read-back traffic
/// than the RGBA buffer (1.5 vs 4 bytes/px) and removes the CPU per-pixel loop
/// entirely. The encoder (libx264 etc.) wants YUV420P natively, so the planes
/// feed straight into the AVFrame with no further conversion.
///
/// **Color space**: BT.601 *limited* range, using the exact same integer
/// fixed-point coefficients as the legacy CPU path
/// (`miniav_tools_ffmpeg` `_rgbaToYuv420p`) so the GPU output is byte-identical
/// and the encoded colors do not change. (The AV1 minigpu pipeline uses BT.709;
/// that path is unaffected.)
///
/// Input is packed RGBA8 (`array<u32>`, R in the low byte — the layout the
/// [GpuScreenProcessor] downscale/effects buffers already use). Width and height
/// must be even (YUV420 chroma is 2×2 subsampled).
library;

import 'dart:typed_data';

import 'package:minigpu/minigpu.dart';

const _kRgbaToYuv420Bt601Wgsl = r'''
struct Params {
  w    : u32,
  h    : u32,
  mode : u32,   // 0 = luma plane, 1 = chroma planes
  _pad : u32,
};

@group(0) @binding(0) var<storage, read_write> rgba   : array<u32>;
@group(0) @binding(1) var<storage, read_write> yOut   : array<u32>;
@group(0) @binding(2) var<storage, read_write> uOut   : array<u32>;
@group(0) @binding(3) var<storage, read_write> vOut   : array<u32>;
@group(0) @binding(4) var<storage, read_write> params : Params;

fn clamp255(v : i32) -> i32 { return clamp(v, 0, 255); }

// RGB bytes (0..255) of pixel (x,y). R is the low byte (little-endian RGBA8).
fn rgb_at(x : u32, y : u32) -> vec3<u32> {
  let p = rgba[y * params.w + x];
  return vec3<u32>(p & 0xFFu, (p >> 8u) & 0xFFu, (p >> 16u) & 0xFFu);
}

// BT.601 limited-range, ×8192 fixed-point (matches the Dart CPU reference).
fn y_of(c : vec3<u32>) -> u32 {
  let r = i32(c.x); let g = i32(c.y); let b = i32(c.z);
  return u32(clamp255((2105 * r + 4128 * g + 803 * b + 131072 + 4096) >> 13u));
}

@compute @workgroup_size(64, 1, 1)
fn main(@builtin(global_invocation_id) gid : vec3<u32>) {
  let quad = gid.x; // each invocation packs 4 output bytes into one u32

  if (params.mode == 0u) {
    // --- Luma: 4 consecutive (linear) pixels -> 4 packed Y bytes ---
    let ySize = params.w * params.h;       // bytes; always %4==0 for even w,h
    let nQuads = ySize / 4u;
    if (quad >= nQuads) { return; }
    let base = quad * 4u;
    var packed : u32 = 0u;
    for (var k = 0u; k < 4u; k = k + 1u) {
      let p = base + k;
      let x = p % params.w;
      let y = p / params.w;
      packed = packed | (y_of(rgb_at(x, y)) << (k * 8u));
    }
    yOut[quad] = packed;
  } else {
    // --- Chroma: 4 consecutive chroma samples -> packed U and V bytes ---
    let cw = params.w / 2u;
    let ch = params.h / 2u;
    let uvSize = cw * ch;
    let nQuads = (uvSize + 3u) / 4u;
    if (quad >= nQuads) { return; }
    let base = quad * 4u;
    var uPacked : u32 = 0u;
    var vPacked : u32 = 0u;
    for (var k = 0u; k < 4u; k = k + 1u) {
      let j = base + k;
      if (j >= uvSize) { continue; } // padded tail: leave byte = 0
      let cx = j % cw;
      let cy = j / cw;
      let x0 = cx * 2u;
      let y0 = cy * 2u;
      let c00 = rgb_at(x0, y0);
      let c10 = rgb_at(x0 + 1u, y0);
      let c01 = rgb_at(x0, y0 + 1u);
      let c11 = rgb_at(x0 + 1u, y0 + 1u);
      // 2x2 integer average via >>2, matching the CPU reference exactly.
      let r = i32((c00.x + c10.x + c01.x + c11.x) >> 2u);
      let g = i32((c00.y + c10.y + c01.y + c11.y) >> 2u);
      let b = i32((c00.z + c10.z + c01.z + c11.z) >> 2u);
      let uv = u32(clamp255((-1212 * r - 2384 * g + 3596 * b + 1048576 + 4096) >> 13u));
      let vv = u32(clamp255(( 3596 * r - 3015 * g -  581 * b + 1048576 + 4096) >> 13u));
      uPacked = uPacked | (uv << (k * 8u));
      vPacked = vPacked | (vv << (k * 8u));
    }
    uOut[quad] = uPacked;
    vOut[quad] = vPacked;
  }
}
''';

int _ceil4(int n) => (n + 3) & ~3;

/// Reusable GPU RGBA→YUV420P converter. One per output resolution; buffers and
/// the shader are reused across frames. Not thread-safe — drive it from a single
/// (serialized) encode path, like the rest of [GpuScreenProcessor].
class GpuYuv420Converter {
  GpuYuv420Converter(this._gpu);

  final Minigpu _gpu;

  ComputeShader? _shader;
  Buffer? _yBuf;
  Buffer? _uBuf;
  Buffer? _vBuf;
  Buffer? _paramsBuf;
  Buffer? _rgbaUpload; // only for the CPU-bytes entry point (tests / no GPU src)
  int _w = 0;
  int _h = 0;
  bool _disposed = false;

  /// Y-plane size in bytes for [width]×[height] (full resolution).
  static int ySize(int width, int height) => width * height;

  /// U or V plane size in bytes (chroma is 2×2 subsampled).
  static int uvSize(int width, int height) => (width ~/ 2) * (height ~/ 2);

  void _ensure(int w, int h) {
    assert(!_disposed, 'GpuYuv420Converter used after dispose()');
    if (w.isOdd || h.isOdd) {
      throw ArgumentError('YUV420 requires even dimensions; got ${w}x$h');
    }
    if (_shader != null && w == _w && h == _h) return;
    _disposeBuffers();
    _w = w;
    _h = h;
    final uv = uvSize(w, h);
    _shader = _gpu.createComputeShader()..loadKernelString(_kRgbaToYuv420Bt601Wgsl);
    _yBuf = _gpu.createBuffer(ySize(w, h), BufferDataType.uint8);
    _uBuf = _gpu.createBuffer(_ceil4(uv), BufferDataType.uint8);
    _vBuf = _gpu.createBuffer(_ceil4(uv), BufferDataType.uint8);
    _paramsBuf = _gpu.createBuffer(16, BufferDataType.uint8);
  }

  Future<void> _writeParams(int w, int h, int mode) {
    final data = ByteData(16)
      ..setUint32(0, w, Endian.little)
      ..setUint32(4, h, Endian.little)
      ..setUint32(8, mode, Endian.little)
      ..setUint32(12, 0, Endian.little);
    return _paramsBuf!.write(
      data.buffer.asUint8List(),
      16,
      dataType: BufferDataType.uint8,
    );
  }

  Future<void> _run(Buffer rgbaSource, int w, int h) async {
    final s = _shader!
      ..setBufferAtSlot(0, rgbaSource)
      ..setBufferAtSlot(1, _yBuf!)
      ..setBufferAtSlot(2, _uBuf!)
      ..setBufferAtSlot(3, _vBuf!)
      ..setBufferAtSlot(4, _paramsBuf!);
    const wg = 64;
    // Luma pass.
    await _writeParams(w, h, 0);
    final yQuads = ySize(w, h) ~/ 4;
    await s.dispatch((yQuads + wg - 1) ~/ wg, 1, 1);
    // Chroma pass.
    await _writeParams(w, h, 1);
    final uvQuads = (uvSize(w, h) + 3) ~/ 4;
    await s.dispatch((uvQuads + wg - 1) ~/ wg, 1, 1);
  }

  Future<void> _readback(int w, int h, Uint8List outY, Uint8List outU, Uint8List outV) async {
    await _yBuf!.read(outY, ySize(w, h), dataType: BufferDataType.uint8);
    await _uBuf!.read(outU, uvSize(w, h), dataType: BufferDataType.uint8);
    await _vBuf!.read(outV, uvSize(w, h), dataType: BufferDataType.uint8);
  }

  /// Converts a packed-RGBA8 GPU [Buffer] (the [GpuScreenProcessor] effects
  /// output) at [w]×[h] into the provided Y/U/V plane buffers — no RGBA
  /// read-back. [outY] must hold [ySize]; [outU]/[outV] must hold [uvSize].
  Future<void> convertFromGpuBuffer(
    Buffer rgbaGpu,
    int w,
    int h, {
    required Uint8List outY,
    required Uint8List outU,
    required Uint8List outV,
  }) async {
    _ensure(w, h);
    await _run(rgbaGpu, w, h);
    await _readback(w, h, outY, outU, outV);
  }

  /// Converts packed-RGBA8 CPU [rgba] bytes by uploading them first. Mainly for
  /// tests and sources that aren't already a GPU buffer.
  Future<void> convertFromBytes(
    Uint8List rgba,
    int w,
    int h, {
    required Uint8List outY,
    required Uint8List outU,
    required Uint8List outV,
  }) async {
    _ensure(w, h);
    final upload = _rgbaUpload ??= _gpu.createBuffer(
      w * h * 4,
      BufferDataType.uint8,
    );
    await upload.write(rgba, w * h * 4, dataType: BufferDataType.uint8);
    await _run(upload, w, h);
    await _readback(w, h, outY, outU, outV);
  }

  void _disposeBuffers() {
    _shader?.destroy();
    _yBuf?.destroy();
    _uBuf?.destroy();
    _vBuf?.destroy();
    _paramsBuf?.destroy();
    _rgbaUpload?.destroy();
    _shader = null;
    _yBuf = _uBuf = _vBuf = _paramsBuf = _rgbaUpload = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _disposeBuffers();
  }
}
