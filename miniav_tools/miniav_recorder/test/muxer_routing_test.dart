/// Container-aware muxer/audio routing.
///
/// The recorder registers the first-party backends before it negotiates
/// anything, which makes the OS AAC encoder (priority 55) outbid FFmpeg (50).
/// `FfmpegMuxer` can only describe audio FFmpeg itself encoded, so for every
/// recording it has to write, audio must be pinned back to FFmpeg — and for
/// every recording the first-party ISO-BMFF writer can take, it must not be.
/// These tests pin that matrix down without touching a capture device.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:miniav_recorder/miniav_recorder.dart';
import 'package:miniav_tools/miniav_tools.dart';
import 'package:miniav_tools_codecs/miniav_tools_codecs.dart'
    show ContainerFramingBackend, registerFirstPartyBackends;
import 'package:miniav_tools_ffmpeg/miniav_tools_ffmpeg.dart'
    show FfmpegBackend, registerFfmpegBackend;
import 'package:test/test.dart';

/// An avcC configuration record (not Annex-B), so `Mp4Muxer` takes it as-is
/// instead of trying to parse parameter sets out of it.
final _avcC = Uint8List.fromList([
  0x01, 0x42, 0xC0, 0x1F, 0xFF, 0xE1, 0x00, 0x04, 0x67, 0x42, 0xC0, 0x1F,
  0x01, 0x00, 0x04, 0x68, 0xCE, 0x3C, 0x80,
]);

/// Annex-B extraData whose only NAL is not an SPS — `buildAvcC` cannot build a
/// configuration record from it, which is the failure whose *cause* used to be
/// thrown away by the negotiator.
final _annexBNoSps = Uint8List.fromList([0, 0, 0, 1, 0x09, 0x10]);

({Container? container, String path}) _sink(String path, [Container? c]) =>
    (container: c, path: path);

