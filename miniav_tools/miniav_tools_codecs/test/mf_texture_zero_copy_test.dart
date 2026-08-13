/// The scale/effects zero-copy path: a BGRA texture on ANOTHER device, imported
/// cross-device and converted to NV12 by a D3D11 VideoProcessor — no readback.
///
/// This is the branch the recorder takes when a scale policy or effects are
/// configured. It is worth a real test rather than a compile check: on failure
/// `MfVideoEncoder.encode` THROWS (a GPU-resident frame has no CPU pixels to
/// fall back to), so a broken path kills a live recording rather than quietly
/// slowing it down.
///
/// The source texture is created on its own D3D11 device with
/// `D3D11_RESOURCE_MISC_SHARED` — the same shape minigpu's `SharedOutputTexture`
/// has, which is what makes the cross-device import legal.
@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';
import 'package:miniav_tools_codecs/src/codecs_native.dart';
import 'package:test/test.dart';

const _w = 640, _h = 480;

void main() {
  test('an injected device that cannot do NV12 is declined, not adopted',
      () async {
    // The regression this guards: adopting the caller's device unconditionally.
    // A rendering device (Dawn's, for one) is created without
    // D3D11_CREATE_DEVICE_VIDEO_SUPPORT. It still QueryInterfaces to
    // ID3D11VideoDevice and still builds a VideoProcessor -- and then cannot
    // allocate the NV12 render target the conversion writes into, so every
    // texture frame failed before the import was even attempted. The encoder
    // must notice up front and build its own device instead.
    //
    // A BGRA-only device stands in for that shape: created without video
    // support, exactly like a rendering device.
    final plain = mfencTestPlainDevice();
    if (plain == nullptr) {
      markTestSkipped('could not create a video-support-free D3D11 device');
      return;
    }
    addTearDown(() => mfencTestDeviceRelease(plain));

    final enc = await MfVideoEncoder.open(
      const EncoderConfig(
        codec: VideoCodec.h264,
        width: _w,
        height: _h,
        bitrateBps: 2000000,
        frameRateNumerator: 30,
        frameRateDenominator: 1,
        gopLength: 30,
      ),
      existingD3d11Device: plain.address,
    );
    expect(enc, isNotNull, reason: 'encoder refused to open at all');
    addTearDown(() => enc!.close());
    if (!enc!.supportsD3d11Input) {
      markTestSkipped('no D3D11 path on this machine');
      return;
    }

    final tex = mfencTestSharedFmt(_w, _h, 1, 1, 1); // NT-shared RGBA
    expect(tex, isNot(nullptr));
    addTearDown(() => mfencTestTextureRelease(tex));

    final packets = <EncodedPacket>[];
    for (var i = 0; i < 10; i++) {
      final p = await enc.encode(D3D11TextureFrameSource(
        texturePtr: tex.address,
        width: _w,
        height: _h,
        pixelFormat: MiniAVPixelFormat.rgba32,
        timestampUs: i * 33333,
      ));
      if (p != null) packets.add(p);
    }
    packets.addAll(await enc.flush());
    expect(packets, isNotEmpty,
        reason: 'encoding produced nothing when handed a device without video '
            'support — it adopted the device instead of declining it. '
            'Native reason: ${enc.lastImportError}');
  });

  test('ODD frame dimensions still encode from a texture', () async {
    // 4:2:0 subsamples chroma 2x2, so a DXGI NV12 texture must have EVEN width
    // and height -- CreateTexture2D returns E_INVALIDARG otherwise. Real
    // capture sizes are arbitrary: a window at 2576x1119 is an odd HEIGHT, and
    // every test here had used 640x480 or 320x240, so the staging allocation
    // failed in the field while passing the whole suite.
    const ow = 641, oh = 361; // odd in both axes
    final enc = await MfVideoEncoder.open(const EncoderConfig(
      codec: VideoCodec.h264,
      width: ow,
      height: oh,
      bitrateBps: 2000000,
      frameRateNumerator: 30,
      frameRateDenominator: 1,
      gopLength: 30,
    ));
    if (enc == null) {
      markTestSkipped('encoder would not open at odd dimensions');
      return;
    }
    addTearDown(() => enc.close());
    if (!enc.supportsD3d11Input) {
      markTestSkipped('no D3D11 path');
      return;
    }
    final tex = mfencTestSharedFmt(ow, oh, 1, 1, 1);
    expect(tex, isNot(nullptr));
    addTearDown(() => mfencTestTextureRelease(tex));

    final packets = <EncodedPacket>[];
    for (var i = 0; i < 10; i++) {
      final p = await enc.encode(D3D11TextureFrameSource(
        texturePtr: tex.address,
        width: ow,
        height: oh,
        pixelFormat: MiniAVPixelFormat.rgba32,
        timestampUs: i * 33333,
      ));
      if (p != null) packets.add(p);
    }
    packets.addAll(await enc.flush());
    expect(packets, isNotEmpty,
        reason: 'odd dimensions produced nothing. Native reason: '
            '${enc.lastImportError}');
  });

  // BOTH pixel formats. The recorder's GPU processor hands over RGBA
  // (`MiniAVPixelFormat.rgba32`); every other test here used BGRA, so a
  // VideoProcessor that refuses RGBA input would pass the whole suite and fail
  // every real frame.
  for (final (fmt, label) in [(0, 'BGRA'), (1, 'RGBA')]) {
    test('$label source is accepted by the VideoProcessor', () async {
      final enc = await MfVideoEncoder.open(const EncoderConfig(
        codec: VideoCodec.h264,
        width: _w,
        height: _h,
        bitrateBps: 2000000,
        frameRateNumerator: 30,
        frameRateDenominator: 1,
        gopLength: 30,
      ));
      expect(enc, isNotNull);
      addTearDown(() => enc!.close());
      if (!enc!.supportsD3d11Input) {
        markTestSkipped('no D3D11 device bound');
        return;
      }
      final tex = mfencTestSharedFmt(_w, _h, 1, 1, fmt);
      expect(tex, isNot(nullptr));
      addTearDown(() => mfencTestTextureRelease(tex));

      final packets = <EncodedPacket>[];
      for (var i = 0; i < 10; i++) {
        final p = await enc.encode(D3D11TextureFrameSource(
          texturePtr: tex.address,
          width: _w,
          height: _h,
          pixelFormat: fmt == 0
              ? MiniAVPixelFormat.bgra32
              : MiniAVPixelFormat.rgba32,
          timestampUs: i * 33333,
        ));
        if (p != null) packets.add(p);
      }
      packets.addAll(await enc.flush());
      expect(packets, isNotEmpty,
          reason: '$label produced nothing. Native reason: '
              '\${enc.lastImportError}');
    });
  }

  // Both sharing shapes. The NT-handle case is the one real GPU producers use
  // (minigpu's shared output texture documents CreateSharedHandle +
  // OpenSharedResource1); the legacy case is what older producers publish. An
  // importer that only handles one fails in the field while passing here, which
  // is precisely what happened.
  for (final (nt, label) in [(0, 'legacy MISC_SHARED'), (1, 'NT handle')]) {
    test('BGRA texture shared via $label encodes without readback', () async {
      final enc = await MfVideoEncoder.open(const EncoderConfig(
        codec: VideoCodec.h264,
        width: _w,
        height: _h,
        bitrateBps: 4000000,
        frameRateNumerator: 30,
        frameRateDenominator: 1,
        gopLength: 30,
      ));
      expect(enc, isNotNull);
      addTearDown(() => enc!.close());
      if (!enc!.supportsD3d11Input) {
        markTestSkipped('no D3D11 device bound (software MFT)');
        return;
      }
      final tex = mfencTestSharedBgraEx(_w, _h, 1, nt);
      expect(tex, isNot(nullptr), reason: 'could not create a $label source');
      addTearDown(() => mfencTestTextureRelease(tex));

      final packets = <EncodedPacket>[];
      for (var i = 0; i < 20; i++) {
        final p = await enc.encode(D3D11TextureFrameSource(
          texturePtr: tex.address,
          width: _w,
          height: _h,
          pixelFormat: MiniAVPixelFormat.bgra32,
          timestampUs: i * 33333,
        ));
        if (p != null) packets.add(p);
      }
      packets.addAll(await enc.flush());
      expect(packets, isNotEmpty,
          reason: '$label source produced NOTHING — the importer does not '
              'handle this sharing mode, which in the field means a recording '
              'with no video track at all');
      expect(packets.any((p) => p.isKeyframe), isTrue);
    });
  }

  test('BGRA texture on a foreign device encodes without readback', () async {
    final enc = await MfVideoEncoder.open(const EncoderConfig(
      codec: VideoCodec.h264,
      width: _w,
      height: _h,
      bitrateBps: 4000000,
      frameRateNumerator: 30,
      frameRateDenominator: 1,
      gopLength: 30,
    ));
    expect(enc, isNotNull, reason: 'MF H.264 encoder failed to open');
    addTearDown(() => enc!.close());

    if (!enc!.supportsD3d11Input) {
      markTestSkipped('no D3D11 device bound (software MFT) — nothing to test');
      return;
    }
    // NB: deliberately does NOT assert `supportsD3d11TextureInput` — that flag
    // is the recorder-facing switch and is flipped only once this test passes.
    // `encode()` routes a texture frame on `supportsD3d11Input`, so the path
    // under test is reachable either way.

    final tex = mfencTestSharedBgra(_w, _h, 1);
    expect(tex, isNot(nullptr), reason: 'could not create a shared BGRA source');
    addTearDown(() => mfencTestTextureRelease(tex));

    final packets = <EncodedPacket>[];
    for (var i = 0; i < 20; i++) {
      final p = await enc.encode(D3D11TextureFrameSource(
        texturePtr: tex.address,
        width: _w,
        height: _h,
        pixelFormat: MiniAVPixelFormat.bgra32,
        timestampUs: i * 33333,
      ));
      if (p != null) packets.add(p);
    }
    packets.addAll(await enc.flush());

    expect(packets, isNotEmpty, reason: 'VideoProcessor path produced nothing');
    expect(packets.any((p) => p.isKeyframe), isTrue, reason: 'no keyframe');
    expect(enc.isHardware, isTrue);

    // POSITIVE CONTROL. "It produced packets" proves nothing here: if the
    // VideoProcessor silently wrote nothing, the NV12 staging texture stays
    // uniform and still encodes fine — just tiny. So encode a FLAT GREY source
    // through the identical path and require the gradient to cost materially
    // more bits. Equal sizes ⇒ the blt never transferred the picture.
    final gradientBytes = packets.fold<int>(0, (a, p) => a + p.data.length);

    final flat = mfencTestSharedBgra(_w, _h, 0);
    expect(flat, isNot(nullptr));
    addTearDown(() => mfencTestTextureRelease(flat));
    final enc2 = await MfVideoEncoder.open(const EncoderConfig(
      codec: VideoCodec.h264,
      width: _w,
      height: _h,
      bitrateBps: 4000000,
      frameRateNumerator: 30,
      frameRateDenominator: 1,
      gopLength: 30,
    ));
    addTearDown(() => enc2!.close());
    final flatPackets = <EncodedPacket>[];
    for (var i = 0; i < 20; i++) {
      final p = await enc2!.encode(D3D11TextureFrameSource(
        texturePtr: flat.address,
        width: _w,
        height: _h,
        pixelFormat: MiniAVPixelFormat.bgra32,
        timestampUs: i * 33333,
      ));
      if (p != null) flatPackets.add(p);
    }
    flatPackets.addAll(await enc2!.flush());
    final flatBytes = flatPackets.fold<int>(0, (a, p) => a + p.data.length);

    expect(gradientBytes, greaterThan(flatBytes * 3),
        reason: 'gradient=$gradientBytes B vs flat-grey=$flatBytes B — too '
            'close; the VideoProcessor blt is not transferring the picture');
  });

  test('repeatLastFrame duplicates without touching the source texture',
      () async {
    final enc = await MfVideoEncoder.open(const EncoderConfig(
      codec: VideoCodec.h264,
      width: _w,
      height: _h,
      bitrateBps: 2000000,
      frameRateNumerator: 30,
      frameRateDenominator: 1,
      gopLength: 30,
    ));
    expect(enc, isNotNull);
    addTearDown(() => enc!.close());

    // Nothing submitted yet: a repeat must decline rather than invent a frame.
    expect(await enc!.repeatLastFrame(0), isNull);

    if (!enc.supportsD3d11Input) {
      markTestSkipped('no D3D11 device bound (software MFT)');
      return;
    }
    // Submit one GPU frame, then DROP the source. A repeat tracks the surface
    // handed to the MFT, which for a GPU frame the encoder retains itself.
    final tex = mfencTestSharedBgraEx(_w, _h, 1, 1);
    expect(tex, isNot(nullptr));
    await enc.encode(D3D11TextureFrameSource(
      texturePtr: tex.address,
      width: _w,
      height: _h,
      pixelFormat: MiniAVPixelFormat.bgra32,
      timestampUs: 0,
    ));
    mfencTestTextureRelease(tex); // the producer is done with it

    // The point of the test: repeats keep working after the SOURCE is gone.
    // That is the idle-duplicator situation -- the producer has recycled its
    // surface and the encoder must still be able to fill the CFR slot.
    var got = 0;
    for (var i = 1; i <= 10; i++) {
      if (await enc.repeatLastFrame(i * 33333) != null) got++;
    }
    final out = await enc.flush();
    expect(got + out.length, greaterThanOrEqualTo(5),
        reason: 'repeatLastFrame produced almost nothing — idle CFR slots '
            'would go unfilled');
  });

  test('invalidateImports drops the cached sources and re-imports correctly',
      () async {
    // The import cache keys on the producer's TEXTURE POINTER. A pointer is not
    // an identity — free a texture and the next allocation can land on the same
    // address, which a resize or a rebuilt output ring makes routine — so a
    // stale hit would encode the previous picture forever while reporting
    // success at every step. The cache now holds a reference to each source,
    // which makes that impossible, and this is the entry point that lets the
    // producer say "those surfaces are gone" instead of pinning VRAM forever.
    final enc = await MfVideoEncoder.open(const EncoderConfig(
      codec: VideoCodec.h264,
      width: _w,
      height: _h,
      bitrateBps: 2000000,
      frameRateNumerator: 30,
      frameRateDenominator: 1,
      gopLength: 30,
    ));
    expect(enc, isNotNull);
    addTearDown(() => enc!.close());
    if (!enc!.supportsD3d11Input) {
      markTestSkipped('no D3D11 device bound');
      return;
    }

    final a = mfencTestSharedFmt(_w, _h, 1, 1, 1); // gradient, NT-shared RGBA
    final b = mfencTestSharedFmt(_w, _h, 0, 1, 1); // flat grey, same shape
    expect(a, isNot(nullptr));
    expect(b, isNot(nullptr));
    addTearDown(() => mfencTestTextureRelease(a));
    addTearDown(() => mfencTestTextureRelease(b));

    // Import + blt each source and read the NV12 staging luma back. This is the
    // only measurement that can tell "the cache returned the right texture"
    // from "packets came out either way".
    final sumA = mfencTestBltLumaSum(enc.nativeHandleForTest, a);
    final sumB = mfencTestBltLumaSum(enc.nativeHandleForTest, b);
    expect(sumA, greaterThan(0), reason: 'blt of A failed: ${enc.lastImportError}');
    expect(sumB, greaterThan(0), reason: 'blt of B failed: ${enc.lastImportError}');
    expect((sumA - sumB).abs(), greaterThan(_w * _h),
        reason: 'the two sources must be distinguishable through the blt, or '
            'this test cannot detect a stale cache hit at all');

    // Both are cached now, and each pins its source; invalidation releases
    // exactly those and leaves nothing behind.
    expect(enc.invalidateImports(), 2,
        reason: 'two producer textures were imported and pinned');
    expect(enc.invalidateImports(), 0,
        reason: 'a second invalidation has nothing left to release');

    // Re-import after the invalidation: each source must still yield ITS OWN
    // picture. A cache that handed back the previously imported texture would
    // return the other sum here.
    expect(mfencTestBltLumaSum(enc.nativeHandleForTest, b), sumB,
        reason: 're-imported B but got a different picture');
    expect(mfencTestBltLumaSum(enc.nativeHandleForTest, a), sumA,
        reason: 're-imported A but got a different picture');

    // And the encoder still encodes the new content end to end.
    enc.invalidateImports();
    final packets = <EncodedPacket>[];
    for (var i = 0; i < 10; i++) {
      final p = await enc.encode(D3D11TextureFrameSource(
        texturePtr: b.address,
        width: _w,
        height: _h,
        pixelFormat: MiniAVPixelFormat.rgba32,
        timestampUs: i * 33333,
      ));
      if (p != null) packets.add(p);
    }
    packets.addAll(await enc.flush());
    expect(packets, isNotEmpty,
        reason: 'encoding stopped working after an invalidation. NATIVE '
            'REASON: ${enc.lastImportError}');
  });

  test('the same session accepts NV12 after a texture frame', () async {
    // The VideoProcessor and its NV12 staging texture are built lazily and
    // reused; feeding a CPU frame afterwards must still work (the MFT input
    // type is NV12 either way).
    final enc = await MfVideoEncoder.open(const EncoderConfig(
      codec: VideoCodec.h264,
      width: _w,
      height: _h,
      bitrateBps: 2000000,
      frameRateNumerator: 30,
      frameRateDenominator: 1,
      gopLength: 30,
    ));
    expect(enc, isNotNull);
    addTearDown(() => enc!.close());
    if (!enc!.supportsD3d11Input) {
      markTestSkipped('no D3D11 device bound');
      return;
    }

    final tex = mfencTestSharedBgra(_w, _h, 1);
    expect(tex, isNot(nullptr));
    addTearDown(() => mfencTestTextureRelease(tex));

    await enc.encode(D3D11TextureFrameSource(
      texturePtr: tex.address,
      width: _w,
      height: _h,
      pixelFormat: MiniAVPixelFormat.bgra32,
    ));
    final nv12 = _nv12(_w, _h);
    await enc.encode(FrameSource.cpu(
      bytes: nv12,
      pixelFormat: MiniAVPixelFormat.nv12,
      width: _w,
      height: _h,
      timestampUs: 33333,
    ));
    final out = await enc.flush();
    expect(out, isNotEmpty, reason: 'mixed texture + NV12 input failed');
  });
}

Uint8List _nv12(int w, int h) {
  final y = w * h;
  final b = Uint8List(y + y ~/ 2);
  for (var i = 0; i < y; i++) {
    b[i] = (i ~/ w) & 0xFF;
  }
  b.fillRange(y, b.length, 128);
  return b;
}
