# OS media session — architecture and plan

Status: **Windows and web backends working; macOS/iOS, Linux and Android not
implemented.**

> **Relationship to the threading work** (gpu `docs/WORK_CONTEXT_PLAN.md`,
> 2026-08): background services and WorkContext compose but stay separate —
> this layer owns process LIFETIME (foreground service / `UIBackgroundModes` /
> audio-exempt tabs), WorkContext owns in-process placement. Once the player
> pipeline is a WorkContext server, `miniav_media_session_player` becomes just
> another client of the player's command/event channel (lock-screen pause =
> `PauseCmd`; notification position = the same `ProgressEvent` stream the UI
> reads). Requirements that plan takes on for us: multi-client channels, and
> no rAF-driven pacing anywhere in the pipeline.
>
> **DECIDED 2026-08-17: `miniav_media_session_player` is slated for
> elimination** before anything publishes (all three packages are still
> unpublished — no pub.dev name is claimed yet, so this is free now and
> permanent later). The transport vocabulary moves to
> `miniav_tools_platform_interface`; this package's `attach(channel)` replaces
> the binding; the one-liner moves into app code. The two-package table below
> then reads: `miniav_media_session` (+ its `_flutter` Android companion,
> which stays — it is the JVM/manifest carrier and will also host the
> foreground service). `WorkEntry.service(...)` in the WorkContext plan is the
> declaration this layer honors.

## The problem

An app that plays audio should appear in the system shell — the Windows volume
flyout, the macOS Control Center tile, the Android/iOS lock screen, the browser
media notification — and the keyboard's media keys should control it.

Nothing in the family did any of this. `miniav_player` exposes a complete
transport (`isPaused`, `position`, `duration`, `pause()`, `resume()`, `seek()`)
with nothing publishing it.

## The one non-obvious fact

**Publishing and receiving are the same feature, not two.**

On every platform the OS routes media keys to whichever app owns the registered
media session. There is no "read the media key" path:

- Windows delivers `WM_APPCOMMAND` only to the **foreground** window, which is
  useless for an app running behind a game or a stream.
- A low-level keyboard hook can see media keys globally — by stealing them from
  every other media app on the machine.

So registering a session is the prerequisite for the keys working at all. This
is why the work does **not** belong in miniAV's `input` module even though that
module already installs keyboard hooks on Windows.

## Package layout

Two packages, both in `miniav_tools`:

| Package | Depends on | Why |
|---|---|---|
| `miniav_media_session` | nothing in the family | The OS integration. Pure Dart + a native asset. |
| `miniav_media_session_player` | `miniav_media_session`, `miniav_player` | One-line binding. |

**Why the session package is not inside `miniav_player`:**

1. **Weight.** `miniav_player` pulls `minigpu`, `minigpu_view`,
   `miniav_tools_ffmpeg` and `miniav_tools_codecs` — an entire decode and
   GPU-present stack including an FFmpeg native build. An app that only wants a
   now-playing card (a soundboard, a mixer, a game) must not have to build
   FFmpeg to get one.
2. **Cardinality.** The OS allows exactly **one** session per app, but an app
   can hold many players at once. Session ownership is an app-level policy
   decision, not a player-level one. `MiniavMediaSession.create` throws on a
   second concurrent session rather than letting two players silently fight
   over the lock screen.
3. **Permissions.** Android needs a foreground service and a notification
   permission; iOS needs `UIBackgroundModes: audio`. Inside the player, every
   consumer would inherit those — including recorder-style apps that never play
   anything.

The dependency runs one way: the binding knows about both, neither knows about
the binding.

## Native assets, not a Flutter plugin

The first draft used method channels. That was wrong. The family already builds
native assets for every native platform (`miniav_ffi/hook/build.dart` switches
on `targetOS` across android/iOS/macOS/linux/windows), and:

- `miniav_c` already compiles **C++/WinRT** (`screen_context_win_wgc.cpp`), so
  SMTC needs no new toolchain.
- The HWND that `ISystemMediaTransportControlsInterop::GetForWindow` requires
  does not have to come from a plugin registrar — native code can own a hidden
  top-level window, and `MiniAV_MediaSession_SetHostWindow` lets an app hand
  over its existing one instead.
- Native assets keep the package usable from plain Dart, so `dart test` covers
  it (it does — see `test/media_session_test.dart`).

Android is the one genuine exception: `MediaSession`, the foreground service
and the notification are JVM-only. The family already has that exact seam —
`miniav_flutter` loads `miniav_flutter_jni` and hands a JNI global ref down to
`miniav_c`, alongside a typed foreground service in
`MiniavScreenCaptureService.kt`. Android's backend follows the same shape.

Web has no native half at all and never will: browsers expose
`navigator.mediaSession` directly, so that backend is pure Dart selected by
conditional import.

## Backend status

| Platform | API | Implementation | Verification |
|---|---|---|---|
| Windows | SMTC via `ISystemMediaTransportControlsInterop` (C++/WinRT) | `native/src/windows/` | Compiles, activates, session held + released on-device |
| Web | `navigator.mediaSession` | `lib/src/backend_web.dart` | Compiles and passes in Chrome (`dart test -p chrome`) |
| Linux | MPRIS2 over D-Bus | `lib/src/backend_mpris.dart` (**pure Dart**) | Analyses; no-bus path unit-tested; never run against a real bus |
| macOS | `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` (ObjC++) | `native/src/apple/` | **Never compiled** |
| iOS | same, plus an `AVAudioSession` category | `native/src/apple/` (shared) | **Never compiled** |
| Android | framework `MediaSession` + foreground-service MediaStyle notification | `miniav_media_session_flutter` (Kotlin) | **Never compiled or run** |

