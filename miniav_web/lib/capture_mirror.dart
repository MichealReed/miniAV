/// The capture mirror's CONSUMER, on its own entry point.
///
/// 🔴 Separate from `miniav_web.dart` on purpose. That barrel is a Flutter web
/// plugin and pulls `package:flutter` in with it; this path is meant to be
/// drained from a WORKER, whose payload is compiled by dart2js with no Flutter
/// at all. Dart's import graph is per-LIBRARY, so importing this one costs
/// nothing but `dart:typed_data` — importing the barrel would not compile.
///
/// The producer is `MiniAV_Audio_SetCaptureMirror` in `miniav_c`; the wiring
/// that allocates the ring and attaches it is
/// `MiniAVWebAudioInputContext.openCaptureMirror`.
library;

export 'src/capture_mirror.dart'
    show CaptureMirrorReader, MirrorDrain, MirrorHeader;
