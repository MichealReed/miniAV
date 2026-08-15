// WebCodecs decode, on a worker. Web only — there is no `VideoDecoder` on the
// VM, so this file is never compiled for native and its entry is `.split`.
//
// The browser already decodes off-thread; what sat on the UI thread was our
// bridge to it — building each chunk, then yielding the event loop repeatedly
// waiting for the output callback to fire (`decode` spins up to 16 turns per
// packet). Those turns were competing with Flutter's build/raster work for the
// same frame budget. Moving the bridge here leaves the main thread with one
// postMessage per frame and no polling at all.
//
// The decoders themselves are NOT reimplemented: this hosts the very same
// `WebCodecsVideoDecoder` / `WebCodecsAudioDecoder` the in-process path uses,
// so a stream cannot decode differently depending on whether a payload was
// built. Everything here is transport.

import 'dart:typed_data';

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';
import 'package:spawn/spawn.dart';

import '../src/web/web_codecs_audio_decoder.dart';
import '../src/web/web_codecs_decoder.dart';

/// Role of a codec worker, chosen by the host in the initial message.
const String kRoleVideo = 'video';

/// See [kRoleVideo].
const String kRoleAudio = 'audio';

const String _kBackend = 'webcodecs-worker';

/// Hosts one decoder — video or audio — for the life of the worker.
///
/// One decoder per worker, matching the seam it implements: a `PlatformDecoder`
/// is created, used and closed as a unit, so its thread can be too. An A/V
/// stream therefore gets two workers, which is the right trade: they decode
/// concurrently instead of interleaving on one thread, and the payload is
/// fetched once and cached by the browser either way.
Future<void> codecWorker(WorkerChannel channel) async {
  final init = channel.initialMessage! as Map<String, Object?>;
  final role = init['role'] as String?;

  PlatformDecoder? video;
  PlatformAudioDecoder? audio;

  channel.handleRequests((Object? request) async {
    switch (request) {
      case 'open':
        // Configure here rather than at spawn time so a codec the browser
        // declines surfaces as a failed request the host can fall back from,
        // not as a worker that started and is quietly useless.
        switch (role) {
          case kRoleVideo:
            video = await WebCodecsVideoDecoder.create(_videoConfig(init));
          case kRoleAudio:
            audio = await WebCodecsAudioDecoder.create(_audioConfig(init));
          default:
            throw CodecInitException(_kBackend, 'unknown worker role: $role');
        }
        return null;

      case ['decode', final Map<String, Object?> packet]:
        final encoded = _packet(packet);
        if (video != null) return _sendFrame(await video!.decode(encoded));
        return <Object?>[
          for (final chunk in await audio!.decode(encoded)) _chunk(chunk),
        ];

      case 'flush':
        if (video != null) {
          return <Object?>[
            for (final frame in await video!.flush()) _sendFrame(frame),
          ];
        }
        return <Object?>[
          for (final chunk in await audio!.flush()) _chunk(chunk),
        ];

      default:
        throw StateError('unknown op: $request');
    }
  });

  await channel.onClose;
  try {
    await video?.close();
    await audio?.close();
  } on Object {
    // Teardown is best effort; the host is already gone.
  }
}

/// Hands a decoded frame to the host as an opaque, transferred `VideoFrame`.
///
/// Nothing is copied and nothing is read back: [PlatformValue] transfers the
/// frame itself, which is what makes this worth doing — a `VideoFrame` is a
/// handle to a surface the browser (often the GPU) already owns.
///
/// The frame's own metadata travels with it — `timestamp`, `displayWidth`,
/// `displayHeight` are all readable on the receiving side — so nothing is sent
/// alongside it that could drift out of step with the pixels.
///
/// Ownership moves with the transfer, so the wrapper is deliberately NOT
/// closed here. If the frame never leaves (an encoding failure, a dead host)
/// that would leak a decoder pool slot, so the caller closes it on that path.
Object? _sendFrame(DecodedFrame? frame) {
  if (frame == null) return null; // decoder buffering (priming / B-frames)
  final handle = frame.webVideoFrame;
  if (handle == null) {
    // A WebCodecs decoder always yields a browser frame; anything else means
    // this worker is hosting a decoder it was never meant to host.
    frame.close();
    throw const CodecRuntimeException(
      _kBackend,
      'decoder produced a non-browser frame',
    );
  }
  return PlatformValue(handle);
}

DecoderConfig _videoConfig(Map<String, Object?> init) => DecoderConfig(
  codec: VideoCodec.values.byName(init['codec']! as String),
  extraData: init['extra'] as Uint8List?,
  width: init['width'] as int?,
  height: init['height'] as int?,
  backendOptions: _options(init),
);

AudioDecoderConfig _audioConfig(Map<String, Object?> init) => AudioDecoderConfig(
  codec: AudioCodec.values.byName(init['codec']! as String),
  extraData: init['extra'] as Uint8List?,
  sampleRate: init['sampleRate'] as int?,
  channels: init['channels'] as int?,
  backendOptions: _options(init),
);

Map<String, String> _options(Map<String, Object?> init) {
  final raw = init['options'];
  if (raw is! Map<String, Object?>) return const <String, String>{};
  return <String, String>{
    for (final entry in raw.entries) entry.key: '${entry.value}',
  };
}

/// Only the three fields a WebCodecs decoder actually reads.
///
/// dts, duration and track index are the demuxer's business and are already
/// spent by the time a packet reaches a decoder; sending them would be bytes
/// on the wire per frame in exchange for nothing.
EncodedPacket _packet(Map<String, Object?> packet) => EncodedPacket(
  data: packet['data']! as Uint8List,
  ptsUs: packet['pts']! as int,
  dtsUs: packet['pts']! as int,
  isKeyframe: packet['key']! as bool,
);

/// Decoded PCM as portable values. The samples are a `Float32List`, which
/// `spawn` carries as typed data — copied, not transferred: the chunk is
/// handed straight to the audio sink and a detached buffer would silence it.
Map<String, Object?> _chunk(DecodedAudio chunk) => <String, Object?>{
  'samples': chunk.samples,
  'frames': chunk.frameCount,
  'rate': chunk.sampleRate,
  'ch': chunk.channels,
  'pts': chunk.ptsUs,
};

void main() => runWorker(codecWorker);
