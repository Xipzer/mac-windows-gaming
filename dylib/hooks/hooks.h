#ifndef STEAMBRIDGE_HOOKS_HOOKS_H
#define STEAMBRIDGE_HOOKS_HOOKS_H

#include <stdint.h>
#include <stddef.h>
#include "../resolver/resolver.h"

typedef enum {
    SB_PATCH_REPLACE = 0,
    SB_PATCH_PREHOOK = 1,
} sb_patch_mode_t;

typedef struct { uint64_t _d0, sp, _d1; struct { uint64_t x[29]; } general; } sb_arm64_ctx_t;

typedef struct {
    const char      *label;
    const char      *signature;
    uintptr_t        address;
    void            *entry;
    void           **trampoline;
    sb_patch_mode_t  mode;
    int              tolerate_missing;
} sb_patch_entry_t;

int               sb_hooks_compat_count(void);
sb_patch_entry_t *sb_hooks_compat_defs(void);

void sb_hooks_compat_publish_originals(void);

void sb_hooks_compat_set_helpers(uintptr_t yld_register_tool,
                                 uintptr_t get_valid_platforms,
                                 uintptr_t find_tool_for_target_app,
                                 uintptr_t set_compat_tool_mapping,
                                 uintptr_t find_mapping,
                                 uintptr_t get_wildcard_mapping);

int               sb_hooks_webui_count(void);
sb_patch_entry_t *sb_hooks_webui_defs(void);

void sb_hooks_webui_bind(const struct mach_header_64 *mh, intptr_t slide,
                         uintptr_t register_fn, uintptr_t dispatch_fn);

int               sb_hooks_shortcut_count(void);
sb_patch_entry_t *sb_hooks_shortcut_defs(void);

int               sb_hooks_icon_count(void);
sb_patch_entry_t *sb_hooks_icon_defs(void);

int sb_hooks_install_all(const struct mach_header_64 *mh, intptr_t slide,
                         sb_resolve_result_t *resolved, int *total_out);

int sb_hooks_install_steamui(const struct mach_header_64 *mh, intptr_t slide,
                             sb_resolve_result_t *resolved, int *total_out);

int sb_hooks_env_lists_label(const char *var, const char *label);

void sb_hooks_spawn_install(void);

#endif
