/// Web selection for the worker-hosted audio track.
///
/// The implementation lives with the pieces it composes — the AudioWorklet sink
/// and the audio worker are both in miniav_tools_codecs, and that package has a
/// browser harness that can be given shared memory to test it in. This file is
/// only the web half of the conditional import in `player.dart`; see
/// worker_audio_stub.dart for the native half.
library;

export 'package:miniav_tools_codecs/web.dart' show WorkerAudioTrack;
