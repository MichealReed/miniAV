/// The D3D11 encoder's cache of IMPORTED PRODUCER TEXTURES must be dropped
/// when those textures stop being valid.
///
/// The native side of this was already correct and covered by its own tests in
/// miniav_tools_codecs. What was missing was any CALLER at all: the cache pins
/// each producer surface with a reference (that pin is what makes a texture
/// POINTER a safe cache key — free a texture and the next allocation may reuse
/// its address, and a pointer-keyed hit would then encode a stale picture
/// forever), so nothing ever released them. On a 4K screen recording that is
/// ~135 MB of VRAM the producer has finished with, held until LRU eviction
/// happens to walk past it.
///
/// These tests drive [EncoderImportCache] — the unit the recorder's video
/// runtime delegates both invalidation points to — with fake encoders. Pure
/// Dart: no GPU, no capture, no Media Foundation.
///
/// Every decision about WHICH frames and WHICH tracks report lives in that
/// unit rather than at the call site, because `_VideoTrackRuntime` is
/// library-private, needs a live `Recorder`, and releases buffers through
/// native MiniAV — there is no double that reaches it. What is left of the
/// wiring is two delegating lines, and the last group asserts those at source
/// level; see the note above it for why that is weak but not nothing.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:miniav_recorder/miniav_recorder.dart';
import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';
import 'package:test/test.dart';

/// A capture frame whose payload lives in a D3D11 texture the PRODUCER owns —
/// the only shape that can put an entry in the encoder's import cache.
MiniAVBuffer _gpuFrame(int width, int height) => MiniAVBuffer(
  type: MiniAVBufferType.video,
  contentType: MiniAVBufferContentType.gpuD3D11Handle,
  timestampUs: 0,
  dataSizeBytes: 0,
  data: MiniAVVideoBuffer(
    width: width,
    height: height,
    pixelFormat: MiniAVPixelFormat.bgra32,
    strideBytes: const [],
    planes: const [],
    nativeHandles: const [0xDEADBEEF],
  ),
);

/// The same geometry delivered as CPU pixels. Nothing was imported, so nothing
/// can be stale.
MiniAVBuffer _cpuFrame(int width, int height) => MiniAVBuffer(
  type: MiniAVBufferType.video,
  contentType: MiniAVBufferContentType.cpu,
  timestampUs: 0,
  dataSizeBytes: width * height * 4,
  data: MiniAVVideoBuffer(
    width: width,
    height: height,
    pixelFormat: MiniAVPixelFormat.bgra32,
    strideBytes: [width * 4],
    planes: [Uint8List(0)],
    nativeHandles: const [],
  ),
);

/// An encoder with no import cache — every encoder but the Media Foundation
/// one. It must never be called and must never throw.
class _PlainEncoder implements PlatformEncoder {
  @override
  Future<EncodedPacket?> encode(FrameSource frame) async => null;
  @override
  Future<List<EncodedPacket>> flush() async => const [];
  @override
  Future<void> requestKeyframe() async {}
  @override
  CodecExtraData? get extraData => null;
  @override
  Future<void> close() async {}
  @override
  bool get supportsGpuBufferInput => false;
  @override
  bool get acceptsYuv420pPlanes => false;
  @override
  bool get supportsD3d11SharedHandleInput => false;
  @override
  bool get supportsD3d11TextureInput => false;
}

/// The MF encoder's shape: `int invalidateImports()`, returning how many cache
/// entries it released.
class _ImportingEncoder extends _PlainEncoder {
  int calls = 0;

  /// Entries currently pinned. Drained by an invalidation, refilled by the
  /// producer — mirroring a cache that fills back up after a resize.
  int pinned = 4;

  int invalidateImports() {
    calls++;
    final released = pinned;
    pinned = 0;
    return released;
  }
}

/// Right name, wrong signature — a duck-typed probe must reject it rather than
/// call it and blow up on the return value.
class _WrongShapeEncoder extends _PlainEncoder {
  int calls = 0;
  String invalidateImports() {
    calls++;
    return 'not a count';
  }
}

