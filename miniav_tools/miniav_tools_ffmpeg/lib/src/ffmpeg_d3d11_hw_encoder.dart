/// Stage B — true zero-copy D3D11VA hardware encoder.
///
/// Accepts D3D11-backed frames (a `D3D11TextureFrameSource`, or a
/// `MiniAVBufferSource` whose `contentType == gpuD3D11Handle`) and feeds
/// them to an `*_amf` / `*_qsv` / `*_mf` encoder via `AV_PIX_FMT_D3D11`
/// without ever touching system memory.
///
/// Pipeline per frame:
/// 1. Capture produces an NT-shared D3D11 texture (`MiniAVBuffer`).
/// 2. We `OpenSharedResource1` it on FFmpeg's own `ID3D11Device`.
/// 3. We `CopyResource` it into a pool texture allocated by FFmpeg's
///    `AVHWFramesContext` (BGRA → no colour-space conversion).
/// 4. The pool AVFrame is sent to the encoder; the encoder driver
///    (AMF / Intel Media SDK / MediaFoundation) consumes the texture
///    on the GPU and produces an encoded packet.
///
/// **Vendors covered here:**
/// - NVENC — accepts `AV_PIX_FMT_D3D11` natively via NVENC's DirectX
///   resource path (`NV_ENC_INPUT_RESOURCE_TYPE_DIRECTX`). No CUDA needed.
/// - AMF — AMD's encoder runtime; native D3D11 surface input.
/// - QSV — Intel Media SDK; needs a *derived* `qsv` hwframes context
///   chained from D3D11VA (handled by [openWith]).
/// - MediaFoundation — universal Windows fallback (vendor MFT under the
///   hood; usually slower than the dedicated runtimes above).
///
/// **Skipped here (Apple/Linux/Android-only)**: VideoToolbox, VAAPI,
/// V4L2 M2M, MediaCodec — those live in their own platform encoder files.
///
/// **Why this is faster than Stage A** (NVENC `bgr0` upload):
/// Stage A copies `width × height × 4` bytes across the PCIe bus per frame
/// (~29 MB at 5K). Stage B does a pure intra-GPU `CopyResource`. At 5K60 the
/// difference is ~1.7 GB/s of CPU→GPU bandwidth completely eliminated.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

import 'ffmpeg_encoder.dart' show address;
import 'ffmpeg_ffi.dart';
import 'ffmpeg_muxer.dart' show FfmpegEncoderBridge;
import 'ffmpeg_shim.dart';

/// FFmpeg pixel-format enum value for `AV_PIX_FMT_D3D11` (libavutil 60).
/// Resolved by name at init — falls back to a hard-coded literal only if
/// the lookup fails (which would indicate a libavutil without D3D11VA
/// support, in which case the encoder won't open anyway).
const int _avPixFmtD3d11Fallback = 174;

/// Encoder vendors that natively consume `AV_PIX_FMT_D3D11`.
enum D3d11HwVendor { nvenc, amf, qsv, mediafoundation }

/// DXGI pixel layout of the source textures the encoder will receive in
/// `encode()`. Determines the `sw_format` of FFmpeg's hwframes pool, which
/// in turn dictates the DXGI format of the pool textures —
/// `CopySubresourceRegion` cannot copy across format type-groups, so this
/// MUST match the source layout exactly.
///
/// - [bgra] — `DXGI_FORMAT_B8G8R8A8_UNORM` (miniav DXGI screen capture).
/// - [rgba] — `DXGI_FORMAT_R8G8B8A8_UNORM` (minigpu `SharedOutputTexture`,
///   the standard WebGPU `rgba8unorm` storage texture format).
enum D3d11HwSourceFormat { bgra, rgba }

class _D3d11Spec {
  final D3d11HwVendor vendor;
  final VideoCodec codec;
  final String encoderName;
  final int maxWidth;
  final int maxHeight;
  final Map<String, String> defaults;

  const _D3d11Spec({
    required this.vendor,
    required this.codec,
    required this.encoderName,
    required this.maxWidth,
    required this.maxHeight,
    required this.defaults,
  });
}

