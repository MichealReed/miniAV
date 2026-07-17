# miniAV Remote-Desktop A/V/Input Readiness Plan

**Status: Phase A SHIPPED (2026-07-10, miniav_ffi 0.7.0) — injection + cursor + hscroll. Output/present deferred to a future `_tools` player.**

> **Done:** `MiniAV_Inject_*` (SendInput / CGEventPost / uinput), `MiniAV_Screen_SetCaptureCursor`
> (WGC/SCK/PipeWire; DXGI cursor-less), `MiniAVMouseEvent.wheel_delta_x` + `is_absolute`, full
> 5-package Dart wiring. Windows compiled + linked + smoke-tested; macOS/Linux self-reviewed +
> adversarially reviewed (1 major + 3 minor, all fixed). **Remaining gate = CI/device:** the one
> open item is the Linux absolute-pointer uinput device *signature* (`INPUT_PROP_DIRECT`+`BTN_TOUCH`
> vs an `INPUT_PROP_POINTER`/BTN_LEFT absolute-mouse signature, and whether abs moves need a
> BTN_TOUCH transition) — only a real X11/Wayland compositor can confirm which classification makes
> libinput honor the ABS axes. Everything else in Phase A is done.

> **Decision (2026-07-10):** Build Phase A **except output**. Audio output AND video
> present both move into a future **`_tools` media player** (bring-your-own / bundled
> codec, GPU hotpath preserved — the livetensor pattern). miniAV_c core therefore gains
> **no** output/sink module for now — only the three source/control items below.
> §3 (output architecture) is retained as design notes for that later tools work; the
> A/B/C fork is moot for core since present now lives in tools by decision.

Date: 2026-07-10 · Follows the mobile catch-up (`MOBILE_PLATFORM_SPEC.md`) and the desktop audit (`NATIVE_AUDIT.md`).

Goal: make miniAV's **A/V/Input primitives** complete enough that someone can build a
cross-platform remote-desktop client/server on top of it. We are **not** building the
client/server and **not** picking a codec here — only the capture / inject / output
primitives and the buffer contracts that a codec plugs into.

---

## 0. The remote-desktop data flow (what the layer must cover)

```
                          SERVER (controlled machine)                 CLIENT (viewer)
  ┌─────────────┐   ┌──────────────┐   ┌───────┐   net   ┌────────┐   ┌───────────────┐
  │ Screen cap  │──▶│ frame buffer │──▶│encode │─ ─ ─ ─ ▶│ decode │──▶│ video present │
  │ (GPU tex)   │   │ (GPU/CPU)    │   │(codec)│         │(codec) │   │ (GPU tex→surf)│
  └─────────────┘   └──────────────┘   └───────┘         └────────┘   └───────────────┘
  ┌─────────────┐   ┌──────────────┐   ┌───────┐   net   ┌────────┐   ┌───────────────┐
  │ Loopback/mic│──▶│ PCM buffer   │──▶│encode │─ ─ ─ ─ ▶│ decode │──▶│ audio output  │
  └─────────────┘   └──────────────┘   └───────┘         └────────┘   └───────────────┘
  ┌─────────────┐                              net                    ┌───────────────┐
  │ input inject│◀─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─│ input capture │
  │ (replay)    │                                                     │ (kbd/mouse/pad)│
  └─────────────┘                                                     └───────────────┘
```

miniAV owns the **grey boxes** (capture on the left, output/inject on the right). The
**codec boxes are explicitly out of scope** — they belong in `_tools` or are brought by
the user, and they operate on miniAV's buffer contract so the GPU hotpath is never broken.

The key mental model shift: **miniAV is the OS glue for both directions.** Today it only
does the capture (source) direction. Remote desktop needs the **output (sink) direction**:
input injection, audio output, and video present. These are the mirror image of the
capture modules and reuse the same `MiniAVBuffer` contract, just flowing the other way.

---

## 1. Capability audit (2026-07-10, all four desktop backends + public API)

