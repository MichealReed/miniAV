// ABI size guard.
//
// REGRESSION: MiniAVInputConfig grew three appended motion fields in C
// (48 -> 64 bytes) while lib/miniav_ffi_bindings.dart still described the
// 48-byte shape. `calloc<MiniAVInputConfig>()` therefore handed C a 48-byte
// allocation and `input_api.c`'s `ctx->config = *config;` copied 64 bytes out
// of it — 16 bytes of unrelated heap landing in motion_rate_hz / motion_mode /
// motion_callback, the last of which C calls as a function pointer.
//
// "Fields were APPENDED so offsets are unchanged" does not save you: callers
// allocate by sizeof(), and sizeof() changed. So assert sizeof() itself, for
// every struct that crosses the boundary, driven by the C-side table so a new
// C struct cannot be silently left unchecked on the Dart side.

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:miniav_ffi/miniav_ffi_bindings.dart' as bindings;
import 'package:test/test.dart';

/// Dart's sizeOf for every struct named in the C ABI table.
/// Keys MUST match the C struct names in miniav_c/src/common/miniav_abi.c.
final Map<String, int> dartStructSizes = {
  'MiniAVDeviceInfo': ffi.sizeOf<bindings.MiniAVDeviceInfo>(),
  'MiniAVVideoInfo': ffi.sizeOf<bindings.MiniAVVideoInfo>(),
  'MiniAVAudioInfo': ffi.sizeOf<bindings.MiniAVAudioInfo>(),
  'MiniAVLoopbackTargetInfo': ffi.sizeOf<bindings.MiniAVLoopbackTargetInfo>(),
  'MiniAVKeyboardEvent': ffi.sizeOf<bindings.MiniAVKeyboardEvent>(),
  'MiniAVMouseEvent': ffi.sizeOf<bindings.MiniAVMouseEvent>(),
  'MiniAVGamepadEvent': ffi.sizeOf<bindings.MiniAVGamepadEvent>(),
  'MiniAVVec3': ffi.sizeOf<bindings.MiniAVVec3>(),
  'MiniAVQuat': ffi.sizeOf<bindings.MiniAVQuat>(),
  'MiniAVMotionEvent': ffi.sizeOf<bindings.MiniAVMotionEvent>(),
  'MiniAVInputConfig': ffi.sizeOf<bindings.MiniAVInputConfig>(),
  'MiniAVVideoPlane': ffi.sizeOf<bindings.MiniAVVideoPlane>(),
  'MiniAVBuffer': ffi.sizeOf<bindings.MiniAVBuffer>(),
  'MiniAVNativeBufferInternalPayload':
      ffi.sizeOf<bindings.MiniAVNativeBufferInternalPayload>(),
  // Anonymous in C, so ffigen names them UnnamedUnion*/UnnamedStruct*. Checked
  // individually because two compensating errors inside the payload union
  // would leave sizeof(MiniAVBuffer) matching. MiniAVBuffer's own trailing
  // member — the hand-written _MiniAVNativeFence — is private to the bindings
  // and is pinned by MiniAVBuffer's total plus these three.
  'MiniAVLoopbackTargetInfo.TARGETHANDLE': ffi.sizeOf<bindings.UnnamedUnion1>(),
  'MiniAVBuffer.data': ffi.sizeOf<bindings.UnnamedUnion2>(),
  'MiniAVBuffer.data.video': ffi.sizeOf<bindings.UnnamedStruct1>(),
  'MiniAVBuffer.data.audio': ffi.sizeOf<bindings.UnnamedStruct2>(),
};

int cSizeOf(String name) {
  final namePtr = name.toNativeUtf8();
  try {
    return bindings.MiniAV_ABI_StructSize(namePtr.cast<ffi.Char>());
  } finally {
    calloc.free(namePtr);
  }
}

List<String> cStructNames() {
  final count = bindings.MiniAV_ABI_StructCount();
  return [
    for (var i = 0; i < count; i++)
      bindings.MiniAV_ABI_StructNameAt(i).cast<Utf8>().toDartString(),
  ];
}

void main() {
  group('FFI struct ABI', () {
    test('every C struct in the ABI table is checked by Dart', () {
      final fromC = cStructNames();
      expect(fromC, isNotEmpty, reason: 'native ABI table failed to load');
      expect(
        fromC.toSet().difference(dartStructSizes.keys.toSet()),
        isEmpty,
        reason:
            'C added a struct to the ABI table with no Dart size assertion. '
            'Add it to dartStructSizes (and to miniav_ffi_bindings.dart).',
      );
      expect(
        dartStructSizes.keys.toSet().difference(fromC.toSet()),
        isEmpty,
        reason:
            'Dart names a struct the C ABI table does not know — typo, or the '
            'struct was removed from miniav_abi.c.',
      );
    });

    test('unknown struct name reports 0 (so a typo cannot pass silently)', () {
      expect(cSizeOf('MiniAVNoSuchStruct'), 0);
    });

    for (final name in dartStructSizes.keys) {
      test('sizeOf<$name> matches C sizeof', () {
        final c = cSizeOf(name);
        expect(c, greaterThan(0), reason: '$name missing from the C ABI table');
        expect(
          dartStructSizes[name],
          c,
          reason:
              'Dart $name is ${dartStructSizes[name]} bytes, C is $c. A field '
              'was added to the C struct without regenerating/updating '
              'lib/miniav_ffi_bindings.dart. Every calloc<$name>() is now '
              'under-sized and any `*dst = *src;` in C reads past its end.',
        );
      });
    }

    // The concrete instance this guard was written for. Motion capture is not
    // wired on the FFI backend, so the appended trio must be present AND inert:
    // a null motion_callback is what stops input_api.c calling it.
    test('MiniAVInputConfig carries the appended motion trio, zeroed', () {
      if (ffi.sizeOf<ffi.Pointer<ffi.Void>>() == 8) {
        // The exact number this regression was about: 48 before the motion
        // fields reached the Dart side, 64 after.
        expect(ffi.sizeOf<bindings.MiniAVInputConfig>(), 64);
      }
      final cfg = calloc<bindings.MiniAVInputConfig>();
      try {
        expect(cfg.ref.motion_rate_hz, 0);
        expect(cfg.ref.motion_modeAsInt, 0);
        expect(cfg.ref.motion_callback, ffi.nullptr);
      } finally {
        calloc.free(cfg);
      }
    });
  });
}
