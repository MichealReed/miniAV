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
    // Raw AAC in ADTS framing. Previously unmapped, which sent `out.aac`
    // through the track-mix heuristic and wrote an M4A into it.
    'aac' || 'adts' => Container.adts,
    _ => null,
  };
}

/// Heuristic container for a track mix when the file extension offers no
/// hint and the caller did not supply an explicit [Container] override.
///
/// Rules (in order):
/// - video + audio, codec mix the first-party writer handles → MP4
/// - video + audio, anything else → MKV  (handles any codec mix)
/// - video only    → MP4
/// - audio only    → M4A / MP3 / OGG / WAV based on codec; MKV as catch-all
/// - mixed audio codecs → MKV
///
/// The video+audio case answers MP4 only when both [videoCodecs] and
/// [audioCodecs] are known AND [firstPartyMuxerCanWrite] accepts them: an
/// unstated codec is an unknown one, and MKV — via FFmpeg — is the answer that
/// works for every mix. Callers that know their codecs therefore land on the
/// FFmpeg-free path, and callers that don't keep the old behaviour.
///
/// Audio-only PCM answers WAV rather than the old MKV catch-all. MKV was not a
/// working answer for it: only FFmpeg writes MKV, FFmpeg has no PCM *encoder*,
/// and the recording was rejected before it started. AAC stays on M4A — ADTS is
/// reachable by asking for it (`.aac`, or an explicit [Container.adts]), and
/// M4A is the better default for a file that is going to be kept.
Container containerForTrackMix({
  required bool hasVideo,
  required bool hasAudio,

  /// Codec(s) present on video tracks. Only consulted when [hasVideo] and
  /// [hasAudio] are both true.
  Set<VideoCodec> videoCodecs = const {},

  /// Codec(s) present on audio tracks.
  Set<AudioCodec> audioCodecs = const {},
}) {
  if (hasVideo) {
    if (!hasAudio) return Container.mp4;
    final firstParty =
        videoCodecs.isNotEmpty &&
        audioCodecs.isNotEmpty &&
        firstPartyMuxerCanWrite(
          container: Container.mp4,
          videoCodecs: videoCodecs,
          audioCodecs: audioCodecs,
        );
    return firstParty ? Container.mp4 : Container.mkv;
  }
  if (audioCodecs.length == 1) {
    return switch (audioCodecs.single) {
      AudioCodec.aac => Container.m4a,
      AudioCodec.mp3 => Container.mp3,
      AudioCodec.opus => Container.ogg,
      AudioCodec.pcmS16le || AudioCodec.pcmF32le => Container.wav,
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
/// Kept deliberately narrow: it answers `false` for anything the first-party
/// writers do not handle (MKV above all), and those fall to FFmpeg as before.
///
/// Three writers are covered, each mirroring its own accept set:
///  * `Mp4Muxer` — MP4/M4A, H.264/HEVC/AV1 video + AAC/Opus audio, any number
///    of tracks.
///  * `WavMuxer` — WAV, exactly one PCM audio track and no video.
///  * `AdtsMuxer` — ADTS, exactly one AAC audio track and no video.
///
/// The last two matter beyond tidiness: FFmpeg has no PCM *encoder*, so before
/// they were routed here a `.wav` sink could not be recorded by any path at
/// all, and a `.aac` sink was written as an M4A.
bool firstPartyMuxerCanWrite({
  required Container container,
  required Iterable<VideoCodec> videoCodecs,
  required Iterable<AudioCodec> audioCodecs,

  /// Number of audio TRACKS the sink will carry, when the caller knows it.
  ///
  /// Only WAV and ADTS read this, and only they need it: both hold exactly one
  /// track and neither writer looks at `EncodedPacket.trackIndex`, so a second
  /// audio track would be interleaved into the first one's stream rather than
  /// refused. [audioCodecs] cannot answer it — callers legitimately pass a SET,
  /// where two AAC tracks collapse to one element. `null` falls back to that
  /// element count, which is exact whenever the iterable is per-track.
  int? audioTracks,
}) {
  switch (container) {
    case Container.mp4:
    case Container.m4a:
      // Mirrors Mp4Muxer's own accept sets — it writes dOps for Opus as well
      // as esds/AudioSpecificConfig for AAC.
      const video = {VideoCodec.h264, VideoCodec.hevc, VideoCodec.av1};
      const audio = {AudioCodec.aac, AudioCodec.opus};
      return videoCodecs.every(video.contains) &&
          audioCodecs.every(audio.contains);
    case Container.wav:
      return _singleAudioTrack(videoCodecs, audioCodecs, audioTracks) &&
          audioCodecs.every(_pcmCodecs.contains);
    case Container.adts:
      return _singleAudioTrack(videoCodecs, audioCodecs, audioTracks) &&
          audioCodecs.every((c) => c == AudioCodec.aac);
    default:
      return false;
  }
}

/// Codecs `WavMuxer` writes. PCM is the container's whole content, so this is
/// also the set for which no encoder work happens at all.
const _pcmCodecs = {AudioCodec.pcmS16le, AudioCodec.pcmF32le};

/// The audio-only, exactly-one-track shape WAV and ADTS require.
bool _singleAudioTrack(
  Iterable<VideoCodec> videoCodecs,
  Iterable<AudioCodec> audioCodecs,
  int? audioTracks,
) =>
    videoCodecs.isEmpty &&
    audioCodecs.isNotEmpty &&
    (audioTracks ?? audioCodecs.length) == 1;

/// Container a file sink will be written with, resolved from configuration
/// alone: an explicit override, else the path's extension, else the track mix.
///
/// Same precedence [Recorder] applies when it opens the muxer — kept here so
/// the answer is available *before* any encoder is negotiated (see
/// [recordingRequiresFfmpegMuxer]) and so it is testable without a recorder.
Container resolveSinkContainer({
  Container? explicit,
  required String path,
  required Set<VideoCodec> videoCodecs,
  required Set<AudioCodec> audioCodecs,
}) =>
    explicit ??
    containerForExtension(path) ??
    containerForTrackMix(
      hasVideo: videoCodecs.isNotEmpty,
      hasAudio: audioCodecs.isNotEmpty,
      videoCodecs: videoCodecs,
      audioCodecs: audioCodecs,
    );

/// Whether any of these file sinks can only be written by `FfmpegMuxer`.
///
/// This is the question that decides how a recording's AUDIO may negotiate.
/// `FfmpegMuxer` fills each audio stream's codecpar from a live
/// `AVCodecContext` (`ch_layout` is not reachable through the Dart-side
/// `AVCodecParameters` prefix), so it can only describe audio that FFmpeg
/// itself encoded. A recording it has to write must therefore encode its audio
/// on FFmpeg — a hard coupling, not a preference. Every sink whose container +
/// codec mix the first-party writer accepts leaves audio free to negotiate
/// (OS AAC outranks FFmpeg, which is the point of the first-party path).
///
/// Answered from CONFIGS, before any encoder exists: after the encoders are
/// open it is too late — the mismatch would surface as a throw inside the
/// muxer with no way back.
///
/// [videoCodecs]/[audioCodecs] are the codecs the sources are configured with.
/// Resolution-driven H.264→HEVC promotion cannot change the answer: both are
/// codecs the first-party writer accepts.
///
/// [audioTracks] is the number of configured audio sources; see
/// [firstPartyMuxerCanWrite], which is the only thing that reads it.
bool recordingRequiresFfmpegMuxer({
  required Iterable<({Container? container, String path})> fileSinks,
  required Set<VideoCodec> videoCodecs,
  required Set<AudioCodec> audioCodecs,
  int? audioTracks,
}) {
  // No audio ⇒ no codecpar to fill ⇒ no coupling, whatever the container is.
  if (audioCodecs.isEmpty) return false;
  for (final sink in fileSinks) {
    final container = resolveSinkContainer(
      explicit: sink.container,
      path: sink.path,
      videoCodecs: videoCodecs,
      audioCodecs: audioCodecs,
    );
    if (!firstPartyMuxerCanWrite(
      container: container,
      videoCodecs: videoCodecs,
      audioCodecs: audioCodecs,
      audioTracks: audioTracks,
    )) {
      return true;
    }
  }
  return false;
}
