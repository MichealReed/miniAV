import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

class Demuxer {
  final PlatformDemuxer _platform;
  final String backendName;
  bool _closed = false;

  Demuxer(this._platform, this.backendName);

  bool get isClosed => _closed;

  /// Tracks discovered by probing the input.
  List<TrackInfo> get tracks => _platform.tracks;

  /// Read the next packet, or `null` at EOF.
  Future<EncodedPacket?> readPacket() {
    _checkOpen();
    return _platform.readPacket();
  }

  /// Seek to the given timestamp (microseconds).
  Future<void> seek(int timestampUs) {
    _checkOpen();
    return _platform.seek(timestampUs);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _platform.close();
  }

  void _checkOpen() {
    if (_closed) {
      throw StateError('Demuxer[$backendName] has been closed.');
    }
  }
}
