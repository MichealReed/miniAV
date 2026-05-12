/// GPU screen frame processor: optional bilinear downscale + chained effects.
///
/// Handles all per-frame GPU work for a screen source in the zero-copy
/// pipeline:
///
/// ```
/// MiniAVBuffer (D3D11 NT handle)
///   -> importVideoFrame()         VideoTexture  BGRA, srcW x srcH
///   -> VideoTexture.toRGBA()      Buffer        RGBA u32[], srcW x srcH
///   -> [bilinear downscale]       Buffer        RGBA u32[], dstW x dstH  (optional)
///   -> effect[0].apply()          Buffer        RGBA u32[], w0 x h0      (may change dims)
///   -> effect[n].apply()          ...
///   -> SharedOutputTexture.copyFromBuffer
///                                 SharedOutputTexture (RGBA, outputW x outputH)
///   -> D3D11TextureFrameSource -> FfmpegD3d11HwEncoder (zero-copy)
/// ```
library;

import 'dart:ffi' show Pointer;
import 'dart:io';
import 'dart:typed_data';

import 'package:miniav_tools_ffmpeg/miniav_tools_ffmpeg.dart';
import 'package:minigpu/minigpu.dart';

import 'screen_effect.dart';

// ---------------------------------------------------------------------------
// WGSL bilinear downscale kernel
// ---------------------------------------------------------------------------

const _kDownscaleWgsl = r'''
struct Params {
  srcW     : u32,
  srcH     : u32,
  dstW     : u32,
  dstH     : u32,
};

@group(0) @binding(0) var<storage, read_write> src    : array<u32>;
@group(0) @binding(1) var<storage, read_write> dst    : array<u32>;
@group(0) @binding(2) var<storage, read_write> params : Params;

fn unpack_rgba(p : u32) -> vec4<f32> {
  return vec4<f32>(
    f32( p        & 0xFFu),
    f32((p >>  8u) & 0xFFu),
    f32((p >> 16u) & 0xFFu),
    f32((p >> 24u) & 0xFFu),
  ) / 255.0;
}

fn pack_rgba(c : vec4<f32>) -> u32 {
  let q = clamp(c, vec4<f32>(0.0), vec4<f32>(1.0)) * 255.0 + vec4<f32>(0.5);
  return  u32(q.x)
       | (u32(q.y) <<  8u)
       | (u32(q.z) << 16u)
       | (u32(q.w) << 24u);
}

fn read_src(x : u32, y : u32) -> vec4<f32> {
  let xx = clamp(x, 0u, params.srcW - 1u);
  let yy = clamp(y, 0u, params.srcH - 1u);
  return unpack_rgba(src[yy * params.srcW + xx]);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid : vec3<u32>) {
  if (gid.x >= params.dstW || gid.y >= params.dstH) { return; }

  let scaleX = f32(params.srcW) / f32(params.dstW);
  let scaleY = f32(params.srcH) / f32(params.dstH);
  let sx = (f32(gid.x) + 0.5) * scaleX - 0.5;
  let sy = (f32(gid.y) + 0.5) * scaleY - 0.5;

  let x0 = u32(max(i32(sx), 0));
  let y0 = u32(max(i32(sy), 0));
  let x1 = min(x0 + 1u, params.srcW - 1u);
  let y1 = min(y0 + 1u, params.srcH - 1u);

  let tx = fract(sx);
  let ty = fract(sy);

  let c = mix(mix(read_src(x0, y0), read_src(x1, y0), tx),
              mix(read_src(x0, y1), read_src(x1, y1), tx), ty);
  dst[gid.y * params.dstW + gid.x] = pack_rgba(c);
}
''';

// ---------------------------------------------------------------------------
// WGSL crop kernel
// ---------------------------------------------------------------------------
// Reads a sub-rectangle from src (srcW×srcH) and writes it to dst (dstW×dstH).
// dstW = cropWidth, dstH = cropHeight.
const _kCropWgsl = r'''
struct Params {
  srcW  : u32,
  srcH  : u32,
  dstW  : u32,
  dstH  : u32,
  cropX : u32,
  cropY : u32,
  _p0   : u32,
  _p1   : u32,
};

@group(0) @binding(0) var<storage, read_write> src    : array<u32>;
@group(0) @binding(1) var<storage, read_write> dst    : array<u32>;
@group(0) @binding(2) var<storage, read_write> params : Params;

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid : vec3<u32>) {
  if (gid.x >= params.dstW || gid.y >= params.dstH) { return; }
  let srcX = clamp(gid.x + params.cropX, 0u, params.srcW - 1u);
  let srcY = clamp(gid.y + params.cropY, 0u, params.srcH - 1u);
  dst[gid.y * params.dstW + gid.x] = src[srcY * params.srcW + srcX];
}
''';

