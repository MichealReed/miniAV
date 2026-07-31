/// First-party Media Foundation H.264/HEVC video-encode backend (Windows).
///
/// Runs on the OS **hardware** encoder MFT (NVENC / AMF / QSV, whichever the
/// driver exposes) with a software-MFT fallback, entirely FFmpeg-free.
///
/// Priority 55, above FFmpeg's 50. Note that priority is only tiebreak #5 in
/// the negotiator — `isHardware` and `zeroCopy` are ranked first — so
/// [supportsEncode] reporting the hardware path honestly matters far more than
/// the number here. It reports hardware only when the OS actually lists a
/// hardware MFT for the codec, so a box with software-only MF still ranks below
/// a real hardware FFmpeg path.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

import '../codecs_native.dart';
import 'mf_video_encoder.dart';

class MfEncodeBackend extends MiniAVToolsBackend {
  static const String backendName = 'mf_encode';
  static const int defaultPriority = 55;

  static const _codecs = {VideoCodec.h264, VideoCodec.hevc};

  /// Cached per-codec answer to "does this machine expose a hardware encoder
  /// MFT?" — [supportsEncode] is called on every negotiation, and the probe
  /// enumerates MFTs.
  static final Map<VideoCodec, bool> _hwCache = {};

  static int? _codecId(VideoCodec c) => switch (c) {
        VideoCodec.h264 => 0,
        VideoCodec.hevc => 1,
        _ => null,
      };

  /// Whether the OS lists a hardware encoder MFT for [codec]. A missing or
  /// unloadable native asset answers "no" rather than throwing, so the
  /// negotiator simply ranks this backend as software.
  ///
  /// `mfencListHw` returns -1 for "could not enumerate here", which is not the
  /// same fact as "this machine has no hardware encoder" and must never be
  /// cached as one — a later caller could get the real answer. Only a definitive
  /// result (0 = enumerated, none found; >0 = found) is remembered.
  ///
  /// The probe itself is marshalled to the encoder's MTA worker thread, so the
  /// apartment of the caller no longer decides the answer. That mattered: MF
  /// needs MTA and `CoInitializeEx(COINIT_MULTITHREADED)` fails with
  /// `RPC_E_CHANGED_MODE` on an STA thread, which is what Flutter's UI thread
  /// is — before the worker existed this returned -1 inside every Flutter app
  /// and the backend silently disclaimed hardware it had.
  static bool hasHardwareMft(VideoCodec codec) {
    final cached = _hwCache[codec];
    if (cached != null) return cached;
    final id = _codecId(codec);
    if (id == null) return false;
    int n;
    try {
      final buf = calloc<Uint8>(1024);
      try {
        n = mfencListHw(id, buf, 1024);
      } finally {
        calloc.free(buf);
      }
    } catch (_) {
      return false; // asset not loadable — not a fact about this machine
    }
    if (n < 0) return false; // could not enumerate here; ask again elsewhere
    return _hwCache[codec] = n > 0;
  }

  @override
  String get name => backendName;

  @override
  int get priority => defaultPriority;

  @override
  bool supportsEncode(VideoCodec codec, {bool hwAccel = false}) {
    if (!Platform.isWindows || !_codecs.contains(codec)) return false;
    // The software MFT is always a valid fallback, so the SW capability stands
    // unconditionally; the HW one is claimed only when an MFT really exists.
    return hwAccel ? hasHardwareMft(codec) : true;
  }

  @override
  bool supportsDecode(VideoCodec codec, {bool hwAccel = false}) => false;

  @override
  bool supportsAudioEncode(AudioCodec codec) => false;

  @override
  bool supportsAudioDecode(AudioCodec codec) => false;

  @override
  bool supportsMux(Container container) => false;

  @override
  bool supportsDemux(Container container) => false;

  @override
  Set<FrameSourceKind> get acceptedFrameSources =>
      const {
        FrameSourceKind.cpu,
        FrameSourceKind.miniavBufferCpu,
        // Zero-copy: a GPU capture buffer's shared NT handle, straight into the
        // encoder MFT (the recorder's direct-passthrough path).
        FrameSourceKind.miniavBufferD3D11,
        // Zero-copy: a GPU processor texture on another device, imported and
        // converted RGBA→NV12 by a D3D11 VideoProcessor. This is what makes the
        // recorder's scale/effects path available without a CPU readback — the
        // recorder filters negotiation on exactly this kind when it has GPU
        // work to do.
        FrameSourceKind.d3d11Texture,
      };

  @override
  Future<PlatformEncoder?> createEncoder(
    EncoderConfig config, {
    BackendContext? context,
  }) =>
      // Encode on the caller's device when it has one. Otherwise the encoder
      // builds its own on the DEFAULT adapter, and every GPU frame then has to
      // be exported and re-opened — which fails outright when the producer's
      // texture is not shareable, and is pure overhead when it is.
      MfVideoEncoder.open(config,
          existingD3d11Device: context?.d3d11DeviceHandle ?? 0);

  @override
  Future<PlatformDecoder?> createDecoder(
    DecoderConfig config, {
    BackendContext? context,
  }) async => null;

  @override
  Future<PlatformMuxer?> createMuxer(MuxerConfig config) async => null;

  @override
  Future<PlatformDemuxer?> createDemuxer(DemuxerConfig config) async => null;
}