const List<_D3d11Spec> _d3d11Specs = [
  // ─── NVIDIA NVENC ─────────────────────────────────────────────────────────
  // NVENC accepts AV_PIX_FMT_D3D11 directly — the wrapper registers each
  // pool texture with the NVENC session via NV_ENC_INPUT_RESOURCE_TYPE_DIRECTX.
  // Preset 'p4' = balanced quality/speed; tune 'll' = low-latency; rc 'cbr'
  // matches the encoder's expectations for screen-share / live workloads.
  _D3d11Spec(
    vendor: D3d11HwVendor.nvenc,
    codec: VideoCodec.h264,
    encoderName: 'h264_nvenc',
    maxWidth: 4096,
    maxHeight: 4096,
    defaults: {'preset': 'p4', 'tune': 'll', 'rc': 'cbr'},
  ),
  _D3d11Spec(
    vendor: D3d11HwVendor.nvenc,
    codec: VideoCodec.hevc,
    encoderName: 'hevc_nvenc',
    maxWidth: 8192,
    maxHeight: 8192,
    defaults: {'preset': 'p4', 'tune': 'll', 'rc': 'cbr'},
  ),
  _D3d11Spec(
    vendor: D3d11HwVendor.nvenc,
    codec: VideoCodec.av1,
    encoderName: 'av1_nvenc',
    maxWidth: 8192,
    maxHeight: 8192,
    defaults: {'preset': 'p4', 'tune': 'll', 'rc': 'cbr'},
  ),

  // ─── AMD AMF ──────────────────────────────────────────────────────────────
  _D3d11Spec(
    vendor: D3d11HwVendor.amf,
    codec: VideoCodec.h264,
    encoderName: 'h264_amf',
    maxWidth: 4096,
    maxHeight: 4096,
    defaults: {'usage': 'transcoding', 'quality': 'speed'},
  ),
  _D3d11Spec(
    vendor: D3d11HwVendor.amf,
    codec: VideoCodec.hevc,
    encoderName: 'hevc_amf',
    maxWidth: 8192,
    maxHeight: 8192,
    defaults: {'usage': 'transcoding', 'quality': 'speed'},
  ),
  _D3d11Spec(
    vendor: D3d11HwVendor.amf,
    codec: VideoCodec.av1,
    encoderName: 'av1_amf',
    maxWidth: 8192,
    maxHeight: 8192,
    defaults: {'usage': 'transcoding', 'quality': 'speed'},
  ),

  // ─── Intel QSV ────────────────────────────────────────────────────────────
  _D3d11Spec(
    vendor: D3d11HwVendor.qsv,
    codec: VideoCodec.h264,
    encoderName: 'h264_qsv',
    maxWidth: 4096,
    maxHeight: 4096,
    defaults: {'preset': 'veryfast'},
  ),
  _D3d11Spec(
    vendor: D3d11HwVendor.qsv,
    codec: VideoCodec.hevc,
    encoderName: 'hevc_qsv',
    maxWidth: 8192,
    maxHeight: 8192,
    defaults: {'preset': 'veryfast'},
  ),
  _D3d11Spec(
    vendor: D3d11HwVendor.qsv,
    codec: VideoCodec.av1,
    encoderName: 'av1_qsv',
    maxWidth: 8192,
    maxHeight: 8192,
    defaults: {'preset': 'veryfast'},
  ),

  // ─── Windows Media Foundation (universal fallback on Windows) ────────────
  _D3d11Spec(
    vendor: D3d11HwVendor.mediafoundation,
    codec: VideoCodec.h264,
    encoderName: 'h264_mf',
    maxWidth: 4096,
    maxHeight: 4096,
    defaults: {'hw_encoding': '1'},
  ),
  _D3d11Spec(
    vendor: D3d11HwVendor.mediafoundation,
    codec: VideoCodec.hevc,
    encoderName: 'hevc_mf',
    maxWidth: 8192,
    maxHeight: 8192,
    defaults: {'hw_encoding': '1'},
  ),
];

/// Default vendor probe order: NVENC → AMF → QSV → MediaFoundation.
/// The first three are vendor-native fast paths (one per GPU vendor);
/// MF is the generic Windows fallback and typically slowest. Each vendor
/// will only succeed on its matching GPU, so this order safely covers all
/// three IHVs without relying on runtime detection of the adapter vendor.
const List<D3d11HwVendor> _defaultD3d11Order = [
  D3d11HwVendor.nvenc,
  D3d11HwVendor.amf,
  D3d11HwVendor.qsv,
  D3d11HwVendor.mediafoundation,
];

bool _encoderPresent(Ffmpeg ff, String name) {
  final p = name.toNativeUtf8();
  try {
    return ff.avcodecFindEncoderByName(p) != address(0);
  } finally {
    calloc.free(p);
  }
}

_D3d11Spec? _findSpec(D3d11HwVendor vendor, VideoCodec codec) {
  for (final s in _d3d11Specs) {
    if (s.vendor == vendor && s.codec == codec) return s;
  }
  return null;
}

_D3d11Spec? _pickSpec(
  Ffmpeg ff,
  VideoCodec codec, {
  List<D3d11HwVendor> order = _defaultD3d11Order,
}) {
  for (final v in order) {
    final spec = _findSpec(v, codec);
    if (spec == null) continue;
    if (_encoderPresent(ff, spec.encoderName)) return spec;
  }
  return null;
}

/// Returns the list of D3D11VA-compatible vendors registered in the loaded
/// FFmpeg build. Cheap — only does name lookups, does not init any GPU.
List<D3d11HwVendor> ffmpegD3d11VendorsAvailable() {
  if (!Platform.isWindows) return const [];
  final ff = Ffmpeg.instance();
  if (ff == null) return const [];
  final seen = <D3d11HwVendor>{};
  for (final s in _d3d11Specs) {
    if (seen.contains(s.vendor)) continue;
    if (_encoderPresent(ff, s.encoderName)) seen.add(s.vendor);
  }
  return seen.toList(growable: false);
}

