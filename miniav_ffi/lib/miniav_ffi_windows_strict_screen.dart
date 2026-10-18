/// Optional low-level native bindings, not a capture permission or screen API.
/// Kept outside generated bindings so missing symbols disable only this feature.
@ffi.DefaultAsset('package:miniav_ffi/miniav_ffi_bindings.dart')
library;

// Match the frozen C field names when inspecting the ABI.
// ignore_for_file: non_constant_identifier_names
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

import 'miniav_ffi_bindings.dart' as bindings;

final class MiniAVWindowsAppAdmissionV1 extends ffi.Struct {
  @ffi.Uint32()
  external int struct_size;
  @ffi.Uint32()
  external int abi_version;
  @ffi.Uint64()
  external int host_epoch;
  @ffi.Uint64()
  external int grant_generation;
  @ffi.Uint64()
  external int runtime_source_generation;
  @ffi.Uint64()
  external int valid_until_tick_ms;
  @ffi.Uint64()
  external int admitted_process_handle;
  @ffi.Uint64()
  external int process_creation_filetime;
  @ffi.Uint32()
  external int process_id;
  @ffi.Uint32()
  external int reserved0;
  @ffi.Array(32)
  external ffi.Array<ffi.Uint8> executable_sha256;
}

final class MiniAVWindowsSelectionNonceV1 extends ffi.Struct {
  @ffi.Uint32()
  external int struct_size;
  @ffi.Uint32()
  external int abi_version;
  @ffi.Array(16)
  external ffi.Array<ffi.Uint8> nonce;
}

final class MiniAVWindowsScreenCandidateV1 extends ffi.Struct {
  @ffi.Uint32()
  external int struct_size;
  @ffi.Uint32()
  external int abi_version;
  @ffi.Uint64()
  external int candidate_id;
  @ffi.Uint64()
  external int hwnd_value;
  @ffi.Uint32()
  external int process_id;
  @ffi.Uint32()
  external int reserved0;
  @ffi.Uint64()
  external int process_creation_filetime;
  @ffi.Array(256)
  external ffi.Array<ffi.Char> title_utf8;
}

final class MiniAVWindowsStrictCaptureOptionsV1 extends ffi.Struct {
  @ffi.Uint32()
  external int struct_size;
  @ffi.Uint32()
  external int abi_version;
  @ffi.Uint32()
  external int strict_gpu_only;
  @ffi.Uint32()
  external int reserved0;
}

final class MiniAVWindowsStrictWindowWitnessV1 extends ffi.Struct {
  @ffi.Uint32()
  external int struct_size;
  @ffi.Uint32()
  external int abi_version;
  @ffi.Array(16)
  external ffi.Array<ffi.Uint8> selection_nonce;
  @ffi.Uint64()
  external int capture_id;
  @ffi.Uint64()
  external int window_incarnation;
  @ffi.Uint64()
  external int hwnd_value;
  @ffi.Uint32()
  external int process_id;
  @ffi.Uint32()
  external int reserved0;
  @ffi.Uint64()
  external int process_creation_filetime;
  @ffi.Uint64()
  external int host_epoch;
  @ffi.Uint64()
  external int grant_generation;
  @ffi.Uint64()
  external int runtime_source_generation;
  @ffi.Uint64()
  external int valid_until_tick_ms;
  @ffi.Array(32)
  external ffi.Array<ffi.Uint8> executable_sha256;
}

final class MiniAVWindowsStrictRetirementV1 extends ffi.Struct {
  @ffi.Uint32()
  external int struct_size;
  @ffi.Uint32()
  external int abi_version;
  @ffi.Uint64()
  external int capture_id;
  @ffi.Uint32()
  external int state;
  @ffi.Int32()
  external int terminal_reason;
  @ffi.Int32()
  external int cleanup_error;
  @ffi.Uint32()
  external int flags;
  @ffi.Uint32()
  external int callbacks_in_flight;
  @ffi.Uint32()
  external int buffers_outstanding;
  @ffi.Uint64()
  external int frames_posted;
  @ffi.Uint64()
  external int frames_released;
}

