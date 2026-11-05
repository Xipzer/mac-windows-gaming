#ifndef STEAMBRIDGE_FEATS_COMPATSVC_H
#define STEAMBRIDGE_FEATS_COMPATSVC_H

#include <stdint.h>
#include <stddef.h>
#include <mach-o/loader.h>

void sb_compatsvc_register(const struct mach_header_64 *mh, intptr_t slide,
                           uintptr_t text_base, size_t text_size);

enum {
    SB_COMPATSVC_UNTRIED = 0,
    SB_COMPATSVC_READY,
    SB_COMPATSVC_ABSENT,
};
int sb_compatsvc_routes(void);

#define SB_COMPAT_TOOL_NONE "steambridge.none"

void sb_compatsvc_state_changed(void);

#endif
