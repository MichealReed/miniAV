# miniav_media_session

Publishes what your app is playing to the OS shell, and receives transport
commands back from it — hardware media keys, the Windows volume flyout, the
macOS Control Center tile, lock-screen widgets, browser media notifications,
Bluetooth headsets.

Those two halves are one feature. Every platform routes media keys to whichever
app owns the registered session, so publishing is what makes the keys work.
There is no way to just read a media key without stealing it from every other
media app on the machine.

## Install

Driving your own playback:

```yaml
dependencies:
  miniav_media_session: ^0.1.0
  # Android only. Its MediaSession lives on the JVM and cannot be reached from
  # a code asset, so Android needs this companion. Harmless on other platforms.
  miniav_media_session_flutter: ^0.1.0
```

Using `MiniavPlayer`? Take **`miniav_media_session_player`** instead and skip
everything below — it wires the whole session to a player in one call and pulls
both packages in for you:

```yaml
dependencies:
  miniav_media_session_player: ^0.1.0
```

## Usage

```dart
final session = await MiniavMediaSession.create(appName: 'Tunes');

// Android's JVM half. No-op on every other platform; omit it if you do not
// depend on miniav_media_session_flutter.
registerMiniavMediaSessionAndroid();

final commands = session.commands.listen((command) {
  switch (command.action) {
    case MediaAction.play:
      resumePlayback();
    case MediaAction.pause:
      pausePlayback();
    case MediaAction.playPause:
      togglePlayback();
    case MediaAction.stop:
      stopPlayback();
    case MediaAction.seekTo:
      // Always null-check: only seekTo carries a position, and some platforms
      // send the action with no value.
      final target = command.position;
      if (target != null) seekTo(target);
    case MediaAction.seekForward:
      seekBy(command.offset ?? const Duration(seconds: 10));
    case MediaAction.seekBackward:
      seekBy(-(command.offset ?? const Duration(seconds: 10)));
    default:
      break;
  }
});

await session.setMetadata(const MediaMetadata(
  title: 'Song',
  artist: 'Band',
  duration: Duration(minutes: 3, seconds: 42),
));
await session.setPlaybackState(MediaPlaybackState.playing);

// Push the playhead a few times a second while playing, and once after a seek.
await session.setPosition(const MediaPosition(
  position: Duration(seconds: 12),
  duration: Duration(minutes: 3, seconds: 42),
));

// On shutdown — see "Releasing the session" below.
await commands.cancel();
await session.dispose();
```

`registerMiniavMediaSessionAndroid` must run **before** `create`; the ordering
above is only for readability. Call it once at startup.

## Releasing the session

Call `dispose()` when playback is finished with — on app shutdown, or when you
hand the transport to something else. It is not optional housekeeping:

- The shell card stays on screen and media keys keep routing to a dead app
  until the OS notices.
- On native platforms the session holds a `NativeCallable`, which keeps the
  isolate alive.
- Only one session may be live per app, so a leaked one makes the next
  `create()` throw `StateError`.

`dispose()` is idempotent, so a redundant call in a teardown path is fine.

## Behaviour worth knowing

**`create` never throws for an unsupported platform.** A missing shell
integration is not a reason to stop playback. Check `isSupported` and
`unsupportedReason` to find out whether the card will actually appear.

**A live session is not the same as a visible card.** On several platforms the
session registers and media keys route to it while the shell still shows
nothing, because the shell needs an app identity or active audio it cannot find.
`session.backendDetail` reports what the backend actually did — check it first
when the keys work but nothing is on screen. Every per-platform gotcha below is
a version of this.

**One session per app.** That is an OS limit, not a library one. Creating a
second live session throws `StateError` rather than letting two of them fight
over the lock screen.

**Position does not need pushing at frame rate.** Shells extrapolate the
playhead from `MediaPosition.speed` between updates. A few times a second, plus
once after each seek, is enough; pushing more often makes some shells stutter
the progress bar rather than smooth it. Report `speed: 0` while paused, or the
bar creeps forward and snaps back.

**Declaring an action is a promise.** The OS renders a button or routes a key
for everything you declare. `kDefaultMediaActions` omits next/previous for that
reason — declare them only when a queue exists behind them.

## Platform support

| Platform | API | State |
|---|---|---|
| Windows | System Media Transport Controls | Implemented; verified on-device |
| Web | `navigator.mediaSession` | Implemented; verified in Chrome |
| Linux | MPRIS2 over D-Bus (pure Dart) | Implemented; not yet run on a desktop |
| macOS / iOS | `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` | Implemented; **never compiled** |
| Android | framework `MediaSession` | Implemented; **never compiled or run** |

No platform ever reports success while publishing nothing — an unavailable
backend reports `isSupported == false` and says why.

## Integration checklist

Everything an integrating app has to do, in one place. Nothing here is done for
you, and each item is the thing that most commonly makes a session register
while nothing appears on screen.

| Platform | What you must do |
|---|---|
| All | Call `dispose()` on shutdown. Publish `speed: 0` while paused. Only declare actions you actually handle. |
| Web | Start audible playback from a **user gesture** before publishing. Use `MediaArtwork.bytes`/`.uri`, never `.file`. |
| Windows | Create the session **after** your window exists (post-first-frame), or pass `hostWindowHandle`. Nothing to install. |
| macOS | Ship as a real `.app` bundle. Nothing to install. |
| iOS | Add `UIBackgroundModes: audio` to `Info.plist` **and** activate an `AVAudioSession` playback category yourself. |
| Linux | Nothing — but there must be a D-Bus session bus at runtime. |
| Android | Add `miniav_media_session_flutter`, call `registerMiniavMediaSessionAndroid()`, and ensure `minSdkVersion >= 24`. |