// ---------------------------------------------------------------------------
// WGSL flip kernel
// ---------------------------------------------------------------------------
// Mirrors src into dst (same dimensions).  Separate buffers avoid the
// in-place race condition that would occur if threads operated on shared pixels.
const _kFlipWgsl = r'''
struct Params {
  srcW  : u32,
  srcH  : u32,
  flipH : u32,   // 1 = mirror horizontally
  flipV : u32,   // 1 = mirror vertically
};

@group(0) @binding(0) var<storage, read_write> src    : array<u32>;
@group(0) @binding(1) var<storage, read_write> dst    : array<u32>;
@group(0) @binding(2) var<storage, read_write> params : Params;

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid : vec3<u32>) {
  if (gid.x >= params.srcW || gid.y >= params.srcH) { return; }
  let srcX = select(gid.x, params.srcW - 1u - gid.x, params.flipH != 0u);
  let srcY = select(gid.y, params.srcH - 1u - gid.y, params.flipV != 0u);
  dst[gid.y * params.srcW + gid.x] = src[srcY * params.srcW + srcX];
}
''';

// ---------------------------------------------------------------------------
// WGSL rotate kernel
// ---------------------------------------------------------------------------
// rotation codes: 1 = 90° CW, 2 = 180°, 3 = 270° CW.
// For 90° / 270°: dstW = srcH, dstH = srcW.
// For 180°:       dstW = srcW, dstH = srcH.
const _kRotateWgsl = r'''
struct Params {
  srcW     : u32,
  srcH     : u32,
  dstW     : u32,
  dstH     : u32,
  rotation : u32,   // 1=90°CW, 2=180°, 3=270°CW
  _p0      : u32,
  _p1      : u32,
  _p2      : u32,
};

@group(0) @binding(0) var<storage, read_write> src    : array<u32>;
@group(0) @binding(1) var<storage, read_write> dst    : array<u32>;
@group(0) @binding(2) var<storage, read_write> params : Params;

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid : vec3<u32>) {
  if (gid.x >= params.dstW || gid.y >= params.dstH) { return; }
  var srcX : u32;
  var srcY : u32;
  if (params.rotation == 1u) {
    // 90° CW: dest(x,y) ← src(y, srcH-1-x)
    srcX = gid.y;
    srcY = params.srcH - 1u - gid.x;
  } else if (params.rotation == 2u) {
    // 180°: dest(x,y) ← src(srcW-1-x, srcH-1-y)
    srcX = params.srcW - 1u - gid.x;
    srcY = params.srcH - 1u - gid.y;
  } else {
    // 270° CW: dest(x,y) ← src(srcW-1-y, x)
    srcX = params.srcW - 1u - gid.y;
    srcY = gid.x;
  }
  dst[gid.y * params.dstW + gid.x] = src[srcY * params.srcW + srcX];
}
''';

// ---------------------------------------------------------------------------
// Abstract effect runtime base
// ---------------------------------------------------------------------------

abstract class _EffectRuntime {
  /// Apply the effect.
  ///
  /// [inBuf] is the current RGBA8 pixel buffer at [inW]×[inH].
  /// In-place effects modify [inBuf] directly. Transform effects write to
  /// their own output buffer; call [outBuf] to get it.
  Future<void> apply(Buffer inBuf, int inW, int inH);

  /// For transform effects: the persistent output buffer (at [outW]×[outH]).
  /// Returns `null` for in-place effects.
  Buffer? get outBuf;
  int? get outW;
  int? get outH;

  void dispose();
}

// ---------------------------------------------------------------------------
// Internal per-effect GPU runtime (in-place WGSL)
// ---------------------------------------------------------------------------

