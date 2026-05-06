/// Universal GPU codec pipeline abstraction.
///
/// Wraps `gpu_pipeline.Pipeline` so that a *codec* (MJPEG, future MotionJPEG-2K,
/// future GPU-driven WebP-lite, future NVENC bridge, …) is expressed as a
/// **stage graph** rather than a bespoke `PlatformEncoder` implementation.
///
/// ## Contract
///
/// A subclass of [GpuCodecPipeline] must:
///
/// 1. Build a `gpu_pipeline.Pipeline` whose first stage takes a single tensor
///    input named [kFrameInputKey] holding **interleaved RGBA bytes uploaded
///    as Float32** values in `[0, 255]`, with shape `[H, W, 4]`.
/// 2. Produce a final stage output tensor named [kEncodedOutputKey] with
///    `BufferDataType.uint8` and shape `[N]` — the encoded bitstream for
///    that frame.
/// 3. Override [isKeyframe] to declare per-packet keyframe status. (For
///    intra-only codecs like MJPEG this is always `true`.)
/// 4. Optionally override [extraData] (codec-private bytes for muxers).
///
/// The [GpuCodecEncoder] adapter wraps any [GpuCodecPipeline] into a
/// `PlatformEncoder`, handling frame-source dispatch, pts management, and
/// EncodedPacket construction. Adding a new codec is a single new subclass —
/// no new `PlatformEncoder` boilerplate.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:gpu_pipeline/gpu_pipeline.dart';
import 'package:gpu_tensor/gpu_tensor.dart';
import 'package:miniav_platform_interface/miniav_platform_interface.dart'
    show MiniAVPixelFormat, MiniAVVideoBuffer;
import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';
import 'package:minigpu_platform_interface/minigpu_platform_interface.dart'
    show BufferDataType;

/// Tensor key the abstraction expects on the input stage.
const String kFrameInputKey = 'frame';

/// Tensor key the abstraction expects on the terminal stage.
const String kEncodedOutputKey = 'encoded';

/// Subclasses define a stage graph that turns one RGBA frame into an encoded
/// byte stream. Lifecycle is owned by [GpuCodecEncoder].
abstract class GpuCodecPipeline {
  GpuCodecPipeline({required this.config});

  /// Encoder configuration this pipeline was built for. Subclasses use this
  /// to size buffers, pick quantization tables, etc.
  final EncoderConfig config;

  /// Lazily-built underlying pipeline.
  Pipeline? _pipeline;
  Future<void>? _building;

  /// Subclass hook: build the gpu_pipeline.Pipeline. Called exactly once
  /// (lazily, on first encode). Implementations:
  ///   - call [Pipeline] constructor
  ///   - add stages whose first input port is [kFrameInputKey]
  ///   - whose final output port is [kEncodedOutputKey] (uint8 tensor)
  ///   - call `await pipeline.start()` themselves if needed
  Future<Pipeline> buildPipeline();

  /// Per-packet keyframe flag (defaults to `true`: most GPU-friendly codecs
  /// here are intra-only).
  bool isKeyframe(int frameIndex) => true;

  /// Codec-private extras (e.g. JFIF tail bytes for MJPEG; SPS/PPS for
  /// future GPU H.264). Default: none.
  CodecExtraData? get extraData => null;

  /// Internal: lazily start the underlying pipeline.
  Future<Pipeline> _ensure() async {
    if (_pipeline != null) return _pipeline!;
    _building ??= () async {
      final p = await buildPipeline();
      _pipeline = p;
    }();
    await _building;
    return _pipeline!;
  }

  /// Run one frame through the pipeline. Returns the encoded byte stream
  /// for that frame, or `null` if the pipeline buffered (rare for intra
  /// codecs; reserved for future GPU codecs with lookahead).
  Future<Uint8List?> _runOneFrame(Tensor<Float32List> input) async {
    final p = await _ensure();
    final outputs = await p.runOnce({kFrameInputKey: input});
    final encoded = outputs[kEncodedOutputKey];
    if (encoded == null) {
      throw CodecRuntimeException(
        'minigpu',
        'pipeline produced no "$kEncodedOutputKey" output (saw '
            '${outputs.keys.toList()})',
      );
    }
    final bytes = await encoded.getData();
    // The pipeline's CPU stage uploads outputs as Float32 tensors (one float
    // per byte), so we materialise them back to a tight Uint8List here.
    if (bytes is Float32List) {
      final out = Uint8List(bytes.length);
      for (var i = 0; i < bytes.length; i++) {
        final v = bytes[i];
        out[i] = v <= 0 ? 0 : (v >= 255 ? 255 : v.round());
      }
      return out;
    } else if (bytes is Uint8List) {
      return Uint8List(bytes.length)..setAll(0, bytes);
    } else {
      throw CodecRuntimeException(
        'minigpu',
        'pipeline produced unsupported encoded type ${bytes.runtimeType}',
      );
    }
  }

  /// Drain any internally buffered packets at end-of-stream. Default: none
  /// (intra-only codec).
  Future<List<Uint8List>> _flushFrames() async => const [];

  /// Release the underlying pipeline + GPU resources.
  Future<void> _close() async {
    final p = _pipeline;
    _pipeline = null;
    if (p != null) {
      await p.stop();
    }
  }
}

/// Adapter: turns any [GpuCodecPipeline] into a [PlatformEncoder].
///
/// Backends construct one of these per `createEncoder()` call:
/// ```dart
/// return GpuCodecEncoder(MinigpuMjpegPipeline(config));
/// ```
class GpuCodecEncoder implements PlatformEncoder {
  GpuCodecEncoder(this._pipeline);

