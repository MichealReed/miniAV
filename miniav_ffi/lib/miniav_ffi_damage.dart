// Resolve this optional hand-written export in the existing native asset.
@ffi.DefaultAsset('package:miniav_ffi/miniav_ffi_bindings.dart')
library;

import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:miniav_platform_interface/miniav_platform_types.dart';

import 'miniav_ffi_bindings.dart' as bindings;

@ffi.Native<
  ffi.Uint32 Function(
    ffi.Pointer<bindings.MiniAVBuffer>,
    ffi.Pointer<ffi.Uint64>,
    ffi.Uint32,
  )
>(symbol: 'MiniAV_VideoBuffer_CopyDamage', isLeaf: true)
external int _copyDamage(
  ffi.Pointer<bindings.MiniAVBuffer> buffer,
  ffi.Pointer<ffi.Uint64> words,
  int capacity,
);

/// Copy the private native sidecar before the buffer can be released.
/// Older native libraries and all uncertified producers return absent metadata.
MiniAVVideoDamage? copyVideoDamage(ffi.Pointer<bindings.MiniAVBuffer> buffer) {
  if (!Platform.isWindows) return null;
  ffi.Pointer<ffi.Uint64> words = ffi.nullptr;
  try {
    final required = _copyDamage(buffer, ffi.nullptr, 0);
    // Six header words plus at most 256 bounded conservative rectangles.
    if (required < 6 || required > 1030 || (required - 6) % 4 != 0) {
      return null;
    }
    words = calloc<ffi.Uint64>(required);
    if (_copyDamage(buffer, words, required) != required) return null;
    final epoch = words[0];
    final generation = words[1];
    final width = words[2];
    final height = words[3];
    final full = words[4];
    final count = words[5];
    if (epoch <= 0 ||
        generation <= 0 ||
        width <= 0 ||
        height <= 0 ||
        full > 1 ||
        count != (required - 6) ~/ 4 ||
        (full == 0 && count == 0)) {
      return null;
    }
    final rectangles = <MiniAVDamageRect>[];
    for (var i = 0; i < count; i++) {
      final offset = 6 + i * 4;
      final x = words[offset];
      final y = words[offset + 1];
      final w = words[offset + 2];
      final h = words[offset + 3];
      if (x < 0 ||
          y < 0 ||
          w <= 0 ||
          h <= 0 ||
          x > width - w ||
          y > height - h) {
        return null;
      }
      rectangles.add(MiniAVDamageRect(x: x, y: y, width: w, height: h));
    }
    return MiniAVVideoDamage(
      sourceEpoch: epoch,
      generation: generation,
      width: width,
      height: height,
      fullFrame: full == 1,
      rectangles: rectangles,
    );
  } catch (_) {
    // Symbol resolution may fail when an older DLL is supplied by the host.
    return null;
  } finally {
    if (words != ffi.nullptr) calloc.free(words);
  }
}
