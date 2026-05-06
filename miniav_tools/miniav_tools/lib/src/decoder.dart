import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

class Decoder {
  final PlatformDecoder _platform;
  final String backendName;
  bool _closed = false;

  Decoder(this._platform, this.backendName);

  bool get isClosed => _closed;

  Future<DecodedFrame?> decode(EncodedPacket packet) {
    _checkOpen();
    return _platform.decode(packet);
  }

  Future<List<DecodedFrame>> flush() {
    _checkOpen();
    return _platform.flush();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _platform.close();
  }

  void _checkOpen() {
    if (_closed) {
      throw StateError('Decoder[$backendName] has been closed.');
    }
  }
}