Linux is pure Dart on purpose: MPRIS is a D-Bus wire protocol, not an OS API,
so there is nothing a native TU could do that Dart cannot — and doing it in
Dart avoids a `libdbus-1` system dependency and makes the code analysable and
unit-testable on any host. `MINIAV_MS_ENABLE_MPRIS` stays OFF; the Dart factory
routes `Platform.isLinux` before the code asset is reached.

Android is the only platform that needs a plugin. `MediaSession` needs a
`Context` and the shade notification needs a foreground `Service` — both
JVM-only. The core package cannot depend on the companion without inverting the
dependency graph and dragging the Flutter SDK into a plain-Dart package, so the
companion pushes itself in through `MiniavMediaSession.backendOverride`.

Unimplemented platforms report `isSupported == false` with a reason naming the
file that would implement them. They deliberately do **not** report success —
a backend that accepted every call and published nothing would be
indistinguishable from a working one whose card the shell simply is not
showing. That is the failure mode that hid the per-process loopback bug for
months.

## Phasing

- **P0 — done.** Package skeleton, C ABI (`native/include/miniav_media_session.h`),
  build hook, FFI backend, web backend, player binding, tests. The whole chain
  is verified: CMake builds the DLL, the asset registers, FFI resolves, tests
  pass.
- **P1 — Windows SMTC. Landed.** Hidden top-level host window plus a
  message-pump thread; setters write a mutex-guarded snapshot and post
  `WM_MS_APPLY`, so the pump thread is the only thing that touches the WinRT
  objects and rapid position pushes coalesce. `MiniAV_MediaSession_SetHostWindow`
  adopts an existing `HWND` instead of creating one.
  **Verified:** compiles, activates (`isSupported == true`), holds a live
  session, and releases cleanly with the pump thread joined.
  **NOT yet verified by a human:** that the flyout card actually renders and
  that each hardware key produces the matching `MediaCommand`. Run
  `dart run tool/media_session_probe.dart 60` and watch for `COMMAND ->` lines.
- **P2 — macOS + iOS. Written, never compiled.** One ObjC++ file serves both.
  Gate: it must build on a macOS CI leg before anyone believes it. Environmental
  prerequisites it cannot satisfy itself — a real app bundle on macOS, and an
  active `AVAudioSession` plus `UIBackgroundModes: audio` on iOS — are app
  configuration, because taking over an app's audio session from a library is
  how you break every other sound it makes.
- **P3 — Linux MPRIS. Written in Dart, no-bus path tested.** Needs one run
  against a real session bus with `playerctl` and a desktop's media keys.
- **P4 — Android, phases 1 and 2. Written, never compiled or run.** Phase 1 is
  the MediaSession itself: media buttons and lock-screen controls. Phase 2 adds
  `MiniavMediaSessionService`, a foreground service carrying a MediaStyle
  notification, which is what puts the panel in the notification shade.
  The permissions and the service declaration live in the companion's own
  manifest and merge into the host app, so no host-app manifest edit is needed
  — that inheritance is contained precisely because Android sits in its own
  package. `showNotification: false` opts the whole service back out.
  Notification buttons dispatch through the session's transport controls rather
  than a second command path, so a shade button and a headset button land in
  the same callback.

## Open decisions

1. **Linux transport.** `package:dbus` (pure Dart, no system dep, but splits
   the backend across two languages) vs libdbus/sd-bus in the native asset
   (consistent, adds a system dependency).
2. **Android companion.** A new plugin package versus extending
   `miniav_flutter`. Extending it means a tools package depending on a core
   Flutter package.
3. **Player change notification.** `MiniavPlayer` has no `ValueListenable` or
   state stream, so the binding polls at 250 ms. Position needs a periodic push
   anyway, but the state half is pure overhead and costs up to one interval of
   lag before the shell notices an in-app pause. A small listenable on
   `MiniavPlayer` would remove it — a backwards-compatible addition.
4. **Artwork for byte art.** Done on Windows: `MediaArtwork.bytes` is written
   to `%TEMP%` under a fresh name per track and referenced as a `file:///` URI,
   with the previous track's file reaped on replacement and the last one on
   destroy. Linux will need the same treatment. A fresh name per track is
   mandatory — SMTC keys the thumbnail off the URI, so rewriting one path
   leaves the first cover on screen for the whole session.

## Known gaps

- `PlayerMediaSession` has no automated test. `MiniavPlayer` is a concrete
  class with no interface to fake, so covering the command mapping means either
  extracting a small transport interface or driving a real player in a widget
  test. The mapping is currently verified only by reading.
- The Windows flyout has not been eyeballed and no hardware key has been
  pressed against it; activation is proven, rendering and key routing are not.

## Traps already encoded

- **The command callback passes scalars only.** A Dart
  `NativeCallable.listener` marshals arguments asynchronously, so any pointer
  would dangle by the time the handler runs. `miniav_c` learned this with its
  log callback and had to adopt a malloc-in-C / free-in-Dart handoff. Scalars
  need no handoff, so this callback cannot have that bug.
- **`setPositionState` throws on web** when duration is absent or position
  exceeds it — reachable in normal use, because a poll can observe the outgoing
  track's position against the incoming track's duration. The web backend
  guards rather than catches.
- **Struct growth.** Appending a field to `MiniAVMediaSessionMetadata`
  preserves every existing offset but changes `sizeOf`, and `sizeOf` is what
  the allocation uses. A Dart struct that drifts short of the C one writes past
  the end of the buffer — the `MiniAVInputConfig` bug.
- **Declaring an action is a promise.** The OS renders a button or routes a key
  for every declared action, so `kDefaultMediaActions` excludes next/previous:
  the core session has no queue, and a dead button is worse than an absent one.