/// Owns the [ComputeShader] + params [Buffer] for one [WgslScreenEffect].
/// Created lazily; reuses params buffer across frames unless dimensions change.
class _GpuEffectRuntime extends _EffectRuntime {
  _GpuEffectRuntime(this._gpu, this._descriptor);

  final Minigpu _gpu;
  final WgslScreenEffect _descriptor;

  ComputeShader? _shader;
  Buffer? _paramsBuf;
  int _lastW = -1;
  int _lastH = -1;

  @override
  Buffer? get outBuf => null; // in-place
  @override
  int? get outW => null;
  @override
  int? get outH => null;

  @override
  Future<void> apply(Buffer pixels, int width, int height) async {
    _shader ??= _gpu.createComputeShader()
      ..loadKernelString(_descriptor.wgslSource);

    if (_paramsBuf == null || _lastW != width || _lastH != height) {
      _paramsBuf?.destroy();
      final extras = _descriptor.extraParams;
      // Layout: width(u32) + height(u32) + extraParams(f32 each).
      // Pad to a multiple of 16 bytes for std140 alignment.
      final fieldCount = 2 + extras.length;
      final paddedFields = ((fieldCount + 3) ~/ 4) * 4;
      final byteCount = paddedFields * 4;
      final view = ByteData(byteCount);
      view.setUint32(0, width, Endian.little);
      view.setUint32(4, height, Endian.little);
      for (var i = 0; i < extras.length; i++) {
        view.setFloat32(8 + i * 4, extras[i], Endian.little);
      }
      final buf = _gpu.createBuffer(byteCount, BufferDataType.uint8);
      await buf.write(
        view.buffer.asUint8List(),
        byteCount,
        dataType: BufferDataType.uint8,
      );
      _paramsBuf = buf;
      _lastW = width;
      _lastH = height;
    }

    _shader!.setBufferAtSlot(0, pixels);
    _shader!.setBufferAtSlot(1, _paramsBuf!);

    const kGroup = 8;
    await _shader!.dispatch(
      (width + kGroup - 1) ~/ kGroup,
      (height + kGroup - 1) ~/ kGroup,
      1,
    );
  }

  @override
  void dispose() {
    try {
      _shader?.destroy();
    } catch (_) {}
    try {
      _paramsBuf?.destroy();
    } catch (_) {}
    _shader = null;
    _paramsBuf = null;
  }
}

// ---------------------------------------------------------------------------
// Crop effect runtime (transform: separate src → dst buffers)
// ---------------------------------------------------------------------------

/// GPU runtime for [CropScreenEffect]. Reads a sub-rectangle from the input
/// buffer and writes it to a persistent output buffer at the crop dimensions.
class _CropEffectRuntime extends _EffectRuntime {
  _CropEffectRuntime(this._gpu, this._desc, this._inW, this._inH);

  final Minigpu _gpu;
  final CropScreenEffect _desc;
  final int _inW;
  final int _inH;

  ComputeShader? _shader;
  Buffer? _paramsBuf;
  Buffer? _outBuf;

  @override
  Buffer? get outBuf => _outBuf;
  @override
  int? get outW => _desc.cropWidth;
  @override
  int? get outH => _desc.cropHeight;

  Future<void> init() async {
    assert(
      _desc.cropX + _desc.cropWidth <= _inW &&
          _desc.cropY + _desc.cropHeight <= _inH,
      'ScreenEffect.crop(${_desc.cropX}, ${_desc.cropY}, '
      '${_desc.cropWidth}, ${_desc.cropHeight}) '
      'falls outside the ${_inW}x${_inH} source frame.',
    );

    _shader = _gpu.createComputeShader()..loadKernelString(_kCropWgsl);

    // Params: srcW, srcH, dstW, dstH, cropX, cropY, _pad0, _pad1 (8×u32 = 32 bytes).
    final view = ByteData(32)
      ..setUint32(0, _inW, Endian.little)
      ..setUint32(4, _inH, Endian.little)
      ..setUint32(8, _desc.cropWidth, Endian.little)
      ..setUint32(12, _desc.cropHeight, Endian.little)
      ..setUint32(16, _desc.cropX, Endian.little)
      ..setUint32(20, _desc.cropY, Endian.little);
    _paramsBuf = _gpu.createBuffer(32, BufferDataType.uint8);
    await _paramsBuf!.write(
      view.buffer.asUint8List(),
      32,
      dataType: BufferDataType.uint8,
    );

    _outBuf = _gpu.createBuffer(
      _desc.cropWidth * _desc.cropHeight * 4,
      BufferDataType.uint8,
    );
  }

