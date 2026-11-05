#ifndef STEAMBRIDGE_RESOLVER_AOB_H
#define STEAMBRIDGE_RESOLVER_AOB_H

#include <stdint.h>
#include <stddef.h>

typedef struct {
    uint8_t *bytes;
    uint8_t *mask;
    int      length;
} sb_byte_pattern_t;

int sb_compile_pattern(const char *hex_str, sb_byte_pattern_t *out);

void sb_release_pattern(sb_byte_pattern_t *pat);

uintptr_t sb_scan_sole_match(uintptr_t base, size_t size, const sb_byte_pattern_t *pat);

#endif
