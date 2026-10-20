// The container writer, on a worker.
//
// `finish()` builds the whole sample index in one synchronous pass — every
// sample's duration, size, chunk offset and composition offset — and for a
// two-hour recording that is over half a million entries. On the recorder's
// normal path the isolate paying for that is the one drawing the UI, so the
// app freezes at exactly the moment a person is waiting to be told their
// session was saved.
//
// The writer itself is untouched. It runs here exactly as it runs in process,
// through the same pinned backend, so a file cannot come out different
// depending on where it was assembled.
//
// Pure Dart only, deliberately. A worker-hosted FFmpeg muxer is a different
// problem: it takes codec parameters from a live `AVCodecContext` through
// `FfmpegEncoderBridge`, which is a raw pointer into an encoder that lives on
// another isolate, and it needs every stream's extradata before it will write
// a header. Neither survives the move as-is.

import 'dart:typed_data';

import 'package:miniav_tools/miniav_tools.dart';
import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';
import 'package:spawn/spawn.dart';

/// Phases the worker reports while finishing. Kept as plain strings because
/// they cross a worker boundary; the host maps them onto its own enum.
const String muxPhaseWritingIndex = 'writingIndex';
const String muxPhaseClosing = 'closing';

/// Opens a container over the path it was spawned with, then writes packets.
Future<void> muxWorker(WorkerChannel channel) async {
  final init = channel.initialMessage! as Map<String, Object?>;
  Muxer? muxer;

  channel.handleRequests((Object? request) async {
    switch (request) {
      case 'open':
        registerFirstPartyBackends();
        final opened = await MiniAVTools.createMuxer(
          MuxerConfig(
            container: Container.values.byName(init['container']! as String),
            output: FileMuxerOutput(init['path']! as String),
            tracks: _decodeTracks(init['tracks']! as List<Object?>),
          ),
          // PIN rather than negotiate: this worker exists to host the
          // first-party writer, and a negotiation here could silently land on
          // a backend the host has already decided against.
          preference: BackendPreference.pinned(
            ContainerFramingBackend.backendName,
          ),
        );
        await opened.writeHeader();
        muxer = opened;
        return opened.backendName;

      case [
            'packet',
            final Uint8List data,
            final int ptsUs,
            final int dtsUs,
            final int durationUs,
            final bool isKeyframe,
            final int trackIndex,
          ]:
        await muxer!.writePacket(EncodedPacket(
          data: data,
          ptsUs: ptsUs,
          dtsUs: dtsUs,
          durationUs: durationUs,
          isKeyframe: isKeyframe,
          trackIndex: trackIndex,
        ));
        return null;

      case ['config', final int trackIndex, final Uint8List record]:
        final p = muxer!.platform;
        if (p is! Mp4Muxer) return null;
        return p.setTrackConfig(trackIndex, record).name;

      case 'finish':
        // Say so BEFORE the long call, not after: the whole point is that
        // somebody is waiting and wants to know what for.
        channel.send(muxPhaseWritingIndex);
        await muxer!.finish();
        final p = muxer!.platform;
        final report = <String, Object?>{
          'timingRepairs': <String>[
            if (p is Mp4Muxer)
              for (final r in p.timingReports)
                if (!r.isClean) '$r',
          ],
          'tracksMissingConfig': <int>[
            if (p is Mp4Muxer) ...p.tracksMissingConfig,
          ],
        };
        channel.send(muxPhaseClosing);
        return report;

      default:
        throw StateError('unknown mux op: $request');
    }
  });

  // Park until the host says stop. A handler that returns takes the worker
  // with it, and this one is push-driven — there is nothing to loop over.
  await channel.onClose;
  try {
    await muxer?.close();
  } catch (_) {
    // Closing a muxer that never opened, or already finished, is not a fault
    // worth failing a shutdown over.
  }
}

/// Track descriptions as primitives.
///
/// Hand-rolled rather than sending [TrackInfo] itself: these have to survive a
/// structured clone on web and a protocol registration is a lot of ceremony for
/// nine fields.
List<TrackInfo> _decodeTracks(List<Object?> raw) => [
      for (final entry in raw.cast<Map<Object?, Object?>>())
        if (entry['kind'] == 'video')
          VideoTrackInfo(
            codec: VideoCodec.values.byName(entry['codec']! as String),
            width: entry['width']! as int,
            height: entry['height']! as int,
            frameRateNumerator: entry['fpsNum']! as int,
            frameRateDenominator: entry['fpsDen']! as int,
            rotationDegrees: entry['rotation']! as int,
            extraData: _decodeExtra(entry, video: true),
          )
        else
          AudioTrackInfo(
            codec: AudioCodec.values.byName(entry['codec']! as String),
            sampleRate: entry['sampleRate']! as int,
            channels: entry['channels']! as int,
            extraData: _decodeExtra(entry, video: false),
          ),
    ];

CodecExtraData? _decodeExtra(Map<Object?, Object?> entry, {required bool video}) {
  final bytes = entry['extraData'] as Uint8List?;
  if (bytes == null || bytes.isEmpty) return null;
  final name = entry['codec']! as String;
  return video
      ? CodecExtraData.video(VideoCodec.values.byName(name), bytes)
      : CodecExtraData.audio(AudioCodec.values.byName(name), bytes);
}

/// The host-side encoding for [_decodeTracks]. Lives here so the two halves
/// cannot drift.
Map<String, Object?> encodeTrackInfo(TrackInfo info) => switch (info) {
      VideoTrackInfo() => {
          'kind': 'video',
          'codec': info.codec.name,
          'width': info.width,
          'height': info.height,
          'fpsNum': info.frameRateNumerator,
          'fpsDen': info.frameRateDenominator,
          'rotation': info.rotationDegrees,
          'extraData': info.extraData?.bytes,
        },
      AudioTrackInfo() => {
          'kind': 'audio',
          'codec': info.codec.name,
          'sampleRate': info.sampleRate,
          'channels': info.channels,
          'extraData': info.extraData?.bytes,
        },
    };
