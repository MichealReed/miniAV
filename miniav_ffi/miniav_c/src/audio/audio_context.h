#ifndef AUDIO_CONTEXT_H
#define AUDIO_CONTEXT_H

#include "../../include/miniav_types.h"
#include "../../include/miniav_buffer.h"
#include "../common/miniav_context_base.h"

// Use miniaudio as the backend
#define MA_NO_DECODING
#define MA_NO_ENCODING
#include "miniaudio.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MiniAVAudioContext MiniAVAudioContext;


#ifdef __cplusplus
}
#endif

#endif // AUDIO_CONTEXT_H
