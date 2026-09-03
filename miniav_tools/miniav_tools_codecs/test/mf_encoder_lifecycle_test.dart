/// Session lifecycle for the MF video encoder: draining, restarting, odd frame
/// sizes and what a repeat is allowed to reproduce.
///
/// Every case here is a bug that reported success while producing nothing (or
/// producing the wrong picture), which is why they are asserted on COUNTS
/// rather than on "it did not throw":
///   - flush() then encode() wedged an async MFT forever — the drain ended the
///     stream and nothing ever restarted it, so no NeedInput ever came again;
///   - flush() stopped at the first "nothing ready right now", losing whatever
///     a hardware MFT still held in flight — the tail of every recording;
///   - a CPU frame at an odd height was rejected on its LENGTH, before
///     ProcessInput, on every single frame;
///   - a repeat after a CPU frame resubmitted a GPU surface from minutes ago.
@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';
import 'package:miniav_tools_codecs/src/codecs_native.dart';
import 'package:test/test.dart';

const _w = 640, _h = 480;

Future<MfVideoEncoder?> _open(int w, int h) => MfVideoEncoder.open(EncoderConfig(
      codec: VideoCodec.h264,
      width: w,
      height: h,
      bitrateBps: 2000000,
      frameRateNumerator: 30,
      frameRateDenominator: 1,
      gopLength: 30,
    ));

/// NV12 as a real capture supplies it: tightly packed on the frame width, with
/// FLOORED chroma rows. At an odd height that is one chroma row short of what
/// the encoder needs, which is the whole of the odd-dimension bug — the Dart
/// side has to pad it rather than hand native a buffer it must reject.
Uint8List _nv12Floor(int w, int h, int frame) {
  final y = w * h;
  final b = Uint8List(y + w * (h ~/ 2));
  for (var j = 0; j < h; j++) {
    for (var i = 0; i < w; i++) {
      b[j * w + i] = (i + j + frame * 4) & 0xFF;
    }
  }
  b.fillRange(y, b.length, 128);
  return b;
}

FrameSource _cpu(int w, int h, int frame) => FrameSource.cpu(
      bytes: _nv12Floor(w, h, frame),
      pixelFormat: MiniAVPixelFormat.nv12,
      width: w,
      height: h,
      timestampUs: frame * 33333,
    );

