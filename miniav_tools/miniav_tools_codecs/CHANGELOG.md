# Changelog

## 0.6.8

- **ODD frame dimensions no longer break the D3D11 texture path.** NV12
  subsamples chroma 2x2, so a DXGI NV12 surface must have EVEN width and height;
  `CreateTexture2D` returns E_INVALIDARG otherwise. The staging ring was
  allocated at the exact frame size, so a capture like 2576x1119 (odd height --
  window sizes are arbitrary) failed to allocate, `mfenc_ensure_vp` bailed, and
  every texture frame was refused before the import was even attempted. The
  staging surface is now padded up to even; the blt writes only the real region
  via the stream rects and the MFT takes its frame size from the media type, so
  the spare row is never read. Covered by an odd-dimension test that reproduces
  the exact field signature when reverted.
- `MfVideoEncoder` accepts an `existingD3d11Device`, and `MfEncodeBackend`
  passes `BackendContext.d3d11DeviceHandle` into it. Encoding on the device the
  frames already live on removes the per-frame shared-handle import entirely --
  previously the encoder always built its own device via
  `D3D11CreateDevice(NULL, ...)`, i.e. on the DEFAULT adapter, so every GPU
  frame had to be exported and re-opened even in the common case.
- **New: `MfVideoEncoder.lastImportError`** — which step of the D3D11 texture
  import failed, and its HRESULT, now included in the thrown message. "could not
  import" covers a QueryInterface miss, a refused `CreateSharedHandle`, a
  cross-adapter `OpenSharedResource` and a rejected
  `CreateVideoProcessorInputView`; those have nothing in common except the
  symptom, and guessing between them from outside produced several confident
  wrong fixes in a row.
- The zero-copy test now covers both sharing modes (legacy / NT handle) AND both
  pixel formats (BGRA / RGBA, the latter being what the recorder's GPU processor
  actually produces). Each was a case where the test had been agreeing with the
  encoder rather than with real producers.

## 0.6.7

- **New: `MfVideoEncoder.repeatLastFrame(ptsUs)`** — re-encodes the surface most
  recently handed to the MFT under a new timestamp, without importing anything.
  This is what a duplicate/CFR-fill frame actually is, and expressing it by
  re-importing the producer's texture made it depend on a lifetime the producer
  owns: the idle timer fires exactly when that surface is most likely to have
  been recycled, and it fails outright in configurations where nothing is
  writing that texture at all. Returns null when there is nothing to repeat
  (nothing submitted yet, or the last frame was CPU-side), so the caller can
  simply skip the slot.

## 0.6.6

- **Fixes the D3D11 texture import against real GPU producers.** The importer
  only tried `IDXGIResource::GetSharedHandle`, the legacy sharing mode. A
  D3D12/Dawn-backed producer -- minigpu's shared output texture among them --
  publishes an NT handle from `IDXGIResource1::CreateSharedHandle`, for which
  the legacy call simply fails. Every frame was refused, and because the encoder
  skips a refused texture frame the result was a recording with NO VIDEO TRACK
  and no error anywhere. The import now resolves in three steps: same-device
  (no import at all), NT handle via `OpenSharedResource1`, then legacy.
- Sustained failure is no longer silent: 60 consecutive texture-import misses
  now throw, naming adapter mismatch as the likely cause. A single miss is still
  skipped, because the idle-frame duplicator legitimately re-submits a recycled
  texture -- but a run of them is a different fault and must not be quiet.
- TRAP for whoever touches this next: the zero-copy test built its source with
  legacy `MISC_SHARED`, so it agreed with the importer rather than with real
  producers and passed throughout. It now runs both sharing modes, and the
  NT-handle case was verified to FAIL when the new path is ablated.

## 0.6.5

- **MP4 assembly no longer multiplies memory.** The writer buffers every packet
  until `finish()` -- inherent to a whole-file builder -- but it was then
  copying that media three more times: once per payload into a sample list,
  again to concatenate `mdat`, and again to concatenate the final file. Peak was
  4.85x the media at 300 MB of payload; it is now 1.86x, which is the packets
  themselves plus VM overhead, with the muxer adding ~4 MB over simply holding
  them. Payloads needing no rewrite are referenced rather than copied, `mdat`
  offsets are summed instead of concatenated, and the container is emitted as
  ordered pieces via `Mp4Muxer.outputParts` so a file sink streams them.
  `getBytes()` is unchanged for callers that want one buffer -- it just costs
  the concatenation it always did. Measured by
  `benchmark/mp4_muxer_memory.dart`.
