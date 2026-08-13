// ABI size probe.
//
// Every struct here is allocated on ONE side of the FFI boundary and read or
// copied on the other. A binding generator that has not been re-run since a
// field was appended produces a Dart struct that is SMALLER than the C one;
// `calloc<T>()` then under-allocates and the first `*dst = *src;` in C reads
// past the end of the allocation. That is exactly how MiniAVInputConfig's
// motion fields (appended in 0.7.x) turned into a garbage function pointer in
// MiniAVInputContext::config.
//
// "ABI-additive" only ever meant OFFSETS are stable. sizeof() is NOT, and
// sizeof() is what calloc and struct assignment use.
//
// Dart asserts sizeOf<T>() == MiniAV_ABI_StructSize("T") for every name below
// (test/abi_struct_size_test.dart). Add a struct here the moment it starts
// crossing the boundary; unknown names return 0 so a typo fails loudly.

#include "../include/miniav_buffer.h"
#include "../include/miniav_capture.h"
#include "../include/miniav_types.h"

#include <stddef.h>
#include <string.h>

typedef struct {
  const char *name;
  uint32_t size;
} MiniAVAbiEntry;

#define MINIAV_ABI_ENTRY(T)                                                    \
  { #T, (uint32_t)sizeof(T) }

// MiniAVBuffer's payload union / fence are ANONYMOUS in C, so ffigen names
// them UnnamedUnion2 / UnnamedStruct1 / ... and the fence is hand-written in
// the Dart bindings (it carries an explicit pad0). Size them individually:
// a compensating pair of errors inside the union would otherwise leave
// sizeof(MiniAVBuffer) matching while a member is misaligned.
#define MINIAV_ABI_MEMBER(Name, T, Member)                                     \
  { Name, (uint32_t)sizeof(((T *)0)->Member) }

static const MiniAVAbiEntry k_abi_table[] = {
    MINIAV_ABI_ENTRY(MiniAVDeviceInfo),
    MINIAV_ABI_ENTRY(MiniAVVideoInfo),
    MINIAV_ABI_ENTRY(MiniAVAudioInfo),
    MINIAV_ABI_ENTRY(MiniAVLoopbackTargetInfo),
    MINIAV_ABI_ENTRY(MiniAVKeyboardEvent),
    MINIAV_ABI_ENTRY(MiniAVMouseEvent),
    MINIAV_ABI_ENTRY(MiniAVGamepadEvent),
    MINIAV_ABI_ENTRY(MiniAVVec3),
    MINIAV_ABI_ENTRY(MiniAVQuat),
    MINIAV_ABI_ENTRY(MiniAVMotionEvent),
    MINIAV_ABI_ENTRY(MiniAVInputConfig),
    MINIAV_ABI_ENTRY(MiniAVVideoPlane),
    MINIAV_ABI_ENTRY(MiniAVBuffer),
    MINIAV_ABI_ENTRY(MiniAVNativeBufferInternalPayload),
    MINIAV_ABI_MEMBER("MiniAVLoopbackTargetInfo.TARGETHANDLE",
                      MiniAVLoopbackTargetInfo, TARGETHANDLE),
    MINIAV_ABI_MEMBER("MiniAVBuffer.data", MiniAVBuffer, data),
    MINIAV_ABI_MEMBER("MiniAVBuffer.data.video", MiniAVBuffer, data.video),
    MINIAV_ABI_MEMBER("MiniAVBuffer.data.audio", MiniAVBuffer, data.audio),
};

MINIAV_API uint32_t MiniAV_ABI_StructSize(const char *struct_name) {
  if (!struct_name) {
    return 0;
  }
  for (size_t i = 0; i < sizeof(k_abi_table) / sizeof(k_abi_table[0]); ++i) {
    if (strcmp(k_abi_table[i].name, struct_name) == 0) {
      return k_abi_table[i].size;
    }
  }
  return 0;
}

MINIAV_API uint32_t MiniAV_ABI_StructCount(void) {
  return (uint32_t)(sizeof(k_abi_table) / sizeof(k_abi_table[0]));
}

MINIAV_API const char *MiniAV_ABI_StructNameAt(uint32_t index) {
  if (index >= sizeof(k_abi_table) / sizeof(k_abi_table[0])) {
    return NULL;
  }
  return k_abi_table[index].name;
}
