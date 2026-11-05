#include "compat.h"
#include "../util/log.h"
#include "../util/file.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define TOOL_DIR_NAME "steambridge"
#define TOOL_DISPLAY_NAME "SteamBridge"

#define COMPAT_MANAGER_ENABLED_OFF  0x7B0
#define COMPAT_TOOL_STRIDE          0x130
#define COMPAT_TOOL_FLAGS_OFF       0x28
#define COMPAT_TOOL_FLAG_NO_APP     0x1
#define COMPAT_TOOL_FROM_OSLIST_OFF 0x70
#define COMPAT_TOOL_TO_OSLIST_OFF   0x78

#define COMPAT_MAPPING_PRIORITY_GLOBAL 75
#define COMPAT_MAPPING_PRIORITY_APP    250

static const char TOOL_MANIFEST[] =
    "\"manifest\"\n"
    "{\n"
    "  \"version\" \"2\"\n"
    "  \"commandline\" \"/run %verb%\"\n"
    "}\n";

static const char TOOL_DECLARATION[] =
    "\"compatibilitytools\"\n"
    "{\n"
    "  \"compat_tools\"\n"
    "  {\n"
    "    \"" TOOL_DIR_NAME "\"\n"
    "    {\n"
    "      \"install_path\" \".\"\n"
    "      \"display_name\" \"" TOOL_DISPLAY_NAME "\"\n"
    "      \"from_oslist\" \"windows\"\n"
    "      \"to_oslist\" \"macos\"\n"
    "    }\n"
    "  }\n"
    "}\n";

#include "compat_run.h"

static int write_file(const char *path, const char *content, int executable) {
    FILE *f = fopen(path, "w");
    if (!f) return -1;
    fputs(content, f);
    int err = fclose(f);
    if (executable)
        chmod(path, 0755);
    return err ? -1 : 0;
}

static int ensure_dir(const char *path) {
    struct stat st;
    if (stat(path, &st) == 0)
        return S_ISDIR(st.st_mode) ? 0 : -1;
    return mkdir(path, 0755);
}

static int32_t g_tool_shift;

static int ldr32_from_x0(uint32_t w, uint32_t *off, uint32_t *rt) {
    if ((w & 0xFFC003E0u) != 0xB9400000u) return 0;
    *rt  = w & 0x1Fu;
    *off = ((w >> 10) & 0xFFFu) * 4u;
    return 1;
}

static int ldr64_from(uint32_t w, uint32_t base, uint32_t *off) {
    if ((w & 0xFFC00000u) != 0xF9400000u) return 0;
    if (((w >> 5) & 0x1Fu) != base) return 0;
    *off = ((w >> 10) & 0xFFFu) * 8u;
    return 1;
}

static int ldr64_from_x0(uint32_t w, uint32_t *off) {
    return ldr64_from(w, 0, off);
}

static int ldrb_from(uint32_t w, uint32_t base, uint32_t *off) {
    if ((w & 0xFFC00000u) != 0x39400000u) return 0;
    if (((w >> 5) & 0x1Fu) != base) return 0;
    *off = (w >> 10) & 0xFFFu;
    return 1;
}

static int mov_from_x0(uint32_t w, uint32_t *rd) {
    if ((w & 0xFFFFFFE0u) != 0xAA0003E0u) return 0;
    *rd = w & 0x1Fu;
    return 1;
}

static int cbz32(uintptr_t pc, uint32_t w, uint32_t rt, uintptr_t *target) {
    if ((w & 0xFF000000u) != 0x34000000u) return 0;
    if ((w & 0x1Fu) != rt) return 0;
    int32_t imm = (int32_t)((w >> 5) & 0x7FFFFu);
    imm = (imm << 13) >> 13;
    *target = pc + (uintptr_t)(imm * 4);
    return 1;
}

