// Native-assets build hook for the miniav_tools_codecs first-party codecs lib.
//
// Compiles `native/` (opus_decode.c + libopus static; mf_decoder.c on Windows)
// into `miniav_tools_codecs_native` and binds it to `lib/src/codecs_native.dart`.
//
// Unlike the FFmpeg shim's hook, this does NOT download or link FFmpeg — the
// whole point is a codec path (Opus audio + Media Foundation video) that runs
// with zero FFmpeg in the process. libopus is fetched + built from source by
// `native/cmake/opus.cmake` (system libopus is used if present).

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';

const _assetName = 'miniav_tools_codecs_native';
const _dartFile = 'codecs_native.dart';
final _sourceDir = Directory('./native');

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    hierarchicalLoggingEnabled = true;
    final logger = Logger('build')
      ..level = Level.ALL
      ..onRecord.listen((r) => stderr.writeln('[codecs] ${r.message}'));

    final os = input.config.code.targetOS;
    if (os != OS.windows &&
        os != OS.linux &&
        os != OS.macOS &&
        os != OS.iOS &&
        os != OS.android) {
      logger.info('codecs native lib not built on $os');
      return;
    }

    final generator = switch (os) {
      OS.linux || OS.android => Generator.ninja,
      OS.macOS || OS.iOS => Generator.make,
      _ => Generator.defaultGenerator,
    };

    // hooks_runner re-runs this hook only when the hook script itself or a
    // REGISTERED dependency is newer than the cached output. CMakeBuilder
    // registers none of its sources, so without this an edited encoder or
    // decoder keeps serving the previously built library - here and in every
    // package that depends on this one - and the edit looks like it changed
    // nothing.
    output.dependencies.addAll(_sourceFiles(_sourceDir));

    final builder = CMakeBuilder.create(
      name: _assetName,
      sourceDir: _sourceDir.absolute.uri,
      generator: generator,
      buildMode: BuildMode.release,
      targets: const [_assetName],
    );
    await builder.run(input: input, output: output, logger: logger);

    final assets = await output.findAndAddCodeAssets(
      input,
      names: const {_assetName: _dartFile},
    );
    for (final asset in assets) {
      logger.info('registered asset: ${asset.file}');
    }
  });
}

/// Every native source under [dir] that the CMake build compiles, as absolute
/// URIs for `output.dependencies`. Build trees (`build*/`, which include the
/// wasm and web builds' output) are skipped: registering generated files
/// would rebuild this library whenever they change.
Iterable<Uri> _sourceFiles(Directory dir) sync* {
  const extensions = {'.c', '.cc', '.cpp', '.h', '.hpp', '.txt', '.cmake'};
  final buildTree = RegExp(r'/build[^/]*/');
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final path = entity.path.replaceAll(r'\', '/');
    if (buildTree.hasMatch(path)) continue;
    final dot = path.lastIndexOf('.');
    if (dot < 0 || !extensions.contains(path.substring(dot))) continue;
    yield entity.absolute.uri;
  }
}
