#include "hooks.h"
#include "../util/log.h"
#include "../util/peicon.h"

#include <dlfcn.h>
#include <limits.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#define SB_ICON_MAX_SIDE 4096

typedef void *(*sb_icon_render_fn)(const char *const *path_slot, int size);

static sb_icon_render_fn g_render_orig;

typedef struct { double x, y; } sb_pt_t;
typedef struct { double w, h; } sb_sz_t;
typedef struct { sb_pt_t origin; sb_sz_t size; } sb_rect_t;

typedef void *(*msg_0_t)(void *, void *);
typedef void *(*msg_id_t)(void *, void *, void *);
typedef void *(*msg_bytes_t)(void *, void *, void *, unsigned long, signed char);
typedef void  (*msg_long_t)(void *, void *, long);
typedef void  (*msg_size_t)(void *, void *, sb_sz_t);
typedef void  (*msg_draw_t)(void *, void *, sb_rect_t, sb_rect_t, unsigned long, double);
typedef void *(*msg_rep_t)(void *, void *, unsigned char **, long, long, long, long,
                           signed char, signed char, void *, long, long);

static void *(*sb_get_class)(const char *);
static void *(*sb_sel)(const char *);
static void  *g_msg_send;
static void  (*sb_release)(void *);
static void *(*sb_pool_push)(void);
static void  (*sb_pool_pop)(void *);
static void  *g_device_rgb;

static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static char           *g_cache_path;
static void           *g_cache_ico;
static size_t          g_cache_len;
static long            g_cache_mtime;
static long long       g_cache_size;

static pthread_once_t g_runtime_once = PTHREAD_ONCE_INIT;
static int            g_runtime_ok;

static void runtime_init(void) {
    sb_get_class = (void *(*)(const char *))dlsym(RTLD_DEFAULT, "objc_getClass");
    sb_sel       = (void *(*)(const char *))dlsym(RTLD_DEFAULT, "sel_registerName");
    g_msg_send   = dlsym(RTLD_DEFAULT, "objc_msgSend");
    sb_release   = (void (*)(void *))dlsym(RTLD_DEFAULT, "objc_release");
    sb_pool_push = (void *(*)(void))dlsym(RTLD_DEFAULT, "objc_autoreleasePoolPush");
    sb_pool_pop  = (void (*)(void *))dlsym(RTLD_DEFAULT, "objc_autoreleasePoolPop");

    void **rgb = (void **)dlsym(RTLD_DEFAULT, "NSDeviceRGBColorSpace");
    if (rgb) g_device_rgb = *rgb;

    g_runtime_ok = sb_get_class && sb_sel && g_msg_send && sb_release &&
                   sb_pool_push && sb_pool_pop && g_device_rgb;
    if (!g_runtime_ok) SB_WARN("icon: AppKit runtime unavailable, leaving icons to Steam");
}

static int runtime_ready(void) {
    pthread_once(&g_runtime_once, runtime_init);
    return g_runtime_ok;
}

static void *ico_copy_for_path(const char *path, size_t *out_len) {
    struct stat st;
    char unquoted[PATH_MAX];

    if (!path || !*path) return NULL;

    size_t len = strlen(path);
    if (len >= 2 && path[0] == '"' && path[len - 1] == '"') {
        if (len - 2 >= sizeof(unquoted)) return NULL;
        memcpy(unquoted, path + 1, len - 2);
        unquoted[len - 2] = '\0';
        path = unquoted;
    }

    if (stat(path, &st) != 0 || !S_ISREG(st.st_mode)) return NULL;

    pthread_mutex_lock(&g_lock);

    int hit = g_cache_ico && g_cache_path &&
              strcmp(g_cache_path, path) == 0 &&
              g_cache_mtime == (long)st.st_mtime &&
              g_cache_size == (long long)st.st_size;

    if (!hit) {
        pthread_mutex_unlock(&g_lock);

        size_t len = 0;
        void  *ico = sb_pe_icon_ico(path, &len);
        if (!ico) return NULL;
        char *dup = strdup(path);
        SB_LOG("icon: read an icon out of '%s'", path);

        pthread_mutex_lock(&g_lock);
        free(g_cache_ico);
        free(g_cache_path);
        g_cache_ico   = ico;
        g_cache_len   = len;
        g_cache_path  = dup;
        g_cache_mtime = (long)st.st_mtime;
        g_cache_size  = (long long)st.st_size;
    }

    void *copy = NULL;
    if (g_cache_len) {
        copy = malloc(g_cache_len);
        if (copy) {
            memcpy(copy, g_cache_ico, g_cache_len);
            *out_len = g_cache_len;
        }
    }
    pthread_mutex_unlock(&g_lock);
    return copy;
}

