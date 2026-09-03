/// Container display rotation surfaces as `VideoTrackInfo.rotationDegrees`.
///
/// A phone-shot "sideways" video stores frames in coded orientation and
/// declares the turn in the container (MP4 `tkhd` transformation matrix →
/// libavformat `AV_PKT_DATA_DISPLAYMATRIX` stream side data). Before the shim
/// read that side data the demuxer reported 0 for every container, so such a
/// file rendered sideways.
///
/// Fixtures are produced by this package's own FFmpeg encode+mux path (no CLI
/// dependency): mux a plain MP4, then rewrite the video track's `tkhd` matrix
/// in place — same bytes a rotating muxer would have written, and the only
/// place the rotation lives, so the assertion is on the real demux path.
///
/// SIGN CONVENTION verified here: degrees CLOCKWISE, matching
/// `VideoTrackInfo.rotationDegrees` and miniav_player's
/// `RotatedBox(quarterTurns: rotationDegrees ~/ 90)`.
@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:miniav_tools_ffmpeg/miniav_tools_ffmpeg.dart';
import 'package:test/test.dart';

const int kW = 160;
const int kH = 120;
const int kFps = 15;
const int kFrames = 6;

/// 16.16 fixed-point 1.0, as used by the ISO-BMFF transformation matrix.
const int _one = 0x10000;
const int _w = 0x40000000; // 2.30 fixed-point 1.0 for matrix[8]

/// Encode a few frames of synthetic video and mux to an in-memory MP4.
/// [rotationDegrees] is declared on the track, i.e. written by the muxer.
Future<Uint8List> _muxPlainMp4({int rotationDegrees = 0}) async {
  final backend = FfmpegBackend();
  final v = (await backend.createEncoder(
    const EncoderConfig(
      codec: VideoCodec.h264,
      width: kW,
      height: kH,
      bitrateBps: 400000,
      gopLength: 3,
      frameRateNumerator: kFps,
      frameRateDenominator: 1,
      backendOptions: {'global_header': '1', 'sw_isolate': '0'},
    ),
  ))!;

  final muxer = FfmpegMuxer.open(
    MuxerConfig(
      container: Container.mp4,
      output: const BytesMuxerOutput(),
      tracks: [
        VideoTrackInfo(
          codec: VideoCodec.h264,
          width: kW,
          height: kH,
          frameRateNumerator: kFps,
          frameRateDenominator: 1,
          rotationDegrees: rotationDegrees,
        ),
      ],
    ),
    encoderForTrack: {0: v as FfmpegEncoderBridge},
  );
  await muxer.writeHeader();

  final rgba = Uint8List(kW * kH * 4);
  for (var i = 0; i < kFrames; i++) {
    for (var y = 0; y < kH; y++) {
      for (var x = 0; x < kW; x++) {
        final off = (y * kW + x) * 4;
        rgba[off] = (x + i * 8) % 256;
        rgba[off + 1] = (y + i * 4) % 256;
        rgba[off + 2] = 64;
        rgba[off + 3] = 255;
      }
    }
    final p = await v.encode(
      FrameSource.cpu(
        bytes: rgba,
        pixelFormat: MiniAVPixelFormat.rgba32,
        width: kW,
        height: kH,
        timestampUs: (i * 1000000) ~/ kFps,
      ),
    );
    if (p != null) await muxer.writePacket(p.copyWith(trackIndex: 0));
  }
  for (final p in await v.flush()) {
    await muxer.writePacket(p.copyWith(trackIndex: 0));
  }

  await muxer.finish();
  final bytes = Uint8List.fromList(muxer.getBytes()!);
  await muxer.close();
  await v.close();
  return bytes;
}

// --- Minimal ISO-BMFF surgery ----------------------------------------------
// Only enough box walking to reach moov/trak/tkhd and rewrite the 3x3 matrix
// in place (sizes never change, so no re-layout is needed).

class _Box {
  _Box(this.type, this.payloadStart, this.end);
  final String type;
  final int payloadStart;
  final int end;
}

