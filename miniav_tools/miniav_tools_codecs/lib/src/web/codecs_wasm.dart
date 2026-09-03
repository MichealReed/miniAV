/// Loader + low-level bindings for the `miniav_tools_codecs` WASM module — the
/// general web twin of `codecs_native.dart`, with libopus compiled to
/// WebAssembly via Emscripten. Opus is the first codec exposed; more portable
/// codecs can be added to the same module (see native/CMakeLists.txt).
///
/// The Emscripten glue is a MODULARIZE build (`EXPORT_NAME=MiniavCodecs`), so
/// the module is an INSTANCE object returned by a factory — NOT a global
/// `Module` — which lets it coexist with `miniav_web`'s own global-`Module`
/// wasm. Exports are reached off the instance (`module._miniav_opus_*`,
/// `module.HEAPU8/HEAPF32`). Pure synchronous opus_encode/decode → no ASYNCIFY /
/// AudioWorklet / shared memory, so this needs NO crossOriginIsolated.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// libopus `OPUS_APPLICATION_*` (kept in sync with codecs_native.dart).
const int kOpusApplicationAudio = 2049;

/// Process-wide singleton over the codecs wasm module.
class CodecsWasm {
  CodecsWasm._();
  static final CodecsWasm instance = CodecsWasm._();

  static const _glueUrl =
      'assets/packages/miniav_tools_codecs/web/miniav_codecs.js';

  JSObject? _m;
  Future<void>? _loading;

  bool get isReady => _m != null;

  /// Load the wasm module once. Safe to await repeatedly. Throws on load
  /// failure — callers should treat that as "wasm opus unavailable" and fall
  /// back (return null from the backend factories).
  Future<void> ensureLoaded() {
    if (_m != null) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    final g = globalContext;
    // Inject the glue script once; it installs the global `MiniavCodecs` factory.
    if (g.getProperty<JSAny?>('MiniavCodecs'.toJS).isUndefinedOrNull) {
      if (g.getProperty<JSAny?>('document'.toJS).isUndefinedOrNull) {
        // Worker scope: no DOM, no <script> injection — but
        // `importScripts` exists and is synchronous. `_glueUrl` is
        // page-relative; a worker's relative URLs resolve against the WORKER
        // SCRIPT's location (assets/packages/.../workers/build/x.dart.js), so
        // recover the app base from it: everything up to its own '/assets/'.
        g.callMethodVarArgs<JSAny?>(
            'importScripts'.toJS, [_workerGlueUrl().toJS]);
      } else {
        final loaded = Completer<void>();
        final script = web.HTMLScriptElement()
          ..src = _glueUrl
          ..async = true;
        script.onload = (() {
          if (!loaded.isCompleted) loaded.complete();
        }).toJS;
        script.onerror = ((JSAny _) {
          if (!loaded.isCompleted) {
            loaded.completeError(StateError('failed to load $_glueUrl'));
          }
        }).toJS;
        web.document.head!.appendChild(script);
        await loaded.future;
      }
    }
    // Call the MODULARIZE factory → Promise<module instance>.
    //
    // 🔴 `locateFile` is REQUIRED, not a nicety: the factory resolves
    // `miniav_codecs.wasm` against Emscripten's internal `scriptDirectory`,
    // which in a WORKER comes from the worker script's own location — not the
    // corrected `importScripts` URL — so the wasm fetch 404'd
    // ("wasm streaming compile failed: HTTP status code is not ok", then
    // "BufferSource argument is empty" abort) even though the glue loaded
    // fine. Resolve every module file against this package's asset dir
    // explicitly, in both scopes.
    final factory = g.getProperty<JSFunction>('MiniavCodecs'.toJS);
    final assetDir = _assetDirUrl();
    final config = JSObject();
    config.setProperty(
      'locateFile'.toJS,
      ((JSString path, JSString _) => '$assetDir${path.toDart}'.toJS).toJS,
    );
    final promise =
        factory.callAsFunction(null, config) as JSPromise<JSObject>;
    _m = await promise.toDart;
  }

  /// This package's asset directory, resolved for the CURRENT scope: page-
  /// relative on the main thread; against the app base recovered from the
  /// worker script's URL (everything up to its own `/assets/`) in a worker.
  static String _assetDirUrl() {
    const rel = 'assets/packages/miniav_tools_codecs/web/';
    if (!globalContext.getProperty<JSAny?>('document'.toJS).isUndefinedOrNull) {
      return rel;
    }
    final loc = globalContext
        .getProperty<JSObject>('location'.toJS)
        .getProperty<JSString>('href'.toJS)
        .toDart;
    final i = loc.lastIndexOf('/assets/');
    if (i < 0) return rel;
    return '${loc.substring(0, i + 1)}$rel';
  }

