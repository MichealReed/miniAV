/// Codec, container, and configuration enums.
library;

/// Video codec identifiers. Backends declare which they support via
/// [MiniAVToolsBackend.supportsEncode] / [supportsDecode].
enum VideoCodec {
  /// H.264 / AVC. Universally supported.
  h264,

  /// H.265 / HEVC.
  hevc,

  /// AV1 — modern royalty-free codec.
  av1,

  /// VP9 — used by WebM/YouTube.
  vp9,

  /// VP8 — older WebM/WebRTC codec.
  vp8,

  /// Motion JPEG — every frame is an independent JPEG. Trivial to encode in
  /// pure GPU compute.
  mjpeg,

  /// ProRes — Apple intermediate codec (decode only on most platforms).
  prores,
}

/// Audio codec identifiers.
enum AudioCodec { aac, opus, vorbis, mp3, flac, pcmS16le, pcmF32le }

/// Container / file-format identifiers for muxing & demuxing.
enum Container {
  /// ISO/IEC 14496-14 — `.mp4`. Most universal.
  mp4,

  /// Fragmented MP4 — for streaming / DASH / HLS-fMP4.
  fmp4,

  /// Matroska — `.mkv`.
  mkv,

  /// WebM — Matroska subset for VP8/9/AV1 + Opus/Vorbis.
  webm,

  /// MPEG-TS — `.ts`. Used by HLS.
  mpegts,

  /// Raw codec bitstream — no container, just packets concatenated.
  /// Useful for intermediate piping or Annex-B H.264 streams.
  raw,

  /// Ogg — `.ogg` / `.opus`.
  ogg,

  /// WAV — uncompressed audio container.
  wav,
}

/// Hardware acceleration preference.
///
/// - [forbidden]: never use HW. Always pick a software encoder/decoder.
/// - [allowed]:   use HW only if the backend reports it for free.
/// - [preferred]: try HW first; fall back to SW if unavailable.
/// - [required]:  fail with [CodecInitException] if no HW path exists.
enum HwAccelPreference { forbidden, allowed, preferred, required }

/// Rate-control mode for video encoders.
///
/// - [cbr]: constant bitrate — for streaming, fixed bandwidth.
/// - [vbr]: variable bitrate — better quality at same average bitrate.
/// - [crf]: constant quality (rate factor) — set [EncoderConfig.crfQuality].
/// - [icq]: intelligent constant quality (NVENC).
enum RateControl { cbr, vbr, crf, icq }

/// H.264 / HEVC profile identifiers (a sensible cross-codec subset).
enum EncoderProfile { baseline, main, high, high10, high422, high444 }

/// H.264 / HEVC level. Backends interpret this codec-appropriately.
enum EncoderLevel {
  level3_0,
  level3_1,
  level4_0,
  level4_1,
  level5_0,
  level5_1,
  level5_2,
  level6_0,
  level6_1,
  level6_2,
}
