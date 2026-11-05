#include <string.h>

#include "compatsvc.h"
#include "compat.h"
#include "webui.h"
#include "../resolver/anchor.h"
#include "../util/log.h"

#define ROUTE_GET_COMPAT_TOOLS     "CompatManager.GetCompatTools#1"
#define ROUTE_SPECIFY_COMPAT_TOOL  "CompatManager.SpecifyCompatTool#1"
#define ROUTE_NOTIFY_STATE_CHANGED "CompatManager.NotifyStateChanged#1"

#define TYPE_GET_REQUEST      "37CCompatManager_GetCompatTools_Request"
#define TYPE_GET_RESPONSE     "38CCompatManager_GetCompatTools_Response"
#define TYPE_SPECIFY_REQUEST  "40CCompatManager_SpecifyCompatTool_Request"
#define TYPE_SPECIFY_RESPONSE "41CCompatManager_SpecifyCompatTool_Response"
#define TYPE_STATE_CHANGED    "40CCompatManager_StateChanged_Notification"

#define REQ_HAS_BITS_OFF 16
#define REQ_APPID_OFF    24
#define REQ_HAS_APPID    1

#define SPECIFY_TOOL_NAME_OFF 24
#define SPECIFY_APPID_OFF     32
#define SPECIFY_HAS_APPID     2

#define RESULT_OK   1
#define RESULT_FAIL 2

#define TOOL_NAME            1
#define TOOL_DISPLAY_NAME    2
#define TOOL_IS_DEFAULT      3
#define TOOL_IS_ACTIVE       4
#define TOOL_IS_LEGACY       5
#define TOOL_IS_INCOMPATIBLE 6

#define RESP_TOOLS    1
#define RESP_SELECTED 3
#define RESP_DEFAULT  4

#define WIRE_VARINT 0
#define WIRE_BYTES  2

#define TOOL_MAX  512
#define BODY_MAX  (TOOL_MAX * 8)

#define PLATFORMS_UNSCOPED COMPAT_PLATFORM_WINDOWS

#define RESULT_IS_A_TOOL 128

#define TOOL_NONE_LABEL "No Compatibility Tool"

typedef struct {
    uint8_t *buf;
    size_t   cap;
    size_t   len;
    int      ok;
} sb_pb_t;

static void pb_byte(sb_pb_t *w, uint8_t b) {
    if (w->len >= w->cap) { w->ok = 0; return; }
    w->buf[w->len++] = b;
}

static void pb_varint(sb_pb_t *w, uint64_t v) {
    do {
        uint8_t b = (uint8_t)(v & 0x7f);
        v >>= 7;
        pb_byte(w, v ? (uint8_t)(b | 0x80) : b);
    } while (v && w->ok);
}

static void pb_tag(sb_pb_t *w, uint32_t field, uint32_t wire) {
    pb_varint(w, ((uint64_t)field << 3) | wire);
}

static void pb_blob(sb_pb_t *w, uint32_t field, const uint8_t *bytes, size_t len) {
    pb_tag(w, field, WIRE_BYTES);
    pb_varint(w, len);
    for (size_t i = 0; i < len && w->ok; i++)
        pb_byte(w, bytes[i]);
}

static void pb_string(sb_pb_t *w, uint32_t field, const char *str) {
    if (!str) return;
    pb_blob(w, field, (const uint8_t *)str, strlen(str));
}

static void pb_bool(sb_pb_t *w, uint32_t field, int set) {
    pb_tag(w, field, WIRE_VARINT);
    pb_varint(w, set ? 1 : 0);
}

static void pb_tool(sb_pb_t *w, uint32_t resp_field,
                    const char *name, const char *display,
                    int is_active, int is_incompatible) {
    uint8_t item[TOOL_MAX];
    sb_pb_t t = { item, sizeof item, 0, 1 };
    pb_string(&t, TOOL_NAME, name);
    pb_string(&t, TOOL_DISPLAY_NAME, display);
    pb_bool(&t, TOOL_IS_DEFAULT, 0);
    pb_bool(&t, TOOL_IS_ACTIVE, is_active);
    pb_bool(&t, TOOL_IS_LEGACY, 0);
    pb_bool(&t, TOOL_IS_INCOMPATIBLE, is_incompatible);
    if (t.ok)
        pb_blob(w, resp_field, item, t.len);
    else
        w->ok = 0;
}