void main() {
  // -----------------------------------------------------------------------
  // firstPartyMuxerCanWrite — capability of the ISO-BMFF writer
  // -----------------------------------------------------------------------
  group('firstPartyMuxerCanWrite', () {
    test('mp4 + h264 + aac → true', () {
      expect(
        firstPartyMuxerCanWrite(
          container: Container.mp4,
          videoCodecs: [VideoCodec.h264],
          audioCodecs: [AudioCodec.aac],
        ),
        isTrue,
      );
    });

    test('mp4 + h264 + opus → true (Mp4Muxer writes dOps)', () {
      expect(
        firstPartyMuxerCanWrite(
          container: Container.mp4,
          videoCodecs: [VideoCodec.h264],
          audioCodecs: [AudioCodec.opus],
        ),
        isTrue,
      );
    });

    test('m4a + opus only → true', () {
      expect(
        firstPartyMuxerCanWrite(
          container: Container.m4a,
          videoCodecs: const [],
          audioCodecs: [AudioCodec.opus],
        ),
        isTrue,
      );
    });

    test('mp4 + mixed aac/opus → true', () {
      expect(
        firstPartyMuxerCanWrite(
          container: Container.mp4,
          videoCodecs: [VideoCodec.hevc],
          audioCodecs: [AudioCodec.aac, AudioCodec.opus],
        ),
        isTrue,
      );
    });

    test('mp4 + mp3 audio → false', () {
      expect(
        firstPartyMuxerCanWrite(
          container: Container.mp4,
          videoCodecs: [VideoCodec.h264],
          audioCodecs: [AudioCodec.mp3],
        ),
        isFalse,
      );
    });

    test('mp4 + vp9 video → false', () {
      expect(
        firstPartyMuxerCanWrite(
          container: Container.mp4,
          videoCodecs: [VideoCodec.vp9],
          audioCodecs: [AudioCodec.aac],
        ),
        isFalse,
      );
    });

    test('mkv is never first-party, whatever the codecs', () {
      expect(
        firstPartyMuxerCanWrite(
          container: Container.mkv,
          videoCodecs: [VideoCodec.h264],
          audioCodecs: [AudioCodec.aac],
        ),
        isFalse,
      );
    });
  });

  // -----------------------------------------------------------------------
  // firstPartyMuxerCanWrite — WAV and ADTS.
  //
  // Before these were routed here, an audio-only `.wav` could not be recorded
  // by ANY path: the gate answered false, so the sink fell to FfmpegMuxer,
  // which can only describe audio FFmpeg encoded — and FFmpeg has no PCM
  // encoder at all. A `.aac` sink was written as an M4A.
  // -----------------------------------------------------------------------
  group('firstPartyMuxerCanWrite — WavMuxer', () {
    for (final codec in [AudioCodec.pcmS16le, AudioCodec.pcmF32le]) {
      test('wav + ${codec.name}, audio only → true', () {
        expect(
          firstPartyMuxerCanWrite(
            container: Container.wav,
            videoCodecs: const [],
            audioCodecs: [codec],
          ),
          isTrue,
        );
      });
    }

    test('wav + aac → false (WavMuxer writes PCM only)', () {
      expect(
        firstPartyMuxerCanWrite(
          container: Container.wav,
          videoCodecs: const [],
          audioCodecs: [AudioCodec.aac],
        ),
        isFalse,
      );
    });

    test('wav + a video track → false (no video in RIFF/WAVE)', () {
      expect(
        firstPartyMuxerCanWrite(
          container: Container.wav,
          videoCodecs: [VideoCodec.h264],
          audioCodecs: [AudioCodec.pcmS16le],
        ),
        isFalse,
      );
    });

    test('wav with no audio at all → false', () {
      expect(
        firstPartyMuxerCanWrite(
          container: Container.wav,
          videoCodecs: const [],
          audioCodecs: const [],
        ),
        isFalse,
      );
    });

    test('wav + two PCM tracks → false', () {
      // WavMuxer.writePacket never looks at EncodedPacket.trackIndex, so a
      // second track would be INTERLEAVED into the first one's stream rather
      // than refused. Better to fall through to FFmpeg and fail loudly.
      expect(
        firstPartyMuxerCanWrite(
          container: Container.wav,
          videoCodecs: const [],
          audioCodecs: [AudioCodec.pcmS16le, AudioCodec.pcmS16le],
        ),
        isFalse,
      );
    });

    test('wav + a SET of one codec but two tracks → false', () {
      // The trap the audioTracks argument exists for: callers legitimately
      // pass a Set, where two same-codec tracks collapse to one element and
      // the count alone would say "single track".
      expect(
        firstPartyMuxerCanWrite(
          container: Container.wav,
          videoCodecs: const {},
          audioCodecs: const {AudioCodec.pcmS16le},
          audioTracks: 2,
        ),
        isFalse,
      );
      expect(
        firstPartyMuxerCanWrite(
          container: Container.wav,
          videoCodecs: const {},
          audioCodecs: const {AudioCodec.pcmS16le},
          audioTracks: 1,
        ),
        isTrue,
      );
    });
  });

  group('firstPartyMuxerCanWrite — AdtsMuxer', () {
    test('adts + aac, audio only → true', () {
      expect(
        firstPartyMuxerCanWrite(
          container: Container.adts,
          videoCodecs: const [],
          audioCodecs: [AudioCodec.aac],
        ),
        isTrue,
      );
    });

    test('adts + opus → false (ADTS frames raw AAC only)', () {
      expect(
        firstPartyMuxerCanWrite(
          container: Container.adts,
          videoCodecs: const [],
          audioCodecs: [AudioCodec.opus],
        ),
        isFalse,
      );
    });

    test('adts + a video track → false', () {
      expect(
        firstPartyMuxerCanWrite(
          container: Container.adts,
          videoCodecs: [VideoCodec.h264],
          audioCodecs: [AudioCodec.aac],
        ),
        isFalse,
      );
    });

    test('adts + two AAC tracks → false', () {
      expect(
        firstPartyMuxerCanWrite(
          container: Container.adts,
          videoCodecs: const [],
          audioCodecs: [AudioCodec.aac, AudioCodec.aac],
        ),
        isFalse,
      );
    });
  });

  group('firstPartyMuxerCanWrite — containers deliberately left out', () {
    // OggMuxer still assembles the whole file in memory and exposes it through
    // getBytes(): it has no streaming FileMuxerOutput mode, so routing a .ogg
    // sink here would buffer an open-ended recording in RAM. Unchanged.
    test('ogg + opus → false', () {
      expect(
        firstPartyMuxerCanWrite(
          container: Container.ogg,
          videoCodecs: const [],
          audioCodecs: [AudioCodec.opus],
        ),
        isFalse,
      );
    });

    test('mp3 → false (demux-only; there is no first-party MP3 writer)', () {
      expect(
        firstPartyMuxerCanWrite(
          container: Container.mp3,
          videoCodecs: const [],
          audioCodecs: [AudioCodec.mp3],
        ),
        isFalse,
      );
    });
  });

  // -----------------------------------------------------------------------
  // containerForTrackMix — default shift for video+audio
  // -----------------------------------------------------------------------
  group('containerForTrackMix default shift', () {
    test('video + audio, h264/aac → mp4 (was mkv)', () {
      expect(
        containerForTrackMix(
          hasVideo: true,
          hasAudio: true,
          videoCodecs: {VideoCodec.h264},
          audioCodecs: {AudioCodec.aac},
        ),
        Container.mp4,
      );
    });

    test('video + audio, hevc/opus → mp4', () {
      expect(
        containerForTrackMix(
          hasVideo: true,
          hasAudio: true,
          videoCodecs: {VideoCodec.hevc},
          audioCodecs: {AudioCodec.opus},
        ),
        Container.mp4,
      );
    });

    test('video + audio, vp9/opus → mkv (not first-party writable)', () {
      expect(
        containerForTrackMix(
          hasVideo: true,
          hasAudio: true,
          videoCodecs: {VideoCodec.vp9},
          audioCodecs: {AudioCodec.opus},
        ),
        Container.mkv,
      );
    });

    test('video + audio, h264/mp3 → mkv', () {
      expect(
        containerForTrackMix(
          hasVideo: true,
          hasAudio: true,
          videoCodecs: {VideoCodec.h264},
          audioCodecs: {AudioCodec.mp3},
        ),
        Container.mkv,
      );
    });

    test('video + audio with codecs unstated → mkv (unknown is not a fit)', () {
      expect(
        containerForTrackMix(hasVideo: true, hasAudio: true),
        Container.mkv,
      );
    });

    test('video only is unchanged → mp4', () {
      expect(
        containerForTrackMix(
          hasVideo: true,
          hasAudio: false,
          videoCodecs: {VideoCodec.h264},
        ),
        Container.mp4,
      );
    });

    test('audio-only rules are unchanged', () {
      expect(
        containerForTrackMix(
          hasVideo: false,
          hasAudio: true,
          audioCodecs: {AudioCodec.aac},
        ),
        Container.m4a,
      );
      expect(
        containerForTrackMix(
          hasVideo: false,
          hasAudio: true,
          audioCodecs: {AudioCodec.opus},
        ),
        Container.ogg,
      );
      expect(
        containerForTrackMix(
          hasVideo: false,
          hasAudio: true,
          audioCodecs: {AudioCodec.aac, AudioCodec.opus},
        ),
        Container.mkv,
      );
    });
  });

  // -----------------------------------------------------------------------
  // resolveSinkContainer — precedence, from configs alone
  // -----------------------------------------------------------------------
  group('resolveSinkContainer', () {
    test('explicit override beats the extension', () {
      expect(
        resolveSinkContainer(
          explicit: Container.mkv,
          path: 'out.mp4',
          videoCodecs: {VideoCodec.h264},
          audioCodecs: {AudioCodec.aac},
        ),
        Container.mkv,
      );
    });

    test('extension beats the track-mix heuristic', () {
      expect(
        resolveSinkContainer(
          path: 'out.mkv',
          videoCodecs: {VideoCodec.h264},
          audioCodecs: {AudioCodec.aac},
        ),
        Container.mkv,
      );
    });

    test('unknown extension falls back to the track mix', () {
      expect(
        resolveSinkContainer(
          path: 'out.avi',
          videoCodecs: {VideoCodec.h264},
          audioCodecs: {AudioCodec.aac},
        ),
        Container.mp4,
      );
    });
  });

  // -----------------------------------------------------------------------
  // recordingRequiresFfmpegMuxer — the audio-negotiation gate (R1b)
  // -----------------------------------------------------------------------
  group('recordingRequiresFfmpegMuxer', () {
    test('mp4 sink + h264 + aac → false (audio negotiates freely)', () {
      expect(
        recordingRequiresFfmpegMuxer(
          fileSinks: [_sink('rec.mp4')],
          videoCodecs: {VideoCodec.h264},
          audioCodecs: {AudioCodec.aac},
        ),
        isFalse,
      );
    });

    test('mkv sink + h264 + aac → true (FFmpeg muxer, so FFmpeg audio)', () {
      expect(
        recordingRequiresFfmpegMuxer(
          fileSinks: [_sink('rec.mkv')],
          videoCodecs: {VideoCodec.h264},
          audioCodecs: {AudioCodec.aac},
        ),
        isTrue,
      );
    });

    test('explicit mkv override on an .mp4 path → true', () {
      expect(
        recordingRequiresFfmpegMuxer(
          fileSinks: [_sink('rec.mp4', Container.mkv)],
          videoCodecs: {VideoCodec.h264},
          audioCodecs: {AudioCodec.aac},
        ),
        isTrue,
      );
    });

    test('m4a sink + aac only → false', () {
      expect(
        recordingRequiresFfmpegMuxer(
          fileSinks: [_sink('mic.m4a')],
          videoCodecs: const {},
          audioCodecs: {AudioCodec.aac},
        ),
        isFalse,
      );
    });

    test('ogg sink + opus → true (first-party MP4 writer only takes mp4/m4a)',
        () {
      expect(
        recordingRequiresFfmpegMuxer(
          fileSinks: [_sink('mic.ogg')],
          videoCodecs: const {},
          audioCodecs: {AudioCodec.opus},
        ),
        isTrue,
      );
    });

    test('webm and ts sinks → true', () {
      for (final path in ['rec.webm', 'rec.ts']) {
        expect(
          recordingRequiresFfmpegMuxer(
            fileSinks: [_sink(path)],
            videoCodecs: {VideoCodec.h264},
            audioCodecs: {AudioCodec.aac},
          ),
          isTrue,
          reason: path,
        );
      }
    });

    test('no audio → false even for mkv (no codecpar to fill)', () {
      expect(
        recordingRequiresFfmpegMuxer(
          fileSinks: [_sink('rec.mkv')],
          videoCodecs: {VideoCodec.h264},
          audioCodecs: const {},
        ),
        isFalse,
      );
    });

    test('no file sinks (stream-only) → false', () {
      expect(
        recordingRequiresFfmpegMuxer(
          fileSinks: const [],
          videoCodecs: {VideoCodec.h264},
          audioCodecs: {AudioCodec.aac},
        ),
        isFalse,
      );
    });

    test('one mp4 + one mkv sink → true (the strictest sink decides)', () {
      expect(
        recordingRequiresFfmpegMuxer(
          fileSinks: [_sink('a.mp4'), _sink('b.mkv')],
          videoCodecs: {VideoCodec.h264},
          audioCodecs: {AudioCodec.aac},
        ),
        isTrue,
      );
    });

    test('two mp4 sinks → false', () {
      expect(
        recordingRequiresFfmpegMuxer(
          fileSinks: [_sink('a.mp4'), _sink('b.mp4')],
          videoCodecs: {VideoCodec.h264},
          audioCodecs: {AudioCodec.aac},
        ),
        isFalse,
      );
    });

    test('wav sink + pcm → false (was true: no path could write it at all)',
        () {
      for (final codec in [AudioCodec.pcmS16le, AudioCodec.pcmF32le]) {
        expect(
          recordingRequiresFfmpegMuxer(
            fileSinks: [_sink('mic.wav')],
            videoCodecs: const {},
            audioCodecs: {codec},
            audioTracks: 1,
          ),
          isFalse,
          reason: codec.name,
        );
      }
    });

    test('wav sink + TWO pcm tracks → true (WavMuxer holds one)', () {
      expect(
        recordingRequiresFfmpegMuxer(
          fileSinks: [_sink('mic.wav')],
          videoCodecs: const {},
          audioCodecs: {AudioCodec.pcmS16le},
          audioTracks: 2,
        ),
        isTrue,
      );
    });

    test('mkv sink + pcm → still true (only FFmpeg writes MKV)', () {
      expect(
        recordingRequiresFfmpegMuxer(
          fileSinks: [_sink('mic.mkv')],
          videoCodecs: const {},
          audioCodecs: {AudioCodec.pcmS16le},
          audioTracks: 1,
        ),
        isTrue,
      );
    });

    test('.aac sink + aac → false (ADTS, not an M4A in an .aac file)', () {
      expect(
        recordingRequiresFfmpegMuxer(
          fileSinks: [_sink('mic.aac')],
          videoCodecs: const {},
          audioCodecs: {AudioCodec.aac},
          audioTracks: 1,
        ),
        isFalse,
      );
    });

    test('.wav sink carrying video → true (RIFF/WAVE has no video track)', () {
      expect(
        recordingRequiresFfmpegMuxer(
          fileSinks: [_sink('rec.wav')],
          videoCodecs: {VideoCodec.h264},
          audioCodecs: {AudioCodec.pcmS16le},
          audioTracks: 1,
        ),
        isTrue,
      );
    });

    test('no-extension path + h264/aac resolves to mp4 → false', () {
      // The track-mix default shift is what makes this first-party.
      expect(
        recordingRequiresFfmpegMuxer(
          fileSinks: [_sink('recording')],
          videoCodecs: {VideoCodec.h264},
          audioCodecs: {AudioCodec.aac},
        ),
        isFalse,
      );
    });
  });

  // -----------------------------------------------------------------------
  // Backend ranking — the premise of R1b, checked against the real registry
  // -----------------------------------------------------------------------
  group('registered backends', () {
    setUpAll(() {
      registerFfmpegBackend();
      registerFirstPartyBackends();
    });

    test('a first-party backend outranks FFmpeg for AAC encode', () {
      final ranked = MiniAVToolsPlatform.instance
          .orderedBackends(BackendPreference.auto)
          .where((b) => b.supportsAudioEncode(AudioCodec.aac))
          .toList();
      expect(ranked, isNotEmpty);
      expect(
        ranked.map((b) => b.name),
        contains(FfmpegBackend.backendName),
        reason: 'FFmpeg must remain available as the fallback',
      );
      if (Platform.isWindows) {
        // This is exactly why the routing above exists: left alone, the MF AAC
        // encoder wins and hands FfmpegMuxer an audio track it cannot describe.
        expect(ranked.first.name, isNot(FfmpegBackend.backendName));
      }
    });

    test('the container framing backend muxes mp4 and m4a', () {
      final b = MiniAVToolsPlatform.instance.backends.firstWhere(
        (b) => b.name == ContainerFramingBackend.backendName,
      );
      expect(b.supportsMux(Container.mp4), isTrue);
      expect(b.supportsMux(Container.m4a), isTrue);
      expect(b.supportsMux(Container.mkv), isFalse);
    });
  });

  // -----------------------------------------------------------------------
  // The route itself: an MP4 file sink's config, muxed first-party.
  // -----------------------------------------------------------------------
  group('first-party MP4 file route', () {
    late Directory tmp;

    setUpAll(() {
      registerFfmpegBackend();
      registerFirstPartyBackends();
    });
    setUp(() => tmp = Directory.systemTemp.createTempSync('rec_route_'));
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('h264 + aac writes a streamed MP4 with no FFmpeg encoder', () async {
      final path = '${tmp.path}${Platform.pathSeparator}route.mp4';
      final muxer = await MiniAVTools.createMuxer(
        MuxerConfig(
          container: Container.mp4,
          output: FileMuxerOutput(path),
          tracks: [
            VideoTrackInfo(
              codec: VideoCodec.h264,
              width: 320,
              height: 240,
              frameRateNumerator: 30,
              frameRateDenominator: 1,
              extraData: CodecExtraData.video(VideoCodec.h264, _avcC),
            ),
            // No encoder bridge anywhere — the point of the first-party path.
            const AudioTrackInfo(
              codec: AudioCodec.aac,
              sampleRate: 48000,
              channels: 2,
            ),
          ],
        ),
        preference: BackendPreference.pinned(
          ContainerFramingBackend.backendName,
        ),
      );
      expect(muxer.backendName, ContainerFramingBackend.backendName);

      await muxer.writeHeader();
      // The file exists while packets are still arriving — i.e. it streams
      // instead of assembling the whole recording in RAM.
      expect(File(path).existsSync(), isTrue);
      for (var i = 0; i < 4; i++) {
        await muxer.writePacket(
          EncodedPacket(
            trackIndex: 0,
            data: Uint8List.fromList([0, 0, 0, 2, 0x65, 0x88]),
            ptsUs: i * 33333,
            dtsUs: i * 33333,
            durationUs: 33333,
            isKeyframe: i == 0,
          ),
        );
        await muxer.writePacket(
          EncodedPacket(
            trackIndex: 1,
            data: Uint8List.fromList([0x21, 0x00, 0x03]),
            ptsUs: i * 21333,
            dtsUs: i * 21333,
            durationUs: 21333,
            isKeyframe: true,
          ),
        );
      }
      await muxer.finish();
      await muxer.close();

      final bytes = File(path).readAsBytesSync();
      expect(bytes.length, greaterThan(64));
      // 'ftyp' at offset 4.
      expect(String.fromCharCodes(bytes.sublist(4, 8)), 'ftyp');
      expect(String.fromCharCodes(bytes), contains('moov'));
    });

    test('a refusal records its cause instead of losing it', () async {
      final path = '${tmp.path}${Platform.pathSeparator}nosps.mp4';
      await expectLater(
        () => MiniAVTools.createMuxer(
          MuxerConfig(
            container: Container.mp4,
            output: FileMuxerOutput(path),
            tracks: [
              VideoTrackInfo(
                codec: VideoCodec.h264,
                width: 320,
                height: 240,
                frameRateNumerator: 30,
                frameRateDenominator: 1,
                extraData: CodecExtraData.video(
                  VideoCodec.h264,
                  _annexBNoSps,
                ),
              ),
            ],
          ),
          preference: BackendPreference.pinned(
            ContainerFramingBackend.backendName,
          ),
        ),
        throwsA(isA<NoBackendForCodecException>()),
      );
      // The generic throw above is why this exists: the real reason is here.
      final cause = ContainerFramingBackend.lastMuxerInitFailure;
      expect(cause, isNotNull);
      expect(cause.toString(), contains('SPS'));
    });

    test('pcm writes a streamed WAV with no encoder anywhere', () async {
      final path = '${tmp.path}${Platform.pathSeparator}route.wav';
      final muxer = await MiniAVTools.createMuxer(
        MuxerConfig(
          container: Container.wav,
          output: FileMuxerOutput(path),
          tracks: const [
            AudioTrackInfo(
              codec: AudioCodec.pcmS16le,
              sampleRate: 48000,
              channels: 2,
            ),
          ],
        ),
        preference: BackendPreference.pinned(
          ContainerFramingBackend.backendName,
        ),
      );
      expect(muxer.backendName, ContainerFramingBackend.backendName);

      await muxer.writeHeader();
      // Streaming, not buffered: the header is on disk before any packet.
      expect(File(path).lengthSync(), 44);
      for (var i = 0; i < 4; i++) {
        await muxer.writePacket(
          EncodedPacket(
            trackIndex: 0,
            data: Uint8List.fromList([0x11, 0x22, 0x33, 0x44]),
            ptsUs: i * 1000,
            dtsUs: i * 1000,
            durationUs: 1000,
            isKeyframe: true,
          ),
        );
      }
      await muxer.finish();
      await muxer.close();

      final bytes = File(path).readAsBytesSync();
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      // The two lengths are patched at finish(); an unpatched file reads as an
      // empty (but well-formed) WAVE, which is the failure this catches.
      final data = ByteData.sublistView(bytes);
      expect(data.getUint32(40, Endian.little), 16, reason: 'data chunk size');
      expect(data.getUint32(4, Endian.little), 52, reason: 'RIFF size');
      expect(bytes.length, 44 + 16);
    });

    test('aac writes a streamed ADTS stream with no encoder anywhere',
        () async {
      final path = '${tmp.path}${Platform.pathSeparator}route.aac';
      final muxer = await MiniAVTools.createMuxer(
        MuxerConfig(
          container: Container.adts,
          output: FileMuxerOutput(path),
          tracks: const [
            AudioTrackInfo(
              codec: AudioCodec.aac,
              sampleRate: 48000,
              channels: 2,
            ),
          ],
        ),
        preference: BackendPreference.pinned(
          ContainerFramingBackend.backendName,
        ),
      );
      expect(muxer.backendName, ContainerFramingBackend.backendName);

      await muxer.writeHeader();
      expect(File(path).existsSync(), isTrue);
      for (var i = 0; i < 4; i++) {
        await muxer.writePacket(
          EncodedPacket(
            trackIndex: 0,
            data: Uint8List.fromList([0x21, 0x00, 0x03]),
            ptsUs: i * 21333,
            dtsUs: i * 21333,
            durationUs: 21333,
            isKeyframe: true,
          ),
        );
      }
      await muxer.finish();
      await muxer.close();

      final bytes = File(path).readAsBytesSync();
      expect(bytes.length, 4 * (7 + 3), reason: '7-byte header per frame');
      expect(bytes[0], 0xFF);
      expect(bytes[1] & 0xF6, 0xF0, reason: 'syncword + MPEG-4 + layer 0');
    });

    test('lastMuxerInitFailure is cleared by a successful open', () async {
      final path = '${tmp.path}${Platform.pathSeparator}ok.mp4';
      final muxer = await MiniAVTools.createMuxer(
        MuxerConfig(
          container: Container.mp4,
          output: FileMuxerOutput(path),
          tracks: [
            VideoTrackInfo(
              codec: VideoCodec.h264,
              width: 320,
              height: 240,
              frameRateNumerator: 30,
              frameRateDenominator: 1,
              extraData: CodecExtraData.video(VideoCodec.h264, _avcC),
            ),
          ],
        ),
        preference: BackendPreference.pinned(
          ContainerFramingBackend.backendName,
        ),
      );
      expect(ContainerFramingBackend.lastMuxerInitFailure, isNull);
      await muxer.close();
    });
  });

  // -----------------------------------------------------------------------
  // The unsatisfiable-coupling throw, end to end through Recorder.start().
  // Reached during _prepare's routing step, before any device is opened.
  // -----------------------------------------------------------------------
  group('Recorder._prepare coupling check', () {
    test('non-FFmpeg audio pin + mkv sink throws a CodecInitException', () {
      final rec =
          (RecorderBuilder()
                ..backendPreference = BackendPreference.pinned('mf_aac')
                ..addMic(deviceId: 'fake-mic', codec: AudioCodec.aac)
                ..addFileOutput('coupling.mkv'))
              .build();
      expect(
        rec.start(),
        throwsA(
          isA<CodecInitException>().having(
            (e) => e.message,
            'message',
            allOf(contains('FfmpegMuxer'), contains('MP4/M4A')),
          ),
        ),
      );
    });

    test('excluding FFmpeg with an mkv sink throws too', () {
      final rec =
          (RecorderBuilder()
                ..backendPreference = BackendPreference.excluded({
                  FfmpegBackend.backendName,
                })
                ..addMic(deviceId: 'fake-mic', codec: AudioCodec.aac)
                ..addFileOutput('coupling.mkv'))
              .build();
      expect(rec.start(), throwsA(isA<CodecInitException>()));
    });

    // The negative case (same pin, MP4 sink → no coupling error) is covered by
    // `recordingRequiresFfmpegMuxer` above. It cannot be checked through
    // start(): the check is deliberately upstream of encoder negotiation, so
    // getting past it means opening a real capture device.
  });

  // -----------------------------------------------------------------------
  // The FFmpeg audio pin is a CONTAINER answer; whether FFmpeg can encode the
  // configured codec is a separate, capability question. Pinning without
  // asking it made PCM unreachable behind a NoBackendForCodecException that
  // named a codec PcmBackend does support.
  // -----------------------------------------------------------------------
  //
  // NOTE: this used to be checked with a `.wav` sink, which is no longer a
  // container only FFmpeg can write — WavMuxer takes the PCM packets directly,
  // so a PCM `.wav` recording never reaches this check at all. That was the
  // bug, not the test: FFmpeg has no PCM encoder, so the old route could only
  // ever end in this throw. MKV still exercises it, and still must.
  group('Recorder._prepare FFmpeg audio capability check', () {
    for (final codec in [AudioCodec.pcmS16le, AudioCodec.pcmF32le]) {
      test('${codec.name} + an mkv sink names the codec, not "no backend"', () {
        final rec =
            (RecorderBuilder()
                  ..addMic(deviceId: 'fake-mic', codec: codec)
                  ..addFileOutput('capability.mkv'))
                .build();
        expect(
          rec.start(),
          throwsA(
            allOf(
              isA<CodecInitException>().having(
                (e) => e.message,
                'message',
                allOf(
                  contains(codec.name),
                  contains('FFmpeg has no encoder'),
                ),
              ),
              isNot(isA<NoBackendForCodecException>()),
            ),
          ),
        );
      });
    }

    test('mp3 audio + an mkv sink is rejected the same way', () {
      final rec =
          (RecorderBuilder()
                ..addMic(deviceId: 'fake-mic', codec: AudioCodec.mp3)
                ..addFileOutput('capability.mkv'))
              .build();
      expect(
        rec.start(),
        throwsA(
          isA<CodecInitException>().having(
            (e) => e.message,
            'message',
            contains('mp3'),
          ),
        ),
      );
    });

    // No positive case here: an audio codec FFmpeg CAN encode gets past this
    // check and straight into ensureFFmpegLoaded() + a real capture device.
    // The two `Recorder._prepare coupling check` tests above already prove the
    // check is not a blanket throw — they reach the preference check, which
    // sits below this one.
  });
}
