/// Isolate-hosted software video encoder.
///
/// [FfmpegSoftwareEncoder] performs its libav calls (`avcodec_send_frame` /
/// `avcodec_receive_packet`) synchronously on the calling isolate. On the
/// recorder's software-fallback path that isolate is the Flutter UI isolate,
/// and a 2560×720 openh264/SVT encode takes tens of milliseconds per frame —
/// the app visibly freezes while recording.
///
/// [IsolateSoftwareEncoder] wraps the exact same encoder in a long-lived
/// worker isolate: frames cross as [TransferableTypedData] (one copy, then
/// zero-copy ownership transfer), packets come back the same way, and the UI
/// isolate only pays the transfer cost (~1 ms/frame at 720p) instead of the
/// encode cost. The encoder is stateful and confined to the worker, so libav
/// is always called from a single thread.
///
/// This package is native-only (it imports `dart:ffi` throughout), so using
/// `dart:isolate` here does not affect web builds — the web backend lives in
/// `miniav_tools_web`.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:miniav_platform_interface/miniav_platform_types.dart';
import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

import 'ffmpeg_bindings.dart' show ensureFFmpegLoaded;
import 'ffmpeg_encoder.dart';
import 'ffmpeg_log.dart';

/// Software encoder hosted on a dedicated worker isolate. Public API is
/// identical to [FfmpegSoftwareEncoder]; construction is async ([open]).
class IsolateSoftwareEncoder implements PlatformEncoder {
  IsolateSoftwareEncoder._(this._isolate, this._toWorker, this._fromWorker);

  final Isolate _isolate;
  final SendPort _toWorker;
  final ReceivePort _fromWorker;

  final Map<int, Completer<List<dynamic>>> _pending = {};
  int _nextId = 0;
  bool _closed = false;
  bool _forceKeyframe = false;
  CodecExtraData? _extraData;
  VideoCodec? _codec;

  /// Spawns the worker isolate, loads FFmpeg there, and opens the software
  /// encoder for [cfg]. Throws [CodecInitException] if the worker fails to
  /// open the encoder.
  static Future<IsolateSoftwareEncoder> open(EncoderConfig cfg) async {
    final fromWorker = ReceivePort();
    final handshake = Completer<List<dynamic>>();

    late final IsolateSoftwareEncoder self;
    fromWorker.listen((dynamic msg) {
      final list = msg as List;
      if (!handshake.isCompleted) {
        handshake.complete(list);
        return;
      }
      final id = list[1] as int;
      self._pending.remove(id)?.complete(list);
    });

    final Isolate isolate;
    try {
      isolate = await Isolate.spawn(
        _workerMain,
        [fromWorker.sendPort, cfg],
        debugName: 'IsolateSoftwareEncoder(${cfg.codec.name})',
        errorsAreFatal: true,
      );
    } catch (e) {
      fromWorker.close();
      throw CodecInitException('ffmpeg-sw-isolate', 'isolate spawn failed: $e');
    }

    final ready = await handshake.future;
    if (ready[0] != 'ready') {
      fromWorker.close();
      isolate.kill(priority: Isolate.immediate);
      throw CodecInitException('ffmpeg-sw-isolate', ready[1] as String);
    }

    self = IsolateSoftwareEncoder._(
      isolate,
      ready[1] as SendPort,
      fromWorker,
    );
    self._codec = cfg.codec;
    final extra = ready[2] as TransferableTypedData?;
    if (extra != null) {
      self._extraData = CodecExtraData.video(
        cfg.codec,
        extra.materialize().asUint8List(),
      );
    }
    ffmpegToolsLog(
      MiniAVLogLevel.info,
      '[ffmpeg-sw-isolate] worker ready for ${cfg.codec} '
      '${cfg.width}x${cfg.height} (extraData: '
      '${self._extraData?.bytes.length ?? 0}B)',
    );
    return self;
  }