/// The configured geometry, read after Configure and before Start.
final class MiniAVWindowsStrictResourceProfileV1 extends ffi.Struct {
  @ffi.Uint32()
  external int struct_size;
  @ffi.Uint32()
  external int abi_version;
  @ffi.Uint64()
  external int capture_id;
  @ffi.Uint64()
  external int window_incarnation;
  @ffi.Uint32()
  external int width;
  @ffi.Uint32()
  external int height;
  @ffi.Uint32()
  external int pixel_format;
  @ffi.Uint32()
  external int pool_slots;
  @ffi.Uint32()
  external int max_outstanding_buffers;
  @ffi.Uint32()
  external int flags;
  @ffi.Uint64()
  external int frame_bytes;
  @ffi.Uint64()
  external int reserved0;
}

final class MiniAVWindowsStrictOwnerStorageExtentV1 extends ffi.Struct {
  @ffi.Uint32()
  external int kind;
  @ffi.Uint32()
  external int alignment;
  @ffi.Uint64()
  external int requested_bytes;
  @ffi.Uint64()
  external int reserved0;
}

final class MiniAVWindowsStrictOwnerStorageProfileV1 extends ffi.Struct {
  @ffi.Uint32()
  external int struct_size;
  @ffi.Uint32()
  external int abi_version;
  @ffi.Uint32()
  external int factory_revision;
  @ffi.Uint32()
  external int flags;
  @ffi.Array(10)
  external ffi.Array<ffi.Uint32> build_identity;
  @ffi.Uint32()
  external int role_count;
  @ffi.Uint32()
  external int additional_resources;
  @ffi.Uint64()
  external int total_requested_bytes;
  @ffi.Uint64()
  external int reserved0;
  @ffi.Array(2)
  external ffi.Array<MiniAVWindowsStrictOwnerStorageExtentV1> roles;
}

final class MiniAVWindowsStrictControlStorageProfileV1 extends ffi.Struct {
  @ffi.Uint32()
  external int struct_size;
  @ffi.Uint32()
  external int abi_version;
  @ffi.Uint32()
  external int factory_revision;
  @ffi.Uint32()
  external int flags;
  @ffi.Array(10)
  external ffi.Array<ffi.Uint32> build_identity;
  @ffi.Uint32()
  external int role_count;
  @ffi.Uint32()
  external int additional_resources;
  @ffi.Uint64()
  external int total_requested_bytes;
  @ffi.Uint64()
  external int reserved0;
  @ffi.Array(4)
  external ffi.Array<MiniAVWindowsStrictOwnerStorageExtentV1> roles;
}

final class MiniAVWindowsStrictControlStorageEventV1 extends ffi.Struct {
  @ffi.Uint32()
  external int size;
  @ffi.Uint32()
  external int version;
  @ffi.Uint32()
  external int event;
  @ffi.Uint32()
  external int role;
  @ffi.Uint64()
  external int generation;
  @ffi.Uint64()
  external int source_epoch;
  @ffi.Uint32()
  external int row;
  @ffi.Uint32()
  external int alignment;
  @ffi.Uint64()
  external int address;
  @ffi.Uint64()
  external int bytes;
}

typedef MiniAVWindowsStrictControlStorageScope =
    ffi.Void Function(ffi.Pointer<ffi.Void> context);
typedef MiniAVWindowsStrictControlStorageRecord =
    ffi.Uint32 Function(
      ffi.Pointer<ffi.Void> context,
      ffi.Pointer<MiniAVWindowsStrictControlStorageEventV1> record,
    );

/// Ledger callbacks run on native threads; only native code may supply them.
final class MiniAVWindowsStrictControlStorageOpsV1 extends ffi.Struct {
  external ffi.Pointer<
    ffi.NativeFunction<MiniAVWindowsStrictControlStorageScope>
  >
  retain;
  external ffi.Pointer<
    ffi.NativeFunction<MiniAVWindowsStrictControlStorageScope>
  >
  release;
  external ffi.Pointer<
    ffi.NativeFunction<MiniAVWindowsStrictControlStorageRecord>
  >
  event;
}

