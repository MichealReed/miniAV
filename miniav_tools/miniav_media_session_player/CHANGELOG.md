## 0.1.0

- Initial release. `PlayerMediaSession.attach` binds a `MiniavPlayer` to the OS
  media session: it publishes the track, playback state and playhead, and routes
  play/pause/stop/seek commands back into the player.
- `next`/`previous` are offered only when `onNext`/`onPrevious` callbacks are
  supplied; the player has no queue of its own.
- The player is polled (every 250 ms by default) because `MiniavPlayer` has no
  change notifications; commands from the OS are applied immediately.
- `stop` pauses and seeks to the start, since `MiniavPlayer` has no `stop()`.
