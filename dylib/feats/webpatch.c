#include "webpatch.h"
#include "../util/log.h"

#include <stdlib.h>
#include <string.h>

#define SB_C1 "\001"
#define SB_C2 "\002"
#define SB_C3 "\003"
#define SB_C4 "\004"
#define SB_C5 "\005"
#define SB_C6 "\006"
#define SB_C7 "\007"
#define SB_C8 "\010"
#define SB_CAP_MAX 8

typedef struct {
    const char *find;
    const char *replace;
    int         expect;
} sb_gate_t;

typedef struct { const char *at; size_t len; } sb_cap_t;

static int is_ident_char(unsigned char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
           (c >= '0' && c <= '9') || c == '_' || c == '$';
}

static int cap_index(unsigned char c) {
    return (c >= 1 && c <= SB_CAP_MAX) ? c - 1 : -1;
}

static size_t match_at(const char *src, size_t len, size_t pos,
                       const char *find, sb_cap_t *caps) {
    for (int i = 0; i < SB_CAP_MAX; i++) { caps[i].at = NULL; caps[i].len = 0; }

    size_t s = pos;
    for (const char *f = find; *f; f++) {
        int ci = cap_index((unsigned char)*f);
        if (ci < 0) {
            if (s >= len || src[s] != *f) return 0;
            s++;
            continue;
        }

        size_t run = 0;
        while (s + run < len && is_ident_char((unsigned char)src[s + run])) run++;
        if (run == 0) return 0;

        if (caps[ci].at) {
            if (run != caps[ci].len || memcmp(src + s, caps[ci].at, run) != 0)
                return 0;
        } else {
            caps[ci].at = src + s;
            caps[ci].len = run;
        }
        s += run;
    }
    return s - pos;
}

static size_t count_matches(const char *src, size_t len, const char *find) {
    sb_cap_t caps[SB_CAP_MAX];
    size_t n = 0;
    for (size_t i = 0; i < len; ) {
        size_t used = match_at(src, len, i, find, caps);
        if (used) { n++; i += used; } else i++;
    }
    return n;
}

typedef struct { char *buf; size_t len, cap; } sb_out_t;

static int out_reserve(sb_out_t *o, size_t extra) {
    if (o->len + extra + 1 <= o->cap) return 1;
    size_t want = o->cap ? o->cap : 1024;
    while (want < o->len + extra + 1) want *= 2;
    char *grown = realloc(o->buf, want);
    if (!grown) return 0;
    o->buf = grown;
    o->cap = want;
    return 1;
}

static int out_put(sb_out_t *o, const char *p, size_t n) {
    if (!out_reserve(o, n)) return 0;
    memcpy(o->buf + o->len, p, n);
    o->len += n;
    return 1;
}

static int out_expand(sb_out_t *o, const char *replace, const sb_cap_t *caps) {
    for (const char *r = replace; *r; r++) {
        int ci = cap_index((unsigned char)*r);
        if (ci < 0) {
            if (!out_put(o, r, 1)) return 0;
        } else {
            if (!caps[ci].at) return 0;
            if (!out_put(o, caps[ci].at, caps[ci].len)) return 0;
        }
    }
    return 1;
}

#define SB_CX_OPTIONS_CSS \
    "\".MSCXPanel{margin-top:10px}" \
    ".MSCXPanel .MSCXRow{display:flex;flex-direction:row;padding:9px;margin:0;" \
    "color:#dfe3e6;background:rgba(59,63,72,.5);border-radius:3px}" \
    ".MSCXPanel .MSCXRow:hover{box-shadow:0 6px 8px 0 rgba(0,0,0,.16)}" \
    ".MSCXNoBottomGap{margin-bottom:0}\""

