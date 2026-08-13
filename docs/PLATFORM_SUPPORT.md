# Platform support

Canonical, evidence-based statement of what miniAV and miniav_tools actually do
per platform. Written 2026-08-02 from a four-part audit of the capture layer,
the codec/backend layer, the player and the recorder.

**This document exists because pub.dev was advertising five platforms that
nobody had ever asserted.** No pubspec in either repo declared a `platforms:`
key, so pub.dev *inferred* android/ios/linux/macos/windows from static analysis
— which only ever meant "nothing in the Dart code forbids it". Four of those
five had never been compiled by CI, let alone run.

## How to read this

| Status | Meaning |
|---|---|
| **VERIFIED** | A test or a recorded real-hardware run proves it works on that platform |
| **IMPLEMENTED** | Code exists and plausibly runs. Nothing proves it |
| **FALLBACK** | Works only through FFmpeg or another degraded path. The cost is stated |
| **PARTIAL** | Works with a specific documented gap |
| **STUB** | Code exists but no-ops, returns not-supported, or silently does nothing |
| **ABSENT** | No code path |

Two rules used throughout, because both are easy to get wrong:

- **Compiling is not working.** A cross-compile job that configures and builds
  a native library proves the sources parse and link for that triple. It proves
  nothing about runtime behaviour.
- **A test that always skips is not coverage.** A suite listed in CI that
  unconditionally `markTestSkipped`s on the runner records a green check and
  zero information.

## What CI proves today

Stated plainly, because the answer is smaller than it looks:

- **Windows** — the Dart suites run (`miniav_tools_codecs`, `miniav_recorder`).
  The hardware-dependent parts (Media Foundation MFTs, Dawn/GPU) *skip* on the
  runner, so they are green only on a developer machine with the hardware.
- **Linux** — pure-Dart suites only (`miniav_tools_platform_interface`,
  `miniav_tools` with fake backends). No native code is exercised.
- **macOS** — nothing. There is no macOS job in `dart-ci.yml` at all.
- **Android / iOS** — nothing at runtime.
- **`miniav_ffi/test/*`, the actual capture suite, is not referenced by any CI
  job on any platform.**
- **`miniav_player` has no CI test job at all** — its job is commented out in
  `dart-ci.yml`, so all nine of its suites are dead to CI.

`native-build.yml` cross-compiles `miniav_c` for all five platforms. As of
2026-08-02 it had run twice and **both runs failed at `actions/checkout`**
before configuring anything (a committed-symlink corruption, since fixed at
HEAD but never re-triggered because the fixing commit touched no
`miniav_ffi/miniav_c/**` path). **No green native-build run has ever existed.**
Any "supported" claim for macOS/Linux/Android/iOS rests on review, not
execution, until that changes.

## Capture layer — `miniav` / `miniav_ffi`

| Module | Windows | macOS | Linux | Android | iOS |
|---|---|---|---|---|---|
| Camera | **VERIFIED** (Media Foundation, D3D11 shared handle) | IMPLEMENTED (AVFoundation + Metal) | IMPLEMENTED (PipeWire + DMA-BUF) | IMPLEMENTED (Camera2 NDK) | IMPLEMENTED (AVFoundation) |
| Screen — display | **VERIFIED** (WGC + DXGI) | IMPLEMENTED (ScreenCaptureKit 12.3+) | IMPLEMENTED (PipeWire + portal) | IMPLEMENTED (MediaProjection) | IMPLEMENTED (ReplayKit) |
| Screen — window | **VERIFIED** (WGC) | **ABSENT** (returns not-supported; enumerates zero windows) | PARTIAL (portal picker; `window_id` is never sent to the portal) | ABSENT | ABSENT |
| Screen — region | ABSENT (declines honestly) | IMPLEMENTED (`SCStreamConfiguration.sourceRect`) | **STUB** (accepts, warns, does not crop, returns success) | ABSENT | ABSENT |
| Loopback / system audio | **VERIFIED** (WASAPI; per-PID **VERIFIED** on Win10 20348+, fails closed below) | IMPLEMENTED (taps 14.2+ → SCK 13+ → virtual device) | IMPLEMENTED (PipeWire) | **ABSENT** (not compiled) | **ABSENT** (not compiled) |
| Microphone | **VERIFIED** (miniaudio) | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED |
| Audio output | **VERIFIED** | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED |
| Input capture | IMPLEMENTED (LL hooks + XInput; no automated test) | IMPLEMENTED (CGEventTap) | IMPLEMENTED (evdev) | ABSENT | ABSENT |
| Motion / IMU | n/a | n/a | n/a | IMPLEMENTED but **unreachable from Dart** | IMPLEMENTED but **unreachable from Dart** |
| Inject | **VERIFIED** (SendInput) | IMPLEMENTED (CGEventPost) | IMPLEMENTED (uinput) | **ABSENT** (not compiled) | **ABSENT** (not compiled) |

