# miniav_media_session_flutter

Android companion for [`miniav_media_session`](../miniav_media_session).

Android is the only platform whose media-session API cannot be reached from the
core package's code asset: `MediaSession` needs a `Context`, and the media
notification needs a foreground `Service`. Both are JVM-only. Windows SMTC and
Apple Now Playing are called over `dart:ffi`, Linux MPRIS is pure Dart, and web
is `navigator.mediaSession` — so this package exists for exactly one platform.

## Install

```yaml
dependencies:
  miniav_media_session: ^0.1.0
  miniav_media_session_flutter: ^0.1.0
```

**`minSdkVersion` must be at least 24.** This module targets API 24, so a lower
app fails the Gradle manifest merge with `uses-sdk:minSdkVersion N cannot be
smaller than version 24 declared in library`. Raise it in
`android/app/build.gradle`:

```groovy
android {
    defaultConfig {
        minSdkVersion 24
    }
}
```

Nothing else is required — the service and its permissions are declared in this
package's own manifest and merge into your app.

## Usage

```dart
registerMiniavMediaSessionAndroid();   // before create(), once at startup
final session = await MiniavMediaSession.create(appName: 'Tunes');
```

Using `miniav_media_session_player`? It registers this for you.

Registration is explicit because the core package is plain Dart and cannot
depend on this one — that would invert the dependency graph and pull the Flutter
SDK into a package that is deliberately usable from `dart test`.

## What you get

- Media buttons: hardware, headset and Bluetooth.
- Lock-screen transport controls.
- The media panel in the notification shade, with album art, title/artist, and
  play/pause plus previous/next when you declare those actions.
- Tapping the panel returns to the app.

The panel is carried by a foreground service, because an ongoing media
notification that is not owned by one is killed as soon as the app leaves the
foreground — which is exactly when you still want the controls.

## Options

```dart
registerMiniavMediaSessionAndroid(
  showNotification: false,             // media buttons + lock screen only
  notificationChannelName: 'Music',    // shown in Android notification settings
);
```

`showNotification: false` drops the shade panel and the service with it. Worth
considering if you would rather not ship the
`FOREGROUND_SERVICE_MEDIA_PLAYBACK` declaration below.

## Manifest contributions

This package's manifest merges the following into your app. Nothing further is
required from you — the service is declared here.

| Entry | Why |
|---|---|
| `FOREGROUND_SERVICE` | start the service that owns the notification |
| `FOREGROUND_SERVICE_MEDIA_PLAYBACK` | required *in addition* from Android 14; without it `startForeground` throws |
| `POST_NOTIFICATIONS` | declared so your app *can* request it — declaring grants nothing |
| `<service …foregroundServiceType="mediaPlayback">` | the service itself, not exported |

`POST_NOTIFICATIONS` is a runtime permission and requesting it needs an
Activity, so it stays your call. Media-session notifications are generally
exempt from it; the declaration is here so apps that do prompt are not blocked
by a missing entry.

This inheritance is the reason Android lives in a separate package: an app that
only wants a now-playing card on desktop, or that uses `miniav_player` without
a media session, never takes these on.

## Behaviour worth knowing

**The notification is dismissible while paused, ongoing while playing.** A
permanently undismissable paused notification is one the user cannot get rid of
without killing the app.

**Notification buttons take the same path as hardware keys.** They fire
PendingIntents into the service, which forwards them to the session's transport
controls — landing in the same `MediaSession.Callback` a headset button does.
One route from "user pressed something" to Dart; a second would drift.

**A paused session reports rate 0.** At 1.0 the system extrapolates a playhead
that is not moving.

**Uses the framework `MediaSession`, not androidx.media3.** A now-playing card
should not drag a media-playback library into every app that wants one.

## Status

Written but **never compiled or run on a device**. An Android build and an
on-device check are the gate before trusting any of this.
