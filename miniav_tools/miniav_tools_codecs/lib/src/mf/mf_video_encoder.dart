/// Media Foundation H.264/HEVC video encoder (Windows) — FFmpeg-free, via the
/// OS encoder MFT. Prefers a HARDWARE (async) MFT and falls back to the sync
/// software one; check [isHardware] / [mftName] for which one is live.
///
/// Input is still system-memory NV12, so a GPU frame is read back before it
/// reaches the encoder — D3D11 zero-copy texture input remains a follow-up, as
/// does an MTA-isolate host (today `open` returns `null` on an STA thread →
/// FFmpeg).
/// [extraData] is the Annex-B parameter-set blob (the MF sequence header, or
/// the sets harvested from the first keyframe when the MFT does not publish
/// one). `Mp4Muxer` converts it to an avcC/hvcC record and rewrites the samples
/// to length-prefixed NALs, so Annex-B is the right thing to hand back here —
/// see `framing/annexb.dart`.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

import '../codecs_native.dart';
import '../framing/annexb.dart';

class MfVideoEncoder implements PlatformEncoder {
  MfVideoEncoder._(this._handle, this._extra, this._codec);

  final Pointer<Void> _handle;
  final VideoCodec _codec;
  CodecExtraData? _extra;

  /// Consecutive `D3D11TextureFrameSource` imports that failed. An isolated
  /// miss is expected — the recorder's idle-frame duplicator re-submits a
  /// texture the GPU processor has already recycled — so those are skipped
  /// quietly. A sustained run is not expected and must not be quiet.
  int _textureMisses = 0;
  static const int _maxTextureMisses = 60;

  /// Raw session handle — for the native diagnostics in
  /// `test/mf_texture_zero_copy_test.dart` only.
  Pointer<Void> get nativeHandleForTest => _handle;

  /// Collect whatever the MFT has ready, returning how many packets arrived —
  /// for `benchmark/mf_texture_bench.dart`, which times submit and drain
  /// separately because they have different costs and different cures.
  int drainForTest() {
    final before = _pending.length;
    _drain();
    return _pending.length - before;
  }

  /// Whether zero-copy D3D11 texture input is available (device manager bound).
  ///
  /// Answered once and remembered. The device manager is bound during
  /// `create` and never rebound, so this is a property of the session — but
  /// [encode] consults it on every frame, and every native call here is
  /// MARSHALLED to the MTA worker thread. A cross-thread round-trip to
  /// re-answer a constant is not just wasted time, it is wasted time whose
  /// cost depends on the scheduler, which is how steady work turns into jitter.
  late final bool supportsD3d11Input = mfencHasD3d11(_handle) != 0;

  /// Whether a hardware MFT was activated (vs the software fallback). Fixed at
  /// activation, so cached for the same reason as [supportsD3d11Input].
  late final bool isHardware = mfencIsHardware(_handle) != 0;

  /// Duck-typed by the recorder's encoder-open log (it probes `vendor` +
  /// `encoderName` via `dynamic` to avoid depending on any codec package), so
  /// a recording log says which MFT actually ran rather than just "mf_encode".
  /// Without these the line cannot distinguish NVENC from the software MFT —
  /// the exact confusion that hid the software fallback for so long.
  String get encoderName => mftName.isEmpty ? 'unknown MFT' : mftName;

  String get vendor => isHardware ? 'hardware' : 'software';

  /// Friendly name of the MFT actually in use, e.g. "NVIDIA H.264 Encoder MFT".
  /// Empty when the driver did not expose one.
  /// Why the most recent D3D11 texture import failed — which step, and the
  /// HRESULT. "could not import" covers several unrelated faults with
  /// different fixes, and this is what distinguishes them.
  String get lastImportError {
    final buf = calloc<Uint8>(224);
    try {
      final n = mfencLastImportError(_handle, buf, 224);
      return n <= 0 ? '' : String.fromCharCodes(buf.asTypedList(n));
    } finally {
      calloc.free(buf);
    }
  }

  String _reasonOrNone() {
    final r = lastImportError;
    return r.isEmpty ? '(native layer recorded none)' : r;
  }

  String get mftName {
    final buf = calloc<Uint8>(128);
    try {
      final n = mfencGetMftName(_handle, buf, 128);
      if (n <= 0) return '';
      return String.fromCharCodes(buf.asTypedList(n));
    } finally {
      calloc.free(buf);
    }
  }

  final List<EncodedPacket> _pending = [];
  final Pointer<MfEncFrame> _frame = calloc<MfEncFrame>();
  bool _forceKeyframe = false;
  bool _closed = false;