/// Returns true if any D3D11VA encoder for [codec] is registered AND the
/// shim is loaded. Stage B is otherwise unavailable.
bool ffmpegD3d11EncoderAvailable(VideoCodec codec) {
  if (!Platform.isWindows) return false;
  if (FfmpegShim.tryLoad() == null) return false;
  final ff = Ffmpeg.instance();
  if (ff == null) return false;
  for (final s in _d3d11Specs) {
    if (s.codec == codec && _encoderPresent(ff, s.encoderName)) return true;
  }
  return false;
}

/// True zero-copy D3D11VA hardware encoder. See library doc-comment for
/// pipeline details.
class FfmpegD3d11HwEncoder implements PlatformEncoder, FfmpegEncoderBridge {
  FfmpegD3d11HwEncoder._(
    this._ff,
    this._shim,
    this._cfg,
    this._spec,
    this._codecCtx,
    this._packet,
    this._hwDeviceRef,
    this._hwFramesRef,
    this._d3dDevice,
    this._d3dContext,
    this._d3dPixFmt,
  );

  final Ffmpeg _ff;
  final FfmpegShim _shim;
  final EncoderConfig _cfg;
  final _D3d11Spec _spec;
  final Pointer<AVCodecContext> _codecCtx;
  final Pointer<AVPacket> _packet;

  /// `AVBufferRef*` to the FFmpeg-owned `AVHWDeviceContext` (D3D11VA).
  Pointer<Void> _hwDeviceRef;

  /// `AVBufferRef*` to the FFmpeg-owned `AVHWFramesContext` (pool of
  /// `width × height` BGRA D3D11 textures).
  Pointer<Void> _hwFramesRef;

  /// `ID3D11Device*` owned by FFmpeg (we don't AddRef/Release — FFmpeg
  /// keeps the only strong ref via [_hwDeviceRef]).
  final Pointer<Void> _d3dDevice;

  /// `ID3D11DeviceContext*` (immediate context) on the same device.
  final Pointer<Void> _d3dContext;

  /// Resolved `AV_PIX_FMT_D3D11` value.
  final int _d3dPixFmt;

  bool _closed = false;
  int _nextPts = 0;
  CodecExtraData? _extraData;
  bool _forceKeyframe = false;

  D3d11HwVendor get vendor => _spec.vendor;
  String get encoderName => _spec.encoderName;

  /// Open the best D3D11VA encoder for [cfg.codec], honouring [vendorOrder]
  /// (default: AMF → QSV → MediaFoundation). Throws [CodecInitException]
  /// on every failure mode (no compatible vendor, shim missing, GPU init
  /// failure). Callers that want a graceful fall-back to Stage A should
  /// catch this and try `FfmpegHwEncoder.open(cfg)`.
  static FfmpegD3d11HwEncoder open(
    EncoderConfig cfg, {
    List<D3d11HwVendor> vendorOrder = _defaultD3d11Order,
    int existingD3d11Device = 0,
    D3d11HwSourceFormat sourceTextureFormat = D3d11HwSourceFormat.bgra,
  }) {
    if (!Platform.isWindows) {
      throw const CodecInitException(
        'ffmpeg-d3d11',
        'D3D11VA encoder is Windows-only',
      );
    }
    final shim = FfmpegShim.tryLoad();
    if (shim == null) {
      throw const CodecInitException(
        'ffmpeg-d3d11',
        'miniav_tools_ffmpeg shim is not loadable — Stage B unavailable. '
            'Run `dart pub get` to rebuild the native asset.',
      );
    }
    final ff = Ffmpeg.instance();
    if (ff == null) {
      throw const CodecInitException(
        'ffmpeg-d3d11',
        'FFmpeg not loaded — call ensureFFmpegLoaded() first',
      );
    }
    // Try each vendor in priority order. A vendor whose encoder *symbol*
    // exists may still fail at runtime (e.g. AMF on a non-AMD GPU, QSV
    // without an Intel iGPU). Fall through to the next on CodecInitException.
    final attempted = <String>[];
    Object? lastError;
    StackTrace? lastStack;
    for (final vendor in vendorOrder) {
      final spec = _findSpec(vendor, cfg.codec);
      if (spec == null || !_encoderPresent(ff, spec.encoderName)) {
        attempted.add('${vendor.name}(missing)');
        continue;
      }
      try {
        return openWith(
          cfg,
          vendor,
          existingD3d11Device: existingD3d11Device,
          sourceTextureFormat: sourceTextureFormat,
        );
      } on CodecInitException catch (e, st) {
        attempted.add('${vendor.name}(${e.message})');
        lastError = e;
        lastStack = st;
      } catch (e, st) {
        attempted.add('${vendor.name}($e)');
        lastError = e;
        lastStack = st;
      }
    }
    throw CodecInitException(
      'ffmpeg-d3d11',
      'No working D3D11VA encoder for ${cfg.codec}. Tried: '
          '${attempted.join(' | ')}. Last error: $lastError'
          '${lastStack != null ? '\n$lastStack' : ''}',
    );
  }