  final GpuCodecPipeline _pipeline;
  bool _closed = false;
  int _frameIndex = 0;
  int _nextFrameIndexForFlush = 0;

  EncoderConfig get _cfg => _pipeline.config;

  @override
  CodecExtraData? get extraData => _pipeline.extraData;

  @override
  Future<void> requestKeyframe() async {
    /* intra-only by default */
  }

  @override
  Future<EncodedPacket?> encode(FrameSource frame) async {
    _checkOpen();
    final rgba = _frameToRgba(frame);
    final input = await Tensor.create<Float32List>([
      _cfg.height,
      _cfg.width,
      4,
    ], dataType: BufferDataType.float32);
    try {
      final asFloat = Float32List(rgba.length);
      for (var i = 0; i < rgba.length; i++) {
        asFloat[i] = rgba[i].toDouble();
      }
      await input.write(asFloat);
      final bytes = await _pipeline._runOneFrame(input);
      if (bytes == null) return null;
      final pts = _ptsForFrame(_frameIndex, frame.timestampUs);
      final pkt = EncodedPacket(
        data: bytes,
        ptsUs: pts,
        dtsUs: pts,
        durationUs: _frameDurationUs,
        isKeyframe: _pipeline.isKeyframe(_frameIndex),
      );
      _frameIndex++;
      return pkt;
    } finally {
      input.destroy();
    }
  }

  @override
  Future<List<EncodedPacket>> flush() async {
    _checkOpen();
    final frames = await _pipeline._flushFrames();
    final out = <EncodedPacket>[];
    for (final bytes in frames) {
      final i = _nextFrameIndexForFlush++;
      final pts = _ptsForFrame(i, null);
      out.add(
        EncodedPacket(
          data: bytes,
          ptsUs: pts,
          dtsUs: pts,
          durationUs: _frameDurationUs,
          isKeyframe: _pipeline.isKeyframe(i),
        ),
      );
    }
    return out;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _pipeline._close();
  }

  // --- helpers -------------------------------------------------------------

  void _checkOpen() {
    if (_closed) {
      throw const CodecRuntimeException('minigpu', 'encoder closed');
    }
  }

  int get _frameDurationUs =>
      (1000000 * _cfg.frameRateDenominator) ~/ _cfg.frameRateNumerator;

  int _ptsForFrame(int frameIndex, int? sourceTsUs) {
    if (sourceTsUs != null && sourceTsUs > 0) return sourceTsUs;
    return frameIndex * _frameDurationUs;
  }

  /// Always materialise an RGBA byte buffer of size `width*height*4` for
  /// the GPU upload. Pixel format conversion lives here so subclasses can
  /// rely on a uniform input layout.
  Uint8List _frameToRgba(FrameSource src) {
    switch (src) {
      case CpuFrameSource():
        return _convertToRgba(
          bytes: src.bytes,
          format: src.pixelFormat,
          width: src.width,
          height: src.height,
        );
      case MiniAVBufferSource():
        final buf = src.buffer.data;
        if (buf is! MiniAVVideoBuffer) {
          throw const CodecRuntimeException(
            'minigpu',
            'GpuCodecEncoder expects video buffers',
          );
        }
        final plane0 = buf.planes.isNotEmpty ? buf.planes[0] : null;
        if (plane0 == null) {
          throw const CodecRuntimeException(
            'minigpu',
            'GpuCodecEncoder MVP only accepts CPU-backed MiniAV buffers '
                '(plane[0] was null — likely a GPU buffer; zero-copy import '
                'is a follow-up)',
          );
        }
        return _convertToRgba(
          bytes: plane0,
          format: buf.pixelFormat,
          width: buf.width,
          height: buf.height,
        );
      default:
        throw CodecRuntimeException(
          'minigpu',
          'Unsupported FrameSource: ${src.runtimeType}',
        );
    }
  }
}

/// Convert any of the supported MiniAV pixel formats to interleaved RGBA8.
/// Kept private to this file — codecs share one canonical input layout.
Uint8List _convertToRgba({
  required Uint8List bytes,
  required MiniAVPixelFormat format,
  required int width,
  required int height,
}) {
  final n = width * height;
  final out = Uint8List(n * 4);
  switch (format) {
    case MiniAVPixelFormat.rgba32:
      out.setRange(0, n * 4, bytes);
      return out;
    case MiniAVPixelFormat.bgra32:
      for (var i = 0; i < n; i++) {
        out[i * 4 + 0] = bytes[i * 4 + 2];
        out[i * 4 + 1] = bytes[i * 4 + 1];
        out[i * 4 + 2] = bytes[i * 4 + 0];
        out[i * 4 + 3] = bytes[i * 4 + 3];
      }
      return out;
    case MiniAVPixelFormat.rgb24:
      for (var i = 0; i < n; i++) {
        out[i * 4 + 0] = bytes[i * 3 + 0];
        out[i * 4 + 1] = bytes[i * 3 + 1];
        out[i * 4 + 2] = bytes[i * 3 + 2];
        out[i * 4 + 3] = 0xff;
      }
      return out;
    case MiniAVPixelFormat.bgr24:
      for (var i = 0; i < n; i++) {
        out[i * 4 + 0] = bytes[i * 3 + 2];
        out[i * 4 + 1] = bytes[i * 3 + 1];
        out[i * 4 + 2] = bytes[i * 3 + 0];
        out[i * 4 + 3] = 0xff;
      }
      return out;
    default:
      throw CodecRuntimeException(
        'minigpu',
        'GpuCodecEncoder: pixel format $format not supported by the '
            'shared RGBA upload path',
      );
  }
}
