#include "../feats/webpatch.c"

#include <stdarg.h>
#include <stdio.h>

int   sb_log_level = SB_LVL_INFO;
FILE *sb_log_file;

static int g_wrong;

static void wrong(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    fputs("WRONG: ", stdout);
    vprintf(fmt, ap);
    fputc('\n', stdout);
    va_end(ap);
    g_wrong = 1;
}

static void check_gate(const char *nm, size_t i, const sb_gate_t *a,
                       const sb_gate_t *group, size_t group_n) {
    if (!a->find || !*a->find)       wrong("[%s] gate %zu has no anchor", nm, i);
    if (!a->replace || !*a->replace) wrong("[%s] gate %zu has no replacement", nm, i);
    if (a->expect < 1)               wrong("[%s] gate %zu expects %d hits", nm, i, a->expect);
    if (a->find && a->replace && strcmp(a->find, a->replace) == 0)
        wrong("[%s] gate %zu replaces its anchor with itself", nm, i);
    if (a->find && a->replace && *a->find && strstr(a->replace, a->find))
        wrong("[%s] gate %zu replacement still contains its own anchor", nm, i);
    for (const char *r = a->replace; r && *r; r++) {
        int ci = cap_index((unsigned char)*r);
        if (ci >= 0 && !strchr(a->find, *r))
            wrong("[%s] gate %zu replacement reads capture %d, anchor never binds it",
                  nm, i, ci + 1);
    }
    for (size_t j = 0; j < group_n; j++) {
        if (i == j || !a->find || !group[j].find || !*group[j].find) continue;
        if (strstr(a->find, group[j].find))
            wrong("[%s] gate %zu anchor contains gate %zu anchor", nm, i, j);
    }
}

static void selfcheck(void) {
    size_t total = 0;
    for (size_t sh = 0; sh < SB_SHAPE_COUNT; sh++) {
        const sb_ui_shape_t *S = &g_shapes[sh];
        const char *nm = S->name;
        if (!S->probe || !*S->probe) wrong("[%s] has no probe", nm);
        for (size_t o = 0; o < SB_SHAPE_COUNT; o++) {
            if (o == sh) continue;
            if (strcmp(S->probe, g_shapes[o].probe) == 0)
                wrong("[%s] and [%s] share a probe", nm, g_shapes[o].name);
        }
        for (size_t i = 0; i < S->count; i++)
            check_gate(nm, i, &S->gates[i], S->gates, S->count);
        total += S->count;
    }

    for (size_t f = 0; f < SB_FIX_COUNT; f++) {
        check_gate("fix", f, &g_fixes[f], g_fixes, SB_FIX_COUNT);
        for (size_t sh = 0; sh < SB_SHAPE_COUNT; sh++)
            for (size_t g = 0; g < g_shapes[sh].count; g++)
                if (strstr(g_fixes[f].find, g_shapes[sh].gates[g].find) ||
                    strstr(g_shapes[sh].gates[g].find, g_fixes[f].find))
                    wrong("fix %zu and [%s] gate %zu share an anchor",
                          f, g_shapes[sh].name, g);
    }

    printf("%zu shapes, %zu gates, %zu fixes checked\n",
           SB_SHAPE_COUNT, total, SB_FIX_COUNT);
}

static uint8_t *slurp(const char *path, size_t *len) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (n < 0) { fclose(f); return NULL; }
    uint8_t *buf = malloc((size_t)n + 1);
    if (!buf) { fclose(f); return NULL; }
    size_t got = fread(buf, 1, (size_t)n, f);
    fclose(f);
    buf[got] = 0;
    *len = got;
    return buf;
}

static const sb_ui_shape_t *shape_of(const char *buf, size_t len) {
    for (size_t i = 0; i < SB_SHAPE_COUNT; i++)
        if (count_matches(buf, len, g_shapes[i].probe) > 0) return &g_shapes[i];
    return NULL;
}

static void check_output(const char *out, size_t out_len) {
    const sb_ui_shape_t *S = shape_of(out, out_len);
    if (!S) { wrong("the patched chunk no longer matches any known compat UI"); return; }
    for (size_t g = 0; g < S->count; g++) {
        if (count_matches(out, out_len, S->gates[g].find) != 0)
            wrong("[%s] gate %zu anchor survived the patch", S->name, g);
        if (count_matches(out, out_len, S->gates[g].replace)
            < (size_t)S->gates[g].expect)
            wrong("[%s] gate %zu replacement is missing from the patch", S->name, g);
    }
    for (size_t f = 0; f < SB_FIX_COUNT; f++) {
        size_t anchor = count_matches(out, out_len, g_fixes[f].find);
        size_t repl   = count_matches(out, out_len, g_fixes[f].replace);
        if (!anchor && !repl) continue;
        if (anchor)
            wrong("fix %zu anchor survived the patch", f);
        if (repl < (size_t)g_fixes[f].expect)
            wrong("fix %zu replacement is missing from the patch", f);
    }

    size_t again_len = 0;
    int saved = sb_log_level;
    sb_log_level = -1;
    char *again = sb_webpatch_transform((const uint8_t *)out, out_len, &again_len, NULL);
    sb_log_level = saved;
    if (again) { wrong("a patched chunk was patched a second time"); free(again); }
}

static int extract(const char *chunk, const char *out_path) {
    size_t len = 0;
    uint8_t *buf = slurp(chunk, &len);
    if (!buf) { fprintf(stderr, "cannot read %s\n", chunk); return 1; }

    FILE *o = fopen(out_path, "wb");
    if (!o) { fprintf(stderr, "cannot write %s\n", out_path); free(buf); return 1; }

    const sb_ui_shape_t *S = shape_of((const char *)buf, len);
    if (!S) {
        fprintf(stderr, "%s carries no known compat UI\n", chunk);
        fclose(o); free(buf);
        return 1;
    }
    fprintf(o, "%s\n", S->probe);

    const size_t pad = 160;
    sb_cap_t caps[SB_CAP_MAX];
    for (size_t g = 0; g < S->count; g++) {
        size_t hits = 0;
        for (size_t i = 0; i < len; ) {
            size_t used = match_at((const char *)buf, len, i, S->gates[g].find, caps);
            if (!used) { i++; continue; }
            size_t from = i > pad ? i - pad : 0;
            size_t to   = i + used + pad < len ? i + used + pad : len;
            fwrite(buf + from, 1, to - from, o);
            fputs("\n", o);
            hits++;
            i += used;
        }
        if (hits != (size_t)S->gates[g].expect) {
            fprintf(stderr, "[%s] gate %zu found %zu times in %s, table expects %d\n",
                    S->name, g, hits, chunk, S->gates[g].expect);
            fclose(o); free(buf);
            return 1;
        }
    }
    fclose(o);
    free(buf);
    printf("extracted fixture to %s\n", out_path);
    return 0;
}

int main(int argc, char **argv) {
    if (argc == 4 && strcmp(argv[1], "--extract") == 0)
        return extract(argv[2], argv[3]);

    if (argc < 2) { selfcheck(); return g_wrong; }

    for (int i = 1; i < argc; i++) {
        size_t len = 0;
        uint8_t *buf = slurp(argv[i], &len);
        if (!buf) { wrong("cannot read %s", argv[i]); continue; }

        size_t out_len = 0;
        char *out = sb_webpatch_transform(buf, len, &out_len, NULL);
        if (out) {
            check_output(out, out_len);
            printf("APPLIED  %s\n", argv[i]);
            free(out);
        } else {
            printf("REJECTED %s\n", argv[i]);
        }
        free(buf);
    }
    return g_wrong;
}