final class MiniAVWindowsStrictControlStorageExtentV1 extends ffi.Struct {
  @ffi.Uint64()
  external int requested_bytes;
  @ffi.Uint32()
  external int alignment;
  @ffi.Uint32()
  external int reserved0;
}

final class MiniAVWindowsStrictControlStorageAuthorityV1 extends ffi.Struct {
  @ffi.Uint32()
  external int struct_size;
  @ffi.Uint32()
  external int abi_version;
  external ffi.Pointer<ffi.Void> context;
  external ffi.Pointer<MiniAVWindowsStrictControlStorageOpsV1> ops;
  @ffi.Uint64()
  external int generation;
  @ffi.Uint64()
  external int source_epoch;
  @ffi.Uint32()
  external int row;
  @ffi.Uint32()
  external int role_count;
  @ffi.Uint64()
  external int reserved0;
  @ffi.Array(4)
  external ffi.Array<MiniAVWindowsStrictControlStorageExtentV1> roles;
}

final class MiniAVWindowsStrictControlStorageOutcomeV1 extends ffi.Struct {
  @ffi.Uint32()
  external int struct_size;
  @ffi.Uint32()
  external int abi_version;
  @ffi.Uint32()
  external int disposition;
  @ffi.Uint32()
  external int flags;
  @ffi.Int32()
  external int result;
  @ffi.Uint32()
  external int reserved0;
  @ffi.Uint64()
  external int generation;
  @ffi.Uint64()
  external int source_epoch;
  @ffi.Uint32()
  external int row;
  @ffi.Uint32()
  external int reserved1;
  @ffi.Uint64()
  external int context_value;
  @ffi.Uint64()
  external int reserved2;
}

final Map<String, int> miniavWindowsStrictRecordSizes = Map.unmodifiable({
  'MiniAVWindowsAppAdmissionV1': ffi.sizeOf<MiniAVWindowsAppAdmissionV1>(),
  'MiniAVWindowsSelectionNonceV1': ffi.sizeOf<MiniAVWindowsSelectionNonceV1>(),
  'MiniAVWindowsScreenCandidateV1': ffi
      .sizeOf<MiniAVWindowsScreenCandidateV1>(),
  'MiniAVWindowsStrictCaptureOptionsV1': ffi
      .sizeOf<MiniAVWindowsStrictCaptureOptionsV1>(),
  'MiniAVWindowsStrictWindowWitnessV1': ffi
      .sizeOf<MiniAVWindowsStrictWindowWitnessV1>(),
  'MiniAVWindowsStrictRetirementV1': ffi
      .sizeOf<MiniAVWindowsStrictRetirementV1>(),
  'MiniAVWindowsStrictResourceProfileV1': ffi
      .sizeOf<MiniAVWindowsStrictResourceProfileV1>(),
  'MiniAVWindowsStrictOwnerStorageExtentV1': ffi
      .sizeOf<MiniAVWindowsStrictOwnerStorageExtentV1>(),
  'MiniAVWindowsStrictOwnerStorageProfileV1': ffi
      .sizeOf<MiniAVWindowsStrictOwnerStorageProfileV1>(),
  'MiniAVWindowsStrictControlStorageProfileV1': ffi
      .sizeOf<MiniAVWindowsStrictControlStorageProfileV1>(),
  'MiniAVWindowsStrictControlStorageEventV1': ffi
      .sizeOf<MiniAVWindowsStrictControlStorageEventV1>(),
  'MiniAVWindowsStrictControlStorageOpsV1': ffi
      .sizeOf<MiniAVWindowsStrictControlStorageOpsV1>(),
  'MiniAVWindowsStrictControlStorageExtentV1': ffi
      .sizeOf<MiniAVWindowsStrictControlStorageExtentV1>(),
  'MiniAVWindowsStrictControlStorageAuthorityV1': ffi
      .sizeOf<MiniAVWindowsStrictControlStorageAuthorityV1>(),
  'MiniAVWindowsStrictControlStorageOutcomeV1': ffi
      .sizeOf<MiniAVWindowsStrictControlStorageOutcomeV1>(),
});

