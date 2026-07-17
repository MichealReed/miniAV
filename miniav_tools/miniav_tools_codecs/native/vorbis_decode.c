/* vorbis_decode.c — first-party Ogg Vorbis decode via stb_vorbis (public
 * domain). FFmpeg-free. Whole-buffer decode → malloc'd interleaved float32. */
#define STB_VORBIS_NO_STDIO
#define STB_VORBIS_NO_PUSHDATA_API
#include "third_party/stb_vorbis.c"

#include <stdint.h>
#include <stdlib.h>

#if defined(_WIN32)
#  define MSW_API __declspec(dllexport)
#else
#  define MSW_API __attribute__((visibility("default")))
#endif

/* Decode a whole Ogg-Vorbis byte buffer into interleaved float32. See
 * miniav_mp3_decode for the contract (free *out via miniav_sw_free). */
MSW_API int miniav_vorbis_decode(const uint8_t *data, int len, float **out,
                                 int *channels, int *rate) {
  if (!data || len <= 0 || !out) return -1;
  int err = 0;
  stb_vorbis *v = stb_vorbis_open_memory(data, len, &err, NULL);
  if (!v) return -1;
  stb_vorbis_info info = stb_vorbis_get_info(v);
  unsigned int total = stb_vorbis_stream_length_in_samples(v); /* frames/ch */
  float *buf =
      (float *)malloc((size_t)total * info.channels * sizeof(float));
  if (!buf) {
    stb_vorbis_close(v);
    return -1;
  }
  int read = stb_vorbis_get_samples_float_interleaved(
      v, info.channels, buf, (int)(total * info.channels));
  *out = buf;
  if (channels) *channels = info.channels;
  if (rate) *rate = (int)info.sample_rate;
  stb_vorbis_close(v);
  return read; /* frames per channel */
}
