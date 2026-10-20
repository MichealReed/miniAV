/// Re-resolving a display target across a topology change.
///
/// A display device id is a live platform handle — on Windows literally an
/// HMONITOR pointer. Windows destroys its monitor objects and issues new ones
/// on every topology change, which is the exact family of losses the recorder
/// re-acquires from: Win+P, dock/undock, a mode change, an RDP transition.
/// Re-acquiring against the id the track was built with therefore asks for a
/// monitor that no longer exists, and keeps asking, while the physical display
/// sits there attached and capturable under a new handle.
///
/// That is not hypothetical. A recorded Win+P test spent ten seconds failing
/// on `HMONITOR:0x000000001C8507A1` — three re-configures, then stage rebuilds
/// — against a display that was present the whole time.
///
/// Every case below is a statement about what the enumeration says, so none of
/// them need a display to physically unplug.
@TestOn('vm')
library;

import 'package:miniav/miniav.dart';
import 'package:miniav_recorder/src/recorder.dart';
import 'package:test/test.dart';

MiniAVDeviceInfo _d(String id, String name, {bool primary = false}) =>
    MiniAVDeviceInfo(deviceId: id, name: name, isDefault: primary);

/// The two displays of the recorded session, before Win+P.
final _before = [
  _d('HMONITOR:0x000000001C8507A1', r'\\.\DISPLAY1', primary: true),
  _d('HMONITOR:0x000000000B2211C4', r'\\.\DISPLAY2'),
];

/// The same two displays after Win+P settles: same names, new handles.
final _after = [
  _d('HMONITOR:0x00000000771A0033', r'\\.\DISPLAY1', primary: true),
  _d('HMONITOR:0x00000000E40C9A18', r'\\.\DISPLAY2'),
];

void main() {
  group('resolveDeviceTarget', () {
    test('a live id resolves to itself', () {
      expect(
        resolveDeviceTarget(
          requestedId: 'HMONITOR:0x000000001C8507A1',
          knownName: r'\\.\DISPLAY1',
          devices: _before,
        ),
        'HMONITOR:0x000000001C8507A1',
      );
    });

    test('a live id wins over the name, so stable-id platforms never '
        'take the name path', () {
      // Two entries share a name. If the name were consulted first this would
      // be ambiguous and refuse; the id is present, so it is simply used.
      final duplicated = [
        _d('portal_display', 'Screen (select via Portal)', primary: true),
        _d('portal_display_2', 'Screen (select via Portal)'),
      ];
      expect(
        resolveDeviceTarget(
          requestedId: 'portal_display',
          knownName: 'Screen (select via Portal)',
          devices: duplicated,
        ),
        'portal_display',
      );
    });

    test('after Win+P the same display resolves to its NEW handle', () {
      expect(
        resolveDeviceTarget(
          requestedId: 'HMONITOR:0x000000001C8507A1',
          knownName: r'\\.\DISPLAY1',
          devices: _after,
        ),
        'HMONITOR:0x00000000771A0033',
      );
    });

    test('resolves the display that was asked for, not the primary', () {
      // The recorded session captured the primary. A recorder that re-resolved
      // by "the default display" would keep working there and look correct
      // while silently recording something else, so pin the opposite case: the
      // requested display is the SECOND one and stays the second one.
      expect(
        resolveDeviceTarget(
          requestedId: 'HMONITOR:0x000000000B2211C4',
          knownName: r'\\.\DISPLAY2',
          devices: _after,
        ),
        'HMONITOR:0x00000000E40C9A18',
      );
    });

    test('a display that is not attached resolves to null, not a substitute',
        () {
      // Win+P "Second screen only": DISPLAY1 is gone entirely. DISPLAY2 is
      // right there and is NOT an answer to this question.
      expect(
        resolveDeviceTarget(
          requestedId: 'HMONITOR:0x000000001C8507A1',
          knownName: r'\\.\DISPLAY1',
          devices: [_after[1]],
        ),
        isNull,
      );
    });

    test('an outage resolves to null while it lasts and to the new handle '
        'when it ends', () {
      const requested = 'HMONITOR:0x000000001C8507A1';
      const name = r'\\.\DISPLAY1';
      String? at(List<MiniAVDeviceInfo> devices) => resolveDeviceTarget(
            requestedId: requested,
            knownName: name,
            devices: devices,
          );

      expect(at(_before), requested, reason: 'before the change');
      expect(at([_before[1]]), isNull, reason: 'mid-transition, display gone');
      expect(at(const []), isNull, reason: 'both displays momentarily gone');
      expect(at(_after), 'HMONITOR:0x00000000771A0033', reason: 'settled');
    });

    test('an id never seen alive is handed back unchanged', () {
      // Nothing to re-resolve BY. Returning null would report "not attached"
      // about a display this has no grounds to claim anything about; the
      // configure attempt gives the platform's own error instead.
      expect(
        resolveDeviceTarget(
          requestedId: 'HMONITOR:0xDEADBEEF',
          knownName: null,
          devices: _after,
        ),
        'HMONITOR:0xDEADBEEF',
      );
    });

    test('an empty known name is treated as no name', () {
      // Some platforms leave the name blank. Matching on '' would pair the
      // target with every other nameless display.
      expect(
        resolveDeviceTarget(
          requestedId: 'gone',
          knownName: '',
          devices: [_d('other', '')],
        ),
        'gone',
      );
    });

    test('an ambiguous name refuses rather than picking one', () {
      // The name has stopped identifying a single display. Choosing between
      // them would be choosing what the file is a recording of.
      expect(
        resolveDeviceTarget(
          requestedId: 'HMONITOR:0x000000001C8507A1',
          knownName: r'\\.\DISPLAY1',
          devices: [
            _d('HMONITOR:0xAAA', r'\\.\DISPLAY1', primary: true),
            _d('HMONITOR:0xBBB', r'\\.\DISPLAY1'),
          ],
        ),
        isNull,
      );
    });

    test('an empty enumeration with a known name means not attached', () {
      expect(
        resolveDeviceTarget(
          requestedId: 'HMONITOR:0x000000001C8507A1',
          knownName: r'\\.\DISPLAY1',
          devices: const [],
        ),
        isNull,
      );
    });
  });

  _driftTests();

  group('CaptureTargetUnavailable', () {
    test('carries the message plainly, with no exception noise', () {
      // It is logged during a normal outage, so it reads as a sentence rather
      // than as "Exception: ...".
      const e = CaptureTargetUnavailable(r'display \\.\DISPLAY1 is not attached');
      expect('$e', r'display \\.\DISPLAY1 is not attached');
      expect(e, isA<Exception>());
    });
  });
}