  Future<List<dynamic>> _request(List<dynamic> msg) {
    if (_closed) {
      throw const CodecRuntimeException('ffmpeg-sw-isolate', 'encoder closed');
    }
    final id = _nextId++;
    final completer = Completer<List<dynamic>>();
    _pending[id] = completer;
    _toWorker.send([msg[0], id, ...msg.sublist(1)]);
    return completer.future;
  }

  void _absorbExtra(TransferableTypedData? extra) {
    if (extra == null || _extraData != null) return;
    _extraData = CodecExtraData.video(
      _codec,
      extra.materialize().asUint8List(),
    );
  }

  EncodedPacket? _unpackPacket(List<dynamic> reply) {
    if (reply[0] == 'err') {
      throw CodecRuntimeException('ffmpeg-sw-isolate', reply[2] as String);
    }
    _absorbExtra(reply.length > 7 ? reply[7] as TransferableTypedData? : null);
    if (reply[2] as bool != true) return null;
    return EncodedPacket(
      data: (reply[3] as TransferableTypedData).materialize().asUint8List(),
      ptsUs: reply[4] as int,
      dtsUs: reply[5] as int,
      durationUs: reply[6] as int,
      isKeyframe: reply.length > 8 ? reply[8] as bool : false,
    );
  }

  @override
  Future<EncodedPacket?> encode(FrameSource frame) async {
    final forceKey = _forceKeyframe;
    _forceKeyframe = false;
    switch (frame) {
      case Yuv420pFrameSource():
        // One copy into a transferable, then zero-copy hand-off — required
        // anyway because the recorder's plane buffers are reused per frame.
        final payload = TransferableTypedData.fromList([
          frame.yPlane,
          frame.uPlane,
          frame.vPlane,
        ]);
        return _unpackPacket(
          await _request([
            'encode',
            'yuv',
            frame.width,
            frame.height,
            payload,
            0,
            const <int>[],
            forceKey,
          ]),
        );
      case CpuFrameSource():
        return _unpackPacket(
          await _request([
            'encode',
            'cpu',
            frame.width,
            frame.height,
            TransferableTypedData.fromList([frame.bytes]),
            frame.pixelFormat.index,
            frame.strideBytes ?? const <int>[],
            forceKey,
          ]),
        );
      case MiniAVBufferSource():
        final video = frame.buffer.data;
        if (video is! MiniAVVideoBuffer ||
            video.planes.isEmpty ||
            video.planes[0] == null) {
          throw const CodecRuntimeException(
            'ffmpeg-sw-isolate',
            'MiniAVBufferSource: only CPU plane bytes are supported by the '
                'software encoder (plane[0] was null — likely a GPU buffer)',
          );
        }
        return _unpackPacket(
          await _request([
            'encode',
            'cpu',
            video.width,
            video.height,
            TransferableTypedData.fromList([video.planes[0]!]),
            video.pixelFormat.index,
            video.strideBytes,
            forceKey,
          ]),
        );
      default:
        throw CodecRuntimeException(
          'ffmpeg-sw-isolate',
          'unsupported FrameSource: ${frame.runtimeType}',
        );
    }
  }

  @override
  Future<List<EncodedPacket>> flush() async {
    final reply = await _request(['flush']);
    if (reply[0] == 'err') {
      throw CodecRuntimeException('ffmpeg-sw-isolate', reply[2] as String);
    }
    final datas = (reply[2] as List).cast<TransferableTypedData>();
    final metas = (reply[3] as List).cast<List>();
    return [
      for (var i = 0; i < datas.length; i++)
        EncodedPacket(
          data: datas[i].materialize().asUint8List(),
          ptsUs: metas[i][0] as int,
          dtsUs: metas[i][1] as int,
          durationUs: metas[i][2] as int,
          isKeyframe: metas[i][3] as bool,
        ),
    ];
  }

  @override
  Future<void> requestKeyframe() async => _forceKeyframe = true;

  @override
  CodecExtraData? get extraData => _extraData;

  @override
  bool get supportsGpuBufferInput => false;

  // Same contract as FfmpegSoftwareEncoder: YUV420P planes are consumed
  // directly (the worker feeds them straight into the AVFrame).
  @override
  bool get acceptsYuv420pPlanes => true;