The only running evidence for this entire layer is `dart test` in `miniav_ffi`
on a Windows development machine with real devices attached.

## Codec / backend layer — `miniav_tools_codecs`, `miniav_tools_ffmpeg`

The decisive constraint is not the codecs package, whose native asset is
genuinely portable (one source list for every platform, with `#if
defined(_WIN32)` guards *inside* the Windows-only translation units). It is
FFmpeg:

> **The `miniav_tools_ffmpeg` shim is built only when the FFmpeg auto-download
> succeeds, and that download exists only for Windows-x64 and Linux-x64.**
> Every FFmpeg decoder, encoder, muxer, demuxer and audio codec hard-requires
> that shim. On macOS, Android and iOS the FFmpeg backend is therefore
> unusable — **including after `brew install ffmpeg`**, because the libraries
> loading does not cause the shim to be built.

| Capability | Windows | Linux x64 | macOS | Android | iOS | Web |
|---|---|---|---|---|---|---|
| H.264 decode | MF hardware → D3D11 zero-copy; FFmpeg SW | FALLBACK (FFmpeg SW) | **ABSENT** | **ABSENT** | **ABSENT** | IMPLEMENTED (WebCodecs) |
| HEVC decode | MF hardware; FFmpeg SW | FALLBACK | **ABSENT** | **ABSENT** | **ABSENT** | IMPLEMENTED |
| H.264 encode | MF hardware MFT (FFmpeg-free) | FALLBACK (NVENC/QSV/v4l2m2m, or libopenh264) | **ABSENT** | **ABSENT** | **ABSENT** | IMPLEMENTED |
| HEVC encode | MF MFT | FALLBACK (hardware only — no SW HEVC in an LGPL build) | **ABSENT** | **ABSENT** | **ABSENT** | IMPLEMENTED |
| AAC decode / encode | MF AAC | FALLBACK | **ABSENT** | **ABSENT** | **ABSENT** | IMPLEMENTED |
| Opus | **VERIFIED** (libopus) | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED (wasm) |
| MP3 decode | **VERIFIED** (dr_mp3) | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED |
| FLAC / Vorbis decode | FALLBACK (FFmpeg, by design) | FALLBACK | **ABSENT** | **ABSENT** | **ABSENT** | IMPLEMENTED |
| PCM / WAV | **VERIFIED** | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED | PARTIAL (framing yes, PCM codec not registered) |
| MP4 mux / demux (bytes) | **VERIFIED** (pure Dart) | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED |
| MKV / WebM / fMP4 / TS | FALLBACK | FALLBACK | **ABSENT** | **ABSENT** | **ABSENT** | **ABSENT** |
| Colour conversion | **VERIFIED** (C + WGSL + Dart) | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED |

**File paths always need FFmpeg.** The first-party demuxers accept in-memory
bytes only (`container_backend.dart`: `if (input is! BytesDemuxerInput) return
null;`). A `MediaSource.file(...)` therefore routes to FFmpeg on every
platform, including Windows — which is why file playback fails on macOS even
though "MP4 demux without FFmpeg" is true in the bytes case.

FFmpeg obtainability, precisely:

| Target | Result |
|---|---|
| Windows x64 | Auto-downloads (LGPL build, ~92 MB, cached) |
| Linux x64 | Auto-downloads (LGPL build) |
| Windows ARM64 / Linux ARM64 | **Downloads the x86-64 archive**, which then fails to load. No architecture detection exists |
| macOS | No artifact. Returns null; the shim is never built |
| Android / iOS | No artifact, no bundling mechanism. iOS additionally forbids `dlopen` of downloaded code |

The LGPL constraint is correctly honoured: the pinned build is LGPL, the cache
directory is namespaced by licence so flipping it cannot silently reuse a GPL
install, and no `libx264`/`libx265`/`libfdk-aac` is linked anywhere. The
practical consequence is that **software HEVC encode does not exist** and is
transparently substituted with H.264.

## `miniav_player`

| Pillar | Windows | Linux | macOS | Android / iOS | Web |
|---|---|---|---|---|---|
| Video decode | **VERIFIED** (MF hardware) | FALLBACK (FFmpeg SW) | **ABSENT** | **ABSENT** | IMPLEMENTED |
| Audio decode | **VERIFIED** | opus/mp3/pcm IMPLEMENTED; aac/flac/vorbis FALLBACK | opus/mp3/pcm only | **ABSENT** | IMPLEMENTED |
| Presentation | **VERIFIED** (zero-copy) | FALLBACK (CPU convert + upload) | FALLBACK | FALLBACK | IMPLEMENTED |
| Audio output | **VERIFIED** (WASAPI) | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED |
| `MediaSource.bytes` | **VERIFIED** | IMPLEMENTED | PARTIAL (audio-only) | ABSENT | IMPLEMENTED |
| `MediaSource.file` | **VERIFIED** | IMPLEMENTED | **ABSENT** (needs the shim) | ABSENT | ABSENT (no `dart:io`) |

