#include "miniav_time.h"

#if defined(_WIN32)
#include <windows.h>

// Static variable to store the frequency so it's queried only once.
static LARGE_INTEGER g_qpc_frequency;
static BOOL g_qpc_frequency_initialized = FALSE;

uint64_t miniav_get_time_us(void) {
  if (!g_qpc_frequency_initialized) {
    QueryPerformanceFrequency(&g_qpc_frequency);
    g_qpc_frequency_initialized = TRUE;
  }
  LARGE_INTEGER counter;
  QueryPerformanceCounter(&counter);
  // Multiply by 1,000,000 (microseconds per second)
  return (uint64_t)((counter.QuadPart * 1000000) / g_qpc_frequency.QuadPart);
}

LARGE_INTEGER miniav_get_qpc_frequency(void) {
  if (!g_qpc_frequency_initialized) {
    QueryPerformanceFrequency(&g_qpc_frequency);
    g_qpc_frequency_initialized = TRUE;
  }
  return g_qpc_frequency;
}

uint64_t miniav_qpc_to_microseconds(LARGE_INTEGER qpc_value,
                                    LARGE_INTEGER qpc_frequency) {
  if (qpc_frequency.QuadPart == 0) {
    return 0; // Avoid division by zero
  }
  // Multiply by 1,000,000 (microseconds per second) then divide by frequency.
  // Ensure intermediate multiplication doesn't overflow.
  return (uint64_t)((qpc_value.QuadPart * 1000000) / qpc_frequency.QuadPart);
}

#elif defined(__APPLE__)
#include <mach/mach_time.h>

uint64_t miniav_get_time_us(void) {
  static mach_timebase_info_data_t timebase;
  static int initialized = 0;
  if (!initialized) {
    mach_timebase_info(&timebase);
    initialized = 1;
  }
  uint64_t t = mach_absolute_time();
  return (t * timebase.numer / timebase.denom) / 1000;
}

#else // POSIX
#include <time.h>

uint64_t miniav_get_time_us(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t)ts.tv_sec * 1000000 + ts.tv_nsec / 1000;
}
#endif