static void *render(void *bytes, size_t len, int side) {
    void *pool = sb_pool_push();

    void *data = ((msg_bytes_t)g_msg_send)(
        sb_get_class("NSData"),
        sb_sel("dataWithBytesNoCopy:length:freeWhenDone:"),
        bytes, (unsigned long)len, 1);

    if (!data) {
        free(bytes);
        sb_pool_pop(pool);
        return NULL;
    }

    void *img = ((msg_id_t)g_msg_send)(
        ((msg_0_t)g_msg_send)(sb_get_class("NSImage"), sb_sel("alloc")),
        sb_sel("initWithData:"), data);
    if (!img) {
        sb_pool_pop(pool);
        return NULL;
    }

    void *rep = ((msg_rep_t)g_msg_send)(
        ((msg_0_t)g_msg_send)(sb_get_class("NSBitmapImageRep"), sb_sel("alloc")),
        sb_sel("initWithBitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:"
               "samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bytesPerRow:"
               "bitsPerPixel:"),
        NULL, side, side, 8, 4, 1, 0, g_device_rgb, 4L * side, 32);

    if (!rep) {
        sb_release(img);
        sb_pool_pop(pool);
        return NULL;
    }

    void *gc  = sb_get_class("NSGraphicsContext");
    void *ctx = ((msg_id_t)g_msg_send)(gc, sb_sel("graphicsContextWithBitmapImageRep:"), rep);
    if (!ctx) {
        sb_release(img);
        sb_release(rep);
        sb_pool_pop(pool);
        return NULL;
    }

    ((msg_long_t)g_msg_send)(ctx, sb_sel("setImageInterpolation:"), 2);
    ((msg_0_t)g_msg_send)(gc, sb_sel("saveGraphicsState"));
    ((msg_id_t)g_msg_send)(gc, sb_sel("setCurrentContext:"), ctx);

    sb_sz_t   size = { (double)side, (double)side };
    sb_rect_t dst  = { { 0.0, 0.0 }, { (double)side, (double)side } };
    sb_rect_t src  = { { 0.0, 0.0 }, { 0.0, 0.0 } };

    ((msg_size_t)g_msg_send)(img, sb_sel("setSize:"), size);
    ((msg_draw_t)g_msg_send)(img, sb_sel("drawInRect:fromRect:operation:fraction:"),
                             dst, src, 1, 1.0);

    ((msg_0_t)g_msg_send)(gc, sb_sel("restoreGraphicsState"));

    sb_release(img);
    sb_pool_pop(pool);
    return rep;
}

static void *sb_icon_render(const char *const *path_slot, int side) {
    const char *path = path_slot ? *path_slot : NULL;

    if (side <= 0 || side > SB_ICON_MAX_SIDE || !path || !runtime_ready())
        return g_render_orig ? g_render_orig(path_slot, side) : NULL;

    size_t len   = 0;
    void  *bytes = ico_copy_for_path(path, &len);
    if (!bytes)
        return g_render_orig ? g_render_orig(path_slot, side) : NULL;

    void *rep = render(bytes, len, side);
    if (!rep)
        return g_render_orig ? g_render_orig(path_slot, side) : NULL;

    return rep;
}

static sb_patch_entry_t g_hooks[] = {
    {
        .label            = "shortcut-icon",
        .signature        = "steamui::ShortcutIconRender",
        .entry            = (void *)sb_icon_render,
        .trampoline       = (void **)&g_render_orig,
        .tolerate_missing = 1,
        .mode             = SB_PATCH_REPLACE,
    },
};

int sb_hooks_icon_count(void) {
    return (int)(sizeof(g_hooks) / sizeof(g_hooks[0]));
}

sb_patch_entry_t *sb_hooks_icon_defs(void) {
    return g_hooks;
}
