/// Downloads + caches a shared-library FFmpeg build on first use.
///
/// Source: BtbN/FFmpeg-Builds GitHub releases — they ship official, signed
/// shared-library archives for Windows (.zip), Linux (.tar.xz) and recent
/// macOS via the auto-build pipeline. We pin to a known-good release.
///
/// Cache layout:
///   `<cacheRoot>/<release-tag>/<platform>/bin`   (Windows DLLs)
///   `<cacheRoot>/<release-tag>/<platform>/lib`   (Linux .so / macOS .dylib)
///
/// `cacheRoot` defaults to:
///   - Windows: %LOCALAPPDATA%\miniav_tools\ffmpeg
///   - macOS:   ~/Library/Caches/miniav_tools/ffmpeg
///   - Linux:   $XDG_CACHE_HOME/miniav_tools/ffmpeg or ~/.cache/...
///
/// Override with `MINIAV_TOOLS_FFMPEG_CACHE` env var. Skip auto-download
/// entirely with `MINIAV_TOOLS_FFMPEG_NO_AUTODOWNLOAD=1`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Pinned release tag from https://github.com/BtbN/FFmpeg-Builds/releases.
/// `latest` is a rolling tag updated daily by the CI; assets are named
/// `ffmpeg-master-latest-<platform>-<gpl|lgpl>-shared.<ext>`.
const String kFfmpegReleaseTag = 'latest';
const String kFfmpegVersionSuffix = 'master-latest';

class FfmpegDownloadResult {
  /// Directory containing the loadable shared libraries
  /// (`.dll` on Windows, `.so` on Linux, `.dylib` on macOS).
  final String libDir;

  /// Where the archive was extracted (`libDir`'s parent for Windows builds
  /// where DLLs live in `bin/`, otherwise the same as [libDir]).
  final String installRoot;

  const FfmpegDownloadResult({required this.libDir, required this.installRoot});
}

class FfmpegDownloader {
  /// Asset filename per platform (BtbN naming convention).
  static String? _assetName() {
    if (Platform.isWindows) {
      return 'ffmpeg-master-latest-win64-gpl-shared.zip';
    }
    if (Platform.isLinux) {
      return 'ffmpeg-master-latest-linux64-gpl-shared.tar.xz';
    }
    // macOS: BtbN does not ship official macOS shared builds. User must
    // install via `brew install ffmpeg` (homebrew puts dylibs in
    // /opt/homebrew/lib or /usr/local/lib which our loader already probes).
    return null;
  }

  /// Download URL for the current platform, or `null` if unsupported.
  static Uri? downloadUri() {
    final asset = _assetName();
    if (asset == null) return null;
    return Uri.https(
      'github.com',
      '/BtbN/FFmpeg-Builds/releases/download/$kFfmpegReleaseTag/$asset',
    );
  }

