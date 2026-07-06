/// Abstract platform classes implemented by backends.
library;

import 'dart:typed_data';

import 'package:miniav_platform_interface/miniav_platform_types.dart';

import 'config.dart';
import 'frame_source.dart';
import 'packet.dart';

/// Abstract video/audio encoder. Backends return a concrete subclass from
/// [MiniAVToolsBackend.createEncoder].
///
/// Lifecycle:
///   create → encode* (zero or more) → flush → close
abstract class PlatformEncoder {
  /// Submit one frame for encoding. Returns the encoded packet for that
  /// frame, or `null` if the encoder is buffering (e.g. for B-frames or
  /// hardware lookahead). Always call [flush] at end-of-stream to drain any
  /// remaining buffered packets.
  Future<EncodedPacket?> encode(FrameSource frame);

  /// Drain any internally buffered packets. Returns them in DTS order.
  /// Call once at end-of-stream.
  Future<List<EncodedPacket>> flush();

  /// Force the next encoded frame to be a keyframe (IDR for H.264).
  Future<void> requestKeyframe();

  /// Codec extra-data (SPS/PPS, codec-private) for muxer track headers.
  /// May be `null` until the first packet has been emitted.
  CodecExtraData? get extraData;

  /// Release encoder resources.
  Future<void> close();

  /// Whether this encoder can accept GPU buffer input via an out-of-band
  /// path (bypassing the normal [FrameSource] pipeline).  When `true` the
  /// recorder can hand a caller-owned GPU buffer directly to the encoder
  /// without a CPU round-trip.  Default: `false`.
  bool get supportsGpuBufferInput => false;

  /// Whether this encoder consumes pre-converted planar YUV420P (I420) frames
  /// directly (`FrameSource.yuv420p`) without an internal RGBA→YUV conversion.
  /// When `true`, the recorder's GPU-downscale + CPU-readback path can convert
  /// to YUV420P on the GPU and read back the smaller planes instead of RGBA.
  /// Encoders that need a different input layout (e.g. NV12 for a CPU-fed HW
  /// encoder) should leave this `false`.  Default: `false`.
  bool get acceptsYuv420pPlanes => false;
}

/// Abstract audio encoder. Backends return a concrete subclass from
/// [MiniAVToolsBackend.createAudioEncoder].
///
/// Lifecycle:
///   create → encode* → flush → close
///
/// PCM data is supplied per call (not at construction) so a single encoder
/// can transparently accept whichever interleaved PCM layout miniav
/// delivers — the implementation handles deinterleave / sample-format
/// conversion as needed by the underlying codec.
abstract class PlatformAudioEncoder {
  /// Submit interleaved PCM samples for encoding.
  ///
  /// - [pcm]:        raw bytes; size must equal `frameCount * channels *
  ///                 bytesPerSample(format)`.
  /// - [format]:     sample format describing [pcm] (u8/s16/s32/f32).
  /// - [frameCount]: samples per channel in [pcm].
  /// - [ptsUs]:      presentation timestamp of the FIRST sample, microseconds.
  ///
  /// Returns zero or more encoded packets; one input chunk may emit several
  /// codec packets when the codec frame size is smaller than [frameCount],
  /// or none when buffering across chunks.
  Future<List<EncodedPacket>> encode({
    required Uint8List pcm,
    required MiniAVAudioFormat format,
    required int frameCount,
    required int ptsUs,
  });

  /// Flush any internally buffered samples + emit trailing packets.
  Future<List<EncodedPacket>> flush();

  /// Codec extra-data (e.g. ASC for AAC, OpusHead for Opus). May be `null`
  /// until the first packet has been emitted.
  CodecExtraData? get extraData;

  /// Release encoder resources.
  Future<void> close();
}

///
/// Lifecycle:
///   create → decode* → flush → close
abstract class PlatformDecoder {
  /// Submit one encoded packet. Returns a [DecodedFrame] when one is ready,
  /// or `null` if the decoder is buffering (e.g. waiting for B-frame
  /// dependencies).
  Future<DecodedFrame?> decode(EncodedPacket packet);

  /// Drain any internally buffered frames at end-of-stream.
  Future<List<DecodedFrame>> flush();

  /// Release decoder resources.
  Future<void> close();
}

/// A decoded frame. Backends may return CPU bytes or GPU handles depending on
/// [DecoderConfig.requestGpuOutput].
abstract class DecodedFrame {
  int get width;
  int get height;
  int get ptsUs;

  /// Backend-specific accessor: returns CPU bytes if available.
  /// May trigger GPU→CPU readback if the frame is GPU-resident.
  Future<List<int>> readBytes();

  /// Release the decoded frame. Always call when done.
  void close();
}

/// Abstract container muxer.
///
/// Lifecycle:
///   create → writeHeader → writePacket* → finish → close
abstract class PlatformMuxer {
  /// Write the container header. Must be called once before any packets.
  /// Track [extraData] from [TrackInfo] is consulted here.
  Future<void> writeHeader();

  /// Write one encoded packet. Packets must be in DTS order per track but
  /// may be interleaved across tracks.
  Future<void> writePacket(EncodedPacket packet);

  /// Finalise the container (write trailing index, MOOV, etc.).
  /// For [BytesMuxerOutput], retrieve the bytes via [getBytes] after calling.
  Future<void> finish();

  /// Only valid for [BytesMuxerOutput].
  List<int>? getBytes() => null;

  /// Release muxer resources.
  Future<void> close();
}

/// Abstract container demuxer.
///
/// Lifecycle:
///   create → trackInfos (probe) → readPacket* → close
abstract class PlatformDemuxer {
  /// Tracks discovered by probing the input. Available after construction.
  List<TrackInfo> get tracks;

  /// Read the next packet from any track. Returns `null` at EOF.
  Future<EncodedPacket?> readPacket();

  /// Seek to the given timestamp (microseconds). Some containers/codecs only
  /// support keyframe-accurate seeking.
  Future<void> seek(int timestampUs);

  /// Release demuxer resources.
  Future<void> close();
}