#define SB_CX_OPTIONS_BODY(ARG, RT, BARREL) \
    ARG "=>{" \
    "const t=" ARG ".details,o=t.strLaunchOptions||\"\"," \
    "g=k=>{const p=o.split(\" \").find(x=>x.indexOf(k+\"=\")===0);return p?p.slice(k.length+1):\"\"}," \
    "s=ps=>{const a=o.split(\" \").filter(x=>x&&!ps.some(p=>x.indexOf(p[0]+\"=\")===0));" \
    "ps.forEach(p=>{if(p[1])a.unshift(p[0]+\"=\"+p[1])});" \
    "SteamClient.Apps.SetAppLaunchOptions(t.unAppID,a.join(\" \"))}," \
    "T=(ks,l,on,off)=>(0," RT ".jsx)(" BARREL ".Yh,{className:\"MSCXRow\",label:l," \
    "checked:g(ks[0])===on," \
    "onChange:v=>s(ks.map(k=>[k,v?on:(off||\"\")]))},ks[0])," \
    "b=g(\"CX_GRAPHICS_BACKEND\")," \
    "dm=\"\"===b||\"d3dmetal\"===b," \
    "dx=\"\"===b||\"dxmt\"===b," \
    "sw=\"1\"===g(\"DXMT_METALFX_SPATIAL_SWAPCHAIN\")," \
    "F=\"d3d11.metalSpatialUpscaleFactor=\"," \
    "cf=g(\"DXMT_CONFIG\")," \
    "U=[{data:\"\",label:\"Off\"}," \
    "{data:\"1.5\",label:\"1.5x\"}," \
    "{data:\"1.72\",label:\"1.72x\"}," \
    "{data:\"2.0\",label:\"2x\"}," \
    "{data:\"3.0\",label:\"3x\"}]," \
    "B=[{data:\"\",label:\"Automatic\"}," \
    "{data:\"d3dmetal\",label:\"D3DMetal\"}," \
    "{data:\"dxmt\",label:\"DXMT\"}," \
    "{data:\"dxvk\",label:\"DXVK\"}," \
    "{data:\"wined3d\",label:\"WineD3D\"}];" \
    "if(t.unAppID<2147483648&&(t.vecPlatforms||[]).indexOf(\"osx\")>=0" \
    "&&!t.strCompatToolName)return null;" \
    "return(0," RT ".jsx)(\"div\",{className:\"MSCXPanel\",children:(0," RT ".jsxs)(" RT ".Fragment,{children:[" \
    "(0," RT ".jsx)(\"style\",{children:" SB_CX_OPTIONS_CSS "})," \
    "(0," RT ".jsxs)(" BARREL ".XY,{label:\"Graphics\",children:[" \
    "(0," RT ".jsx)(" BARREL ".m,{rgOptions:B,selectedOption:b," \
    "onChange:v=>s([[\"CX_GRAPHICS_BACKEND\",v.data]]" \
    ".concat(\"\"===v.data||\"d3dmetal\"===v.data?[]:[[\"D3DM_ENABLE_METALFX\",\"\"]])" \
    ".concat(\"\"===v.data||\"dxmt\"===v.data?[]:" \
    "[[\"DXMT_METALFX_SPATIAL_SWAPCHAIN\",\"\"],[\"DXMT_CONFIG\",\"\"]])" \
    ".concat(\"dxmt\"===v.data?[]:[[\"DXMT_ENABLE_NVEXT\",\"\"]]))})," \
    "T([\"MTL_HUD_ENABLED\"],\"Metal HUD\",\"1\")," \
    "dm&&T([\"D3DM_ENABLE_METALFX\"],\"DLSS\",\"1\")," \
    "\"dxmt\"===b&&T([\"DXMT_ENABLE_NVEXT\"],\"DLSS\",\"1\")," \
    "T([\"ROSETTA_ADVERTISE_AVX\"],\"Advertise AVX2 to Rosetta\",\"1\",\"0\")," \
    "T([\"WINEMSYNC\"],\"MSync\",\"1\",\"0\")," \
    "T([\"STEAMBRIDGE_RETINA\"],\"High Resolution\",\"1\",\"0\")" \
    "]},\"gfx\")," \
    "dx&&(0," RT ".jsx)(" BARREL ".XY," \
    "{label:\"MetalFX Upscaling (Samples from the resolution the game is set to)\"," \
    "children:(0," RT ".jsx)(" BARREL ".m,{rgOptions:U," \
    "selectedOption:sw?(0===cf.indexOf(F)?cf.slice(F.length):\"2.0\"):\"\"," \
    "onChange:v=>s(v.data?[[\"DXMT_METALFX_SPATIAL_SWAPCHAIN\",\"1\"],[\"DXMT_CONFIG\",F+v.data]]" \
    ":[[\"DXMT_METALFX_SPATIAL_SWAPCHAIN\",\"\"],[\"DXMT_CONFIG\",\"\"]])})},\"usf\")" \
    "]})})}"