typedef _CapabilitiesNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Uint32>, ffi.Pointer<ffi.Uint64>);
typedef MiniAVWindowsStrictCapabilities =
    int Function(ffi.Pointer<ffi.Uint32>, ffi.Pointer<ffi.Uint64>);
typedef _MaxOutstandingNative = ffi.Int32 Function(ffi.Pointer<ffi.Uint32>);
typedef MiniAVWindowsStrictMaxOutstandingBuffers =
    int Function(ffi.Pointer<ffi.Uint32>);
typedef _OwnerStorageNative =
    ffi.Int32 Function(ffi.Pointer<MiniAVWindowsStrictOwnerStorageProfileV1>);
typedef MiniAVWindowsStrictGetOwnerStorageProfile =
    int Function(ffi.Pointer<MiniAVWindowsStrictOwnerStorageProfileV1>);
typedef _ControlStorageNative =
    ffi.Int32 Function(ffi.Pointer<MiniAVWindowsStrictControlStorageProfileV1>);
typedef MiniAVWindowsStrictGetControlStorageProfile =
    int Function(ffi.Pointer<MiniAVWindowsStrictControlStorageProfileV1>);
typedef _CreateFundedNative =
    ffi.Int32 Function(
      ffi.Pointer<MiniAVWindowsStrictControlStorageAuthorityV1>,
      ffi.Pointer<MiniAVWindowsStrictControlStorageOutcomeV1>,
    );
typedef MiniAVWindowsStrictCreateFundedControl =
    int Function(
      ffi.Pointer<MiniAVWindowsStrictControlStorageAuthorityV1>,
      ffi.Pointer<MiniAVWindowsStrictControlStorageOutcomeV1>,
    );
typedef _ReleaseFundedNative =
    ffi.Int32 Function(bindings.MiniAVScreenContextHandle);
typedef MiniAVWindowsStrictReleaseFundedControl =
    int Function(bindings.MiniAVScreenContextHandle);
typedef _BeginNative =
    ffi.Int32 Function(
      bindings.MiniAVScreenContextHandle,
      ffi.Pointer<MiniAVWindowsAppAdmissionV1>,
      ffi.Pointer<MiniAVWindowsSelectionNonceV1>,
      ffi.Pointer<ffi.Pointer<MiniAVWindowsScreenCandidateV1>>,
      ffi.Pointer<ffi.Uint32>,
    );
typedef MiniAVWindowsStrictBeginSelection =
    int Function(
      bindings.MiniAVScreenContextHandle,
      ffi.Pointer<MiniAVWindowsAppAdmissionV1>,
      ffi.Pointer<MiniAVWindowsSelectionNonceV1>,
      ffi.Pointer<ffi.Pointer<MiniAVWindowsScreenCandidateV1>>,
      ffi.Pointer<ffi.Uint32>,
    );
typedef _BeginV2Native =
    ffi.Int32 Function(
      bindings.MiniAVScreenContextHandle,
      ffi.Pointer<MiniAVWindowsAppAdmissionV1>,
      ffi.Pointer<MiniAVWindowsSelectionNonceV1>,
      ffi.Pointer<ffi.Uint32>,
    );
typedef MiniAVWindowsStrictBeginSelectionV2 =
    int Function(
      bindings.MiniAVScreenContextHandle,
      ffi.Pointer<MiniAVWindowsAppAdmissionV1>,
      ffi.Pointer<MiniAVWindowsSelectionNonceV1>,
      ffi.Pointer<ffi.Uint32>,
    );
typedef _CopyNative =
    ffi.Int32 Function(
      bindings.MiniAVScreenContextHandle,
      ffi.Pointer<MiniAVWindowsSelectionNonceV1>,
      ffi.Uint32,
      ffi.Pointer<MiniAVWindowsScreenCandidateV1>,
    );
