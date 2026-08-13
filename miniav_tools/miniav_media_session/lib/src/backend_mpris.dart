import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';

import 'backend.dart';
import 'media_metadata.dart';
import 'media_playback.dart';

const _rootInterface = 'org.mpris.MediaPlayer2';
const _playerInterface = 'org.mpris.MediaPlayer2.Player';
const _objectPath = '/org/mpris/MediaPlayer2';

/// Linux backend: MPRIS2 over the D-Bus session bus.
///
/// Unlike every other backend this one is pure Dart, because MPRIS is a **wire
/// protocol, not an OS API** — there is no libdbus call that a C backend could
/// make that this cannot. That buys three things: no `libdbus-1` system
/// dependency, no fifth native translation unit, and code that can be analysed
/// and unit-tested on any host instead of only on Linux.
///
/// Desktop environments (GNOME, KDE, and `playerctl`) discover players by
/// scanning the bus for `org.mpris.MediaPlayer2.*` names, then drive them
/// through the `Player` interface. Media keys are routed by the DE, which is
/// why owning this name is what makes them work.
class MprisMediaSessionBackend implements MediaSessionBackend {
  final String appName;

  DBusClient? _client;
  _MprisObject? _object;

  bool _supported = false;
  String? _unsupportedReason;
  String? _busName;

  final _commands = StreamController<MediaCommand>.broadcast();

  // Published state. The D-Bus object reads these directly.
  MediaMetadata? _metadata;
  MediaPlaybackState _state = MediaPlaybackState.none;
  MediaPosition _position = MediaPosition.zero;
  Set<MediaAction> _actions = const {};
  String? _artUrl;
  File? _artTempFile;

  /// Wall-clock reference for extrapolating [Position].
  ///
  /// MPRIS exposes `Position` as a property clients read on demand, and it is
  /// explicitly NOT signalled through `PropertiesChanged` — so returning the
  /// last pushed value would make every client's progress bar tick in 250 ms
  /// jumps. Extrapolating from the last push plus the playback rate gives a
  /// smooth playhead between pushes.
  DateTime _positionStampedAt = DateTime.now();

  /// Monotonically increasing so each track gets a distinct `mpris:trackid`.
  /// Clients key their state off it; reusing one id makes a track change look
  /// like an edit of the same track.
  int _trackSerial = 0;

  MprisMediaSessionBackend({required this.appName});

  @override
  String get name => 'mpris';

  @override
  bool get isSupported => _supported;

  @override
  String? get unsupportedReason => _unsupportedReason;

  @override
  String? get detail => _supported ? 'mpris: owns $_busName' : null;

  @override
  Stream<MediaCommand> get commands => _commands.stream;

  @override
  Future<void> initialize({required Set<MediaAction> actions}) async {
    _actions = actions;
    try {
      final client = DBusClient.session();
      final object = _MprisObject(this);

      // The PID suffix follows the MPRIS spec's instance convention. Without
      // it a second copy of the app fails to take the name and silently has no
      // session, rather than appearing as a second player.
      final busName =
          'org.mpris.MediaPlayer2.${_sanitiseName(appName)}.instance$pid';

      await client.registerObject(object);
      final reply = await client.requestName(busName);
      if (reply == DBusRequestNameReply.exists) {
        await client.close();
        _supported = false;
        _unsupportedReason = 'another player already owns $busName';
        return;
      }

      _client = client;
      _object = object;
      _busName = busName;
      _supported = true;
      _unsupportedReason = null;
    } on SocketException catch (e) {
      // No session bus: a headless box, a container, or a root shell.
      _supported = false;
      _unsupportedReason = 'no D-Bus session bus (${e.message})';
    } catch (e) {
      // Deliberately broad. package:dbus has no single exception base, and the
      // failure set here is wide — a missing DBUS_SESSION_BUS_ADDRESS, a
      // closed client, a malformed name, a bus that hangs up mid-handshake.
      // The contract is that an unavailable session is reported, never thrown:
      // an app must not fail to play music because the desktop has no bus.
      _supported = false;
      _unsupportedReason = 'D-Bus unavailable: $e';
    }
  }

  /// A D-Bus name element: `[A-Za-z_][A-Za-z0-9_]*`.
  static String _sanitiseName(String raw) {
    final buffer = StringBuffer();
    for (final rune in raw.runes) {
      final c = String.fromCharCode(rune);
      buffer.write(RegExp(r'[A-Za-z0-9_]').hasMatch(c) ? c : '_');
    }
    var out = buffer.toString();
    if (out.isEmpty) out = 'miniav';
    // A leading digit is illegal in a name element.
    if (RegExp(r'^[0-9]').hasMatch(out)) out = '_$out';
    return out;
  }