#define SB_CX_OPTIONS_COMPONENT \
    "MSCXOpts=" SB_CX_OPTIONS_BODY("e", "i", "c") ","

#define SB_CX_OPTIONS_STATEMENT \
    "var MSCXOpts=" SB_CX_OPTIONS_BODY("np", SB_C3, SB_C4) ";"

static const sb_gate_t g_gates_forcetool[] = {
    { "function ue(e){return(0,T.CI)()?",
      "function ue(e){return true?", 1 },
    { "(0,f.CI)()&&o.push({title:(0,A.we)(\"#AppProperties_CompatibilityPage\")",
      "true&&o.push({title:(0,A.we)(\"#AppProperties_CompatibilityPage\")", 2 },
    { "Compatibility:{visible:t&&(0,f.CI)()&&!(0,f.rf)()",
      "Compatibility:{visible:t&&true&&!(0,f.rf)()", 1 },
    { "return(0,i.jsxs)(i.Fragment,{children:[0!=a.length&&(0,i.jsx)(_r,{label:(0,A.we)"
      "(\"#AppProperties_CompatilibityForceTool\"),checked:g,onChange:C,disabled:!r||0===a.length}),"
      "g&&a.length>0&&(0,i.jsx)(c.m,{strClassName:K().TopGap,rgOptions:d,"
      "selectedOption:t.strCompatToolName,onChange:e=>SteamClient.Apps.SpecifyCompatTool"
      "(t.unAppID,e.data)})]})",
      "return(0,i.jsxs)(i.Fragment,{children:[0!=a.length&&(0,i.jsx)(_r,{label:(0,A.we)"
      "(\"#AppProperties_CompatilibityForceTool\"),checked:g,onChange:C,disabled:!r||0===a.length}),"
      "g&&a.length>0&&(0,i.jsx)(c.m,{strClassName:K().TopGap+\" MSCXNoBottomGap\",rgOptions:d,"
      "selectedOption:t.strCompatToolName,onChange:e=>SteamClient.Apps.SpecifyCompatTool"
      "(t.unAppID,e.data)})]})", 1 },
    { "Rt=(0,a.PA)(e=>(0,i.jsxs)(c.nB,{children:[(0,i.jsx)(\"div\",{className:K().HiddenIfNotLast,"
      "children:(0,A.we)(\"#AppProperties_CompatibilityNoOptions\")}),(0,i.jsx)(It,{...e}),"
      "(0,i.jsx)(xt,{...e})]}));",
      SB_CX_OPTIONS_COMPONENT
      "Rt=(0,a.PA)(e=>(0,i.jsxs)(c.nB,{children:[(0,i.jsx)(\"div\",{className:K().HiddenIfNotLast,"
      "children:(0,A.we)(\"#AppProperties_CompatibilityNoOptions\")}),(0,i.jsx)(It,{...e}),"
      "(0,i.jsx)(xt,{...e}),(0,i.jsx)(MSCXOpts,{...e})]}));", 1 },
    { "get is_invalid_os_type(){return this.most_available_per_client_data.is_invalid_os_type}",
      "get is_invalid_os_type(){return false}", 1 },
    { "s.is_invalid_os_type&&(0,n.jsx)(U,{})",
      "!s.local_per_client_data?.installed&&"
      "s.most_available_per_client_data?.is_invalid_os_type&&(0,n.jsx)(U,{})", 1 },
    { "(0,h.we)(\"#GameList_Entry_Invalid_OSType2\")",
      "\"Enable CrossOver under Properties > Compatibility to install and run "
      "the Windows version.\"", 1 },
};

