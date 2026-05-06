/// Public entry point for the miniav_tools platform interface.
///
/// Application code should depend on `miniav_tools` (the facade) rather than
/// this package directly. Backend authors implement [MiniAVToolsBackend].
library;

export 'src/backend.dart';
export 'src/backend_context.dart';
export 'src/codec_types.dart';
export 'src/config.dart';
export 'src/exceptions.dart';
export 'src/frame_source.dart';
export 'src/packet.dart';
export 'src/platform.dart';
export 'src/platform_codec.dart';

// Re-export commonly used miniav types so users don't need a second import.
export 'package:miniav_platform_interface/miniav_platform_types.dart'
    show
        MiniAVPixelFormat,
        MiniAVAudioFormat,
        MiniAVBuffer,
        MiniAVBufferContentType,
        MiniAVBufferType,
        MiniAVVideoBuffer,
        MiniAVAudioBuffer,
        MiniAVNativeFence;