List<_Box> _boxes(ByteData d, int start, int end) {
  final out = <_Box>[];
  var p = start;
  while (p + 8 <= end) {
    var size = d.getUint32(p, Endian.big);
    final type = String.fromCharCodes([
      for (var i = 0; i < 4; i++) d.getUint8(p + 4 + i),
    ]);
    var header = 8;
    if (size == 1) {
      if (p + 16 > end) break;
      size = d.getUint64(p + 8, Endian.big);
      header = 16;
    } else if (size == 0) {
      size = end - p;
    }
    if (size < header || p + size > end) break;
    out.add(_Box(type, p + header, p + size));
    p += size;
  }
  return out;
}

_Box? _child(ByteData d, _Box parent, String type) {
  for (final b in _boxes(d, parent.payloadStart, parent.end)) {
    if (b.type == type) return b;
  }
  return null;
}

/// Rewrite the video track's `tkhd` matrix to declare [clockwise] degrees.
/// Returns a fresh buffer; the input is left untouched.
Uint8List _withTkhdRotation(Uint8List src, int clockwise) {
  // ISO-BMFF matrix order: [a b u; c d v; x y w].
  final (a, b, c, e) = switch (clockwise) {
    0 => (_one, 0, 0, _one),
    90 => (0, _one, -_one, 0),
    180 => (-_one, 0, 0, -_one),
    270 => (0, -_one, _one, 0),
    _ => throw ArgumentError('unsupported rotation $clockwise'),
  };
  return _withTkhdMatrix(src, a, b, c, e);
}

/// Rewrite the video track's `tkhd` 2x2 to an arbitrary (a,b,c,d) — used for
/// the matrices that are NOT plain turns (flips, non-quadrant transforms).
Uint8List _withTkhdMatrix(Uint8List src, int a, int b, int c, int e) {
  final bytes = Uint8List.fromList(src);
  final d = ByteData.sublistView(bytes);
  final moov = _boxes(d, 0, bytes.length).firstWhere((b) => b.type == 'moov');
  var patched = 0;
  for (final trak in _boxes(d, moov.payloadStart, moov.end)) {
    if (trak.type != 'trak') continue;
    final mdia = _child(d, trak, 'mdia');
    final hdlr = mdia == null ? null : _child(d, mdia, 'hdlr');
    if (hdlr == null) continue;
    // hdlr payload: version+flags(4) + pre_defined(4) + handler_type(4cc).
    final handler = String.fromCharCodes([
      for (var i = 0; i < 4; i++) d.getUint8(hdlr.payloadStart + 8 + i),
    ]);
    if (handler != 'vide') continue;
    final tkhd = _child(d, trak, 'tkhd');
    if (tkhd == null) continue;
    final version = d.getUint8(tkhd.payloadStart);
    // version+flags(4) + times/id/duration (v1: 32, v0: 20) + reserved(8) +
    // layer(2) + alternate_group(2) + volume(2) + reserved(2) → matrix[0].
    final m = tkhd.payloadStart + 4 + (version == 1 ? 32 : 20) + 16;
    expect(m + 36, lessThanOrEqualTo(tkhd.end), reason: 'tkhd too short');
    for (var i = 0; i < 9; i++) {
      d.setInt32(m + i * 4, 0, Endian.big);
    }
    d.setInt32(m, a, Endian.big);
    d.setInt32(m + 4, b, Endian.big);
    d.setInt32(m + 12, c, Endian.big);
    d.setInt32(m + 16, e, Endian.big);
    d.setInt32(m + 32, _w, Endian.big);
    patched++;
  }
  expect(patched, 1, reason: 'expected exactly one video trak to patch');
  return bytes;
}