  /// [_glueUrl] resolved for a worker scope: against the app base recovered
  /// from the worker script's own URL (`self.location.href`), assuming the
  /// Flutter convention that all assets — including the running worker payload
  /// — are served under `<base>/assets/`. Falls back to the raw relative URL
  /// (resolved against the worker script's directory) when the marker is
  /// absent, e.g. a test serving the glue next to a hand-placed worker.
  static String _workerGlueUrl() {
    final loc = globalContext
        .getProperty<JSObject>('location'.toJS)
        .getProperty<JSString>('href'.toJS)
        .toDart;
    final i = loc.lastIndexOf('/assets/');
    if (i < 0) return _glueUrl;
    return '${loc.substring(0, i + 1)}$_glueUrl';
  }

  // --- raw module calls -----------------------------------------------------
  int _int(String fn, List<JSAny?> args) =>
      _m!.callMethodVarArgs<JSNumber>(fn.toJS, args).toDartInt;
  void _void(String fn, List<JSAny?> args) =>
      _m!.callMethodVarArgs<JSAny?>(fn.toJS, args);

  int _malloc(int n) => _int('_malloc', [n.toJS]);
  void _free(int p) => _void('_free', [p.toJS]);

  // Heap views are re-fetched on every access — ALLOW_MEMORY_GROWTH detaches
  // old typed-array views when the wasm heap grows.
  Uint8List get _u8 => _m!.getProperty<JSUint8Array>('HEAPU8'.toJS).toDart;
  Float32List get _f32 => _m!.getProperty<JSFloat32Array>('HEAPF32'.toJS).toDart;

  // --- Opus decoder ---------------------------------------------------------
  int createDecoder(int sampleRate, int channels) =>
      _int('_miniav_opus_create', [sampleRate.toJS, channels.toJS]);
  int decoderChannels(int handle) =>
      _int('_miniav_opus_channels', [handle.toJS]);
  int decoderSampleRate(int handle) =>
      _int('_miniav_opus_sample_rate', [handle.toJS]);
  void destroyDecoder(int handle) =>
      _void('_miniav_opus_destroy', [handle.toJS]);

  /// Decode one bare Opus packet → interleaved f32 (length = frames*channels),
  /// empty on error/no-output. An empty [pkt] requests PLC (packet-loss
  /// concealment).
  Float32List decode(int handle, Uint8List pkt, int maxFrames, int channels) {
    final inPtr = _malloc(pkt.isEmpty ? 1 : pkt.length);
    final outPtr = _malloc(maxFrames * channels * 4);
    try {
      if (pkt.isNotEmpty) _u8.setRange(inPtr, inPtr + pkt.length, pkt);
      final frames = _int('_miniav_opus_decode', [
        handle.toJS,
        (pkt.isEmpty ? 0 : inPtr).toJS,
        pkt.length.toJS,
        outPtr.toJS,
        maxFrames.toJS,
      ]);
      if (frames <= 0) return Float32List(0);
      final base = outPtr >> 2;
      return Float32List.fromList(_f32.sublist(base, base + frames * channels));
    } finally {
      _free(inPtr);
      _free(outPtr);
    }
  }

  // --- Opus encoder ---------------------------------------------------------
  int createEncoder(
          int sampleRate, int channels, int bitrateBps, int application) =>
      _int('_miniav_opus_enc_create', [
        sampleRate.toJS,
        channels.toJS,
        bitrateBps.toJS,
        application.toJS,
      ]);
  /// Encoder lookahead in samples at the encoder's rate — the priming a decoder
  /// must discard, i.e. OpusHead's pre-skip once scaled to 48 kHz.
  int encoderLookahead(int handle) =>
      _int('_miniav_opus_enc_lookahead', [handle.toJS]);

  void destroyEncoder(int handle) =>
      _void('_miniav_opus_enc_destroy', [handle.toJS]);

  /// Encode one frame of interleaved f32 [pcm] (framesPerCh*channels floats) →
  /// a bare Opus packet (empty on error; a 1-byte packet is DTS/silence).
  Uint8List encode(int handle, Float32List pcm, int framesPerCh) {
    const cap = 4000; // libopus-recommended max packet bytes
    final inPtr = _malloc(pcm.length * 4);
    final outPtr = _malloc(cap);
    try {
      _f32.setRange(inPtr >> 2, (inPtr >> 2) + pcm.length, pcm);
      final n = _int('_miniav_opus_enc_encode', [
        handle.toJS,
        inPtr.toJS,
        framesPerCh.toJS,
        outPtr.toJS,
        cap.toJS,
      ]);
      if (n <= 0) return Uint8List(0);
      return Uint8List.fromList(_u8.sublist(outPtr, outPtr + n));
    } finally {
      _free(inPtr);
      _free(outPtr);
    }
  }
}
