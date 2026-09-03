/// Sealed config types for recorder sources.
library;

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

import 'audio_effect.dart';
import 'screen_effect.dart';
import 'screen_scale_policy.dart';

export 'audio_effect.dart';
export 'screen_effect.dart';
export 'screen_scale_policy.dart';

/// Controls how [VideoTrackRuntime] fills the gap when the capture source
/// delivers frames at a lower rate than the configured fps (e.g. WGC / DXGI
/// only sending a frame when content changes).
enum VideoIdleFramePolicy {
  /// Re-encode the last captured GPU frame (zero-copy [SharedOutputTexture])
  /// at the target interval.
  ///
  /// Only active on the zero-copy GPU path. Silently does nothing on CPU or
  /// GPU-readback paths since those don't retain a reusable frame between
  /// captures.
  duplicate,

  /// Emit a black (all-zeros RGBA) CPU frame at the target interval when idle.
  ///
  /// Works on all encoding paths. The encoder typically produces tiny P/skip
  /// frames for static input, so bitrate overhead is minimal.
  black,

  /// No idle fill — the encoded stream reflects the capture source cadence,
  /// which may be as low as 1–2 fps on a mostly-static screen.
  none,
}

/// What a recorder does when a capture TARGET disappears mid-recording.
///
/// This is not the same as a source that has gone quiet. The target is gone:
/// a display was unplugged or re-routed (Win+P, dock/undock, a mode change),
/// a session was locked or handed to RDP, a captured window was closed, a
/// USB microphone was pulled, an HDMI audio endpoint went away with the
/// monitor it belonged to. The platform says so — Windows Graphics Capture
/// closes the capture item, WASAPI answers `AUDCLNT_E_DEVICE_INVALIDATED`,
/// Media Foundation ends the sample stream — and everything downstream keeps
/// running: the encoders, the muxer, the other tracks, the file.
///
/// The choice this enum makes is what happens to the REST of the recording.
///
/// A note on what is deliberately absent: nothing here substitutes a
/// DIFFERENT device for the one that went away. A recorder that silently
/// starts capturing something else has changed what the file is a recording
/// of, and no caller can tell from the output that it happened. If the
/// original target never returns, that track ends — and [Recorder] says so at
/// stop. Choosing a new target is the application's call, made with a user in
/// the loop, and it starts a new recording.
enum CaptureLossPolicy {
  /// Re-acquire the SAME target and carry on in the same file and the same
  /// track. The default, because for a long session the tail is usually worth
  /// more than the gap: a display that comes back after twenty seconds costs
  /// twenty seconds of frozen picture, where ending the track costs every
  /// minute after it. For audio the trade is starker still — a track that
  /// stops is silence to the end of the file.
  ///
  /// Retrying is cheap — one re-configure attempt on a backoff that settles
  /// at [RecorderBuilder.reacquireInterval] — and it stops the moment the
  /// target returns or the recording does.
  reacquire,

  /// End this track where the target was lost, and keep recording every
  /// other one. Choose this when a short file that is KNOWN complete is
  /// worth more than a long one with a hole in the middle.
  ///
  /// The other tracks keep running: an audio track that outlives its video
  /// track is ordinary in MP4, and the alternative is throwing away media
  /// that was captured perfectly well.
  endTrack,
}

/// The former name of [CaptureLossPolicy], from when only video had a loss
/// signal wired. Same type; both names work.
typedef VideoCaptureLossPolicy = CaptureLossPolicy;

sealed class RecorderSource {
  const RecorderSource();
}

class ScreenRecorderSource extends RecorderSource {
  final String? displayId;
  final String? windowId;
  final VideoCodec codec;
  final int? bitrateBps;
  final int? width;
  final int? height;
  final int? fps;
  final HwAccelPreference hwAccel;

  /// How to scale down the capture before encoding. Defaults to [ScreenScalePolicy.none].
  /// Use [ScreenScalePolicy.h264Friendly] to auto-downscale ultrawide / 4K+
  /// displays so H.264 HW encoders stay in range (max dim ≤ 4096).
  final ScreenScalePolicy scale;

  /// Zero or more GPU post-processing effects applied in order after downscaling.
  /// Effects run entirely on the GPU (WGSL compute) and add no CPU overhead.
  /// Requires the zero-copy GPU path to be active; ignored otherwise.
  final List<ScreenEffect> effects;

