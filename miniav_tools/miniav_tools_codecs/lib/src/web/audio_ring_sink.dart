/// A web audio sink whose samples are delivered by the audio thread itself.
///
/// The browser renders audio on a realtime thread. Every other sink we have
/// puts the main thread in the middle of that: decoded PCM is pushed into a
/// device buffer by whoever is running the pump, so a main thread busy with
/// Flutter build and raster work is a main thread that is not refilling the
/// device, and a device that runs dry clicks.
///
/// This sink removes the main thread from the path entirely. Samples live in a
/// [SharedAudioRing] — shared memory — and an `AudioWorklet` reads them on the
/// audio thread. Whoever fills the ring can be a Worker. Once [open] returns,
/// the main thread is not involved in playback again: it can block for as long
/// as the ring holds audio and nothing is heard.
///
/// It needs `SharedArrayBuffer`, so it needs a cross-origin-isolated page
/// (COOP: same-origin, COEP: require-corp). Without that, [open] returns null
/// and the caller keeps its existing sink — this is an upgrade, never a
/// requirement.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';
import 'package:web/web.dart' as web;

/// Default depth. The margin a stalled producer gets before anything is heard,
/// and the latency added to a seek — 400 ms buys a very large Flutter hitch for
/// 150 kB of stereo memory.
const Duration kDefaultRingDepth = Duration(milliseconds: 400);

/// The worklet's registered processor name. Must match the `registerProcessor`
/// call in miniav_audio_ring_worklet.js.
const String _kProcessor = 'miniav-audio-ring';

/// Where the worklet module is served from in a Flutter app.
const String kWorkletAssetUrl =
    'assets/packages/miniav_tools_codecs/web/miniav_audio_ring_worklet.js';

/// An `AudioWorklet` playing from shared memory.
class AudioRingSink {
  AudioRingSink._(this._context, this._node, this._gain, this.ring);

  final web.AudioContext _context;
  final web.AudioWorkletNode _node;
  final web.GainNode _gain;

  /// The ring to fill. Hand [SharedAudioRing.shareable] to the producer thread
  /// and rebuild it there with `SharedAudioRing.attach`.
  ///
  /// EXACTLY ONE thread may write to it. The ring is single-producer by
  /// construction, and a second writer corrupts audio silently.
  final SharedAudioRing ring;

  bool _closed = false;

  /// Opens a sink for [sampleRate]/[channels], or returns null when this page
  /// cannot host one.
  ///
  /// Null covers a page that is not cross-origin isolated (no shared memory to
  /// play from), a browser without `AudioWorklet`, and a worklet module that
  /// will not load. Every one of them means "keep the sink you have".
  ///
  /// The context is created AT [sampleRate] so the browser resamples to the
  /// device rate for us; feeding a 44.1 kHz stream to a 48 kHz device otherwise
  /// plays it slightly sharp.
  ///
  /// [workletUrl] exists so a test can serve the module from its own tree.
  static Future<AudioRingSink?> open({
    required int sampleRate,
    required int channels,
    Duration depth = kDefaultRingDepth,
    String workletUrl = kWorkletAssetUrl,
  }) async {
    if (sampleRate <= 0 || channels <= 0) return null;

    final ring = SharedAudioRing.allocate(
      capacityFrames: (depth.inMicroseconds * sampleRate) ~/ 1000000,
      channels: channels,
      sampleRate: sampleRate,
    );
    // No shared memory means the worklet would be reading a buffer the
    // producer's writes never reach. Better to decline than to play silence.
    if (!ring.isSharedAcrossThreads) return null;

    web.AudioContext? context;
    try {
      context = web.AudioContext(
        web.AudioContextOptions(sampleRate: sampleRate.toDouble()),
      );

      // Verify the browser actually HONOURED the requested rate.
      //
      // Asking for a rate is a request, not a guarantee: WebKit ties an
      // AudioContext to the hardware audio session and has historically run at
      // the device rate regardless of what was asked for. The failure that
      // buys is silent and total — samples produced for 48 kHz fed to a
      // 44.1 kHz context play about 9% sharp, for the whole stream, with
      // nothing anywhere reporting a problem. Declining costs us the
      // off-thread path on that device and keeps playback correct, which is
      // the right way round.
      if (context.sampleRate.round() != sampleRate) {
        await context.close().toDart;
        return null;
      }

      // `audioWorklet` is undefined on a browser without it, and reading
      // `.addModule` off undefined throws into the catch below — but say so
      // explicitly, because "no AudioWorklet" and "the module failed to load"
      // are different problems and only one of them is a bug worth chasing.
      if (!context.has('audioWorklet')) {
        await context.close().toDart;
        return null;
      }
      await context.audioWorklet.addModule(workletUrl).toDart;

      // Verify the DESTINATION can actually carry the channel count — the
      // same request-is-not-a-guarantee reasoning as the sample-rate check
      // above. A worklet emitting 6 channels into a stereo-capped
      // destination gets silently down-mixed (or worse, per-browser,
      // dropped), so decline and let the caller fall back to stereo rather
      // than play a mix whose centre may be gone.
      if (channels > context.destination.maxChannelCount) {
        await context.close().toDart;
        return null;
      }

      final node = web.AudioWorkletNode(
        context,
        _kProcessor,
        web.AudioWorkletNodeOptions(
          numberOfInputs: 0,
          numberOfOutputs: 1,
          outputChannelCount: <int>[channels].jsify()! as JSArray<JSNumber>,
          processorOptions: _processorOptions(ring),
        ),
      );
      final gain = web.GainNode(context);
      node.connect(gain);
      if (channels > 2) {
        // Surround: address the destination's channels DISCRETELY, in the
        // worklet's emitted order. The default 'speakers' interpretation
        // would run the Web Audio up/down-mix matrix over what is already a
        // finished speaker feed.
        context.destination.channelCount = channels;
        context.destination.channelInterpretation = 'discrete';
        gain.channelCount = channels;
        gain.channelCountMode = 'explicit';
        gain.channelInterpretation = 'discrete';
      }
      gain.connect(context.destination);

      // Autoplay policy: a context created before a user gesture starts
      // suspended. Resuming is best effort — if it is refused the sink still
      // works and starts when the page resumes it.
      unawaited(context.resume().toDart.then<void>((_) {}, onError: (_) {}));

      return AudioRingSink._(context, node, gain, ring);
    } on Object {
      try {
        await context?.close().toDart;
      } on Object {
        // Nothing to salvage; the caller falls back.
      }
      return null;
    }
  }

