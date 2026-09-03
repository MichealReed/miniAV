/// Selects the backend for the current compilation target.
///
/// `dart.library.ffi` is true on the VM and false on web; `dart.library.js_interop`
/// is the reverse. The first matching condition wins, so native gets the FFI
/// backend, web gets `navigator.mediaSession`, and anything else falls back to
/// the honest no-op. This is a compile-time choice — the web backend is never
/// tree-shaken into a native build and `dart:ffi` is never imported on web.
library;

export 'backend_factory_unsupported.dart'
    if (dart.library.ffi) 'backend_factory_ffi.dart'
    if (dart.library.js_interop) 'backend_factory_web.dart';