## Per-platform setup

### Web — the page must actually be playing audio

Nothing to install. But browsers do **not** show a media notification, and do
**not** route media keys, just because you set metadata: they surface the
session only while the page is genuinely playing audible media, started from a
user gesture. A silent page that calls `setMetadata` gets no card and no keys,
and that is the browser's policy, not a bug here.

So: start playback first, from a real user interaction, then publish. If your
audio path is a bare Web Audio graph with no media element, some browsers will
not consider the page a media session at all.

`MediaArtwork.file` cannot work on web — a browser cannot read an arbitrary
local path. Use `MediaArtwork.bytes` (turned into a blob URL, and revoked on
the next track) or `MediaArtwork.uri`. Passing a file path is accepted and
ignored so shared code still runs.

Safari implements only part of the API; unsupported actions are skipped
individually rather than failing the whole set.

### Windows — needs a real window

SMTC needs a top-level window, and the shell draws its card from the **app
identity behind that window**. The backend adopts the host process's own
visible top-level window when it has one, and falls back to a hidden helper
window otherwise.

That fallback is a working session with no card: keys route, but the shell has
nothing to draw. A console process — or a Flutter app that attaches before its
first frame — hits exactly this. `backendDetail` tells you which happened.

The fix is almost always ordering, not configuration: create the session after
the first frame.

```dart
WidgetsBinding.instance.addPostFrameCallback((_) async {
  session = await MiniavMediaSession.create(appName: 'Tunes');
});
```

`hostWindowHandle` exists for the cases that ordering cannot fix — a hidden
main window, or several top-level windows where the automatic pick is wrong.
Dart has no built-in way to get an `HWND`; take it from whatever window-management
plugin you already use, or from `GetActiveWindow` over FFI. Most apps never
need it.

Requires Windows 10, which is already Flutter's own desktop minimum — so this
adds no constraint your app does not have.

### macOS — needs an app bundle

`MPNowPlayingInfoCenter` attributes the session to the running application, so
the process must be a real `.app` bundle. A bare executable (`dart run`, a CLI)
has no bundle identifier and `create` reports that rather than publishing into
a void. A normal `flutter build macos` app is fine.

### iOS — needs an audio session and a background mode

Add to `Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array><string>audio</string></array>
```

and activate an `AVAudioSession` with a playback category in your app before
creating the session — for example in `AppDelegate.swift`:

```swift
import AVFoundation

let audio = AVAudioSession.sharedInstance()
try? audio.setCategory(.playback, mode: .default)
try? audio.setActive(true)
```

Without an active playback-category session, `MPRemoteCommandCenter` delivers
nothing and the lock-screen controls never appear — the session is live and
silent, the same failure shape as the Windows and web cases.

This library deliberately does **not** configure the audio session for you: a
library that seizes an app's audio session breaks every other sound the app
makes, and the right category depends on whether you duck, mix or interrupt.

### Linux — needs a D-Bus session bus

No system package required; the backend speaks MPRIS2 over the session bus in
pure Dart. It claims `org.mpris.MediaPlayer2.<AppName>.instance<pid>`, which is
what GNOME, KDE and `playerctl` scan for, and the desktop environment is what
routes media keys to it.

Headless boxes, containers and root shells often have no session bus; `create`
reports that instead of failing.

Verify with:

```sh
playerctl -l          # should list your app
playerctl metadata    # should show the current track
```

### Android — needs the companion package

`MediaSession` lives on the JVM and cannot be reached from a code asset, so
Android needs **`miniav_media_session_flutter`**:

```yaml
dependencies:
  miniav_media_session: ^0.1.0
  miniav_media_session_flutter: ^0.1.0
```

```dart
registerMiniavMediaSessionAndroid();   // no-op off Android
final session = await MiniavMediaSession.create(appName: 'Tunes');
```

`miniav_media_session_player` calls that registration for you.

**`minSdkVersion` must be at least 24.** The companion targets API 24, so a
lower app fails the Gradle manifest merge outright with
`uses-sdk:minSdkVersion N cannot be smaller than version 24 declared in
library`. Raise it in `android/app/build.gradle`:

```groovy
android {
    defaultConfig {
        minSdkVersion 24
    }
}
```

You get media buttons (hardware, headset, Bluetooth), lock-screen transport,
and the media panel in the notification shade with album art. The panel is
carried by a foreground service, so the companion's manifest contributes
`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK` and
`POST_NOTIFICATIONS`, plus the service declaration itself — nothing further is
needed from your manifest.

Do not want that? `registerMiniavMediaSessionAndroid(showNotification: false)`
keeps the buttons and lock screen and drops the panel and the service.

## Testing

```sh
dart test               # VM: types, session lifetime, native backend
dart test -p chrome     # browser: the web backend's compile + behaviour gate
```

The browser leg matters on its own: the web backend never sees the Dart VM, so
a `dart:js_interop` mistake in it is invisible to `dart analyze` on a native
host.

See `docs/MEDIA_SESSION_PLAN.md` in the repository for the architecture and
per-backend verification status.