static int probe_oslist_offsets(uintptr_t oslist_gate, uint32_t base,
                                uint32_t *from_off, uint32_t *to_off) {
    if (!oslist_gate) return 0;

    uint32_t seen[2];
    int n = 0;
    for (uintptr_t pc = oslist_gate - 0x40; pc <= oslist_gate + 0x20; pc += 4) {
        uint32_t off;
        if (!ldr64_from(*(const uint32_t *)pc, base, &off)) continue;
        if (n > 0 && seen[0] == off) continue;
        if (n > 1 && seen[1] == off) continue;
        if (n == 2) return 0;
        seen[n++] = off;
    }
    if (n != 2) return 0;

    *to_off   = seen[0] > seen[1] ? seen[0] : seen[1];
    *from_off = seen[0] > seen[1] ? seen[1] : seen[0];
    return 2;
}

int sb_compat_probe_tool_layout(uintptr_t appid_gate, uintptr_t oslist_gate) {
    if (!appid_gate) return 0;

    uint32_t appid_off, rt;
    if (!ldr32_from_x0(*(const uint32_t *)appid_gate, &appid_off, &rt)) {
        SB_WARN("sb_compat_probe_tool_layout: 0x%lx is not the appid load",
                (unsigned long)appid_gate);
        return 0;
    }

    uintptr_t local_path;
    if (!cbz32(appid_gate + 4, *(const uint32_t *)(appid_gate + 4), rt, &local_path)) {
        SB_WARN("sb_compat_probe_tool_layout: no appid branch after 0x%lx",
                (unsigned long)appid_gate);
        return 0;
    }

    uint32_t install_off = 0;
    for (uintptr_t pc = local_path; pc < local_path + 0x20; pc += 4) {
        if (ldr64_from_x0(*(const uint32_t *)pc, &install_off)) break;
    }
    if (!install_off) {
        SB_WARN("sb_compat_probe_tool_layout: no install load at 0x%lx",
                (unsigned long)local_path);
        return 0;
    }

    int32_t by_appid   = (int32_t)appid_off   - COMPAT_TOOL_APPID_OFF;
    int32_t by_install = (int32_t)install_off - COMPAT_TOOL_INSTALL_OFF;
    if (by_appid != by_install) {
        SB_ERR("sb_compat_probe_tool_layout: appid moved %+d but install moved %+d; "
               "the tool layout no longer shifts as one block",
               by_appid, by_install);
        return 0;
    }

    uint32_t from_off = 0, to_off = 0;
    if (probe_oslist_offsets(oslist_gate, 21, &from_off, &to_off) == 2) {
        int32_t by_from = (int32_t)from_off - COMPAT_TOOL_FROM_OSLIST_OFF;
        int32_t by_to   = (int32_t)to_off   - COMPAT_TOOL_TO_OSLIST_OFF;
        if (by_from != by_appid || by_to != by_appid) {
            SB_ERR("sb_compat_probe_tool_layout: near fields moved %+d but oslist "
                   "moved %+d/%+d; the tool layout no longer shifts as one block",
                   by_appid, by_from, by_to);
            return 0;
        }
        SB_DBG("sb_compat_probe_tool_layout: oslist offsets 0x%x/0x%x agree on %+d",
               from_off, to_off, by_appid);
    }

    g_tool_shift = by_appid;
    if (g_tool_shift)
        SB_LOG("sb_compat_probe_tool_layout: tool fields from install onward are "
               "%+d from the baseline (appid 0x%x, install 0x%x)",
               g_tool_shift, appid_off, install_off);
    return 1;
}

static uint32_t g_enabled_off = COMPAT_MANAGER_ENABLED_OFF;

