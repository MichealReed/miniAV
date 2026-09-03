/// Browser-native video playback via a `<video>` element — the web fallback for
/// when WebCodecs is unavailable (older Safari/Firefox) or when you just want
/// the browser to demux+decode+render+play-audio a container end-to-end.
///
/// Two source modes:
///   - [MseController.blob] — a WHOLE container already in memory. Wrapped in a
///     Blob URL and handed to the `<video>` (progressive playback). Works for
///     any browser-supported container with NO codec string / no MSE machinery.
///   - [MseController.stream] — a growing/segmented container (live fMP4). Uses
///     Media Source Extensions: a [web.MediaSource] + [web.SourceBuffer] that
///     [appendBytes] feeds as segments arrive. Requires a precise MIME+codecs
///     string and fragmented ISO-BMFF / WebM.
///
/// The decoded frames stay inside the browser's media pipeline and are shown by
/// the `<video>` element, registered as a platform view ([viewType]) so Flutter
/// web can host it with `HtmlElementView`. Audio plays through the element too
/// (no miniaudio sink involved on this path).
///
/// Web-only: the native twin ([MseController] in `mse_controller_stub.dart`)
/// reports unsupported. Selected via conditional import.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:web/web.dart' as web;

/// WebKit's `ManagedMediaSource` — the ONLY MSE flavour on iPhone (classic
/// `MediaSource` never shipped there; MMS arrived in iOS 17.1). It subclasses
/// MediaSource in the browser, so `implements web.MediaSource` is truthful and
/// the whole SourceBuffer machinery below works on it unchanged. Two extras it
/// demands: the media element must opt out of remote playback (AirPlay) before
/// `src` is assigned, and it fires `startstreaming`/`endstreaming` to say when
/// appending is wanted — appending outside that window invites QuotaExceeded,
/// because the UA actively evicts to save battery.
@JS('ManagedMediaSource')
extension type _ManagedMediaSource._(JSObject _) implements web.MediaSource {
  external factory _ManagedMediaSource();
  external static bool isTypeSupported(String type);
}

class MseController {
  MseController._(this._video, this.viewType);

  /// True on this (web) platform.
  static bool get isSupportedPlatform => true;

  static bool get _hasClassicMse => globalContext.has('MediaSource');
  static bool get _hasManagedMse => globalContext.has('ManagedMediaSource');

  /// Whether a MIME+codecs string is playable via MSE in this browser.
  /// Guarded: referencing `MediaSource.isTypeSupported` on an iPhone (where
  /// the global does not exist) is a ReferenceError, not a false.
  static bool isTypeSupported(String mimeWithCodecs) {
    if (_hasClassicMse) return web.MediaSource.isTypeSupported(mimeWithCodecs);
    if (_hasManagedMse) return _ManagedMediaSource.isTypeSupported(mimeWithCodecs);
    return false;
  }

  /// Play a whole in-memory container (progressive). [mimeType] is the plain
  /// container type, e.g. `video/mp4` or `video/webm` (no codecs= needed).
  factory MseController.blob(Uint8List bytes, {required String mimeType}) {
    final video = _newVideoElement();
    final viewType = _register(video);
    final ctrl = MseController._(video, viewType).._wireElementEvents();
    // Blob wants a JS typed array; copy the Dart bytes across the boundary once.
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    ctrl._objectUrl = web.URL.createObjectURL(blob);
    video.src = ctrl._objectUrl!;
    ctrl._readyCompleter.complete(); // progressive: ready immediately
    return ctrl;
  }

