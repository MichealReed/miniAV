/// A video track whose encoder publishes its configuration record LATE.
///
/// The writer builds `moov` at `finish()` and `stsd` with it, so the record is
/// not needed until then — but `open` refused a track without one, and the
/// recorder builds its muxer before a single frame has been encoded. A
/// hardware H.264 MFT is allowed to withhold `MF_MT_MPEG_SEQUENCE_HEADER`
/// until it has produced output; Intel's Quick Sync MFT does, NVIDIA's does
/// not. `MfVideoEncoder` already recovers the parameter sets from the first
/// keyframe — that recovery just ran after the only thing that read it.
///
/// The consequence was not a missing feature. Those machines fell back to
/// FFmpeg for the whole recording, and FFmpeg's file output carries
/// `+faststart`, which rewrites the entire multi-gigabyte file at
/// `av_write_trailer` on whatever isolate called stop.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';
import 'package:test/test.dart';

/// Annex-B SPS+PPS, the shape a Media Foundation encoder hands over.
final _annexB = Uint8List.fromList([
  0, 0, 0, 1, //
  0x67, 0x64, 0x00, 0x1f, 0xac, 0xd9, 0x40, 0x50, 0x05, 0xbb, 0x01, 0x6a,
  0x02, 0x02, 0x02, 0x80, 0x00, 0x00, 0x03, 0x00, 0x80, 0x00, 0x00, 0x1e,
  0x07, 0x8c, 0x18, 0xcb,
  0, 0, 0, 1, //
  0x68, 0xeb, 0xec, 0xb2, 0x2c,
]);

/// One Annex-B IDR, as the same encoder emits samples.
Uint8List _idr() => Uint8List.fromList([
      ...[0, 0, 0, 1],
      0x65, 0x88, 0x84, 0x00, 0x10, 0xff, 0xfe, 0xf6, 0xf0,
    ]);

VideoTrackInfo _track({Uint8List? extra}) => VideoTrackInfo(
      codec: VideoCodec.h264,
      width: 1920,
      height: 1080,
      frameRateNumerator: 30,
      frameRateDenominator: 1,
      extraData:
          extra == null ? null : CodecExtraData.video(VideoCodec.h264, extra),
    );

Mp4Muxer _open({Uint8List? extra}) => Mp4Muxer.open(MuxerConfig(
      container: Container.mp4,
      output: MuxerOutput.bytes(),
      tracks: [_track(extra: extra)],
    ));

Future<void> _feed(Mp4Muxer m, {int frames = 4}) async {
  for (var i = 0; i < frames; i++) {
    await m.writePacket(EncodedPacket(
      data: _idr(),
      ptsUs: i * 33333,
      dtsUs: i * 33333,
      durationUs: 33333,
      isKeyframe: true,
      trackIndex: 0,
    ));
  }
}

void main() {
  test('a track with no config record at open is accepted', () {
    // It used to throw here, which is what sent the whole recording to FFmpeg.
    expect(_open, returnsNormally);
  });

  test('the record supplied with the first frame produces a playable track',
      () async {
    final m = _open();
    await m.writeHeader();
    expect(m.setTrackConfig(0, _annexB), Mp4ConfigChange.added);
    await _feed(m);
    await m.finish();

    expect(m.tracksMissingConfig, isEmpty);
    expect(m.trackConfigCount(0), 1, reason: 'one sample entry, not two');

    final d = Mp4Demuxer.open(Uint8List.fromList(m.getBytes()!));
    final track = d.tracks.single as VideoTrackInfo;
    expect(track.codec, VideoCodec.h264);
    expect(track.extraData, isNotNull,
        reason: 'the container carries an avcC record');
    await d.close();
  });

  test('deferring produces the same file as supplying it at open', () async {
    // The whole point: nothing about the OUTPUT depends on when the encoder
    // got round to publishing.
    final upFront = _open(extra: _annexB);
    await upFront.writeHeader();
    await _feed(upFront);
    await upFront.finish();

    final deferred = _open();
    await deferred.writeHeader();
    deferred.setTrackConfig(0, _annexB);
    await _feed(deferred);
    await deferred.finish();

    expect(deferred.getBytes(), upFront.getBytes());
  });

  test('the deferred record also settles Annex-B sample framing', () async {
    // Decided from the config record at open; there is none, so it comes from
    // the record when it arrives. Getting this wrong writes Annex-B start
    // codes into mdat where the container promises length prefixes, and every
    // player renders nothing.
    final m = _open();
    await m.writeHeader();
    m.setTrackConfig(0, _annexB);
    await _feed(m, frames: 1);
    await m.finish();

    final bytes = Uint8List.fromList(m.getBytes()!);
    final d = Mp4Demuxer.open(bytes);
    final pkt = await d.readPacket();
    expect(pkt, isNotNull);
    // Length-prefixed: the first four bytes are the NAL length, and an
    // Annex-B start code (00 00 00 01) would mean the rewrite never happened.
    final head = pkt!.data.sublist(0, 4);
    expect(head, isNot([0, 0, 0, 1]));
    final len = (head[0] << 24) | (head[1] << 16) | (head[2] << 8) | head[3];
    expect(len, pkt.data.length - 4, reason: 'a single length-prefixed NAL');
    await d.close();
  });

  test('a track that never gets a record is reported, not thrown', () async {
    // Throwing at finish would take moov down with it — every track lost to
    // save one that was already broken. The samples are on disk either way.
    final m = _open();
    await m.writeHeader();
    await _feed(m);
    await m.finish();

    expect(m.tracksMissingConfig, [0]);
    expect(m.getBytes(), isNotNull, reason: 'the file still got written');
  });

  test('a track opened WITH a record reports nothing missing', () async {
    final m = _open(extra: _annexB);
    await m.writeHeader();
    await _feed(m);
    await m.finish();
    expect(m.tracksMissingConfig, isEmpty);
  });
}
