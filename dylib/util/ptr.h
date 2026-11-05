#ifndef STEAMBRIDGE_UTIL_PTR_H
#define STEAMBRIDGE_UTIL_PTR_H

#include <stdint.h>

static inline int sb_plausible_ptr(uint64_t v) {
    if (v < 0x100000000ULL)      return 0;
    if (v >= 0x800000000000ULL)  return 0;
    if (v & 0x7)                 return 0;
    return 1;
}

#endif
