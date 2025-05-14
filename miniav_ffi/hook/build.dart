import 'package:native_assets_cli/native_assets_cli.dart';
import 'package:logging/logging.dart';
import 'package:native_assets_cli/code_assets_builder.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';

// Needs web conditional import
import 'dart:io';

final sourceDir = Directory('./miniav_c');

void main(List<String> args) async {
  await build(args, (input, output) async {
    Logger logger = Logger('build');
    await runBuild(input, output, sourceDir.absolute.uri);
    final miniavLib = await output.findAndAddCodeAssets(
      input,
      names: {'miniav_c': 'miniav_ffi_bindings.dart'},
    );
    final assets = <List<dynamic>>[miniavLib];

    for (final assetList in assets) {
      for (CodeAsset asset in assetList) {
        logger.info('Added file: ${asset.file}');
      }
    }
  });
}

const name = 'miniav_ffi.dart';

Future<void> runBuild(
  BuildInput input,
  BuildOutputBuilder output,
  Uri sourceDir,
) async {
  Generator generator = Generator.defaultGenerator;
  switch (input.config.code.targetOS) {
    case OS.android:
      generator = Generator.ninja;
      break;
    case OS.iOS:
      generator = Generator.make;
      break;
    case OS.macOS:
      generator = Generator.make;
      break;
    case OS.linux:
      generator = Generator.ninja;
      break;
    case OS.windows:
      generator = Generator.defaultGenerator;
      break;
    case OS.fuchsia:
      generator = Generator.defaultGenerator;
      break;
  }

  final builder = CMakeBuilder.create(
    name: name,
    sourceDir: sourceDir,
    generator: generator,
    defines: {},
  );
  await builder.run(
    input: input,
    output: output,
    logger:
        Logger('')
          ..level = Level.ALL
          ..onRecord.listen((record) => stderr.writeln(record)),
  );
}