static const sb_gate_t g_gates_selecttool[] = {
    { "(0," SB_C1 ".CI)()&&" SB_C2 ".push({title:(0," SB_C3 ".we)"
      "(\"#AppProperties_CompatibilityPage\")",
      "true&&" SB_C2 ".push({title:(0," SB_C3 ".we)"
      "(\"#AppProperties_CompatibilityPage\")", 2 },
    { "Compatibility:{visible:" SB_C1 "&&(0," SB_C2 ".CI)(),title:",
      "Compatibility:{visible:" SB_C1 "&&true,title:", 1 },
    { "function " SB_C1 "(" SB_C2 "){return(0," SB_C3 ".jsxs)(" SB_C4 ".XY,{label:(0," SB_C5 ".we)"
      "(\"#Settings_SteamPlay_SteamPlay\"),children:[(0," SB_C3 ".jsx)(" SB_C6 ",{details:" SB_C2 ".details}),"
      "(0," SB_C3 ".jsx)(" SB_C7 ".G,{setting:\"compat_show_all_tools\",label:(0," SB_C5 ".we)"
      "(\"#Settings_SteamPlay_ShowAll\"),feature:" SB_C8 ".OK})]})}",
      SB_CX_OPTIONS_STATEMENT
      "function " SB_C1 "(" SB_C2 "){return(0," SB_C3 ".jsxs)(" SB_C3 ".Fragment,{children:["
      "(0," SB_C3 ".jsxs)(" SB_C4 ".XY,{label:(0," SB_C5 ".we)"
      "(\"#Settings_SteamPlay_SteamPlay\"),children:[(0," SB_C3 ".jsx)(" SB_C6 ",{details:" SB_C2 ".details}),"
      "(0," SB_C3 ".jsx)(" SB_C7 ".G,{setting:\"compat_show_all_tools\",label:(0," SB_C5 ".we)"
      "(\"#Settings_SteamPlay_ShowAll\"),feature:" SB_C8 ".OK})]}),"
      "(0," SB_C3 ".jsx)(MSCXOpts,{details:" SB_C2 ".details})]})}", 1 },
    { "get is_invalid_os_type(){return this.most_available_per_client_data.is_invalid_os_type}",
      "get is_invalid_os_type(){return false}", 1 },
    { SB_C1 ".is_invalid_os_type&&(0," SB_C2 ".jsx)(" SB_C3 ",{})",
      "!" SB_C1 ".local_per_client_data?.installed&&"
      SB_C1 ".most_available_per_client_data?.is_invalid_os_type&&"
      "(0," SB_C2 ".jsx)(" SB_C3 ",{})", 1 },
    { "(0," SB_C1 ".we)(\"#GameList_Entry_Invalid_OSType2\")",
      "\"Enable CrossOver under Properties > Compatibility to install and run "
      "the Windows version.\"", 1 },
};

static const sb_gate_t g_fixes[] = {
    { "(\"#AddNonSteam_Filter_Exe_MacOS\"),rFilePatterns:[\"*.app\"]",
      "(\"#AddNonSteam_Filter_Exe_MacOS\"),rFilePatterns:[\"*.app\",\"*.exe\"]", 1 },
    { "{strFileTypeName:\"Image Files (*.tga,*.png)\",rFilePatterns:[\"*.tga\",\"*.png\"]}",
      "{strFileTypeName:\"Image Files (*.tga,*.png,*.exe)\","
      "rFilePatterns:[\"*.tga\",\"*.png\",\"*.exe\"]}", 1 },
};
#define SB_FIX_COUNT (sizeof(g_fixes) / sizeof(g_fixes[0]))

typedef struct {
    const char     *name;
    const char     *probe;
    const sb_gate_t *gates;
    size_t          count;
} sb_ui_shape_t;

