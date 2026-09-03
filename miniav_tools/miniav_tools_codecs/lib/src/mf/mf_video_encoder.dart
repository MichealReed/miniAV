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

class MfVideoEncoder implements PlatformEncoder, Finalizable {
  MfVideoEncoder._(this._handle, this._extra, this._codec) {
    // The owner is supposed to call close(), but an exception thrown out of
    // encode() (the miss counters below do exactly that) can skip it, and the
    // native session owns an MFT, a D3D11 device and up to four pinned producer
    // textures. Without a finalizer that leaks for the life of the process.
    _sessionFinalizer.attach(this, _handle, detach: this);
    _frameFinalizer.attach(this, _frame.cast(), detach: this);
  }

  static final NativeFinalizer _sessionFinalizer = NativeFinalizer(
      Native.addressOf<NativeFunction<Void Function(Pointer<Void>)>>(
          mfencDestroy));
  static final NativeFinalizer _frameFinalizer =
      NativeFinalizer(calloc.nativeFree);

  final Pointer<Void> _handle;
  final VideoCodec _codec;
  CodecExtraData? _extra;

  /// Consecutive `D3D11TextureFrameSource` imports that FAILED (native r < 0).
  /// An isolated miss is expected — the recorder's idle-frame duplicator
  /// re-submits a texture the GPU processor has already recycled — so those are
  /// skipped quietly. A sustained run is not expected and must not be quiet.
  int _textureMisses = 0;
  static const int _maxTextureMisses = 60;

  /// Consecutive frames the encoder REFUSED (native r == 1). A different fault
  /// with a different cure: the MFT is holding its input surfaces and is not
  /// giving them back, which is back-pressure, not a broken import. Counting
  /// the two together is how a merely slow MFT came to report "the texture
  /// could not be imported ... NATIVE REASON: (native layer recorded none)" —
  /// wrong about the cause and wrong about the diagnostics.
  int _textureBackpressure = 0;
  static const int _maxTextureBackpressure = 120;

  /// Raw session handle — for the native diagnostics in
  /// `test/mf_texture_zero_copy_test.dart` only.
  Pointer<Void> get nativeHandleForTest {
    _check();
    return _handle;
  }

  /// Collect whatever the MFT has ready, returning how many packets arrived —
  /// for `benchmark/mf_texture_bench.dart`, which times submit and drain
  /// separately because they have different costs and different cures.
  int drainForTest() {
    _check();
    final before = _pending.length;
    _drain();
    return _pending.length - before;
  }

  /// Forget every producer texture the native import cache is holding.
  ///
  /// Call this whenever the producer's textures stop being valid — a resolution
  /// change, a rebuilt texture ring, a swapped source. The cache keys on the
  /// texture POINTER and pins each one with a reference, so a stale hit cannot
  /// happen; what can happen without this call is that up to four of the
  /// producer's surfaces stay resident in VRAM after it is done with them.
  ///
  /// Also drops the retained repeat source, so [repeatLastFrame] returns null
  /// until the next real frame — a duplicate of a pre-change picture is worse
  /// than a skipped CFR slot. Returns the number of cache entries released.
  int invalidateImports() {
    _check();
    return mfencInvalidateImports(_handle);
  }

  /// Whether zero-copy D3D11 texture input is available (device manager bound).
  ///
  /// Answered once and remembered. The device manager is bound during
  /// `create` and never rebound, so this is a property of the session — but
  /// [encode] consults it on every frame, and every native call here is
  /// MARSHALLED to the MTA worker thread. A cross-thread round-trip to
  /// re-answer a constant is not just wasted time, it is wasted time whose
  /// cost depends on the scheduler, which is how steady work turns into jitter.
  late final bool supportsD3d11Input = _readSupportsD3d11();

  bool _readSupportsD3d11() {
    _check();
    return mfencHasD3d11(_handle) != 0;
  }

  /// Whether a hardware MFT was activated (vs the software fallback). Fixed at
  /// activation, so cached for the same reason as [supportsD3d11Input].
  late final bool isHardware = _readIsHardware();