static int offered(const uint8_t *tool, uint32_t platforms, int bypass) {
    uint32_t converts_from =
        *(const uint32_t *)(tool + sb_compat_tool_off(COMPAT_TOOL_PLATFORM_OFF));
    uint32_t gate = *(const uint32_t *)(tool + COMPAT_TOOL_GATE_FLAGS_OFF);

    if (!(platforms & converts_from)) return 0;
    if ((gate & COMPAT_TOOL_GATE_HIDDEN) && !bypass) return 0;
    return 1;
}

static const char *tool_name(const void *tool) {
    if (!tool) return NULL;
    return *(const char *const *)((const uint8_t *)tool + COMPAT_TOOL_NAME_OFF);
}

static int get_compat_tools(uintptr_t request, uintptr_t response) {
    uint32_t has_bits = *(const uint32_t *)(request + REQ_HAS_BITS_OFF);
    uint32_t appid    = (has_bits & REQ_HAS_APPID)
                      ? *(const uint32_t *)(request + REQ_APPID_OFF) : 0;

    uint8_t *mgr = (uint8_t *)sb_compat_manager();
    if (!mgr) {
        SB_WARN("compatsvc: app %u asked for tools before any manager was seen, so "
                "the page gets an empty list", appid);
        return RESULT_OK;
    }

    const uint8_t *array = *(const uint8_t **)(mgr + COMPAT_MANAGER_TOOL_ARRAY_OFF);
    uint32_t count       = *(const uint32_t *)(mgr + COMPAT_MANAGER_TOOL_COUNT_OFF);
    if (!array || count > COMPAT_MANAGER_TOOLS_MAX) {
        SB_ERR("compatsvc: the manager reports %u tool(s) at %p, which is not a list "
               "this reads", count, (const void *)array);
        return RESULT_FAIL;
    }

    int bypass = mgr[sb_compat_enabled_off() + 2] != 0;
    if (appid && !bypass) {
        for (uint32_t i = 0; i < count; i++) {
            const uint8_t *tool = array + (size_t)i * sb_compat_tool_stride();
            if (*(const uint32_t *)(tool + sb_compat_tool_off(COMPAT_TOOL_APPID_OFF)) != appid)
                continue;
            SB_LOG("compatsvc: app %u is itself a compatibility tool, so it is "
                   "offered none", appid);
            return RESULT_IS_A_TOOL;
        }
    }

    uint32_t platforms = appid ? sb_compat_valid_platforms(mgr, appid)
                               : PLATFORMS_UNSCOPED;
    const char *active = tool_name(sb_compat_tool_for_app(mgr, appid));
    const char *chosen = appid ? sb_compat_app_mapping(mgr, appid)
                               : tool_name(sb_compat_chosen_tool(mgr, 0));
    const bool  holds_none = chosen && strcmp(chosen, SB_COMPAT_TOOL_NONE) == 0;
    const char *fallback = sb_compat_wildcard_mapping(mgr, appid);
    if (!fallback && (appid == 0 || sb_compat_would_force(mgr, appid)))
        fallback = tool_name(sb_compat_registered_tool(mgr));

    int32_t best = 0;
    for (uint32_t i = 0; i < count; i++) {
        int32_t prio = *(const int32_t *)(array + (size_t)i * sb_compat_tool_stride()
                                          + COMPAT_TOOL_PRIORITY_OFF);
        if (prio > best) best = prio;
    }

    uint8_t  body[BODY_MAX];
    sb_pb_t  w      = { body, sizeof body, 0, 1 };
    uint32_t listed = 0;

    for (uint32_t i = 0; i < count; i++) {
        const uint8_t *tool = array + (size_t)i * sb_compat_tool_stride();
        if (!offered(tool, platforms, bypass)) continue;

        const char *name = tool_name(tool);
        if (!name) continue;

        int32_t prio = *(const int32_t *)(tool + COMPAT_TOOL_PRIORITY_OFF);
        pb_tool(&w, RESP_TOOLS, name,
                *(const char *const *)(tool + COMPAT_TOOL_DISPLAY_OFF),
                active && strcmp(active, name) == 0,
                best != 0 && prio != best && prio > 0);
        if (!w.ok) {
            SB_ERR("compatsvc: tool %s does not fit the reply", name);
            return RESULT_FAIL;
        }
        listed++;
    }

    if (appid && (fallback || holds_none)) {
        pb_tool(&w, RESP_TOOLS, SB_COMPAT_TOOL_NONE, TOOL_NONE_LABEL,
                holds_none, 0);
        if (!w.ok) {
            SB_ERR("compatsvc: the entry for using no tool does not fit the reply");
            return RESULT_FAIL;
        }
        listed++;
    }

    pb_string(&w, RESP_SELECTED, chosen ? chosen : "");

    if (fallback)
        pb_string(&w, RESP_DEFAULT, fallback);

    if (!w.ok) {
        SB_ERR("compatsvc: %u tool(s) do not fit the reply to app %u", listed, appid);
        return RESULT_FAIL;
    }
    if (!sb_webui_parse_into(response, body, (uint32_t)w.len)) {
        SB_ERR("compatsvc: the client rejected the %zu byte reply built for app %u",
               w.len, appid);
        return RESULT_FAIL;
    }

    SB_LOG("compatsvc: app %u is offered %u entr(ies) from %u tool(s) on platforms "
           "0x%x, mapped to %s, running under %s, defaulting to %s", appid, listed,
           count, platforms, chosen ? chosen : "no tool",
           active ? active : "no tool", fallback ? fallback : "no tool");
    return RESULT_OK;
}

