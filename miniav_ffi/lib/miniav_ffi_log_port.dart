/// Native-port delivery for the miniav C library's log stream.
///
/// `MiniAV_SetLogCallback` installs a **process-global** function pointer. A
/// Dart [NativeCallable] registered there is owned by exactly one isolate;
/// when that isolate exits the VM deletes the trampoline while the native
/// library still holds the pointer. The next `miniav_log()` from a capture or
/// worker thread — or from inside a leaf FFI call such as
/// `MiniAV_ReleaseBuffer` — then aborts the entire process
/// (`runtime_entry.cc: ... Callback invoked after it has been deleted` /
/// `... Cannot invoke native callback from a leaf call`). A whole-suite
/// `dart test` run hits this reliably, because every test file is a separate
/// isolate inside one VM process.
///
/// Posting to a Dart port is defined, silent and thread-safe even after the
/// port closes, so the port is the supported Dart delivery path. The
/// function-pointer API stays in the C library for non-Dart embedders, which
/// own their own function's lifetime.
///
/// These bindings live outside `miniav_ffi_bindings.dart` because that file
/// is ffigen output; the `@DefaultAsset` below re-attaches them to the same
/// `miniav_c` code asset.
@DefaultAsset('package:miniav_ffi/miniav_ffi_bindings.dart')
library;

import 'dart:ffi';

/// Initialises the native library's vendored Dart dynamic-linking API.
/// Returns `MINIAV_SUCCESS` (0) on success, `MINIAV_ERROR_NOT_SUPPORTED`
/// (-5) when the library was built without it. Idempotent.
@Native<Int Function(Pointer<Void>)>(symbol: 'MiniAV_InitDartApi')
external int miniavInitDartApi(Pointer<Void> initializeApiDLData);

/// Routes formatted native log lines to [port]. Pass 0 to stop delivery.
///
/// Messages arrive as `[int32 level, Uint8List utf8Message]`. The bytes are
/// copied into the message by the native side — nothing to free.
///
/// PROCESS-GLOBAL, LAST WRITER WINS across isolates.
@Native<Int Function(Int64)>(symbol: 'MiniAV_SetLogPort')
external int miniavSetLogPort(int port);
