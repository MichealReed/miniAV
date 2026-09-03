// Rotation survives the first-party MP4 mux → demux round trip.
//
// The demuxer already READ the tkhd display matrix; the muxer always wrote the
// unity matrix, so a recorder-produced portrait clip came back as
// rotationDegrees == 0 and played sideways. Both halves now agree.
//
// Sign convention is CLOCKWISE — the same one miniav_player consumes
// (`RotatedBox(quarterTurns: rotationDegrees ~/ 90)`, and Flutter's quarterTurns
// is clockwise). The (a,b,c,d) values asserted here byte-for-byte are what an
// ffmpeg-written `-display_rotation -90` file carries, which is why the foreign
// fixture and a self-muxed file must report the same number.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';
import 'package:test/test.dart';

const _avcC = [1, 0x64, 0, 0x1f, 0xff, 0xe1]; // stub avcC; nothing decodes it

Future<Uint8List> _muxRotated(int rotationDegrees) async {
  final m = Mp4Muxer.open(MuxerConfig(
    container: Container.mp4,
    output: MuxerOutput.bytes(),
    tracks: [
      VideoTrackInfo(
        codec: VideoCodec.h264,
        width: 1080,
        height: 1920,
        frameRateNumerator: 30,
        frameRateDenominator: 1,
        rotationDegrees: rotationDegrees,
        extraData: CodecExtraData.video(
            VideoCodec.h264, Uint8List.fromList(_avcC)),
      ),
    ],
  ));
  await m.writeHeader();
  for (var i = 0; i < 4; i++) {
    await m.writePacket(EncodedPacket(
      data: Uint8List.fromList(List.generate(16, (j) => (i * 7 + j) & 0xFF)),
      ptsUs: i * 33333,
      dtsUs: i * 33333,
      isKeyframe: i == 0,
      trackIndex: 0,
    ));
  }
  await m.finish();
  return Uint8List.fromList(m.getBytes()!);
}

/// The 9 matrix entries of the first video tkhd, read straight out of the file.
///
/// Deliberately independent of `Mp4Demuxer._tkhdRotation`: if writer and reader
/// shared a sign error, a pure round-trip assertion would still pass.
List<int> _tkhdMatrix(Uint8List mp4) {
  final d = ByteData.sublistView(mp4);
  final off = _tkhdMatrixOffset(mp4);
  return [for (var i = 0; i < 9; i++) d.getInt32(off + i * 4, Endian.big)];
}

/// Byte offset of `matrix[0]` in the first video tkhd.
int _tkhdMatrixOffset(Uint8List mp4) {
  final d = ByteData.sublistView(mp4);
  // Walk top-level boxes → moov → trak → tkhd.
  int? find(int start, int end, String type) {
    var p = start;
    while (p + 8 <= end) {
      final size = d.getUint32(p, Endian.big);
      final t = String.fromCharCodes(mp4.sublist(p + 4, p + 8));
      if (t == type) return p;
      if (size < 8) return null;
      p += size;
    }
    return null;
  }

  final moov = find(0, mp4.length, 'moov')!;
  final moovEnd = moov + d.getUint32(moov, Endian.big);
  final trak = find(moov + 8, moovEnd, 'trak')!;
  final trakEnd = trak + d.getUint32(trak, Endian.big);
  final tkhd = find(trak + 8, trakEnd, 'tkhd')!;
  final payload = tkhd + 8; // size + type
  final version = d.getUint8(payload);
  // version+flags(4) + [times/id/reserved/duration] + reserved(8) + layer(2)
  // + alt_group(2) + volume(2) + reserved(2)  →  matrix[0]
  return payload + 4 + (version == 1 ? 32 : 20) + 16;
}

const _one = 0x00010000, _w = 0x40000000;

/// The nine tkhd matrix entries ffmpeg writes for `-display_rotation -90`,
/// recorded verbatim from `test/assets/rot90.mp4`.
///
/// This is the golden the sign convention rests on, so it is a CONSTANT rather
/// than a read of that file: the fixture is untracked (`*.mp4` is gitignored
/// repo-wide), so a fixture-only check skips green on CI and every fresh clone
/// — i.e. it would guarantee the convention nowhere but the machine that
/// generated it. The test below re-verifies the constant against the file when
/// it happens to be present.
const _ffmpegRot90Matrix = [0, _one, 0, -_one, 0, 0, 0, 0, _w];

const _unityMatrix = [_one, 0, 0, 0, _one, 0, 0, 0, _w];

