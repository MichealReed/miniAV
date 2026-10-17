# Strict owner storage CPU witness

This opt-in target compiles the real strict owner and common factories. It
constructs a cold platform object, calls no public screen-context creation,
initializes no COM/GPU, launches no worker and never
captures a window or frame. Unrelated activation entrypoints abort if invoked.
The test's fixed callbacks model original ledger custody; they are not a host
SDK budget bridge, process consent or a native worker-join receipt.

From the `miniav_c` directory, with the inspected MSVC toolset installed:

```powershell
$ownerBuild = Join-Path $env:TEMP 'miniav-owner-storage'
cmake -S src/screen/test/strict_owner_storage -B "$ownerBuild" -G "Visual Studio 17 2022" -A x64 -T "v143,version=14.40.33807"
cmake --build "$ownerBuild" --config Release --target miniav_strict_owner_storage_cpu miniav_strict_owner_storage_unsupported_cpu -- /m:2
& "$ownerBuild/Release/miniav_strict_owner_storage_cpu.exe"
& "$ownerBuild/Release/miniav_strict_owner_storage_unsupported_cpu.exe"
```

The exact-layout adapter qualifies Windows x64 MSVC19.40.33818, STL143/update
202402, C++17, NDEBUG, iterator-debug0, dynamic multithreaded CRT. Other builds
refuse funded construction before heap entry. Legacy unscoped construction
remains available; its allocations are not the funded profile's shared block.

The fixed observer checks actual operator-new/delete requests and addresses,
real C++ platform construction/destruction and initialized atomics/null WinRT
references, extra strong and weak aliases, final physical free, original-domain/epoch and
extent refusal before either allocation, both allocation-failure positions,
readable ownership on pre-free refusal, and consumed-pointer success after a
post-free receipt refusal. Unknown custody retains the original authority/debt.
The forced-unsupported executable observes zero allocations over the refused
query and factory call.

To compare the public query in an actual built DLL with those witnessed sizes:

```powershell
dart src/screen/test/strict_owner_storage/probe_dll.dart C:/absolute/path/miniav_c.dll HOLDER_BYTES OWNER_BYTES
```

Replace the last arguments with that build's witness output. The probe checks
the defining module, C ABI, headers, unknown suffix and exact requested sizes.
It does not create a context or attest the DLL's asset provenance. Do not copy
observed byte counts into a host's enforcement constants.

`MiniAV_Screen_Windows_GetStrictOwnerStorageProfileV1` describes two allocations
additional to the screen/platform pair. Its staged internal funded factory is
not selected by ordinary context creation. Base/platform storage, host binding,
other control allocations, OS/driver/allocator costs and actual source lifecycle
still need their own admission and qualification. This is not capture readiness.
