#include "hooks.h"
#include "../core/macho.h"
#include "../feats/webui.h"
#include "../feats/compat.h"
#include "../util/log.h"
#include <stdlib.h>
#include <string.h>

extern int DobbyHook(void *address, void *replace_call, void **origin_call);
typedef void (*sb_prehook_fn)(void *address, void *ctx);
extern int DobbyInstrument(void *address, sb_prehook_fn pre_handler);

int sb_hooks_env_lists_label(const char *var, const char *label) {
    const char *list = getenv(var);
    if (!list || !list[0] || !label)
        return 0;

    size_t label_len = strlen(label);
    while (*list) {
        const char *comma = strchr(list, ',');
        size_t field_len = comma ? (size_t)(comma - list) : strlen(list);
        if (field_len == label_len && memcmp(list, label, label_len) == 0)
            return 1;
        if (!comma)
            break;
        list = comma + 1;
    }
    return 0;
}

typedef struct {
    const char        *group;
    int              (*count)(void);
    sb_patch_entry_t *(*entries)(void);
} sb_hook_group_t;

static const sb_hook_group_t sb_groups[] = {
    { "compat", sb_hooks_compat_count, sb_hooks_compat_defs },
    { "webui",  sb_hooks_webui_count,  sb_hooks_webui_defs  },
};

static const sb_hook_group_t sb_steamui_groups[] = {
    { "shortcut", sb_hooks_shortcut_count, sb_hooks_shortcut_defs },
    { "icon",     sb_hooks_icon_count,     sb_hooks_icon_defs     },
};

static int sb_apply_entry(sb_resolve_result_t *resolved, const char *group,
                          sb_patch_entry_t *e) {
    if (sb_hooks_env_lists_label("STEAMBRIDGE_DISABLE", e->label)) {
        SB_WARN("[%s] %s: DISABLED via STEAMBRIDGE_DISABLE", group, e->label);
        return 0;
    }

    uintptr_t addr = e->address ? e->address
                   : e->signature ? sb_lookup_address(resolved, e->signature) : 0;
    if (!addr) {
        if (e->tolerate_missing)
            SB_DBG("[%s] %s: unresolved (optional)", group, e->label);
        else
            SB_WARN("[%s] %s: unresolved, cannot install", group, e->label);
        return 0;
    }

    int prehook = (e->mode == SB_PATCH_PREHOOK);
    int rc = prehook ? DobbyInstrument((void *)addr, (sb_prehook_fn)e->entry)
                     : DobbyHook((void *)addr, e->entry, e->trampoline);
    if (rc == 0) {
        SB_LOG("[%s] %s: %s @ %p", group, e->label,
               prehook ? "instrumented" : "hooked", (void *)addr);
        return 1;
    }

    SB_ERR("[%s] %s: %s failed (ret=%d) @ %p, target may stay patched with no original; "
           "the hook degrades instead of calling it",
           group, e->label, prehook ? "DobbyInstrument" : "DobbyHook", rc, (void *)addr);
    return 0;
}

static int install_groups(const sb_hook_group_t *groups, size_t n_groups,
                          sb_resolve_result_t *resolved, int *total_out) {
    int total  = 0;
    int landed = 0;

    for (size_t g = 0; g < n_groups; g++) {
        const sb_hook_group_t *group = &groups[g];
        sb_patch_entry_t *entries = group->entries();
        int n = group->count();
        for (int i = 0; i < n; i++) {
            total++;
            landed += sb_apply_entry(resolved, group->group, &entries[i]);
        }
    }

    if (total_out)
        *total_out = total;
    return landed;
}

int sb_hooks_install_steamui(const struct mach_header_64 *mh, intptr_t slide,
                             sb_resolve_result_t *resolved, int *total_out) {
    (void)mh;
    (void)slide;

    int total  = 0;
    int landed = install_groups(sb_steamui_groups,
                                sizeof(sb_steamui_groups) / sizeof(sb_steamui_groups[0]),
                                resolved, &total);

    if (total_out)
        *total_out = total;
    SB_LOG("hooks: steamui %d/%d installed", landed, total);
    return landed;
}

int sb_hooks_install_all(const struct mach_header_64 *mh, intptr_t slide,
                         sb_resolve_result_t *resolved, int *total_out) {
    sb_hooks_compat_set_helpers(
        sb_lookup_address(resolved, "CCompatManager::YldRegisterTool"),
        sb_lookup_address(resolved, "CCompatManager::GetValidPlatforms"),
        sb_lookup_address(resolved, "CCompatManager::FindToolForTargetApp"),
        sb_lookup_address(resolved, "CCompatManager::SetCompatToolMapping"),
        sb_lookup_address(resolved, "CCompatManager::FindMapping"),
        sb_lookup_address(resolved, "CCompatManager::GetWildcardMapping"));

    sb_compat_probe_tool_layout(
        sb_lookup_address(resolved, "CCompatManager::ResolveCompatToolForApp.local_redirect"),
        sb_lookup_address(resolved, "CCompatManager::GetOSListOverrideForApp.oslist_gate"));
    sb_compat_probe_enabled_off(
        sb_lookup_address(resolved, "CCompatManager::BIsCompatibilityToolEnabled"));

    uintptr_t register_fn = sb_lookup_address(resolved,
                                             "CWebUIJobDispatcher::RegisterHandler");
    uintptr_t dispatch_fn = sb_lookup_address(resolved, "CWebUITransport::DispatchJob");

    sb_webui_init(mh, slide, register_fn, dispatch_fn,
                  sb_lookup_address(resolved, "CWebUIMsgJob::SendResponse"));
    sb_webui_dump_routes();
    sb_hooks_webui_bind(mh, slide, register_fn, dispatch_fn);

    int total  = 0;
    int landed = install_groups(sb_groups, sizeof(sb_groups) / sizeof(sb_groups[0]),
                                resolved, &total);

    sb_hooks_compat_publish_originals();

    if (total_out)
        *total_out = total;
    SB_LOG("hooks: %d/%d installed", landed, total);
    return landed;
}
