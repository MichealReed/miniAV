/// The two `MfVideoEncoder.flush()` faults that used to be SILENT, reached with
/// an MFT told to misbehave.
///
///   1. The drain never completes. Before the throw, the 2 s poll simply expired
///      and whatever had come out so far was returned as if it were a complete
///      stream — a recording missing its tail, with success reported at every
///      step.
///   2. The session accepted frames and the MFT produced nothing for any of
///      them, yet reported its drain complete. Before the throw that was an
///      empty list, indistinguishable from an ordinary empty flush (which is a
///      NORMAL answer — see mf_encoder_lifecycle_test). It is a video track with
///      no video.
///
/// Neither is reachable on working hardware, so the alternative to injecting
/// them is not testing them: `mfencSetFault` makes ONE session behave that way.
/// It is scoped to the session handle rather than to the process because
/// `dart test` runs every test file in its own isolate inside a SINGLE process —
/// a global switch (or an environment variable) would inject the fault into
/// whatever else happened to be encoding at the same moment.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';
import 'package:miniav_tools_codecs/src/codecs_native.dart';
import 'package:test/test.dart';

const _w = 320, _h = 240;

/// Mirrors `MfVideoEncoder._flushTimeout`. The timing assertions below are what
/// distinguish the two faults from each other: case 1 can only be reported
/// after the wait expires, case 2 only before it.
const _flushTimeout = Duration(seconds: 2);

const _faultNone = 0;
const _faultNeverDrain = 1;
const _faultNoOutput = 2;

Future<MfVideoEncoder?> _open() => MfVideoEncoder.open(const EncoderConfig(
      codec: VideoCodec.h264,
      width: _w,
      height: _h,
      bitrateBps: 2000000,
      frameRateNumerator: 30,
      frameRateDenominator: 1,
      gopLength: 30,
    ));

FrameSource _cpu(int frame) {
  final y = _w * _h;
  final b = Uint8List(y + y ~/ 2);
  for (var j = 0; j < _h; j++) {
    for (var i = 0; i < _w; i++) {
      b[j * _w + i] = (i + j + frame * 4) & 0xFF;
    }
  }
  b.fillRange(y, b.length, 128);
  return FrameSource.cpu(
    bytes: b,
    pixelFormat: MiniAVPixelFormat.nv12,
    width: _w,
    height: _h,
    timestampUs: frame * 33333,
  );
}

Future<Object?> _flushError(MfVideoEncoder enc) async {
  try {
    await enc.flush();
    return null;
  } catch (e) {
    return e;
  }
}

void main() {
  test('a drain that never completes fails the flush and KEEPS the packets',
      () async {
    if (!Platform.isWindows || mfencHasMft(0) == 0) {
      markTestSkipped('no H.264 encoder MFT');
      return;
    }
    final enc = await _open();
    expect(enc, isNotNull);
    addTearDown(() => enc!.close());

    // Real frames first: the packets this produces are what the failed flush
    // has to hand back afterwards.
    for (var i = 0; i < 12; i++) {
      await enc!.encode(_cpu(i));
    }
    expect(mfencSetFault(enc!.nativeHandleForTest, _faultNeverDrain), 0,
        reason: 'fault injection is not available in this build');

    final sw = Stopwatch()..start();
    final err = await _flushError(enc);
    sw.stop();

    expect(err, isA<CodecRuntimeException>(),
        reason: 'a drain that never completes must not return a truncated tail '
            'as a finished stream');
    // The MESSAGE has to name the condition. "Something threw" would still pass
    // if flush() failed for an unrelated reason.
    expect('$err', contains('never finished draining'));
    expect('$err', contains('tail of this stream is incomplete'));
    // Only the timeout branch can report this, so it cannot have been reported
    // before the timeout elapsed.
    expect(sw.elapsed, greaterThanOrEqualTo(_flushTimeout),
        reason: 'the wait loop exited early — it did not reach the timeout');

    // The packets that DID come out are real, and the whole point of leaving
    // _pending intact is that a caller can salvage them. The message reports how
    // many are being held; a second flush must return exactly those.
    final held = RegExp(r'after (\d+) packet\(s\)').firstMatch('$err');
    expect(held, isNotNull, reason: 'the message must say how many are held');
    final heldCount = int.parse(held!.group(1)!);
    expect(heldCount, greaterThan(0),
        reason: 'nothing was pending, so this run cannot prove the salvage '
            'path — the MFT handed every packet back through encode()');

    expect(mfencSetFault(enc.nativeHandleForTest, _faultNone), 0);
    final salvaged = await enc.flush();
    expect(salvaged.length, heldCount,
        reason: 'the failed flush dropped the packets it said it was holding');
    expect(salvaged.every((p) => p.data.isNotEmpty), isTrue);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('an MFT that accepts frames and emits none fails the flush', () async {
    if (!Platform.isWindows || mfencHasMft(0) == 0) {
      markTestSkipped('no H.264 encoder MFT');
      return;
    }
    final enc = await _open();
    expect(enc, isNotNull);
    addTearDown(() => enc!.close());
    // Set BEFORE the first frame: this fault is about a session that produced
    // nothing across its whole life, so not one packet may escape.
    expect(mfencSetFault(enc!.nativeHandleForTest, _faultNoOutput), 0,
        reason: 'fault injection is not available in this build');

    var live = 0;
    for (var i = 0; i < 8; i++) {
      if (await enc.encode(_cpu(i)) != null) live++;
    }
    expect(live, 0, reason: 'the injected fault let a packet through');

    final sw = Stopwatch()..start();
    final err = await _flushError(enc);
    sw.stop();

    expect(err, isA<CodecRuntimeException>(),
        reason: 'a session that swallowed every frame must not report an '
            'ordinary empty flush');
    expect('$err', contains('empty video track'));
    // Distinguishes this from fault 1: the drain reported COMPLETE, so the
    // answer came from the "produced nothing" check and not from the timeout.
    expect(sw.elapsed, lessThan(_flushTimeout),
        reason: 'this went through the wedged-drain timeout instead — the '
            'test would be passing on the wrong exception');
    expect(RegExp(r'accepted [1-9]\d* frame').hasMatch('$err'), isTrue,
        reason: 'the message must say how many frames were accepted; got $err');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('fault injection is inert by default and rejects unknown modes',
      () async {
    if (!Platform.isWindows || mfencHasMft(0) == 0) {
      markTestSkipped('no H.264 encoder MFT');
      return;
    }
    final enc = await _open();
    expect(enc, isNotNull);
    addTearDown(() => enc!.close());
    // Nothing was set, so this session must behave exactly like every other.
    var live = 0;
    for (var i = 0; i < 8; i++) {
      if (await enc!.encode(_cpu(i)) != null) live++;
    }
    final tail = await enc!.flush();
    expect(live + tail.length, 8, reason: '8 frames in, one packet each out');
    // An unknown mode must not silently arm something.
    expect(mfencSetFault(enc.nativeHandleForTest, 7), -1);
    expect(mfencSetFault(enc.nativeHandleForTest, -1), -1);
  });
}
