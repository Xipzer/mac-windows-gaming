#include "aob.h"
#include "../util/log.h"
#include "../util/hex.h"

#include <stdlib.h>
#include <string.h>

int sb_compile_pattern(const char *hex_str, sb_byte_pattern_t *out) {
    if (!hex_str || !out) return -1;
    memset(out, 0, sizeof(*out));

    size_t max_len = strlen(hex_str) / 2 + 1;
    uint8_t *b = calloc(max_len, 1);
    uint8_t *m = calloc(max_len, 1);
    if (!b || !m) { free(b); free(m); return -1; }

    int n = 0;
    const char *c = hex_str;
    while (*c) {
        if (*c == ' ') { c++; continue; }
        if (c[0] == '?' && c[1] == '?') {
            b[n] = 0x00;
            m[n] = 0x00;
            n++; c += 2;
        } else {
            int hi = sb_hex_val(c[0]);
            int lo = sb_hex_val(c[1]);
            if (hi < 0 || lo < 0) { free(b); free(m); return -1; }
            b[n] = (uint8_t)((hi << 4) | lo);
            m[n] = 0xFF;
            n++; c += 2;
        }
    }
    if (n == 0) { free(b); free(m); return -1; }

    out->bytes  = b;
    out->mask   = m;
    out->length = n;
    return 0;
}

void sb_release_pattern(sb_byte_pattern_t *pat) {
    if (!pat) return;
    free(pat->bytes); pat->bytes = NULL;
    free(pat->mask);  pat->mask  = NULL;
    pat->length = 0;
}

static int concrete_byte(const sb_byte_pattern_t *pat, uint8_t *val) {
    for (int k = 0; k < pat->length; k++) {
        if (pat->mask[k] == 0xFF) {
            *val = pat->bytes[k];
            return k;
        }
    }
    return -1;
}

static int matches_at(const uint8_t *mem, const sb_byte_pattern_t *pat) {
    const uint8_t *pb = pat->bytes, *pm = pat->mask;
    int rem = pat->length;
    int k = 0;

    while (rem >= 4) {
        uint32_t d, e, f;
        memcpy(&d, mem + k, 4);
        memcpy(&f, pm + k,  4);
        memcpy(&e, pb + k,  4);
        if ((d & f) != e) return 0;
        k += 4; rem -= 4;
    }
    while (rem-- > 0) {
        if ((mem[k] & pm[k]) != pb[k]) return 0;
        k++;
    }
    return 1;
}

uintptr_t sb_scan_sole_match(uintptr_t base, size_t size,
                             const sb_byte_pattern_t *pat) {
    if (!pat || pat->length <= 0 || (size_t)pat->length > size)
        return 0;

    uint8_t anchor;
    int anchor_off = concrete_byte(pat, &anchor);
    if (anchor_off < 0) return 0;

    const uint8_t *region = (const uint8_t *)base;
    size_t limit = size - (size_t)pat->length;
    uintptr_t found = 0;
    int hits = 0;

    for (size_t pos = 0; pos <= limit; pos += 4) {
        if (region[pos + anchor_off] != anchor) continue;
        if (!matches_at(region + pos, pat)) continue;
        if (++hits > 1) return 0;
        found = base + pos;
    }
    return found;
}