int sb_compat_probe_enabled_off(uintptr_t bis_enabled) {
    if (!bis_enabled) return 0;

    uint32_t base = 0;
    int have_base = 0;
    for (uintptr_t pc = bis_enabled; pc < bis_enabled + 0x40; pc += 4) {
        if (mov_from_x0(*(const uint32_t *)pc, &base)) { have_base = 1; break; }
    }
    if (!have_base) {
        SB_WARN("sb_compat_probe_enabled_off: this is never parked in a register "
                "at 0x%lx", (unsigned long)bis_enabled);
        return 0;
    }

    uint32_t off = 0;
    int found = 0;
    for (uintptr_t pc = bis_enabled; pc < bis_enabled + 0x80; pc += 4) {
        if (ldrb_from(*(const uint32_t *)pc, base, &off)) { found = 1; break; }
    }
    if (!found) {
        SB_WARN("sb_compat_probe_enabled_off: no flag load through x%u at 0x%lx",
                base, (unsigned long)bis_enabled);
        return 0;
    }

    if (off < 0x100) {
        SB_ERR("sb_compat_probe_enabled_off: 0x%x is too low to be the enabled "
               "flag; refusing to write it", off);
        return 0;
    }

    if (off != g_enabled_off)
        SB_LOG("sb_compat_probe_enabled_off: enabled flag at 0x%x, %+d from the "
               "baseline", off, (int32_t)off - COMPAT_MANAGER_ENABLED_OFF);
    g_enabled_off = off;
    return 1;
}

uint32_t sb_compat_enabled_off(void) {
    return g_enabled_off;
}

uint32_t sb_compat_tool_off(uint32_t reference_off) {
    if (reference_off < COMPAT_TOOL_INSTALL_OFF) return reference_off;
    return (uint32_t)((int32_t)reference_off + g_tool_shift);
}

size_t sb_compat_tool_stride(void) {
    return (size_t)((int32_t)COMPAT_TOOL_STRIDE + g_tool_shift);
}

void sb_compat_export_tools_path(void) {
    const char *home = sb_home_dir();
    if (!home) return;
    if (getenv("STEAM_EXTRA_COMPAT_TOOLS_PATHS")) return;

    char tools_dir[512];
    snprintf(tools_dir, sizeof(tools_dir),
             "%s/Library/Application Support/Steam/compatibilitytools.d", home);

    setenv("STEAM_EXTRA_COMPAT_TOOLS_PATHS", tools_dir, 1);
    SB_LOG("sb_compat_export_tools_path: set STEAM_EXTRA_COMPAT_TOOLS_PATHS=%s",
           tools_dir);
}

int sb_compat_ensure_tool_manifest(void) {
    const char *home = sb_home_dir();
    if (!home) return -1;

    char tools_dir[512];
    snprintf(tools_dir, sizeof(tools_dir),
             "%s/Library/Application Support/Steam/compatibilitytools.d", home);

    if (ensure_dir(tools_dir) != 0) {
        SB_WARN("sb_compat_ensure_tool_manifest: cannot create %s", tools_dir);
        return -1;
    }

    char tool_dir[512];
    snprintf(tool_dir, sizeof(tool_dir), "%s/%s", tools_dir, TOOL_DIR_NAME);

    if (ensure_dir(tool_dir) != 0) {
        SB_WARN("sb_compat_ensure_tool_manifest: cannot create %s", tool_dir);
        return -1;
    }

    char path[512];
    int wrote = 0;

    snprintf(path, sizeof(path), "%s/compatibilitytool.vdf", tool_dir);
    if (write_file(path, TOOL_DECLARATION, 0) == 0) wrote++;
    else SB_WARN("sb_compat_ensure_tool_manifest: failed to write %s", path);

    snprintf(path, sizeof(path), "%s/toolmanifest.vdf", tool_dir);
    if (access(path, F_OK) != 0) {
        if (write_file(path, TOOL_MANIFEST, 0) == 0) wrote++;
        else SB_WARN("sb_compat_ensure_tool_manifest: failed to write %s", path);
    }

    snprintf(path, sizeof(path), "%s/run", tool_dir);
    if (write_file(path, RUN_SCRIPT, 1) == 0) wrote++;
    else SB_WARN("sb_compat_ensure_tool_manifest: failed to write %s", path);

    if (wrote > 0)
        SB_LOG("sb_compat_ensure_tool_manifest: wrote %d file(s) to %s", wrote, tool_dir);

    return 0;
}

const char *sb_compat_tool_dir(void) {
    static char dir[512];
    static int resolved = 0;

    if (resolved)
        return dir[0] ? dir : NULL;

    resolved = 1;

    const char *home = sb_home_dir();
    if (!home) {
        dir[0] = '\0';
        return NULL;
    }

    snprintf(dir, sizeof(dir),
             "%s/Library/Application Support/Steam/compatibilitytools.d/%s",
             home, TOOL_DIR_NAME);
    return dir;
}

