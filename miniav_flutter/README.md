# miniav_flutter

Flutter companion for [miniav](../miniav). Re-exports the full `miniav` API and adds a thin widget that automatically calls `MiniAV.dispose()` during Flutter hot reload — preventing the *"Callback invoked after it has been deleted"* fatal crash.

## Why this package exists

`miniav` uses long-lived `NativeCallable` function pointers for capture callbacks. During a Flutter hot reload the Dart isolate is torn down and rebuilt, but native capture threads keep running. If a thread fires a callback into a dead `NativeCallable` handle the VM aborts unconditionally — there is no way to recover.

`MiniAVBinding` is a `StatefulWidget` whose `reassemble()` calls `MiniAV.dispose()` before the isolate is rebuilt. This atomically disables the C-layer callback dispatch so native threads silently drop in-flight callbacks instead of crashing. The next call to any `startCapture` re-enables dispatch automatically.

## Installation

```yaml
dependencies:
  miniav_flutter: ^0.5.4
```

Use `miniav_flutter` **instead of** `miniav` — it re-exports everything, so no other imports need to change.

## Usage

Wrap your root widget with `MiniAVBinding` once in `main()`:

```dart
import 'package:miniav_flutter/miniav_flutter.dart';

void main() {
  runApp(const MiniAVBinding(child: MyApp()));
}
```

That is all that is required. All `MiniAV.*` APIs (`MiniCamera`, `MiniScreen`, `MiniAudioInput`, `MiniLoopback`, `MiniInput`, etc.) are available from the same `package:miniav_flutter/miniav_flutter.dart` import.

### Pure-Dart projects

If you are **not** using Flutter (e.g. a CLI tool or a Dart-only test), import `package:miniav/miniav.dart` directly and call `MiniAV.dispose()` manually when tearing down.

## API surface

Everything exported by `package:miniav/miniav.dart`, plus:

| Symbol | Description |
|--------|-------------|
| `MiniAVBinding` | Root widget — call `reassemble()` hook wires up `MiniAV.dispose()` |
