/* flac_decode.c — first-party FLAC decode via dr_flac (public domain).
 * FFmpeg-free. Whole-buffer decode → malloc'd interleaved float32. */
#define DR_FLAC_IMPLEMENTATION
#define DR_FLAC_NO_STDIO
#include "third_party/dr_flac.h"

#include <stdint.h>
#include <stdlib.h>

#if defined(_WIN32)
#  define MSW_API __declspec(dllexport)
#else
#  define MSW_API __attribute__((visibility("default")))
#endif

/* Decode a whole FLAC byte buffer into interleaved float32. See
 * miniav_mp3_decode for the contract (free *out via miniav_sw_free). */
MSW_API int miniav_flac_decode(const uint8_t *data, int len, float **out,
                               int *channels, int *rate) {
  if (!data || len <= 0 || !out) return -1;
  drflac *f = drflac_open_memory(data, (size_t)len, NULL);
  if (!f) return -1;
  drflac_uint64 total = f->totalPCMFrameCount;
  float *buf = (float *)malloc((size_t)total * f->channels * sizeof(float));
  if (!buf) {
    drflac_close(f);
    return -1;
  }
  drflac_uint64 read = drflac_read_pcm_frames_f32(f, total, buf);
  *out = buf;
  if (channels) *channels = (int)f->channels;
  if (rate) *rate = (int)f->sampleRate;
  drflac_close(f);
  return (int)read;
}