  /// [existingD3d11Device] is an `ID3D11Device*` (as an address) to encode on.
  /// Pass the device the incoming frames already live on and the per-frame
  /// shared-handle import disappears — the texture is simply ours. Zero means
  /// "create one", which lands on the DEFAULT adapter and is only correct when
  /// nobody else owns the frames.
  static Future<MfVideoEncoder?> open(EncoderConfig config,
      {int existingD3d11Device = 0}) async {
    if (!Platform.isWindows) return null;
    final codecId = switch (config.codec) {
      VideoCodec.h264 => 0,
      VideoCodec.hevc => 1,
      _ => null,
    };
    if (codecId == null) return null;
    Pointer<Void> h = nullptr;
    try {
      if (mfencHasMft(codecId) == 0) return null;
      h = mfencCreate(
        codecId,
        config.width,
        config.height,
        config.bitrateBps,
        config.frameRateNumerator,
        config.frameRateDenominator,
        config.gopLength,
        Pointer<Void>.fromAddress(existingD3d11Device),
      );
    } catch (_) {
      return null;
    }
    if (h == nullptr) return null;

    // 1 KiB is generous: an H.264 SPS+PPS is tens of bytes, HEVC VPS+SPS+PPS
    // under 200. `get_extradata` returns -1 rather than truncating.
    CodecExtraData? extra;
    const cap = 1024;
    final buf = calloc<Uint8>(cap);
    try {
      final n = mfencGetExtradata(h, buf, cap);
      if (n > 0) {
        extra = CodecExtraData.video(
          config.codec,
          Uint8List.fromList(buf.asTypedList(n)),
        );
      }
    } finally {
      calloc.free(buf);
    }
    return MfVideoEncoder._(h, extra, config.codec);
  }

  /// Re-encode the last submitted frame under [timestampUs] — an idle/CFR
  /// duplicate — without touching the producer's texture.
  ///
  /// Returns null when there is nothing to repeat — no frame submitted yet, or
  /// the last one was a CPU frame (only GPU submissions are retained; keeping
  /// the last system-memory buffer alive would cost real memory for a case the
  /// caller can simply skip).
  /// This exists because expressing "same picture, new timestamp" by
  /// re-importing the producer's surface makes a duplicate depend on a
  /// lifetime the producer controls, and it fires from a timer long after that
  /// surface may have been recycled.
  Future<EncodedPacket?> repeatLastFrame(int timestampUs) async {
    _check();
    final force = _forceKeyframe ? 1 : 0;
    _forceKeyframe = false;
    var r = mfencRepeatLast(_handle, timestampUs, force);
    if (r == 1) {
      _drain();
      r = mfencRepeatLast(_handle, timestampUs, force);
    }
    if (r != 0) {
      _forceKeyframe = force == 1;
      return null;
    }
    _drain();
    return _pending.isEmpty ? null : _pending.removeAt(0);
  }

