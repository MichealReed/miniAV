/// First-party codecs for miniav_tools.
///
/// This is the home for direct, GPU-handle-first codec backends — kept distinct
/// from `miniav_tools_ffmpeg` (the shrinking software/container fallback):
///   - GPU-compute codecs via minigpu (WGSL) — MJPEG today; AV1 / custom
///     ML-oriented codecs in progress.
///   - Hardware video codecs via native platform APIs (Media Foundation first,
///     then vendor SDKs — NVENC/NVDEC, VideoToolbox, AMF, VAAPI, MediaCodec),
///     producing/consuming GPU surfaces (D3D11 texture, etc.) with no readback.
///   - Direct audio codec libraries (libopus, …).
///
/// Web codec support (WebCodecs + MSE fallback) also lives here.
library;

export 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';
export 'src/minigpu_backend.dart' show MinigpuBackend;
export 'src/gpu_codec_pipeline.dart'
    show GpuCodecPipeline, GpuCodecEncoder, kFrameInputKey, kEncodedOutputKey;
export 'src/minigpu_mjpeg_pipeline.dart' show MinigpuMjpegPipeline;
export 'src/av1/minigpu_av1_pipeline.dart' show MinigpuAv1Pipeline;
export 'src/av1/av1_yuv420_stage.dart'
    show Yuv420Layout, buildRgba8ToYuv420Bt709LimitedStage, kYuv420Key;
export 'src/av1/av1_yuv420_reference.dart' show rgbaToYuv420Bt709LimitedCpu;
export 'src/av1/mp4/av1_mp4_muxer.dart' show Av1Mp4Muxer;
export 'src/opus/opus_backend.dart' show OpusBackend;
export 'src/opus/opus_audio_decoder.dart' show OpusAudioDecoder;
export 'src/opus/opus_audio_encoder.dart' show OpusAudioEncoder;
export 'src/mf/mf_decode_backend.dart' show MfDecodeBackend;
export 'src/mf/mf_d3d11_decoder.dart' show MfD3d11Decoder;
export 'src/mf/aac_backend.dart' show AacBackend;
export 'src/mf/mf_aac_decoder.dart' show MfAacDecoder;
export 'src/mf/mf_aac_encoder.dart' show MfAacEncoder;
export 'src/mf/mf_encode_backend.dart' show MfEncodeBackend;
export 'src/mf/mf_video_encoder.dart' show MfVideoEncoder;
export 'src/pcm/pcm_backend.dart' show PcmBackend;
export 'src/pcm/pcm_audio_decoder.dart' show PcmAudioDecoder;
export 'src/pcm/pcm_audio_encoder.dart' show PcmAudioEncoder;
export 'src/framing/container_backend.dart' show ContainerFramingBackend;
export 'src/framing/wav_container.dart' show WavDemuxer, WavMuxer;
export 'src/framing/ogg_container.dart' show OggDemuxer, OggMuxer;
export 'src/framing/adts_container.dart'
    show AdtsDemuxer, AdtsMuxer, ascToAdtsParams, adtsSampleRates;
export 'src/framing/mp3_container.dart'
    show Mp3Demuxer, Mp3VbrHeader, isMp3Sync, isAdtsSync, isId3Magic,
        id3TagLength;
export 'src/framing/mp4_container.dart'
    show Mp4ConfigChange, Mp4Demuxer, Mp4Muxer, Mp4TrackTimingReport;
export 'src/framing/annexb.dart'
    show isAnnexB, splitAnnexB, buildAvcC, buildHvcC, annexBToLengthPrefixed;
export 'src/sw_audio/sw_audio_backend.dart' show SwAudioBackend;
export 'src/sw_audio/sw_audio_decoder.dart' show SwAudioDecoder;
export 'src/sw_audio/sw_audio_stream_decoder.dart' show SwAudioStreamDecoder;
export 'src/frame_convert.dart'
    show
        CpuFrameConverter,
        YuvPlanar,
        cpuI420ToRgba,
        cpuNv12ToRgba,
        cpuP010ToRgba,
        cpuPlanarToRgba,
        cpuRgbaToI420;