  /// Stream a segmented container via MSE. [mimeWithCodecs] MUST be the full
  /// `video/mp4; codecs="avc1.640028,mp4a.40.2"`-style string (see
  /// [mp4MimeForTracks]); the segments appended via [appendBytes] must be
  /// fragmented ISO-BMFF (init segment first) or WebM.
  factory MseController.stream({required String mimeWithCodecs}) {
    final video = _newVideoElement();
    final viewType = _register(video);
    final ctrl = MseController._(video, viewType).._wireElementEvents();
    final web.MediaSource media;
    if (_hasClassicMse) {
      media = web.MediaSource();
    } else if (_hasManagedMse) {
      media = _ManagedMediaSource();
      // MMS refuses to open on an element that could hand off to AirPlay
      // unless an AirPlay source alternative is provided; opting out is the
      // documented single-source path. Must be set BEFORE src.
      video.disableRemotePlayback = true;
      // Append only while the UA wants data. MMS evicts aggressively to save
      // battery; appending outside the window is how QuotaExceeded happens.
      media.addEventListener(
        'startstreaming',
        ((web.Event _) {
          ctrl._streamingPaused = false;
          ctrl._pump();
        }).toJS,
      );
      media.addEventListener(
        'endstreaming',
        ((web.Event _) => ctrl._streamingPaused = true).toJS,
      );
    } else {
      throw StateError(
        'Neither MediaSource nor ManagedMediaSource exists in this browser — '
        'MSE stream mode is unavailable (blob mode still works).',
      );
    }
    ctrl._media = media;
    ctrl._objectUrl = web.URL.createObjectURL(media);
    video.src = ctrl._objectUrl!;
    media.onsourceopen = ((web.Event _) {
      // Exactly once: MediaSource can re-fire on some browsers after endOfStream.
      if (ctrl._sourceBuffer != null || ctrl._disposed) return;
      try {
        final sb = media.addSourceBuffer(mimeWithCodecs);
        ctrl._sourceBuffer = sb;
        sb.onupdateend = ((web.Event _) => ctrl._onUpdateEnd()).toJS;
        sb.onerror = ((web.Event _) {
          ctrl._reportError(StateError('MSE SourceBuffer error (bad segment?)'));
        }).toJS;
        if (!ctrl._readyCompleter.isCompleted) ctrl._readyCompleter.complete();
        ctrl._pump();
      } catch (e) {
        final err =
            StateError('MSE addSourceBuffer("$mimeWithCodecs") failed: $e');
        if (!ctrl._readyCompleter.isCompleted) {
          ctrl._readyCompleter.completeError(err);
        }
        ctrl._reportError(err);
      }
    }).toJS;
    return ctrl;
  }

  final web.HTMLVideoElement _video;

  /// Platform-view type id to host with `HtmlElementView(viewType: ...)`.
  final String viewType;

  web.MediaSource? _media;
  web.SourceBuffer? _sourceBuffer;
  String? _objectUrl;
  bool _disposed = false;
  bool _endOfStreamRequested = false;

  /// ManagedMediaSource only: true between `endstreaming` and the next
  /// `startstreaming`, while the UA does not want appends. Always false on
  /// classic MediaSource.
  bool _streamingPaused = false;

  final _readyCompleter = Completer<void>();
  final _firstFrameCompleter = Completer<void>();
  final _endedController = StreamController<void>.broadcast();
  final _errorController = StreamController<Object>.broadcast();

  // Pending segments for the MSE path, appended one-at-a-time (a SourceBuffer
  // rejects appendBuffer while `updating`).
  final _pending = <Uint8List>[];

  static int _viewSeq = 0;

  static web.HTMLVideoElement _newVideoElement() {
    final v = web.document.createElement('video') as web.HTMLVideoElement;
    v.autoplay = false;
    v.controls = false;
    v.setAttribute('playsinline', 'true'); // iOS Safari inline playback
    v.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = 'contain'
      ..backgroundColor = 'black';
    return v;
  }

  static String _register(web.HTMLVideoElement video) {
    final viewType = 'miniav-mse-video-${_viewSeq++}';
    ui_web.platformViewRegistry
        .registerViewFactory(viewType, (int _) => video);
    return viewType;
  }

  /// Media-element lifecycle events. Without the 'error' listener a corrupt or
  /// unsupported-codec source is SILENT BLACK forever; without 'ended' the
  /// [onEnded] stream never fires for element-driven playback.
  void _wireElementEvents() {
    _video.addEventListener(
      'error',
      ((web.Event _) {
        final me = _video.error;
        _reportError(StateError(
          'MSE <video> error: code=${me?.code ?? 0} '
          '${me?.message ?? "(no message)"}',
        ));
      }).toJS,
    );
    _video.addEventListener(
      'loadeddata',
      ((web.Event _) {
        if (!_firstFrameCompleter.isCompleted) _firstFrameCompleter.complete();
      }).toJS,
    );
    _video.addEventListener(
      'ended',
      ((web.Event _) {
        if (!_endedController.isClosed) _endedController.add(null);
      }).toJS,
    );
  }

  void _reportError(Object error) {
    if (_disposed) return;
    if (!_errorController.isClosed) _errorController.add(error);
    // A source that errors before producing a frame never will produce one.
    if (!_firstFrameCompleter.isCompleted) {
      _firstFrameCompleter.completeError(error);
    }
  }

