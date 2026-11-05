#ifndef STEAMBRIDGE_RESOLVER_SIGDB_H
#define STEAMBRIDGE_RESOLVER_SIGDB_H

#include <stdint.h>
#include <stddef.h>
#include "anchor.h"

#define SB_MODULE_DEFAULT "steamclient.dylib"

typedef struct {
    char        name[128];
    char        module[64];
    char        aob_hex[4096];
    uintptr_t   func_addr_this_build;
    int         deprecated;
    int32_t     match_offset;
    sb_anchor_t anchor;
} sb_sig_entry_t;

typedef struct {
    sb_sig_entry_t *signatures;
    int             sig_count;
    int             schema_version;
    int             sigdb_version;
    uint64_t        steam_build;
    char            steam_build_date[32];
} sb_sigdb_t;

int  sb_load_profile(const char *path, sb_sigdb_t *out);
void sb_free_profile(sb_sigdb_t *p);

#endif
