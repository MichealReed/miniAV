import 'dart:io';
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';

final sourceDir = Directory('./miniav_c');

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    Logger logger = Logger('build');

    // hooks_runner re-runs this hook only when the hook script itself or a
    // REGISTERED dependency is newer than the cached output. CMakeBuilder
    // registers none of its sources, so without this an edited .c/.h keeps
    // serving the previously built DLL — new exports resolve to nothing and
    // the failure looks like a Dart bug, not a stale build.
    output.dependencies.addAll(_sourceFiles(sourceDir));

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

/// Every native source under [dir] that the CMake build actually compiles,
/// as absolute URIs for `output.dependencies`. Build trees (`build*/`) and
/// VCS metadata are skipped — registering generated output would make the
/// hook re-run forever.
Iterable<Uri> _sourceFiles(Directory dir) sync* {
  const extensions = {
    '.c',
    '.cc',
    '.cpp',
    '.h',
    '.hpp',
    '.m',
    '.mm',
    '.txt',
    '.cmake',
  };
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final path = entity.path.replaceAll(r'\', '/');
    if (path.contains('/build/') ||
        path.contains('/build_win/') ||
        path.contains('/build_linux/') ||
        path.contains('/build_web/') ||
        path.contains('/.git/')) {
      continue;
    }
    final dot = path.lastIndexOf('.');
    if (dot < 0 || !extensions.contains(path.substring(dot))) continue;
    yield entity.absolute.uri;
  }
}

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
    appleArgs: const AppleBuilderArgs(
      enableArc: false,
      enableBitcode: false,
      enableVisibility: true,
    ),
  );
  await builder.run(
    input: input,
    output: output,
    logger: Logger('')
      ..level = Level.ALL
      ..onRecord.listen((record) => stderr.writeln(record)),
  );
}
