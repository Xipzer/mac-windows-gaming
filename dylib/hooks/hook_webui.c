#include "hooks.h"
#include "../core/macho.h"
#include "../feats/compatsvc.h"
#include "../feats/webui.h"
#include "../util/log.h"
#include <stdint.h>
#include <string.h>

#define LOOKUP_LABEL "CWebUITransport::RouteLookup"

static const struct mach_header_64 *g_mh;
static intptr_t g_slide;
static uintptr_t g_text_base;
static size_t    g_text_size;

static void register_routes(void *address, void *ctx) {
    (void)address;
    (void)ctx;
    sb_compatsvc_register(g_mh, g_slide, g_text_base, g_text_size);
}

static sb_patch_entry_t g_hooks[] = {
    {
        .label            = LOOKUP_LABEL,
        .entry            = (void *)register_routes,
        .trampoline       = NULL,
        .tolerate_missing = 0,
        .mode             = SB_PATCH_PREHOOK,
    },
};

void sb_hooks_webui_bind(const struct mach_header_64 *mh, intptr_t slide,
                         uintptr_t register_fn, uintptr_t dispatch_fn) {
    if (!mh || !dispatch_fn) return;
    if (sb_get_section_containing(mh, slide, dispatch_fn, &g_text_base, &g_text_size) != 0)
        return;

    g_mh    = mh;
    g_slide = slide;

    uintptr_t site = sb_webui_lookup_site(register_fn, dispatch_fn);
    for (size_t i = 0; i < sizeof(g_hooks) / sizeof(g_hooks[0]); i++)
        if (strcmp(g_hooks[i].label, LOOKUP_LABEL) == 0)
            g_hooks[i].address = site;
}

int sb_hooks_webui_count(void) {
    return (int)(sizeof(g_hooks) / sizeof(g_hooks[0]));
}

sb_patch_entry_t *sb_hooks_webui_defs(void) {
    return g_hooks;
}
