part of '../miniav_web.dart';

/// Web stub for [MiniInputPlatformInterface].
///
/// Real keyboard/mouse capture on the web is intentionally not implemented;
/// only gamepads are exposed (via the Gamepad API). Most apps should listen
/// for input through the DOM directly. This stub exists so that
/// `MiniAVPlatformInterface` is fully implemented on web.
class MiniAVWebInputPlatform implements MiniInputPlatformInterface {
  @override
  Future<List<MiniAVDeviceInfo>> enumerateGamepads() async {
    final out = <MiniAVDeviceInfo>[];
    try {
      final pads = web.window.navigator.getGamepads().toDart;
      for (var i = 0; i < pads.length; i++) {
        final p = pads[i];
        if (p == null) continue;
        out.add(
          MiniAVDeviceInfo(deviceId: p.id, name: p.id, isDefault: out.isEmpty),
        );
      }
    } catch (_) {}
    return out;
  }

  @override
  Future<MiniInputContextPlatformInterface> createContext() async {
    throw UnsupportedError(
      'MiniInput contexts are not supported on the web platform.',
    );
  }

  @override
  void Function() addGamepadChangeListener(
    MiniAVDeviceChangeListener listener,
  ) {
    void connHandler(JSAny? event) {
      try {
        final ge = event as web.GamepadEvent;
        final pad = ge.gamepad;
        listener(
          MiniAVDeviceChangeNotification(
            MiniAVDeviceChangeEvent.added,
            MiniAVDeviceInfo(deviceId: pad.id, name: pad.id, isDefault: false),
          ),
        );
      } catch (_) {}
    }

    void disconnHandler(JSAny? event) {
      try {
        final ge = event as web.GamepadEvent;
        final pad = ge.gamepad;
        listener(
          MiniAVDeviceChangeNotification(
            MiniAVDeviceChangeEvent.removed,
            MiniAVDeviceInfo(deviceId: pad.id, name: pad.id, isDefault: false),
          ),
        );
      } catch (_) {}
    }

    final connJs = connHandler.toJS;
    final disconnJs = disconnHandler.toJS;
    web.window.addEventListener('gamepadconnected', connJs);
    web.window.addEventListener('gamepaddisconnected', disconnJs);
    return () {
      web.window.removeEventListener('gamepadconnected', connJs);
      web.window.removeEventListener('gamepaddisconnected', disconnJs);
    };
  }
}
