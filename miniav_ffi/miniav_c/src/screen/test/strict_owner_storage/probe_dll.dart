// Cold public ABI check only. Does not create a screen context or initialize
// COM, GPU, capture, workers, input, audio, windows or frames.
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

typedef _Query = Int32 Function(Pointer<Void>);
typedef _CallQuery = int Function(Pointer<Void>);
typedef _Calloc = Pointer<Void> Function(IntPtr, IntPtr);
typedef _CallCalloc = Pointer<Void> Function(int, int);
typedef _Free = Void Function(Pointer<Void>);
typedef _CallFree = void Function(Pointer<Void>);
typedef _Module = Int32 Function(
  Uint32, Pointer<Uint16>, Pointer<Pointer<Void>>);
typedef _CallModule = int Function(
  int, Pointer<Uint16>, Pointer<Pointer<Void>>);

void require(bool value, String message) {
  if (!value) throw StateError(message);
}

void main(List<String> args) {
  if (!Platform.isWindows || args.length != 3) {
    throw ArgumentError('probe_dll.dart ABSOLUTE_DLL HOLDER_BYTES OWNER_BYTES');
  }
  final file = File(args[0]).absolute;
  require(file.existsSync(), 'Missing native DLL');
  final expectedHolder = int.parse(args[1]);
  final expectedOwner = int.parse(args[2]);
  final library = DynamicLibrary.open(file.path);
  final address = library.lookup<NativeFunction<_Query>>(
    'MiniAV_Screen_Windows_GetStrictOwnerStorageProfileV1');
  final _CallQuery query = address.asFunction<_CallQuery>();
  final runtime = DynamicLibrary.open('msvcrt.dll');
  final _CallCalloc calloc = runtime.lookupFunction<_Calloc, _CallCalloc>('calloc');
  final _CallFree free = runtime.lookupFunction<_Free, _CallFree>('free');
  final _CallModule module = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<_Module, _CallModule>('GetModuleHandleExW');
  final memory = calloc(1, 144);
  final defining = calloc(1, sizeOf<Pointer<Void>>()).cast<Pointer<Void>>();
  require(memory != nullptr && defining != nullptr, 'Probe allocation failed');
  try {
    require(module(6, address.cast<Uint16>(), defining) != 0 &&
        defining.value == library.handle, 'Forwarded/different-module query');
    final bytes = memory.cast<Uint8>().asTypedList(144);
    final data = ByteData.sublistView(bytes);
    void reset(int size, int version) {
      bytes.fillRange(0, bytes.length, 0xa5);
      data.setUint32(0, size, Endian.little);
      data.setUint32(4, version, Endian.little);
    }
    for (final header in [(8, 1), (128, 2)]) {
      reset(header.$1, header.$2);
      final before = Uint8List.fromList(bytes);
      require(query(memory) != 0 &&
          List.generate(144, (i) => bytes[i] == before[i]).every((v) => v),
          'Refused header modified memory');
    }
    require(query(nullptr) != 0, 'Null header accepted');
    reset(144, 1);
    require(query(memory) == 0, 'Actual DLL profile refused');
    int u32(int offset) => data.getUint32(offset, Endian.little);
    int u64(int offset) => data.getUint64(offset, Endian.little);
    require(u32(0) == 128 && u32(4) == 1 && u32(8) == 1 && u32(12) == 3 &&
        u32(56) == 2 && u32(60) == 2 && u64(72) == 0 &&
        u32(80) == 0 && u32(104) == 1 && u64(96) == 0 && u64(120) == 0,
        'Noncanonical profile');
    require(u64(88) == expectedHolder && u64(112) == expectedOwner &&
        u64(64) == expectedHolder + expectedOwner && u32(84) == 8 && u32(108) == 8,
        'DLL differs from actual factory witness');
    require(bytes.skip(128).every((v) => v == 0xa5), 'Unknown suffix modified');
    stdout.writeln('PASS actual DLL owner profile: holder=${u64(88)} '
        'owner=${u64(112)} total=${u64(64)}; same defining module, C ABI/headers/suffix');
    stdout.writeln('build_identity=${[for (var i = 0; i < 10; i++) u32(16 + i * 4)]}');
    stdout.writeln('Metadata only; SDK source selection and native capture remain unqualified');
  } finally {
    free(defining.cast<Void>());
    free(memory);
  }
}