  @override
  Future<void> setMetadata(MediaMetadata metadata) async {
    _metadata = metadata;
    _trackSerial++;
    await _resolveArtwork(metadata.artwork);
    await _object?.emitPropertiesChanged(
      _playerInterface,
      changedProperties: {'Metadata': _object!.metadataValue},
    );
  }

  Future<void> _resolveArtwork(MediaArtwork? artwork) async {
    final previous = _artTempFile;
    _artTempFile = null;

    switch (artwork) {
      case UriArtwork(:final uri):
        _artUrl = uri.toString();
      case FileArtwork(:final path):
        _artUrl = Uri.file(path).toString();
      case BytesArtwork(:final bytes, :final mimeType):
        // MPRIS carries `mpris:artUrl`, a URL — there is nowhere to put raw
        // bytes, so ID3 cover art has to land on disk. A fresh name per track
        // because clients cache by URL.
        try {
          final ext = switch (mimeType) {
            'image/png' => 'png',
            'image/jpeg' || 'image/jpg' => 'jpg',
            _ => 'img',
          };
          final file = File(
            '${Directory.systemTemp.path}/miniav_ms_${pid}_$_trackSerial.$ext',
          );
          await file.writeAsBytes(bytes, flush: true);
          _artTempFile = file;
          _artUrl = Uri.file(file.path).toString();
        } catch (_) {
          _artUrl = null;
        }
      case null:
        _artUrl = null;
    }

    // Reap the previous track's file only after the new URL is published, so a
    // client fetching the outgoing cover is not raced.
    if (previous != null) {
      try {
        await previous.delete();
      } catch (_) {
        // A stale temp file is a smaller problem than a thrown teardown.
      }
    }
  }

  @override
  Future<void> setPlaybackState(MediaPlaybackState state) async {
    _state = state;
    await _object?.emitPropertiesChanged(
      _playerInterface,
      changedProperties: {
        'PlaybackStatus': DBusString(_object!.playbackStatusString),
      },
    );
  }

  @override
  Future<void> setPosition(MediaPosition position) async {
    final seeked =
        (position.position - _extrapolatedPosition()).abs() >
        const Duration(seconds: 2);
    _position = position;
    _positionStampedAt = DateTime.now();
    // MPRIS forbids signalling Position through PropertiesChanged; a jump is
    // announced with the Seeked signal instead. Small drift is normal and must
    // NOT fire it, or clients re-sync on every tick.
    if (seeked) {
      await _object?.emitSignal(_playerInterface, 'Seeked', [
        DBusInt64(position.position.inMicroseconds),
      ]);
    }
  }

  Duration _extrapolatedPosition() {
    if (_state != MediaPlaybackState.playing || _position.speed <= 0) {
      return _position.position;
    }
    final since = DateTime.now().difference(_positionStampedAt);
    var out = _position.position + since * _position.speed;
    final duration = _position.duration;
    if (duration != null && out > duration) out = duration;
    return out;
  }

  @override
  Future<void> setActions(Set<MediaAction> actions) async {
    _actions = actions;
    await _object?.emitPropertiesChanged(
      _playerInterface,
      changedProperties: _object!.capabilityValues,
    );
  }

  void _emit(MediaAction action, {Duration? position, Duration? offset}) {
    if (!_actions.contains(action)) return;
    if (_commands.isClosed) return;
    _commands.add(MediaCommand(action, position: position, offset: offset));
  }

  @override
  Future<void> dispose() async {
    final client = _client;
    _client = null;
    _object = null;
    _supported = false;
    if (client != null) {
      try {
        await client.close();
      } catch (_) {
        // Losing the bus during teardown is not worth throwing over.
      }
    }
    final art = _artTempFile;
    _artTempFile = null;
    if (art != null) {
      try {
        await art.delete();
      } catch (_) {}
    }
    await _commands.close();
  }
}

/// The object exported at `/org/mpris/MediaPlayer2`.
class _MprisObject extends DBusObject {
  final MprisMediaSessionBackend _backend;

  _MprisObject(this._backend) : super(DBusObjectPath(_objectPath));

  String get playbackStatusString => switch (_backend._state) {
    MediaPlaybackState.playing => 'Playing',
    MediaPlaybackState.paused => 'Paused',
    // MPRIS has no "no media" status; Stopped is the closest, and it is what
    // clients expect when a player is idle but present.
    MediaPlaybackState.stopped || MediaPlaybackState.none => 'Stopped',
  };

