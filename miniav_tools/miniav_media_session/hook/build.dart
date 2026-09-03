// Native-assets build hook for miniav_media_session.
//
// Compiles `native/` into `miniav_media_session_native` and binds it to
// `lib/src/media_session_native.dart`.
//
// Web has no native asset — browsers expose navigator.mediaSession directly, so
// that backend is pure Dart (lib/src/backend_web.dart) and this hook simply
// does not run for it.

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';

const _assetName = 'miniav_media_session_native';
const _dartFile = 'media_session_native.dart';
final _sourceDir = Directory('./native');

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    hierarchicalLoggingEnabled = true;
    final logger = Logger('build')
      ..level = Level.ALL
      ..onRecord.listen((r) => stderr.writeln('[media_session] ${r.message}'));

    final os = input.config.code.targetOS;
    if (os != OS.windows &&
        os != OS.linux &&
        os != OS.macOS &&
        os != OS.iOS &&
        os != OS.android) {
      logger.info('media session native lib not built on $os');
      return;
    }

    final generator = switch (os) {
      OS.linux || OS.android => Generator.ninja,
      OS.macOS || OS.iOS => Generator.make,
      _ => Generator.defaultGenerator,
    };

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