  @override
  Future<void> apply(Buffer inBuf, int inW, int inH) async {
    _shader!
      ..setBufferAtSlot(0, inBuf)
      ..setBufferAtSlot(1, _outBuf!)
      ..setBufferAtSlot(2, _paramsBuf!);
    const kGroup = 8;
    await _shader!.dispatch(
      (_desc.cropWidth + kGroup - 1) ~/ kGroup,
      (_desc.cropHeight + kGroup - 1) ~/ kGroup,
      1,
    );
  }

  @override
  void dispose() {
    try {
      _shader?.destroy();
    } catch (_) {}
    try {
      _paramsBuf?.destroy();
    } catch (_) {}
    try {
      _outBuf?.destroy();
    } catch (_) {}
    _shader = null;
    _paramsBuf = null;
    _outBuf = null;
  }
}

// ---------------------------------------------------------------------------
// Flip effect runtime (transform: separate src → dst, same dimensions)
// ---------------------------------------------------------------------------

/// GPU runtime for [FlipScreenEffect]. Mirrors into a persistent output buffer
/// to avoid the race condition that would occur with an in-place shader.
class _FlipEffectRuntime extends _EffectRuntime {
  _FlipEffectRuntime(this._gpu, this._desc, this._inW, this._inH);

  final Minigpu _gpu;
  final FlipScreenEffect _desc;
  final int _inW;
  final int _inH;

  ComputeShader? _shader;
  Buffer? _paramsBuf;
  Buffer? _outBuf;

  @override
  Buffer? get outBuf => _outBuf;
  @override
  int? get outW => _inW; // same dims
  @override
  int? get outH => _inH;

  Future<void> init() async {
    _shader = _gpu.createComputeShader()..loadKernelString(_kFlipWgsl);

    // Params: srcW, srcH, flipH (0/1), flipV (0/1) — 4×u32 = 16 bytes.
    final view = ByteData(16)
      ..setUint32(0, _inW, Endian.little)
      ..setUint32(4, _inH, Endian.little)
      ..setUint32(8, _desc.horizontal ? 1 : 0, Endian.little)
      ..setUint32(12, _desc.vertical ? 1 : 0, Endian.little);
    _paramsBuf = _gpu.createBuffer(16, BufferDataType.uint8);
    await _paramsBuf!.write(
      view.buffer.asUint8List(),
      16,
      dataType: BufferDataType.uint8,
    );

    _outBuf = _gpu.createBuffer(_inW * _inH * 4, BufferDataType.uint8);
  }

  @override
  Future<void> apply(Buffer inBuf, int inW, int inH) async {
    _shader!
      ..setBufferAtSlot(0, inBuf)
      ..setBufferAtSlot(1, _outBuf!)
      ..setBufferAtSlot(2, _paramsBuf!);
    const kGroup = 8;
    await _shader!.dispatch(
      (_inW + kGroup - 1) ~/ kGroup,
      (_inH + kGroup - 1) ~/ kGroup,
      1,
    );
  }

  @override
  void dispose() {
    try {
      _shader?.destroy();
    } catch (_) {}
    try {
      _paramsBuf?.destroy();
    } catch (_) {}
    try {
      _outBuf?.destroy();
    } catch (_) {}
    _shader = null;
    _paramsBuf = null;
    _outBuf = null;
  }
}

// ---------------------------------------------------------------------------
// Rotate effect runtime (transform: separate src → dst, may change dimensions)
// ---------------------------------------------------------------------------

/// GPU runtime for [RotateScreenEffect]. Rotates into a persistent output
/// buffer. 90°/270° rotations produce a buffer with swapped dimensions.
class _RotateEffectRuntime extends _EffectRuntime {
  _RotateEffectRuntime(this._gpu, this._desc, int inW, int inH)
    : _inW = inW,
      _inH = inH {
    final (w, h) = _desc.outputSize(inW, inH);
    _outWidth = w;
    _outHeight = h;
  }

