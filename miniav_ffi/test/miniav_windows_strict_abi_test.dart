// CPU-only optional ABI qualification; never creates a capture/GPU context.
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:miniav_ffi/miniav_ffi_bindings.dart' as bindings;
import 'package:miniav_ffi/miniav_ffi_windows_strict_screen.dart' as strict;
import 'package:test/test.dart';

void _offsets(
  ffi.Pointer<ffi.Void> pointer,
  int size, {
  bool header = true,
  Map<int, int> u64 = const {},
  Map<int, int> u32 = const {},
  Map<int, int> i32 = const {},
  Map<int, int> bytes = const {},
}) {
  final data = ByteData.sublistView(
    pointer.cast<ffi.Uint8>().asTypedList(size),
  );
  if (header) {
    expect(data.getUint32(0, Endian.little), size);
    expect(data.getUint32(4, Endian.little), 1);
  }
  for (final item in u64.entries) {
    expect(
      data.getUint64(item.key, Endian.little),
      item.value,
      reason: 'u64@${item.key}',
    );
  }
  for (final item in u32.entries) {
    expect(
      data.getUint32(item.key, Endian.little),
      item.value,
      reason: 'u32@${item.key}',
    );
  }
  for (final item in i32.entries) {
    expect(
      data.getInt32(item.key, Endian.little),
      item.value,
      reason: 'i32@${item.key}',
    );
  }
  for (final item in bytes.entries) {
    expect(data.getUint8(item.key), item.value, reason: 'byte@${item.key}');
  }
}

