#include "anchor.h"
#include "resolver.h"
#include "../core/macho.h"
#include "../util/log.h"

#include <dlfcn.h>
#include <string.h>

#define DEFAULT_INSN      0xD63F0000u
#define DEFAULT_INSN_MASK 0xFFFFFC1Fu

static const char *const data_segs[] = {"__DATA_CONST", "__DATA"};
#define N_DATA_SEGS ((int)(sizeof(data_segs) / sizeof(data_segs[0])))

static uintptr_t adrp_target(uintptr_t pc, uint32_t w, int *reg) {
    if ((w & 0x9F000000u) != 0x90000000u) return 0;
    *reg = (int)(w & 0x1Fu);
    uint32_t lo = (w >> 29) & 3u;
    uint32_t hi = (w >> 5)  & 0x7FFFFu;
    int64_t imm = (int64_t)((hi << 2) | lo);
    imm = (imm << 43) >> 43;
    return (pc & ~(uintptr_t)0xFFF) + (uintptr_t)(imm << 12);
}

static uintptr_t add_imm_target(uint32_t w, int expected_rn, uintptr_t page) {
    if ((w & 0x7F800000u) != 0x11000000u) return 0;
    if ((int)((w >> 5) & 0x1Fu) != expected_rn) return 0;
    uint32_t imm = (w >> 10) & 0xFFFu;
    if ((w >> 22) & 1u) imm <<= 12;
    return page + imm;
}

static uintptr_t ldr_slot_addr(uint32_t w, int expected_rn, uintptr_t page) {
    if ((w & 0xFFC00000u) != 0xF9400000u) return 0;
    if ((int)((w >> 5) & 0x1Fu) != expected_rn) return 0;
    uint32_t imm12 = (w >> 10) & 0xFFFu;
    return page + (uintptr_t)imm12 * 8u;
}

static uintptr_t branch26_target(uintptr_t pc, uint32_t w, uint32_t opcode) {
    if ((w & 0xFC000000u) != opcode) return 0;
    int64_t imm = (int64_t)(w & 0x03FFFFFFu);
    imm = (imm << 38) >> 38;
    return pc + (uintptr_t)(imm * 4);
}

static uintptr_t bl_target(uintptr_t pc, uint32_t w) {
    return branch26_target(pc, w, 0x94000000u);
}

static uintptr_t b_target(uintptr_t pc, uint32_t w) {
    return branch26_target(pc, w, 0x14000000u);
}

static const struct { uint32_t mask, val; } entry_forms[] = {
    { 0xFF0003FF, 0xD10003FF },
    { 0xFFC003E0, 0xA98003E0 },
    { 0xFFFFFFFF, 0xD503237F },
};

static int is_entry_insn(uintptr_t pc) {
    uint32_t w = *(const uint32_t *)pc;
    for (size_t i = 0; i < sizeof(entry_forms) / sizeof(entry_forms[0]); i++) {
        if ((w & entry_forms[i].mask) == entry_forms[i].val) return 1;
    }
    return 0;
}

static uintptr_t cstring_va(const struct mach_header_64 *mh, intptr_t slide,
                            const char *needle) {
    static const char *candidates[] = {"__TEXT", "__DATA_CONST", "__DATA"};
    size_t needle_len = strlen(needle);

    for (int s = 0; s < (int)(sizeof(candidates) / sizeof(candidates[0])); s++) {
        uintptr_t seg_base;
        size_t seg_size;
        if (sb_find_segment(mh, slide, candidates[s], &seg_base, &seg_size) != 0)
            continue;
        if (seg_size <= needle_len) continue;

        const char *region = (const char *)seg_base;
        uintptr_t result = 0;
        for (size_t off = 0; off + needle_len < seg_size; off++) {
            if (region[off] != needle[0]) continue;
            if (memcmp(region + off, needle, needle_len) != 0) continue;
            if (region[off + needle_len] != '\0') continue;
            if (result) return 0;
            result = seg_base + off;
            off += needle_len;
        }
        if (result) return result;
    }
    return 0;
}