  /// The shared buffer, handed to the worklet through its constructor options.
  ///
  /// `processorOptions` is structured-cloned into the worklet scope, and a
  /// `SharedArrayBuffer` clones by SHARING — which is exactly what is wanted
  /// and is why it must never appear in a transfer list.
  static JSObject _processorOptions(SharedAudioRing ring) {
    final options = JSObject();
    options.setProperty('buffer'.toJS, ring.shareable as JSAny);
    return options;
  }

  /// Frames the audio thread wanted and could not have. Non-zero means the
  /// producer fell behind — the one number worth alerting on.
  int get underruns => ring.underruns;

  /// How much audio is buffered: the margin a stalled producer still has.
  Duration get buffered => ring.buffered;

  /// Output gain, 0..1. A `GainNode` rather than scaling samples, so volume
  /// costs the producer nothing and changes take effect without touching the
  /// ring.
  double get volume => _gain.gain.value;
  set volume(double value) => _gain.gain.value = value;

  /// The rate the audio graph is actually running at. Equal to the ring's
  /// sample rate by construction — [open] declines rather than return a sink
  /// where these differ, because that difference is a pitch shift.
  int get contextSampleRate => _context.sampleRate.round();

  /// Whether the audio context is running (an unresumed context is silent).
  bool get isRunning => _context.state == 'running';

  /// Suspends the audio thread: it stops calling the worklet, so it stops
  /// consuming.
  ///
  /// This is the whole of pause. The producer needs no telling — with nothing
  /// draining the ring it fills, and the producer blocks on backpressure. It is
  /// also what makes a seek safe, by removing the consumer that a ring clear
  /// would otherwise race.
  Future<void> suspend() async {
    try {
      await _context.suspend().toDart;
    } on Object {
      // Already suspended or already closed.
    }
  }

  /// Resumes a context the autoplay policy or [suspend] stopped. Safe to call
  /// at any time; call it from a user gesture if [isRunning] is false.
  Future<void> resume() async {
    try {
      await _context.resume().toDart;
    } on Object {
      // Still suspended; the caller can retry from a gesture.
    }
  }

  /// Stops the worklet and releases the audio context.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      // Ask the processor to return false so the node is collected, THEN tear
      // the graph down; disconnecting first can leave it running silently.
      _node.port.postMessage('stop'.toJS);
      _node.disconnect();
      _gain.disconnect();
    } on Object {
      // Already gone.
    }
    try {
      await _context.close().toDart;
    } on Object {
      // Already closed.
    }
  }
}
