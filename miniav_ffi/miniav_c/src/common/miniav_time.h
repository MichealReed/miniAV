#ifndef MINIAV_TIME_H
#define MINIAV_TIME_H

#include <stdint.h>

#if defined(_WIN32)
#include <windows.h> // For LARGE_INTEGER
#endif

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Gets the current high-resolution time in microseconds.
 * This time is suitable for general-purpose timestamping.
 * @return Current time in microseconds.
 */
uint64_t miniav_get_time_us(void);

#if defined(_WIN32)
/**
 * @brief Gets the Query Performance Counter (QPC) frequency.
 * Only available on Windows.
 * @return The QPC frequency as a LARGE_INTEGER.
 */
LARGE_INTEGER miniav_get_qpc_frequency(void);

/**
 * @brief Converts a Query Performance Counter (QPC) value to microseconds.
 * Only available on Windows.
 * @param qpc_value The QPC value to convert.
 * @param qpc_frequency The QPC frequency (obtained from miniav_get_qpc_frequency).
 * @return The time in microseconds.
 */
uint64_t miniav_qpc_to_microseconds(LARGE_INTEGER qpc_value, LARGE_INTEGER qpc_frequency);
#endif // _WIN32


#ifdef __cplusplus
}
#endif

#endif // MINIAV_TIME_H