| Capability | Direction | State | Notes |
|---|---|---|---|
| Screen capture | source | ✅ | WGC, DXGI, macOS SCK, Linux PipeWire; GPU-handle zero-copy |
| Camera capture | source | ✅ | + mobile (0.7.0) |
| Mic capture | source | ✅ | miniaudio |
| System-audio (loopback) capture | source | ✅ | WASAPI / CoreAudio taps / PipeWire |
| Input **capture** (kbd/mouse/pad) | source | ✅ | keycode+scancode, abs xy + deltas, all buttons, gamepad |
| Multi-context capture | source | ✅ | DXGI/macOS per-context; WGC/PipeWire share ref-counted plumbing — not blockers |
| **Input injection** (replay) | **sink** | ❌ | the server-side "control" — nothing replays events |
| **Audio output** (play PCM) | **sink** | ❌ | miniaudio supports it; only `capture` is wired |
| **Video present** (show frame) | **sink** | ❌ | frames are captured, never presented; no surface/swapchain path |
| Cursor in captured frame | source | ❌ | all 4 backends strip it; 3/4 support a native toggle |
| Horizontal scroll | both | ❌ | `MiniAVMouseEvent.wheel_delta` is vertical only |

---

## 2. Confirmed workstream (decided — can proceed independently)

### 2.1 Input injection — new `MiniAV_Inject_*` module
Mirror of the input-capture module (same `api.c` / `context.h` / backend-table shape).
The sink twin of input capture: takes `MiniAVKeyboardEvent` / `MiniAVMouseEvent` /
`MiniAVGamepadEvent` and replays them onto the local machine.

- **Windows:** `SendInput` (keyboard/mouse). Gamepad injection has no public API →
  report NOT_SUPPORTED (or a documented ViGEm-shaped extension seam later).
- **macOS:** `CGEventPost` (keyboard/mouse). Requires Accessibility permission — document it.
- **Linux:** **`/dev/uinput`** (decided). Works under **both X11 and Wayland** (XTest is
  X11-only and dead on Wayland). Needs uinput device access via a udev rule or root —
  document it. Create a virtual kbd+mouse device on configure, destroy on teardown.
- Absolute vs relative mouse: support both (`MOVE` with abs x/y and with delta_x/delta_y).
- API sketch: `MiniAV_Inject_CreateContext` → `Configure(types)` →
  `InjectKeyboard/InjectMouse/InjectGamepad(event)` → `DestroyContext`. No callback thread;
  injection is a synchronous call. Bounded-destroy protocol still applies if a virtual
  device teardown can block.

### 2.2 Cursor show toggle
A pre-configure setter seam (like `SetIOSAppGroup`), **not** an ABI break to
`ConfigureDisplay`. `MiniAV_Screen_SetCaptureCursor(ctx, bool)` (name TBD), wired to:
- WGC: `GraphicsCaptureSession.IsCursorCaptureEnabled` (Win 10 2004+).
- macOS SCK: `SCStreamConfiguration.showsCursor`.
- PipeWire: portal `cursor_mode` = embedded.
- **DXGI: cursor-less** — would need manual pointer-shape compositing
  (`GetFramePointerShape` + monochrome/color/masked blends). Documented: use WGC when you
  need the cursor on Windows. (Optional later: DXGI compositing for full parity.)

### 2.3 Horizontal scroll (minor)
Add `wheel_delta_x` (rename existing to `wheel_delta_y` or add alongside) to
`MiniAVMouseEvent`; populate from WGC/raw-input `WM_MOUSEHWHEEL`, macOS
`scrollingDeltaX`, evdev `REL_HWHEEL`. Also consumed by injection (2.1).

---

## 3. The output/present architecture (THE fork to think about)

Audio output is unambiguous. **Video present is the real design decision**, and it hinges
on one hard constraint you set:

> Do not introduce the minigpu integration at the miniAV level. The user brings their own
> codec but keeps the GPU hotpath (the livetensor pattern).

