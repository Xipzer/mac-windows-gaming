#ifndef STEAMBRIDGE_UTIL_HEX_H
#define STEAMBRIDGE_UTIL_HEX_H

static inline int sb_hex_val(int ch) {
    if (ch >= '0' && ch <= '9')
        return ch - '0';
    ch |= 0x20;
    if (ch >= 'a' && ch <= 'f')
        return ch - 'a' + 10;
    return -1;
}

#endif
