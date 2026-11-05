#include "sigdb.h"
#include "../util/log.h"
#include "../util/file.h"
#include "../../vendor/cJSON.h"

#include <stdlib.h>
#include <string.h>

static cJSON *read_json_file(const char *path) {
    size_t n = 0;
    uint8_t *raw = sb_read_whole_file(path, &n);
    if (!raw) return NULL;
    uint8_t *buf = realloc(raw, n + 1);
    if (!buf) { free(raw); return NULL; }
    buf[n] = '\0';
    cJSON *j = cJSON_Parse((char *)buf);
    free(buf);
    return j;
}

static void str_field(cJSON *parent, const char *key, char *dst, size_t cap) {
    cJSON *v = cJSON_GetObjectItem(parent, key);
    if (!v || !cJSON_IsString(v) || !v->valuestring || cap == 0) return;
    size_t n = strlen(v->valuestring);
    if (n >= cap) n = cap - 1;
    memcpy(dst, v->valuestring, n);
    dst[n] = '\0';
}

static uintptr_t hex_field(cJSON *parent, const char *key) {
    cJSON *v = cJSON_GetObjectItem(parent, key);
    if (!v || !cJSON_IsString(v) || !v->valuestring) return 0;
    const char *s = v->valuestring;
    if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) s += 2;
    return (uintptr_t)strtoull(s, NULL, 16);
}

static uint64_t build_field(cJSON *parent, const char *key) {
    cJSON *v = cJSON_GetObjectItem(parent, key);
    if (!v) return 0;
    if (cJSON_IsString(v) && v->valuestring)
        return strtoull(v->valuestring, NULL, 10);
    if (cJSON_IsNumber(v))
        return (uint64_t)v->valuedouble;
    return 0;
}

static int int_field(cJSON *parent, const char *key, int fallback) {
    cJSON *v = cJSON_GetObjectItem(parent, key);
    return (v && cJSON_IsNumber(v)) ? v->valueint : fallback;
}

static int load_insn_pair(cJSON *anchor_obj, sb_insn_pair_t *p) {
    cJSON *obj = cJSON_GetObjectItem(anchor_obj, "pair");
    if (!obj || !cJSON_IsObject(obj)) return -1;

    p->first       = (uint32_t)hex_field(obj, "first");
    p->first_mask  = (uint32_t)hex_field(obj, "first_mask");
    p->second      = (uint32_t)hex_field(obj, "second");
    p->second_mask = (uint32_t)hex_field(obj, "second_mask");
    p->tie_mask    = (uint32_t)hex_field(obj, "tie_mask");

    cJSON *land = cJSON_GetObjectItem(obj, "land");
    p->land_on_second = (land && cJSON_IsString(land) && land->valuestring &&
                         strcmp(land->valuestring, "second") == 0) ? 1 : 0;

    if (!p->first_mask || !p->second_mask) return -1;
    return 0;
}

static int load_call_path(cJSON *obj, sb_anchor_t *a) {
    cJSON *arr = cJSON_GetObjectItem(obj, "call_path");
    if (!arr || !cJSON_IsArray(arr)) return -1;

    int n = cJSON_GetArraySize(arr);
    if (n < 1 || n > SB_CALL_PATH_MAX) return -1;

    for (int i = 0; i < n; i++) {
        cJSON *e = cJSON_GetArrayItem(arr, i);
        if (!e || !cJSON_IsNumber(e)) return -1;
        if (e->valueint < 1) return -1;
        a->call_path[i] = e->valueint;
    }
    a->call_depth = n;
    return 0;
}

