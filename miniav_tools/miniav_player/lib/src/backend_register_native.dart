/// Native backend registration (default): FFmpeg via `miniav_tools_ffmpeg`.
///
/// Selected on the VM/native by the conditional import in `player.dart`. Not
/// compiled on web (it pulls `dart:ffi`).
library;

import 'package:miniav_tools_codecs/miniav_tools_codecs.dart'
    show
        registerMfDecodeBackend,
        registerOpusBackend,
        registerPcmBackend,
        registerContainerFramingBackend,
        registerSwAudioBackend,
        registerAacBackend;
import 'package:miniav_tools_ffmpeg/miniav_tools_ffmpeg.dart'
    show registerFfmpegBackend;

/// Register the platform's codec backend(s) with the tools registry
/// (idempotent).
///
/// The first-party, **FFmpeg-free** backends live in `miniav_tools_codecs`:
///   - Media Foundation hardware video decode (Windows) → the negotiator picks
///     it (→ D3D11 texture) over software decode.
///   - libopus audio decode + encode (all platforms) → picked over FFmpeg for Opus.
///   - raw PCM (pcmS16le/pcmF32le) decode + encode (all platforms).
///   - dr_mp3 MP3 decode (all platforms).
///   - WAV / Ogg / ADTS / MP4 container framing + MP3 demux (all platforms) →
///     `.wav`/`.opus` files demux/mux with no libavformat.
///
/// FFmpeg remains the cross-platform software floor + the fallback for other
/// codecs/containers — so a packet-streaming H.264/HEVC-video + Opus-audio
/// player, and `.wav`/`.opus` file playback, run with zero FFmpeg in the
/// process on Windows.
void registerPlayerBackends() {
  registerMfDecodeBackend(); // FFmpeg-free HW video (Windows)
  registerOpusBackend(); // FFmpeg-free Opus audio (decode + encode)
  registerPcmBackend(); // FFmpeg-free raw PCM
  registerSwAudioBackend(); // FFmpeg-free MP3 decode (FLAC/Vorbis: see below)
  registerAacBackend(); // FFmpeg-free OS AAC decode+encode (Windows; MTA)
  registerContainerFramingBackend(); // FFmpeg-free WAV/Ogg/ADTS/MP4/MP3 demux
  // Software floor + fallback (MKV, SW video, STA AAC) — and the ONLY decoder
  // for FLAC/Vorbis: sw_audio's are whole-container-only, so they cannot take a
  // demuxed track and the backend does not claim those codecs.
  registerFfmpegBackend();
}
