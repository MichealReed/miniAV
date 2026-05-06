/// Stage B (zero-copy D3D11VA) hardware-encoder tests.
///
/// These exercise the real GPU pipeline using a self-contained NT-shared
/// BGRA texture produced by the test-only shim helpers — no miniav, no
/// screen capture, no display required. Skips cleanly when:
///   * not on Windows,
///   * no FFmpeg in this environment,
///   * the shim asset is unavailable, or
///   * no D3D11VA-capable encoder is registered.
@TestOn('vm')
@Tags(['windows-gpu'])
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:miniav_platform_interface/miniav_platform_types.dart';
import 'package:miniav_tools_ffmpeg/miniav_tools_ffmpeg.dart';
import 'package:miniav_tools_ffmpeg/src/ffmpeg_shim.dart';
import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';
import 'package:test/test.dart';

void main() {
  group('Stage B / D3D11 zero-copy encoder', () {
    late bool ffmpegOk;

    setUpAll(() async {
      if (!Platform.isWindows) return;
      try {
        await ensureFFmpegLoaded();
        ffmpegOk = true;
      } catch (_) {
        ffmpegOk = false;
      }
    });

    test('shim ABI matches expected version', () {
      if (!Platform.isWindows) {
        markTestSkipped('Stage B is Windows-only');
        return;
      }
      final shim = FfmpegShim.tryLoad();
      if (shim == null) {
        markTestSkipped('shim asset not available');
        return;
      }
      expect(shim.abiVersion(), FfmpegShim.kExpectedAbiVersion);
    });

    test('vendor probe is fast and returns a list', () {
      if (!Platform.isWindows) {
        markTestSkipped('Stage B is Windows-only');
        return;
      }
      if (!ffmpegOk) {
        markTestSkipped('FFmpeg not loaded');
        return;
      }
      final sw = Stopwatch()..start();
      final vendors = ffmpegD3d11VendorsAvailable();
      sw.stop();
      print(
        'D3D11 vendors: $vendors  (probe took ${sw.elapsedMilliseconds}ms)',
      );
      expect(vendors, isA<List<D3d11HwVendor>>());
      // Symbol lookup only — must complete well under 100ms even on cold disk.
      expect(sw.elapsedMilliseconds, lessThan(500));
    });

    test('ffmpegD3d11EncoderAvailable agrees with vendor probe', () {
      if (!Platform.isWindows || !ffmpegOk) {
        markTestSkipped('preconditions');
        return;
      }
      if (FfmpegShim.tryLoad() == null) {
        markTestSkipped('shim asset not available');
        return;
      }
      final hasAnyHevcVendor = ffmpegD3d11VendorsAvailable().isNotEmpty;
      final hevcAvail = ffmpegD3d11EncoderAvailable(VideoCodec.hevc);
      // If at least one vendor is present, hevc availability must hold (every
      // shipping vendor we list supports hevc).
      if (hasAnyHevcVendor) {
        expect(hevcAvail, isTrue);
      }
    });

    test(
      'per-vendor open succeeds OR throws CodecInitException — never crashes',
      () {
        if (!Platform.isWindows || !ffmpegOk) {
          markTestSkipped('preconditions');
          return;
        }
        if (FfmpegShim.tryLoad() == null) {
          markTestSkipped('shim asset not available');
          return;
        }
        final vendors = ffmpegD3d11VendorsAvailable();
        if (vendors.isEmpty) {
          markTestSkipped('no D3D11 vendor on this system');
          return;
        }

        const cfg = EncoderConfig(
          codec: VideoCodec.hevc,
          width: 1280,
          height: 720,
          bitrateBps: 2_000_000,
          frameRateNumerator: 30,
          frameRateDenominator: 1,
          bFrameCount: 0,
          hwAccel: HwAccelPreference.required,
          rateControl: RateControl.vbr,
        );

        var openedAtLeastOne = false;
        for (final v in vendors) {
          FfmpegD3d11HwEncoder? enc;
          try {
            enc = FfmpegD3d11HwEncoder.openWith(cfg, v);
            openedAtLeastOne = true;
            expect(enc.vendor, v);
            print('OPEN OK: $v / ${enc.encoderName}');
          } on CodecInitException catch (e) {
            print('OPEN SKIP: $v — ${e.message.split('\n').first}');
          } finally {
            enc?.close();
          }
        }
        expect(
          openedAtLeastOne,
          isTrue,
          reason:
              'Every detected vendor failed to even open. Driver runtime '
              'probably missing (amfrt64.dll / libmfx / mfreadwrite.dll).',
        );
      },
    );

    test(
      'end-to-end zero-copy: NT-shared BGRA → encoded HEVC packets',
      () async {
        if (!Platform.isWindows || !ffmpegOk) {
          markTestSkipped('preconditions');
          return;
        }
        final shim = FfmpegShim.tryLoad();
        if (shim == null) {
          markTestSkipped('shim asset not available');
          return;
        }
        if (ffmpegD3d11VendorsAvailable().isEmpty) {
          markTestSkipped('no D3D11 encoder vendor on this system');
          return;
        }

        const w = 1280;
        const h = 720;
        const cfg = EncoderConfig(
          codec: VideoCodec.hevc,
          width: w,
          height: h,
          bitrateBps: 4_000_000,
          frameRateNumerator: 30,
          frameRateDenominator: 1,
          bFrameCount: 0,
          gopLength: 30,
          hwAccel: HwAccelPreference.required,
          rateControl: RateControl.vbr,
        );

        final enc = FfmpegD3d11HwEncoder.open(cfg);
        print('chosen vendor: ${enc.vendor} (${enc.encoderName})');

        // Producer-side: independent device + texture, NT shared handle.
        final tex = shim.testCreateSharedBgra(w, h);
        expect(
          tex,
          isNot(equals(nullptr)),
          reason: 'shim could not create producer texture',
        );

        try {
          var packets = 0;
          var bytes = 0;
          for (var i = 0; i < 30; i++) {
            // Re-fill so adjacent frames differ (encoder otherwise emits a
            // single tiny IDR + repeat-references — still valid but less
            // realistic). Tag rotates through 0..255.
            final fillRet = shim.testFillBgra(tex, i);
            expect(fillRet, 0);

            final ntHandle = shim.testTextureHandle(tex);
            expect(ntHandle, isNot(equals(nullptr)));

            final src = FrameSource.d3d11Texture(
              texturePtr: ntHandle.address,
              width: w,
              height: h,
              pixelFormat: MiniAVPixelFormat.bgra32,
              timestampUs: i * 33333,
            );
            final pkt = await enc.encode(src);
            if (pkt != null) {
              packets++;
              bytes += pkt.data.length;
            }
          }
          final tail = await enc.flush();
          for (final p in tail) {
            packets++;
            bytes += p.data.length;
          }
          print('encoded $packets packets, $bytes bytes');
          expect(packets, greaterThan(0));
          // Black/empty output would be ~60-200 bytes; real content with
          // 30 BGRA changing frames at 4Mbps target should comfortably
          // exceed 5 KB.
          expect(
            bytes,
            greaterThan(5000),
            reason:
                'Output suspiciously small ($bytes bytes) — looks like the '
                'producer texture never made it to the encoder (cross-device '
                'sync regression?).',
          );
        } finally {
          await enc.close();
          shim.testDestroyTexture(tex);
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'encoder rejects mismatched frame size with CodecRuntimeException',
      () async {
        if (!Platform.isWindows || !ffmpegOk) {
          markTestSkipped('preconditions');
          return;
        }
        final shim = FfmpegShim.tryLoad();
        if (shim == null || ffmpegD3d11VendorsAvailable().isEmpty) {
          markTestSkipped('no shim / no vendor');
          return;
        }
        const cfg = EncoderConfig(
          codec: VideoCodec.hevc,
          width: 640,
          height: 480,
          bitrateBps: 1_000_000,
          frameRateNumerator: 30,
          frameRateDenominator: 1,
          bFrameCount: 0,
          hwAccel: HwAccelPreference.required,
        );
        final enc = FfmpegD3d11HwEncoder.open(cfg);
        final tex = shim.testCreateSharedBgra(1280, 720);
        try {
          shim.testFillBgra(tex, 0);
          final src = FrameSource.d3d11Texture(
            texturePtr: shim.testTextureHandle(tex).address,
            width: 1280,
            height: 720,
            pixelFormat: MiniAVPixelFormat.bgra32,
          );
          await expectLater(
            enc.encode(src),
            throwsA(isA<CodecRuntimeException>()),
          );
        } finally {
          await enc.close();
          shim.testDestroyTexture(tex);
        }
      },
    );

    test('non-D3D11 frame source throws CodecRuntimeException', () async {
      if (!Platform.isWindows || !ffmpegOk) {
        markTestSkipped('preconditions');
        return;
      }
      if (FfmpegShim.tryLoad() == null ||
          ffmpegD3d11VendorsAvailable().isEmpty) {
        markTestSkipped('no shim / no vendor');
        return;
      }
      const cfg = EncoderConfig(
        codec: VideoCodec.hevc,
        width: 640,
        height: 480,
        bitrateBps: 1_000_000,
        frameRateNumerator: 30,
        frameRateDenominator: 1,
        bFrameCount: 0,
        hwAccel: HwAccelPreference.required,
      );
      final enc = FfmpegD3d11HwEncoder.open(cfg);
      try {
        final src = FrameSource.cpu(
          bytes: Uint8List(640 * 480 * 4),
          pixelFormat: MiniAVPixelFormat.bgra32,
          width: 640,
          height: 480,
        );
        // Wrong source kind — encoder must reject loud, not produce garbage.
        await expectLater(
          enc.encode(src),
          throwsA(isA<CodecRuntimeException>()),
        );
      } finally {
        await enc.close();
      }
    });

    test('D3d11HwSourceFormat enum is exported with bgra and rgba', () {
      // Surface-level guard: the constants are referenced by callers
      // (screenshare_mp4, minigpu integrations) via the public export, so a
      // missing show-clause is a real regression. Cheap to verify.
      expect(D3d11HwSourceFormat.values, hasLength(2));
      expect(D3d11HwSourceFormat.values, contains(D3d11HwSourceFormat.bgra));
      expect(D3d11HwSourceFormat.values, contains(D3d11HwSourceFormat.rgba));
    });

    test(
      'openWith(sourceTextureFormat: rgba) opens or fails cleanly — never crashes',
      () {
        if (!Platform.isWindows || !ffmpegOk) {
          markTestSkipped('preconditions');
          return;
        }
        if (FfmpegShim.tryLoad() == null) {
          markTestSkipped('shim asset not available');
          return;
        }
        final vendors = ffmpegD3d11VendorsAvailable();
        if (vendors.isEmpty) {
          markTestSkipped('no D3D11 vendor on this system');
          return;
        }
        const cfg = EncoderConfig(
          codec: VideoCodec.hevc,
          width: 640,
          height: 360,
          bitrateBps: 1_500_000,
          frameRateNumerator: 30,
          frameRateDenominator: 1,
          bFrameCount: 0,
          hwAccel: HwAccelPreference.required,
        );
        // Try one vendor with rgba sw_format. Either we get an encoder
        // configured against an RGBA hwframes pool, or av_hwframe_ctx_init
        // refuses RGBA on this driver and we get a clean CodecInitException.
        FfmpegD3d11HwEncoder? enc;
        try {
          enc = FfmpegD3d11HwEncoder.openWith(
            cfg,
            vendors.first,
            sourceTextureFormat: D3d11HwSourceFormat.rgba,
          );
          expect(enc.encoderName, isNotEmpty);
        } on CodecInitException catch (e) {
          // Acceptable: not every driver accepts AV_PIX_FMT_RGBA in the
          // D3D11 hwframes pool. The contract is "no crash".
          expect(e.message, isNotEmpty);
        } finally {
          enc?.close();
        }
      },
    );

    test('openWith(existingD3d11Device: 0) is the documented default path', () {
      // Smoke-coverage for the new optional parameter at the API level:
      // passing the default sentinel must behave identically to omitting
      // it (FFmpeg picks adapter 0). End-to-end coverage of a non-zero
      // device pointer lives in the screenshare_mp4 example, which wires
      // minigpu's createD3D11DeviceOnDawnAdapter through to this call —
      // we don't pull minigpu into this package's test deps just for that.
      if (!Platform.isWindows || !ffmpegOk) {
        markTestSkipped('preconditions');
        return;
      }
      if (FfmpegShim.tryLoad() == null ||
          ffmpegD3d11VendorsAvailable().isEmpty) {
        markTestSkipped('no shim / no vendor');
        return;
      }
      const cfg = EncoderConfig(
        codec: VideoCodec.hevc,
        width: 640,
        height: 360,
        bitrateBps: 1_000_000,
        frameRateNumerator: 30,
        frameRateDenominator: 1,
        bFrameCount: 0,
        hwAccel: HwAccelPreference.required,
      );
      final enc = FfmpegD3d11HwEncoder.open(cfg, existingD3d11Device: 0);
      try {
        expect(enc.encoderName, isNotEmpty);
      } finally {
        enc.close();
      }
    });
  });
}
