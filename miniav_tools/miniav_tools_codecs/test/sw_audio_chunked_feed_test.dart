// A whole-file feed delivered in CHUNKS — the documented SwAudioDecoder
// contract ("accumulates the compressed bytes across decode calls and decodes
// them all on flush") for the two codecs that are whole-container-only.
//
// The streaming batch drain was gated on packet COUNT alone: from the second
// packet on, a buffer past the batch threshold was decoded immediately. That is
// right for MP3 (a run of self-contained frames) and fatal for FLAC/Vorbis,
// where a batch is a slice of a container — `drflac_open_memory` gets a
// truncated stream and the decoder throws CodecRuntimeException('flac', 'SW
// decode failed'). Nothing caught it because sw_audio_test feeds ONE packet and
// every fixture is smaller than one 16 KiB batch, so the drain could not fire.
//
// This test crosses the threshold on purpose: it inflates tone.flac with a FLAC
// PADDING metadata block (standard, inert — the decoded PCM is unchanged) until
// a chunked feed spans several batches.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:miniav_tools/miniav_tools.dart';
import 'package:miniav_tools_codecs/miniav_tools_codecs.dart'
    show Mp3Demuxer, SwAudioDecoder;
import 'package:test/test.dart';

/// Splice a PADDING metadata block of [padBytes] zeroes into [flac].
///
/// FLAC layout: "fLaC", then metadata blocks each headed by
/// `[last<<7 | type(7)][length(24 BE)]`. STREAMINFO (type 0) must stay first,
/// so the padding goes directly after it and inherits its last-block flag.
Uint8List _padFlac(Uint8List flac, int padBytes) {
  expect(flac.sublist(0, 4), [0x66, 0x4C, 0x61, 0x43], reason: 'fLaC magic');
  final infoLen = (flac[5] << 16) | (flac[6] << 8) | flac[7];
  final afterInfo = 8 + infoLen;
  final streamInfoWasLast = (flac[4] & 0x80) != 0;
  return (BytesBuilder()
        ..add(flac.sublist(0, 4))
        ..addByte(flac[4] & 0x7F) // STREAMINFO no longer terminates the list
        ..add(flac.sublist(5, afterInfo))
        ..addByte(streamInfoWasLast ? 0x81 : 0x01) // PADDING, type 1
        ..addByte((padBytes >> 16) & 0xFF)
        ..addByte((padBytes >> 8) & 0xFF)
        ..addByte(padBytes & 0xFF)
        ..add(Uint8List(padBytes))
        ..add(flac.sublist(afterInfo)))
      .toBytes();
}

/// Feed [data] to a fresh decoder in [chunk]-byte packets, then flush.
/// Returns (what came out during decode, everything).
Future<(List<DecodedAudio>, List<DecodedAudio>)> _feedChunked(
  AudioCodec codec,
  Uint8List data,
  int chunk,
) async {
  final dec = (await SwAudioDecoder.open(AudioDecoderConfig(codec: codec)))!;
  final duringDecode = <DecodedAudio>[];
  for (var off = 0; off < data.length; off += chunk) {
    final end = off + chunk < data.length ? off + chunk : data.length;
    duringDecode.addAll(await dec.decode(EncodedPacket(
      data: Uint8List.sublistView(data, off, end),
      ptsUs: 0,
      dtsUs: 0,
    )));
  }
  final all = [...duringDecode, ...await dec.flush()];
  await dec.close();
  return (duringDecode, all);
}

Future<DecodedAudio> _decodeWhole(AudioCodec codec, Uint8List data) async {
  final (_, out) = await _feedChunked(codec, data, data.length);
  expect(out, hasLength(1));
  return out.single;
}

void main() {
  const batchBytes = 16 * 1024; // SwAudioDecoder._batchBytes
  final tone = File('test/assets/tone.flac').readAsBytesSync();

  test('a chunked whole-file FLAC feed decodes at flush instead of throwing',
      () async {
    final padded = _padFlac(tone, 48 * 1024);
    expect(padded.length, greaterThan(3 * batchBytes),
        reason: 'the feed must span several batches, or the drain this test '
            'exists for never fires');

    final (duringDecode, all) =
        await _feedChunked(AudioCodec.flac, padded, 8 * 1024);

    expect(duringDecode, isEmpty,
        reason: 'a slice of a container is not a container — FLAC must not be '
            'batched, it must accumulate');
    expect(all, hasLength(1), reason: 'one decode, at flush');

    // Byte-for-byte the same audio as the one-packet feed of the SAME bytes...
    final wholePadded = await _decodeWhole(AudioCodec.flac, padded);
    expect(all.single.samples, wholePadded.samples);
    // ...and as the original asset, which also proves the PADDING block this
    // test splices in is inert (a positive control on the fixture itself).
    final wholeTone = await _decodeWhole(AudioCodec.flac, tone);
    expect(all.single.samples, wholeTone.samples);
    expect(all.single.sampleRate, 48000);
    expect(all.single.channels, 2);
    expect(all.single.frameCount, greaterThan(8000)); // ~0.25 s @ 48 kHz
  });

  test('a chunked Vorbis feed accumulates too', () async {
    // tone.ogg is under one batch, so this cannot cross the threshold the way
    // the FLAC case does; it pins the contract (nothing emitted before flush,
    // audio identical to a one-packet feed) for the other container codec.
    final ogg = File('test/assets/tone.ogg').readAsBytesSync();
    final (duringDecode, all) =
        await _feedChunked(AudioCodec.vorbis, ogg, 1024);
    expect(duringDecode, isEmpty);
    expect(all, hasLength(1));
    final whole = await _decodeWhole(AudioCodec.vorbis, ogg);
    expect(all.single.samples, whole.samples);
  });

  test('MP3 still batches — the FLAC gate is not a retreat from streaming',
      () async {
    // A concatenation of whole MP3 frames is a valid elementary stream, so
    // repeating the fixture's FRAMES (not the file — that would repeat its
    // tags) builds one big enough to batch, with no new asset.
    final dm = Mp3Demuxer.open(File('test/assets/tone.mp3').readAsBytesSync());
    final frames = <Uint8List>[];
    for (var p = await dm.readPacket(); p != null; p = await dm.readPacket()) {
      frames.add(p.data);
    }
    await dm.close();
    final b = BytesBuilder();
    for (var i = 0; i < 8; i++) {
      for (final f in frames) {
        b.add(f);
      }
    }
    final stream = b.toBytes();
    expect(stream.length, greaterThan(2 * batchBytes));

    final (duringDecode, _) =
        await _feedChunked(AudioCodec.mp3, stream, 4 * 1024);
    expect(duringDecode, isNotEmpty,
        reason: 'MP3 frames are self-contained; a streaming consumer must get '
            'audio before EOF');
  });
}