  bool _readIsHardware() {
    _check();
    return mfencIsHardware(_handle) != 0;
  }

  /// The `ID3D11Device*` this encoder is bound to, as an address.
  ///
  /// Compare against the device the frame producer uses. When they match, a GPU
  /// frame needs no import at all; when they differ, every frame depends on the
  /// producer's texture being shareable -- and whether that was the case has
  /// been the difference between a working recording and one silently missing
  /// its video track. Surfaced because a log cannot otherwise answer it.
  late final int boundD3d11Device = _readBoundDevice();

  int _readBoundDevice() {
    _check();
    return mfencGetDevice(_handle).address;
  }

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
    // Guarded like every other native read: this one is called from ERROR
    // paths, which is exactly where an owner is most likely to have closed the
    // session already — and a freed pointer handed to native strlen is a
    // use-after-free, not an empty string.
    _check();
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
    _check();
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

  /// Frames the MFT ACCEPTED (a native send returned 0), and packets it has
  /// handed back, over the life of the session. Not statistics: [flush] uses
  /// them to tell a completed drain that legitimately had nothing left apart
  /// from an encoder that swallowed every frame it was given. The second is a
  /// recording with no video track and success reported at every step, which is
  /// the one answer this class must never give quietly.
  int _submitted = 0;
  int _produced = 0;

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
    _submitted++;
    _drain();
    return _pending.isEmpty ? null : _pending.removeAt(0);
  }

  /// Encode one frame, returning a packet IF one happened to be ready.
  ///
  /// A null answer is not "this frame produced nothing": a hardware MFT is
  /// ASYNC and holds two to four frames, so a frame's packet comes back from
  /// whichever call is in flight when the MFT raises METransformHaveOutput —
  /// this one, a later [encode], or [flush]. Which one is genuinely
  /// timing-dependent (the same frame comes back from `encode` on a busy
  /// machine and from `flush` on an idle one), so a caller must ACCUMULATE both
  /// or it will drop packets the encoder handed it. Counting only what [flush]
  /// returns is the classic version of that mistake.
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
          _textureBackpressure = 0;
          _submitted++;
          _drain();
          return _pending.isEmpty ? null : _pending.removeAt(0);
        }
        _forceKeyframe = force == 1;
        // r == 1 is BACK-PRESSURE, not a failed import: the MFT is still
        // holding every staging surface, or never issued input credit. Its cure
        // is draining, which the retry above already attempted, and its
        // diagnosis is completely different — so it gets its own counter and
        // its own message rather than being reported as an import failure.
        if (r > 0) {
          if (++_textureBackpressure >= _maxTextureBackpressure) {
            _textureBackpressure = 0;
            throw CodecRuntimeException(
              'mf_encode',
              'the MF encoder refused input for $_maxTextureBackpressure '
              'consecutive frames — it is holding its input surfaces and not '
              'producing output, so this is not a dropped frame. '
              'NATIVE REASON: ${_reasonOrNone()}',
            );
          }
          return null;
        }
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
          _submitted++;
          _drain();
          return _pending.isEmpty ? null : _pending.removeAt(0);
        }
        _forceKeyframe = force == 1;
        // r == 1 is back-pressure, and the throw below is for a BROKEN import.
        // Reporting "could not open the capture texture" because the MFT was
        // momentarily full names a fault that did not happen and kills a
        // recording that was merely running behind. Drop the frame instead.
        if (r > 0) return null;
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
          throw CodecRuntimeException(
            'mf_encode',
            'could not open the capture texture on the encoder device. The '
            'frame is GPU-resident, so there are no CPU pixels to fall back '
            'to. Most likely the encoder device is on a different adapter '
            'than the capture; use the FFmpeg D3D11 encoder on this machine. '
            'NATIVE REASON: ${_reasonOrNone()}',
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
        // Naming ProcessInput here was a guess, and a wrong one: at odd frame
        // sizes the native side rejected the buffer LENGTH and never reached
        // ProcessInput at all, so the message sent every reader to the wrong
        // place. The native layer records which step actually failed.
        throw CodecRuntimeException(
          'mf_encode',
          'the MF encoder rejected a ${nv12.length} B NV12 frame at '
          '${frame.width}x${frame.height}. NATIVE REASON: ${_reasonOrNone()}',
        );
      }
      if (r == 0) _submitted++;
      _drain();
      return _pending.isEmpty ? null : _pending.removeAt(0);
    } finally {
      calloc.free(inBuf);
    }
  }

  /// Longest a flush will wait WITHOUT PROGRESS before calling the MFT wedged.
  ///
  /// Measured from the last packet the drain handed back, not from the start of
  /// the flush: every poll is marshalled to the one process-wide MTA worker, so
  /// on a machine running several encoder sessions at once a perfectly healthy
  /// drain can spend far longer than this in total while still delivering. An
  /// absolute budget turns that into a spurious failure; "nothing at all for
  /// two seconds" is the condition that actually means stuck.
  static const Duration _flushTimeout = Duration(seconds: 2);

  /// Drain the MFT and return the packets it had not already handed back.
  ///
  /// EMPTY IS A LEGITIMATE ANSWER and does not mean the tail was lost: an async
  /// hardware MFT can raise METransformHaveOutput while an [encode] call is
  /// still in flight, in which case that call already returned the packet.
  /// Callers must sum both — see [encode].
  ///
  /// Throws [CodecRuntimeException] rather than returning silently when the
  /// drain does not complete, or when the session accepted frames and the MFT
  /// produced nothing for any of them across its whole life. Those two are the
  /// real "succeeded and recorded nothing" faults, and a caller cannot tell
  /// them apart from an ordinary empty list.
  @override
  Future<List<EncodedPacket>> flush() async {
    _check();
    mfencDrain(_handle);
    _drain();
    // Do NOT stop because receive() returned nothing.
    //
    // For an async (hardware) MFT that answer only means "nothing ready at this
    // instant" — the drain is still running and the encoder is routinely
    // holding two to four frames. Stopping there silently truncated the end of
    // every recording. `mfencDrainState` reports 1 only once
    // METransformDrainComplete has landed AND every output it raised has been
    // taken, and each call waits a bounded ~8 ms natively (no blocking
    // GetEvent, no Sleep), so this loop cannot spin hot. That wait is
    // drain-specific on purpose: the submit-side one wakes on
    // METransformNeedInput, which is left over at flush time and would make
    // every poll here return instantly.
    final sw = Stopwatch()..start();
    var seen = _produced;
    var state = mfencDrainState(_handle);
    while (state != 1) {
      _drain();
      if (_produced != seen) {
        seen = _produced;
        sw.reset(); // progress — the drain is not wedged, only slow
      } else if (sw.elapsed >= _flushTimeout) {
        break;
      }
      state = mfencDrainState(_handle);
    }
    _drain();
    if (state != 1) {
      // _pending is deliberately LEFT INTACT: the packets that did come out are
      // real, and a caller that wants to salvage them can flush again. What it
      // must not get is this list dressed up as a completed drain.
      throw CodecRuntimeException(
        'mf_encode',
        'the MF encoder never finished draining — no output for '
        '${_flushTimeout.inSeconds}s after ${_pending.length} packet(s). The '
        'tail of this stream is incomplete. NATIVE REASON: ${_reasonOrNone()}',
      );
    }
    if (_submitted > 0 && _produced == 0) {
      throw CodecRuntimeException(
        'mf_encode',
        'the MF encoder accepted $_submitted frame(s) and produced no packets '
        'at all, yet reports its drain complete. This is an empty video track, '
        'not an empty flush. NATIVE REASON: ${_reasonOrNone()}',
      );
    }
    final out = List<EncodedPacket>.of(_pending);
    _pending.clear();
    return out;
  }

  /// Bound on consecutive `MF_E_TRANSFORM_STREAM_CHANGE` answers. The native
  /// side renegotiates the output type and gives up after a few tries; this is
  /// the belt-and-braces half, so a stuck MFT cannot make [_drain] a hot loop.
  static const int _maxStreamChanges = 8;

  void _drain() {
    var changes = 0;
    while (true) {
      final r = mfencReceive(_handle, _frame);
      if (r == 2) {
        // The MFT renegotiated its output type natively; try again for output.
        if (++changes >= _maxStreamChanges) break;
        continue;
      }
      if (r != 1) break;
      final f = _frame.ref;
      if (f.size <= 0 || f.data == nullptr) break;
      final data = Uint8List.fromList(f.data.asTypedList(f.size));
      mfencFree(f.data.cast());
      if (_extra == null && f.isKeyframe == 1) _harvestParamSets(data);
      _produced++;
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
      // The factory documents tightly-packed (width/2)x(height/2) chroma.
      return _i420PlanesToNv12(frame.yPlane, frame.uPlane, frame.vPlane,
          frame.width, frame.height, frame.width ~/ 2, frame.height ~/ 2);
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

  /// NV12 row stride for a frame [w] px wide.
  ///
  /// 4:2:0 chroma arrives in U,V PAIRS, so a row is an even number of bytes and
  /// an odd width rounds up — the same `(w + 1) & ~1` convention the native
  /// staging texture ring uses, because both sides have to agree byte for byte.
  static int _nv12Stride(int w) => (w + 1) & ~1;

  /// Chroma rows in an NV12 frame [h] px tall — CEIL(h/2), not floor.
  ///
  /// This is the odd-height bug in one line: at 1119 the floored count is 559
  /// instead of 560, the buffer came up one chroma row (2576 B at 2576x1119)
  /// short of what native required, and every single frame was rejected before
  /// ProcessInput was ever reached.
  static int _nv12ChromaRows(int h) => (h + 1) >> 1;

  /// Total bytes of the NV12 layout the native side expects. Mirrors
  /// `mfenc_nv12_size` in `native/mf_encoder.c`.
  static int _nv12Size(int w, int h) =>
      _nv12Stride(w) * h + _nv12Stride(w) * _nv12ChromaRows(h);

  /// Interleaved single-buffer input. NV12 passes through when it is already in
  /// exactly the expected layout; anything else is repacked.
  Uint8List _fromCpu(Uint8List bytes, MiniAVPixelFormat fmt, int w, int h,
      List<int>? strides) {
    switch (fmt) {
      case MiniAVPixelFormat.nv12:
        // A padded stride would shear the image, so repack rather than trust
        // it — and so would a buffer built on the floored chroma height.
        final stride = (strides != null && strides.isNotEmpty) ? strides[0] : w;
        if (stride == _nv12Stride(w) && bytes.length >= _nv12Size(w, h)) {
          return bytes;
        }
        return _repackNv12(bytes, stride, w, h);
      case MiniAVPixelFormat.i420:
        // Source chroma planes use the FLOORED dimensions, which is the I420
        // convention this facade documents; the NV12 side needs the ceiled
        // ones, so the last column/row is replicated rather than left black.
        final scw = w ~/ 2, sch = h ~/ 2;
        final ySize = w * h, cSize = scw * sch;
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
          scw,
          sch,
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

    final dstStride = _nv12Stride(w);
    switch (v.pixelFormat) {
      case MiniAVPixelFormat.nv12:
        final y = plane(0), uv = plane(1);
        final cRows = _nv12ChromaRows(h);
        final out = Uint8List(_nv12Size(w, h));
        final uvStride = stride(1, dstStride);
        _copyRowsPadded(y, stride(0, w), h, out, 0, w, dstStride, h, 1);
        _copyRowsPadded(
            uv,
            uvStride,
            uvStride > 0 ? uv.length ~/ uvStride : 0,
            out,
            dstStride * h,
            uvStride >= dstStride ? dstStride : (uvStride & ~1),
            dstStride,
            cRows,
            2);
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
        return _i420PlanesToNv12(yt, ut, vt, w, h, cw, ch);
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

  /// Copy [rows] rows of [srcRowBytes] into a destination whose rows are
  /// [dstStride] wide, replicating the last [unit] bytes across the pad and the
  /// previous row when the source runs out ([srcRows] < [rows]).
  ///
  /// Both kinds of shortfall are real, not defensive padding: NV12 demands an
  /// even width and an even number of luma rows' worth of chroma, while capture
  /// sizes are arbitrary (2576x1119 is a real window size). Replicating beats
  /// zero-filling — a black edge column is a visible artifact, a duplicated one
  /// is not. [unit] is 1 for luma and 2 for an interleaved UV row, so a pad
  /// never splits a chroma pair.
  static void _copyRowsPadded(Uint8List src, int srcStride, int srcRows,
      Uint8List dst, int dstOffset, int srcRowBytes, int dstStride, int rows,
      int unit) {
    if (srcRows <= 0 || srcRowBytes <= 0) {
      throw UnsupportedFrameSourceException(
          'mf_encode', 'plane is empty: expected $rows x $dstStride B');
    }
    for (var r = 0; r < rows; r++) {
      final d = dstOffset + r * dstStride;
      if (r < srcRows) {
        final s = r * srcStride;
        if (s + srcRowBytes > src.length) {
          throw UnsupportedFrameSourceException('mf_encode',
              'plane is short: row $r of $rows overruns the buffer');
        }
        dst.setRange(d, d + srcRowBytes, src, s);
        for (var x = srcRowBytes; x < dstStride; x++) {
          dst[d + x] = dst[d + x - unit];
        }
      } else {
        dst.setRange(d, d + dstStride, dst, d - dstStride);
      }
    }
  }

  static Uint8List _repackNv12(Uint8List src, int stride, int w, int h) {
    final dstStride = _nv12Stride(w);
    final out = Uint8List(_nv12Size(w, h));
    _copyRowsPadded(src, stride, h, out, 0, w, dstStride, h, 1);
    // Whatever the producer supplied for chroma — which for an odd height is
    // usually one row short — starts right after the luma plane.
    final uvOffset = stride * h;
    final uv = uvOffset < src.length
        ? Uint8List.sublistView(src, uvOffset)
        : Uint8List(0);
    _copyRowsPadded(
        uv,
        stride,
        stride > 0 ? uv.length ~/ stride : 0,
        out,
        dstStride * h,
        stride >= dstStride ? dstStride : (stride & ~1),
        dstStride,
        _nv12ChromaRows(h),
        2);
    return out;
  }

  /// I420 (planar U then V) → NV12 (Y plane then interleaved UV), in the padded
  /// layout native expects. [scw]/[sch] are the SOURCE chroma plane dimensions,
  /// which for an odd-sized frame are the floored ones — the missing column and
  /// row are replicated rather than left black.
  static Uint8List _i420PlanesToNv12(Uint8List y, Uint8List u, Uint8List v,
      int w, int h, int scw, int sch) {
    if (scw <= 0 || sch <= 0) {
      throw UnsupportedFrameSourceException(
          'mf_encode', 'I420 chroma planes are ${scw}x$sch');
    }
    final dstStride = _nv12Stride(w);
    final cw = dstStride >> 1; // chroma sample pairs per destination row
    final ch = _nv12ChromaRows(h);
    final out = Uint8List(_nv12Size(w, h));
    for (var r = 0; r < h; r++) {
      final s = r * w, d = r * dstStride;
      out.setRange(d, d + w, y, s);
      for (var x = w; x < dstStride; x++) {
        out[d + x] = out[d + x - 1];
      }
    }
    var o = dstStride * h;
    for (var r = 0; r < ch; r++) {
      final sr = r < sch ? r : sch - 1;
      for (var c = 0; c < cw; c++) {
        final i = sr * scw + (c < scw ? c : scw - 1);
        out[o++] = u[i];
        out[o++] = v[i];
      }
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
    _sessionFinalizer.detach(this);
    _frameFinalizer.detach(this);
    mfencDestroy(_handle);
    calloc.free(_frame);
  }

  void _check() {
    if (_closed) throw StateError('MfVideoEncoder has been closed.');
  }
}