void main() {
  group('capability probe', () {
    test('an encoder that keeps an import cache is detected', () {
      expect(EncoderImportCache(_ImportingEncoder()).supported, isTrue);
    });

    test('an encoder without one is detected, and is a silent no-op', () {
      final cache = EncoderImportCache(_PlainEncoder());
      expect(cache.supported, isFalse);
      // Both entry points must be safe on it: they are on the video hot path
      // and run for every encoder, not just the MF one.
      expect(cache.noteProducerSize(1920, 1080), -1);
      expect(cache.noteProducerSize(1280, 720), -1);
      expect(cache.invalidate(), -1);
      expect(cache.invalidations, 0);
    });

    test('a same-named member of the wrong type is not called', () {
      final enc = _WrongShapeEncoder();
      final cache = EncoderImportCache(enc);
      expect(cache.supported, isFalse);
      cache.noteProducerSize(1920, 1080);
      cache.noteProducerSize(1280, 720);
      expect(cache.invalidate(), -1);
      expect(enc.calls, 0, reason: 'the probe must not invoke it');
    });
  });

  group('resolution change', () {
    test('the first frame is not a change', () {
      final enc = _ImportingEncoder();
      final cache = EncoderImportCache(enc);
      expect(cache.noteProducerSize(1920, 1080), -1);
      expect(enc.calls, 0, reason: 'nothing was imported before it');
    });

    test('a steady stream of same-sized frames never invalidates', () {
      final enc = _ImportingEncoder();
      final cache = EncoderImportCache(enc);
      for (var i = 0; i < 200; i++) {
        cache.noteProducerSize(1920, 1080);
      }
      expect(enc.calls, 0);
      expect(cache.invalidations, 0);
    });

    test('a resolution change drops the cache exactly once', () {
      final enc = _ImportingEncoder();
      final cache = EncoderImportCache(enc);
      cache.noteProducerSize(3840, 2160);
      expect(
        cache.noteProducerSize(1920, 1080),
        4,
        reason: 'returns how many producer surfaces were released',
      );
      expect(enc.calls, 1);
      // The frames that follow the change carry the NEW geometry and must not
      // keep re-dropping a cache the producer is busy refilling.
      cache.noteProducerSize(1920, 1080);
      cache.noteProducerSize(1920, 1080);
      expect(enc.calls, 1);
      expect(cache.invalidations, 1);
    });

    test('a height-only change counts (letterbox / rotate)', () {
      final enc = _ImportingEncoder();
      final cache = EncoderImportCache(enc);
      cache.noteProducerSize(1920, 1080);
      cache.noteProducerSize(1920, 1200);
      expect(enc.calls, 1);
    });

    test('a flapping resolution invalidates on each flip', () {
      final enc = _ImportingEncoder();
      final cache = EncoderImportCache(enc);
      cache.noteProducerSize(1920, 1080);
      for (var i = 0; i < 3; i++) {
        enc.pinned = 4; // producer refills between flips
        cache.noteProducerSize(1280, 720);
        enc.pinned = 4;
        cache.noteProducerSize(1920, 1080);
      }
      expect(enc.calls, 6);
    });
  });

  group('texture-ring rebuild', () {
    test('invalidate() drops unconditionally — geometry cannot show it', () {
      final enc = _ImportingEncoder();
      final cache = EncoderImportCache(enc);
      cache.noteProducerSize(1920, 1080);
      // The shared-output ring is ENCODER-sized, so a rebuilt ring looks
      // identical to noteProducerSize. Only the explicit call can say it.
      expect(cache.invalidate(), 4);
      expect(enc.calls, 1);
      expect(cache.invalidations, 1);
    });

    test('a rebuild does not disturb the geometry the resize path tracks', () {
      final enc = _ImportingEncoder();
      final cache = EncoderImportCache(enc);
      cache.noteProducerSize(1920, 1080);
      cache.invalidate();
      enc.pinned = 4;
      // Still 1920x1080 — the ring changed, the source size did not.
      expect(cache.noteProducerSize(1920, 1080), -1);
      expect(enc.calls, 1, reason: 'only the explicit rebuild call fired');
    });
  });

  // noteFrame is what the video runtime actually calls, so the decision of
  // WHICH frames and WHICH tracks report belongs here rather than at the call
  // site — a branch in the runtime would be a branch no test can reach.
  group('which frames report', () {
    test('a D3D11 producer frame reports its geometry', () {
      final enc = _ImportingEncoder();
      final cache = EncoderImportCache(enc);
      cache.noteFrame(_gpuFrame(3840, 2160));
      expect(cache.noteFrame(_gpuFrame(1920, 1080)), 4);
      expect(enc.calls, 1);
    });

    test('a CPU frame never reports — nothing was imported from it', () {
      final enc = _ImportingEncoder();
      final cache = EncoderImportCache(enc);
      expect(cache.noteFrame(_cpuFrame(3840, 2160)), -1);
      expect(cache.noteFrame(_cpuFrame(1920, 1080)), -1);
      expect(enc.calls, 0);
    });

    test('a CPU frame does not poison the geometry a GPU frame tracks', () {
      final enc = _ImportingEncoder();
      final cache = EncoderImportCache(enc);
      cache.noteFrame(_gpuFrame(1920, 1080));
      cache.noteFrame(_cpuFrame(1280, 720));
      // The imports still came from 1920x1080, so this is not a change.
      expect(cache.noteFrame(_gpuFrame(1920, 1080)), -1);
      expect(enc.calls, 0);
    });

    test('a buffer with no video payload is ignored, not crashed on', () {
      // MiniAVBuffer.data is Object? — the geometry read has to be a type
      // test, not a cast, or a malformed frame takes down the encode loop.
      final enc = _ImportingEncoder();
      final cache = EncoderImportCache(enc);
      final noPayload = MiniAVBuffer(
        type: MiniAVBufferType.video,
        contentType: MiniAVBufferContentType.gpuD3D11Handle,
        timestampUs: 0,
        dataSizeBytes: 0,
        data: null,
      );
      expect(cache.noteFrame(noPayload), -1);
      expect(enc.calls, 0);
    });
  });

  group('which tracks report', () {
    test('a track that never submits producer textures reports nothing', () {
      // The pure GPU-processor path: what the encoder imports is the
      // PROCESSOR's shared-output ring, which is encoder-sized and unmoved by
      // a producer resize. Reporting one would drop a cache the geometry does
      // not describe — and the encoder's retained repeat source with it.
      final enc = _ImportingEncoder();
      final cache = EncoderImportCache(enc, importsProducerTextures: false);
      expect(cache.supported, isTrue, reason: 'the cache still exists');
      cache.noteFrame(_gpuFrame(3840, 2160));
      expect(cache.noteFrame(_gpuFrame(1920, 1080)), -1);
      expect(enc.calls, 0);
      expect(cache.invalidations, 0);
    });

    test('an explicit ring rebuild still drops on such a track', () {
      // Only the resize SIGNAL is muted; the ring the processor tore down is
      // exactly the thing this track's cache holds.
      final enc = _ImportingEncoder();
      final cache = EncoderImportCache(enc, importsProducerTextures: false);
      expect(cache.invalidate(), 4);
      expect(enc.calls, 1);
    });

    test(
      'a producer-submitting track reports (passthrough / no processor)',
      () {
        final enc = _ImportingEncoder();
        final cache = EncoderImportCache(enc, importsProducerTextures: true);
        cache.noteFrame(_gpuFrame(3840, 2160));
        expect(cache.noteFrame(_gpuFrame(1920, 1080)), 4);
      },
    );
  });

  // What a caller MUST do with the return value. The encoder's retained repeat
  // source (its `last_sub`) goes out with the imports, and no getter exposes
  // that — a CFR idle filler that keeps believing a duplicate is possible
  // claims a grid slot repeatLastFrame then refuses to fill, and the hole is
  // permanent.
  group('invalidation is observable so the caller can react', () {
    test('every drop returns >= 0 and every no-op returns -1', () {
      final enc = _ImportingEncoder();
      final cache = EncoderImportCache(enc);
      expect(cache.noteFrame(_gpuFrame(1920, 1080)), -1, reason: 'first frame');
      expect(cache.noteFrame(_gpuFrame(1920, 1080)), -1, reason: 'unchanged');
      expect(cache.noteFrame(_gpuFrame(1280, 720)) >= 0, isTrue);
      expect(cache.invalidate() >= 0, isTrue);
    });

    test('an empty cache still reports the drop (0, not -1)', () {
      // The count is how much VRAM came back, not whether the repeat source
      // survived. A caller keying off `> 0` would miss exactly the case where
      // the imports were already evicted but `last_sub` was not.
      final enc = _ImportingEncoder()..pinned = 0;
      final cache = EncoderImportCache(enc);
      cache.noteFrame(_gpuFrame(1920, 1080));
      expect(cache.noteFrame(_gpuFrame(1280, 720)), 0);
    });

    test('an encoder with no cache stays at -1 so nothing is cleared', () {
      final cache = EncoderImportCache(_PlainEncoder());
      cache.noteFrame(_gpuFrame(1920, 1080));
      expect(cache.noteFrame(_gpuFrame(1280, 720)), -1);
    });
  });

  // ── The part this file cannot prove behaviourally ────────────────────────
  //
  // Everything above drives EncoderImportCache directly. The unit under test
  // is only useful if _VideoTrackRuntime actually calls it, and that class is
  // library-private, needs a live Recorder for `now()`/`dispatchPacket`, and
  // releases every buffer through native MiniAV — so there is no test double
  // that reaches the call sites. Deleting both of them left all the
  // behavioural tests green, which made the deliverable itself unverified.
  //
  // A source-level assertion is a poor substitute for executing the code, and
  // it is deliberately the WEAKEST claim that still fails on a revert: it says
  // the two calls exist in the two methods that own them, and that the resize
  // call site acts on the return value. It cannot say they run on the right
  // frames — that part is the tested unit's job, which is why the branching
  // was moved into it.
  group('recorder wiring (source-level — see the note above)', () {
    late String source;

    setUpAll(() {
      final f = File('lib/src/recorder.dart');
      // Not markTestSkipped: skipping here would silently restore the exact
      // gap this group exists to close.
      expect(
        f.existsSync(),
        isTrue,
        reason: 'run from the miniav_recorder package root',
      );
      // Normalised: the repo is checked out with CRLF on Windows, and the
      // member-boundary scan below matches on `\n  }\n`.
      source = f.readAsStringSync().replaceAll('\r\n', '\n');
    });

    /// The body of a method declared at class-member indentation, from its
    /// signature to the next member at the same indentation.
    String bodyOf(String signature) {
      final start = source.indexOf(signature);
      expect(start, isNot(-1), reason: 'no `$signature` in recorder.dart');
      final end = source.indexOf('\n  }\n', start);
      expect(end, isNot(-1), reason: '`$signature` has no closing brace');
      return source.substring(start, end);
    }

    test('the encode path reports producer geometry', () {
      expect(
        bodyOf('Future<void> _encodeOne('),
        contains('_imports.noteFrame('),
        reason: 'without this the encoder pins dead producer surfaces',
      );
    });

    test('the encode path acts on the drop it just caused', () {
      // The clear must be tied to the call, not merely present in the file.
      final body = bodyOf('Future<void> _encodeOne(');
      final call = body.indexOf('_imports.noteFrame(');
      expect(call, isNot(-1));
      expect(
        body.substring(call, math.min(call + 200, body.length)),
        contains('_lastSharedTex = null'),
        reason:
            'a drop releases the encoder\'s retained repeat source, so '
            'the duplicator\'s proof it can still repeat must go too',
      );
    });

    test('the idle filler reports a torn-down texture ring', () {
      expect(
        bodyOf('void _maybeDuplicateLast()'),
        contains('_imports.invalidate()'),
        reason:
            'a rebuilt ring is invisible in frame geometry — only this '
            'explicit call can say it',
      );
    });
  });
}
