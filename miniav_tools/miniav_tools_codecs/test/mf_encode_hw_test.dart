/// Hardware-engagement gate for the first-party (FFmpeg-free) MF encoder.
///
/// A plain "it encoded something" test passes identically on the software MFT,
/// so it cannot detect a silent fall back to software — which is exactly what
/// happened before hardware enumeration was fixed. These assert WHICH MFT ran.
@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:miniav_tools_codecs/src/codecs_native.dart';
import 'package:miniav_tools_codecs/src/mf/mf_video_encoder.dart';
import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';
import 'package:test/test.dart';

const _w = 640, _h = 480;

Uint8List _nv12(int seed) {
  final y = _w * _h;
  final b = Uint8List(y + y ~/ 2);
  for (var i = 0; i < y; i++) {
    b[i] = ((i ~/ _w) + seed * 7) & 0xFF; // moving gradient — real work to encode
  }
  b.fillRange(y, b.length, 128);
  return b;
}

/// Does this machine expose any hardware encoder MFT for [codecId]?
bool _hasHw(int codecId) {
  final buf = calloc<Uint8>(1024);
  try {
    return mfencListHw(codecId, buf, 1024) > 0;
  } finally {
    calloc.free(buf);
  }
}

void main() {
  for (final (codec, codecId, label) in [
    (VideoCodec.h264, 0, 'H.264'),
    (VideoCodec.hevc, 1, 'HEVC'),
  ]) {
    test('$label: encodes on a HARDWARE MFT and emits a valid bitstream', () async {
      final enc = await MfVideoEncoder.open(EncoderConfig(
        codec: codec,
        width: _w,
        height: _h,
        bitrateBps: 4000000,
        frameRateNumerator: 30,
        frameRateDenominator: 1,
        gopLength: 30,
      ));
      expect(enc, isNotNull, reason: '$label encoder failed to open');

      // Hardware is only *expected* where the OS actually lists an MFT for it;
      // elsewhere the software fallback is the correct outcome, not a failure.
      if (_hasHw(codecId)) {
        expect(enc!.isHardware, isTrue,
            reason: '$label fell back to software ("${enc.mftName}") despite a '
                'hardware MFT being available');
        expect(enc.mftName, isNotEmpty);
      }

      final packets = <EncodedPacket>[];
      for (var i = 0; i < 30; i++) {
        final p = await enc!.encode(FrameSource.cpu(
          bytes: _nv12(i),
          pixelFormat: MiniAVPixelFormat.nv12,
          width: _w,
          height: _h,
          timestampUs: i * 33333,
        ));
        if (p != null) packets.add(p);
      }
      packets.addAll(await enc!.flush());

      expect(packets, isNotEmpty, reason: 'no packets produced');
      final first = packets.first.data;
      // Annex-B start code: every conformant elementary stream begins with one.
      expect(first.length, greaterThan(4));
      expect(
        first[0] == 0 && first[1] == 0 && (first[2] == 1 || first[3] == 1),
        isTrue,
        reason: 'first packet is not Annex-B framed',
      );
      expect(packets.any((p) => p.isKeyframe), isTrue,
          reason: 'no keyframe emitted');

      await enc.close();
    });
  }
}