static const sb_ui_shape_t g_shapes[] = {
    { SB_SHAPE_FORCETOOL,  "#AppProperties_CompatilibityForceTool",
      g_gates_forcetool,  sizeof(g_gates_forcetool) / sizeof(g_gates_forcetool[0]) },
    { SB_SHAPE_SELECTTOOL, "#AppProperties_Compat_SelectTool",
      g_gates_selecttool, sizeof(g_gates_selecttool) / sizeof(g_gates_selecttool[0]) },
};
#define SB_SHAPE_COUNT (sizeof(g_shapes) / sizeof(g_shapes[0]))

static int has_suffix(const char *s, const char *suf) {
    size_t ls = strlen(s), lf = strlen(suf);
    return ls >= lf && memcmp(s + ls - lf, suf, lf) == 0;
}

int sb_webpatch_should_patch(const char *path) {
    return path
        && strstr(path, "steamui") != NULL
        && strstr(path, "/chunk~") != NULL
        && has_suffix(path, ".js");
}

char *sb_webpatch_transform(const uint8_t *src, size_t src_len, size_t *out_len,
                            const char **out_shape) {
    const char *s = (const char *)src;

    if (out_shape)
        *out_shape = NULL;

    const sb_ui_shape_t *shape = NULL;
    for (size_t i = 0; i < SB_SHAPE_COUNT; i++) {
        if (count_matches(s, src_len, g_shapes[i].probe) == 0)
            continue;
        if (shape) {
            SB_WARN("webpatch: chunk carries both the '%s' and '%s' compat UI, "
                    "refusing to guess which one renders", shape->name, g_shapes[i].name);
            return NULL;
        }
        shape = &g_shapes[i];
    }
    int    fix_on[SB_FIX_COUNT];
    size_t fix_live = 0;
    for (size_t f = 0; f < SB_FIX_COUNT; f++) {
        size_t n = count_matches(s, src_len, g_fixes[f].find);
        fix_on[f] = n == (size_t)g_fixes[f].expect;
        if (fix_on[f]) { fix_live++; continue; }
        if (n)
            SB_WARN("webpatch: fix %zu expected %d occurrence(s), found %zu; "
                    "leaving it alone", f, g_fixes[f].expect, n);
    }

    if (!shape && !fix_live)
        return NULL;

    if (shape) {
        if (out_shape)
            *out_shape = shape->name;

        int drifted = 0;
        for (size_t g = 0; g < shape->count; g++) {
            size_t n = count_matches(s, src_len, shape->gates[g].find);
            if (n != (size_t)shape->gates[g].expect) {
                SB_WARN("webpatch: [%s] gate %zu expected %d occurrence(s), found %zu",
                        shape->name, g, shape->gates[g].expect, n);
                drifted = 1;
            }
        }
        if (drifted) {
            SB_ERR("webpatch: [%s] compat UI left unpatched, a Steam update moved the "
                   "anchors", shape->name);
            return NULL;
        }
    }

    sb_out_t out = {0};
    sb_cap_t caps[SB_CAP_MAX];
    for (size_t i = 0; i < src_len; ) {
        const sb_gate_t *hit = NULL;
        size_t used = 0;
        for (size_t g = 0; shape && g < shape->count; g++) {
            used = match_at(s, src_len, i, shape->gates[g].find, caps);
            if (used) { hit = &shape->gates[g]; break; }
        }
        for (size_t f = 0; !hit && f < SB_FIX_COUNT; f++) {
            if (!fix_on[f]) continue;
            used = match_at(s, src_len, i, g_fixes[f].find, caps);
            if (used) { hit = &g_fixes[f]; break; }
        }
        int ok = hit ? out_expand(&out, hit->replace, caps)
                     : out_put(&out, s + i, 1);
        if (!ok) { free(out.buf); return NULL; }
        i += hit ? used : 1;
    }

    if (!out_reserve(&out, 0)) { free(out.buf); return NULL; }
    out.buf[out.len] = '\0';
    *out_len = out.len;
    SB_LOG("webpatch: [%s] %zu gates, %zu fixes applied",
           shape ? shape->name : "no compat UI", shape ? shape->count : 0, fix_live);
    return out.buf;
}
