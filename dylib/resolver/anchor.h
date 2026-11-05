#ifndef STEAMBRIDGE_RESOLVER_ANCHOR_H
#define STEAMBRIDGE_RESOLVER_ANCHOR_H

#include <stdint.h>
#include <stddef.h>
#include <mach-o/loader.h>

typedef enum {
    SB_MATCH_NONE = 0,
    SB_MATCH_STRING,
    SB_MATCH_VTABLE_SLOT,
    SB_MATCH_INSN_AFTER_STRING,
    SB_MATCH_INSN_PAIR_IN_FN,
    SB_MATCH_AOB,
    SB_MATCH_CALL_TARGET,
} sb_match_kind_t;

#define SB_CALL_PATH_MAX 4

typedef struct {
    uint32_t first, first_mask;
    uint32_t second, second_mask;
    uint32_t tie_mask;
    int      land_on_second;
} sb_insn_pair_t;

typedef struct {
    sb_match_kind_t kind;
    char             str[256];
    uintptr_t        va;
    uint32_t         insn;
    uint32_t         insn_mask;
    int              nth;

    int              nth_xref;

    sb_insn_pair_t   pair;

    int              indirect;

    int              caller_hops;
    int              caller_tail;

    int              call_path[SB_CALL_PATH_MAX];
    int              call_depth;
} sb_anchor_t;

#define SB_FN_SPAN_MAX 0x400

uintptr_t sb_locate_anchor(const struct mach_header_64 *mh, intptr_t slide,
                            uintptr_t text_base, size_t text_size,
                            const sb_anchor_t *anchor);

uintptr_t sb_rtti_vptr(const struct mach_header_64 *mh, intptr_t slide,
                       uintptr_t text_base, size_t text_size,
                       const char *type_name);

#endif
