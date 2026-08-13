## 0.1.0

- Initial release. Supplies the Android half of `miniav_media_session` using
  the framework `android.media.session.MediaSession` (API 21+, no androidx
  dependency).
- `registerMiniavMediaSessionAndroid()` routes Android through it; a no-op on
  every other platform. `miniav_media_session_player` calls it for you.
- Media buttons (hardware, headset, Bluetooth), lock-screen transport, and the
  media panel in the notification shade with album art and transport actions.
- The shade panel is carried by a foreground service with
  `foregroundServiceType="mediaPlayback"`. An ongoing media notification that
  is not owned by one is killed as soon as the app leaves the foreground —
  exactly when the controls are still wanted.
- Manifest contributes `FOREGROUND_SERVICE`,
  `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `POST_NOTIFICATIONS` and the service
  declaration. Opt out with
  `registerMiniavMediaSessionAndroid(showNotification: false)`, which keeps
  media buttons and lock screen but drops the panel and the service.
- Notification buttons dispatch through the session's own transport controls,
  so they land in the same `MediaSession.Callback` as a hardware key rather
  than opening a second command path.
- TRAP: a paused session must report rate 0. At 1.0 the system extrapolates a
  playhead that is not moving.
- TRAP: the notification is ongoing only while playing. A permanently
  undismissable paused notification cannot be cleared without killing the app.
- TRAP: the service's static handle on the MediaSession must be cleared before
  teardown, or it keeps the session graph alive after the engine detaches.
- NOT VERIFIED: written on Windows, never compiled or run on a device.
