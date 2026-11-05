#ifndef STEAMBRIDGE_CORE_MACHO_H
#define STEAMBRIDGE_CORE_MACHO_H

#include <stdint.h>
#include <stddef.h>
#include <mach-o/loader.h>

int sb_await_image(const char *name, int timeout_ms,
                         const struct mach_header_64 **out_mh, intptr_t *out_slide,
                         char *out_path, size_t path_size);

void sb_await_stop(void);

int sb_find_segment(const struct mach_header_64 *mh, intptr_t slide,
                   const char *segname, uintptr_t *out_base, size_t *out_size);

int sb_get_section_containing(const struct mach_header_64 *mh, intptr_t slide,
                              uintptr_t addr, uintptr_t *out_base,
                              size_t *out_size);

int sb_function_bounds(const struct mach_header_64 *mh, intptr_t slide,
                       uintptr_t addr, uintptr_t *out_start, uintptr_t *out_end);

#endif
