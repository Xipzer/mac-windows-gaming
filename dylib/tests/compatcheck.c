#include "../feats/compat.c"

#include <stdio.h>

int   sb_log_level = -1;
FILE *sb_log_file  = NULL;

int sb_log_first_hit(const void *anchor, unsigned long tag) {
    (void)anchor; (void)tag;
    return 1;
}

const char *sb_home_dir(void) {
    return "/nonexistent";
}

static int failures;

static void check(int ok, const char *what) {
    if (!ok) {
        printf("FAIL %s\n", what);
        failures++;
    }
}

#define NOP 0xD503201Fu
static uint32_t ldr32_x0(uint32_t off, uint32_t rt) { return 0xB9400000u | ((off / 4u) << 10) | rt; }
static uint32_t ldr64(uint32_t base, uint32_t off, uint32_t rt) {
    return 0xF9400000u | ((off / 8u) << 10) | (base << 5) | rt;
}
static uint32_t ldrb(uint32_t base, uint32_t off, uint32_t rt) {
    return 0x39400000u | (off << 10) | (base << 5) | rt;
}
static uint32_t mov_x0(uint32_t rd) { return 0xAA0003E0u | rd; }
static uint32_t cbz(int32_t words, uint32_t rt) {
    return 0x34000000u | (((uint32_t)words & 0x7FFFFu) << 5) | rt;
}

#define CODE_WORDS 64
#define GATE_IDX   32
static uint32_t code[CODE_WORDS];

static uintptr_t build_gate(uint32_t appid_off, uint32_t install_off) {
    for (int i = 0; i < CODE_WORDS; i++) code[i] = NOP;
    code[GATE_IDX]     = ldr32_x0(appid_off, 3);
    code[GATE_IDX + 1] = cbz(4, 3);
    code[GATE_IDX + 5] = ldr64(0, install_off, 4);
    return (uintptr_t)&code[GATE_IDX];
}

static uint32_t oslist_code[CODE_WORDS];

static uintptr_t build_oslist(uint32_t from_off, uint32_t to_off) {
    for (int i = 0; i < CODE_WORDS; i++) oslist_code[i] = NOP;
    oslist_code[GATE_IDX]     = ldr64(21, from_off, 1);
    oslist_code[GATE_IDX + 1] = ldr64(21, to_off, 2);
    return (uintptr_t)&oslist_code[GATE_IDX];
}

static void probe_cases(void) {
    g_tool_shift = 0;
    check(sb_compat_probe_tool_layout(build_gate(0x60, 0x58), 0) == 1,
          "the reference layout probes clean");
    check(g_tool_shift == 0, "the reference layout reports no shift");
    check(sb_compat_tool_stride() == COMPAT_TOOL_STRIDE, "an unshifted entry keeps its stride");

    g_tool_shift = 0;
    check(sb_compat_probe_tool_layout(build_gate(0x68, 0x60), 0) == 1,
          "a client that grew the entry by 8 probes clean");
    check(sb_compat_tool_off(COMPAT_TOOL_APPID_OFF) == 0x68, "appid follows the shift");
    check(sb_compat_tool_off(COMPAT_TOOL_INSTALL_OFF) == 0x60, "install follows the shift");
    check(sb_compat_tool_off(COMPAT_TOOL_GATE_FLAGS_OFF) == COMPAT_TOOL_GATE_FLAGS_OFF,
          "a field ahead of the insertion point does not follow the shift");
    check(sb_compat_tool_stride() == COMPAT_TOOL_STRIDE + 8, "the entry widens by what it moved");

    g_tool_shift = 8;
    check(sb_compat_probe_tool_layout(build_gate(0x68, 0x58), 0) == 0,
          "appid and install disagreeing about the shift is refused");
    check(g_tool_shift == 8, "a refused probe leaves the shift alone");

    g_tool_shift = 0;
    check(sb_compat_probe_tool_layout(0, 0) == 0, "no gate is refused");

    for (int i = 0; i < CODE_WORDS; i++) code[i] = NOP;
    check(sb_compat_probe_tool_layout((uintptr_t)&code[GATE_IDX], 0) == 0,
          "a gate that is not the appid load is refused");

    uintptr_t gate = build_gate(0x60, 0x58);
    code[GATE_IDX + 1] = NOP;
    check(sb_compat_probe_tool_layout(gate, 0) == 0, "an appid load with no branch after it is refused");

    gate = build_gate(0x60, 0x58);
    code[GATE_IDX + 5] = NOP;
    check(sb_compat_probe_tool_layout(gate, 0) == 0, "a branch landing on no install load is refused");
}