typedef MiniAVWindowsStrictCopyCandidate =
    int Function(
      bindings.MiniAVScreenContextHandle,
      ffi.Pointer<MiniAVWindowsSelectionNonceV1>,
      int,
      ffi.Pointer<MiniAVWindowsScreenCandidateV1>,
    );
typedef _ConfigureNative =
    ffi.Int32 Function(
      bindings.MiniAVScreenContextHandle,
      ffi.Pointer<MiniAVWindowsSelectionNonceV1>,
      ffi.Uint64,
      ffi.Pointer<bindings.MiniAVVideoInfo>,
      ffi.Pointer<MiniAVWindowsStrictCaptureOptionsV1>,
      ffi.Pointer<MiniAVWindowsStrictWindowWitnessV1>,
    );
typedef MiniAVWindowsStrictConfigureWindow =
    int Function(
      bindings.MiniAVScreenContextHandle,
      ffi.Pointer<MiniAVWindowsSelectionNonceV1>,
      int,
      ffi.Pointer<bindings.MiniAVVideoInfo>,
      ffi.Pointer<MiniAVWindowsStrictCaptureOptionsV1>,
      ffi.Pointer<MiniAVWindowsStrictWindowWitnessV1>,
    );
typedef _ResourceProfileNative =
    ffi.Int32 Function(
      bindings.MiniAVScreenContextHandle,
      ffi.Pointer<MiniAVWindowsStrictResourceProfileV1>,
    );
typedef MiniAVWindowsStrictGetResourceProfile =
    int Function(
      bindings.MiniAVScreenContextHandle,
      ffi.Pointer<MiniAVWindowsStrictResourceProfileV1>,
    );
typedef _StopNative =
    ffi.Int32 Function(bindings.MiniAVScreenContextHandle, ffi.Int32);
typedef MiniAVWindowsStrictRequestStop =
    int Function(bindings.MiniAVScreenContextHandle, int);
typedef _RetirementNative =
    ffi.Int32 Function(
      bindings.MiniAVScreenContextHandle,
      ffi.Pointer<MiniAVWindowsStrictRetirementV1>,
    );
typedef MiniAVWindowsStrictGetRetirement =
    int Function(
      bindings.MiniAVScreenContextHandle,
      ffi.Pointer<MiniAVWindowsStrictRetirementV1>,
    );
typedef _SizeNative = ffi.Uint32 Function(ffi.Pointer<ffi.Char>);
typedef _Size = int Function(ffi.Pointer<ffi.Char>);

