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
    ffi.Pointer<ffi.Uint32>,
    ffi.Pointer<ffi.Uint32>,
  )
>(symbol: 'MiniAV_VideoBuffer_GetColor', isLeaf: true)
external int _getColor(
  ffi.Pointer<bindings.MiniAVBuffer> buffer,
  ffi.Pointer<ffi.Uint32> matrix,
  ffi.Pointer<ffi.Uint32> fullRange,
);

/// Two words reused for every frame: [matrix, fullRange].
ffi.Pointer<ffi.Uint32>? _words;

/// Set when the native library predates the export, so a missing symbol
/// costs one failed lookup rather than one per frame.
bool _unavailable = false;

/// The frame's YUV matrix and range, read before the buffer can be released.
/// Null when the producer does not say, or the native library is older.
MiniAVVideoColor? copyVideoColor(ffi.Pointer<bindings.MiniAVBuffer> buffer) {
  if (!Platform.isWindows || _unavailable) return null;
  try {
    final words = _words ??= calloc<ffi.Uint32>(2);
    if (_getColor(buffer, words, words + 1) != 1) return null;
    final matrix = switch (words[0]) {
      1 => MiniAVYuvMatrix.bt601,
      2 => MiniAVYuvMatrix.bt709,
      3 => MiniAVYuvMatrix.bt2020,
      _ => null,
    };
    if (matrix == null) return null;
    return MiniAVVideoColor(matrix: matrix, fullRange: words[1] == 1);
  } catch (_) {
    // Symbol resolution fails when an older DLL is supplied by the host.
    _unavailable = true;
    return null;
  }
}
