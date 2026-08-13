## 0.1.0

- Initial release. `PlayerMediaSession.attach` binds a `MiniavPlayer` to the OS
  media session: publishes track, playback state and playhead, and routes
  play/pause/stop/seek commands back into the player.
- `next`/`previous` are advertised only when `onNext`/`onPrevious` callbacks are
  supplied — the player has no queue of its own.
- Polls the player (250 ms default) because `MiniavPlayer` exposes no change
  notification; commands arriving from the OS push immediately instead of
  waiting for the next tick.
- TRAP: `stop` maps to pause + seek(0). `MiniavPlayer` has no `stop()`.
