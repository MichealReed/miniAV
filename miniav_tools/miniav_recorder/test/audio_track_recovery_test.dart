/// An audio device that dies mid-recording, driven through the real runtime.
///
/// The occurrence this exists for (2026-09-03): one Win+P took out a display
/// AND the HDMI render endpoint that belonged to the same monitor. The video
/// loss was reported and re-acquired. The audio just stopped — four seconds
/// absent from the file, `Loopback capture is not running` at stop, no issue
/// raised, and "Recording stopped" reported as success.
///
/// The signal had been there the whole time: WASAPI's capture thread calls
/// `lost_cb` on AUDCLNT_E_DEVICE_INVALIDATED, and `addLostListener` carries it
/// to Dart. Nothing subscribed. These tests are about the subscription and
/// what happens after it, so the platform is a pair of closures.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:miniav/miniav.dart';
import 'package:miniav_recorder/miniav_recorder.dart';
import 'package:miniav_recorder/src/recorder.dart';
import 'package:miniav_tools/miniav_tools.dart';
import 'package:test/test.dart';

class _FakeAudioEncoder implements PlatformAudioEncoder {
  @override
  Future<List<EncodedPacket>> encode({
    required Uint8List pcm,
    required MiniAVAudioFormat format,
    required int frameCount,
    required int ptsUs,
  }) async =>
      const [];

  @override
  Future<List<EncodedPacket>> flush() async => const [];

  @override
  CodecExtraData? get extraData => null;

  @override
  Future<void> close() async {}
}

/// The platform side of one audio capture: who is listening, how many times
/// it has been started, and a way to kill it.
class _Device {
  int starts = 0;
  int reacquires = 0;
  int unsubscribes = 0;

  /// What a re-acquire answers. False is the device still not being there.
  bool comesBack = true;

  MiniAVContextLostListener? _listener;

  void Function() subscribe(MiniAVContextLostListener l) {
    _listener = l;
    return () => unsubscribes++;
  }

  void die() => _listener?.call(-14);
}

/// A recorder that exists only to hand the track a master clock.
Recorder _recorder() => (RecorderBuilder()
      ..addLoopback(deviceId: 'loop')
      ..addStreamOutput((_) {}))
    .build();

AudioTrackRuntime _track(_Device dev) => AudioTrackRuntime(
      index: 0,
      label: 'loopback[DENON-AVR]',
      encoder: AudioEncoder(_FakeAudioEncoder(), 'fake'),
      encoderConfig: const AudioEncoderConfig(
        codec: AudioCodec.aac,
        sampleRate: 48000,
        channels: 2,
        bitrateBps: 128000,
      ),
      audioCodec: AudioCodec.aac,
      sampleRate: 48000,
      channels: 2,
      audioFormat: MiniAVAudioFormat.f32,
      captureCtx: Object(),
      startFn: (_) async => dev.starts++,
      stopFn: () async {},
      destroyFn: () async {},
      addLostListenerFn: dev.subscribe,
      reacquireFn: () async {
        dev.reacquires++;
        return dev.comesBack;
      },
    );

void main() {
  test('a device that dies is re-acquired, in the same track', () async {
    final dev = _Device();
    final track = _track(dev);
    await track.startCapture(_recorder());
    expect(dev.starts, 1);
    expect(track.captureStatuses.single.lost, isFalse);

    dev.die();
    // The first re-acquire attempt is on a 250 ms backoff.
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(dev.reacquires, 1);
    expect(dev.starts, 2, reason: 'the callback is re-registered');
    final s = track.captureStatuses.single;
    expect(s.lost, isFalse);
    expect(s.lossCount, 1);
    expect(s.recoveryCount, 1);
    expect(s.healthy, isFalse,
        reason: 'recovered is not the same as nothing having happened — '
            'the gap is still missing from the file');
    await track.stopCapture();
  });

  test('the outage is reported at stop, not swallowed', () async {
    final dev = _Device();
    final track = _track(dev);
    await track.startCapture(_recorder());

    dev.die();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await track.stopCapture();

    // This is the line that was missing from the session that started all of
    // this: the file is short and nothing said why.
    expect(track.captureLossSummaries.single, contains('loopback[DENON-AVR]'));
  });

  test('a device that has not come back keeps the track marked lost',
      () async {
    final dev = _Device()..comesBack = false;
    final track = _track(dev);
    await track.startCapture(_recorder());

    dev.die();
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final s = track.captureStatuses.single;
    expect(s.lost, isTrue);
    expect(s.healthy, isFalse);
    expect(dev.starts, 1, reason: 'not restarted onto a device that is gone');
    expect(dev.reacquires, greaterThanOrEqualTo(1));
    await track.stopCapture();
  });

  test('stopping unsubscribes and stops trying', () async {
    final dev = _Device()..comesBack = false;
    final track = _track(dev);
    await track.startCapture(_recorder());

    dev.die();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await track.stopCapture();
    expect(dev.unsubscribes, 1);

    final attempts = dev.reacquires;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(dev.reacquires, attempts,
        reason: 'a cancelled recovery does not keep polling a dead device');
  });

  test('a loss reported during teardown starts nothing', () async {
    // The platform fires from its own thread; the notification can land after
    // stop has begun. A recovery started here would outlive the recording.
    final dev = _Device();
    final track = _track(dev);
    await track.startCapture(_recorder());

    await track.stopCapture();
    dev.die();
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(dev.reacquires, 0);
    expect(track.captureLost, isFalse);
  });

  test('endTrack does not re-acquire, and says why', () async {
    final dev = _Device();
    final track = AudioTrackRuntime(
      index: 0,
      label: 'mic[AT2020]',
      encoder: AudioEncoder(_FakeAudioEncoder(), 'fake'),
      encoderConfig: const AudioEncoderConfig(
        codec: AudioCodec.aac,
        sampleRate: 48000,
        channels: 1,
        bitrateBps: 96000,
      ),
      audioCodec: AudioCodec.aac,
      sampleRate: 48000,
      channels: 1,
      audioFormat: MiniAVAudioFormat.f32,
      captureCtx: Object(),
      startFn: (_) async => dev.starts++,
      stopFn: () async {},
      destroyFn: () async {},
      addLostListenerFn: dev.subscribe,
      reacquireFn: () async => true,
      lossPolicy: CaptureLossPolicy.endTrack,
    );
    await track.startCapture(_recorder());

    dev.die();
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final s = track.captureStatuses.single;
    expect(s.ended, isTrue);
    expect(s.recoveryCount, 0);
    expect(dev.starts, 1);
    expect(track.captureLossSummaries.single, contains('mic[AT2020]'));
    await track.stopCapture();
  });
}