static void oslist_cases(void) {
    g_tool_shift = 0;
    check(sb_compat_probe_tool_layout(build_gate(0x68, 0x60), build_oslist(0x78, 0x80)) == 1,
          "the far end agreeing on the shift probes clean");
    check(g_tool_shift == 8, "agreement at both ends keeps the shift");

    g_tool_shift = 0;
    check(sb_compat_probe_tool_layout(build_gate(0x68, 0x60), build_oslist(0x70, 0x78)) == 0,
          "the near fields moving and the oslist not is refused");
    check(g_tool_shift == 0, "a far-end disagreement writes no shift");

    g_tool_shift = 0;
    check(sb_compat_probe_tool_layout(build_gate(0x68, 0x60), build_oslist(0x80, 0x78)) == 1,
          "the oslist pair is read by offset rather than by load order");
}

static void enabled_cases(void) {
    g_enabled_off = COMPAT_MANAGER_ENABLED_OFF;

    for (int i = 0; i < CODE_WORDS; i++) code[i] = NOP;
    code[0] = mov_x0(21);
    code[1] = ldrb(21, 0x7C0, 8);
    check(sb_compat_probe_enabled_off((uintptr_t)code) == 1, "the enabled flag probes clean");
    check(sb_compat_enabled_off() == 0x7C0, "the probed flag offset is what gets reported");

    g_enabled_off = COMPAT_MANAGER_ENABLED_OFF;
    for (int i = 0; i < CODE_WORDS; i++) code[i] = NOP;
    code[0] = mov_x0(21);
    code[1] = ldrb(21, 0x20, 8);
    check(sb_compat_probe_enabled_off((uintptr_t)code) == 0,
          "a byte read too early in the object is not taken for the flag");
    check(sb_compat_enabled_off() == COMPAT_MANAGER_ENABLED_OFF,
          "a refused flag probe leaves the baseline in place");

    for (int i = 0; i < CODE_WORDS; i++) code[i] = NOP;
    code[0] = ldrb(21, 0x7C0, 8);
    check(sb_compat_probe_enabled_off((uintptr_t)code) == 0,
          "a body that never parks this in a register is refused");

    check(sb_compat_probe_enabled_off(0) == 0, "no function is refused");
}

static uint8_t manager[0x400];
static uint8_t entries[8 * (COMPAT_TOOL_STRIDE + 64)];

static void *build_manager(uint32_t count, int named_slot) {
    memset(manager, 0, sizeof manager);
    memset(entries, 0, sizeof entries);
    *(uint8_t **)(manager + COMPAT_MANAGER_TOOL_ARRAY_OFF) = entries;
    *(uint32_t *)(manager + COMPAT_MANAGER_TOOL_COUNT_OFF) = count;
    if (named_slot >= 0) {
        uint8_t *entry = entries + (size_t)named_slot * sb_compat_tool_stride();
        *(const char **)(entry + COMPAT_TOOL_NAME_OFF) = TOOL_DIR_NAME;
    }
    return manager;
}

static void manager_cases(void) {
    g_tool_shift = 0;

    void *mgr = build_manager(3, 1);
    void *want = entries + sb_compat_tool_stride();
    check(sb_compat_registered_tool(mgr) == want, "the entry registered under the tool name is found");

    check(sb_compat_registered_tool(build_manager(3, -1)) == NULL,
          "a manager holding no entry of ours reports none");
    check(sb_compat_registered_tool(NULL) == NULL, "no manager reports no entry");

    check(sb_compat_registered_tool(build_manager(COMPAT_MANAGER_TOOLS_MAX + 1, 1)) == NULL,
          "a count past the cap is refused rather than walked");
    check(sb_compat_registered_tool(build_manager(COMPAT_MANAGER_TOOLS_MAX, -1)) == NULL,
          "a count at the cap is still walked");

    mgr = build_manager(3, 1);
    *(uint8_t **)((uint8_t *)mgr + COMPAT_MANAGER_TOOL_ARRAY_OFF) = NULL;
    check(sb_compat_registered_tool(mgr) == NULL, "a manager with no array is refused");

    g_tool_shift = 8;
    mgr = build_manager(3, 2);
    check(sb_compat_registered_tool(mgr) == entries + 2 * sb_compat_tool_stride(),
          "the walk steps by the live stride rather than the baseline");
    g_tool_shift = 0;
}

