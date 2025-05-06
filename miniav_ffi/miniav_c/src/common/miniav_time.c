#include "miniav_time.h"

#if defined(_WIN32)
#include <windows.h>

uint64_t miniav_get_time_us(void) {
    static LARGE_INTEGER freq;
    static BOOL freq_init = FALSE;
    if (!freq_init) {
        QueryPerformanceFrequency(&freq);
        freq_init = TRUE;
    }
    LARGE_INTEGER counter;
    QueryPerformanceCounter(&counter);
    return (uint64_t)((counter.QuadPart * 1000000) / freq.QuadPart);
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