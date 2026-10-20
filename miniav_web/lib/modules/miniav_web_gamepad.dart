part of '../miniav_web.dart';

/// Standard Gamepad layout -> the existing canonical XInput-shaped event.
/// Unknown layouts are left unmapped. No device identifiers enter the samples.
final class _WebGamepadCapture {
  final _latest = <int, MiniAVGamepadEvent>{};
  Timer? _timer;
  void Function(MiniAVGamepadEvent, Object?)? _emit;
  Object? _userData;
  int _generation = 0;

  MiniAVGamepadEvent? snapshot(int index) => _latest[index];

  void start(
    int hz,
    void Function(MiniAVGamepadEvent, Object?)? emit,
    Object? userData,
  ) {
    stop();
    _emit = emit;
    _userData = userData;
    final generation = _generation;
    try {
      _poll();
      if (_generation != generation) return;
      _timer = Timer.periodic(
        Duration(microseconds: 1000000 ~/ (hz <= 0 ? 60 : hz.clamp(1, 120))),
        (_) {
          if (_generation != generation) return;
          try {
            _poll();
          } catch (_) {
            if (_generation != generation) return;
            try {
              _disconnected();
            } finally {
              if (_generation == generation) stop();
            }
          }
        },
      );
    } catch (_) {
      if (_generation == generation) stop();
      throw UnsupportedError('Gamepad capture is unavailable');
    }
  }

  void _poll() {
    final next = <int, MiniAVGamepadEvent>{};
    final now = _WebUtils._getCurrentTimestampUs();
    if (web.document.visibilityState == 'visible') {
      final pads = web.window.navigator.getGamepads().toDart;
      for (var i = 0; i < math.min(pads.length, 16); i++) {
        final pad = pads[i];
        if (pad == null ||
            !pad.connected ||
            pad.mapping != 'standard' ||
            pad.index != i) {
          continue;
        }
        final axes = pad.axes.toDart, buttons = pad.buttons.toDart;
        double axis(int index) {
          final v = index < axes.length ? axes[index].toDartDouble : 0.0;
          return v.isFinite ? v.clamp(-1.0, 1.0).toDouble() : 0;
        }

        int stick(double value) =>
            (value * (value < 0 ? 32768 : 32767)).round();
        int trigger(int index) {
          final v = index < buttons.length ? buttons[index].value : 0.0;
          return v.isFinite ? (v.clamp(0.0, 1.0) * 255).round() : 0;
        }

        // W3C standard indices; Home remains OS-owned, triggers stay analog.
        const bits = [
          0x1000,
          0x2000,
          0x4000,
          0x8000,
          0x100,
          0x200,
          0,
          0,
          0x20,
          0x10,
          0x40,
          0x80,
          1,
          2,
          4,
          8,
        ];
        var pressed = 0;
        for (var b = 0; b < math.min(buttons.length, bits.length); b++) {
          if (buttons[b].pressed) pressed |= bits[b];
        }
        next[i] = MiniAVGamepadEvent(
          timestampUs: now,
          gamepadIndex: i,
          connected: true,
          buttons: pressed,
          leftStickX: stick(axis(0)),
          leftStickY: stick(-axis(1)),
          rightStickX: stick(axis(2)),
          rightStickY: stick(-axis(3)),
          leftTrigger: trigger(6),
          rightTrigger: trigger(7),
        );
      }
    }
    final events = <MiniAVGamepadEvent>[
      for (final e in next.entries)
        if (!_same(_latest[e.key], e.value)) e.value,
      for (final slot in _latest.keys)
        if (!next.containsKey(slot)) _gone(slot, now),
    ];
    _latest
      ..clear()
      ..addAll(next);
    final generation = _generation;
    for (final event in events) {
      if (_generation != generation) break;
      _emit?.call(event, _userData);
    }
  }

  void _disconnected() {
    final slots = _latest.keys.toList();
    _latest.clear();
    final generation = _generation, now = _WebUtils._getCurrentTimestampUs();
    for (final slot in slots) {
      if (_generation != generation) break;
      _emit?.call(_gone(slot, now), _userData);
    }
  }

  static MiniAVGamepadEvent _gone(int slot, int now) => MiniAVGamepadEvent(
    timestampUs: now,
    gamepadIndex: slot,
    connected: false,
    buttons: 0,
    leftStickX: 0,
    leftStickY: 0,
    rightStickX: 0,
    rightStickY: 0,
    leftTrigger: 0,
    rightTrigger: 0,
  );
  static bool _same(MiniAVGamepadEvent? a, MiniAVGamepadEvent b) =>
      a != null &&
      a.buttons == b.buttons &&
      a.leftStickX == b.leftStickX &&
      a.leftStickY == b.leftStickY &&
      a.rightStickX == b.rightStickX &&
      a.rightStickY == b.rightStickY &&
      a.leftTrigger == b.leftTrigger &&
      a.rightTrigger == b.rightTrigger;

  void stop() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _emit = null;
    _userData = null;
    _latest.clear();
  }
}