static void load_anchor(cJSON *sig_obj, sb_anchor_t *a) {
    cJSON *obj = cJSON_GetObjectItem(sig_obj, "anchor");
    if (!obj || !cJSON_IsObject(obj)) return;

    cJSON *kind = cJSON_GetObjectItem(obj, "kind");
    if (!kind || !cJSON_IsString(kind) || !kind->valuestring) return;

    const char *ks = kind->valuestring;
    if (strcmp(ks, "string") == 0) {
        a->kind = SB_MATCH_STRING;
        str_field(obj, "value", a->str, sizeof(a->str));
    } else if (strcmp(ks, "insn_after_string") == 0) {
        a->kind = SB_MATCH_INSN_AFTER_STRING;
        str_field(obj, "value", a->str, sizeof(a->str));
        a->nth = int_field(obj, "n", 1);
    } else if (strcmp(ks, "insn_pair_in_fn") == 0) {
        a->kind = SB_MATCH_INSN_PAIR_IN_FN;
        str_field(obj, "value", a->str, sizeof(a->str));
        if (load_insn_pair(obj, &a->pair) != 0) {
            SB_WARN("sigdb: anchor '%s' has no usable pair; ignoring it", a->str);
            a->kind = SB_MATCH_NONE;
            return;
        }
    } else if (strcmp(ks, "call_target") == 0) {
        a->kind = SB_MATCH_CALL_TARGET;
        str_field(obj, "value", a->str, sizeof(a->str));
        if (load_call_path(obj, a) != 0) {
            SB_WARN("sigdb: anchor '%s' has no usable call_path; ignoring it", a->str);
            a->kind = SB_MATCH_NONE;
            return;
        }
    } else if (strcmp(ks, "vtable_slot") == 0) {
        a->va = hex_field(obj, "va");
        if (!a->va) {
            SB_WARN("sigdb: vtable_slot anchor has no usable va; ignoring it");
            a->kind = SB_MATCH_NONE;
            return;
        }
        a->kind = SB_MATCH_VTABLE_SLOT;
        return;
    } else if (strcmp(ks, "aob") == 0) {
        a->kind = SB_MATCH_AOB;
        return;
    } else {
        return;
    }

    int nth_xref    = int_field(obj, "nth_xref", 0);
    int caller_hops = int_field(obj, "caller_hops", 0);
    if (nth_xref < 0 || caller_hops < 0) {
        SB_WARN("sigdb: anchor '%s' has a negative nth_xref/caller_hops; ignoring it",
                a->str);
        a->kind = SB_MATCH_NONE;
        return;
    }

    a->nth_xref    = nth_xref;
    a->caller_hops = caller_hops;

    cJSON *tail = cJSON_GetObjectItem(obj, "caller_tail");
    a->caller_tail = (tail && cJSON_IsTrue(tail)) ? 1 : 0;

    if (a->caller_tail && !caller_hops) {
        SB_WARN("sigdb: anchor '%s' sets caller_tail without caller_hops; ignoring it",
                a->str);
        a->kind = SB_MATCH_NONE;
        return;
    }

    cJSON *ind = cJSON_GetObjectItem(obj, "indirect");
    a->indirect = (ind && cJSON_IsTrue(ind)) ? 1 : 0;
}

int sb_load_profile(const char *path, sb_sigdb_t *out) {
    if (!path || !out) return -1;
    memset(out, 0, sizeof(*out));

    cJSON *root = read_json_file(path);
    if (!root) { SB_ERR("sigdb: cannot read or parse '%s'", path); return -1; }

    cJSON *v;
    if ((v = cJSON_GetObjectItem(root, "schema_version")))
        out->schema_version = v->valueint;
    if ((v = cJSON_GetObjectItem(root, "profile_version")))
        out->sigdb_version = v->valueint;
    out->steam_build = build_field(root, "steam_build");
    str_field(root, "steam_build_date", out->steam_build_date, sizeof(out->steam_build_date));

    cJSON *arr = cJSON_GetObjectItem(root, "signatures");
    int total = (arr && cJSON_IsArray(arr)) ? cJSON_GetArraySize(arr) : 0;

    if (total > 0) {
        out->signatures = calloc((size_t)total, sizeof(sb_sig_entry_t));
        if (!out->signatures) { cJSON_Delete(root); return -1; }
        out->sig_count = total;

        cJSON *elem = NULL;
        int i = 0;
        cJSON_ArrayForEach(elem, arr) {
            if (i >= total) break;
            sb_sig_entry_t *e = &out->signatures[i++];

            str_field(elem, "name",    e->name,    sizeof(e->name));
            str_field(elem, "module",  e->module,  sizeof(e->module));
            str_field(elem, "aob_hex", e->aob_hex, sizeof(e->aob_hex));
            e->func_addr_this_build = hex_field(elem, "func_addr_this_build");

            if (!e->module[0])
                memcpy(e->module, SB_MODULE_DEFAULT, sizeof(SB_MODULE_DEFAULT));

            if ((v = cJSON_GetObjectItem(elem, "deprecated")))
                e->deprecated = cJSON_IsTrue(v);
            if ((v = cJSON_GetObjectItem(elem, "match_offset"))) {
                if (cJSON_IsNumber(v)) {
                    e->match_offset = (int32_t)v->valueint;
                } else {
                    SB_WARN("sigdb: '%s' has a non-numeric match_offset; dropping "
                            "its byte pattern", e->name);
                    e->aob_hex[0] = '\0';
                }
            }

            load_anchor(elem, &e->anchor);

            if (e->anchor.kind == SB_MATCH_AOB && !e->aob_hex[0]) {
                SB_WARN("sigdb: '%s' anchors on its byte pattern but carries none; "
                        "ignoring it", e->name);
                e->anchor.kind = SB_MATCH_NONE;
            }
        }
    }

    cJSON_Delete(root);
    SB_LOG("sigdb: loaded %d signatures from '%s' (schema=%d, profile=%d, steam_build=%llu %s)",
           out->sig_count, path, out->schema_version, out->sigdb_version,
           (unsigned long long)out->steam_build,
           out->steam_build_date[0] ? out->steam_build_date : "");
    return 0;
}

void sb_free_profile(sb_sigdb_t *p) {
    if (!p) return;
    free(p->signatures);
    p->signatures   = NULL;
    p->sig_count = 0;
}
