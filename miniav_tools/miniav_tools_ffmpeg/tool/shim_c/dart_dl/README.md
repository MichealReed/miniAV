# Vendored Dart API dynamic linking headers

Verbatim copies of `include/` from the Dart SDK
(`dart_api.h`, `dart_api_dl.c`, `dart_api_dl.h`, `dart_native_api.h`,
`dart_version.h`, `internal/dart_api_dl_impl.h`).

Copyright the Dart project authors; BSD-style license (header retained in
every file).

They are vendored so this native build can call `Dart_PostCObject_DL` and
deliver process-global log lines to a Dart **native port** instead of a
`NativeCallable` function pointer. A stale function pointer left behind by an
exited isolate aborts the VM; posting to a closed port is defined, silent and
thread-safe.

Update procedure: re-copy from `<dart-sdk>/include` — do not hand-edit.