  final Minigpu _gpu;
  final RotateScreenEffect _desc;
  final int _inW;
  final int _inH;

  late final int _outWidth;
  late final int _outHeight;

  ComputeShader? _shader;
  Buffer? _paramsBuf;
  Buffer? _outBuf;

  @override
  Buffer? get outBuf => _outBuf;
  @override
  int? get outW => _outWidth;
  @override
  int? get outH => _outHeight;

  Future<void> init() async {
    _shader = _gpu.createComputeShader()..loadKernelString(_kRotateWgsl);

    // rotation encoding: r90=1, r180=2, r270=3
    final rotCode = switch (_desc.rotation) {
      ScreenRotation.r90 => 1,
      ScreenRotation.r180 => 2,
      ScreenRotation.r270 => 3,
    };

    // Params: srcW, srcH, dstW, dstH, rotation, _p0, _p1, _p2 — 8×u32 = 32 bytes.
    final view = ByteData(32)
      ..setUint32(0, _inW, Endian.little)
      ..setUint32(4, _inH, Endian.little)
      ..setUint32(8, _outWidth, Endian.little)
      ..setUint32(12, _outHeight, Endian.little)
      ..setUint32(16, rotCode, Endian.little);
    _paramsBuf = _gpu.createBuffer(32, BufferDataType.uint8);
    await _paramsBuf!.write(
      view.buffer.asUint8List(),
      32,
      dataType: BufferDataType.uint8,
    );

    _outBuf = _gpu.createBuffer(
      _outWidth * _outHeight * 4,
      BufferDataType.uint8,
    );
  }

  @override
  Future<void> apply(Buffer inBuf, int inW, int inH) async {
    _shader!
      ..setBufferAtSlot(0, inBuf)
      ..setBufferAtSlot(1, _outBuf!)
      ..setBufferAtSlot(2, _paramsBuf!);
    const kGroup = 8;
    await _shader!.dispatch(
      (_outWidth + kGroup - 1) ~/ kGroup,
      (_outHeight + kGroup - 1) ~/ kGroup,
      1,
    );
  }

  @override
  void dispose() {
    try {
      _shader?.destroy();
    } catch (_) {}
    try {
      _paramsBuf?.destroy();
    } catch (_) {}
    try {
      _outBuf?.destroy();
    } catch (_) {}
    _shader = null;
    _paramsBuf = null;
    _outBuf = null;
  }
}

// ---------------------------------------------------------------------------
// Scale effect runtime (transform: separate src → dst, arbitrary target dims)
// ---------------------------------------------------------------------------

/// GPU runtime for [ScaleScreenEffect]. Uses the same bilinear kernel as the
/// initial downscale step but operates as a mid-chain effect, allowing upscale
/// or downscale to any target size after earlier effects (e.g. crop → scale).
class _ScaleEffectRuntime extends _EffectRuntime {
  _ScaleEffectRuntime(this._gpu, this._desc, this._inW, this._inH);

  final Minigpu _gpu;
  final ScaleScreenEffect _desc;
  final int _inW;
  final int _inH;

  ComputeShader? _shader;
  Buffer? _paramsBuf;
  Buffer? _outBuf;

  @override
  Buffer? get outBuf => _outBuf;
  @override
  int? get outW => _desc.width;
  @override
  int? get outH => _desc.height;

  Future<void> init() async {
    // Reuse the bilinear downscale WGSL — it works for up and downscale.
    _shader = _gpu.createComputeShader()..loadKernelString(_kDownscaleWgsl);

    // Params: srcW, srcH, dstW, dstH — 4×u32 = 16 bytes (same as downscale).
    final view = ByteData(16)
      ..setUint32(0, _inW, Endian.little)
      ..setUint32(4, _inH, Endian.little)
      ..setUint32(8, _desc.width, Endian.little)
      ..setUint32(12, _desc.height, Endian.little);
    _paramsBuf = _gpu.createBuffer(16, BufferDataType.uint8);
    await _paramsBuf!.write(
      view.buffer.asUint8List(),
      16,
      dataType: BufferDataType.uint8,
    );

    _outBuf = _gpu.createBuffer(
      _desc.width * _desc.height * 4,
      BufferDataType.uint8,
    );
  }

