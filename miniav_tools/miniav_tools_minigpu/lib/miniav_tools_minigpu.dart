/// minigpu (WGSL compute) backend for miniav_tools.
///
/// Phase A: MJPEG encoder (the simplest GPU codec) — pure compute, no
///          entropy-coder serial dependencies beyond the per-MCU level.
/// Phase B: VP8/VP9-style intra-only "raw GPU" codec for screen capture.
/// Phase C: Custom video codec optimised for ML inference pipelines.
library;

export 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';
export 'src/minigpu_backend.dart' show MinigpuBackend;
export 'src/gpu_codec_pipeline.dart'
    show GpuCodecPipeline, GpuCodecEncoder, kFrameInputKey, kEncodedOutputKey;
export 'src/minigpu_mjpeg_pipeline.dart' show MinigpuMjpegPipeline;

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

import 'src/minigpu_backend.dart';

// ignore: unused_element
final _registered = registerMinigpuBackend();

bool registerMinigpuBackend() {
  final existing = MiniAVToolsPlatform.instance.backends.any(
    (b) => b.name == MinigpuBackend.backendName,
  );
  if (existing) return false;
  MiniAVToolsPlatform.instance.register(MinigpuBackend());
  return true;
}