  @override
  Future<EncodedPacket?> encode(FrameSource frame) async {
    _check();

    // Zero-copy (scale/effects path): a raw texture on the GPU processor's
    // device. Imported cross-device and converted RGBA→NV12 by a D3D11
    // VideoProcessor, entirely in VRAM.
    if (frame is D3D11TextureFrameSource && supportsD3d11Input) {
      final addr = frame.texturePtr;
      if (addr != 0) {
        final force = _forceKeyframe ? 1 : 0;
        _forceKeyframe = false;
        var r = mfencSendD3d11Texture(
            _handle, Pointer<Void>.fromAddress(addr), frame.timestampUs, force);
        if (r == 1) {
          _drain(); // async MFT withholds NeedInput until output is taken
          r = mfencSendD3d11Texture(_handle, Pointer<Void>.fromAddress(addr),
              frame.timestampUs, force);
        }
        if (r == 0) {
          _textureMisses = 0;
          _drain();
          return _pending.isEmpty ? null : _pending.removeAt(0);
        }
        _forceKeyframe = force == 1;
        // A run of misses is a DIFFERENT fault from an occasional one, and
        // silence is only right for the occasional case. Sustained failure
        // means no video at all, and a recording that quietly contains no video
        // track is far worse than one that stops with an error.
        if (++_textureMisses >= _maxTextureMisses) {
          _textureMisses = 0;
          throw CodecRuntimeException(
            'mf_encode',
            'the GPU processor texture could not be imported for '
            '$_maxTextureMisses consecutive frames — systemic, not a dropped '
            'frame. NATIVE REASON: ${_reasonOrNone()}',
          );
        }
        // SKIP this frame — do not throw.
        //
        // Unlike a capture buffer, a processor texture has a bounded lifetime:
        // it comes from a small output ring the GPU processor owns and recycles,
        // and Dawn re-takes ownership between frames (Begin/EndAccess). A caller
        // holding one past its turn — the recorder's idle-frame DUPLICATOR does
        // exactly that, re-encoding `_lastSharedTex` from a timer — will
        // legitimately find it unimportable. That is a frame worth dropping, not
        // a recording worth killing: the live path is unaffected, and throwing
        // here turned an expected miss into repeated exceptions inside a timer
        // callback.
        return null;
      }
    }

    // Zero-copy: a GPU capture buffer carries a shared NT handle in
    // nativeHandles[0]. Feed the texture straight to the encoder — no readback,
    // no memcpy. Falls through to the CPU path when the handle is absent or the
    // encoder has no D3D device bound, so this is always safe to attempt.
    if (frame is MiniAVBufferSource && supportsD3d11Input) {
      // The handle lives on the VIDEO payload, not the envelope; planes[0] is
      // a non-null but EMPTY list on the GPU path, so it is not a discriminator.
      final v = frame.buffer.data;
      final handles = v is MiniAVVideoBuffer ? v.nativeHandles : const [];
      final h0 = handles.isNotEmpty ? handles[0] : null;
      final addr = h0 is int ? h0 : 0;
      if (addr != 0) {
        final force = _forceKeyframe ? 1 : 0;
        _forceKeyframe = false;
        var r = mfencSendD3d11(
            _handle, Pointer<Void>.fromAddress(addr), frame.timestampUs, force);
        if (r == 1) {
          _drain(); // async MFT withholds NeedInput until output is taken
          r = mfencSendD3d11(
              _handle, Pointer<Void>.fromAddress(addr), frame.timestampUs, force);
        }
        if (r == 0) {
          _drain();
          return _pending.isEmpty ? null : _pending.removeAt(0);
        }
        _forceKeyframe = force == 1;
        // r < 0. A GPU-resident buffer has NO CPU pixels — planes[] is empty —
        // so there is nothing to fall back to; `_nv12Bytes` below would throw
        // "needs CPU NV12", which names the symptom and hides the cause. Fail
        // loudly and accurately instead.
        //
        // The likeliest cause is an adapter mismatch: the encoder builds its
        // D3D11 device on the DEFAULT adapter, and on a hybrid machine that may
        // not be the adapter the capture texture lives on, so
        // OpenSharedResource1 refuses the handle. That is systematic, not
        // transient — every frame would fail — so surfacing it on the first
        // frame is better than a silently empty recording.
        if (frame.buffer.contentType != MiniAVBufferContentType.cpu) {
          throw const CodecRuntimeException(
            'mf_encode',
            'could not open the capture texture on the encoder device '
                '(OpenSharedResource1 failed). The frame is GPU-resident, so '
                'there are no CPU pixels to fall back to. Most likely the '
                'encoder device is on a different adapter than the capture; '
                'use the FFmpeg D3D11 encoder on this machine.',
          );
        }
        // A CPU-content buffer that merely carried a stale handle can still go
        // down the readback path below.
      }
    }

    final nv12 = _nv12Bytes(frame);
    final inBuf = calloc<Uint8>(nv12.length);
    inBuf.asTypedList(nv12.length).setAll(0, nv12);
    try {
      final force = _forceKeyframe ? 1 : 0;
      _forceKeyframe = false;
      var r = mfencSendNv12(_handle, inBuf, nv12.length, frame.timestampUs, force);
      if (r == 1) {
        _drain();
        r = mfencSendNv12(_handle, inBuf, nv12.length, frame.timestampUs, force);
      }
      if (r < 0) {
        throw const CodecRuntimeException('mf_encode', 'ProcessInput failed');
      }
      _drain();
      return _pending.isEmpty ? null : _pending.removeAt(0);
    } finally {
      calloc.free(inBuf);
    }
  }

  @override
  Future<List<EncodedPacket>> flush() async {
    _check();
    mfencDrain(_handle);
    _drain();
    final out = List<EncodedPacket>.of(_pending);
    _pending.clear();
    return out;
  }

  void _drain() {
    while (true) {
      final r = mfencReceive(_handle, _frame);
      if (r == 2) continue; // stream change
      if (r != 1) break;
      final f = _frame.ref;
      if (f.size <= 0 || f.data == nullptr) break;
      final data = Uint8List.fromList(f.data.asTypedList(f.size));
      mfencFree(f.data.cast());
      if (_extra == null && f.isKeyframe == 1) _harvestParamSets(data);
      _pending.add(EncodedPacket(
        data: data,
        ptsUs: f.ptsUs,
        dtsUs: f.ptsUs,
        isKeyframe: f.isKeyframe == 1,
      ));
    }
  }