### 3.1 Resolving "GPU present at this level" vs "no minigpu in core"
These are **not** in conflict, because **presenting a native GPU texture to a native
surface does not require minigpu.** minigpu is a *compute* abstraction (WGSL/Dawn).
Present is just platform swapchain code (D3D11/Metal/EGL-Vulkan/ANativeWindow) — the same
class of native GPU code miniAV already uses on the *capture* side to produce handles. So
miniAV_c **can** own "present this D3D11/Metal/AHardwareBuffer texture to this surface"
with zero minigpu dependency. The codec that *fills* the texture is what stays outside.

### 3.2 Symmetric buffer contract (the load-bearing idea)
Capture already emits `MiniAVBuffer` with `contentType ∈ {cpu, gpuD3D11Handle,
gpuMetalTexture, gpuAHardwareBuffer, dmabuf}`, `pixelFormat`, `planes[]`, `nativeHandles[]`,
`nativeFence`. **Output consumes exactly that same struct, flowing the other way.** A
decoder (in `_tools` or BYO) writes into a GPU texture, wraps it as a `MiniAVBuffer` with
the right GPU content type + a fence, and hands it to the output primitive. End-to-end GPU
hotpath, no CPU round-trip, no minigpu in the core.

One inversion to design: the **release/fence direction flips.** On capture, miniAV owns the
buffer until `MiniAV_ReleaseBuffer`. On output, the *app* owns the submitted buffer until
miniAV signals it has consumed it (presented/copied) — so we need a completion signal
(a fence the app waits on, or a per-submit "done" callback) before the app reuses/frees the
texture. This is `nativeFence` used in reverse.

### 3.3 Where does "present" live? — three forks

**Fork A — Present in core (miniav_c owns a native swapchain).**
App hands miniAV a native surface (HWND / CAMetalLayer / wl_surface / ANativeWindow);
miniAV creates a swapchain, blits the submitted texture into the backbuffer, presents.
- ✅ Turnkey "playback"; the app just submits frames. Symmetric with capture using native GPU.
- ❌ Biggest lift: per-platform swapchains, resize/vsync, and **cross-adapter** handling
  when the decode device ≠ the display device (shared handles + possible copy — the
  `CrossAdapterRowMajor` / shared-fence territory already noted in project memory). Windows
  surface ownership is the fraught part; macOS/Android are cleaner (UMA / SurfaceTexture).

**Fork B — Contract only (present in app/tools; core adds nothing for video).**
The existing GPU buffer contract already suffices; `_tools` ships decoders that *produce*
that contract; the app presents via its own renderer (Flutter external `Texture`, minigpu,
custom). miniAV_c gets **no** video-output module.
- ✅ Smallest core; strictly honors "no minigpu / no present ownership in core"; a Flutter
  client presents through the texture registry it already uses.
- ❌ miniAV is not the thing that shows pixels — "video playback" is a `_tools`/app story,
  not a miniAV primitive. May feel incomplete for non-Flutter/native consumers.

**Fork C — Present helper in `_tools` (core clean, optional turnkey present).**
Core stays capture + audio-output + the buffer contract. `_tools` provides BOTH the
decoders AND an optional present/blit helper (which *may* use minigpu or native GPU),
taking a `MiniAVBuffer` + an app surface. BYO-decode and BYO-present both slot into the
same contract.
- ✅ Core stays minimal and minigpu-free; turnkey present available without bloating core;
  matches the livetensor "GPU hotpath in tools" pattern most literally.
- ❌ Two places to look (core for audio-out, tools for video-present); slight asymmetry
  between the audio and video output stories.

### 3.4 Recommendation (for discussion, not decided)
- **Audio output → core, now.** No codec, no GPU, symmetric with capture, miniaudio already
  does it. New `MiniAV_AudioOutput_*` module. Zero controversy.
- **Video present → lean Fork C**, with the option to promote the present helper into core
  (Fork A) later if a turnkey native-surface path proves broadly wanted. Rationale: it
  keeps your hard constraint intact (core never imports minigpu, never owns a window),
  ships the GPU hotpath where livetensor-style tools already live, and still lets a
  native-surface present helper exist for apps that want it — without making the core
  responsible for swapchains/resize/cross-adapter on four platforms.