@ffi.Native<_CapabilitiesNative>(
  symbol: 'MiniAV_Screen_Windows_StrictCapabilitiesV1',
)
external int _capabilities(
  ffi.Pointer<ffi.Uint32> bits,
  ffi.Pointer<ffi.Uint64> tick,
);
@ffi.Native<_MaxOutstandingNative>(
  symbol: 'MiniAV_Screen_Windows_StrictMaxOutstandingBuffersV1',
)
external int _maxOutstanding(ffi.Pointer<ffi.Uint32> maximum);
@ffi.Native<_OwnerStorageNative>(
  symbol: 'MiniAV_Screen_Windows_GetStrictOwnerStorageProfileV1',
)
external int _ownerStorage(
  ffi.Pointer<MiniAVWindowsStrictOwnerStorageProfileV1> profile,
);
@ffi.Native<_ControlStorageNative>(
  symbol: 'MiniAV_Screen_Windows_GetStrictControlStorageProfileV1',
)
external int _controlStorage(
  ffi.Pointer<MiniAVWindowsStrictControlStorageProfileV1> profile,
);
@ffi.Native<_CreateFundedNative>(
  symbol: 'MiniAV_Screen_Windows_CreateFundedControlV1',
)
external int _createFunded(
  ffi.Pointer<MiniAVWindowsStrictControlStorageAuthorityV1> authority,
  ffi.Pointer<MiniAVWindowsStrictControlStorageOutcomeV1> outcome,
);
@ffi.Native<_ReleaseFundedNative>(
  symbol: 'MiniAV_Screen_Windows_ReleaseFundedControlV1',
)
external int _releaseFunded(bindings.MiniAVScreenContextHandle context);
@ffi.Native<_BeginNative>(
  symbol: 'MiniAV_Screen_Windows_BeginStrictSelectionV1',
)
external int _begin(
  bindings.MiniAVScreenContextHandle context,
  ffi.Pointer<MiniAVWindowsAppAdmissionV1> admission,
  ffi.Pointer<MiniAVWindowsSelectionNonceV1> nonce,
  ffi.Pointer<ffi.Pointer<MiniAVWindowsScreenCandidateV1>> candidates,
  ffi.Pointer<ffi.Uint32> count,
);
@ffi.Native<_BeginV2Native>(
  symbol: 'MiniAV_Screen_Windows_BeginStrictSelectionV2',
)
external int _beginV2(
  bindings.MiniAVScreenContextHandle context,
  ffi.Pointer<MiniAVWindowsAppAdmissionV1> admission,
  ffi.Pointer<MiniAVWindowsSelectionNonceV1> nonce,
  ffi.Pointer<ffi.Uint32> count,
);
@ffi.Native<_CopyNative>(
  symbol: 'MiniAV_Screen_Windows_CopyStrictSelectionCandidateV1',
)
external int _copy(
  bindings.MiniAVScreenContextHandle context,
  ffi.Pointer<MiniAVWindowsSelectionNonceV1> nonce,
  int index,
  ffi.Pointer<MiniAVWindowsScreenCandidateV1> candidate,
);
@ffi.Native<_ConfigureNative>(
  symbol: 'MiniAV_Screen_Windows_ConfigureStrictWindowV1',
)
external int _configure(
  bindings.MiniAVScreenContextHandle context,
  ffi.Pointer<MiniAVWindowsSelectionNonceV1> nonce,
  int candidate,
  ffi.Pointer<bindings.MiniAVVideoInfo> format,
  ffi.Pointer<MiniAVWindowsStrictCaptureOptionsV1> options,
  ffi.Pointer<MiniAVWindowsStrictWindowWitnessV1> witness,
);
@ffi.Native<_ResourceProfileNative>(
  symbol: 'MiniAV_Screen_Windows_GetStrictResourceProfileV1',
)
external int _resourceProfile(
  bindings.MiniAVScreenContextHandle context,
  ffi.Pointer<MiniAVWindowsStrictResourceProfileV1> profile,
);
@ffi.Native<_StopNative>(symbol: 'MiniAV_Screen_Windows_RequestStrictStopV1')
external int _stop(bindings.MiniAVScreenContextHandle context, int reason);
@ffi.Native<_RetirementNative>(
  symbol: 'MiniAV_Screen_Windows_GetStrictRetirementV1',
)
external int _retirement(
  bindings.MiniAVScreenContextHandle context,
  ffi.Pointer<MiniAVWindowsStrictRetirementV1> receipt,
);

/// Resolves only optional ABI entry points; this never opens capture or a GPU.
/// The supplied library is retained, but pinning it does not establish trust.
/// An installed trusted host must independently authorize its actual provider.
/// Raw admission fields must come from that host's retained native owner.
final class MiniAVWindowsStrictScreenBindings {
  MiniAVWindowsStrictScreenBindings._({
    required this.library,
    required this.capabilities,
    required this.maxOutstandingBuffers,
    required this.getOwnerStorageProfile,
    required this.getControlStorageProfile,
    required this.createFundedControl,
    required this.releaseFundedControl,
    required this.beginSelection,
    required this.beginSelectionV2,
    required this.copyCandidate,
    required this.configureWindow,
    required this.getResourceProfile,
    required this.requestStop,
    required this.getRetirement,
    required _Size size,
  }) : _size = size;

