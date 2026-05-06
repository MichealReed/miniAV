import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

/// User-facing wrapper around a [PlatformEncoder]. Adds:
/// * which backend produced it (`backendName`)
/// * lifecycle guards (cannot use after [close])
class Encoder {
  final PlatformEncoder _platform;
  final String backendName;
  bool _closed = false;

  Encoder(this._platform, this.backendName);

  /// `true` if [close] has been called.
  bool get isClosed => _closed;

  /// Underlying [PlatformEncoder]. Exposed so callers that need backend-
  /// specific bridging interfaces (e.g. `FfmpegEncoderBridge` for direct
  /// muxer wiring) can downcast. Most users should not touch this.
  PlatformEncoder get platform => _platform;

  /// Submit one frame for encoding. Returns the encoded packet for that
  /// frame, or `null` if the encoder is buffering. Always call [flush] at
  /// end-of-stream.
  Future<EncodedPacket?> encode(FrameSource frame) {
    _checkOpen();
    return _platform.encode(frame);
  }

  /// Drain any internally buffered packets at end-of-stream.
  Future<List<EncodedPacket>> flush() {
    _checkOpen();
    return _platform.flush();
  }

  /// Force the next encoded frame to be a keyframe.
  Future<void> requestKeyframe() {
    _checkOpen();
    return _platform.requestKeyframe();
  }

  /// Codec extra-data needed by muxers (SPS/PPS, etc.). May be `null` until
  /// the first packet has been emitted.
  CodecExtraData? get extraData => _platform.extraData;

  /// Release encoder resources. Safe to call multiple times.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _platform.close();
  }

  void _checkOpen() {
    if (_closed) {
      throw StateError('Encoder[$backendName] has been closed.');
    }
  }
}