  /// Normalized quality target in the range **0.0 – 1.0**.
  ///
  /// When set, the encoder switches to constant-quality (CRF/ICQ) mode and
  /// [bitrateBps] is ignored. This is the recommended way to control file
  /// size: a static desktop clip will be far smaller than a fast-moving game
  /// at the same quality setting, whereas a fixed bitrate wastes bits on
  /// still content.
  ///
  /// | Value | Meaning |
  /// |-------|---------|
  /// | `1.0` | Best quality (large files) |
  /// | `0.7` | High quality — good for DVR clips (default when set) |
  /// | `0.5` | Balanced quality / size |
  /// | `0.0` | Smallest file (visibly degraded) |
  ///
  /// Leave `null` (the default) to use bitrate-based rate control instead
  /// ([bitrateBps] or [RecorderBuilder.defaultVideoBitrate]).
  final double? quality;

  /// Raw encoder options forwarded directly to the backend (FFmpeg av_opt or
  /// NVENC param name → string value). These override anything the recorder
  /// sets automatically and are intended as an expert escape hatch.
  ///
  /// Examples:
  /// ```dart
  /// encoderOptions: {'preset': 'p7', 'tune': 'hq'}   // NVENC
  /// encoderOptions: {'preset': 'slow', 'crf': '20'}  // libx264
  /// ```
  final Map<String, String> encoderOptions;

  /// How to fill video gaps when the capture source delivers fewer frames than
  /// the configured fps. Defaults to [VideoIdleFramePolicy.duplicate].
  final VideoIdleFramePolicy idleFramePolicy;

  /// When true (default), sustained GPU saturation (e.g. a game maxing the GPU
  /// so the recorder's downscale/effects/copy passes queue behind it) steps the
  /// live capture rate down evenly (2×/4× frame spacing) instead of dropping
  /// frames unevenly under back-pressure; [idleFramePolicy] duplication keeps
  /// the encoded output at the target fps, so playback degrades smoothly rather
  /// than stuttering. Restores automatically when GPU pressure clears.
  final bool adaptiveGpuThrottle;

  /// When true, the encoded stream is constant-frame-rate: output PTS are
  /// quantized to the exact fps grid and every grid slot is filled exactly
  /// once — live frames claim the slot nearest their capture time, slots the
  /// capture missed (GPU contention, drops) are backfilled with duplicates of
  /// the previous frame, and surplus frames are dropped. A missed capture
  /// becomes an invisible duplicated frame instead of a visible playback
  /// hiccup, regardless of the source cadence.
  ///
  /// Default false = VFR: frames keep their capture timestamps, and a source
  /// within ~15% of the target rate passes through untouched.
  ///
  /// Backfill/idle fill needs a retained frame, which the zero-copy D3D11
  /// paths keep; on CPU-fed paths CFR still grid-aligns PTS but missed slots
  /// stay unfilled. Requires [idleFramePolicy] != none for idle-gap fill.
  final bool cfrOutput;

  /// What to do if the captured display or window goes away mid-recording.
  /// Defaults to [CaptureLossPolicy.reacquire].
  final CaptureLossPolicy lossPolicy;

  /// How long to keep trying to re-acquire a lost target before giving up and
  /// ending the video track. `null` (the default) means for as long as the
  /// recording runs.
  ///
  /// A limit is the right choice when a hole past some length makes the file
  /// useless anyway; no limit is the right choice when the tail is what you
  /// are paying for. Ignored under [CaptureLossPolicy.endTrack].
  final Duration? reacquireLimit;

  const ScreenRecorderSource({
    this.displayId,
    this.windowId,
    required this.codec,
    this.bitrateBps,
    this.width,
    this.height,
    this.fps,
    required this.hwAccel,
    this.scale = ScreenScalePolicy.none,
    this.effects = const [],
    this.quality,
    this.encoderOptions = const {},
    this.idleFramePolicy = VideoIdleFramePolicy.duplicate,
    this.adaptiveGpuThrottle = true,
    this.cfrOutput = false,
    this.lossPolicy = CaptureLossPolicy.reacquire,
    this.reacquireLimit,
  });
}

class CameraRecorderSource extends RecorderSource {
  final String deviceId;
  final VideoCodec codec;
  final int? bitrateBps;
  final int? width;
  final int? height;
  final int? fps;
  final HwAccelPreference hwAccel;

  /// See [ScreenRecorderSource.quality].
  final double? quality;

  /// See [ScreenRecorderSource.encoderOptions].
  final Map<String, String> encoderOptions;

  /// See [VideoIdleFramePolicy]. Defaults to [VideoIdleFramePolicy.none]
  /// because cameras deliver at a fixed rate and rarely need idle fill.
  final VideoIdleFramePolicy idleFramePolicy;

  /// What to do if the camera is unplugged or reset mid-recording.
  /// Defaults to [CaptureLossPolicy.reacquire].
  ///
  /// A camera IS re-acquirable, unlike a closed window: a USB device that is
  /// pulled and pushed back in, or one whose driver resets, comes back under
  /// the same device id. See [ScreenRecorderSource.reacquireLimit].
  final CaptureLossPolicy lossPolicy;

