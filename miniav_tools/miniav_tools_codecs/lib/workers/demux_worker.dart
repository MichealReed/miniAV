// The container demuxer, on a worker.
//
// On web this is the whole point: `Mp4Demuxer` is a couple of thousand lines
// of Dart box parsing, and running it on the UI thread is what makes playback
// stutter — the browser's own decode is already off-thread, so the parse was
// the part left holding the frame budget.
//
// The parser itself is untouched. It runs here exactly as it runs in process,
// via the same `openInProcess` the direct path uses, so a file cannot demux
// differently depending on whether a payload happened to be built.

import 'dart:typed_data';

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';
import 'package:spawn/spawn.dart';

import '../src/framing/container_backend.dart' show ContainerFramingBackend;

/// Opens a container over the bytes it was spawned with, then serves packets.
Future<void> demuxWorker(WorkerChannel channel) async {
  final init = channel.initialMessage! as Map<String, Object?>;
  PlatformDemuxer? demuxer;

  channel.handleRequests((Object? request) async {
    switch (request) {
      case 'open':
        final containerName = init['container'] as String?;
        final opened = ContainerFramingBackend.openInProcess(
          init['bytes']! as Uint8List,
          containerName == null ? null : Container.values.byName(containerName),
        );
        if (opened == null) {
          throw const CodecInitException(
            'container-worker',
            'no pure-Dart parser claims this container',
          );
        }
        demuxer = opened;
        return TracksMessage(
          opened.tracks,
          opened.durationUs,
          opened.isSeekable,
        );

      case 'read':
        final packet = await demuxer!.readPacket();
        return packet == null ? null : PacketMessage(packet);

      case ['seek', final int timestampUs]:
        await demuxer!.seek(timestampUs);
        return null;

      default:
        throw StateError('unknown op: $request');
    }
  });

  await channel.onClose;
  try {
    await demuxer?.close();
  } on Object {
    // Teardown is best effort; the host is already gone.
  }
}

void main() => runWorker(demuxWorker, protocol: registerDemuxProtocol);