  @override
  Future<void> close() async {
    if (_closed) return;
    try {
      await _request(['close']);
    } catch (_) {
      // Worker may already be gone; proceed with teardown.
    }
    _closed = true;
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(
          const CodecRuntimeException('ffmpeg-sw-isolate', 'encoder closed'),
        );
      }
    }
    _pending.clear();
    _fromWorker.close();
    _isolate.kill(priority: Isolate.beforeNextEvent);
  }
}

/// Worker-isolate entry point. args = [SendPort toMain, EncoderConfig cfg].
Future<void> _workerMain(List<dynamic> args) async {
  final toMain = args[0] as SendPort;
  final cfg = args[1] as EncoderConfig;

  FfmpegSoftwareEncoder enc;
  try {
    final loaded = await ensureFFmpegLoaded();
    if (!loaded) {
      toMain.send(['error', 'FFmpeg failed to load in worker isolate']);
      return;
    }
    enc = FfmpegSoftwareEncoder.open(cfg);
  } catch (e) {
    toMain.send(['error', 'software encoder open failed: $e']);
    return;
  }

  final commands = ReceivePort();
  toMain.send([
    'ready',
    commands.sendPort,
    enc.extraData != null
        ? TransferableTypedData.fromList([enc.extraData!.bytes])
        : null,
  ]);

  var extraSent = enc.extraData != null;
  TransferableTypedData? pendingExtra() {
    if (extraSent || enc.extraData == null) return null;
    extraSent = true;
    return TransferableTypedData.fromList([enc.extraData!.bytes]);
  }

  await for (final dynamic raw in commands) {
    final msg = raw as List;
    final op = msg[0] as String;
    final id = msg[1] as int;
    try {
      switch (op) {
        case 'encode':
          final kind = msg[2] as String;
          final w = msg[3] as int;
          final h = msg[4] as int;
          final payload = (msg[5] as TransferableTypedData)
              .materialize()
              .asUint8List();
          final pixFmtIndex = msg[6] as int;
          final strides = (msg[7] as List).cast<int>();
          final forceKey = msg[8] as bool;
          if (forceKey) await enc.requestKeyframe();

          final FrameSource src;
          if (kind == 'yuv') {
            final ySize = w * h;
            final uvSize = (w ~/ 2) * (h ~/ 2);
            src = FrameSource.yuv420p(
              yPlane: Uint8List.sublistView(payload, 0, ySize),
              uPlane: Uint8List.sublistView(payload, ySize, ySize + uvSize),
              vPlane: Uint8List.sublistView(
                payload,
                ySize + uvSize,
                ySize + 2 * uvSize,
              ),
              width: w,
              height: h,
            );
          } else {
            src = FrameSource.cpu(
              bytes: payload,
              pixelFormat: MiniAVPixelFormat.values[pixFmtIndex],
              width: w,
              height: h,
              strideBytes: strides.isEmpty ? null : strides,
            );
          }
          final pkt = await enc.encode(src);
          toMain.send([
            'pkt',
            id,
            pkt != null,
            pkt != null ? TransferableTypedData.fromList([pkt.data]) : null,
            pkt?.ptsUs ?? 0,
            pkt?.dtsUs ?? 0,
            pkt?.durationUs ?? 0,
            pendingExtra(),
            pkt?.isKeyframe ?? false,
          ]);
        case 'flush':
          final pkts = await enc.flush();
          toMain.send([
            'pkts',
            id,
            [
              for (final p in pkts) TransferableTypedData.fromList([p.data]),
            ],
            [
              for (final p in pkts)
                [p.ptsUs, p.dtsUs, p.durationUs, p.isKeyframe],
            ],
          ]);
        case 'close':
          try {
            await enc.close();
          } catch (_) {}
          toMain.send(['closed', id, true]);
          commands.close();
          return;
        default:
          toMain.send(['err', id, 'unknown op: $op']);
      }
    } catch (e) {
      toMain.send(['err', id, e.toString()]);
    }
  }
}