  @override
  Future<void> apply(Buffer inBuf, int inW, int inH) async {
    _shader!
      ..setBufferAtSlot(0, inBuf)
      ..setBufferAtSlot(1, _outBuf!)
      ..setBufferAtSlot(2, _paramsBuf!);
    const kGroup = 8;
    await _shader!.dispatch(
      (_desc.width + kGroup - 1) ~/ kGroup,
      (_desc.height + kGroup - 1) ~/ kGroup,
      1,
    );
  }

  @override
  void dispose() {
    try {
      _shader?.destroy();
    } catch (_) {}
    try {
      _paramsBuf?.destroy();
    } catch (_) {}
    try {
      _outBuf?.destroy();
    } catch (_) {}
    _shader = null;
    _paramsBuf = null;
    _outBuf = null;
  }
}
// ---------------------------------------------------------------------------

/// Owns all GPU resources for processing one screen-capture track per frame.
///
/// Combines optional bilinear downscaling and an ordered chain of
/// [ScreenEffect]s into a single [process] call that returns a
/// [SharedOutputTexture] ready for [FfmpegD3d11HwEncoder].
///
/// Lifecycle: create once per track, call [process] each frame, [dispose] on
/// track teardown.
class GpuScreenProcessor {
  GpuScreenProcessor({
    required Minigpu gpu,
    required this.srcWidth,
    required this.srcHeight,
    required this.dstWidth,
    required this.dstHeight,
    List<ScreenEffect> effects = const [],
  }) : _gpu = gpu,
       _effectDescriptors = List.unmodifiable(effects) {
    // Initialise the tracked src dims to the initial capture size.
    _currentSrcW = srcWidth;
    _currentSrcH = srcHeight;
    // Pre-compute the final output size by chaining each effect's outputSize().
    var (w, h) = (dstWidth, dstHeight);
    for (final fx in effects) {
      (w, h) = fx.outputSize(w, h);
    }
    outputWidth = w;
    outputHeight = h;
  }

  final Minigpu _gpu;

  /// Full-resolution capture dimensions.
  final int srcWidth;
  final int srcHeight;

  /// Dimensions after the [ScreenScalePolicy] downscale (pre-effects).
  /// Equal to [srcWidth]×[srcHeight] when no scale policy is active.
  final int dstWidth;
  final int dstHeight;

  /// Final output dimensions — after all effects have been applied.
  /// This is the size the encoder and [SharedOutputTexture] are opened at.
  /// Equals [dstWidth]×[dstHeight] when no dimension-changing effects are used.
  late final int outputWidth;
  late final int outputHeight;

  final List<ScreenEffect> _effectDescriptors;

  bool _resourcesReady = false;

  // Downscale resources (only allocated when dstW x dstH != srcW x srcH).
  ComputeShader? _downscaleShader;
  Buffer? _dstBuf; // persistent per-frame output buffer of the downsample
  Buffer? _paramsBuf; // 16-byte params for the downsample kernel

  SharedOutputTexture? _sharedTex;
  final List<_EffectRuntime> _effectRuntimes = [];

  bool _disposed = false;

  // -------------------------------------------------------------------------

  /// Current incoming frame dimensions. Initialised from [srcWidth]/[srcHeight]
  /// and updated whenever a window resize is detected in [process].
  int _currentSrcW = 0;
  int _currentSrcH = 0;

  /// True when the current input frame must be scaled to [dstWidth]×[dstHeight].
  bool get _needsDownscale =>
      _currentSrcW != dstWidth || _currentSrcH != dstHeight;

  /// True when this processor has actual GPU work to do on each frame.
  bool get hasWork =>
      srcWidth != dstWidth ||
      srcHeight != dstHeight ||
      _effectDescriptors.isNotEmpty;

  // -------------------------------------------------------------------------