/// The check that separates a still desktop from a stale capture.
///
/// Both deliver nothing. Only one of them is bound to a display that has since
/// changed shape or gone away, and asking is what turns a ten second wait into
/// a three second one.
void _driftTests() {
  const name = r'\.\DISPLAY1';

  group('displayDriftReason', () {
    test('a display that still matches is not drifting', () {
      expect(
        displayDriftReason(
          display: name,
          attached: true,
          deliveredW: 5120,
          deliveredH: 1440,
          currentW: 5120,
          currentH: 1440,
        ),
        isNull,
      );
    });

    test('a display that changed shape under the capture is', () {
      // The recorded first case: Win+P took 5120x1440 to 3840x1440, WGC
      // delivered a few frames and then stopped without reporting anything.
      final why = displayDriftReason(
        display: name,
        attached: true,
        deliveredW: 5120,
        deliveredH: 1440,
        currentW: 3840,
        currentH: 1440,
      );
      expect(why, isNotNull);
      expect(why, contains('3840x1440'));
      expect(why, contains('5120x1440'));
    });

    test('height alone moving is caught, with the width unchanged', () {
      expect(
        displayDriftReason(
          display: name,
          attached: true,
          deliveredW: 3840,
          deliveredH: 2160,
          currentW: 3840,
          currentH: 1080,
        ),
        isNotNull,
      );
    });

    test('a detached display needs no measurements at all', () {
      // Win+P "second screen only". Nothing to compare, and nothing to wait
      // for either.
      expect(
        displayDriftReason(
          display: name,
          attached: false,
          deliveredW: 0,
          deliveredH: 0,
          currentW: 0,
          currentH: 0,
        ),
        contains('no longer attached'),
      );
    });

    test('a capture that has delivered nothing yet is not judged', () {
      // Otherwise every track is "drifting" for the moment between start and
      // its first frame.
      expect(
        displayDriftReason(
          display: name,
          attached: true,
          deliveredW: 0,
          deliveredH: 0,
          currentW: 5120,
          currentH: 1440,
        ),
        isNull,
      );
    });

    test('a display reporting 0x0 is a dead handle, not a match', () {
      // GetMonitorInfo failing leaves the size at zero — which is how a stale
      // HMONITOR answers. It is emphatically not "same as delivered".
      expect(
        displayDriftReason(
          display: name,
          attached: true,
          deliveredW: 5120,
          deliveredH: 1440,
          currentW: 0,
          currentH: 0,
        ),
        contains('no size at all'),
      );
    });
  });
}