static uintptr_t xref_to_va(uintptr_t text, size_t text_sz, uintptr_t target,
                            int nth, int indirect) {
    size_t words = text_sz / 4;
    if (words < 2) return 0;

    const uint32_t *code = (const uint32_t *)text;
    uintptr_t first = 0;
    int seen = 0;

    for (size_t i = 0; i + 1 < words; i++) {
        int reg = -1;
        uintptr_t page = adrp_target(text + i * 4, code[i], &reg);
        if (!page) continue;

        uintptr_t addr = indirect ? ldr_slot_addr(code[i + 1], reg, page)
                                  : add_imm_target(code[i + 1], reg, page);
        if (!addr || addr != target) continue;

        seen++;
        if (nth > 0) {
            if (seen == nth) return text + i * 4;
            continue;
        }
        if (first) return 0;
        first = text + i * 4;
    }
    return nth > 0 ? 0 : first;
}

static uintptr_t slot_holding(uintptr_t seg, size_t seg_sz,
                              uintptr_t a, uintptr_t b) {
    if (seg_sz < sizeof(uintptr_t)) return 0;
    const uintptr_t *p = (const uintptr_t *)seg;
    size_t n = seg_sz / sizeof(uintptr_t);
    uintptr_t found = 0;
    for (size_t i = 0; i < n; i++) {
        if (p[i] != a && !(b && p[i] == b)) continue;
        if (found) return 0;
        found = seg + i * sizeof(uintptr_t);
    }
    return found;
}

static uintptr_t uniqued_selector(const char *name) {
    static void *(*sel_get_uid)(const char *);
    static int looked_up;
    if (!looked_up) {
        looked_up = 1;
        sel_get_uid = (void *(*)(const char *))dlsym(RTLD_DEFAULT, "sel_getUid");
    }
    return sel_get_uid ? (uintptr_t)sel_get_uid(name) : 0;
}


static uintptr_t enclosing_fn(const struct mach_header_64 *mh, intptr_t slide,
                              uintptr_t text, uintptr_t pc) {
    uintptr_t floor = text;
    uintptr_t sect_base;
    size_t sect_size;
    if (sb_get_section_containing(mh, slide, pc, &sect_base, &sect_size) == 0)
        floor = sect_base;

    while (pc >= floor) {
        if (is_entry_insn(pc)) return pc;
        if (pc == floor) break;
        pc -= 4;
    }
    return 0;
}

static uintptr_t sole_caller(const struct mach_header_64 *mh, intptr_t slide,
                             uintptr_t text, size_t text_sz, uintptr_t callee,
                             int tail) {
    size_t words = text_sz / 4;
    const uint32_t *code = (const uint32_t *)text;
    uintptr_t found = 0;
    for (size_t i = 0; i < words; i++) {
        uintptr_t pc = text + i * 4;
        uintptr_t t = tail ? b_target(pc, code[i]) : bl_target(pc, code[i]);
        if (t != callee) continue;
        if (tail && enclosing_fn(mh, slide, text, pc) == callee) continue;
        if (found) return 0;
        found = pc;
    }
    return found ? enclosing_fn(mh, slide, text, found) : 0;
}


#define MAX_CALLER_HOPS 4

static uintptr_t hop_to_caller(const struct mach_header_64 *mh, intptr_t slide,
                               uintptr_t text, size_t text_sz, uintptr_t from,
                               int hops, int tail) {
    if (hops > MAX_CALLER_HOPS) {
        SB_WARN("anchor: caller_hops=%d exceeds the %d supported", hops,
                MAX_CALLER_HOPS);
        return 0;
    }
    for (int i = 0; i < hops; i++) {
        from = sole_caller(mh, slide, text, text_sz, from, tail);
        if (!from) return 0;
    }
    return from;
}

static uintptr_t scan_for_insn(uintptr_t text, size_t text_sz,
                               uintptr_t start,
                               uint32_t opcode, uint32_t opmask, int nth) {
    uintptr_t bound = text + text_sz;
    int count = 0;
    for (uintptr_t pc = start; pc + 4 <= bound; pc += 4) {
        uint32_t w = *(const uint32_t *)pc;
        if ((w & opmask) == opcode) {
            if (++count == nth) return pc + 4;
        }
    }
    return 0;
}

static uintptr_t body_end(const struct mach_header_64 *mh, intptr_t slide,
                          uintptr_t fn, uintptr_t text, size_t text_sz) {
    uintptr_t cap = fn + SB_FN_SPAN_MAX;
    uintptr_t bound = text + text_sz;
    if (cap > bound) cap = bound;

    uintptr_t start, end;
    if (sb_function_bounds(mh, slide, fn, &start, &end) == 0 &&
        start == fn && end > fn && end <= bound)
        return end < cap ? end : cap;

    for (uintptr_t pc = fn + 4; pc + 4 <= cap; pc += 4) {
        if (is_entry_insn(pc)) return pc;
    }
    return cap;
}