static const char *string_field(uintptr_t field) {
    uintptr_t str = *(const uintptr_t *)field & ~(uintptr_t)1;
    if (!str) return "";

    const int8_t *bytes = (const int8_t *)str;
    return bytes[23] < 0 ? *(const char *const *)str : (const char *)str;
}

static int specify_compat_tool(uintptr_t request, uintptr_t response) {
    uint32_t has_bits = *(const uint32_t *)(request + REQ_HAS_BITS_OFF);
    uint32_t appid    = (has_bits & SPECIFY_HAS_APPID)
                      ? *(const uint32_t *)(request + SPECIFY_APPID_OFF) : 0;
    const char *tool  = string_field(request + SPECIFY_TOOL_NAME_OFF);
    (void)response;

    uint8_t *mgr = (uint8_t *)sb_compat_manager();
    if (!mgr) {
        SB_ERR("compatsvc: app %u cannot be mapped to %s before any manager was seen",
               appid, *tool ? tool : "its default");
        return RESULT_FAIL;
    }

    sb_compat_map_tool(mgr, appid, tool);
    SB_LOG("compatsvc: app %u now maps to %s", appid, *tool ? tool : "its default");
    return RESULT_OK;
}

static uintptr_t g_state_changed;
static int g_routes = SB_COMPATSVC_UNTRIED;

void sb_compatsvc_state_changed(void) {
    if (!g_state_changed) return;
    sb_webui_notify(ROUTE_NOTIFY_STATE_CHANGED, g_state_changed);
}

void sb_compatsvc_register(const struct mach_header_64 *mh, intptr_t slide,
                           uintptr_t text_base, size_t text_size) {
    if (g_routes != SB_COMPATSVC_UNTRIED || !sb_webui_registry()) return;

    uintptr_t request  = sb_rtti_vptr(mh, slide, text_base, text_size, TYPE_GET_REQUEST);
    uintptr_t response = sb_rtti_vptr(mh, slide, text_base, text_size, TYPE_GET_RESPONSE);
    if (!request || !response) {
        g_routes = SB_COMPATSVC_ABSENT;
        SB_LOG("compatsvc: the client has no message types for %s",
               ROUTE_GET_COMPAT_TOOLS);
        return;
    }

    sb_webui_register_route(ROUTE_GET_COMPAT_TOOLS, request, response, get_compat_tools);

    uintptr_t specify_request  = sb_rtti_vptr(mh, slide, text_base, text_size,
                                              TYPE_SPECIFY_REQUEST);
    uintptr_t specify_response = sb_rtti_vptr(mh, slide, text_base, text_size,
                                              TYPE_SPECIFY_RESPONSE);
    if (!specify_request || !specify_response) {
        g_routes = SB_COMPATSVC_ABSENT;
        SB_ERR("compatsvc: the client answers %s but has no message types for %s",
               ROUTE_GET_COMPAT_TOOLS, ROUTE_SPECIFY_COMPAT_TOOL);
        return;
    }

    sb_webui_register_route(ROUTE_SPECIFY_COMPAT_TOOL, specify_request,
                            specify_response, specify_compat_tool);

    g_routes = SB_COMPATSVC_READY;

    uintptr_t notification = sb_rtti_vptr(mh, slide, text_base, text_size,
                                          TYPE_STATE_CHANGED);
    g_state_changed = notification ? sb_webui_new_message(notification) : 0;
    if (!g_state_changed)
        SB_WARN("compatsvc: the page will show a stale tool until it is reopened");
}

int sb_compatsvc_routes(void) {
    return g_routes;
}