The honest macOS feature set is **audio-only playback of WAV / MP3 / Opus /
Ogg via `MediaSource.bytes`** — first-party demux, first-party decode,
miniaudio output. Everything else needs the shim.

The player's web path is more complete than its macOS, Android and iOS paths
combined, and is the one platform pub.dev does *not* advertise — blocked by an
unconditional `miniav_tools_ffmpeg` dependency that the web build never
imports.

## `miniav_recorder`

| Pillar | Windows | Linux | macOS | Android / iOS |
|---|---|---|---|---|
| Screen capture | **VERIFIED** | IMPLEMENTED | IMPLEMENTED | see caveats |
| Window capture | **VERIFIED** | PARTIAL | **ABSENT** | ABSENT |
| Camera / microphone | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED (no permission handling) |
| Loopback audio | **VERIFIED** | IMPLEMENTED | IMPLEMENTED | **ABSENT** |
| Video encode | **VERIFIED** (hardware) | FALLBACK | **ABSENT** | **ABSENT** |
| AAC audio encode (the default) | **VERIFIED** | FALLBACK | **ABSENT** | **ABSENT** |
| Opus / PCM audio encode | **VERIFIED** | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED |
| Mux mp4 / m4a / wav / aac | **VERIFIED** (pure Dart) | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED |
| Mux mkv | **VERIFIED** | FALLBACK | **ABSENT** | **ABSENT** |
| Zero-copy GPU path | **VERIFIED** | ABSENT | ABSENT | ABSENT |

`addMic()` defaults to AAC, and OS AAC is Windows-only
(`registerAacBackend()` opens with `if (!Platform.isWindows) return false`), so
the **default recording configuration has no first-party audio encoder anywhere
except Windows** and falls to FFmpeg.

Neither package can be used on web: both import `dart:ffi` and `dart:io`
unconditionally. pub.dev is correct to omit the web tag for them.

## Per-platform caveats worth stating in package docs

**Windows**
- Loopback reports the **negotiated** format: WASAPI shared-mode loopback always
  runs at the endpoint mix format, so `getConfiguredFormat()` and the `info` on
  delivered buffers describe the mix format, not whatever was requested. A
  request the endpoint cannot provide is logged, not honoured. *(Fixed in
  `miniav_ffi` 0.7.1 — it previously reported the request, silently mislabelling
  PCM on any non-48 kHz / non-stereo endpoint.)*
- A per-process audio target (`pid:<id>`, used by window capture) is now really
  scoped to that process, via `ActivateAudioInterfaceAsync` against
  `VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK` (include-process-tree). Needs
  **Windows 10 build 20348 / Windows 11**. *(Fixed in `miniav_ffi` 0.7.1. It
  previously passed the PID to `IAudioClient3::InitializeSharedAudioStream`
  where the API expects `PeriodInFrames`; that always failed with
  `AUDCLNT_E_INVALID_DEVICE_PERIOD` and the backend silently substituted
  whole-system audio, so per-process capture had never worked and no caller
  could tell.)*
- Per-process capture that cannot be delivered — unsupported Windows build,
  activation failure, or a PID that is not running — **fails
  `Loopback.configure`** rather than substituting the whole system's audio.
  Setting `MINIAV_LOOPBACK_ALLOW_SYSTEM_FALLBACK=1` re-enables the
  substitution; it is then logged at ERROR and reported by
  `MiniAV_Loopback_GetActiveTargetInfo`, which tells a caller which scope is
  actually in effect (C API only — not exposed through the Dart bindings).
- Per-process loopback picks up the target's stream **before the endpoint
  master volume**, so it is typically louder than the same audio seen through
  whole-system loopback. It also *negotiates*: unlike endpoint loopback, the
  requested sample rate / channel count / sample format is honoured and
  converted into (48 kHz, 44.1 kHz and 16 kHz all verified on one target).
- Screen capture with `captureAudio: true` **fails** rather than degrading to
  video only if no audio path can be established *(behaviour change in 0.7.1;
  window capture with audio previously returned success and delivered video
  only, every time)*.
- Region capture is declined honestly (not supported).

**Linux**
- Requires a ~92 MB FFmpeg download on first build; offline or firewalled
  builds silently produce no video codec at all.
- x86-64 only. ARM64 downloads the wrong archive.
- Screen capture never fires `lost_cb` — revoking the screencast from the
  compositor is invisible to the application.
- `startCapture()` returns success *before* the portal consent dialog is shown;
  a denial is indistinguishable from success.