  /// Recover the parameter sets from a keyframe when the MFT published no
  /// `MF_MT_MPEG_SEQUENCE_HEADER`. Some hardware MFTs only fill that attribute
  /// after the first output — and the muxer refuses a video track with no
  /// config record, so a null [extraData] would fail the whole recording.
  /// The sets are repeated in-band on every IDR, so the first keyframe has them.
  void _harvestParamSets(Uint8List keyframe) {
    if (!isAnnexB(keyframe)) return;
    final hevc = _codec == VideoCodec.hevc;
    final sets = BytesBuilder(copy: false);
    for (final nal in splitAnnexB(keyframe)) {
      if (nal.isEmpty) continue;
      final type = hevc ? (nal[0] >> 1) & 0x3F : nal[0] & 0x1F;
      final isParamSet = hevc
          ? (type == 32 || type == 33 || type == 34) // VPS / SPS / PPS
          : (type == 7 || type == 8); // SPS / PPS
      if (!isParamSet) continue;
      sets.add(const [0, 0, 0, 1]);
      sets.add(nal);
    }
    final bytes = sets.toBytes();
    if (bytes.isNotEmpty) _extra = CodecExtraData.video(_codec, bytes);
  }

  /// Extract tightly-packed NV12 bytes from [frame].
  ///
  /// Must cover every kind in `MfEncodeBackend.acceptedFrameSources`, including
  /// the D3D11 one: the zero-copy branch falls through to here when the handle
  /// cannot be opened (a different adapter, say), and throwing at that point
  /// would kill a live recording instead of degrading to a readback.
  Uint8List _nv12Bytes(FrameSource frame) {
    if (frame is CpuFrameSource) {
      return _fromCpu(
          frame.bytes, frame.pixelFormat, frame.width, frame.height,
          frame.strideBytes);
    }
    if (frame is Yuv420pFrameSource) {
      return _i420PlanesToNv12(
          frame.yPlane, frame.uPlane, frame.vPlane, frame.width, frame.height);
    }
    if (frame is MiniAVBufferSource) {
      final v = frame.buffer.data;
      if (v is MiniAVVideoBuffer &&
          frame.buffer.contentType == MiniAVBufferContentType.cpu) {
        return _fromPlanes(v);
      }
    }
    throw UnsupportedFrameSourceException(
      'mf_encode',
      'MF video encode needs CPU NV12/I420 pixels (or a D3D11 shared handle); '
          'got ${frame.runtimeType} / ${frame.pixelFormat}',
    );
  }

  /// Interleaved single-buffer input. NV12 passes through when tightly packed;
  /// I420 is interleaved into NV12.
  Uint8List _fromCpu(Uint8List bytes, MiniAVPixelFormat fmt, int w, int h,
      List<int>? strides) {
    switch (fmt) {
      case MiniAVPixelFormat.nv12:
        // A padded stride would shear the image, so repack rather than trust it.
        final stride = (strides != null && strides.isNotEmpty) ? strides[0] : w;
        if (stride == w) return bytes;
        return _repackNv12(bytes, stride, w, h);
      case MiniAVPixelFormat.i420:
        final ySize = w * h, cSize = (w ~/ 2) * (h ~/ 2);
        if (bytes.length < ySize + 2 * cSize) {
          throw UnsupportedFrameSourceException('mf_encode',
              'I420 frame is ${bytes.length} B, need ${ySize + 2 * cSize}');
        }
        return _i420PlanesToNv12(
          Uint8List.sublistView(bytes, 0, ySize),
          Uint8List.sublistView(bytes, ySize, ySize + cSize),
          Uint8List.sublistView(bytes, ySize + cSize, ySize + 2 * cSize),
          w,
          h,
        );
      default:
        throw UnsupportedFrameSourceException('mf_encode',
            'MF video encode needs NV12 or I420 pixels; got $fmt');
    }
  }