  /// Process one captured [buffer] (must have `contentType == gpuD3D11Handle`).
  ///
  /// Returns the [SharedOutputTexture] at [outputWidth] x [outputHeight] with
  /// all scaling + effects applied, or `null` on any failure.
  ///
  /// The returned texture is owned by this processor. Do NOT destroy it.
  Future<SharedOutputTexture?> process(MiniAVBuffer buffer) async {
    assert(!_disposed, 'GpuScreenProcessor.process called after dispose()');

    final video = buffer.data;
    if (video is! MiniAVVideoBuffer) return null;
    if (video.nativeHandles.isEmpty || video.nativeHandles[0] == null) {
      return null;
    }
    final int handleAddr = (video.nativeHandles[0] as Pointer).address;
    if (handleAddr == 0) return null;

    final int stride = video.strideBytes.isNotEmpty
        ? video.strideBytes[0]
        : video.width * 4;

    final extBuf = ExternalVideoBuffer(
      contentType: ExternalContentType.d3d11SharedHandle,
      pixelFormat: ExternalPixelFormat.bgra32,
      width: video.width,
      height: video.height,
      planes: [
        ExternalPlane(
          dataPtr: handleAddr,
          width: video.width,
          height: video.height,
          strideBytes: stride,
        ),
      ],
      fence: ExternalFence(d3d11FencePtr: buffer.nativeFence.d3d11FencePtr),
      timestampUs: buffer.timestampUs,
    );

    VideoTexture? tex;
    Buffer? srcRgba; // full-res RGBA; owned here, must be destroyed in finally
    try {
      tex = _gpu.importVideoFrame(extBuf);
      if (tex == null) return null;

      await _ensureResources();

      // Detect window resize: if the incoming frame has different dimensions
      // than the last seen frame, update the downscale shader params so we
      // always produce output at the fixed encoder size (outputWidth × outputHeight).
      final int actualW = video.width;
      final int actualH = video.height;
      if (actualW != _currentSrcW || actualH != _currentSrcH) {
        stderr.writeln(
          '[gpu_processor] window resize: ${_currentSrcW}x$_currentSrcH → '
          '${actualW}x$actualH — adapting to encoder '
          '${outputWidth}x$outputHeight',
        );
        _currentSrcW = actualW;
        _currentSrcH = actualH;
        await _updateDownscaleParams();
      }

      // 1. BGRA -> RGBA at full resolution (GPU compute).
      srcRgba = tex.toRGBA();

      // 2. Bilinear downsample whenever actual dims differ from dst dims.
      Buffer effectsBuf;
      int effectsW, effectsH;
      if (_needsDownscale) {
        await _runDownscale(srcRgba);
        srcRgba.destroy();
        srcRgba = null; // prevent double-free in finally
        effectsBuf = _dstBuf!; // persistent; NOT freed in finally
        effectsW = dstWidth;
        effectsH = dstHeight;
      } else {
        effectsBuf = srcRgba;
        effectsW = dstWidth;
        effectsH = dstHeight;
      }

      // 3. Chained effects — each runtime may be in-place or transform.
      // Transform effects (e.g. crop) write to their own persistent output
      // buffer and change the working (effectsBuf, effectsW, effectsH).
      for (final fx in _effectRuntimes) {
        await fx.apply(effectsBuf, effectsW, effectsH);
        final ob = fx.outBuf;
        if (ob != null) {
          effectsBuf = ob; // switch to the transform output buffer
          effectsW = fx.outW!;
          effectsH = fx.outH!;
        }
      }

      // 4. Copy processed buffer -> SharedOutputTexture (GPU blit, no PCIe).
      if (!_sharedTex!.copyFromBuffer(effectsBuf)) return null;
      return _sharedTex;
    } catch (e, st) {
      stderr.writeln('[gpu_processor] process error: $e\n$st');
      return null;
    } finally {
      srcRgba?.destroy();
      tex?.destroy();
    }
  }

  // -------------------------------------------------------------------------

  Future<void> _runDownscale(Buffer srcBuf) async {
    _downscaleShader!
      ..setBufferAtSlot(0, srcBuf)
      ..setBufferAtSlot(1, _dstBuf!)
      ..setBufferAtSlot(2, _paramsBuf!);
    const kGroup = 8;
    await _downscaleShader!.dispatch(
      (dstWidth + kGroup - 1) ~/ kGroup,
      (dstHeight + kGroup - 1) ~/ kGroup,
      1,
    );
  }