static uint32_t stub_platforms_value;
static uint32_t stub_platforms(void *mgr, uint32_t appid) {
    (void)mgr; (void)appid;
    return stub_platforms_value;
}

static const char *stub_mapping_entry[3];
static void *stub_find_mapping(void *mgr, uint32_t appid) {
    (void)mgr; (void)appid;
    return stub_mapping_entry;
}

static uint32_t last_priority;
static uint32_t last_appid;
static void stub_set_mapping(void *mgr, uint32_t appid, const char *tool_name,
                             const char *config, uint32_t priority) {
    (void)mgr; (void)tool_name; (void)config;
    last_appid = appid;
    last_priority = priority;
}

static void installed_fn_cases(void) {
    g_get_valid_platforms = NULL;
    g_find_mapping = NULL;
    check(sb_compat_valid_platforms(manager, 7) == 0, "no platforms function reports no platform");
    check(sb_compat_would_force(manager, 7) == false, "no platforms function forces nothing");
    check(sb_compat_app_mapping(manager, 7) == NULL, "no mapping function reports no mapping");

    sb_compat_set_valid_platforms_fn((uintptr_t)stub_platforms);
    stub_platforms_value = COMPAT_PLATFORM_WINDOWS;
    check(sb_compat_would_force(manager, 7), "a windows-only app takes the default");

    stub_platforms_value = COMPAT_PLATFORM_WINDOWS | COMPAT_PLATFORM_MACOS;
    check(!sb_compat_would_force(manager, 7), "an app with a macOS build is left alone");

    stub_platforms_value = COMPAT_PLATFORM_MACOS;
    check(!sb_compat_would_force(manager, 7), "a macOS-only app is left alone");

    stub_platforms_value = COMPAT_PLATFORM_WINDOWS;
    check(!sb_compat_would_force(manager, 0), "appid zero is not an app to force");
    check(sb_compat_valid_platforms(NULL, 7) == 0, "no manager reports no platform");

    sb_compat_set_app_mapping_fn((uintptr_t)stub_find_mapping);
    stub_mapping_entry[0] = "steambridge";
    check(sb_compat_app_mapping(manager, 7) != NULL, "a mapped app reports its entry");
    check(strcmp(sb_compat_app_mapping(manager, 7), "steambridge") == 0,
          "the name in the entry is what comes back");
    check(sb_compat_app_mapping(manager, 0) == NULL,
          "appid zero is refused rather than reaching the global entry");

    stub_mapping_entry[0] = "";
    check(sb_compat_app_mapping(manager, 7) == NULL, "an empty name reports no mapping");
    stub_mapping_entry[0] = NULL;
    check(sb_compat_app_mapping(manager, 7) == NULL, "an entry naming nothing reports no mapping");

    sb_compat_set_mapping_fn((uintptr_t)stub_set_mapping);
    last_priority = 0;
    sb_compat_map_tool(manager, 7, "steambridge");
    check(last_appid == 7 && last_priority == COMPAT_MAPPING_PRIORITY_APP,
          "an app mapping outranks the global one");

    last_priority = 0;
    sb_compat_map_tool(manager, 0, "steambridge");
    check(last_appid == 0 && last_priority == COMPAT_MAPPING_PRIORITY_GLOBAL,
          "the global mapping stays under the threshold that skips the platform check");

    last_priority = 0;
    sb_compat_map_tool(manager, 7, NULL);
    check(last_priority == 0, "mapping an app to no tool at all reaches the client as nothing");
}

int main(void) {
    probe_cases();
    oslist_cases();
    enabled_cases();
    manager_cases();
    installed_fn_cases();

    if (failures) {
        printf("==> compat: %d check(s) failed\n", failures);
        return 1;
    }
    printf("==> compat: layout probes hold, the tool array walk is bounded, "
           "installed functions answer\n");
    return 0;
}
