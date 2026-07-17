/* mp3_decode.c — first-party MP3 decode via dr_mp3 (public domain).
 * FFmpeg-free. Whole-buffer decode → malloc'd interleaved float32. */
#define DR_MP3_IMPLEMENTATION
#define DR_MP3_NO_STDIO
#include "third_party/dr_mp3.h"

#include <stdint.h>
#include <stdlib.h>

#if defined(_WIN32)
#  define MSW_API __declspec(dllexport)
#else
#  define MSW_API __attribute__((visibility("default")))
#endif

/* Decode a whole MP3 byte buffer into interleaved float32.
 * On success returns frames-per-channel (>=0) and sets *out to a malloc'd
 * buffer of (frames*channels) floats (free via miniav_sw_free), plus the
 * channel count and sample rate. Returns -1 on error. */
MSW_API int miniav_mp3_decode(const uint8_t *data, int len, float **out,
                              int *channels, int *rate) {
  if (!data || len <= 0 || !out) return -1;
  drmp3 mp3;
  if (!drmp3_init_memory(&mp3, data, (size_t)len, NULL)) return -1;
  drmp3_uint64 total = drmp3_get_pcm_frame_count(&mp3);
  float *buf = (float *)malloc((size_t)total * mp3.channels * sizeof(float));
  if (!buf) {
    drmp3_uninit(&mp3);
    return -1;
  }
  drmp3_uint64 read = drmp3_read_pcm_frames_f32(&mp3, total, buf);
  *out = buf;
  if (channels) *channels = (int)mp3.channels;
  if (rate) *rate = (int)mp3.sampleRate;
  drmp3_uninit(&mp3);
  return (int)read;
}

/* Free a buffer returned by any miniav_*_decode function. */
MSW_API void miniav_sw_free(void *p) { free(p); }
