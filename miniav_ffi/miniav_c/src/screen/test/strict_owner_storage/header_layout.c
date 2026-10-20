#include "../../../../include/miniav_screen_windows_strict.h"
#include <stddef.h>
_Static_assert(sizeof(MiniAVWindowsStrictOwnerStorageExtentV1) == 24, "extent C ABI");
_Static_assert(sizeof(MiniAVWindowsStrictOwnerStorageProfileV1) == 128, "profile C ABI");
_Static_assert(offsetof(MiniAVWindowsStrictOwnerStorageProfileV1, roles) == 80, "profile roles C ABI");
_Static_assert(sizeof(MiniAVWindowsStrictControlStorageProfileV1) == 176, "control profile C ABI");
_Static_assert(sizeof(MiniAVWindowsStrictControlStorageEventV1) == 56, "control event C ABI");
_Static_assert(sizeof(MiniAVWindowsStrictControlStorageAuthorityV1) == 120, "control authority C ABI");
_Static_assert(offsetof(MiniAVWindowsStrictControlStorageAuthorityV1, roles) == 56, "authority roles C ABI");
_Static_assert(sizeof(MiniAVWindowsStrictControlStorageOutcomeV1) == 64, "control outcome C ABI");
int miniav_owner_storage_c_header_layout(void) { return 1; }