void main() {
  test('muxed rotation 90 demuxes back as 90, with the expected matrix',
      () async {
    final mp4 = await _muxRotated(90);
    expect(_tkhdMatrix(mp4), _ffmpegRot90Matrix,
        reason: 'clockwise 90 is (a,b,c,d) = (0,1,-1,0)');

    final dm = Mp4Demuxer.open(mp4);
    final v = dm.tracks.whereType<VideoTrackInfo>().single;
    expect(v.rotationDegrees, 90);
    // The matrix declares the orientation; the coded size must NOT be swapped
    // too, or a player that honours both rotates the picture twice.
    expect(v.width, 1080);
    expect(v.height, 1920);
    await dm.close();
  });

  test('180 and 270 round-trip; 0 stays unity', () async {
    for (final deg in [0, 180, 270]) {
      final mp4 = await _muxRotated(deg);
      final dm = Mp4Demuxer.open(mp4);
      expect(dm.tracks.whereType<VideoTrackInfo>().single.rotationDegrees, deg,
          reason: 'rotation $deg did not survive the round trip');
      await dm.close();
    }
    expect(_tkhdMatrix(await _muxRotated(0)), _unityMatrix);
  });

  test('an out-of-range rotation writes unity rather than a bogus transform',
      () async {
    // 45° has no matrix the reader can name; unity is the honest fallback.
    final mp4 = await _muxRotated(45);
    expect(_tkhdMatrix(mp4), _unityMatrix);
    final dm = Mp4Demuxer.open(mp4);
    expect(dm.tracks.whereType<VideoTrackInfo>().single.rotationDegrees, 0);
    await dm.close();
  });

  test('audio-only tracks still write the unity matrix', () async {
    final m = Mp4Muxer.open(MuxerConfig(
      container: Container.mp4,
      output: MuxerOutput.bytes(),
      tracks: const [
        AudioTrackInfo(codec: AudioCodec.aac, sampleRate: 44100, channels: 2),
      ],
    ));
    await m.writeHeader();
    await m.writePacket(EncodedPacket(
        data: Uint8List(8), ptsUs: 0, dtsUs: 0, trackIndex: 0));
    await m.finish();
    expect(_tkhdMatrix(Uint8List.fromList(m.getBytes()!)), _unityMatrix);
  });

  test('a foreign un-rotated MP4 still reports 0', () async {
    final f = File('test/assets/bframes.mp4');
    if (!f.existsSync()) {
      markTestSkipped('bframes.mp4 fixture absent');
      return;
    }
    final dm = Mp4Demuxer.open(f.readAsBytesSync());
    expect(dm.tracks.whereType<VideoTrackInfo>().single.rotationDegrees, 0);
    await dm.close();
  });

  test('the recorded ffmpeg matrix is what this muxer writes, and reads back '
      'as 90', () async {
    // Cross-writer agreement on the exact bytes, not just on the decoded
    // number: ffmpeg's -display_rotation -90 produces _ffmpegRot90Matrix, and
    // this muxer must emit the same nine entries for rotationDegrees: 90.
    // Unlike the fixture check below, this one runs everywhere.
    expect(_tkhdMatrix(await _muxRotated(90)), _ffmpegRot90Matrix);

    // And the READER independently agrees, on bytes it did not produce: splice
    // the recorded foreign matrix into a self-muxed unity file and demux it.
    // A writer+reader sign flip that cancels in a pure round trip does not
    // cancel here, because the matrix under test came from ffmpeg.
    final spliced = await _muxRotated(0);
    final off = _tkhdMatrixOffset(spliced);
    final d = ByteData.sublistView(spliced);
    for (var i = 0; i < 9; i++) {
      d.setInt32(off + i * 4, _ffmpegRot90Matrix[i], Endian.big);
    }
    final dm = Mp4Demuxer.open(spliced);
    expect(dm.tracks.whereType<VideoTrackInfo>().single.rotationDegrees, 90,
        reason: "ffmpeg's own -display_rotation -90 matrix must read as 90");
    await dm.close();
  });

  test('the ffmpeg fixture still carries the recorded matrix', () async {
    final f = File('test/assets/rot90.mp4');
    if (!f.existsSync()) {
      // Expected off this machine: test/assets/*.mp4 is gitignored repo-wide.
      // The convention itself is covered by the constant, asserted above.
      markTestSkipped('rot90.mp4 fixture absent (generate with ffmpeg CLI)');
      return;
    }
    expect(_tkhdMatrix(f.readAsBytesSync()), _ffmpegRot90Matrix,
        reason: 'the recorded golden no longer matches the file it came from');
  });
}
