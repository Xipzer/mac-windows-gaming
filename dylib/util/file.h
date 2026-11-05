#ifndef STEAMBRIDGE_UTIL_FILE_H
#define STEAMBRIDGE_UTIL_FILE_H

#include <stdint.h>
#include <stddef.h>

uint8_t *sb_read_whole_file(const char *path, size_t *out_len);

const char *sb_home_dir(void);

void sb_support_path(char *buf, size_t bufsz, const char *home, const char *rel);

#endif