void main() {
  final enabled =
      Platform.environment['MINIAV_TOOLS_FFMPEG_NETTEST'] == '1' ||
      tryLoadFFmpeg();
  final skip = enabled
      ? null
      : 'set MINIAV_TOOLS_FFMPEG_NETTEST=1 to run (auto-downloads FFmpeg)';

  late Uint8List plain;

  setUpAll(() async {
    if (!enabled) return;
    await ensureFFmpegLoaded();
    plain = await _muxPlainMp4();
  });

  test('shim exports the rotation reader (ABI freshness)', skip: skip, () {
    final shim = FfmpegShim.tryLoad();
    expect(shim, isNotNull, reason: 'shim must load for the demuxer at all');
    // A stale DLL either fails the ABI check above (tryLoad returns null) or
    // would throw on the missing symbol below.
    expect(shim!.streamRotationDegrees(nullptr), 0);
  });

  test('un-rotated MP4 keeps rotationDegrees == 0', skip: skip, () async {
    final dem = FfmpegDemuxer.openBytes(plain);
    final v = dem.tracks.whereType<VideoTrackInfo>().single;
    expect(v.rotationDegrees, 0);
    await dem.close();
  });

  test('tkhd display matrix → clockwise 90/180/270', skip: skip, () async {
    for (final deg in [90, 180, 270]) {
      final dem = FfmpegDemuxer.openBytes(_withTkhdRotation(plain, deg));
      final v = dem.tracks.whereType<VideoTrackInfo>().single;
      expect(
        v.rotationDegrees,
        deg,
        reason: 'display matrix for $deg deg clockwise must read back as $deg',
      );
      // Coded dimensions must NOT be swapped — the consumer applies the turn.
      expect(v.width, kW);
      expect(v.height, kH);
      await dem.close();
    }
  });

  // A display matrix that is not a plain turn carries no orientation this API
  // can express. Deriving an angle from it (atan2 + snap) cannot tell a flip
  // from a turn — a pure horizontal flip comes out as 180 — so a mirrored
  // clip would be rendered upside down, and the sibling first-party MP4
  // reader would disagree about the very same file.
  test('flip / arbitrary display matrices read as 0', skip: skip, () async {
    const cases = <String, (int, int, int, int)>{
      'horizontal flip': (-_one, 0, 0, _one),
      'vertical flip': (_one, 0, 0, -_one),
      '90 + horizontal flip': (0, _one, _one, 0),
      '45 degrees': (46341, 46341, -46341, 46341), // 0.7071 in 16.16
      '2x scale, no turn': (2 * _one, 0, 0, 2 * _one),
    };
    for (final entry in cases.entries) {
      final (a, b, c, e) = entry.value;
      final dem = FfmpegDemuxer.openBytes(_withTkhdMatrix(plain, a, b, c, e));
      final v = dem.tracks.whereType<VideoTrackInfo>().single;
      expect(
        v.rotationDegrees,
        0,
        reason: '${entry.key} is not a supported turn and must read as 0',
      );
      await dem.close();
    }
  });

  test('muxer writes VideoTrackInfo.rotationDegrees', skip: skip, () async {
    for (final deg in [90, 180, 270]) {
      final bytes = await _muxPlainMp4(rotationDegrees: deg);
      final dem = FfmpegDemuxer.openBytes(bytes);
      final v = dem.tracks.whereType<VideoTrackInfo>().single;
      expect(
        v.rotationDegrees,
        deg,
        reason: 'a track declaring $deg deg must round-trip through the muxer',
      );
      expect(v.width, kW);
      expect(v.height, kH);
      await dem.close();
    }
  });

  test('muxer rejects a rotation it cannot express', skip: skip, () {
    // Loud, not silent: a container can only carry quadrant turns here, and a
    // dropped orientation is invisible until playback.
    expect(
      () => FfmpegMuxer.open(
        MuxerConfig(
          container: Container.mp4,
          output: const BytesMuxerOutput(),
          tracks: [
            VideoTrackInfo(
              codec: VideoCodec.h264,
              width: kW,
              height: kH,
              frameRateNumerator: kFps,
              frameRateDenominator: 1,
              rotationDegrees: 45,
            ),
          ],
        ),
      ),
      throwsA(isA<CodecInitException>()),
    );
  });

  test('rotation survives the isolate demuxer host', skip: skip, () async {
    final tmp = File(
      '${Directory.systemTemp.path}/miniav_rotation_metadata.mp4',
    );
    if (tmp.existsSync()) tmp.deleteSync();
    tmp.writeAsBytesSync(_withTkhdRotation(plain, 90));
    final dem = (await FfmpegBackend().createDemuxer(
      DemuxerConfig(input: DemuxerInput.file(tmp.path)),
    ))!;
    final v = dem.tracks.whereType<VideoTrackInfo>().single;
    expect(v.rotationDegrees, 90);
    await dem.close();
    if (tmp.existsSync()) tmp.deleteSync();
  });
}
