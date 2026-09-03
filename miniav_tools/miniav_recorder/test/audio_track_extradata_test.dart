/// What an audio track tells the MUXER about itself.
///
/// `Recorder._buildSink` builds `MuxerConfig.tracks` out of `toTrackInfo()`,
/// and that is the ONLY place a first-party muxer learns a codec's private
/// header. The video runtime passed its `extraData`; both audio runtimes did
/// not, so `Mp4Muxer`/`OggMuxer` fell back to synthesising an OpusHead — and a
/// synthesised OpusHead has PreSkip = 0, which discards the encoder's lookahead
/// and plays every recorded sample ~6.5 ms late against video.
///
/// The two audio runtimes are library-private and their constructors are only
/// reached from a live capture device, so the wiring itself is asserted over
/// the source (the invariant is exactly "every audio TrackInfo the recorder
/// builds passes extraData"), and the consequence of breaking it is asserted
/// against the real muxer below.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:miniav_tools/miniav_tools.dart';
import 'package:miniav_tools_codecs/miniav_tools_codecs.dart' show Mp4Muxer;
import 'package:test/test.dart';

/// An OpusHead with a non-zero pre-skip — what a real `OpusAudioEncoder`
/// exposes. 312 is libopus's usual lookahead at 48 kHz.
const int _preSkip = 312;

Uint8List _opusHead() {
  final b = Uint8List(19)
    ..setRange(0, 8, 'OpusHead'.codeUnits)
    ..[8] = 1
    ..[9] = 2;
  final bd = ByteData.sublistView(b);
  bd.setUint16(10, _preSkip, Endian.little);
  bd.setUint32(12, 48000, Endian.little);
  return b;
}

/// [source] with `//` comments removed. Without this the scan below reads a
/// commented-out argument as a live one — which is exactly how a revert of the
/// fix looks, so the check would pass on broken code.
String _stripLineComments(String source) => source
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i < 0 ? l : l.substring(0, i);
    })
    .join('\n');

/// The argument list of every `AudioTrackInfo(` construction in [source],
/// paren-matched so a nested call cannot end one early.
List<String> _audioTrackInfoArgs(String rawSource) {
  final source = _stripLineComments(rawSource);
  const needle = 'AudioTrackInfo(';
  final out = <String>[];
  for (var i = source.indexOf(needle); i >= 0;
      i = source.indexOf(needle, i + 1)) {
    // `VideoTrackInfo(` / `is AudioTrackInfo` etc. must not match.
    final before = i == 0 ? ' ' : source[i - 1];
    if (RegExp(r'[A-Za-z0-9_]').hasMatch(before)) continue;
    var depth = 0;
    final start = i + needle.length - 1;
    for (var j = start; j < source.length; j++) {
      final c = source[j];
      if (c == '(') depth++;
      if (c == ')') {
        depth--;
        if (depth == 0) {
          out.add(source.substring(start + 1, j));
          break;
        }
      }
    }
  }
  return out;
}

/// Payload of the first box named [type], scanned flat over the file.
Uint8List? _findBox(Uint8List b, String type) {
  final t = type.codeUnits;
  for (var i = 0; i + 8 <= b.length; i++) {
    if (b[i + 4] == t[0] &&
        b[i + 5] == t[1] &&
        b[i + 6] == t[2] &&
        b[i + 7] == t[3]) {
      final size = (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
      if (size >= 8 && i + size <= b.length) {
        return Uint8List.sublistView(b, i + 8, i + size);
      }
    }
  }
  return null;
}

Future<Uint8List> _muxM4a(AudioTrackInfo track) async {
  final m = Mp4Muxer.open(MuxerConfig(
    container: Container.m4a,
    output: MuxerOutput.bytes(),
    tracks: [track],
  ));
  await m.writeHeader();
  for (var i = 0; i < 4; i++) {
    await m.writePacket(EncodedPacket(
      data: Uint8List.fromList([0x78, 0x00, 0x01, 0x02]),
      ptsUs: i * 20000,
      dtsUs: i * 20000,
      durationUs: 20000,
      isKeyframe: true,
    ));
  }
  await m.finish();
  return Uint8List.fromList(m.getBytes()!);
}

void main() {
  group('every audio track the recorder describes carries its extra data', () {
    late List<String> args;

    setUpAll(() {
      final src = File('lib/src/recorder.dart').readAsStringSync();
      args = _audioTrackInfoArgs(src);
    });

    test('the scan finds both audio runtimes', () {
      // Without this the assertion below passes vacuously — including if the
      // constructions move or are renamed.
      expect(args.length, 2,
          reason: 'recorder.dart builds one AudioTrackInfo per audio runtime '
              '(mic/loopback and mixed); found ${args.length}');
      for (final a in args) {
        expect(a, contains('codec:'));
        expect(a, contains('sampleRate:'));
      }
    });

    test('each one passes extraData', () {
      for (final a in args) {
        expect(a, contains('extraData:'),
            reason: 'a muxer has no other source for the codec-private header, '
                'and Opus pre-skip is not derivable from rate/channels:\n$a');
        expect(a, contains('encoder.extraData'),
            reason: 'it must be the ENCODER\'s header, not a synthesised one');
      }
    });
  });

  group('what a dropped OpusHead costs the file', () {
    test('an m4a keeps the encoder pre-skip when the track carries it',
        () async {
      // `rec.m4a` + Opus is a live first-party route, so this is the file a
      // user gets.
      final bytes = await _muxM4a(AudioTrackInfo(
        codec: AudioCodec.opus,
        sampleRate: 48000,
        channels: 2,
        extraData: CodecExtraData.audio(AudioCodec.opus, _opusHead()),
      ));
      final dops = _findBox(bytes, 'dOps');
      expect(dops, isNotNull, reason: 'an Opus sample entry must carry dOps');
      expect((dops![2] << 8) | dops[3], _preSkip,
          reason: 'PreSkip is big-endian in dOps');
    });

    test('without it the muxer synthesises PreSkip = 0', () async {
      // Not a hypothetical: this is exactly the header the recorder produced
      // before toTrackInfo forwarded encoder.extraData. Unlike AAC's ASC, the
      // fallback cannot derive this field — nothing in rate/channels holds it.
      final bytes = await _muxM4a(const AudioTrackInfo(
        codec: AudioCodec.opus,
        sampleRate: 48000,
        channels: 2,
      ));
      final dops = _findBox(bytes, 'dOps');
      expect(dops, isNotNull);
      expect((dops![2] << 8) | dops[3], 0,
          reason: 'the priming samples play as audio, ~6.5 ms late');
    });
  });
}
