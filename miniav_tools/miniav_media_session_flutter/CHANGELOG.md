## 0.1.0

- Initial release. The Android half of `miniav_media_session`, over the
  framework `android.media.session.MediaSession` (API 21+, no androidx
  dependency).
- `registerMiniavMediaSessionAndroid()` routes Android through it and does
  nothing on other platforms; `miniav_media_session_player` calls it for you.
- Media buttons (hardware, headset, Bluetooth), lock-screen transport and the
  notification-shade media panel with album art and transport actions, all
  arriving at the same `MediaSession.Callback`.
- The panel is carried by a `mediaPlayback` foreground service, since Android
  removes an ongoing media notification without one as soon as the app leaves
  the foreground. The manifest adds `FOREGROUND_SERVICE`,
  `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `POST_NOTIFICATIONS` and the service
  declaration. `registerMiniavMediaSessionAndroid(showNotification: false)`
  keeps media buttons and the lock screen without the panel or the service.
- The notification can be dismissed while playback is paused.
- Not yet verified: written on Windows, never compiled or run on a device.