  final ffi.DynamicLibrary? library;
  final MiniAVWindowsStrictCapabilities capabilities;
  final MiniAVWindowsStrictMaxOutstandingBuffers maxOutstandingBuffers;
  final MiniAVWindowsStrictGetOwnerStorageProfile getOwnerStorageProfile;
  final MiniAVWindowsStrictGetControlStorageProfile getControlStorageProfile;
  final MiniAVWindowsStrictCreateFundedControl createFundedControl;
  final MiniAVWindowsStrictReleaseFundedControl releaseFundedControl;
  final MiniAVWindowsStrictBeginSelection beginSelection;

  /// Begin without an owned candidate array; read each with [copyCandidate].
  final MiniAVWindowsStrictBeginSelectionV2 beginSelectionV2;
  final MiniAVWindowsStrictCopyCandidate copyCandidate;
  final MiniAVWindowsStrictConfigureWindow configureWindow;
  final MiniAVWindowsStrictGetResourceProfile getResourceProfile;
  final MiniAVWindowsStrictRequestStop requestStop;
  final MiniAVWindowsStrictGetRetirement getRetirement;
  final _Size _size;

  /// Missing ANY symbol returns absent; old generic bindings stay untouched.
  /// Passing a library supports embedders with an explicitly owned provider.
  static MiniAVWindowsStrictScreenBindings? tryResolve({
    ffi.DynamicLibrary? library,
  }) {
    if (ffi.Abi.current() != ffi.Abi.windowsX64) return null;
    try {
      if (library != null) {
        return MiniAVWindowsStrictScreenBindings._(
          library: library,
          capabilities: library
              .lookupFunction<
                _CapabilitiesNative,
                MiniAVWindowsStrictCapabilities
              >('MiniAV_Screen_Windows_StrictCapabilitiesV1'),
          maxOutstandingBuffers: library
              .lookupFunction<
                _MaxOutstandingNative,
                MiniAVWindowsStrictMaxOutstandingBuffers
              >('MiniAV_Screen_Windows_StrictMaxOutstandingBuffersV1'),
          getOwnerStorageProfile: library
              .lookupFunction<
                _OwnerStorageNative,
                MiniAVWindowsStrictGetOwnerStorageProfile
              >('MiniAV_Screen_Windows_GetStrictOwnerStorageProfileV1'),
          getControlStorageProfile: library
              .lookupFunction<
                _ControlStorageNative,
                MiniAVWindowsStrictGetControlStorageProfile
              >('MiniAV_Screen_Windows_GetStrictControlStorageProfileV1'),
          createFundedControl: library
              .lookupFunction<
                _CreateFundedNative,
                MiniAVWindowsStrictCreateFundedControl
              >('MiniAV_Screen_Windows_CreateFundedControlV1'),
          releaseFundedControl: library
              .lookupFunction<
                _ReleaseFundedNative,
                MiniAVWindowsStrictReleaseFundedControl
              >('MiniAV_Screen_Windows_ReleaseFundedControlV1'),
          beginSelection: library
              .lookupFunction<_BeginNative, MiniAVWindowsStrictBeginSelection>(
                'MiniAV_Screen_Windows_BeginStrictSelectionV1',
              ),
          beginSelectionV2: library
              .lookupFunction<
                _BeginV2Native,
                MiniAVWindowsStrictBeginSelectionV2
              >('MiniAV_Screen_Windows_BeginStrictSelectionV2'),
          copyCandidate: library
              .lookupFunction<_CopyNative, MiniAVWindowsStrictCopyCandidate>(
                'MiniAV_Screen_Windows_CopyStrictSelectionCandidateV1',
              ),
          configureWindow: library
              .lookupFunction<
                _ConfigureNative,
                MiniAVWindowsStrictConfigureWindow
              >('MiniAV_Screen_Windows_ConfigureStrictWindowV1'),
          getResourceProfile: library
              .lookupFunction<
                _ResourceProfileNative,
                MiniAVWindowsStrictGetResourceProfile
              >('MiniAV_Screen_Windows_GetStrictResourceProfileV1'),
          requestStop: library
              .lookupFunction<_StopNative, MiniAVWindowsStrictRequestStop>(
                'MiniAV_Screen_Windows_RequestStrictStopV1',
              ),
          getRetirement: library
              .lookupFunction<
                _RetirementNative,
                MiniAVWindowsStrictGetRetirement
              >('MiniAV_Screen_Windows_GetStrictRetirementV1'),
          size: library.lookupFunction<_SizeNative, _Size>(
            'MiniAV_ABI_StructSize',
          ),
        );
      }
      return MiniAVWindowsStrictScreenBindings._(
        library: null,
        capabilities:
            ffi.Native.addressOf<ffi.NativeFunction<_CapabilitiesNative>>(
              _capabilities,
            ).asFunction<MiniAVWindowsStrictCapabilities>(),
        maxOutstandingBuffers:
            ffi.Native.addressOf<ffi.NativeFunction<_MaxOutstandingNative>>(
              _maxOutstanding,
            ).asFunction<MiniAVWindowsStrictMaxOutstandingBuffers>(),
        getOwnerStorageProfile:
            ffi.Native.addressOf<ffi.NativeFunction<_OwnerStorageNative>>(
              _ownerStorage,
            ).asFunction<MiniAVWindowsStrictGetOwnerStorageProfile>(),
        getControlStorageProfile:
            ffi.Native.addressOf<ffi.NativeFunction<_ControlStorageNative>>(
              _controlStorage,
            ).asFunction<MiniAVWindowsStrictGetControlStorageProfile>(),
        createFundedControl:
            ffi.Native.addressOf<ffi.NativeFunction<_CreateFundedNative>>(
              _createFunded,
            ).asFunction<MiniAVWindowsStrictCreateFundedControl>(),
        releaseFundedControl:
            ffi.Native.addressOf<ffi.NativeFunction<_ReleaseFundedNative>>(
              _releaseFunded,
            ).asFunction<MiniAVWindowsStrictReleaseFundedControl>(),
        beginSelection: ffi.Native.addressOf<ffi.NativeFunction<_BeginNative>>(
          _begin,
        ).asFunction<MiniAVWindowsStrictBeginSelection>(),
        beginSelectionV2:
            ffi.Native.addressOf<ffi.NativeFunction<_BeginV2Native>>(
              _beginV2,
            ).asFunction<MiniAVWindowsStrictBeginSelectionV2>(),
        copyCandidate: ffi.Native.addressOf<ffi.NativeFunction<_CopyNative>>(
          _copy,
        ).asFunction<MiniAVWindowsStrictCopyCandidate>(),
        configureWindow:
            ffi.Native.addressOf<ffi.NativeFunction<_ConfigureNative>>(
              _configure,
            ).asFunction<MiniAVWindowsStrictConfigureWindow>(),
        getResourceProfile:
            ffi.Native.addressOf<ffi.NativeFunction<_ResourceProfileNative>>(
              _resourceProfile,
            ).asFunction<MiniAVWindowsStrictGetResourceProfile>(),
        requestStop: ffi.Native.addressOf<ffi.NativeFunction<_StopNative>>(
          _stop,
        ).asFunction<MiniAVWindowsStrictRequestStop>(),
        getRetirement:
            ffi.Native.addressOf<ffi.NativeFunction<_RetirementNative>>(
              _retirement,
            ).asFunction<MiniAVWindowsStrictGetRetirement>(),
        size: bindings.MiniAV_ABI_StructSize,
      );
    } catch (_) {
      return null;
    }
  }

  /// Capability-zero scaffolding is unavailable, even when all exports exist.
  /// A complete provider must also match every native record allocation size.
  bool get isSupported {
    final bits = calloc<ffi.Uint32>(), tick = calloc<ffi.Uint64>();
    try {
      if (capabilities(bits, tick) != 0 ||
          bits.value != 15 ||
          tick.value <= 0) {
        return false;
      }
      for (final entry in miniavWindowsStrictRecordSizes.entries) {
        final name = entry.key.toNativeUtf8();
        try {
          if (_size(name.cast<ffi.Char>()) != entry.value) return false;
        } finally {
          calloc.free(name);
        }
      }
      return true;
    } finally {
      calloc.free(bits);
      calloc.free(tick);
    }
  }
}
