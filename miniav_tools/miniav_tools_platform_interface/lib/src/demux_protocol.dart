/// Wire types shared by every worker-hosted demuxer.
///
/// The host and the worker exchange `spawn` messages, and `spawn` carries only
/// portable values (primitives, typed data, lists and string-keyed maps of
/// them) or types with a byte encoding. `TrackInfo` and `EncodedPacket` are
/// neither, so they get one here.
///
/// That looks like extra work next to `Isolate.spawn`, which would deep-copy
/// them for free — but the free version is native-only, and it is the reason
/// the demuxer protocol could never be reused anywhere else. It lives here,
/// beside the types it encodes, because BOTH hosts need it: the FFmpeg
/// demuxer on an isolate and the container demuxer in a Web Worker speak the
/// same protocol, and there is no reason for two copies of it.
///
/// Encoding also makes the protocol legible to a C or wasm host later, and
/// makes a version skew between host and worker a `FormatException` instead
/// of a cast error deep inside a decode loop.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:spawn/spawn.dart';

import 'codec_types.dart';
import 'config.dart';
import 'packet.dart';

/// Type ids. Local to this protocol; ids are per-application.
const int kTracksTypeId = 0x0D01;
const int kPacketTypeId = 0x0D02;

/// Registers this protocol's decoders. Named by the worker entry so `spawn`
/// runs it on BOTH ends — a registry belongs to one isolate, so a registration
/// the host makes does not exist in the worker.
void registerDemuxProtocol() {
  WireRegistry.instance
    ..register(kTracksTypeId, TracksMessage.decode)
    ..register(kPacketTypeId, PacketMessage.decode);
}

/// The demuxer's opening answer: what it found in the container.
class TracksMessage implements WireMessage {
  const TracksMessage(this.tracks, this.durationUs, this.isSeekable);

  final List<TrackInfo> tracks;
  final int? durationUs;
  final bool isSeekable;

  @override
  int get typeId => kTracksTypeId;

  @override
  Uint8List encode() {
    final w = _Writer();
    final duration = durationUs;
    w.u8(duration == null ? 0 : 1);
    if (duration != null) w.i64(duration);
    w.u8(isSeekable ? 1 : 0);
    w.u16(tracks.length);
    for (final track in tracks) {
      switch (track) {
        case VideoTrackInfo():
          w
            ..u8(0)
            ..str(track.codec.name)
            ..u32(track.width)
            ..u32(track.height)
            ..u32(track.frameRateNumerator)
            ..u32(track.frameRateDenominator)
            ..i64(track.rotationDegrees)
            ..extra(track.extraData);
        case AudioTrackInfo():
          w
            ..u8(1)
            ..str(track.codec.name)
            ..u32(track.sampleRate)
            ..u32(track.channels)
            ..extra(track.extraData);
      }
    }
    return w.take();
  }

  static TracksMessage decode(Uint8List bytes) {
    final r = _Reader(bytes);
    final durationUs = r.u8() == 1 ? r.i64() : null;
    final isSeekable = r.u8() == 1;
    final count = r.u16();
    final tracks = <TrackInfo>[];
    for (var i = 0; i < count; i++) {
      switch (r.u8()) {
        case 0:
          tracks.add(
            VideoTrackInfo(
              codec: VideoCodec.values.byName(r.str()),
              width: r.u32(),
              height: r.u32(),
              frameRateNumerator: r.u32(),
              frameRateDenominator: r.u32(),
              rotationDegrees: r.i64(),
              extraData: r.extra(),
            ),
          );
        case 1:
          tracks.add(
            AudioTrackInfo(
              codec: AudioCodec.values.byName(r.str()),
              sampleRate: r.u32(),
              channels: r.u32(),
              extraData: r.extra(),
            ),
          );
        default:
          throw const FormatException('demux protocol: unknown track kind');
      }
    }
    return TracksMessage(tracks, durationUs, isSeekable);
  }
}

/// One demuxed packet. EOF is `null` rather than an empty packet, so the
/// caller cannot mistake one for the other.
class PacketMessage implements WireMessage {
  const PacketMessage(this.packet);

  final EncodedPacket packet;

  @override
  int get typeId => kPacketTypeId;

