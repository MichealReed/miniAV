/// The demux protocol, on every platform it has to work on.
///
/// Deliberately NOT `@TestOn('vm')`. The first version of this encoder used
/// `ByteData.setInt64`, which the VM supports and dart2js does not — so it
/// passed every test and threw the moment it ran in a browser. A protocol
/// whose whole purpose is to cross a boundary has to be tested on both sides
/// of it.
library;

import 'dart:typed_data';

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';
import 'package:test/test.dart';

void main() {
  test('packets round-trip, including large and negative timestamps', () {
    for (final ptsUs in <int>[
      0,
      1,
      -1,
      1234567,
      -1234567,
      0x7FFFFFFF,
      0x100000000,
      0x1FFFFFFFFFFFF, // ~2^49 us, past what 32 bits can hold
      -0x1FFFFFFFFFFFF,
    ]) {
      final original = EncodedPacket(
        data: Uint8List.fromList(<int>[1, 2, 3, 250]),
        ptsUs: ptsUs,
        dtsUs: ptsUs - 1,
        durationUs: 21333,
        isKeyframe: ptsUs.isEven,
        trackIndex: 3,
      );
      final decoded = PacketMessage.decode(PacketMessage(original).encode());
      expect(decoded.packet.ptsUs, ptsUs, reason: 'pts $ptsUs');
      expect(decoded.packet.dtsUs, ptsUs - 1);
      expect(decoded.packet.durationUs, 21333);
      expect(decoded.packet.isKeyframe, ptsUs.isEven);
      expect(decoded.packet.trackIndex, 3);
      expect(decoded.packet.data, original.data);
    }
  });

  test('an empty packet payload is legal', () {
    final decoded = PacketMessage.decode(
      PacketMessage(
        EncodedPacket(data: Uint8List(0), ptsUs: 0, dtsUs: 0),
      ).encode(),
    );
    expect(decoded.packet.data, isEmpty);
  });

  test('tracks round-trip with extradata and rotation', () {
    final message = TracksMessage(
      <TrackInfo>[
        VideoTrackInfo(
          codec: VideoCodec.h264,
          width: 1920,
          height: 1080,
          frameRateNumerator: 30000,
          frameRateDenominator: 1001,
          rotationDegrees: 270,
          extraData: CodecExtraData.video(
            VideoCodec.h264,
            Uint8List.fromList(<int>[1, 0x42, 0xE0, 0x1E]),
          ),
        ),
        const AudioTrackInfo(
          codec: AudioCodec.aac,
          sampleRate: 48000,
          channels: 2,
        ),
      ],
      9876543210,
      true,
    );

    final decoded = TracksMessage.decode(message.encode());
    expect(decoded.durationUs, 9876543210);
    expect(decoded.isSeekable, isTrue);
    expect(decoded.tracks, hasLength(2));

    final video = decoded.tracks[0] as VideoTrackInfo;
    expect(video.codec, VideoCodec.h264);
    expect(video.width, 1920);
    expect(video.height, 1080);
    expect(video.frameRateNumerator, 30000);
    expect(video.frameRateDenominator, 1001);
    expect(video.rotationDegrees, 270);
    expect(video.extraData!.bytes, <int>[1, 0x42, 0xE0, 0x1E]);
    expect(video.extraData!.videoCodec, VideoCodec.h264);

    final audio = decoded.tracks[1] as AudioTrackInfo;
    expect(audio.codec, AudioCodec.aac);
    expect(audio.sampleRate, 48000);
    expect(audio.channels, 2);
    expect(audio.extraData, isNull);
  });

  test('a null duration stays null', () {
    final decoded = TracksMessage.decode(
      const TracksMessage(<TrackInfo>[], null, false).encode(),
    );
    expect(decoded.durationUs, isNull);
    expect(decoded.isSeekable, isFalse);
    expect(decoded.tracks, isEmpty);
  });

  test('a truncated message is a FormatException, not a wrong answer', () {
    final full = PacketMessage(
      EncodedPacket(data: Uint8List(16), ptsUs: 5, dtsUs: 5),
    ).encode();
    expect(
      () => PacketMessage.decode(Uint8List.sublistView(full, 0, full.length - 4)),
      throwsA(isA<FormatException>()),
    );
  });
}