  /// Open a specific [vendor] for [cfg.codec].
  ///
  /// [existingD3d11Device] — optional `ID3D11Device*` pointer (as an [int]
  /// address) to inject into FFmpeg's D3D11VA device context instead of
  /// letting FFmpeg create its own device.  Use this when you need both
  /// the encoder and an external GPU API (e.g. Dawn/WebGPU) to operate on
  /// the **same DXGI adapter**, which is required for D3D12→D3D11 NT-handle
  /// texture sharing.  FFmpeg takes ownership (calls `Release()` on cleanup).
  static FfmpegD3d11HwEncoder openWith(
    EncoderConfig cfg,
    D3d11HwVendor vendor, {
    int existingD3d11Device = 0,
    D3d11HwSourceFormat sourceTextureFormat = D3d11HwSourceFormat.bgra,
  }) {
    if (!Platform.isWindows) {
      throw const CodecInitException(
        'ffmpeg-d3d11',
        'D3D11VA encoder is Windows-only',
      );
    }
    final shim = FfmpegShim.tryLoad();
    if (shim == null) {
      throw const CodecInitException(
        'ffmpeg-d3d11',
        'miniav_tools_ffmpeg shim is not loadable',
      );
    }
    final ff = Ffmpeg.instance();
    if (ff == null) {
      throw const CodecInitException('ffmpeg-d3d11', 'FFmpeg not loaded');
    }
    final spec = _findSpec(vendor, cfg.codec);
    if (spec == null) {
      throw CodecInitException(
        'ffmpeg-d3d11',
        '$vendor does not support ${cfg.codec}',
      );
    }
    if (cfg.width > spec.maxWidth || cfg.height > spec.maxHeight) {
      throw CodecInitException(
        'ffmpeg-d3d11',
        '${spec.encoderName} max ${spec.maxWidth}x${spec.maxHeight}, '
            'requested ${cfg.width}x${cfg.height}',
      );
    }
    if (!_encoderPresent(ff, spec.encoderName)) {
      throw CodecInitException(
        'ffmpeg-d3d11',
        '${spec.encoderName} not present in this FFmpeg build',
      );
    }

    // 1) Create (or inject) a D3D11VA hardware device.
    //
    // When `existingD3d11Device` is non-zero we use the alloc+set+init path
    // so that FFmpeg's D3D11 device is on the SAME DXGI adapter as an
    // external GPU API (e.g. Dawn/WebGPU).  Cross-adapter NT-handle sharing
    // always fails with E_INVALIDARG; same-adapter sharing works fine.
    //
    // When no device is provided we fall back to av_hwdevice_ctx_create with
    // a NULL device string so FFmpeg picks adapter 0 (the display adapter).
    Pointer<Void> hwDeviceRef;
    if (existingD3d11Device != 0) {
      // Allocate an empty AV_HWDEVICE_TYPE_D3D11VA context, inject the
      // caller's ID3D11Device, then initialise (FFmpeg creates a context).
      final allocRef = ff.avHwdeviceCtxAlloc(kAvHwdeviceTypeD3d11Va);
      if (allocRef == nullptr) {
        throw const CodecInitException(
          'ffmpeg-d3d11',
          'av_hwdevice_ctx_alloc(D3D11VA) returned NULL',
        );
      }
      shim.d3d11SetDevice(
        allocRef,
        Pointer<Void>.fromAddress(existingD3d11Device),
      );
      final initRet = ff.avHwdeviceCtxInit(allocRef);
      if (initRet < 0) {
        // av_buffer_unref to free the alloc
        final rp = calloc<Pointer<Void>>()..value = allocRef;
        ff.avBufferUnref(rp);
        calloc.free(rp);
        throw CodecInitException(
          'ffmpeg-d3d11',
          'av_hwdevice_ctx_init(D3D11VA, injected device): '
              '${ff.strError(initRet)} ($initRet)',
        );
      }
      hwDeviceRef = allocRef;
    } else {
      // Let FFmpeg pick adapter 0 (the display adapter).
      final outRef = calloc<Pointer<Void>>();
      final createRet = ff.avHwdeviceCtxCreate(
        outRef,
        kAvHwdeviceTypeD3d11Va,
        nullptr,
        nullptr,
        0,
      );
      hwDeviceRef = outRef.value;
      calloc.free(outRef);
      if (createRet < 0 || hwDeviceRef == nullptr) {
        throw CodecInitException(
          'ffmpeg-d3d11',
          'av_hwdevice_ctx_create(D3D11VA): ${ff.strError(createRet)} '
              '($createRet). No D3D11-capable adapter or driver too old.',
        );
      }
    }

    Pointer<Void> hwFramesRef = nullptr;
    Pointer<AVCodecContext> codecCtx = nullptr;
    Pointer<AVPacket> packet = nullptr;

    try {
      final d3dDevice = shim.d3d11GetDevice(hwDeviceRef);
      final d3dContext = shim.d3d11GetContext(hwDeviceRef);
      if (d3dDevice == nullptr || d3dContext == nullptr) {
        throw const CodecInitException(
          'ffmpeg-d3d11',
          'shim could not retrieve ID3D11Device/Context from FFmpeg-owned '
              'AVHWDeviceContext (corrupt or wrong-platform shim build)',
        );
      }

      // Resolve AV_PIX_FMT_D3D11 dynamically (enum values shift between
      // libavutil majors). Fall back to the documented value if name lookup
      // fails — that path also fails the encoder open, which is fine.
      final d3dName = 'd3d11'.toNativeUtf8();
      var d3dPixFmt = ff.avGetPixFmtByName(d3dName);
      calloc.free(d3dName);
      if (d3dPixFmt < 0) d3dPixFmt = _avPixFmtD3d11Fallback;

      // SW-format: this is the DXGI texture format used by the hwframes
      // pool the encoder will allocate. CopySubresourceRegion REQUIRES the
      // source and destination to be in the same DXGI type group, so this
      // must match the format of the textures the caller will hand us in
      // encode() — `bgra` for miniav DXGI capture, `rgba` for minigpu's
      // SharedOutputTexture (rgba8unorm storage texture).
      final swFmtName = sourceTextureFormat == D3d11HwSourceFormat.rgba
          ? 'rgba'
          : 'bgra';
      final swNamePtr = swFmtName.toNativeUtf8();
      final bgraFmt = ff.avGetPixFmtByName(swNamePtr);
      calloc.free(swNamePtr);
      if (bgraFmt < 0) {
        throw CodecInitException(
          'ffmpeg-d3d11',
          'av_get_pix_fmt("$swFmtName") failed',
        );
      }
      // 2) Allocate the hwframes pool against the hwdev context.
      hwFramesRef = ff.avHwframeCtxAlloc(hwDeviceRef);
      if (hwFramesRef == nullptr) {
        throw const CodecInitException(
          'ffmpeg-d3d11',
          'av_hwframe_ctx_alloc returned NULL',
        );
      }
      final framesData = shim.hwFramesData(hwFramesRef);
      shim.hwFramesSetParams(
        framesData,
        format: d3dPixFmt,
        swFormat: bgraFmt,
        width: cfg.width,
        height: cfg.height,
        // Pool size must cover encoder reorder + our own in-flight count.
        // 8 is the FFmpeg-recommended floor for typical low-latency configs.
        initialPoolSize: 8,
      );
      final framesInit = ff.avHwframeCtxInit(hwFramesRef);
      if (framesInit < 0) {
        throw CodecInitException(
          'ffmpeg-d3d11',
          'av_hwframe_ctx_init: ${ff.strError(framesInit)} ($framesInit). '
              'Likely BGRA D3D11 textures unsupported on this adapter.',
        );
      }

      // 3) Allocate + configure the encoder's AVCodecContext.
      final namePtr = spec.encoderName.toNativeUtf8();
      Pointer<AVCodec> codec;
      try {
        codec = ff.avcodecFindEncoderByName(namePtr);
      } finally {
        calloc.free(namePtr);
      }
      codecCtx = ff.avcodecAllocContext3(codec);
      if (codecCtx == address(0)) {
        throw const CodecInitException(
          'ffmpeg-d3d11',
          'avcodec_alloc_context3 returned NULL',
        );
      }

      _configureCtx(ff, codecCtx, cfg, spec, d3dPixFmt);

      // Hand the codec ctx its own ref to the hwframes context. The shim
      // calls av_buffer_ref internally — we keep `hwFramesRef` for cleanup.
      shim.setHwFramesCtx(codecCtx.cast<Void>(), hwFramesRef);

      final openRet = ff.avcodecOpen2(codecCtx, codec, nullptr);
      if (openRet < 0) {
        throw CodecInitException(
          'ffmpeg-d3d11',
          'avcodec_open2(${spec.encoderName}) failed: '
              '${ff.strError(openRet)} ($openRet). The vendor runtime '
              '(amfrt64.dll / libmfx / mfreadwrite.dll) may be missing or '
              'incompatible.',
        );
      }

      packet = ff.avPacketAlloc();
      if (packet == address(0)) {
        throw const CodecInitException(
          'ffmpeg-d3d11',
          'av_packet_alloc returned NULL',
        );
      }

      final enc = FfmpegD3d11HwEncoder._(
        ff,
        shim,
        cfg,
        spec,
        codecCtx,
        packet,
        hwDeviceRef,
        hwFramesRef,
        d3dDevice,
        d3dContext,
        d3dPixFmt,
      ).._loadExtraData();
      // Ownership of refs / codec ctx / packet is now in the instance.
      hwDeviceRef = nullptr;
      hwFramesRef = nullptr;
      codecCtx = nullptr;
      packet = nullptr;
      return enc;
    } catch (_) {
      // Best-effort cleanup of partially-initialised state.
      if (packet != nullptr) {
        final pp = calloc<Pointer<AVPacket>>()..value = packet;
        ff.avPacketFree(pp);
        calloc.free(pp);
      }
      if (codecCtx != nullptr) {
        final cp = calloc<Pointer<AVCodecContext>>()..value = codecCtx;
        ff.avcodecFreeContext(cp);
        calloc.free(cp);
      }
      if (hwFramesRef != nullptr) {
        final rp = calloc<Pointer<Pointer<Void>>>().cast<Pointer<Void>>();
        // av_buffer_unref takes AVBufferRef** — wrap manually.
        final wrap = calloc<Pointer<Void>>()..value = hwFramesRef;
        ff.avBufferUnref(wrap);
        calloc.free(wrap);
        calloc.free(rp);
      }
      if (hwDeviceRef != nullptr) {
        final wrap = calloc<Pointer<Void>>()..value = hwDeviceRef;
        ff.avBufferUnref(wrap);
        calloc.free(wrap);
      }
      rethrow;
    }
  }

