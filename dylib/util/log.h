#ifndef STEAMBRIDGE_UTIL_LOG_H
#define STEAMBRIDGE_UTIL_LOG_H

#include <stdio.h>
#include <time.h>

extern int sb_log_level;
extern FILE *sb_log_file;
void sb_log_init(void);

enum {
    SB_LVL_ERR = 0,
    SB_LVL_WARN,
    SB_LVL_INFO,
    SB_LVL_DBG,
};

#define SB_LOG_PREFIX "[steambridge]"

#define SB_EMIT(level, tag, fmt, ...) do { \
    if (sb_log_level >= (level)) { \
        time_t _now = time(NULL); \
        struct tm _cal; localtime_r(&_now, &_cal); \
        char _ts[24]; \
        strftime(_ts, sizeof(_ts), "%Y-%m-%d %H:%M:%S", &_cal); \
        FILE *_sinks[2] = { stderr, sb_log_file }; \
        for (int _s = 0; _s < 2; _s++) { \
            if (_sinks[_s]) \
                fprintf(_sinks[_s], "%s " SB_LOG_PREFIX " %s " fmt "\n", \
                        _ts, tag, ##__VA_ARGS__); \
        } \
    } \
} while(0)

#define SB_ERR(fmt, ...)  SB_EMIT(SB_LVL_ERR,  "error", fmt, ##__VA_ARGS__)
#define SB_WARN(fmt, ...) SB_EMIT(SB_LVL_WARN, "warn",  fmt, ##__VA_ARGS__)
#define SB_LOG(fmt, ...)  SB_EMIT(SB_LVL_INFO, "info",  fmt, ##__VA_ARGS__)
#define SB_DBG(fmt, ...)  SB_EMIT(SB_LVL_DBG,  "debug", fmt, ##__VA_ARGS__)

int sb_log_first_hit(const void *anchor, unsigned long tag);

#define SB_LOG_FIRST_KEY(key, fmt, ...) do { \
    static const char sb_here = 0; \
    if (sb_log_level >= SB_LVL_DBG || sb_log_first_hit(&sb_here, (unsigned long)(key))) \
        SB_LOG(fmt, ##__VA_ARGS__); \
} while(0)

#define SB_LOG_FIRST(fmt, ...) SB_LOG_FIRST_KEY(0, fmt, ##__VA_ARGS__)

#endif