  /// Completes when the element/source is ready to accept playback (immediately
  /// for [MseController.blob]; after `sourceopen`+SourceBuffer for the MSE path).
  Future<void> get onReady => _readyCompleter.future;

  /// Fires once when the media reaches its end.
  Stream<void> get onEnded => _endedController.stream;

  /// Completes when the FIRST frame is decoded and displayable ('loadeddata').
  /// Errors if the source fails before that. Unlike [onReady] (which is about
  /// accepting data), this is the real "video is visible" signal.
  Future<void> get onFirstFrame => _firstFrameCompleter.future;

  /// Playback/parse errors: the element's 'error' event (corrupt file,
  /// unsupported codec, network), SourceBuffer errors, and append failures.
  Stream<Object> get onError => _errorController.stream;

  set muted(bool value) => _video.muted = value;

  /// Append one media segment (MSE stream mode only). Serialized internally —
  /// safe to call before [onReady] completes (queued). No-op after [dispose].
  Future<void> appendBytes(Uint8List segment) async {
    if (_disposed || _endOfStreamRequested) return;
    if (_sourceBuffer == null && _media == null) {
      throw StateError('appendBytes is only valid in MSE stream mode');
    }
    _pending.add(segment);
    _pump();
  }

  void _pump() {
    final sb = _sourceBuffer;
    if (sb == null || _disposed || _pending.isEmpty || sb.updating) return;
    // Held segments resume from the 'startstreaming' listener. End-of-stream
    // is exempt: with all data delivered there is nothing left to evict for,
    // and holding it would leave duration unknown forever.
    if (_streamingPaused && !_endOfStreamRequested) return;
    final next = _pending.removeAt(0);
    try {
      sb.appendBuffer(next.toJS as web.BufferSource);
    } catch (e) {
      // QuotaExceeded or a detached SourceBuffer: playback can't proceed.
      _reportError(StateError('MSE appendBuffer failed: $e'));
    }
  }

  void _onUpdateEnd() {
    if (_disposed) return;
    if (_pending.isNotEmpty) {
      _pump();
    } else if (_endOfStreamRequested) {
      _finishStream();
    }
  }

  /// Signal end-of-stream (MSE mode): once all queued segments are appended,
  /// finalize the MediaSource so the element knows the total duration.
  void endOfStream() {
    _endOfStreamRequested = true;
    final sb = _sourceBuffer;
    if (sb != null && !sb.updating && _pending.isEmpty) _finishStream();
  }

  void _finishStream() {
    final media = _media;
    if (media == null || media.readyState != 'open') return;
    try {
      media.endOfStream();
    } catch (_) {
      // already ended / detached
    }
  }

  /// Start/resume playback. Returns false when the browser rejected it —
  /// typically the autoplay policy blocking an un-gestured, un-muted play().
  /// Retry from a user gesture (the player's resume()) or mute first.
  Future<bool> play() async {
    if (_disposed) return false;
    try {
      await _video.play().toDart;
      return true;
    } catch (e) {
      _reportError(StateError(
          'play() rejected (autoplay policy? retry after a user gesture, or '
          'mute first): $e'));
      return false;
    }
  }

  void pause() {
    if (!_disposed) _video.pause();
  }

  Future<void> seek(Duration position) async {
    if (_disposed) return;
    _video.currentTime = position.inMicroseconds / 1e6;
  }

  Duration get position =>
      Duration(microseconds: (_video.currentTime * 1e6).round());

  /// Total duration, or null while unknown (NaN before metadata / live).
  Duration? get duration {
    final d = _video.duration;
    if (d.isNaN || d.isInfinite) return null;
    return Duration(microseconds: (d * 1e6).round());
  }

  bool get isEnded => _video.ended;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try {
      _video.pause();
      _video.removeAttribute('src');
      _video.load(); // detach the media element from the source
    } catch (_) {}
    final url = _objectUrl;
    if (url != null) {
      try {
        web.URL.revokeObjectURL(url);
      } catch (_) {}
    }
    _pending.clear();
    if (!_endedController.isClosed) _endedController.close();
    if (!_errorController.isClosed) _errorController.close();
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.completeError(StateError('MseController disposed'));
    }
    if (!_firstFrameCompleter.isCompleted) {
      // Swallowed by default (nobody may be listening); a Future error with no
      // listener would otherwise crash the zone.
      _firstFrameCompleter.future.ignore();
      _firstFrameCompleter.completeError(StateError('MseController disposed'));
    }
  }
}
