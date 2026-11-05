#ifndef STEAMBRIDGE_RESOLVER_RESOLVER_H
#define STEAMBRIDGE_RESOLVER_RESOLVER_H

#include <stdint.h>
#include <stddef.h>
#include <mach-o/loader.h>
#include "sigdb.h"

typedef struct {
    const char *name;
    uintptr_t   site;
} sb_resolved_t;

typedef struct {
    sb_resolved_t *items;
    int            used;
    int            cap;
} sb_resolve_result_t;

int sb_looks_like_prologue(uintptr_t addr);

uintptr_t sb_aob_site(const sb_sig_entry_t *sig, uintptr_t text, size_t text_sz);

int sb_resolve_signatures(const struct mach_header_64 *mh, intptr_t slide,
                      sb_sigdb_t *sigdb, const char *module,
                      sb_resolve_result_t *out);

int sb_required_for_module(const sb_sigdb_t *sigdb, const char *module);

uintptr_t sb_lookup_address(const sb_resolve_result_t *result, const char *name);
void      sb_free_resolution(sb_resolve_result_t *result);

#endif
