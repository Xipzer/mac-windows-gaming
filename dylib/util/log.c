#include "log.h"
#include "file.h"
#include <stdlib.h>
#include <stdint.h>
#include <sys/stat.h>

int sb_log_level = SB_LVL_INFO;
FILE *sb_log_file = NULL;

#define SB_LOG_MAX_BYTES (16 * 1024 * 1024)

#define SB_SEEN_SLOTS 8192

struct sb_seen_slot {
    const void   *anchor;
    unsigned long tag;
    unsigned char filled;
};

static struct sb_seen_slot sb_seen[SB_SEEN_SLOTS];
static int sb_seen_overflow;

static unsigned long sb_seen_fold(const void *anchor, unsigned long tag) {
    unsigned long acc = 1469598103934665603UL;
    unsigned long bits = (unsigned long)(uintptr_t)anchor ^ (tag << 1);
    for (int b = 0; b < (int)sizeof(bits); b++) {
        acc ^= (bits & 0xFF);
        acc *= 1099511628211UL;
        bits >>= 8;
    }
    return acc;
}

int sb_log_first_hit(const void *anchor, unsigned long tag) {
    unsigned long start = sb_seen_fold(anchor, tag) % SB_SEEN_SLOTS;
    for (unsigned long step = 0; step < SB_SEEN_SLOTS; step++) {
        struct sb_seen_slot *slot = &sb_seen[(start + step) % SB_SEEN_SLOTS];
        if (slot->filled) {
            if (slot->anchor == anchor && slot->tag == tag)
                return 0;
            continue;
        }
        slot->anchor = anchor;
        slot->tag    = tag;
        slot->filled = 1;
        return 1;
    }
    if (!sb_seen_overflow) {
        sb_seen_overflow = 1;
        SB_ERR("log dedupe table exhausted at %d entries; repeat lines now dropped",
               SB_SEEN_SLOTS);
    }
    return 0;
}

void sb_log_init(void) {
    const char *want = getenv("STEAMBRIDGE_LOG_LEVEL");
    if (want && want[0]) {
        int parsed = atoi(want);
        if (parsed >= SB_LVL_ERR && parsed <= SB_LVL_DBG)
            sb_log_level = parsed;
    }

    if (sb_log_file)
        return;

    const char *home = sb_home_dir();
    if (!home)
        home = "/tmp";

    char folder[512];
    char logpath[512];
    sb_support_path(folder, sizeof(folder), home, NULL);
    mkdir(folder, 0755);
    snprintf(logpath, sizeof(logpath), "%s/steambridge.log", folder);

    struct stat info;
    int oversize = (stat(logpath, &info) == 0 && info.st_size > SB_LOG_MAX_BYTES);
    sb_log_file = fopen(logpath, oversize ? "w" : "a");
    if (sb_log_file)
        setlinebuf(sb_log_file);
}