- This is a bound, not a licence: a whole-file builder still holds the whole
  file. It suits clips (bounded by the buffer window) and not open-ended
  recording, which streams through FFmpeg.

## 0.6.4

- **`FileMuxerOutput` now actually writes a file.** Every first-party muxer
  (WAV, Ogg, ADTS, MP4/M4A) is a whole-file builder that exposes its result
  through `getBytes()`, and all four ignored the output path completely --
  `writeHeader`/`writePacket`/`finish`/`close` each returned normally and
  nothing reached disk. A caller had no way to detect it and would report
  "saved" to the user. `ContainerFramingBackend.createMuxer` now wraps them so
  the bytes are written on `finish()`; web builds, which have no filesystem,
  raise instead of silently doing nothing. Covered by
  `test/muxer_file_output_test.dart`, which asserts against the filesystem
  rather than against return values.

## 0.6.3

- **Internal pins are now caret ranges, not exact versions.** Exact pins made
  every patch cascade: publishing `miniav_tools_platform_interface` 0.5.3 made
  the already-published `miniav_tools` 0.5.3 and `miniav_tools_ffmpeg` 0.5.3
  unsatisfiable next to it, because they pinned 0.5.2 exactly and nothing in the
  set could move independently. `dart pub publish` warns about this. `release.py
  sync` now normalises to caret so it cannot recur.

## 0.6.2

- **Fixes a broken 0.6.1.** The four native-assets build-hook dependencies
  (`code_assets`, `hooks`, `logging`, `native_toolchain_cmake`) were declared in
  `dev_dependencies`. Consumers do not receive a package's dev_dependencies, so
  `hook/build.dart` could not resolve its own imports and the native asset never
  built downstream — in-repo everything worked, because the dev deps are present
  there. `dart pub publish` reports this as an error; 0.6.1 shipped past it.
  0.6.1 is unusable as a dependency and should be skipped.

## 0.6.1

- **New: `registerFirstPartyBackends()`** — registers every backend in this
  package in one idempotent call. `miniav_recorder` calls it before negotiating
  an encoder, so recording apps now get the FFmpeg-free path (Media Foundation
  hardware H.264/HEVC, OS AAC, first-party MP4 framing) with no per-app setup.
  Registering does not force the outcome: capability is reported honestly and
  FFmpeg still wins where it is the better path. Pin or exclude explicitly with
  `BackendPreference.pinned` / `.excluded`.
- The README previously said this package "self-registers on import". It never
  did, and neither did any other: a top-level `final x = register();` in Dart is
  LAZY, so it runs on first read and nothing reads it. `registerMinigpuBackend`
  had been a no-op for every consumer that did not call it by hand. Covered by
  `test/auto_register_test.dart`, which asserts against the registry rather than
  against the declaration.

- **`Mp4Muxer` now accepts Annex-B H.264/HEVC.** Encoders emit Annex-B
  (start-code framed, parameter sets repeated in-band); MP4 needs an
  `avcC`/`hvcC` configuration record plus length-prefixed NAL samples. The muxer
  decides the framing once from the track's `extraData` — `0x01` means it is
  already a configuration record and is passed through untouched, so remuxing a
  demuxed file does not double-convert. Parameter-set NALs are stripped from the
  samples, which `hvc1` requires.
- New (exported): `isAnnexB`, `splitAnnexB`, `buildAvcC`, `buildHvcC`,
  `annexBToLengthPrefixed` in `src/framing/annexb.dart`. `buildHvcC` parses the
  HEVC SPS (profile_tier_level → chroma_format_idc → bit depths) after removing
  emulation-prevention bytes.
- **D3D11 zero-copy input works for both shapes.** `mfencSendD3d11Texture`
  takes a foreign-device RGBA/BGRA texture (the recorder's GPU processor
  output), imports it via `GetSharedHandle` + `OpenSharedResource`, and converts
  it to NV12 with a D3D11 VideoProcessor — entirely in VRAM. Together with the
  existing shared-NT-handle path this removes the readback from the recorder's
  scale/effects and direct-passthrough paths; `MfVideoEncoder` reports both
  `supportsD3d11TextureInput` and `supportsD3d11SharedHandleInput`.
  Verified by a DIFFERENTIAL test (`test/mf_texture_zero_copy_test.dart`):
  a gradient and a flat-grey source must encode to different sizes. An earlier
  revision produced byte-identical output for both — blank video, while
  reporting success at every step — so "it produced packets" is not a usable
  check here.