static uintptr_t nth_call_target(const struct mach_header_64 *mh, intptr_t slide,
                                 uintptr_t fn, uintptr_t text, size_t text_sz,
                                 int nth) {
    uintptr_t end   = body_end(mh, slide, fn, text, text_sz);
    uintptr_t limit = text + text_sz - 4;
    int seen = 0;

    for (uintptr_t pc = fn; pc + 4 <= end; pc += 4) {
        uintptr_t t = bl_target(pc, *(const uint32_t *)pc);
        if (!t) continue;
        if (++seen != nth) continue;
        if (t < text || t > limit) return 0;

        uintptr_t through = b_target(t, *(const uint32_t *)t);
        if (through && through >= text && through <= limit) t = through;
        return t;
    }
    return 0;
}

static uintptr_t walk_call_path(const struct mach_header_64 *mh, intptr_t slide,
                                uintptr_t fn, uintptr_t text, size_t text_sz,
                                const sb_anchor_t *anchor) {
    if (anchor->call_depth < 1 || anchor->call_depth > SB_CALL_PATH_MAX) {
        SB_WARN("anchor: call_depth=%d outside 1..%d", anchor->call_depth,
                SB_CALL_PATH_MAX);
        return 0;
    }
    for (int i = 0; i < anchor->call_depth; i++) {
        fn = nth_call_target(mh, slide, fn, text, text_sz, anchor->call_path[i]);
        if (!fn) return 0;
    }
    return sb_looks_like_prologue(fn) ? fn : 0;
}

static uintptr_t sole_insn_pair(const struct mach_header_64 *mh, intptr_t slide,
                                uintptr_t fn, uintptr_t text, size_t text_sz,
                                const sb_insn_pair_t *p) {
    uintptr_t end = body_end(mh, slide, fn, text, text_sz);
    uintptr_t found = 0;

    for (uintptr_t pc = fn; pc + 8 <= end; pc += 4) {
        uint32_t a = *(const uint32_t *)pc;
        uint32_t b = *(const uint32_t *)(pc + 4);
        if ((a & p->first_mask)  != p->first)  continue;
        if ((b & p->second_mask) != p->second) continue;
        if (p->tie_mask && (a & p->tie_mask) != (b & p->tie_mask)) continue;
        if (found) return 0;
        found = p->land_on_second ? pc + 4 : pc;
    }
    return found;
}

uintptr_t sb_locate_anchor(const struct mach_header_64 *mh, intptr_t slide,
                            uintptr_t text_base, size_t text_size,
                            const sb_anchor_t *anchor) {
    if (!mh || !anchor || !text_base || !text_size) return 0;

    if (anchor->kind == SB_MATCH_VTABLE_SLOT) {
        if (!anchor->va) return 0;

        uintptr_t sect_base = 0;
        size_t    sect_size = 0;
        uintptr_t slot = anchor->va + (uintptr_t)slide;
        if (sb_get_section_containing(mh, slide, slot, &sect_base, &sect_size) != 0)
            return 0;
        if (sect_size < sizeof(uintptr_t)) return 0;
        if (slot - sect_base > sect_size - sizeof(uintptr_t)) return 0;

        uintptr_t fn = *(const uintptr_t *)slot;
        if (fn < text_base || fn > text_base + text_size - sizeof(uint32_t)) return 0;
        return sb_looks_like_prologue(fn) ? fn : 0;
    }

    uintptr_t str = cstring_va(mh, slide, anchor->str);
    if (!str) return 0;

    uintptr_t target = str;
    if (anchor->indirect) {
        uintptr_t uniqued = uniqued_selector(anchor->str);
        uintptr_t slot = 0;
        for (int s = 0; s < N_DATA_SEGS && !slot; s++) {
            uintptr_t base;
            size_t size;
            if (sb_find_segment(mh, slide, data_segs[s], &base, &size) != 0) continue;
            slot = slot_holding(base, size, str, uniqued);
        }
        if (!slot) return 0;
        target = slot;
    }

    uintptr_t ref = xref_to_va(text_base, text_size, target,
                               anchor->nth_xref, anchor->indirect);
    if (!ref) return 0;

    if (anchor->kind == SB_MATCH_INSN_AFTER_STRING) {
        uint32_t opcode = anchor->insn      ? anchor->insn      : DEFAULT_INSN;
        uint32_t opmask = anchor->insn_mask ? anchor->insn_mask : DEFAULT_INSN_MASK;
        int n = anchor->nth > 0 ? anchor->nth : 1;
        return scan_for_insn(text_base, text_size, ref, opcode, opmask, n);
    }

    if (anchor->kind != SB_MATCH_STRING &&
        anchor->kind != SB_MATCH_INSN_PAIR_IN_FN &&
        anchor->kind != SB_MATCH_CALL_TARGET) return 0;

    uintptr_t fn;
    if (anchor->caller_hops > 0) {
        fn = hop_to_caller(mh, slide, text_base, text_size, ref,
                           anchor->caller_hops, anchor->caller_tail);
        if (!fn) {
            uintptr_t body = enclosing_fn(mh, slide, text_base, ref);
            if (body) fn = hop_to_caller(mh, slide, text_base, text_size, body,
                                         anchor->caller_hops, anchor->caller_tail);
        }
    } else {
        fn = enclosing_fn(mh, slide, text_base, ref);
    }
    if (!fn) return 0;

    if (anchor->kind == SB_MATCH_INSN_PAIR_IN_FN)
        return sole_insn_pair(mh, slide, fn, text_base, text_size, &anchor->pair);
    if (anchor->kind == SB_MATCH_CALL_TARGET)
        return walk_call_path(mh, slide, fn, text_base, text_size, anchor);
    return fn;
}

