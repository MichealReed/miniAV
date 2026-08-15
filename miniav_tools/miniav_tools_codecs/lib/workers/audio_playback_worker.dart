// The whole audio path, on a worker. Web only.
//
// Demux, decode and the ring fill all happen here, so once playback starts the
// main thread is not involved in it again. That is the point: the browser
// renders audio on a realtime thread, and every millisecond the FILLING of that
// thread's buffer spends waiting behind Flutter's build and raster work is a
// millisecond closer to a click. Here there is nothing to wait behind.
//
// The samples never cross a message boundary. They are written straight into a
// SharedAudioRing that the AudioWorklet reads on the audio thread — no
// postMessage per chunk, no main-thread hop, no copy beyond the one out of the
// decoder.
//
// The parser and the decoder are the same ones the in-process path uses, so
// audio cannot decode differently depending on where it ran.

import 'dart:async';
import 'dart:typed_data';

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';
import 'package:spawn/spawn.dart';

import '../src/framing/container_backend.dart' show ContainerFramingBackend;
import '../src/web/web_codecs_audio_decoder.dart';

/// How long to wait when the ring is full before offering samples again.
///
/// Deliberately a real duration and not `Duration.zero`: a zero delay compiles
/// to `setTimeout(0)`, which browsers clamp to 4 ms anyway, so asking for zero
/// only hides what it costs. A full ring means hundreds of milliseconds of
/// audio are already queued and there is nothing whatsoever to hurry for.
const Duration _kRingFullPatience = Duration(milliseconds: 10);

/// Decodes an audio track and keeps a [SharedAudioRing] fed until it runs out
/// or is told to stop.
Future<void> audioPlaybackWorker(WorkerChannel channel) async {
  final init = channel.initialMessage! as Map<String, Object?>;
  final ring = SharedAudioRing.attach(
    (init['ring']! as PlatformValue).value!,
  );

  var stopped = false;
  var eof = false;
  var framesWritten = 0;
  int? seekTargetUs;
  var seekGeneration = 0;
  int? firstPtsUs;
  Object? failure;

  PlatformDemuxer? demuxer;
  PlatformAudioDecoder? decoder;

  channel.handleRequests((Object? request) async {
    switch (request) {
      case 'stats':
        return <String, Object?>{
          'framesWritten': framesWritten,
          'firstPtsUs': firstPtsUs,
          'seekGeneration': seekGeneration,
          'eof': eof,
          'underruns': ring.underruns,
          'buffered': ring.availableFrames,
          'error': failure?.toString(),
        };
      case ['seek', final int targetUs]:
        // Recorded, not performed: the pump owns the demuxer and the decoder,
        // and seeking them from under it mid-decode is how a decoder ends up
        // emitting samples from two different places in the stream. The pump
        // picks this up at its next boundary, which it reaches promptly
        // because a pending seek also breaks it out of a full-ring wait.
        seekTargetUs = targetUs;
        return null;
      case 'stop':
        stopped = true;
        return null;
      default:
        throw StateError('unknown op: $request');
    }
  });

  try {
    demuxer = ContainerFramingBackend.openInProcess(
      init['bytes']! as Uint8List,
      null,
    );
    if (demuxer == null) {
      throw const CodecInitException(
        'audio-worker',
        'no pure-Dart parser claims this container',
      );
    }

    final trackIndex = _audioTrackIndex(demuxer.tracks);
    final track = demuxer.tracks[trackIndex] as AudioTrackInfo;
    decoder = await WebCodecsAudioDecoder.create(
      AudioDecoderConfig.fromTrack(track),
    );

    // The pump. Nothing in here touches the main thread.
    bool interrupted() => stopped || seekTargetUs != null;

    while (!stopped) {
      final target = seekTargetUs;
      if (target != null) {
        seekTargetUs = null;
        await demuxer.seek(target);
        // Drop the decoder's reference state along with the container
        // position: a decoder carried across a seek emits the tail of where it
        // used to be.
        await decoder.flush();
        // Safe here and only here: the host suspends the audio thread across a
        // seek, so there is no consumer to race, and dropping what is queued is
        // the entire point of seeking.
        ring.clear();
        firstPtsUs = null;
        eof = false;
        seekGeneration++;
        continue;
      }

      final packet = await demuxer.readPacket();
      if (packet == null) {
        eof = true;
        for (final chunk in await decoder.flush()) {
          framesWritten += await _fill(ring, chunk, interrupted);
        }
        // Not a break: a seek can restart a finished stream, and exiting here
        // would leave the worker alive but permanently deaf to one.
        while (!stopped && seekTargetUs == null) {
          await Future<void>.delayed(_kRingFullPatience);
        }
        continue;
      }
      if (packet.trackIndex != trackIndex) continue;
      for (final chunk in await decoder.decode(packet)) {
        firstPtsUs ??= chunk.ptsUs;
        framesWritten += await _fill(ring, chunk, interrupted);
        if (interrupted()) break;
      }
    }
  } on Object catch (e) {
    // Recorded rather than thrown: the host asks for stats and can report a
    // dead pump, where an unhandled error in a worker is just a worker that
    // stopped for no stated reason.
    failure = e;
  }

  await channel.onClose;
  try {
    await decoder?.close();
    await demuxer?.close();
  } on Object {
    // Teardown is best effort; the host is already gone.
  }
}

/// Writes one decoded chunk into [ring], waiting out a full ring rather than
/// dropping.
///
/// A full ring is not a problem to solve, it is the throttle working: the
/// consumer is a clock, and it will make room on its own schedule. Dropping
/// here would turn "we are comfortably ahead" into a glitch. It is also what
/// makes PAUSE free: a suspended audio thread stops consuming, the ring fills,
/// and the pump blocks here until it starts again.
///
/// [interrupted] breaks the wait for a stop or a seek. Without it a paused
/// player could not be seeked — the pump would be sitting on a full ring with
/// nothing to drain it.
Future<int> _fill(
  SharedAudioRing ring,
  DecodedAudio chunk,
  bool Function() interrupted,
) async {
  var offset = 0;
  while (offset < chunk.frameCount && !interrupted()) {
    final wrote = ring.write(
      chunk.samples,
      chunk.frameCount - offset,
      sourceFrameOffset: offset,
    );
    offset += wrote;
    if (wrote == 0) await Future<void>.delayed(_kRingFullPatience);
  }
  return offset;
}

int _audioTrackIndex(List<TrackInfo> tracks) {
  for (var i = 0; i < tracks.length; i++) {
    if (tracks[i] is AudioTrackInfo) return i;
  }
  throw const CodecInitException('audio-worker', 'container has no audio track');
}

void main() => runWorker(audioPlaybackWorker);