- **Fixed a tearing hazard in the D3D11 texture path.** The VideoProcessor
  converted into a single NV12 staging texture, but `ProcessInput` hands the MFT
  a sample that only *references* that surface, so the next frame's conversion
  could overwrite a picture the encoder was still reading. It is now a ring, and
  a slot is only reused once the MFT has released it (detected from the
  reference `MFCreateDXGISurfaceBuffer` holds, calibrated at construction rather
  than assumed). When every slot is in flight the encoder reports the same
  "drain and retry" it uses for `MF_E_NOTACCEPTING`, which is self-clearing.
- The texture path allocates nothing per frame: the imported source, its input
  view, the output views, the rects and the blt fence are all built once.
  `IDXGIKeyedMutex::AcquireSync` no longer waits `INFINITE` — a producer that
  never released would have hung the recording rather than dropped a frame.
  Measured cost of the whole path at 2560x1440 fed at 60 fps is 0.60 ms/frame
  mean, 0.91 ms p99 (`benchmark/mf_texture_bench.dart`); the caching itself is
  not where that comes from — ablating it moves nothing, so it is kept for the
  allocation churn rather than for the clock.
- `MfVideoEncoder.supportsD3d11Input` and `.isHardware` are cached. Both are
  fixed at session creation, and every native call is marshalled to the MTA
  worker thread, so re-answering them per frame spent a cross-thread round-trip
  on a constant.
- **MF encode now works on an STA thread — i.e. inside Flutter at all.** MF
  requires MTA; `CoInitializeEx(COINIT_MULTITHREADED)` fails with
  `RPC_E_CHANGED_MODE` on a thread already initialised STA, which Flutter's UI
  thread is. Every entry point therefore reported "no MFT" in any Flutter app
  (measured: `has_mft`=0, `list_hw`=-1) and the encoder silently lost every
  negotiation. `mf_encoder.c` now owns a dedicated MTA worker thread and
  marshals every public call onto it — chosen over an isolate host because
  D3D11 shared handles are process-wide and cross a thread hop for free, so
  zero-copy survives. Jobs run one at a time; concurrent *sessions* serialise.
  Pinned by `test/mf_sta_thread_test.dart`.
- **`MfEncodeBackend` is now the primary Windows H.264/HEVC encoder**: priority
  45 → 55, and it reports a *hardware* capability. It previously answered
  `false` to `supportsEncode(codec, hwAccel: true)`, so despite running on the
  OS hardware MFT it never advertised a hardware path — and `isHardware` outranks
  priority in the negotiator, so no priority bump alone could have promoted it.
  The hardware claim is gated on the OS actually listing a hardware MFT, so a
  software-only machine still ranks below a real hardware FFmpeg path.
