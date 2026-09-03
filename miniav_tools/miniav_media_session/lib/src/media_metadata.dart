import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Cover art for the current item.
///
/// Every platform wants artwork in a different form, and none of them accept
/// all three of these directly:
///
/// | Platform | Native type | How each variant gets there |
/// |----------|-------------|------------------------------|
/// | Windows  | `RandomAccessStreamReference` | `file` → `file://` URI; `uri` direct; `bytes` → temp file |
/// | macOS/iOS| `MPMediaItemArtwork` (NSImage/UIImage) | `file`/`bytes` direct; `uri` must be fetched first |
/// | Android  | `Bitmap` or content URI | `file`/`bytes` direct; `uri` must be fetched first |
/// | Linux    | MPRIS `mpris:artUrl` (a URI) | `file` → `file://` URI; `uri` direct; `bytes` → temp file |
/// | Web      | `MediaImage.src` (a URL) | `uri` direct; `bytes` → blob URL; `file` unsupported |
///
/// [MediaArtwork.bytes] is therefore the most *portable* input even though it
/// is nobody's native form — two platforms materialise a temp file from it and
/// web materialises a blob URL. Prefer [MediaArtwork.uri] when the art already
/// lives at a stable URL, and [MediaArtwork.file] for on-disk libraries (mp3
/// folders), which is the common case for a local music player.
@immutable
sealed class MediaArtwork {
  const MediaArtwork();

  /// Art read from a local file path. Not supported on web (browsers cannot
  /// read arbitrary paths); use [MediaArtwork.bytes] there.
  const factory MediaArtwork.file(String path) = FileArtwork;

  /// Art at a remote or `file://` URL.
  const factory MediaArtwork.uri(Uri uri) = UriArtwork;

  /// Raw encoded image bytes — typically an APIC frame lifted straight out of
  /// an mp3's ID3 tag, which is why this variant exists at all.
  const factory MediaArtwork.bytes(
    Uint8List bytes, {
    required String mimeType,
  }) = BytesArtwork;

  Map<String, Object?> toMap();
}

/// Artwork loaded from a local file path.
final class FileArtwork extends MediaArtwork {
  final String path;

  const FileArtwork(this.path);

  @override
  Map<String, Object?> toMap() => {'kind': 'file', 'path': path};

  @override
  bool operator ==(Object other) =>
      other is FileArtwork && other.path == path;

  @override
  int get hashCode => Object.hash('file', path);
}

/// Artwork referenced by URL.
final class UriArtwork extends MediaArtwork {
  final Uri uri;

  const UriArtwork(this.uri);

  @override
  Map<String, Object?> toMap() => {'kind': 'uri', 'uri': uri.toString()};

  @override
  bool operator ==(Object other) => other is UriArtwork && other.uri == uri;

  @override
  int get hashCode => Object.hash('uri', uri);
}

/// Artwork carried as encoded image bytes (PNG/JPEG).
final class BytesArtwork extends MediaArtwork {
  final Uint8List bytes;
  final String mimeType;

  const BytesArtwork(this.bytes, {required this.mimeType});

  @override
  Map<String, Object?> toMap() => {
    'kind': 'bytes',
    'bytes': bytes,
    'mimeType': mimeType,
  };

  /// Compares by identity of the byte buffer, NOT by content.
  ///
  /// Metadata equality exists so the session can skip redundant platform
  /// pushes ([MediaMetadata] is diffed every poll tick). Deep-comparing a
  /// multi-megabyte cover on every tick would cost more than the push it is
  /// trying to avoid. Callers that decode the same art twice into two buffers
  /// get one extra push — harmless. Callers that hold the art in a field and
  /// reuse it (the normal pattern) get the fast path.
  @override
  bool operator ==(Object other) =>
      other is BytesArtwork &&
      identical(other.bytes, bytes) &&
      other.mimeType == mimeType;

  @override
  int get hashCode => Object.hash('bytes', identityHashCode(bytes), mimeType);
}

/// What is playing, as the OS should describe it to the user.
///
/// This is the payload behind the Windows volume-flyout card, the macOS
/// Control Center tile, the Android/iOS lock-screen widget, and the browser's
/// media notification.
@immutable
class MediaMetadata {
  /// Track title. The only required field — every platform shows it, and a
  /// session with an empty title renders as a blank card.
  final String title;

  final String? artist;
  final String? album;

  /// Total length of the item, when known.
  ///
  /// Duration is carried here *and* in [MediaPosition] because platforms
  /// disagree about which one owns it: web's `setPositionState` requires it
  /// alongside position, while Windows and Android attach it to the metadata
  /// record. Set it in both; the backends read whichever they need.
  final Duration? duration;

  final MediaArtwork? artwork;

  /// Track number within [album], 1-based, when known.
  final int? trackNumber;

  const MediaMetadata({
    required this.title,
    this.artist,
    this.album,
    this.duration,
    this.artwork,
    this.trackNumber,
  });

  MediaMetadata copyWith({
    String? title,
    String? artist,
    String? album,
    Duration? duration,
    MediaArtwork? artwork,
    int? trackNumber,
  }) => MediaMetadata(
    title: title ?? this.title,
    artist: artist ?? this.artist,
    album: album ?? this.album,
    duration: duration ?? this.duration,
    artwork: artwork ?? this.artwork,
    trackNumber: trackNumber ?? this.trackNumber,
  );

  Map<String, Object?> toMap() => {
    'title': title,
    'artist': artist,
    'album': album,
    'durationUs': duration?.inMicroseconds,
    'artwork': artwork?.toMap(),
    'trackNumber': trackNumber,
  };

  @override
  bool operator ==(Object other) =>
      other is MediaMetadata &&
      other.title == title &&
      other.artist == artist &&
      other.album == album &&
      other.duration == duration &&
      other.artwork == artwork &&
      other.trackNumber == trackNumber;

  @override
  int get hashCode =>
      Object.hash(title, artist, album, duration, artwork, trackNumber);

  @override
  String toString() =>
      'MediaMetadata($title${artist == null ? '' : ' — $artist'})';
}
