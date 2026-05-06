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
///   -> effect[0].apply()          Buffer        RGBA u32[], dstW x dstH  (optional chain)
///   -> effect[n].apply()          ...
///   -> SharedOutputTexture.copyFromBuffer
///                                 SharedOutputTexture (RGBA, dstW x dstH)
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
// Internal per-effect GPU runtime
// ---------------------------------------------------------------------------

/// Owns the [ComputeShader] + params [Buffer] for one [WgslScreenEffect].
/// Created lazily; reuses params buffer across frames unless dimensions change.
class _GpuEffectRuntime {
  _GpuEffectRuntime(this._gpu, this._descriptor);

  final Minigpu _gpu;
  final WgslScreenEffect _descriptor;

  ComputeShader? _shader;
  Buffer? _paramsBuf;
  int _lastW = -1;
  int _lastH = -1;

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
// GpuScreenProcessor
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
       _effectDescriptors = List.unmodifiable(effects);

  final Minigpu _gpu;

  /// Full-resolution capture dimensions.
  final int srcWidth;
  final int srcHeight;

  /// Encoder dimensions (post-downscale). Equal to src when no downscaling.
  final int dstWidth;
  final int dstHeight;

  final List<ScreenEffect> _effectDescriptors;

  bool _resourcesReady = false;

  // Downscale resources (only allocated when dstW x dstH != srcW x srcH).
  ComputeShader? _downscaleShader;
  Buffer? _dstBuf; // persistent per-frame output buffer of the downsample
  Buffer? _paramsBuf; // 16-byte params for the downsample kernel

  SharedOutputTexture? _sharedTex;
  final List<_GpuEffectRuntime> _effectRuntimes = [];

  bool _disposed = false;

  // -------------------------------------------------------------------------

  bool get _needsDownscale => dstWidth != srcWidth || dstHeight != srcHeight;

  /// True when this processor has actual GPU work to do on each frame.
  bool get hasWork => _needsDownscale || _effectDescriptors.isNotEmpty;

  // -------------------------------------------------------------------------

  /// Process one captured [buffer] (must have `contentType == gpuD3D11Handle`).
  ///
  /// Returns the [SharedOutputTexture] at [dstWidth] x [dstHeight] with all
  /// scaling + effects applied, or `null` on any failure.
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

      // 1. BGRA -> RGBA at full resolution (GPU compute).
      srcRgba = tex.toRGBA();

      // 2. Optional bilinear downsample.
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
        effectsW = srcWidth;
        effectsH = srcHeight;
      }

      // 3. Chained effects in-place (on the dst-sized buffer).
      for (final fx in _effectRuntimes) {
        await fx.apply(effectsBuf, effectsW, effectsH);
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
        ..setUint32(0, srcWidth, Endian.little)
        ..setUint32(4, srcHeight, Endian.little)
        ..setUint32(8, dstWidth, Endian.little)
        ..setUint32(12, dstHeight, Endian.little);
      _paramsBuf = _gpu.createBuffer(16, BufferDataType.uint8);
      await _paramsBuf!.write(
        pData.buffer.asUint8List(),
        16,
        dataType: BufferDataType.uint8,
      );
    }

    for (final desc in _effectDescriptors) {
      switch (desc) {
        case WgslScreenEffect():
          _effectRuntimes.add(_GpuEffectRuntime(_gpu, desc));
      }
    }

    _sharedTex = _gpu.createSharedOutputTexture(dstWidth, dstHeight);
    if (_sharedTex == null) {
      throw StateError(
        '[gpu_processor] createSharedOutputTexture(${dstWidth}x$dstHeight) '
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