void main() {
  test('flush() then encode() keeps encoding, and no tail frame is lost',
      () async {
    if (!Platform.isWindows || mfencHasMft(0) == 0) {
      markTestSkipped('no H.264 encoder MFT');
      return;
    }
    final enc = await _open(_w, _h);
    expect(enc, isNotNull);
    addTearDown(() => enc!.close());

    const perSegment = 24;
    final counts = <int>[];
    for (var segment = 0; segment < 2; segment++) {
      var live = 0;
      for (var i = 0; i < perSegment; i++) {
        if (await enc!.encode(_cpu(_w, _h, segment * perSegment + i)) != null) {
          live++;
        }
      }
      final tail = await enc!.flush();
      counts.add(live + tail.length);
      // The tail is the point: a hardware MFT holds two to four frames, so a
      // flush that stopped at the first empty receive() would come back with a
      // count SHORT of what was submitted — silently, on every recording.
      expect(counts[segment], perSegment,
          reason: 'segment $segment submitted $perSegment frames but only '
              '${counts[segment]} came back (live=$live, tail=${tail.length}) '
              '— the drain returned before the MFT had finished');
    }
    // And the second segment exists at all. Before the stream-restart fix the
    // MFT stayed at end-of-stream after the first drain: no METransformNeedInput
    // was ever raised again, every submit spun to its timeout, and the shared
    // MTA worker was wedged for every session in the process.
    expect(counts[1], greaterThan(0),
        reason: 'nothing encoded after the first flush() — the MFT was never '
            'told the stream restarted');
  });

  test('flush() twice in a row is harmless', () async {
    if (!Platform.isWindows || mfencHasMft(0) == 0) {
      markTestSkipped('no H.264 encoder MFT');
      return;
    }
    final enc = await _open(_w, _h);
    expect(enc, isNotNull);
    addTearDown(() => enc!.close());
    // Count what encode() hands back too. An async MFT can raise
    // METransformHaveOutput while an encode call is still in flight, so a
    // packet legitimately arrives from either half — asserting on flush()
    // alone measures how loaded the machine is, not whether the encoder
    // works (see mf_frame_sources_test).
    var live = 0;
    for (var i = 0; i < 8; i++) {
      if (await enc!.encode(_cpu(_w, _h, i)) != null) live++;
    }
    final first = await enc!.flush();
    final second = await enc.flush();
    expect(live + first.length, 8, reason: '8 frames in, one packet each out');
    expect(second, isEmpty,
        reason: 'a second flush must not re-issue COMMAND_DRAIN or invent '
            'packets');
    // Still usable afterwards.
    final more = await enc.encode(_cpu(_w, _h, 100));
    final tail = await enc.flush();
    expect((more == null ? 0 : 1) + tail.length, greaterThan(0),
        reason: 'the session did not survive two flushes');
  });

  // ODD frame sizes, CPU path. 2576x1119 is a real window size: even width, odd
  // height, and the floored chroma height made the frame 2576 B short of what
  // native required. The error surfaced as "ProcessInput failed" — a step that
  // was never reached — on every frame.
  for (final (w, h) in const [(641, 361), (320, 241)]) {
    test('CPU NV12 at ${w}x$h encodes (odd dimensions)', () async {
      if (!Platform.isWindows || mfencHasMft(0) == 0) {
        markTestSkipped('no H.264 encoder MFT');
        return;
      }
      final enc = await _open(w, h);
      if (enc == null) {
        markTestSkipped('encoder would not open at ${w}x$h');
        return;
      }
      addTearDown(enc.close);

      var live = 0;
      for (var i = 0; i < 12; i++) {
        if (await enc.encode(_cpu(w, h, i)) != null) live++;
      }
      final tail = await enc.flush();
      expect(live + tail.length, greaterThan(0),
          reason: '${w}x$h produced nothing. NATIVE REASON: '
              '${enc.lastImportError}');
    });
  }

  test('I420 input at an odd size encodes too', () async {
    if (!Platform.isWindows || mfencHasMft(0) == 0) {
      markTestSkipped('no H.264 encoder MFT');
      return;
    }
    const w = 641, h = 361;
    final enc = await _open(w, h);
    if (enc == null) {
      markTestSkipped('encoder would not open at ${w}x$h');
      return;
    }
    addTearDown(enc.close);
    // Floored chroma planes, which is the I420 convention the facade documents.
    final cw = w ~/ 2, ch = h ~/ 2;
    final y = Uint8List(w * h);
    for (var i = 0; i < y.length; i++) {
      y[i] = i & 0xFF;
    }
    final u = Uint8List(cw * ch)..fillRange(0, cw * ch, 110);
    final v = Uint8List(cw * ch)..fillRange(0, cw * ch, 140);

    var live = 0;
    for (var i = 0; i < 12; i++) {
      final p = await enc.encode(FrameSource.yuv420p(
        yPlane: y,
        uPlane: u,
        vPlane: v,
        width: w,
        height: h,
        timestampUs: i * 33333,
      ));
      if (p != null) live++;
    }
    final tail = await enc.flush();
    expect(live + tail.length, greaterThan(0),
        reason: 'odd-size I420 produced nothing. NATIVE REASON: '
            '${enc.lastImportError}');
  });

  test('a repeat after a CPU frame declines instead of resurrecting a GPU one',
      () async {
    if (!Platform.isWindows || mfencHasMft(0) == 0) {
      markTestSkipped('no H.264 encoder MFT');
      return;
    }
    final enc = await _open(_w, _h);
    expect(enc, isNotNull);
    addTearDown(() => enc!.close());
    if (!enc!.supportsD3d11Input) {
      markTestSkipped('no D3D11 device bound (software MFT)');
      return;
    }

    final tex = mfencTestSharedBgraEx(_w, _h, 1, 1);
    expect(tex, isNot(nullptr));
    addTearDown(() => mfencTestTextureRelease(tex));

    await enc.encode(D3D11TextureFrameSource(
      texturePtr: tex.address,
      width: _w,
      height: _h,
      pixelFormat: MiniAVPixelFormat.bgra32,
      timestampUs: 0,
    ));
    // The native return code is the unambiguous signal: -1 means "nothing to
    // repeat", while repeatLastFrame() also returns null merely because no
    // packet happened to be ready.
    expect(mfencRepeatLast(enc.nativeHandleForTest, 33333, 0), isNot(-1),
        reason: 'a GPU frame must leave a repeatable surface behind');
    enc.drainForTest();

    // Now fall back to system memory. This session does not retain CPU frames,
    // so the retained GPU surface has to be DROPPED — otherwise the recorder's
    // idle duplicator fills CFR slots with a picture from before the fallback,
    // which on screen is a flashback to a minutes-old frame.
    await enc.encode(_cpu(_w, _h, 2));
    expect(mfencRepeatLast(enc.nativeHandleForTest, 66666, 0), -1,
        reason: 'the stale GPU surface was still repeatable after a CPU frame');
    expect(await enc.repeatLastFrame(99999), isNull);
  });

  test('a closed session refuses every native read instead of using it',
      () async {
    if (!Platform.isWindows || mfencHasMft(0) == 0) {
      markTestSkipped('no H.264 encoder MFT');
      return;
    }
    final enc = await _open(_w, _h);
    expect(enc, isNotNull);
    await enc!.close();
    // Each of these used to hand a FREED pointer to native strlen — a
    // use-after-free reachable from ordinary error logging.
    expect(() => enc.mftName, throwsStateError);
    expect(() => enc.lastImportError, throwsStateError);
    expect(() => enc.drainForTest(), throwsStateError);
    expect(() => enc.invalidateImports(), throwsStateError);
    expect(() => enc.supportsD3d11Input, throwsStateError);
    // close() stays idempotent.
    await enc.close();
  });
}