  /// Per-plane CPU buffer (miniav capture). Honours each plane's stride.
  Uint8List _fromPlanes(MiniAVVideoBuffer v) {
    final w = v.width, h = v.height;
    Uint8List plane(int i) {
      final p = i < v.planes.length ? v.planes[i] : null;
      if (p == null || p.isEmpty) {
        throw UnsupportedFrameSourceException(
            'mf_encode', 'CPU buffer is missing plane $i');
      }
      return p;
    }

    int stride(int i, int fallback) =>
        (i < v.strideBytes.length && v.strideBytes[i] > 0)
            ? v.strideBytes[i]
            : fallback;

    switch (v.pixelFormat) {
      case MiniAVPixelFormat.nv12:
        final y = plane(0), uv = plane(1);
        final out = Uint8List(w * h + w * (h ~/ 2));
        _copyRows(y, stride(0, w), out, 0, w, h);
        _copyRows(uv, stride(1, w), out, w * h, w, h ~/ 2);
        return out;
      case MiniAVPixelFormat.i420:
        final cw = w ~/ 2, ch = h ~/ 2;
        final y = plane(0), u = plane(1), vP = plane(2);
        // Tighten each plane to its natural stride before interleaving.
        final yt = Uint8List(w * h), ut = Uint8List(cw * ch),
            vt = Uint8List(cw * ch);
        _copyRows(y, stride(0, w), yt, 0, w, h);
        _copyRows(u, stride(1, cw), ut, 0, cw, ch);
        _copyRows(vP, stride(2, cw), vt, 0, cw, ch);
        return _i420PlanesToNv12(yt, ut, vt, w, h);
      default:
        throw UnsupportedFrameSourceException('mf_encode',
            'MF video encode needs NV12 or I420 planes; got ${v.pixelFormat}');
    }
  }

  static void _copyRows(Uint8List src, int srcStride, Uint8List dst,
      int dstOffset, int rowBytes, int rows) {
    if (srcStride == rowBytes && src.length >= rowBytes * rows) {
      dst.setRange(dstOffset, dstOffset + rowBytes * rows, src);
      return;
    }
    for (var r = 0; r < rows; r++) {
      final s = r * srcStride;
      if (s + rowBytes > src.length) {
        throw UnsupportedFrameSourceException(
            'mf_encode', 'plane is short: row $r of $rows overruns the buffer');
      }
      dst.setRange(dstOffset + r * rowBytes, dstOffset + (r + 1) * rowBytes,
          src, s);
    }
  }

  static Uint8List _repackNv12(Uint8List src, int stride, int w, int h) {
    final out = Uint8List(w * h + w * (h ~/ 2));
    _copyRows(src, stride, out, 0, w, h);
    _copyRows(Uint8List.sublistView(src, stride * h), stride, out, w * h, w,
        h ~/ 2);
    return out;
  }

  /// I420 (planar U then V) → NV12 (Y plane then interleaved UV).
  static Uint8List _i420PlanesToNv12(
      Uint8List y, Uint8List u, Uint8List v, int w, int h) {
    final ySize = w * h;
    final cw = w ~/ 2, ch = h ~/ 2;
    final out = Uint8List(ySize + 2 * cw * ch);
    out.setRange(0, ySize, y);
    var o = ySize;
    for (var i = 0; i < cw * ch; i++) {
      out[o++] = u[i];
      out[o++] = v[i];
    }
    return out;
  }

  @override
  bool get acceptsYuv420pPlanes => false;

  @override
  bool get supportsGpuBufferInput => false;

  /// True once the MFT has a D3D11 device manager bound, which is what lets
  /// `mfencSendD3d11` open a capture's shared NT handle on our device.
  ///
  /// Shares the `mfenc_submit_texture` tail with the texture path above, which
  /// IS covered by a differential test — so the submit half is known good. The
  /// handle-opening half is still only exercised with a synthetic handle.
  @override
  bool get supportsD3d11SharedHandleInput => supportsD3d11Input;

  /// A `D3D11TextureFrameSource` carries a raw texture pointer on the GPU
  /// processor's (Dawn's) device. `mfencSendD3d11Texture` imports it
  /// cross-device (`GetSharedHandle` + `OpenSharedResource`, which minigpu's
  /// `D3D11_RESOURCE_MISC_SHARED` output textures support) and converts
  /// RGBA→NV12 with a D3D11 VideoProcessor — all in VRAM, no readback.
  ///
  /// Verified by `test/mf_texture_zero_copy_test.dart`, which encodes a
  /// gradient and a flat-grey source through this path and requires the output
  /// sizes to differ. That differential matters: an earlier version of this
  /// code produced byte-identical output for both and would have recorded blank
  /// video, while reporting success at every step.
  @override
  bool get supportsD3d11TextureInput => supportsD3d11Input;

  @override
  Future<void> requestKeyframe() async {
    _forceKeyframe = true;
  }

  @override
  CodecExtraData? get extraData => _extra;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    mfencDestroy(_handle);
    calloc.free(_frame);
  }

  void _check() {
    if (_closed) throw StateError('MfVideoEncoder has been closed.');
  }
}
