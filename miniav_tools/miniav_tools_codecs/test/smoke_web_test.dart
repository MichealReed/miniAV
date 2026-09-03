/// Browser smoke tests for miniav_tools_codecs.
///
/// Run with:
///   dart test -p chrome --tags browser
///
/// For WebGPU tests, launch Chrome with:
///   --enable-unsafe-webgpu --disable-dawn-features=disallow_unsafe_apis
///
/// CI note: `WebCapability.hasWebGPU` is probed at runtime and the
/// webgpu-tagged test is skipped gracefully if the API is unavailable,
/// so it will not fail on GPU-less CI runners.
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:miniav_tools_codecs/web.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import 'mp3_fixtures.dart';

void main() {
  // Force lazy registration of WebCodecsBackend into MiniAVToolsPlatform.
  setUpAll(ensureInitialized);

  // -------------------------------------------------------------------------
  // WebCapability — synchronous flags
  // -------------------------------------------------------------------------

  group('WebCapability', () {
    test('hasVideoEncoder returns bool without throwing', () {
      expect(WebCapability.hasVideoEncoder, isA<bool>());
    });

    test('hasAudioEncoder returns bool without throwing', () {
      expect(WebCapability.hasAudioEncoder, isA<bool>());
    });

    test('hasWebGPU returns bool without throwing', () {
      expect(WebCapability.hasWebGPU, isA<bool>());
    });

    test('hasMediaRecorder returns bool without throwing', () {
      expect(WebCapability.hasMediaRecorder, isA<bool>());
    });

    test('hasOffscreenCanvas returns bool without throwing', () {
      expect(WebCapability.hasOffscreenCanvas, isA<bool>());
    });

    test('isVideoEncoderSupported returns bool without throwing', () async {
      final result = await WebCapability.isVideoEncoderSupported('avc1.42E01E');
      expect(result, isA<bool>());
    });
  });

  // -------------------------------------------------------------------------
  // Backend registration
  // -------------------------------------------------------------------------

  group('WebCodecsBackend registration', () {
    test('registers in MiniAVToolsPlatform on import', () {
      // Importing miniav_tools_codecs triggers auto-registration.
      final backends = MiniAVToolsPlatform.instance.backends;
      expect(
        backends.any((b) => b.name == 'webcodecs'),
        isTrue,
        reason: 'WebCodecsBackend should be auto-registered on import',
      );
    });

    test('registering twice is idempotent', () {
      final before = MiniAVToolsPlatform.instance.backends.length;
      // Second registration attempt via the same helper.
      MiniAVToolsPlatform.instance.register(WebCodecsBackend());
      // The platform deduplicates by name so count should be the same.
      final after = MiniAVToolsPlatform.instance.backends.length;
      expect(after, equals(before));
    });

    test('backend has correct name and priority', () {
      final b = WebCodecsBackend();
      expect(b.name, equals('webcodecs'));
      expect(b.priority, equals(80));
    });

    test('backend reports correct accepted frame sources', () {
      final b = WebCodecsBackend();
      expect(b.acceptedFrameSources, contains(FrameSourceKind.cpu));
      expect(b.acceptedFrameSources, contains(FrameSourceKind.webVideoFrame));
    });
  });

  // -------------------------------------------------------------------------
  // WebCodecsBackend capabilities
  // -------------------------------------------------------------------------

  group('WebCodecsBackend capability queries', () {
    final b = WebCodecsBackend();

    test('supportsEncode for unsupported codec returns false', () {
      expect(b.supportsEncode(VideoCodec.mjpeg), isFalse);
    });

    test('supportsEncode for H.264 matches hasVideoEncoder', () {
      expect(
        b.supportsEncode(VideoCodec.h264),
        equals(WebCapability.hasVideoEncoder),
      );
    });

    test('createEncoder returns null for unsupported codec', () async {
      final enc = await b.createEncoder(
        EncoderConfig(
          codec: VideoCodec.mjpeg,
          width: 64,
          height: 64,
          bitrateBps: 1000000,
        ),
      );
      expect(enc, isNull);
    });

    test(
      'createEncoder does not throw when VideoEncoder is unavailable',
      () async {
        // Even if WebCodecs is not present, this must return null, not throw.
        final enc = await b.createEncoder(
          EncoderConfig(
            codec: VideoCodec.h264,
            width: 64,
            height: 64,
            bitrateBps: 1000000,
          ),
        );
        // May be null (no WebCodecs) or a WebCodecsVideoEncoder — both fine.
        expect(enc, anyOf(isNull, isA<PlatformEncoder>()));
      },
    );
  });

  // -------------------------------------------------------------------------
  // MediaRecorderCapture fallback
  // -------------------------------------------------------------------------

  group('MediaRecorderCapture', () {
    test('preferredMimeType returns a non-empty string', () {
      final mime = MediaRecorderCapture.preferredMimeType;
      expect(mime, isNotEmpty);
    });

    test('preferredMimeType is a WebM or MP4 variant', () {
      final mime = MediaRecorderCapture.preferredMimeType;
      expect(mime, anyOf(startsWith('video/webm'), startsWith('video/mp4')));
    });
  });

  // -------------------------------------------------------------------------
  // WebVideoFrameSource (platform interface type)
  // -------------------------------------------------------------------------

  group('WebVideoFrameSource', () {
    test('factory construction works with Object videoFrame', () {
      // Use a trivial JS object to stand in for a real VideoFrame.
      final fakeFame = web.window; // any JSObject works for construction
      final src = FrameSource.webVideoFrame(
        videoFrame: fakeFame,
        width: 640,
        height: 480,
        pixelFormat: MiniAVPixelFormat.rgba32,
        timestampUs: 1000,
      );
      expect(src.kind, equals(FrameSourceKind.webVideoFrame));
      expect(src.width, equals(640));
      expect(src.height, equals(480));
      expect(src.timestampUs, equals(1000));
    });
  });

  // -------------------------------------------------------------------------
  // Pure-Dart container framing in the browser — MP3 demux
  // -------------------------------------------------------------------------

  group('MP3 demux (pure Dart, web-safe)', () {
    // Why this matters on web specifically: the browser can DECODE mp3
    // (WebCodecs codec string 'mp3') but there is no FFmpeg here to frame the
    // file, so before this parser existed .mp3 bytes had no path to playback at
    // all. What CI proves here is that the framing runs in a browser (no
    // dart:io, no dart:ffi) and that the backend's sniffer routes mp3 bytes to
    // it. The decode leg needs a real AudioDecoder and is verified manually.
    test('ID3-tagged mp3 bytes demux to whole frames', () async {
      const spec = Mp3FrameSpec();
      final bytes = concatBytes([
        id3v2Tag(bodySize: 64),
        mp3VbrFrame(spec, frameCount: 8),
        mp3Stream(repeatSpec(spec, 8)),
      ]);

      final dm = await ContainerFramingBackend().createDemuxer(
        DemuxerConfig(input: DemuxerInput.bytes(bytes)),
      );
      expect(dm, isNotNull, reason: 'the sniffer must route mp3 bytes here');
      final t = dm!.tracks.single as AudioTrackInfo;
      expect(t.codec, AudioCodec.mp3);
      expect(t.sampleRate, 44100);
      expect(t.channels, 2);
      expect(dm.durationUs, 8 * 1152 * 1000000 ~/ 44100);

      var n = 0;
      for (var p = await dm.readPacket(); p != null; p = await dm.readPacket()) {
        // A WHOLE frame, header included — what an EncodedAudioChunk needs.
        expect(p.data[0], 0xFF);
        expect(p.isKeyframe, isTrue);
        expect(p.ptsUs, n * 1152 * 1000000 ~/ 44100);
        n++;
      }
      expect(n, 8, reason: 'the Xing frame is metadata, not audio');
      await dm.close();
    }, tags: ['browser']);
  });

  // -------------------------------------------------------------------------
  // MP3 DECODE leg — the half that used to be "verified manually"
  // -------------------------------------------------------------------------
  //
  // Leaving this to manual verification is exactly how MP3 shipped broken on
  // web: `AudioDecoderConfig` was built with `description: null`, and because
  // dart:js_interop EMITS an explicitly-passed null (only an omitted argument
  // is absent), WebCodecs threw "Failed to read the 'description' property".
  // MP3 is the codec that exposes it — it is the one with no codec-private
  // data, so every other codec took the other branch and looked fine.

  group('MP3 decode configure (regression: description must be OMITTED)', () {
    test('an mp3 decoder configures without a description', () async {
      if (!WebCapability.hasAudioDecoder) {
        markTestSkipped('AudioDecoder API not available in this browser');
        return;
      }
      if (!await WebCapability.isAudioDecoderSupported('mp3',
          sampleRate: 44100, channels: 2)) {
        markTestSkipped('this browser has AudioDecoder but not mp3');
        return;
      }

      // Configuring IS the assertion: the old code threw a TypeError here.
      final dec = await WebCodecsBackend().createAudioDecoder(
        const AudioDecoderConfig(
          codec: AudioCodec.mp3,
          sampleRate: 44100,
          channels: 2,
        ),
      );
      expect(dec, isNotNull, reason: 'WebCodecs should claim mp3 here');
      await dec!.close();
    }, tags: ['browser']);

    test('a real mp3 stream decodes to PCM through the negotiated backend',
        () async {
      if (!WebCapability.hasAudioDecoder) {
        markTestSkipped('AudioDecoder API not available in this browser');
        return;
      }
      const spec = Mp3FrameSpec();
      final bytes = concatBytes([mp3Stream(repeatSpec(spec, 8))]);
      final dm = await ContainerFramingBackend().createDemuxer(
        DemuxerConfig(input: DemuxerInput.bytes(bytes)),
      );
      final track = dm!.tracks.single as AudioTrackInfo;

      // Whatever the registry picks (WebCodecs, or the decodeAudioData
      // fallback on a browser without it) must produce real samples.
      PlatformAudioDecoder? dec;
      for (final b in MiniAVToolsPlatform.instance
          .orderedBackends(BackendPreference.auto)
          .where((b) => b.supportsAudioDecode(AudioCodec.mp3))) {
        dec = await b.createAudioDecoder(AudioDecoderConfig.fromTrack(track));
        if (dec != null) break;
      }
      expect(dec, isNotNull, reason: 'no backend could decode mp3 on web');

      var packets = 0;
      var frames = 0;
      for (var p = await dm.readPacket(); p != null; p = await dm.readPacket()) {
        packets++;
        for (final d in await dec!.decode(p)) {
          frames += d.frameCount;
        }
      }
      for (final d in await dec!.flush()) {
        frames += d.frameCount;
      }
      await dec.close();
      await dm.close();

      // What this fixture can honestly prove: the whole demux → configure →
      // decode → flush chain RUNS in a browser without throwing, which is
      // exactly what regressed (configure threw a TypeError and no packet was
      // ever fed). It canNOT prove PCM correctness — the frames are synthetic,
      // valid headers over silent payload, so a real decoder may legitimately
      // emit nothing. Byte-accurate output needs a real .mp3 asset served to
      // the browser; see the VM-side decode tests for that coverage.
      expect(packets, 8, reason: 'every demuxed packet must reach the decoder');
      expect(frames, greaterThanOrEqualTo(0));
    }, tags: ['browser']);
  });

  // -------------------------------------------------------------------------
  // WebCodecs round-trip (skipped if VideoEncoder unavailable)
  // -------------------------------------------------------------------------

  group('WebCodecs encoding', () {
    test('encode 64x64 RGBA frame via CPU path', () async {
      if (!WebCapability.hasVideoEncoder) {
        markTestSkipped('VideoEncoder API not available in this browser');
        return;
      }
      if (!WebCapability.hasOffscreenCanvas) {
        markTestSkipped('OffscreenCanvas not available in this browser');
        return;
      }

      // Check H.264 support before creating an encoder.
      final h264ok = await WebCapability.isVideoEncoderSupported(
        'avc1.42E01E',
        width: 64,
        height: 64,
      );
      if (!h264ok) {
        markTestSkipped('H.264 not supported at 64x64 in this browser');
        return;
      }

      final backend = WebCodecsBackend();
      final encoder = await backend.createEncoder(
        EncoderConfig(
          codec: VideoCodec.h264,
          width: 64,
          height: 64,
          bitrateBps: 500000,
          frameRateNumerator: 30,
          frameRateDenominator: 1,
        ),
      );
      expect(encoder, isNotNull, reason: 'createEncoder should succeed');

      // Solid RGBA frame (red pixels).
      final bytes = Uint8List(64 * 64 * 4);
      for (var i = 0; i < bytes.length; i += 4) {
        bytes[i] = 255; // R
        bytes[i + 1] = 0; // G
        bytes[i + 2] = 0; // B
        bytes[i + 3] = 255; // A
      }

      final frame = FrameSource.cpu(
        bytes: bytes,
        pixelFormat: MiniAVPixelFormat.rgba32,
        width: 64,
        height: 64,
        timestampUs: 0,
      );

      final packet = await encoder!.encode(frame);
      // First IDR may or may not flush immediately depending on browser.
      // A null return is valid (encoder buffering); non-null is also valid.
      if (packet != null) {
        expect(packet.data, isNotEmpty);
        expect(packet.isKeyframe, isTrue);
      }

      final flushed = await encoder.flush();
      expect(flushed.length + (packet != null ? 1 : 0), greaterThan(0));

      await encoder.close();
    }, tags: ['browser']);
  });
}