  static void _configureCtx(
    Ffmpeg ff,
    Pointer<AVCodecContext> ctx,
    EncoderConfig cfg,
    _D3d11Spec spec,
    int d3dPixFmt,
  ) {
    final ctxV = ctx.cast<Void>();

    void setStr(String key, String val) {
      final k = key.toNativeUtf8();
      final v = val.toNativeUtf8();
      try {
        ff.avOptSet(ctxV, k, v, 0);
      } finally {
        calloc.free(k);
        calloc.free(v);
      }
    }

    void setIntStrict(String key, int val) {
      final k = key.toNativeUtf8();
      try {
        final r = ff.avOptSetInt(ctxV, k, val, 0);
        if (r < 0) {
          throw CodecInitException(
            'ffmpeg-d3d11',
            'av_opt_set_int($key=$val): ${ff.strError(r)} ($r)',
          );
        }
      } finally {
        calloc.free(k);
      }
    }

    void setQ(String key, int num, int den) {
      final k = key.toNativeUtf8();
      final r = calloc<AVRational>();
      r.ref
        ..num = num
        ..den = den;
      try {
        final ret = ff.avOptSetQ(ctxV, k, r.ref, 0);
        if (ret < 0) {
          throw CodecInitException(
            'ffmpeg-d3d11',
            'av_opt_set_q($key=$num/$den): ${ff.strError(ret)} ($ret)',
          );
        }
      } finally {
        calloc.free(k);
        calloc.free(r);
      }
    }

    setStr('video_size', '${cfg.width}x${cfg.height}');

    // Pixel format MUST be the hardware enum AV_PIX_FMT_D3D11 — that is
    // how the codec knows to consume textures rather than CPU planes.
    final pkKey = 'pixel_format'.toNativeUtf8();
    try {
      final r = ff.avOptSetPixelFmt(ctxV, pkKey, d3dPixFmt, 1);
      if (r < 0) {
        throw CodecInitException(
          'ffmpeg-d3d11',
          'av_opt_set_pixel_fmt(d3d11): ${ff.strError(r)} ($r)',
        );
      }
    } finally {
      calloc.free(pkKey);
    }

    setIntStrict('b', cfg.bitrateBps);
    if (cfg.gopLength > 0) setIntStrict('g', cfg.gopLength);
    setIntStrict('bf', cfg.bFrameCount);
    setQ('time_base', cfg.frameRateDenominator, cfg.frameRateNumerator);

    final fr = calloc<AVRational>();
    fr.ref
      ..num = cfg.frameRateNumerator
      ..den = cfg.frameRateDenominator;
    final frKey = 'framerate'.toNativeUtf8();
    ff.avOptSetQ(ctxV, frKey, fr.ref, 0);
    calloc.free(frKey);
    calloc.free(fr);

    if (cfg.backendOptions['global_header'] == '1') {
      setStr('flags', '+global_header');
    }

    final defaults = <String, String>{...spec.defaults};
    if (cfg.rateControl == RateControl.crf && cfg.crfQuality != null) {
      switch (spec.vendor) {
        case D3d11HwVendor.nvenc:
          // NVENC: 'cq' is constant-quality VBR, 'qp' is fixed-QP CQP.
          // Use cq for CRF semantics (target visual quality, variable bps).
          defaults['rc'] = 'vbr';
          defaults['cq'] = cfg.crfQuality!.toString();
          break;
        case D3d11HwVendor.qsv:
          defaults['global_quality'] = cfg.crfQuality!.toString();
          break;
        case D3d11HwVendor.amf:
          defaults['rc'] = 'cqp';
          defaults['qp_i'] = cfg.crfQuality!.toString();
          defaults['qp_p'] = cfg.crfQuality!.toString();
          break;
        case D3d11HwVendor.mediafoundation:
          break;
      }
    } else if (cfg.rateControl == RateControl.vbr) {
      if (spec.vendor == D3d11HwVendor.amf) {
        defaults.putIfAbsent('rc', () => 'vbr_peak');
      } else if (spec.vendor == D3d11HwVendor.nvenc) {
        defaults['rc'] = 'vbr';
      }
    } else if (cfg.rateControl == RateControl.cbr) {
      if (spec.vendor == D3d11HwVendor.amf) {
        defaults.putIfAbsent('rc', () => 'cbr');
      } else if (spec.vendor == D3d11HwVendor.nvenc) {
        defaults['rc'] = 'cbr';
      }
    }

    defaults.forEach((k, v) {
      if (!cfg.backendOptions.containsKey(k)) setStr(k, v);
    });
    cfg.backendOptions.forEach((k, v) {
      if (k == 'global_header' || k == 'zerocopy') return;
      setStr(k, v);
    });
  }