const char *sb_compat_tool_commandline(void) {
    return "/run %verb%";
}

void sb_compat_force_enable(void *compat_mgr) {
    if (!compat_mgr) return;

    uint8_t *base = (uint8_t *)compat_mgr;
    uint32_t off = sb_compat_enabled_off();
    uint8_t prev = base[off];
    base[off] = 1;

    if (!prev)
        SB_LOG("sb_compat_force_enable: compat layer force-enabled (this+0x%X: 0 -> 1)",
               off);
}

typedef uint32_t (*fn_GetValidPlatforms)(void *compat_mgr, uint32_t appid);
static fn_GetValidPlatforms g_get_valid_platforms;

void sb_compat_set_valid_platforms_fn(uintptr_t get_valid_platforms) {
    g_get_valid_platforms = (fn_GetValidPlatforms)get_valid_platforms;
}

uint32_t sb_compat_valid_platforms(void *compat_mgr, uint32_t appid) {
    if (!g_get_valid_platforms || !compat_mgr)
        return 0;
    return g_get_valid_platforms(compat_mgr, appid);
}

typedef void *(*fn_FindToolForTargetApp)(void *compat_mgr, uint32_t appid);
static fn_FindToolForTargetApp g_find_tool_for_app;

void sb_compat_set_find_tool_fn(uintptr_t find_tool_for_target_app) {
    g_find_tool_for_app = (fn_FindToolForTargetApp)find_tool_for_target_app;
}

void *sb_compat_tool_for_app(void *compat_mgr, uint32_t appid) {
    if (!g_find_tool_for_app || !compat_mgr)
        return NULL;
    return g_find_tool_for_app(compat_mgr, appid);
}

static fn_FindToolForTargetApp g_chosen_tool;

void sb_compat_set_chosen_tool_fn(uintptr_t find_tool_for_target_app) {
    g_chosen_tool = (fn_FindToolForTargetApp)find_tool_for_target_app;
}

void *sb_compat_chosen_tool(void *compat_mgr, uint32_t appid) {
    if (!g_chosen_tool || !compat_mgr)
        return NULL;
    return g_chosen_tool(compat_mgr, appid);
}

bool sb_compat_would_force(void *compat_mgr, uint32_t appid) {
    if (!compat_mgr || !appid)
        return false;
    uint32_t platforms = sb_compat_valid_platforms(compat_mgr, appid);
    return (platforms & COMPAT_PLATFORM_WINDOWS) && !(platforms & COMPAT_PLATFORM_MACOS);
}

typedef void *(*fn_FindMapping)(void *compat_mgr, uint32_t appid);
static fn_FindMapping g_find_mapping;

void sb_compat_set_app_mapping_fn(uintptr_t find_mapping) {
    g_find_mapping = (fn_FindMapping)find_mapping;
}

static const char *mapping_name(const void *mapping) {
    const char *const *entry = (const char *const *)mapping;
    if (!entry || !entry[0] || !entry[0][0])
        return NULL;
    return entry[0];
}

const char *sb_compat_app_mapping(void *compat_mgr, uint32_t appid) {
    if (!g_find_mapping || !compat_mgr || !appid)
        return NULL;
    return mapping_name(g_find_mapping(compat_mgr, appid));
}

static fn_FindMapping g_get_wildcard;

void sb_compat_set_wildcard_fn(uintptr_t get_wildcard_mapping) {
    g_get_wildcard = (fn_FindMapping)get_wildcard_mapping;
}

const char *sb_compat_wildcard_mapping(void *compat_mgr, uint32_t appid) {
    if (!g_get_wildcard || !compat_mgr || !appid)
        return NULL;
    return mapping_name(g_get_wildcard(compat_mgr, appid));
}

typedef void (*fn_SetCompatToolMapping)(void *compat_mgr, uint32_t appid,
                                        const char *tool_name, const char *config,
                                        uint32_t priority);
static fn_SetCompatToolMapping g_set_mapping;

