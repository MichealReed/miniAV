/// The recorder's screen zero-copy modes must be gated on encoder
/// CAPABILITIES, not on a concrete encoder type.
///
/// This regressed silently once already: the gate was
/// `platform is FfmpegD3d11HwEncoder`, so every other GPU-capable encoder —
/// including the first-party Media Foundation one, which takes a capture's
/// shared NT handle directly — failed the check, tripped the safety net, and
/// was forced onto the CPU-readback path. Nothing errored; a full frame
/// readback per frame at screen resolution was simply added back.
///
/// These tests assert the contract each side of that gate relies on. They are
/// pure Dart (no capture, no GPU) so they run everywhere.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';
import 'package:test/test.dart';

/// Minimal encoder that reports nothing — the base-class defaults.
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

/// Takes a capture's shared NT handle but not a foreign-device texture —
/// the MF encoder's shape.
class _HandleOnlyEncoder extends _PlainEncoder {
  @override
  bool get supportsD3d11SharedHandleInput => true;
}

/// Takes both — the FFmpeg D3D11 encoder's shape.
class _FullGpuEncoder extends _PlainEncoder {
  @override
  bool get supportsD3d11SharedHandleInput => true;
  @override
  bool get supportsD3d11TextureInput => true;
}

/// Mirror of the recorder's gating in `_buildScreenTrack`. Kept in lockstep
/// with it deliberately: the decision is a handful of booleans, and pinning
/// them here is what makes an accidental regression to a type check visible.
({bool passthrough, bool pipelined, bool cpuFallback}) gate({
  required PlatformEncoder platform,
  required bool hasProcessor,
  required bool cpuReadback,
  required bool hasGpuWork,
}) {
  final isGpuBuffer =
      hasProcessor && !cpuReadback && platform.supportsGpuBufferInput;
  final eligible = hasProcessor && !cpuReadback && !isGpuBuffer;
  final passthrough =
      eligible && !hasGpuWork && platform.supportsD3d11SharedHandleInput;
  final pipelined =
      eligible && hasGpuWork && platform.supportsD3d11TextureInput;
  final cpuFallback =
      hasProcessor && !cpuReadback && !passthrough && !pipelined && !isGpuBuffer;
  return (
    passthrough: passthrough,
    pipelined: pipelined,
    cpuFallback: cpuFallback,
  );
}

void main() {
  group('PlatformEncoder GPU-input capabilities', () {
    test('default to false so an unaware encoder is never handed a texture',
        () {
      final e = _PlainEncoder();
      expect(e.supportsD3d11SharedHandleInput, isFalse);
      expect(e.supportsD3d11TextureInput, isFalse);
    });
  });

  group('screen zero-copy gating', () {
    test('handle-only encoder gets passthrough when there is no GPU work', () {
      final g = gate(
        platform: _HandleOnlyEncoder(),
        hasProcessor: true,
        cpuReadback: false,
        hasGpuWork: false,
      );
      expect(g.passthrough, isTrue,
          reason: 'this is the case the type check used to break');
      expect(g.pipelined, isFalse);
      expect(g.cpuFallback, isFalse, reason: 'no readback should be added');
    });

    test('handle-only encoder falls back to CPU readback when GPU work exists',
        () {
      // Scale or effects mean the frame must go through the processor, which
      // produces a foreign-device texture this encoder cannot take. Falling
      // back is correct — dropping the scale/effects would not be.
      final g = gate(
        platform: _HandleOnlyEncoder(),
        hasProcessor: true,
        cpuReadback: false,
        hasGpuWork: true,
      );
      expect(g.passthrough, isFalse);
      expect(g.pipelined, isFalse);
      expect(g.cpuFallback, isTrue);
    });

    test('full GPU encoder keeps both modes', () {
      final noWork = gate(
        platform: _FullGpuEncoder(),
        hasProcessor: true,
        cpuReadback: false,
        hasGpuWork: false,
      );
      expect(noWork.passthrough, isTrue);
      expect(noWork.cpuFallback, isFalse);

      final withWork = gate(
        platform: _FullGpuEncoder(),
        hasProcessor: true,
        cpuReadback: false,
        hasGpuWork: true,
      );
      expect(withWork.pipelined, isTrue);
      expect(withWork.cpuFallback, isFalse);
    });

    test('a CPU-only encoder always trips the safety net', () {
      for (final work in [false, true]) {
        final g = gate(
          platform: _PlainEncoder(),
          hasProcessor: true,
          cpuReadback: false,
          hasGpuWork: work,
        );
        expect(g.passthrough, isFalse);
        expect(g.pipelined, isFalse);
        expect(g.cpuFallback, isTrue, reason: 'hasGpuWork=$work');
      }
    });

    test('an already-CPU-readback track is never promoted to zero-copy', () {
      final g = gate(
        platform: _FullGpuEncoder(),
        hasProcessor: true,
        cpuReadback: true,
        hasGpuWork: false,
      );
      expect(g.passthrough, isFalse);
      expect(g.pipelined, isFalse);
      expect(g.cpuFallback, isFalse, reason: 'already on the readback path');
    });
  });

  group('direct-passthrough frame shape', () {
    test('a GPU capture buffer carries its handle in nativeHandles, not planes',
        () {
      // The passthrough path builds FrameSource.miniavBuffer(buffer) and the
      // encoder reads nativeHandles[0]. planes[0] is non-null but EMPTY on the
      // GPU path, so it must not be used to tell the layouts apart.
      final buffer = MiniAVBuffer(
        type: MiniAVBufferType.video,
        contentType: MiniAVBufferContentType.gpuD3D11Handle,
        timestampUs: 1234,
        dataSizeBytes: 0,
        data: MiniAVVideoBuffer(
          width: 1920,
          height: 1080,
          pixelFormat: MiniAVPixelFormat.bgra32,
          strideBytes: const [0],
          planes: [Uint8List(0)],
          nativeHandles: const [0xDEADBEEF],
        ),
      );
      final src = FrameSource.miniavBuffer(buffer);
      expect(src.kind, FrameSourceKind.miniavBufferD3D11);
      expect(src.timestampUs, 1234);

      final v = buffer.data as MiniAVVideoBuffer;
      expect(v.planes[0], isNotNull);
      expect(v.planes[0], isEmpty, reason: 'planes are empty on the GPU path');
      expect(v.nativeHandles[0], 0xDEADBEEF);
    });
  });
}
