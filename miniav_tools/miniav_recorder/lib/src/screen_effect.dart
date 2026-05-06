/// GPU effect descriptors for screen captures.
///
/// Effects are pure configuration objects — no GPU resources are allocated
/// until the [Recorder] starts. They run entirely on the GPU (WGSL compute
/// shaders via Dawn/D3D12) as part of the zero-copy pipeline and require
/// [RecorderBuilder.preferZeroCopy] to be active (the default on Windows).
///
/// ### Pipeline order (per frame)
/// ```
/// D3D11 NT handle (miniav capture)
///   → importVideoFrame()    VideoTexture  BGRA, srcW×srcH
///   → toRGBA()              Buffer        RGBA u32[], srcW×srcH
///   → [bilinear downscale]  Buffer        RGBA u32[], dstW×dstH  ← if scale policy set
///   → effect[0].apply()     Buffer        RGBA u32[], dstW×dstH  ← in-place
///   → effect[1].apply()     …
///   → SharedOutputTexture.copyFromBuffer
///   → FfmpegD3d11HwEncoder  (zero-copy, no PCIe)
/// ```
library;

/// A descriptor for a GPU compute effect applied to screen captures.
///
/// Effects are applied in declaration order **after** any [ScreenScalePolicy]
/// downscaling, operating on the final encoder-sized RGBA8 buffer. This means
/// effects always work on the smallest possible buffer for maximum efficiency.
///
/// ### Built-in effects
/// | Factory | Description |
/// |---|---|
/// | [ScreenEffect.vignette] | Radial vignette + warm colour grade. |
///
/// ### Custom WGSL effect
///
/// Write a standard WGSL compute shader that follows the **binding convention**:
/// ```wgsl
/// struct Params {
///   width    : u32,   // always injected — current frame width in pixels
///   height   : u32,   // always injected — current frame height in pixels
///   myParam  : f32,   // extraParams[0]
///   // ... more extraParams fields ...
/// };
///
/// @group(0) @binding(0) var<storage, read_write> pixels : array<u32>; // RGBA8 in/out
/// @group(0) @binding(1) var<storage, read_write> params : Params;
///
/// @compute @workgroup_size(8, 8, 1)
/// fn main(@builtin(global_invocation_id) gid : vec3<u32>) {
///   if (gid.x >= params.width || gid.y >= params.height) { return; }
///   let idx = gid.y * params.width + gid.x;
///   // … modify pixels[idx] …
/// }
/// ```
///
/// Then register it:
/// ```dart
/// builder.addScreen(
///   effects: [
///     ScreenEffect.wgsl(myWgsl, extraParams: [0.8]),
///   ],
/// );
/// ```
sealed class ScreenEffect {
  const ScreenEffect();

  // ----- factories ---------------------------------------------------------

  /// Apply a custom WGSL compute shader effect.
  ///
  /// [wgslSource] must follow the binding convention described on [ScreenEffect]:
  /// - `@binding(0)` — `array<u32>` RGBA8 pixels, read-write in-place.
  /// - `@binding(1)` — `Params` struct: `width : u32` at byte 0, `height : u32`
  ///   at byte 4, then [extraParams] as `f32` fields from byte 8 onward.
  ///
  /// [extraParams] are appended to the params struct after `width` and `height`.
  /// The recorder injects the current frame dimensions automatically; you only
  /// need to provide your own shader-specific floats here.
  factory ScreenEffect.wgsl(
    String wgslSource, {
    List<double> extraParams = const [],
  }) => WgslScreenEffect(
    wgslSource: wgslSource,
    extraParams: List.unmodifiable(extraParams),
  );

  /// Built-in radial vignette + warm colour grade.
  ///
  /// Darkens corners with a soft radial falloff and applies a warm colour
  /// shift (R +6 %, G neutral, B −8 %).
  ///
  /// [strength] controls intensity: `0.0` = pass-through, `1.0` = full effect.
  factory ScreenEffect.vignette({double strength = 1.0}) => WgslScreenEffect(
    wgslSource: _kVignetteWarmWgsl,
    extraParams: List.unmodifiable([strength.clamp(0.0, 1.0), 0.0]),
  );
}

// ---------------------------------------------------------------------------
// Concrete descriptor (public so gpu_downscaler.dart can access fields across
// the library boundary without using `part`).
// Prefer the ScreenEffect factories rather than constructing this directly.
// ---------------------------------------------------------------------------

/// WGSL-based [ScreenEffect] descriptor.
///
/// Use the [ScreenEffect.wgsl] or [ScreenEffect.vignette] factories rather
/// than constructing this directly.
final class WgslScreenEffect extends ScreenEffect {
  const WgslScreenEffect({required this.wgslSource, required this.extraParams});

  /// WGSL source that follows the standard binding convention.
  final String wgslSource;

  /// Extra `f32` values written into the params buffer starting at byte 8
  /// (after `width : u32` and `height : u32`).
  final List<double> extraParams;
}

// ---------------------------------------------------------------------------
// Built-in vignette + warm grade shader
// ---------------------------------------------------------------------------

const _kVignetteWarmWgsl = r'''
// Radial vignette + warm colour grade.
// Standard binding convention:
//   @binding(0) pixels : array<u32>   RGBA8 in/out (one u32 per pixel)
//   @binding(1) params : Params       { width, height, strength, _pad }
struct Params {
  width    : u32,
  height   : u32,
  strength : f32,
  _pad     : f32,
};

@group(0) @binding(0) var<storage, read_write> pixels : array<u32>;
@group(0) @binding(1) var<storage, read_write> params : Params;

fn unpack(p : u32) -> vec4<f32> {
  return vec4<f32>(
    f32( p        & 0xFFu),
    f32((p >>  8u) & 0xFFu),
    f32((p >> 16u) & 0xFFu),
    f32((p >> 24u) & 0xFFu),
  ) / 255.0;
}

fn pack(c : vec4<f32>) -> u32 {
  let q = clamp(c, vec4<f32>(0.0), vec4<f32>(1.0)) * 255.0 + vec4<f32>(0.5);
  return  u32(q.x)
       | (u32(q.y) <<  8u)
       | (u32(q.z) << 16u)
       | (u32(q.w) << 24u);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid : vec3<u32>) {
  if (gid.x >= params.width || gid.y >= params.height) { return; }
  let idx = gid.y * params.width + gid.x;
  var c = unpack(pixels[idx]);

  // Radial vignette — normalised squared distance from centre.
  let cx = f32(params.width)  * 0.5;
  let cy = f32(params.height) * 0.5;
  let dx = f32(gid.x) - cx;
  let dy = f32(gid.y) - cy;
  let r2 = (dx * dx + dy * dy) / (cx * cx + cy * cy);
  let vig = 1.0 - r2 * 0.65 * params.strength;

  // Warm grade: boost R slightly, dampen B.
  let warm = vec3<f32>(1.06, 1.00, 0.92);
  let rgb = mix(c.rgb, c.rgb * warm * vig, params.strength);
  pixels[idx] = pack(vec4<f32>(rgb, c.a));
}
''';
