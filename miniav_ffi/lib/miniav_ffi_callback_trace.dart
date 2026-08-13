/// TRACING FOR `NativeCallable` LIFETIME BUGS.
///
/// Closing a `NativeCallable` that native code can still invoke aborts the
/// whole process:
///
///     runtime_entry.cc: error: Callback invoked after it has been deleted.
///     ... isolate=(nil)
///
/// It is uncatchable and prints no Dart stack, so the usual debugging move —
/// find out who did it — is not available. When several packages hand
/// callbacks to native threads, narrowing it down is guesswork unless the
/// closes announce themselves.
///
/// Set `MINIAV_TRACE_CALLBACKS=1` and every close in this package prints to
/// **stderr** (not the log port: during a Flutter hot reload the isolate is
/// paused at a safepoint, so port messages are not delivered until after the
/// window in which the crash happens — stderr is written synchronously and
/// survives).
///
/// Read the output as an ordering: the last `[miniav-cb] close` before the
/// abort is the prime suspect. If the abort arrives with NO close line before
/// it, this package did not delete the callback and the culprit is elsewhere.
library;

import 'dart:io';

final bool _tracing =
    Platform.environment['MINIAV_TRACE_CALLBACKS'] == '1';

/// Announces that a [NativeCallable] is about to be closed. [what] should name
/// the callback precisely enough to act on — module plus role.
void traceCallbackClose(String what) {
  if (!_tracing) return;
  stderr.writeln('[miniav-cb] close $what');
}

/// Announces a native-thread callback registration, so the trace shows what
/// was live before a close.
void traceCallbackOpen(String what) {
  if (!_tracing) return;
  stderr.writeln('[miniav-cb] open  $what');
}
