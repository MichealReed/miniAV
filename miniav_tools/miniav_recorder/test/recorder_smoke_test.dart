/// Recorder package smoke test.
///
/// Verifies the public API surface (builder + types) loads and validates
/// inputs without requiring real capture devices.
library;

import 'dart:typed_data';

import 'package:miniav_recorder/miniav_recorder.dart';
import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';
import 'package:test/test.dart';

void main() {
  group('RecorderBuilder', () {
    test('builds with screen + mic + file sink', () {
      final b = RecorderBuilder();
      b.addScreen(displayId: 'fake-display', codec: VideoCodec.h264);
      b.addMic(deviceId: 'fake-mic', codec: AudioCodec.aac);
      b.addFileOutput('out.mkv', container: Container.mkv);
      final rec = b.build();
      expect(rec.state, RecorderState.idle);
    });

    test('builds with camera + loopback + stream sink', () {
      final chunks = <TrackChunk>[];
      final b = RecorderBuilder();
      b.addCamera(deviceId: 'fake-cam', codec: VideoCodec.h264);
      b.addLoopback(deviceId: 'fake-loop', codec: AudioCodec.opus);
      b.addStreamOutput((chunk) {
        if (chunk is TrackChunk) chunks.add(chunk);
      });
      final rec = b.build();
      expect(rec.state, RecorderState.idle);
    });

    test('build() throws when no sources', () {
      final b = RecorderBuilder();
      b.addFileOutput('out.mp4');
      expect(b.build, throwsStateError);
    });

    test('build() throws when no sinks', () {
      final b = RecorderBuilder();
      b.addMic(deviceId: 'd');
      expect(b.build, throwsStateError);
    });
  });

  group('TrackChunk', () {
    test('video chunk fields', () {
      final c = TrackChunk(
        trackIndex: 0,
        kind: TrackKind.video,
        videoCodec: VideoCodec.h264,
        ptsUs: 1000,
        dtsUs: 1000,
        durationUs: 33000,
        bytes: Uint8List(16),
        isKeyframe: true,
      );
      expect(c.kind, TrackKind.video);
      expect(c.videoCodec, VideoCodec.h264);
      expect(c.audioCodec, isNull);
      expect(c.isKeyframe, isTrue);
    });

    test('audio chunk fields', () {
      final c = TrackChunk(
        trackIndex: 1,
        kind: TrackKind.audio,
        audioCodec: AudioCodec.aac,
        ptsUs: 0,
        dtsUs: 0,
        durationUs: 23000,
        bytes: Uint8List(8),
        isKeyframe: true,
      );
      expect(c.kind, TrackKind.audio);
      expect(c.audioCodec, AudioCodec.aac);
      expect(c.videoCodec, isNull);
    });
  });
}
