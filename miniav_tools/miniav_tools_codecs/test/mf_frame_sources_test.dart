/// The MF encoder must accept every `FrameSourceKind` its backend advertises.
///
/// This matters more than it looks: the zero-copy D3D11 branch *falls through*
/// to the CPU path whenever the shared handle can't be opened (a different
/// adapter, a driver refusal). If that fallthrough throws, a live recording
/// dies instead of degrading to a readback — so a lie in
/// `acceptedFrameSources` is a crash, not a missed optimisation.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';
import 'package:miniav_tools_codecs/src/codecs_native.dart';
import 'package:test/test.dart';

const _w = 320, _h = 240;

/// True when this machine has no H.264 encoder MFT at all — a real absence,
/// not contention. Distinguished from "busy" in [_open].
bool get _noMft => !Platform.isWindows || mfencHasMft(0) == 0;

Uint8List _nv12(int seed) {
  final y = _w * _h;
  final b = Uint8List(y + y ~/ 2);
  for (var i = 0; i < y; i++) {
    b[i] = ((i ~/ _w) + seed * 7) & 0xFF;
  }
  b.fillRange(y, b.length, 128);
  return b;
}

(Uint8List, Uint8List, Uint8List) _i420Planes(int seed) {
  final y = Uint8List(_w * _h);
  for (var i = 0; i < y.length; i++) {
    y[i] = ((i ~/ _w) + seed * 7) & 0xFF;
  }
  final cw = _w ~/ 2, ch = _h ~/ 2;
  return (y, Uint8List(cw * ch)..fillRange(0, cw * ch, 110),
      Uint8List(cw * ch)..fillRange(0, cw * ch, 140));
}

MiniAVBufferSource _cpuBuffer(MiniAVPixelFormat fmt, List<Uint8List> planes,
    List<int> strides) {
  return MiniAVBufferSource(MiniAVBuffer(
    type: MiniAVBufferType.video,
    contentType: MiniAVBufferContentType.cpu,
    timestampUs: 0,
    dataSizeBytes: planes.fold(0, (a, p) => a + p.length),
    data: MiniAVVideoBuffer(
      width: _w,
      height: _h,
      pixelFormat: fmt,
      strideBytes: strides,
      planes: planes,
    ),
  ));
}

Future<MfVideoEncoder> _open() async {
  final e = await MfVideoEncoder.open(const EncoderConfig(
    codec: VideoCodec.h264,
    width: _w,
    height: _h,
    bitrateBps: 2000000,
    frameRateNumerator: 30,
    frameRateDenominator: 1,
    gopLength: 30,
  ));
  expect(e, isNotNull, reason: 'MF H.264 encoder failed to open');
  return e!;
}

void main() {
  test('advertised frame-source kinds are all real (no CPU kind throws)',
      () async {
    if (_noMft) {
      markTestSkipped('no H.264 encoder MFT on this machine');
      return;
    }
    // Every CPU-ish kind the backend claims must survive an encode. The D3D11
    // kind needs a live capture handle, so it is covered by the zero-copy
    // branch's fallthrough instead — which is exactly what these exercise.
    final advertised = MfEncodeBackend().acceptedFrameSources;
    expect(advertised, contains(FrameSourceKind.cpu));
    expect(advertised, contains(FrameSourceKind.miniavBufferCpu));

    final (y, u, v) = _i420Planes(1);
    final cw = _w ~/ 2;
    final sources = <String, FrameSource>{
      'cpu/nv12': FrameSource.cpu(
        bytes: _nv12(1),
        pixelFormat: MiniAVPixelFormat.nv12,
        width: _w,
        height: _h,
      ),
      'cpu/i420': FrameSource.cpu(
        bytes: Uint8List.fromList([...y, ...u, ...v]),
        pixelFormat: MiniAVPixelFormat.i420,
        width: _w,
        height: _h,
      ),
      'yuv420pPlanar': FrameSource.yuv420p(
        yPlane: y,
        uPlane: u,
        vPlane: v,
        width: _w,
        height: _h,
      ),
      'miniavBufferCpu/nv12': _cpuBuffer(
        MiniAVPixelFormat.nv12,
        [
          Uint8List.sublistView(_nv12(1), 0, _w * _h),
          Uint8List.sublistView(_nv12(1), _w * _h),
        ],
        [_w, _w],
      ),
      'miniavBufferCpu/i420': _cpuBuffer(
          MiniAVPixelFormat.i420, [y, u, v], [_w, cw, cw]),
    };

    for (final entry in sources.entries) {
      final enc = await _open();
      try {
        // Two frames so the encoder is actually driven, then flush.
        //
        // Count BOTH halves. `encode` returns a packet whenever the async MFT
        // happened to raise METransformHaveOutput while that call was in
        // flight, and on a loaded machine — the marshalling hop through the one
        // process-wide MTA worker is contended by every other suite — it does
        // so for BOTH frames, leaving flush() legitimately empty. Asserting on
        // flush() alone made this a coin flip that measured machine load rather
        // than the encoder (observed: `p1=256 p2=22 flush=0`, drain complete).
        var got = 0;
        if (await enc.encode(entry.value) != null) got++;
        if (await enc.encode(entry.value) != null) got++;
        got += (await enc.flush()).length;
        // Exact, not "at least one": after a completed drain a low-latency
        // H.264 MFT owes one access unit per frame it accepted, so a short
        // count is the tail-loss bug this file exists to catch.
        expect(got, 2, reason: '${entry.key} produced $got packets for 2 frames');
      } finally {
        await enc.close();
      }
    }
  });

  test('a padded NV12 stride is repacked, not sheared', () async {
    if (_noMft) {
      markTestSkipped('no H.264 encoder MFT on this machine');
      return;
    }
    // A capture buffer whose rows are padded: feeding it verbatim would shift
    // every row and produce a diagonal smear that no assertion on packet
    // *count* would ever catch.
    const pad = 64;
    const stride = _w + pad;
    final src = Uint8List(stride * _h + stride * (_h ~/ 2));
    for (var r = 0; r < _h; r++) {
      for (var c = 0; c < _w; c++) {
        src[r * stride + c] = (r + c) & 0xFF;
      }
    }
    for (var r = 0; r < _h ~/ 2; r++) {
      src.fillRange(stride * _h + r * stride,
          stride * _h + r * stride + _w, 128);
    }

    final strided = _cpuBuffer(
      MiniAVPixelFormat.nv12,
      [
        Uint8List.sublistView(src, 0, stride * _h),
        Uint8List.sublistView(src, stride * _h),
      ],
      [stride, stride],
    );

    final enc = await _open();
    try {
      // Both halves again — with a single frame this one flipped even harder:
      // the whole 2847 B keyframe came back from encode() and flush() was
      // rightly empty.
      var got = await enc.encode(strided) == null ? 0 : 1;
      got += (await enc.flush()).length;
      expect(got, 1, reason: 'one frame in, $got packets out');
    } finally {
      await enc.close();
    }
  });

  test('an unsupported pixel format still throws a typed error', () async {
    if (_noMft) {
      markTestSkipped('no H.264 encoder MFT on this machine');
      return;
    }
    final enc = await _open();
    try {
      await expectLater(
        enc.encode(FrameSource.cpu(
          bytes: Uint8List(_w * _h * 4),
          pixelFormat: MiniAVPixelFormat.rgba32,
          width: _w,
          height: _h,
        )),
        throwsA(isA<UnsupportedFrameSourceException>()),
      );
    } finally {
      await enc.close();
    }
  });
}