// The platform-neutral colour-conversion boundary (also importable on its own
// as `package:miniav_tools_codecs/convert.dart` — no FFI/io/minigpu). GPU
// converters live in `package:miniav_tools_codecs/gpu.dart` (web-safe minigpu).
export 'convert.dart'
    show
        YuvRgbCoeffs,
        RgbaYuvCoeffs,
        I420Planes,
        dartI420ToRgba,
        dartI420ToRgbaAsync,
        dartI422ToRgba,
        dartRgbaToI420,
        dartRgbaToI420Async;

import 'dart:io';

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

import 'src/framing/container_backend.dart';
import 'src/mf/aac_backend.dart';
import 'src/mf/mf_decode_backend.dart';
import 'src/mf/mf_encode_backend.dart';
import 'src/minigpu_backend.dart';
import 'src/opus/opus_backend.dart';
import 'src/pcm/pcm_backend.dart';
import 'src/sw_audio/sw_audio_backend.dart';

/// Register every first-party backend at once (idempotent, safe to call
/// repeatedly; each entry no-ops on platforms it does not serve).
///
/// This exists because **Dart has no import side-effect**. A top-level
/// `final x = register();` looks like initialisation but is lazy — it runs on
/// first *read*, and nothing reads it — so a library cannot make itself the
/// default just by being imported. Registration has to happen on a code path
/// that actually executes. `miniav_recorder` calls this before it negotiates an
/// encoder, which is what makes the first-party path the default for recording
/// apps without any per-app boilerplate; anything else should call it from
/// `main()`.
///
/// Registering is not the same as winning. The negotiator ranks `isHardware`
/// above priority, and each backend reports capability honestly — so on a box
/// with no hardware MFT, FFmpeg's hardware path still takes H.264. To pin a
/// specific backend, name it at the call site (`EncoderConfig.backend`);
/// there is no unregister.
///
/// Covers: minigpu, MF encode + decode, OS AAC, Opus, PCM, software audio (MP3)
/// and container framing (WAV/Ogg/ADTS/MP4 demux+mux, MP3 demux).
bool registerFirstPartyBackends() {
  var any = registerMinigpuBackend();
  any = registerMfEncodeBackend() || any;
  any = registerMfDecodeBackend() || any;
  any = registerAacBackend() || any;
  any = registerOpusBackend() || any;
  any = registerPcmBackend() || any;
  any = registerSwAudioBackend() || any;
  any = registerContainerFramingBackend() || any;
  return any;
}

bool registerMinigpuBackend() {
  final existing = MiniAVToolsPlatform.instance.backends.any(
    (b) => b.name == MinigpuBackend.backendName,
  );
  if (existing) return false;
  MiniAVToolsPlatform.instance.register(MinigpuBackend());
  return true;
}

/// Register the first-party Opus audio-decode backend (idempotent). Reports
/// `supportsAudioDecode(opus)` at a higher priority than the FFmpeg backend, so
/// the facade picks it for Opus — a decode path with zero FFmpeg. Falls back to
/// FFmpeg automatically if libopus init fails.
bool registerOpusBackend() {
  final existing = MiniAVToolsPlatform.instance.backends.any(
    (b) => b.name == OpusBackend.backendName,
  );
  if (existing) return false;
  MiniAVToolsPlatform.instance.register(OpusBackend());
  return true;
}