- Region capture accepts the request, does not crop, and returns success.
- Input capture needs `input`-group membership; inject needs `/dev/uinput`.
  Without them `startCapture()` succeeds with zero devices open.

**macOS**
- The FFmpeg shim is never built, so anything needing FFmpeg fails —
  `brew install ffmpeg` changes the error, not the outcome.
- Window capture is not supported and enumerates zero windows.
- Camera `startCapture` returns success without checking authorisation; a
  denied camera yields success and zero frames forever.
- Loopback needs macOS 13.0+ for a driver-free path; below that a third-party
  virtual device is required. A failed per-process tap silently falls back to
  whole-system audio.
- `MiniAV_Dispose()`'s callback-quiesce guarantee does not cover the macOS
  camera, screen or loopback backends.

**Android / iOS**
- Loopback and inject are **not compiled**, but the Dart layer exposes them
  unconditionally — so calling them raises a symbol-resolution error rather
  than `notSupported`.
- No video encoder exists on either platform, and FFmpeg cannot be obtained.
- The app must declare and request `CAMERA` / `RECORD_AUDIO` itself; miniAV
  never prompts. iOS additionally requires the usage-description keys (absent =
  process termination by the OS, not an error return).
- Android screen capture requires `miniav_flutter`'s consent plugin, which
  `miniav_recorder` does not depend on.

## Plan

Ordered so that each step makes the next one meaningful. Steps 1–3 are
prerequisites for making any honest claim at all.

### 1. Stop shipping the memory-safety bug *(release blocker)*

`MiniAVInputConfig` is 64 bytes in C and 48 bytes in the generated Dart
bindings; `input_api.c` copies 64 bytes out of a 48-byte allocation on every
`Input_Configure`, on every platform. Harmless today only because Dart never
enables motion — and regenerating the bindings naively converts it into an
arbitrary indirect call. Fix the mismatch, add a `sizeof` assertion test, and
audit sibling structs for the same appended-field pattern.

### 2. Get one green `native-build` run

The workflow is correct and has simply never executed. Trigger it explicitly
(the path filter will not re-run it on its own) and confirm all five legs
configure and compile. Until this exists, macOS/Linux/Android/iOS support is an
assertion with no backing. This is cheap and it converts four platforms from
"never compiled" to "compiles".

### 3. Make capability reporting honest

Three of four audits independently identified this as the highest-value fix,
ahead of any declaration work, because it converts crashes into clean
fallbacks:

- `FfmpegBackend.supportsEncode/supportsAudioDecode/supportsMux/supportsDemux`
  answer before any library load — `supportsMux` and `supportsDemux` are
  literally `=> true`. Probe availability once at registration and decline.
  Narrow `supportsAudioDecode` to the codecs actually mapped.
- Wrap the `opusCreate` / `opusEncCreate` calls in try/catch and return null,
  matching what every Media Foundation backend already does.
- `sw_audio` and `minigpu` claim unconditionally and cannot decline once they
  win negotiation.

### 4. Declare platforms explicitly

Then, and only then, replace inference with intent:

| Package | Declare |
|---|---|
| `miniav_tools_platform_interface`, `miniav_tools` | all six, including web (pure Dart) |
| `miniav_tools_codecs` | all six including web, after registering `PcmBackend` in the web entry |
| `miniav_tools_ffmpeg` | `windows`, `linux` |
| `miniav_player` | `windows` now; add `web` once the FFmpeg dependency is made web-safe |
| `miniav_recorder` | `windows` now; `linux`/`macos` after step 3 |
| `miniav`, `miniav_ffi` | `windows` now; the rest after step 2 goes green |

Do not declare `android` or `ios` for the recorder or player until loopback and
inject decline cleanly on those platforms and an encoder exists.

### 5. Earn platforms back, cheapest first

- **macOS**: make the build hook fall back to `FFMPEG_LIB_DIR` / the loader's
  Homebrew paths when the auto-download returns null, so a brew install can
  produce the shim. Small, specific, and it unlocks the whole FFmpeg feature
  set on macOS.
- **Web (player)**: make the `miniav_tools_ffmpeg` dependency conditional. The
  web code already works; only the pubspec blocks the tag.
- **Linux**: add a Linux leg that actually runs a suite, then upgrade its rows
  from IMPLEMENTED to VERIFIED.
- **Architecture detection**: return null rather than the x86-64 archive on
  ARM64, so the failure is a clean "unsupported" instead of a 92 MB download
  followed by a load error.

### 6. Keep the document true

This file is only useful if it is corrected when reality moves. The prior
native audit drifted within three weeks — several of its rows were inverted or
stale by the time they were re-checked, and it still tells readers that "CI
gates the release" when CI has never compiled anything. Re-derive the matrix
from evidence rather than editing cells in place.