  @override
  Uint8List encode() {
    final w = _Writer()
      ..i64(packet.ptsUs)
      ..i64(packet.dtsUs)
      ..i64(packet.durationUs)
      ..u8(packet.isKeyframe ? 1 : 0)
      ..u32(packet.trackIndex)
      ..bytes(packet.data);
    return w.take();
  }

  static PacketMessage decode(Uint8List bytes) {
    final r = _Reader(bytes);
    final ptsUs = r.i64();
    final dtsUs = r.i64();
    final durationUs = r.i64();
    final isKeyframe = r.u8() == 1;
    final trackIndex = r.u32();
    return PacketMessage(
      EncodedPacket(
        data: r.bytes(),
        ptsUs: ptsUs,
        dtsUs: dtsUs,
        durationUs: durationUs,
        isKeyframe: isKeyframe,
        trackIndex: trackIndex,
      ),
    );
  }
}

class _Writer {
  final BytesBuilder _out = BytesBuilder(copy: false);
  final Uint8List _scratch = Uint8List(8);
  late final ByteData _view = ByteData.sublistView(_scratch);

  void u8(int v) => _out.addByte(v);

  void u16(int v) {
    _view.setUint16(0, v, Endian.little);
    _out.add(Uint8List.fromList(_scratch.sublist(0, 2)));
  }

  void u32(int v) {
    _view.setUint32(0, v, Endian.little);
    _out.add(Uint8List.fromList(_scratch.sublist(0, 4)));
  }

  /// A 64-bit signed value as two 32-bit halves plus a sign byte.
  ///
  /// NOT `ByteData.setInt64`: dart2js has no Int64 accessor and throws on it,
  /// so a protocol built on one works on the VM and dies in a browser — which
  /// is the failure this file exists to prevent, not to demonstrate.
  void i64(int v) {
    final negative = v < 0;
    final magnitude = negative ? -v : v;
    final high = magnitude ~/ 0x100000000;
    u32(magnitude - high * 0x100000000);
    u32(high);
    u8(negative ? 1 : 0);
  }

  void str(String v) {
    final encoded = utf8.encode(v);
    u16(encoded.length);
    _out.add(encoded);
  }

  void bytes(Uint8List v) {
    u32(v.length);
    _out.add(v);
  }

  void extra(CodecExtraData? v) {
    if (v == null) {
      u8(0);
      return;
    }
    final video = v.videoCodec;
    u8(1);
    if (video != null) {
      u8(0);
      str(video.name);
    } else {
      u8(1);
      str(v.audioCodec!.name);
    }
    bytes(v.bytes);
  }

  Uint8List take() => _out.takeBytes();
}

class _Reader {
  _Reader(this._bytes) : _view = ByteData.sublistView(_bytes);

  final Uint8List _bytes;
  final ByteData _view;
  int _offset = 0;

  void _need(int n) {
    if (_offset + n > _bytes.lengthInBytes) {
      throw FormatException(
        'demux protocol: truncated message (wanted $n bytes at $_offset of '
        '${_bytes.lengthInBytes})',
      );
    }
  }

  int u8() {
    _need(1);
    return _view.getUint8(_offset++);
  }

  int u16() {
    _need(2);
    final v = _view.getUint16(_offset, Endian.little);
    _offset += 2;
    return v;
  }

  int u32() {
    _need(4);
    final v = _view.getUint32(_offset, Endian.little);
    _offset += 4;
    return v;
  }

  int i64() {
    final low = u32();
    final high = u32();
    final negative = u8() == 1;
    final magnitude = high * 0x100000000 + low;
    return negative ? -magnitude : magnitude;
  }

  String str() {
    final length = u16();
    _need(length);
    final v = utf8.decode(
      Uint8List.sublistView(_bytes, _offset, _offset + length),
    );
    _offset += length;
    return v;
  }

  Uint8List bytes() {
    final length = u32();
    _need(length);
    // A copy, not a view: the caller keeps this past the frame's lifetime, and
    // a view would pin the whole message buffer for every packet.
    final v = Uint8List.fromList(
      Uint8List.sublistView(_bytes, _offset, _offset + length),
    );
    _offset += length;
    return v;
  }

  CodecExtraData? extra() {
    if (u8() == 0) return null;
    final isVideo = u8() == 0;
    final name = str();
    final payload = bytes();
    return isVideo
        ? CodecExtraData.video(VideoCodec.values.byName(name), payload)
        : CodecExtraData.audio(AudioCodec.values.byName(name), payload);
  }
}
