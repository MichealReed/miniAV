#ifndef MINIAV_TIME_H
#define MINIAV_TIME_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Returns monotonic time in microseconds
uint64_t miniav_get_time_us(void);

#ifdef __cplusplus
}
#endif

#endif // MINIAV_TIME_H