/// Register the Media Foundation hardware video-decode backend (Windows only,
/// idempotent; no-op elsewhere). Reports a `{mediaFoundation, zeroCopy,
/// d3d11Texture}` capability the negotiator ranks over software decode — a
/// hardware H.264/HEVC → D3D11 path with **zero FFmpeg** (the decoder lives in
/// the standalone `codecs_native` asset). Falls back to software for free when
/// no hardware MFT is available.
bool registerMfDecodeBackend() {
  if (!Platform.isWindows) return false;
  final existing = MiniAVToolsPlatform.instance.backends.any(
    (b) => b.name == MfDecodeBackend.backendName,
  );
  if (existing) return false;
  MiniAVToolsPlatform.instance.register(MfDecodeBackend());
  return true;
}

/// Register the first-party MF video-encode backend (Windows only, idempotent;
/// no-op elsewhere). H.264/HEVC on the OS **hardware** encoder MFT (NVENC /
/// AMF / QSV) with a software-MFT fallback — no FFmpeg. Priority 55, and it
/// reports a hardware capability only where the OS actually lists a hardware
/// MFT, so software-only boxes still rank below a real hardware FFmpeg path.
bool registerMfEncodeBackend() {
  if (!Platform.isWindows) return false;
  final existing = MiniAVToolsPlatform.instance.backends.any(
    (b) => b.name == MfEncodeBackend.backendName,
  );
  if (existing) return false;
  MiniAVToolsPlatform.instance.register(MfEncodeBackend());
  return true;
}

/// Register the first-party OS AAC backend (Windows only, idempotent; no-op
/// elsewhere). Media Foundation AAC decode + encode, preferred over FFmpeg for
/// AAC — falls back to FFmpeg for free when no MFT is available or the thread is
/// STA. License-clean (the OS codec; libfdk-aac is GPL-banned).
bool registerAacBackend() {
  if (!Platform.isWindows) return false;
  final existing = MiniAVToolsPlatform.instance.backends.any(
    (b) => b.name == AacBackend.backendName,
  );
  if (existing) return false;
  MiniAVToolsPlatform.instance.register(AacBackend());
  return true;
}

/// Register the first-party raw-PCM audio backend (pcmS16le / pcmF32le;
/// idempotent, all platforms). Pure Dart, no native lib — decodes/encodes raw
/// interleaved PCM at a priority above FFmpeg, giving raw PCM a real path
/// (previously FFmpeg's audio codec map threw on it).
bool registerPcmBackend() {
  final existing = MiniAVToolsPlatform.instance.backends.any(
    (b) => b.name == PcmBackend.backendName,
  );
  if (existing) return false;
  MiniAVToolsPlatform.instance.register(PcmBackend());
  return true;
}

/// Register the pure-Dart container framing backend — WAV + Ogg + ADTS + MP4
/// demux/mux plus MP3 demux (idempotent, all platforms). Priority 55 (above
/// FFmpeg's 50) so these containers open/write FFmpeg-free by default; a parse
/// failure returns `null`, so the negotiator still falls through to FFmpeg.
/// MP3 is demux-only — there is no first-party mp3 encoder to mux for.
bool registerContainerFramingBackend() {
  final existing = MiniAVToolsPlatform.instance.backends.any(
    (b) => b.name == ContainerFramingBackend.backendName,
  );
  if (existing) return false;
  MiniAVToolsPlatform.instance.register(ContainerFramingBackend());
  return true;
}

/// Register the first-party software audio-decode backend — MP3 via dr_mp3
/// (idempotent, all platforms). Priority 55 (above FFmpeg) — an FFmpeg-free
/// decode path for MP3.
///
/// FLAC and Vorbis are deliberately NOT claimed: the native entry points take a
/// whole container and [SwAudioDecoder] ignores `extraData`, so a demuxed
/// stream has no STREAMINFO/setup headers to open with. They route to FFmpeg
/// (see [SwAudioBackend]).
bool registerSwAudioBackend() {
  final existing = MiniAVToolsPlatform.instance.backends.any(
    (b) => b.name == SwAudioBackend.backendName,
  );
  if (existing) return false;
  MiniAVToolsPlatform.instance.register(SwAudioBackend());
  return true;
}