  /// Lazily creates the downscale shader + buffers if not yet allocated, then
  /// writes the current [_currentSrcW]/[_currentSrcH] into the params buffer.
  ///
  /// Called from [_ensureResources] on first frame, and from [process] whenever
  /// a window resize is detected.
  Future<void> _updateDownscaleParams() async {
    if (_downscaleShader == null) {
      _downscaleShader = _gpu.createComputeShader()
        ..loadKernelString(_kDownscaleWgsl);
      _dstBuf ??= _gpu.createBuffer(
        dstWidth * dstHeight * 4,
        BufferDataType.uint8,
      );
    }
    final pData = ByteData(16)
      ..setUint32(0, _currentSrcW, Endian.little)
      ..setUint32(4, _currentSrcH, Endian.little)
      ..setUint32(8, dstWidth, Endian.little)
      ..setUint32(12, dstHeight, Endian.little);
    _paramsBuf ??= _gpu.createBuffer(16, BufferDataType.uint8);
    await _paramsBuf!.write(
      pData.buffer.asUint8List(),
      16,
      dataType: BufferDataType.uint8,
    );
  }

  Future<void> _ensureResources() async {
    if (_resourcesReady) return;

    if (_needsDownscale) {
      final s = _gpu.createComputeShader();
      s.loadKernelString(_kDownscaleWgsl);
      _downscaleShader = s;

      _dstBuf = _gpu.createBuffer(
        dstWidth * dstHeight * 4,
        BufferDataType.uint8,
      );

      final pData = ByteData(16)
        ..setUint32(0, _currentSrcW, Endian.little)
        ..setUint32(4, _currentSrcH, Endian.little)
        ..setUint32(8, dstWidth, Endian.little)
        ..setUint32(12, dstHeight, Endian.little);
      _paramsBuf = _gpu.createBuffer(16, BufferDataType.uint8);
      await _paramsBuf!.write(
        pData.buffer.asUint8List(),
        16,
        dataType: BufferDataType.uint8,
      );
    }

    // Build effect runtimes, tracking the running (w, h) through the chain.
    var (runW, runH) = (dstWidth, dstHeight);
    for (final desc in _effectDescriptors) {
      switch (desc) {
        case WgslScreenEffect():
          _effectRuntimes.add(_GpuEffectRuntime(_gpu, desc));
        // in-place: runW/runH unchanged
        case CropScreenEffect():
          final rt = _CropEffectRuntime(_gpu, desc, runW, runH);
          await rt.init();
          _effectRuntimes.add(rt);
          runW = desc.cropWidth;
          runH = desc.cropHeight;
        case FlipScreenEffect():
          final rt = _FlipEffectRuntime(_gpu, desc, runW, runH);
          await rt.init();
          _effectRuntimes.add(rt);
        // same dims — runW/runH unchanged
        case RotateScreenEffect():
          final rt = _RotateEffectRuntime(_gpu, desc, runW, runH);
          await rt.init();
          _effectRuntimes.add(rt);
          (runW, runH) = desc.outputSize(runW, runH);
        case ScaleScreenEffect():
          final rt = _ScaleEffectRuntime(_gpu, desc, runW, runH);
          await rt.init();
          _effectRuntimes.add(rt);
          runW = desc.width;
          runH = desc.height;
      }
    }

    _sharedTex = _gpu.createSharedOutputTexture(outputWidth, outputHeight);
    if (_sharedTex == null) {
      throw StateError(
        '[gpu_processor] createSharedOutputTexture(${outputWidth}x$outputHeight) '
        'returned null — Dawn D3D12 backend required.',
      );
    }

    _resourcesReady = true;
  }

  // -------------------------------------------------------------------------

  /// Release all GPU resources. Safe to call multiple times.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try {
      _downscaleShader?.destroy();
    } catch (_) {}
    try {
      _dstBuf?.destroy();
    } catch (_) {}
    try {
      _paramsBuf?.destroy();
    } catch (_) {}
    try {
      _sharedTex?.destroy();
    } catch (_) {}
    for (final fx in _effectRuntimes) {
      try {
        fx.dispose();
      } catch (_) {}
    }
    _effectRuntimes.clear();
    _downscaleShader = null;
    _dstBuf = null;
    _paramsBuf = null;
    _sharedTex = null;
  }
}