  // --- PlatformEncoder ------------------------------------------------------

  @override
  CodecExtraData? get extraData => _extraData;

  @override
  Future<void> requestKeyframe() async {
    _forceKeyframe = true;
  }

  @override
  Future<EncodedPacket?> encode(FrameSource frame) async {
    _checkOpen();

    // There are two ways the caller can supply a GPU-side D3D11 texture:
    //
    //   (A) D3D11TextureFrameSource: `texturePtr` is an already-opened
    //       ID3D11Texture2D* that lives on the SAME ID3D11Device as this
    //       encoder. We use it directly — no OpenSharedResource1.
    //
    //   (B) MiniAVBufferSource (gpuD3D11Handle): `nativeHandles[0]` is an
    //       NT HANDLE for a process-shared D3D11 texture. We must call
    //       OpenSharedResource1 to materialise it on our own device, and
    //       Release the resulting interface after the per-frame copy.
    //
    // In both cases we do GPU-only CopySubresourceRegion + fence into a
    // pool-allocated AVFrame, then send to the codec.
    Pointer<Void> srcTex = nullptr;
    bool ownsSrcTex = false; // true => Release after use
    int subresource = 0;

    switch (frame) {
      case D3D11TextureFrameSource():
        if (frame.texturePtr == 0) {
          throw const CodecRuntimeException(
            'ffmpeg-d3d11',
            'D3D11TextureFrameSource has null texturePtr',
          );
        }
        srcTex = Pointer<Void>.fromAddress(frame.texturePtr);
        subresource = frame.subresourceIndex;
        ownsSrcTex = false;
        break;
      case MiniAVBufferSource():
        final ntHandle = _extractNtHandle(frame);
        if (ntHandle == nullptr) {
          throw const CodecRuntimeException(
            'ffmpeg-d3d11',
            'MiniAVBufferSource for D3D11 zero-copy encoder requires '
                'contentType=gpuD3D11Handle and a non-null NT handle in '
                'nativeHandles[0].',
          );
        }
        subresource = _extractSubresourceIndex(frame);
        // Open the NT-shared handle on FFmpeg's device. Each open returns
        // a fresh ID3D11Texture2D* with refcount 1 — we MUST Release it
        // before the next frame (failing to do so leaks GPU memory and
        // eventually crashes the driver after a few thousand frames).
        srcTex = _shim.d3d11OpenSharedHandle(_d3dDevice, ntHandle);
        if (srcTex == nullptr) {
          throw const CodecRuntimeException(
            'ffmpeg-d3d11',
            'OpenSharedResource1 failed — handle may be from a different '
                'D3D11 adapter or already closed',
          );
        }
        ownsSrcTex = true;
        break;
      default:
        throw const CodecRuntimeException(
          'ffmpeg-d3d11',
          'D3D11 zero-copy encoder requires a D3D11TextureFrameSource OR a '
              'MiniAVBufferSource with contentType=gpuD3D11Handle. Use '
              'FfmpegHwEncoder for CPU-input frames.',
        );
    }

    if (frame.width != _cfg.width || frame.height != _cfg.height) {
      if (ownsSrcTex) _shim.d3d11Release(srcTex);
      throw CodecRuntimeException(
        'ffmpeg-d3d11',
        'Frame ${frame.width}x${frame.height} != encoder '
            '${_cfg.width}x${_cfg.height}',
      );
    }

    Pointer<AVFrame> hwFrame = nullptr;
    try {
      hwFrame = _ff.avFrameAlloc();
      if (hwFrame == address(0)) {
        throw const CodecRuntimeException(
          'ffmpeg-d3d11',
          'av_frame_alloc returned NULL',
        );
      }

      // av_hwframe_get_buffer pulls a free pool texture into the AVFrame.
      // After this call: data[0]=ID3D11Texture2D*, data[1]=subresource idx
      // (as integer cast to pointer), hw_frames_ctx is bound.
      final gb = _ff.avHwframeGetBuffer(_hwFramesRef, hwFrame, 0);
      if (gb < 0) {
        throw CodecRuntimeException(
          'ffmpeg-d3d11',
          'av_hwframe_get_buffer: ${_ff.strError(gb)} ($gb). Pool exhausted '
              '— consumer is not draining packets fast enough.',
        );
      }

      // Pure GPU copy + fence: the shim issues CopySubresourceRegion then
      // waits on a D3D11_QUERY_EVENT before returning.
      final dstTex = hwFrame.ref.data0.cast<Void>();
      final dstSlice = hwFrame.ref.data1.address;
      _shim.d3d11CopyResource(
        _d3dDevice,
        _d3dContext,
        dstTex,
        dstSlice,
        srcTex,
        subresource,
      );

      hwFrame.ref
        ..width = _cfg.width
        ..height = _cfg.height
        ..format = _d3dPixFmt
        ..pts = _nextPts++
        ..pictType = _forceKeyframe ? 1 /* AV_PICTURE_TYPE_I */ : 0;
      _forceKeyframe = false;

      final sendRet = _ff.avcodecSendFrame(_codecCtx, hwFrame);
      if (sendRet < 0 && sendRet != kAvErrorEAgain) {
        throw CodecRuntimeException(
          'ffmpeg-d3d11',
          'avcodec_send_frame: ${_ff.strError(sendRet)} ($sendRet)',
        );
      }
    } finally {
      if (hwFrame != nullptr) {
        _ff.avFrameUnref(hwFrame);
        final fp = calloc<Pointer<AVFrame>>()..value = hwFrame;
        _ff.avFrameFree(fp);
        calloc.free(fp);
      }
      if (ownsSrcTex && srcTex != nullptr) {
        _shim.d3d11Release(srcTex);
      }
    }

    return _drainOne();
  }

