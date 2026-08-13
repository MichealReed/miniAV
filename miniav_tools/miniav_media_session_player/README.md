# miniav_media_session_player

Binds a `MiniavPlayer` to the OS media session, in both directions.

## Install

```yaml
dependencies:
  miniav_media_session_player: ^0.1.0
```

That is the whole dependency list. `miniav_media_session` and the Android
companion `miniav_media_session_flutter` come transitively, and `attach`
registers the Android half for you — there is nothing else to add and nothing
to call at startup.

```dart
final binding = await PlayerMediaSession.attach(
  player,
  appName: 'Tunes',
  metadata: const MediaMetadata(title: 'Song', artist: 'Band'),
);

// Hardware media keys, the lock screen and the Windows flyout now drive
// `player`. The shell shows its track, state and playhead.

await binding.detach();
```

Track changes are one call:

```dart
await binding.setMetadata(const MediaMetadata(title: 'Next song'));
```

Skip controls are advertised only when you can service them:

```dart
await PlayerMediaSession.attach(
  player,
  appName: 'Tunes',
  onNext: playlist.next,
  onPrevious: playlist.previous,
);
```

## Behaviour worth knowing

**It polls, at 250 ms by default.** `MiniavPlayer` exposes a full transport but
no change notification — no `ValueListenable`, no state stream — so noticing an
in-app pause requires looking. Position needs a periodic push anyway, so the
poll is not pure overhead, but state changes made through your own UI can lag
the shell by up to one interval. Commands arriving *from* the OS push
immediately, because that path knows what changed.

**`stop` pauses and rewinds.** `MiniavPlayer` has no `stop()`: closing it would
end playback entirely and pausing alone leaves the playhead mid-track.

**Paused reports rate 0.** Otherwise the shell keeps extrapolating the playhead
forward between pushes and snaps it back on the next one.

**`detach()` does not close the player.** The binding never owned it.

## Platform setup

`attach` works on every platform `miniav_media_session` supports, and registers
the Android companion for you. Two setup steps are still yours, because a
library cannot do them:

- **Attach after your window exists (Windows).** SMTC draws its card from the
  app identity behind a visible top-level window. Attaching during startup,
  before the first frame, silently falls back to a hidden window: media keys
  work, no card appears. Check `binding.session.backendDetail` if that happens.
- **Start playback before publishing (web).** Browsers surface a media session
  only while the page is actually playing audible media, started from a user
  gesture. Attaching to an idle player on web produces no notification and no
  key routing until playback begins.

- **Raise `minSdkVersion` to 24 (Android).** The companion targets API 24, so a
  lower app fails the Gradle manifest merge outright. It also contributes
  `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK` and
  `POST_NOTIFICATIONS` for the notification-shade panel; opt out by registering
  the Android half yourself with `showNotification: false` before calling
  `attach`.
- **`detach()` on shutdown.** It releases the OS session; leaking one leaves
  the shell card on screen and makes the next `attach` throw `StateError`,
  since only one session may be live per app.

macOS needs an app bundle, iOS needs `UIBackgroundModes: audio` plus an active
`AVAudioSession`, Linux needs a D-Bus session bus. Full details, the
integration checklist and the per-backend verification status are in the
[`miniav_media_session` README](../miniav_media_session/README.md).

Unsupported platforms are not an error — `attach` succeeds and `isSupported`
tells you whether the shell accepted the session.