void main() {
  final windowsX64 = ffi.Abi.current() == ffi.Abi.windowsX64;
  test('strict Windows x64 records match frozen native offsets', () {
    expect(strict.miniavWindowsStrictRecordSizes, {
      'MiniAVWindowsAppAdmissionV1': 96,
      'MiniAVWindowsSelectionNonceV1': 24,
      'MiniAVWindowsScreenCandidateV1': 296,
      'MiniAVWindowsStrictCaptureOptionsV1': 16,
      'MiniAVWindowsStrictWindowWitnessV1': 128,
      'MiniAVWindowsStrictRetirementV1': 56,
      'MiniAVWindowsStrictResourceProfileV1': 64,
      'MiniAVWindowsStrictOwnerStorageExtentV1': 24,
      'MiniAVWindowsStrictOwnerStorageProfileV1': 128,
      'MiniAVWindowsStrictControlStorageProfileV1': 176,
      'MiniAVWindowsStrictControlStorageEventV1': 56,
      'MiniAVWindowsStrictControlStorageOpsV1': 24,
      'MiniAVWindowsStrictControlStorageExtentV1': 16,
      'MiniAVWindowsStrictControlStorageAuthorityV1': 120,
      'MiniAVWindowsStrictControlStorageOutcomeV1': 64,
    });
    using((arena) {
      final app = arena<strict.MiniAVWindowsAppAdmissionV1>();
      app.ref
        ..struct_size = 96
        ..abi_version = 1
        ..host_epoch = 11
        ..grant_generation = 12
        ..runtime_source_generation = 13
        ..valid_until_tick_ms = 14
        ..admitted_process_handle = 15
        ..process_creation_filetime = 16
        ..process_id = 17
        ..reserved0 = 18;
      app.ref.executable_sha256[0] = 19;
      app.ref.executable_sha256[31] = 20;
      _offsets(
        app.cast(),
        96,
        u64: {8: 11, 16: 12, 24: 13, 32: 14, 40: 15, 48: 16},
        u32: {56: 17, 60: 18},
        bytes: {64: 19, 95: 20},
      );

      final nonce = arena<strict.MiniAVWindowsSelectionNonceV1>();
      nonce.ref
        ..struct_size = 24
        ..abi_version = 1;
      nonce.ref.nonce[0] = 21;
      nonce.ref.nonce[15] = 22;
      _offsets(nonce.cast(), 24, bytes: {8: 21, 23: 22});

      final candidate = arena<strict.MiniAVWindowsScreenCandidateV1>();
      candidate.ref
        ..struct_size = 296
        ..abi_version = 1
        ..candidate_id = 23
        ..hwnd_value = 24
        ..process_id = 25
        ..reserved0 = 26
        ..process_creation_filetime = 27;
      candidate.ref.title_utf8[0] = 28;
      candidate.ref.title_utf8[255] = 29;
      _offsets(
        candidate.cast(),
        296,
        u64: {8: 23, 16: 24, 32: 27},
        u32: {24: 25, 28: 26},
        bytes: {40: 28, 295: 29},
      );

      final options = arena<strict.MiniAVWindowsStrictCaptureOptionsV1>();
      options.ref
        ..struct_size = 16
        ..abi_version = 1
        ..strict_gpu_only = 30
        ..reserved0 = 31;
      _offsets(options.cast(), 16, u32: {8: 30, 12: 31});

      final witness = arena<strict.MiniAVWindowsStrictWindowWitnessV1>();
      witness.ref
        ..struct_size = 128
        ..abi_version = 1
        ..capture_id = 32
        ..window_incarnation = 33
        ..hwnd_value = 34
        ..process_id = 35
        ..reserved0 = 36
        ..process_creation_filetime = 37
        ..host_epoch = 38
        ..grant_generation = 39
        ..runtime_source_generation = 40
        ..valid_until_tick_ms = 41;
      witness.ref.selection_nonce[0] = 42;
      witness.ref.selection_nonce[15] = 43;
      witness.ref.executable_sha256[0] = 44;
      witness.ref.executable_sha256[31] = 45;
      _offsets(
        witness.cast(),
        128,
        u64: {24: 32, 32: 33, 40: 34, 56: 37, 64: 38, 72: 39, 80: 40, 88: 41},
        u32: {48: 35, 52: 36},
        bytes: {8: 42, 23: 43, 96: 44, 127: 45},
      );

      final receipt = arena<strict.MiniAVWindowsStrictRetirementV1>();
      receipt.ref
        ..struct_size = 56
        ..abi_version = 1
        ..capture_id = 46
        ..state = 47
        ..terminal_reason = -14
        ..cleanup_error = -4
        ..flags = 48
        ..callbacks_in_flight = 49
        ..buffers_outstanding = 50
        ..frames_posted = 51
        ..frames_released = 52;
      _offsets(
        receipt.cast(),
        56,
        u64: {8: 46, 40: 51, 48: 52},
        u32: {16: 47, 28: 48, 32: 49, 36: 50},
        i32: {20: -14, 24: -4},
      );

      final resource = arena<strict.MiniAVWindowsStrictResourceProfileV1>();
      resource.ref
        ..struct_size = 64
        ..abi_version = 1
        ..capture_id = 61
        ..window_incarnation = 62
        ..width = 63
        ..height = 64
        ..pixel_format = 65
        ..pool_slots = 66
        ..max_outstanding_buffers = 67
        ..flags = 68
        ..frame_bytes = 69
        ..reserved0 = 70;
      _offsets(
        resource.cast(),
        64,
        u64: {8: 61, 16: 62, 48: 69, 56: 70},
        u32: {24: 63, 28: 64, 32: 65, 36: 66, 40: 67, 44: 68},
      );

      // Both storage profiles share one prefix; their extents start at 80.
      final owner = arena<strict.MiniAVWindowsStrictOwnerStorageProfileV1>();
      owner.ref
        ..struct_size = 128
        ..abi_version = 1
        ..factory_revision = 71
        ..flags = 72
        ..role_count = 75
        ..additional_resources = 76
        ..total_requested_bytes = 77
        ..reserved0 = 78;
      owner.ref.build_identity[0] = 73;
      owner.ref.build_identity[9] = 74;
      owner.ref.roles[0]
        ..kind = 79
        ..alignment = 80
        ..requested_bytes = 81
        ..reserved0 = 82;
      owner.ref.roles[1]
        ..kind = 83
        ..requested_bytes = 84;
      _offsets(
        owner.cast(),
        128,
        u64: {64: 77, 72: 78, 88: 81, 96: 82, 112: 84},
        u32: {
          8: 71,
          12: 72,
          16: 73,
          52: 74,
          56: 75,
          60: 76,
          80: 79,
          84: 80,
          104: 83,
        },
      );

      final control =
          arena<strict.MiniAVWindowsStrictControlStorageProfileV1>();
      control.ref
        ..struct_size = 176
        ..abi_version = 1
        ..total_requested_bytes = 85;
      control.ref.roles[3]
        ..kind = 86
        ..alignment = 87
        ..requested_bytes = 88
        ..reserved0 = 89;
      _offsets(
        control.cast(),
        176,
        u64: {64: 85, 160: 88, 168: 89},
        u32: {152: 86, 156: 87},
      );

      final event = arena<strict.MiniAVWindowsStrictControlStorageEventV1>();
      event.ref
        ..size = 56
        ..version = 1
        ..event = 90
        ..role = 91
        ..generation = 92
        ..source_epoch = 93
        ..row = 94
        ..alignment = 95
        ..address = 96
        ..bytes = 97;
      _offsets(
        event.cast(),
        56,
        u64: {16: 92, 24: 93, 40: 96, 48: 97},
        u32: {8: 90, 12: 91, 32: 94, 36: 95},
      );

      final ops = arena<strict.MiniAVWindowsStrictControlStorageOpsV1>();
      ops.ref
        ..retain = ffi.Pointer.fromAddress(98)
        ..release = ffi.Pointer.fromAddress(99)
        ..event = ffi.Pointer.fromAddress(100);
      _offsets(ops.cast(), 24, header: false, u64: {0: 98, 8: 99, 16: 100});

      final authority =
          arena<strict.MiniAVWindowsStrictControlStorageAuthorityV1>();
      authority.ref
        ..struct_size = 120
        ..abi_version = 1
        ..context = ffi.Pointer.fromAddress(101)
        ..ops = ffi.Pointer.fromAddress(102)
        ..generation = 103
        ..source_epoch = 104
        ..row = 105
        ..role_count = 106
        ..reserved0 = 107;
      authority.ref.roles[0]
        ..requested_bytes = 108
        ..alignment = 109
        ..reserved0 = 110;
      authority.ref.roles[3]
        ..requested_bytes = 111
        ..alignment = 112;
      _offsets(
        authority.cast(),
        120,
        u64: {8: 101, 16: 102, 24: 103, 32: 104, 48: 107, 56: 108, 104: 111},
        u32: {40: 105, 44: 106, 64: 109, 68: 110, 112: 112},
      );

      final outcome =
          arena<strict.MiniAVWindowsStrictControlStorageOutcomeV1>();
      outcome.ref
        ..struct_size = 64
        ..abi_version = 1
        ..disposition = 113
        ..flags = 114
        ..result = -14
        ..reserved0 = 115
        ..generation = 116
        ..source_epoch = 117
        ..row = 118
        ..reserved1 = 119
        ..context_value = 120
        ..reserved2 = 121;
      _offsets(
        outcome.cast(),
        64,
        u64: {24: 116, 32: 117, 48: 120, 56: 121},
        u32: {8: 113, 12: 114, 20: 115, 40: 118, 44: 119},
        i32: {16: -14},
      );
    });
  }, skip: windowsX64 ? false : 'Frozen qualification profile is Windows x64');

  test(
    'optional strict discovery and header validation allocate no capture',
    () {
      final api = strict.MiniAVWindowsStrictScreenBindings.tryResolve();
      expect(
        api,
        isNotNull,
        reason: 'current library must contain all optional exports',
      );
      final supported = api!.isSupported;
      using((arena) {
        final bits = arena<ffi.Uint32>(), tick = arena<ffi.Uint64>();
        bits.value = 15;
        tick.value = 99;
        expect(api.capabilities(bits, tick), supported ? 0 : -5);
        expect(bits.value, supported ? 15 : 0);
        expect(tick.value, supported ? greaterThan(0) : 0);
        tick.value = 99;
        expect(api.capabilities(ffi.nullptr, tick), -2);
        expect(tick.value, 0);
        // Malformed/null calls prove bounded output handling without creating
        // a GPU/capture context. Real unstarted ownership has a native check.
        final context = ffi.nullptr.cast<bindings.MiniAVScreenContext>();
        final app = arena<strict.MiniAVWindowsAppAdmissionV1>();
        app.ref
          ..struct_size = 96
          ..abi_version = 1;
        final nonce = arena<strict.MiniAVWindowsSelectionNonceV1>();
        nonce.ref
          ..struct_size = 24
          ..abi_version = 1;
        nonce.ref.nonce[0] = 99;
        final candidates =
            arena<ffi.Pointer<strict.MiniAVWindowsScreenCandidateV1>>();
        final count = arena<ffi.Uint32>();
        candidates.value = ffi.Pointer.fromAddress(1);
        count.value = 99;
        expect(api.beginSelection(context, app, nonce, candidates, count), -2);
        expect(nonce.cast<ffi.Uint8>().asTypedList(24), everyElement(0));
        expect(candidates.value, ffi.nullptr);
        expect(count.value, 0);

        // Short output headers must not let a native whole-struct clear write
        // through the caller's allocation; following sentinel bytes stay intact.
        final short = arena<ffi.Uint32>(4);
        short[0] = 8;
        short[1] = 1;
        short[2] = 0xfeed;
        short[3] = 0xbeef;
        expect(
          api.beginSelection(context, app, short.cast(), candidates, count),
          -2,
        );
        expect(short[2], 0xfeed);
        expect(short[3], 0xbeef);
        nonce.ref
          ..struct_size = 24
          ..abi_version = 2;
        expect(api.beginSelection(context, app, nonce, candidates, count), -2);

        nonce.ref
          ..struct_size = 24
          ..abi_version = 1;
        final format = arena<bindings.MiniAVVideoInfo>();
        final options = arena<strict.MiniAVWindowsStrictCaptureOptionsV1>();
        options.ref
          ..struct_size = 16
          ..abi_version = 1
          ..strict_gpu_only = 1;
        final witness = arena<strict.MiniAVWindowsStrictWindowWitnessV1>();
        witness.ref
          ..struct_size = 128
          ..abi_version = 1
          ..capture_id = 99;
        expect(
          api.configureWindow(context, nonce, 1, format, options, witness),
          -2,
        );
        expect(witness.cast<ffi.Uint8>().asTypedList(128), everyElement(0));
        expect(api.requestStop(context, -23), -2);
        final receipt = arena<strict.MiniAVWindowsStrictRetirementV1>();
        receipt.ref
          ..struct_size = 56
          ..abi_version = 1
          ..flags = 31
          ..state = 2;
        expect(api.getRetirement(context, receipt), -2);
        expect(receipt.cast<ffi.Uint8>().asTypedList(56), everyElement(0));

        // Allocation-free selection transport refuses the same way.
        count.value = 99;
        nonce.ref.nonce[0] = 99;
        expect(api.beginSelectionV2(context, app, nonce, count), -2);
        expect(nonce.cast<ffi.Uint8>().asTypedList(24), everyElement(0));
        expect(count.value, 0);
        nonce.ref
          ..struct_size = 24
          ..abi_version = 1;
        final candidate = arena<strict.MiniAVWindowsScreenCandidateV1>();
        candidate.ref
          ..struct_size = 296
          ..abi_version = 1
          ..candidate_id = 99;
        expect(api.copyCandidate(context, nonce, 0, candidate), -2);
        expect(candidate.cast<ffi.Uint8>().asTypedList(296), everyElement(0));
        final resource = arena<strict.MiniAVWindowsStrictResourceProfileV1>();
        resource.ref
          ..struct_size = 64
          ..abi_version = 1
          ..width = 99;
        expect(api.getResourceProfile(context, resource), -2);
        expect(resource.cast<ffi.Uint8>().asTypedList(64), everyElement(0));

        final maximum = arena<ffi.Uint32>();
        maximum.value = 99;
        expect(api.maxOutstandingBuffers(ffi.nullptr), -2);
        expect(api.maxOutstandingBuffers(maximum), supported ? 0 : -5);
        expect(maximum.value, supported ? 3 : 0);

        // Storage profiles describe exact native extents, or are refused with
        // a cleared record on a build that cannot vouch for its layout.
        short[0] = 8;
        short[1] = 1;
        expect(api.getOwnerStorageProfile(short.cast()), -2);
        expect(short[2], 0xfeed);
        expect(short[3], 0xbeef);
        final owner = arena<strict.MiniAVWindowsStrictOwnerStorageProfileV1>();
        owner.ref
          ..struct_size = 128
          ..abi_version = 1;
        final ownerResult = api.getOwnerStorageProfile(owner);
        expect(ownerResult, anyOf(0, -5));
        if (ownerResult == 0) {
          expect(owner.ref.struct_size, 128);
          expect(owner.ref.abi_version, 1);
          expect(owner.ref.factory_revision, 1);
          expect(owner.ref.flags, 3);
          expect(owner.ref.role_count, 2);
          expect(owner.ref.additional_resources, 2);
          expect([owner.ref.roles[0].kind, owner.ref.roles[1].kind], [0, 1]);
          expect(
            owner.ref.total_requested_bytes,
            owner.ref.roles[0].requested_bytes +
                owner.ref.roles[1].requested_bytes,
          );
        } else {
          expect(owner.cast<ffi.Uint8>().asTypedList(128), everyElement(0));
        }
        final control =
            arena<strict.MiniAVWindowsStrictControlStorageProfileV1>();
        control.ref
          ..struct_size = 176
          ..abi_version = 1;
        final controlResult = api.getControlStorageProfile(control);
        expect(controlResult, anyOf(0, -5));
        if (controlResult == 0) {
          expect(control.ref.factory_revision, 1);
          expect(control.ref.flags, 3);
          expect(control.ref.role_count, 4);
          expect(control.ref.additional_resources, 2);
          var total = 0;
          for (var i = 0; i < 4; i++) {
            expect(control.ref.roles[i].kind, i);
            total += control.ref.roles[i].requested_bytes;
          }
          expect(control.ref.total_requested_bytes, total);
        } else {
          expect(control.cast<ffi.Uint8>().asTypedList(176), everyElement(0));
        }

        // A funded control without an authority creates nothing and says so.
        final outcome =
            arena<strict.MiniAVWindowsStrictControlStorageOutcomeV1>();
        outcome.ref
          ..struct_size = 64
          ..abi_version = 1
          ..context_value = 99;
        final expected = controlResult == 0 ? -2 : -5;
        expect(api.createFundedControl(ffi.nullptr, outcome), expected);
        expect(outcome.ref.struct_size, 64);
        expect(outcome.ref.flags, 1);
        expect(outcome.ref.result, expected);
        expect(outcome.ref.disposition, 0);
        expect(outcome.ref.context_value, 0);
        expect(api.releaseFundedControl(context), -2);
      });
    },
    skip: windowsX64 ? false : 'Optional Windows x64 facility',
  );

  final oldPath = Platform.environment['MINIAV_STRICT_OLD_LIBRARY'];
  test(
    'an actual older library keeps generic exports while strict is absent',
    () {
      final old = ffi.DynamicLibrary.open(oldPath!);
      final version = old
          .lookupFunction<
            ffi.Pointer<ffi.Char> Function(),
            ffi.Pointer<ffi.Char> Function()
          >('MiniAV_GetVersionString');
      expect(version().cast<Utf8>().toDartString(), isNotEmpty);
      expect(
        strict.MiniAVWindowsStrictScreenBindings.tryResolve(library: old),
        isNull,
      );
    },
    skip: windowsX64 && oldPath != null
        ? false
        : 'Set MINIAV_STRICT_OLD_LIBRARY to an actual older native library',
  );
}