- `MfVideoEncoder` accepts every frame source the backend advertises: CPU NV12
  and I420, `FrameSource.yuv420p`, and per-plane `miniavBufferCpu` (honouring
  each plane's stride). Previously anything but a packed `CpuFrameSource` NV12
  threw — including the D3D11 zero-copy branch's own fallback, which would have
  killed a recording rather than degrading to a readback.
- `MfEncodeBackend.hasHardwareMft` no longer caches a *failure to enumerate*.
  The hardware-MFT answer is per **apartment**, not per machine: MF needs MTA,
  and on an STA thread (Flutter's UI thread) `mfencListHw` returns -1. Caching
  that as "no hardware" poisoned the static cache for every later caller,
  including an MTA isolate where the same machine answers yes. Only a
  definitive result is cached now.
- `MfVideoEncoder` reports `supportsD3d11SharedHandleInput` (true whenever the
  D3D11 device manager bound) and `supportsD3d11TextureInput` = false: it opens
  a capture's shared NT handle on its own device, but cannot take the GPU
  processor's foreign-device RGBA texture. The recorder uses these to pick its
  screen zero-copy path. When the handle cannot be opened the encoder now throws
  a `CodecRuntimeException` naming the likely adapter mismatch — a GPU-resident
  buffer has no CPU pixels to fall back to, so the old path reported "needs CPU
  NV12", which named the symptom and hid the cause.
- `MfVideoEncoder.extraData` falls back to harvesting the parameter sets from
  the first keyframe when the MFT publishes no `MF_MT_MPEG_SEQUENCE_HEADER`
  (NVIDIA's do; this covers the vendors that don't). A null there would fail the
  track at mux time.

## 0.5.2

## 0.5.1

## 0.5.0

- Version bump to keep the miniav_tools family in lockstep; no changes in this package.

## 0.4.10

## 0.4.9

- Increment to keep in step with others.

## 0.4.8

- Increment to keep in step with others.

## 0.4.7

- Increment to keep in step with others.

## 0.4.6

- Increment to keep in step with others.

## 0.4.5

- Version bump for coordinated release with `miniav_recorder` 0.4.5
  (`Recorder.sharedGpu` getter, `GpuScreenProcessor` public export).

## 0.4.4

- fixing recorder loopback drift

## 0.4.3

- audio data issue, increment miniav

## 0.4.2

- fix timing issue

## 0.4.1

- fix audio timing, add frame duplication

## 0.4.0

- fix frame rate scheduling

## 0.3.12

- fused shader cache fix

## 0.3.11

- Use GPU until we cant.

## 0.3.9

- AMF Fix, fix unknown audio error

## 0.3.8

- Fix vendor Order

## 0.3.7

- fix NV12 path

## 0.3.6

- fix cpu path

## 0.3.5

- fix recorder sync drift

## 0.3.4

- attempt fix resolution issue

## 0.3.3

- fix precheck

## 0.3.2

- fix property

## 0.3.1

- fix scaling crazy, attempt fix other HW encoders

## 0.3.0

- fix recorder logging, Tier A path, deps to 1.5.0

## 0.2.21

- increments minigpu to 1.4.15

## 0.2.20

- increments minigpu to 1.4.14

## 0.2.19

- increments minigpu to 1.4.12

## 0.2.18

- increments minigpu to 1.4.11

## 0.2.17

- increments minigpu to 1.4.9

## 0.2.16

- increments minigpu to 1.4.8, hopefully fix cpu fallback

## 0.2.15

- increments minigpu to 1.4.7

## 0.2.14

- fixes unicode, increments minigpu to 1.4.7

## 0.2.12

- Increment minigpu to 1.4.6

## 0.2.11

## 0.2.9

## 0.2.8

- add RecorderLogSource.minigpu: routes native minigpu/Dawn log lines through the unified Recorder log callback; Recorder.minigpuLevelFor public helper for tests; 12 new tests in log_level_test.dart

## 0.2.7

- fix FormatException on non-UTF-8 bytes in MiniAV log callback: use Utf8Decoder(allowMalformed: true) instead of toDartString()
- Increment minigpu to 1.4.4

## 0.2.5

## 0.2.4

## 0.2.3

## 0.2.2-WIP

- add unified Recorder.setLogLevel and Recorder.setLogCallback routing all native logs (MiniAV + FFmpeg) through a single Dart callback

## 0.2.1

- fixes dawn find issue

## 0.2.0

- add more quality control, fix ffmpeg usage issue

## 0.1.9

- fixes timestamp issues

## 0.1.8

- recorder scaling, warmup feature

## 0.1.7

- adds transform effects

## 0.1.6

- adds clip buffer

## 0.1.5

- fix loopback issue

## 0.1.4

- fix loopback issue, add tests

## 0.1.3

- update with fixes

## 0.1.2

- recorder sync and multi files

## 0.1.1

- updated to latest miniav/minigpu deps

## 0.1.0

- Initial release. Pure-WGSL codec backend for `miniav_tools` running entirely
  on minigpu's WebGPU compute pipeline.
- MJPEG encoder: RGBA → YCbCr → DCT → quantize → Huffman → JFIF emitted as a
  self-contained `.jpg` byte stream (plays in browsers, VLC, QuickTime,
  ffmpeg). No native FFmpeg dependency — works anywhere minigpu works,
  including web (WebGPU).
- `crfQuality` 1..31 maps to JPEG quality 90..10 for parity with FFmpeg's
  `-q:v` semantics.