static uintptr_t type_name_va(const struct mach_header_64 *mh, intptr_t slide,
                              const char *name) {
    uintptr_t base;
    size_t size;
    if (sb_find_segment(mh, slide, "__TEXT", &base, &size) != 0) return 0;

    size_t len = strlen(name);
    if (size <= len + 1) return 0;

    const char *region = (const char *)base;
    uintptr_t found = 0;
    for (size_t off = 1; off + len < size; off++) {
        if (region[off] != name[0]) continue;
        if (region[off - 1] != '\0') continue;
        if (memcmp(region + off, name, len) != 0) continue;
        if (region[off + len] != '\0') continue;
        if (found) return 0;
        found = base + off;
        off += len;
    }
    return found;
}

static uintptr_t vptr_from_typeinfo(const struct mach_header_64 *mh, intptr_t slide,
                                    uintptr_t text, size_t text_sz, uintptr_t ti) {
    uintptr_t found = 0;

    for (int s = 0; s < N_DATA_SEGS; s++) {
        uintptr_t base;
        size_t size;
        if (sb_find_segment(mh, slide, data_segs[s], &base, &size) != 0) continue;
        if (size < 3 * sizeof(uintptr_t)) continue;

        const uintptr_t *p = (const uintptr_t *)base;
        size_t n = size / sizeof(uintptr_t);
        for (size_t i = 1; i + 1 < n; i++) {
            if (p[i] != ti) continue;
            if (p[i - 1] != 0) continue;
            uintptr_t fn = p[i + 1];
            if (fn < text || fn >= text + text_sz) continue;
            if (fn & 3) continue;
            if (found) return 0;
            found = base + (i + 1) * sizeof(uintptr_t);
        }
    }
    return found;
}

uintptr_t sb_rtti_vptr(const struct mach_header_64 *mh, intptr_t slide,
                       uintptr_t text_base, size_t text_size,
                       const char *type_name) {
    if (!mh || !type_name || !*type_name || !text_base || !text_size) return 0;

    uintptr_t name = type_name_va(mh, slide, type_name);
    if (!name) {
        SB_WARN("rtti: no unique type name '%s'", type_name);
        return 0;
    }

    uintptr_t found = 0;

    for (int s = 0; s < N_DATA_SEGS; s++) {
        uintptr_t base;
        size_t size;
        if (sb_find_segment(mh, slide, data_segs[s], &base, &size) != 0) continue;
        if (size < 2 * sizeof(uintptr_t)) continue;

        const uintptr_t *p = (const uintptr_t *)base;
        size_t n = size / sizeof(uintptr_t);
        for (size_t i = 1; i < n; i++) {
            if (p[i] != name) continue;
            uintptr_t vptr = vptr_from_typeinfo(mh, slide, text_base, text_size,
                                                base + (i - 1) * sizeof(uintptr_t));
            if (!vptr) continue;
            if (found && found != vptr) {
                SB_WARN("rtti: '%s' reaches more than one vtable", type_name);
                return 0;
            }
            found = vptr;
        }
    }

    if (!found) SB_WARN("rtti: no vtable for type name '%s'", type_name);
    return found;
}