  @override
  Future<List<EncodedPacket>> flush() async {
    _checkOpen();
    final ret = _ff.avcodecSendFrame(_codecCtx, nullptr);
    if (ret < 0 && ret != kAvErrorEof) {
      throw CodecRuntimeException(
        'ffmpeg-d3d11',
        'avcodec_send_frame(NULL): ${_ff.strError(ret)}',
      );
    }
    final out = <EncodedPacket>[];
    while (true) {
      final pkt = _drainOne();
      if (pkt == null) break;
      out.add(pkt);
    }
    return out;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final pp = calloc<Pointer<AVPacket>>()..value = _packet;
    final cp = calloc<Pointer<AVCodecContext>>()..value = _codecCtx;
    try {
      _ff.avPacketFree(pp);
      _ff.avcodecFreeContext(cp);
    } finally {
      calloc.free(pp);
      calloc.free(cp);
    }
    if (_hwFramesRef != nullptr) {
      final wrap = calloc<Pointer<Void>>()..value = _hwFramesRef;
      _ff.avBufferUnref(wrap);
      calloc.free(wrap);
      _hwFramesRef = nullptr;
    }
    if (_hwDeviceRef != nullptr) {
      final wrap = calloc<Pointer<Void>>()..value = _hwDeviceRef;
      _ff.avBufferUnref(wrap);
      calloc.free(wrap);
      _hwDeviceRef = nullptr;
    }
  }