  DBusValue get metadataValue {
    final metadata = _backend._metadata;
    if (metadata == null) return DBusDict.stringVariant({});

    return DBusDict.stringVariant({
      // Required by the spec and by most clients' change detection.
      'mpris:trackid': DBusObjectPath(
        '$_objectPath/track/${_backend._trackSerial}',
      ),
      if (metadata.duration != null)
        'mpris:length': DBusInt64(metadata.duration!.inMicroseconds),
      'xesam:title': DBusString(metadata.title),
      if (metadata.artist != null)
        'xesam:artist': DBusArray.string([metadata.artist!]),
      if (metadata.album != null) 'xesam:album': DBusString(metadata.album!),
      if (metadata.trackNumber != null)
        'xesam:trackNumber': DBusInt32(metadata.trackNumber!),
      if (_backend._artUrl != null)
        'mpris:artUrl': DBusString(_backend._artUrl!),
    });
  }

  Map<String, DBusValue> get capabilityValues {
    final a = _backend._actions;
    return {
      'CanGoNext': DBusBoolean(a.contains(MediaAction.next)),
      'CanGoPrevious': DBusBoolean(a.contains(MediaAction.previous)),
      'CanPlay': DBusBoolean(
        a.contains(MediaAction.play) || a.contains(MediaAction.playPause),
      ),
      'CanPause': DBusBoolean(
        a.contains(MediaAction.pause) || a.contains(MediaAction.playPause),
      ),
      'CanSeek': DBusBoolean(
        a.contains(MediaAction.seekTo) ||
            a.contains(MediaAction.seekForward) ||
            a.contains(MediaAction.seekBackward),
      ),
      // CanControl false makes most clients hide the player entirely, so it is
      // always true — the per-action flags above are what actually gate the
      // individual buttons.
      'CanControl': const DBusBoolean(true),
    };
  }

