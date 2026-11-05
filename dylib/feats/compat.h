#ifndef STEAMBRIDGE_FEATS_COMPAT_H
#define STEAMBRIDGE_FEATS_COMPAT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define COMPAT_MANAGER_TOOL_ARRAY_OFF  0x320
#define COMPAT_MANAGER_TOOL_COUNT_OFF  0x330
#define COMPAT_TOOL_NAME_OFF           0x40

#define COMPAT_MANAGER_TOOLS_MAX       32

#define COMPAT_PLATFORM_WINDOWS  0x1
#define COMPAT_PLATFORM_MACOS    0x2

#define COMPAT_TOOL_GATE_FLAGS_OFF  0x24
#define COMPAT_TOOL_GATE_HIDDEN     0x1
#define COMPAT_TOOL_PRIORITY_OFF    0x38
#define COMPAT_TOOL_DISPLAY_OFF     0x50

#define COMPAT_TOOL_INSTALL_OFF     0x58
#define COMPAT_TOOL_APPID_OFF       0x60
#define COMPAT_TOOL_PLATFORM_OFF    0x80

int sb_compat_probe_tool_layout(uintptr_t appid_gate, uintptr_t oslist_gate);

int sb_compat_probe_enabled_off(uintptr_t bis_enabled);
uint32_t sb_compat_enabled_off(void);

uint32_t sb_compat_tool_off(uint32_t reference_off);

size_t sb_compat_tool_stride(void);

void sb_compat_export_tools_path(void);

int  sb_compat_ensure_tool_manifest(void);
void sb_compat_force_enable(void *compat_mgr);

void     sb_compat_set_valid_platforms_fn(uintptr_t get_valid_platforms);
uint32_t sb_compat_valid_platforms(void *compat_mgr, uint32_t appid);

void  sb_compat_set_find_tool_fn(uintptr_t find_tool_for_target_app);
void *sb_compat_tool_for_app(void *compat_mgr, uint32_t appid);

void  sb_compat_set_chosen_tool_fn(uintptr_t find_tool_for_target_app);
void *sb_compat_chosen_tool(void *compat_mgr, uint32_t appid);

bool sb_compat_would_force(void *compat_mgr, uint32_t appid);

void        sb_compat_set_wildcard_fn(uintptr_t get_wildcard_mapping);
const char *sb_compat_wildcard_mapping(void *compat_mgr, uint32_t appid);

void        sb_compat_set_app_mapping_fn(uintptr_t find_mapping);
const char *sb_compat_app_mapping(void *compat_mgr, uint32_t appid);

void sb_compat_set_mapping_fn(uintptr_t set_compat_tool_mapping);
void sb_compat_map_tool(void *compat_mgr, uint32_t appid, const char *tool_name);

void sb_compat_set_register_fn(uintptr_t yld_register_tool);

void sb_compat_register_crossover(void *compat_mgr);

void *sb_compat_manager(void);

void *sb_compat_registered_tool(void *compat_mgr);

const char *sb_compat_tool_dir(void);

const char *sb_compat_tool_commandline(void);

#endif
