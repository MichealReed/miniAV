/// Container-selection helpers shared by [Recorder] and unit tests.
library;

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

/// Maps a file-path extension to a [Container], or returns `null` for
/// unrecognised / missing extensions.
///
/// Matching is case-insensitive. Used by [Recorder] to honour the caller's
/// implicit intent when they write `addFileOutput('recording.mp4')` without
/// an explicit `container:` override.
Container? containerForExtension(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return null;
  return switch (path.substring(dot + 1).toLowerCase()) {
    'mp4' || 'm4v' => Container.mp4,
    'mkv' => Container.mkv,
    'webm' => Container.webm,
    'ts' || 'mts' => Container.mpegts,
    'ogg' => Container.ogg,
    'wav' => Container.wav,
    'm4a' => Container.m4a,
    'mp3' => Container.mp3,
    _ => null,
  };
}

/// Heuristic container for a track mix when the file extension offers no
/// hint and the caller did not supply an explicit [Container] override.
///
/// Rules (in order):
/// - video + audio → MKV  (handles any codec mix without restriction)
/// - video only    → MP4
/// - audio only    → M4A / MP3 / OGG based on codec; MKV as catch-all
/// - mixed audio codecs → MKV
Container containerForTrackMix({
  required bool hasVideo,
  required bool hasAudio,

  /// Codec(s) present on audio-only tracks.  Ignored when [hasVideo] is true.
  Set<AudioCodec> audioCodecs = const {},
}) {
  if (hasVideo) {
    return hasAudio ? Container.mkv : Container.mp4;
  }
  if (audioCodecs.length == 1) {
    return switch (audioCodecs.single) {
      AudioCodec.aac => Container.m4a,
      AudioCodec.mp3 => Container.mp3,
      AudioCodec.opus => Container.ogg,
      _ => Container.mkv,
    };
  }
  return Container.mkv; // mixed or unknown codecs
}

/// Whether the first-party (FFmpeg-free) muxer can write this combination.
///
/// This is a capability question with a coupling behind it. `FfmpegMuxer`
/// requires a live `AVCodecContext` per audio track to fill codecpar —
/// `ch_layout` is not reachable from the Dart-side `AVCodecParameters` prefix —
/// which means it can only mux audio that FFmpeg itself encoded. The
/// first-party writer takes already-encoded packets and needs no encoder
/// handle at all, so preferring it removes a dependency between the muxer and
/// whichever backend happened to win the audio negotiation.
///
/// Kept deliberately narrow: it answers `false` for anything the ISO-BMFF
/// writer does not handle (MKV above all), and those fall to FFmpeg as before.
bool firstPartyMuxerCanWrite({
  required Container container,
  required Iterable<VideoCodec> videoCodecs,
  required Iterable<AudioCodec> audioCodecs,
}) {
  if (container != Container.mp4 && container != Container.m4a) return false;
  const video = {VideoCodec.h264, VideoCodec.hevc, VideoCodec.av1};
  return videoCodecs.every(video.contains) &&
      audioCodecs.every((c) => c == AudioCodec.aac);
}