  @override
  List<DBusIntrospectInterface> introspect() => [
    DBusIntrospectInterface(
      _rootInterface,
      methods: [
        DBusIntrospectMethod('Raise'),
        DBusIntrospectMethod('Quit'),
      ],
      properties: [
        DBusIntrospectProperty(
          'Identity',
          DBusSignature('s'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'CanQuit',
          DBusSignature('b'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'CanRaise',
          DBusSignature('b'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'HasTrackList',
          DBusSignature('b'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'SupportedUriSchemes',
          DBusSignature('as'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'SupportedMimeTypes',
          DBusSignature('as'),
          access: DBusPropertyAccess.read,
        ),
      ],
    ),
    DBusIntrospectInterface(
      _playerInterface,
      methods: [
        DBusIntrospectMethod('Next'),
        DBusIntrospectMethod('Previous'),
        DBusIntrospectMethod('Pause'),
        DBusIntrospectMethod('PlayPause'),
        DBusIntrospectMethod('Stop'),
        DBusIntrospectMethod('Play'),
        DBusIntrospectMethod(
          'Seek',
          args: [
            DBusIntrospectArgument(
              DBusSignature('x'),
              DBusArgumentDirection.in_,
              name: 'Offset',
            ),
          ],
        ),
        DBusIntrospectMethod(
          'SetPosition',
          args: [
            DBusIntrospectArgument(
              DBusSignature('o'),
              DBusArgumentDirection.in_,
              name: 'TrackId',
            ),
            DBusIntrospectArgument(
              DBusSignature('x'),
              DBusArgumentDirection.in_,
              name: 'Position',
            ),
          ],
        ),
      ],
      signals: [
        DBusIntrospectSignal(
          'Seeked',
          args: [
            DBusIntrospectArgument(
              DBusSignature('x'),
              DBusArgumentDirection.out,
              name: 'Position',
            ),
          ],
        ),
      ],
      properties: [
        DBusIntrospectProperty(
          'PlaybackStatus',
          DBusSignature('s'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'Metadata',
          DBusSignature('a{sv}'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'Position',
          DBusSignature('x'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty('Rate', DBusSignature('d')),
        DBusIntrospectProperty('Volume', DBusSignature('d')),
        DBusIntrospectProperty(
          'MinimumRate',
          DBusSignature('d'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'MaximumRate',
          DBusSignature('d'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'CanGoNext',
          DBusSignature('b'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'CanGoPrevious',
          DBusSignature('b'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'CanPlay',
          DBusSignature('b'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'CanPause',
          DBusSignature('b'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'CanSeek',
          DBusSignature('b'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'CanControl',
          DBusSignature('b'),
          access: DBusPropertyAccess.read,
        ),
      ],
    ),
  ];

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface == _rootInterface) {
      // Raise and Quit are accepted and ignored: CanQuit and CanRaise are
      // false, so a conforming client never calls them, and a non-conforming
      // one should not get an error for asking.
      switch (call.name) {
        case 'Raise':
        case 'Quit':
          return DBusMethodSuccessResponse();
      }
      return DBusMethodErrorResponse.unknownMethod();
    }

    if (call.interface != _playerInterface) {
      return DBusMethodErrorResponse.unknownInterface();
    }

    switch (call.name) {
      case 'Play':
        _backend._emit(MediaAction.play);
      case 'Pause':
        _backend._emit(MediaAction.pause);
      case 'PlayPause':
        _backend._emit(MediaAction.playPause);
      case 'Stop':
        _backend._emit(MediaAction.stop);
      case 'Next':
        _backend._emit(MediaAction.next);
      case 'Previous':
        _backend._emit(MediaAction.previous);
      case 'Seek':
        // MPRIS Seek is RELATIVE and signed; negative means rewind.
        final offsetUs = (call.values[0] as DBusInt64).value;
        final offset = Duration(microseconds: offsetUs.abs());
        _backend._emit(
          offsetUs < 0 ? MediaAction.seekBackward : MediaAction.seekForward,
          offset: offset,
        );
      case 'SetPosition':
        // The spec says to ignore the call when TrackId does not match the
        // current track — it means the client is acting on a track that has
        // already changed, and honouring it would seek the WRONG song.
        final trackId = (call.values[0] as DBusObjectPath).value;
        final expected = '$_objectPath/track/${_backend._trackSerial}';
        if (trackId != expected) return DBusMethodSuccessResponse();
        final positionUs = (call.values[1] as DBusInt64).value;
        _backend._emit(
          MediaAction.seekTo,
          position: Duration(microseconds: positionUs),
        );
      case 'OpenUri':
        return DBusMethodErrorResponse.failed('OpenUri is not supported');
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
    return DBusMethodSuccessResponse();
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface == _rootInterface) {
      return switch (name) {
        'Identity' => DBusGetPropertyResponse(
          DBusString(_backend.appName),
        ),
        'CanQuit' => DBusGetPropertyResponse(const DBusBoolean(false)),
        'CanRaise' => DBusGetPropertyResponse(const DBusBoolean(false)),
        'HasTrackList' => DBusGetPropertyResponse(const DBusBoolean(false)),
        'SupportedUriSchemes' => DBusGetPropertyResponse(
          DBusArray.string(const []),
        ),
        'SupportedMimeTypes' => DBusGetPropertyResponse(
          DBusArray.string(const []),
        ),
        _ => DBusMethodErrorResponse.unknownProperty(),
      };
    }

    if (interface != _playerInterface) {
      return DBusMethodErrorResponse.unknownProperty();
    }

    final caps = capabilityValues;
    if (caps.containsKey(name)) {
      return DBusGetPropertyResponse(caps[name]!);
    }

    return switch (name) {
      'PlaybackStatus' => DBusGetPropertyResponse(
        DBusString(playbackStatusString),
      ),
      'Metadata' => DBusGetPropertyResponse(metadataValue),
      'Position' => DBusGetPropertyResponse(
        DBusInt64(_backend._extrapolatedPosition().inMicroseconds),
      ),
      'Rate' => DBusGetPropertyResponse(DBusDouble(_backend._position.speed)),
      'MinimumRate' => DBusGetPropertyResponse(const DBusDouble(1.0)),
      'MaximumRate' => DBusGetPropertyResponse(const DBusDouble(1.0)),
      // Volume is mandatory in the spec. Reporting 1.0 and refusing writes is
      // honest: this library publishes a session, it does not own a mixer.
      'Volume' => DBusGetPropertyResponse(const DBusDouble(1.0)),
      _ => DBusMethodErrorResponse.unknownProperty(),
    };
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface == _rootInterface) {
      return DBusGetAllPropertiesResponse({
        'Identity': DBusString(_backend.appName),
        'CanQuit': const DBusBoolean(false),
        'CanRaise': const DBusBoolean(false),
        'HasTrackList': const DBusBoolean(false),
        'SupportedUriSchemes': DBusArray.string(const []),
        'SupportedMimeTypes': DBusArray.string(const []),
      });
    }
    if (interface == _playerInterface) {
      return DBusGetAllPropertiesResponse({
        'PlaybackStatus': DBusString(playbackStatusString),
        'Metadata': metadataValue,
        'Position': DBusInt64(
          _backend._extrapolatedPosition().inMicroseconds,
        ),
        'Rate': DBusDouble(_backend._position.speed),
        'MinimumRate': const DBusDouble(1.0),
        'MaximumRate': const DBusDouble(1.0),
        'Volume': const DBusDouble(1.0),
        ...capabilityValues,
      });
    }
    return DBusGetAllPropertiesResponse({});
  }
}