void sb_compat_set_mapping_fn(uintptr_t set_compat_tool_mapping) {
    g_set_mapping = (fn_SetCompatToolMapping)set_compat_tool_mapping;
}

void sb_compat_map_tool(void *compat_mgr, uint32_t appid, const char *tool_name) {
    if (!g_set_mapping || !compat_mgr || !tool_name) {
        SB_ERR("sb_compat_map_tool: app %u cannot be mapped to %s", appid,
               tool_name ? tool_name : "no tool");
        return;
    }
    g_set_mapping(compat_mgr, appid, tool_name, "",
                  appid ? COMPAT_MAPPING_PRIORITY_APP
                        : COMPAT_MAPPING_PRIORITY_GLOBAL);
}

typedef void (*fn_YldRegisterTool)(void *compat_mgr, void *tool);
static fn_YldRegisterTool g_yld_register_tool;

void sb_compat_set_register_fn(uintptr_t yld_register_tool) {
    g_yld_register_tool = (fn_YldRegisterTool)yld_register_tool;
}

static void *g_manager;

void *sb_compat_manager(void) {
    return g_manager;
}

void sb_compat_register_crossover(void *compat_mgr) {
    static int registered = 0;

    if (compat_mgr)
        g_manager = compat_mgr;

    if (registered || !compat_mgr || !g_yld_register_tool)
        return;

    if (sb_compat_registered_tool(compat_mgr)) {
        registered = 1;
        SB_LOG("sb_compat_register_crossover: %s already registered from disk, "
               "skipping the runtime entry", TOOL_DIR_NAME);
        return;
    }

    static uint8_t tool[COMPAT_TOOL_STRIDE + 64];
    memset(tool, 0, sizeof(tool));

    static const char name[]        = TOOL_DIR_NAME;
    static const char display[]     = TOOL_DISPLAY_NAME;
    static const char from_oslist[] = "windows";
    static const char to_oslist[]   = "macos";

    *(uint32_t *)(tool + COMPAT_TOOL_FLAGS_OFF)      = COMPAT_TOOL_FLAG_NO_APP;
    *(const char **)(tool + COMPAT_TOOL_NAME_OFF)    = name;
    *(const char **)(tool + COMPAT_TOOL_DISPLAY_OFF) = display;
    *(const char **)(tool + sb_compat_tool_off(COMPAT_TOOL_INSTALL_OFF)) =
        sb_compat_tool_dir();
    *(uint32_t *)(tool + sb_compat_tool_off(COMPAT_TOOL_APPID_OFF)) = 0;
    *(const char **)(tool + sb_compat_tool_off(COMPAT_TOOL_FROM_OSLIST_OFF)) = from_oslist;
    *(const char **)(tool + sb_compat_tool_off(COMPAT_TOOL_TO_OSLIST_OFF))   = to_oslist;

    registered = 1;
    g_yld_register_tool(compat_mgr, tool);
    SB_LOG("sb_compat_register_crossover: registered %s into manager 0x%llx",
           name, (unsigned long long)(uintptr_t)compat_mgr);
}

void *sb_compat_registered_tool(void *compat_mgr) {
    if (!compat_mgr)
        return NULL;

    uint8_t *base = (uint8_t *)compat_mgr;
    uint8_t *array = *(uint8_t **)(base + COMPAT_MANAGER_TOOL_ARRAY_OFF);
    uint32_t count = *(uint32_t *)(base + COMPAT_MANAGER_TOOL_COUNT_OFF);
    if (!array || count > COMPAT_MANAGER_TOOLS_MAX) {
        static const char once = 0;
        if (sb_log_first_hit(&once, 0))
            SB_ERR("sb_compat_registered_tool: the manager reports %u tool(s) at %p, "
                   "which is not a list this reads", count, (const void *)array);
        return NULL;
    }

    for (uint32_t i = 0; i < count; i++) {
        uint8_t *entry = array + (size_t)i * sb_compat_tool_stride();
        const char *name = *(const char **)(entry + COMPAT_TOOL_NAME_OFF);
        if (name && strcmp(name, TOOL_DIR_NAME) == 0)
            return entry;
    }
    return NULL;
}
