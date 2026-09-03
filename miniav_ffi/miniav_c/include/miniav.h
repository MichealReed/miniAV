#ifndef MINIAV_H
#define MINIAV_H

#include <stdint.h>
#include <stddef.h>

#include "miniav_types.h"
#include "miniav_buffer.h"
#include "miniav_capture.h"
// Playback (MiniAV_AudioOutput_*) belongs in the umbrella header too. Omitting
// it did not fail to link — the symbols are exported — it failed at the LANGUAGE
// level: a C consumer that included only <miniav.h> got an implicit declaration
// for MiniAV_AudioOutput_CreateContext, which C assumes returns `int`. That
// truncates the returned 64-bit MiniAVAudioOutputContextHandle to 32 bits, and
// the first call that dereferences it segfaults inside miniaudio. Any new
// public header must be added here.
#include "miniav_playback.h"

#endif // MINIAV_H