  @override
  Pointer<AVCodecContext> get nativeCodecContext => _codecCtx;

  // --- Internals ------------------------------------------------------------

  void _checkOpen() {
    if (_closed) {
      throw const CodecRuntimeException('ffmpeg-d3d11', 'encoder closed');
    }
  }

  Pointer<Void> _extractNtHandle(FrameSource src) {
    switch (src) {
      case D3D11TextureFrameSource():
        return Pointer<Void>.fromAddress(src.texturePtr);
      case MiniAVBufferSource():
        if (src.buffer.contentType != MiniAVBufferContentType.gpuD3D11Handle) {
          return nullptr;
        }
        final video = src.buffer.data;
        if (video is! MiniAVVideoBuffer) return nullptr;
        if (video.nativeHandles.isEmpty) return nullptr;
        final h = video.nativeHandles.first;
        if (h is Pointer) return h.cast<Void>();
        if (h is int) return Pointer<Void>.fromAddress(h);
        return nullptr;
      default:
        return nullptr;
    }
  }

  int _extractSubresourceIndex(FrameSource src) {
    switch (src) {
      case D3D11TextureFrameSource():
        return src.subresourceIndex;
      case MiniAVBufferSource():
        // miniav exposes subresource_index per plane in the C struct, but
        // the Dart wrapper does not propagate it today (planes[0].offset
        // is set instead for DXGI). Default to 0 — the screen capture
        // backend always uses subresource 0.
        return 0;
      default:
        return 0;
    }
  }

  void _loadExtraData() {
    final params = _ff.avcodecParametersAlloc();
    if (params == address(0)) return;
    final pp = calloc<Pointer<AVCodecParameters>>()..value = params;
    try {
      final r = _ff.avcodecParametersFromContext(params, _codecCtx);
      if (r < 0) return;
      final ref = params.ref;
      if (ref.extradataSize > 0 && ref.extradata != address(0)) {
        final bytes = Uint8List(ref.extradataSize);
        bytes.setAll(0, ref.extradata.asTypedList(ref.extradataSize));
        _extraData = CodecExtraData.video(_cfg.codec, bytes);
      }
    } finally {
      _ff.avcodecParametersFree(pp);
      calloc.free(pp);
    }
  }

  EncodedPacket? _drainOne() {
    final ret = _ff.avcodecReceivePacket(_codecCtx, _packet);
    if (ret == kAvErrorEAgain || ret == kAvErrorEof) return null;
    if (ret < 0) {
      throw CodecRuntimeException(
        'ffmpeg-d3d11',
        'avcodec_receive_packet: ${_ff.strError(ret)} ($ret)',
      );
    }
    final p = _packet.ref;
    final bytes = Uint8List(p.size);
    final src = p.data.asTypedList(p.size);
    bytes.setRange(0, p.size, src);

    final usPerFrame =
        (1000000 * _cfg.frameRateDenominator) ~/ _cfg.frameRateNumerator;
    final pkt = EncodedPacket(
      data: bytes,
      ptsUs: p.pts * usPerFrame,
      dtsUs: (p.dts == _avNoPts ? p.pts : p.dts) * usPerFrame,
      durationUs: p.duration * usPerFrame,
      isKeyframe: (p.flags & kPktFlagKey) != 0,
    );
    _ff.avPacketUnref(_packet);
    return pkt;
  }
}

const int _avNoPts = -0x8000000000000000;