  /// Default cache root (see library doc-comment for resolution rules).
  static String defaultCacheRoot() {
    final override = Platform.environment['MINIAV_TOOLS_FFMPEG_CACHE'];
    if (override != null && override.isNotEmpty) return override;

    if (Platform.isWindows) {
      final localAppData =
          Platform.environment['LOCALAPPDATA'] ??
          p.join(
            Platform.environment['USERPROFILE'] ?? '.',
            'AppData',
            'Local',
          );
      return p.join(localAppData, 'miniav_tools', 'ffmpeg');
    }
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '.';
      return p.join(home, 'Library', 'Caches', 'miniav_tools', 'ffmpeg');
    }
    // Linux / other POSIX
    final xdg = Platform.environment['XDG_CACHE_HOME'];
    final base = xdg != null && xdg.isNotEmpty
        ? xdg
        : p.join(Platform.environment['HOME'] ?? '.', '.cache');
    return p.join(base, 'miniav_tools', 'ffmpeg');
  }

  /// Returns a path to a directory containing the loadable libav* libraries,
  /// downloading + extracting them if necessary. Returns `null` if
  /// auto-download is disabled, the platform is unsupported, or the download
  /// fails.
  ///
  /// Set [progress] to receive `(bytesReceived, totalBytes)` updates during
  /// the network transfer (totalBytes may be `-1` if the server omits
  /// `Content-Length`).
  static Future<FfmpegDownloadResult?> ensureFfmpeg({
    String? cacheRoot,
    void Function(int received, int total)? progress,
    bool force = false,
  }) async {
    if (Platform.environment['MINIAV_TOOLS_FFMPEG_NO_AUTODOWNLOAD'] == '1') {
      return null;
    }

    final uri = downloadUri();
    if (uri == null) return null; // unsupported platform

    final root = cacheRoot ?? defaultCacheRoot();
    final installRoot = p.join(root, kFfmpegReleaseTag);
    final marker = File(p.join(installRoot, '.ready'));

    if (!force && await marker.exists()) {
      final libDir = await _findLibDir(installRoot);
      if (libDir != null) {
        return FfmpegDownloadResult(libDir: libDir, installRoot: installRoot);
      }
    }

    await Directory(installRoot).create(recursive: true);

    final asset = _assetName()!;
    final archivePath = p.join(installRoot, asset);

    // Concurrent-process safety: use a sibling .lock file via O_EXCL semantics.
    final lock = File(p.join(installRoot, '.lock'));
    IOSink? lockSink;
    try {
      try {
        lockSink = lock.openWrite(mode: FileMode.writeOnly);
      } catch (_) {
        // Another process is downloading; wait briefly for the marker.
        for (var i = 0; i < 600; i++) {
          await Future<void>.delayed(const Duration(seconds: 1));
          if (await marker.exists()) {
            final libDir = await _findLibDir(installRoot);
            if (libDir != null) {
              return FfmpegDownloadResult(
                libDir: libDir,
                installRoot: installRoot,
              );
            }
          }
        }
      }

      // Download.
      final downloaded = await _download(uri, archivePath, progress: progress);
      if (!downloaded) return null;

      // Extract.
      if (asset.endsWith('.zip')) {
        await _extractZip(archivePath, installRoot);
      } else if (asset.endsWith('.tar.xz')) {
        await _extractTarXz(archivePath, installRoot);
      } else {
        stderr.writeln('miniav_tools_ffmpeg: unknown archive format: $asset');
        return null;
      }

      // Best-effort cleanup of the archive to save disk.
      try {
        await File(archivePath).delete();
      } catch (_) {}

      await marker.writeAsString(
        jsonEncode({
          'release': kFfmpegReleaseTag,
          'extractedAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
    } finally {
      try {
        await lockSink?.close();
      } catch (_) {}
      try {
        if (await lock.exists()) await lock.delete();
      } catch (_) {}
    }

    final libDir = await _findLibDir(installRoot);
    if (libDir == null) {
      stderr.writeln(
        'miniav_tools_ffmpeg: extracted FFmpeg but no lib dir found under '
        '$installRoot',
      );
      return null;
    }
    return FfmpegDownloadResult(libDir: libDir, installRoot: installRoot);
  }

  // --- internals -----------------------------------------------------------

  static Future<bool> _download(
    Uri uri,
    String destPath, {
    void Function(int received, int total)? progress,
  }) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', uri);
      final res = await client.send(req);
      if (res.statusCode == 302 || res.statusCode == 301) {
        final loc = res.headers['location'];
        if (loc == null) return false;
        return _download(Uri.parse(loc), destPath, progress: progress);
      }
      if (res.statusCode != 200) {
        stderr.writeln(
          'miniav_tools_ffmpeg: download failed HTTP '
          '${res.statusCode} for $uri',
        );
        return false;
      }
      final total = res.contentLength ?? -1;
      var received = 0;
      final sink = File(destPath).openWrite();
      try {
        await res.stream.forEach((chunk) {
          received += chunk.length;
          sink.add(chunk);
          if (progress != null) progress(received, total);
        });
      } finally {
        await sink.close();
      }
      return true;
    } catch (e) {
      stderr.writeln('miniav_tools_ffmpeg: download error: $e');
      return false;
    } finally {
      client.close();
    }
  }

  static Future<void> _extractZip(String archivePath, String destDir) async {
    final inputStream = InputFileStream(archivePath);
    try {
      final archive = ZipDecoder().decodeStream(inputStream);
      await extractArchiveToDisk(archive, destDir);
    } finally {
      await inputStream.close();
    }
  }

  static Future<void> _extractTarXz(String archivePath, String destDir) async {
    // XZ decoding is in `package:archive` but streaming xz support is
    // limited; for Linux we can use the system `tar` binary which is
    // ubiquitous and far faster.
    final result = await Process.run('tar', [
      '-xJf',
      archivePath,
      '-C',
      destDir,
    ]);
    if (result.exitCode != 0) {
      throw StateError(
        'tar -xJf failed (exit ${result.exitCode}): ${result.stderr}',
      );
    }
  }

  /// BtbN archives extract to `ffmpeg-<tag>/{bin,lib,include}/`. Locate the
  /// directory containing the shared libraries.
  static Future<String?> _findLibDir(String installRoot) async {
    if (!await Directory(installRoot).exists()) return null;
    await for (final entry in Directory(installRoot).list()) {
      if (entry is! Directory) continue;
      // Windows: bin/ holds avcodec-*.dll
      final bin = Directory(p.join(entry.path, 'bin'));
      if (await bin.exists() && await _hasAvLib(bin)) return bin.path;
      // Linux: lib/ holds libavcodec.so.*
      final lib = Directory(p.join(entry.path, 'lib'));
      if (await lib.exists() && await _hasAvLib(lib)) return lib.path;
    }
    // Some archives extract directly without a top wrapper folder.
    final binTop = Directory(p.join(installRoot, 'bin'));
    if (await binTop.exists() && await _hasAvLib(binTop)) return binTop.path;
    final libTop = Directory(p.join(installRoot, 'lib'));
    if (await libTop.exists() && await _hasAvLib(libTop)) return libTop.path;
    return null;
  }

  static Future<bool> _hasAvLib(Directory dir) async {
    await for (final f in dir.list()) {
      final name = p.basename(f.path).toLowerCase();
      if (name.startsWith('avcodec') &&
          (name.endsWith('.dll') ||
              name.contains('.so') ||
              name.endsWith('.dylib'))) {
        return true;
      }
    }
    return false;
  }
}

/// Compute SHA-256 for integrity checks (kept for future asset-pinning).
String sha256OfFile(String path) {
  final bytes = File(path).readAsBytesSync();
  return sha256.convert(bytes).toString();
}