  /// See [ScreenRecorderSource.reacquireLimit].
  final Duration? reacquireLimit;

  const CameraRecorderSource({
    required this.deviceId,
    required this.codec,
    this.bitrateBps,
    this.width,
    this.height,
    this.fps,
    required this.hwAccel,
    this.quality,
    this.encoderOptions = const {},
    this.idleFramePolicy = VideoIdleFramePolicy.none,
    this.lossPolicy = CaptureLossPolicy.reacquire,
    this.reacquireLimit,
  });
}

class MicRecorderSource extends RecorderSource {
  final String deviceId;
  final AudioCodec codec;
  final int? bitrateBps;
  final int? sampleRate;
  final int? channels;

  /// What to do if the microphone goes away mid-recording — unplugged,
  /// preempted, or reset. Defaults to [CaptureLossPolicy.reacquire].
  final CaptureLossPolicy lossPolicy;

  /// See [ScreenRecorderSource.reacquireLimit].
  final Duration? reacquireLimit;

  const MicRecorderSource({
    required this.deviceId,
    required this.codec,
    this.bitrateBps,
    this.sampleRate,
    this.channels,
    this.lossPolicy = CaptureLossPolicy.reacquire,
    this.reacquireLimit,
  });
}

class LoopbackRecorderSource extends RecorderSource {
  final String deviceId;
  final AudioCodec codec;
  final int? bitrateBps;
  final int? sampleRate;
  final int? channels;

  /// What to do if the render endpoint goes away mid-recording. Defaults to
  /// [CaptureLossPolicy.reacquire].
  ///
  /// Worth leaving on: an HDMI or DisplayPort audio endpoint belongs to the
  /// monitor it arrives on, so the display transitions that close a capture
  /// item — Win+P, undock, a mode change — invalidate the endpoint at the
  /// same instant. Both losses come from one keystroke.
  final CaptureLossPolicy lossPolicy;

  /// See [ScreenRecorderSource.reacquireLimit].
  final Duration? reacquireLimit;

  const LoopbackRecorderSource({
    required this.deviceId,
    required this.codec,
    this.bitrateBps,
    this.sampleRate,
    this.channels,
    this.lossPolicy = CaptureLossPolicy.reacquire,
    this.reacquireLimit,
  });
}

/// Captures **mic + loopback simultaneously** and mixes the two PCM streams
/// into a single audio track in the output.
///
/// Use this instead of separate [MicRecorderSource] + [LoopbackRecorderSource]
/// when you want one audio track that every player will play (rather than
/// two tracks where most players auto-pick only the first).
///
/// Both inputs are converted to a common format
/// (48 kHz / stereo / float32) and summed sample-by-sample. The resulting
/// PCM is encoded with a single [AudioEncoder].
///
/// [micGainDb] / [loopbackGainDb] adjust each source's level before the sum
/// (use a negative value such as `-3` to avoid clipping when both are loud).
///
/// [micEffects] / [loopbackEffects] are per-source [AudioEffect] chains
/// applied (after the gain) before the sum; [masterEffects] runs on the
/// summed mix just before encoding. See [AudioEffect] for the built-in
/// stages (auto-level, noise gate, high-pass, limiter).
class MixedAudioRecorderSource extends RecorderSource {
  final String micDeviceId;
  final String loopbackDeviceId;
  final AudioCodec codec;
  final int? bitrateBps;
  final double micGainDb;
  final double loopbackGainDb;
  final List<AudioEffect> micEffects;
  final List<AudioEffect> loopbackEffects;
  final List<AudioEffect> masterEffects;

  /// What to do if EITHER input goes away mid-recording. Defaults to
  /// [CaptureLossPolicy.reacquire], and the two are tracked separately: one
  /// input dying does not end the other.
  ///
  /// This matters more here than for a separate pair of tracks. The mix is
  /// driven by the loopback callback, so a dead render endpoint stops the
  /// whole track — including the microphone, which is still working.
  final CaptureLossPolicy lossPolicy;

  /// See [ScreenRecorderSource.reacquireLimit].
  final Duration? reacquireLimit;

  const MixedAudioRecorderSource({
    required this.micDeviceId,
    required this.loopbackDeviceId,
    this.codec = AudioCodec.aac,
    this.bitrateBps,
    this.micGainDb = 0.0,
    this.loopbackGainDb = 0.0,
    this.micEffects = const [],
    this.loopbackEffects = const [],
    this.masterEffects = const [],
    this.lossPolicy = CaptureLossPolicy.reacquire,
    this.reacquireLimit,
  });
}