- Regardless of fork, **define the output `MiniAVBuffer` submission + completion-fence
  contract in core now** — it is the seam every decoder and every present path binds to,
  and getting it right is what actually makes the GPU hotpath portable.

### 3.5 Open decisions (need your call before video work starts)
1. **Fork A / B / C** for video present.
2. **Surface handshake** (if A or C): app-provided native surface handle, or
   app-provided GPU texture the app then presents itself (Flutter external texture)?
3. **Output umbrella naming:** `MiniAV_AudioOutput_*` / `MiniAV_VideoOutput_*` /
   `MiniAV_Inject_*` (an "Output/sink" family mirroring the capture family), vs folding
   direction into existing modules. (Recommend the separate-module family — matches the
   current per-module layout.)
4. **Completion signal shape** for GPU submit: fence handle the app waits on, vs a
   per-frame "consumed" callback.

---

## 4. Proposed module map (if the Output family is adopted)

```
CAPTURE (source, exists)          OUTPUT (sink, new)
  MiniAV_Camera_*                   —
  MiniAV_Screen_*    ── + cursor toggle
  MiniAV_Audio_*  (mic)             MiniAV_AudioOutput_*   (PCM → device)   [core]
  MiniAV_Loopback_*                 —
  MiniAV_Input_*   (capture)        MiniAV_Inject_*        (replay events)  [core]
                                    MiniAV_VideoOutput_*   (tex → surface)  [fork A: core / C: tools]
```

Each new core module follows the established shape: backend table with `#if` platform
gates + NULL sentinel, per-context ops vtable, bounded-destroy TIMEOUT protocol,
`MINIAV_SAFE_DISPATCH` where a callback thread exists, and the 5-package Dart wiring
(bindings → platform_interface → ffi impl → web stub → miniav wrapper).

---

## 5. Sequencing & risk

1. **Phase A (green-lit, no fork):** input injection (uinput on Linux), cursor toggle,
   horizontal scroll, audio output. All four are self-contained and unblock the
   input-control + audio halves of remote desktop immediately.
2. **Phase B (after fork decision):** the output `MiniAVBuffer` + completion-fence
   contract, then video present per the chosen fork.
3. **Codecs:** never in this repo's core — `_tools` or BYO, binding to the Phase-B contract.

Risks: injection permissions (uinput device access, macOS Accessibility) are deployment
concerns to document, not code blockers. Video present cross-adapter is the one genuinely
hard technical item and is exactly why Fork C (isolate it in tools) is attractive. As with
the mobile tranche, non-Windows backends compile-verify only in CI / on devices from this
Windows box.

---

## 6. Test coverage (Phase A)

Automated Dart tests, all passing on the Windows dev box:

- `miniav_ffi/test/miniav_inject_test.dart` — injection lifecycle
  (create/configure/destroy, use-after-destroy throws), the **MiniAVMouseEvent FFI
  struct ABI round-trip** (proves the Dart struct byte-matches C for the new
  `wheel_delta_x`/`is_absolute` fields), `SetCaptureCursor` before/after-configure
  (rejection path), `setIOSAppGroup` NOT_SUPPORTED off-iOS, and the
  `MINIAV_ERROR_PERMISSION_DENIED` (-23) enum regression guard.
- `miniav/test/miniav_inject_test.dart` — the `MiniInject` wrapper +
  `MiniScreen.setCaptureCursor` at the umbrella level, and the new mouse-event fields
  (defaults `wheelDeltaX=0`/`isAbsolute=true` — the non-breaking-constructor contract —
  plus explicit values).
- Regression: the existing 32-test `miniav/test/miniav_input_test.dart` still passes
  after the shared-struct change.

Deliberately **not** tested here (would be dishonest to fake): real event injection
(moves the developer's actual cursor/keyboard), the macOS/Linux injection backends and
the non-Windows cursor paths (no toolchain — CI compile + on-device manual runs are the
gate), and the mobile backends (same CI/device gate as the mobile tranche). The Linux
uinput absolute-pointer device classification (§ status header) is the specific behavior
a real X11/Wayland session must confirm.
