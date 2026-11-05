#include "hooks.h"
#include "../util/log.h"

#include <spawn.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern int   DobbyHook(void *address, void *replace_call, void **origin_call);
extern void *DobbySymbolResolver(const char *image_name, const char *symbol_name);

typedef int (*fn_execve)(const char *path, char *const argv[], char *const envp[]);
typedef int (*fn_posix_spawn)(pid_t *pid, const char *path,
                             const posix_spawn_file_actions_t *fa,
                             const posix_spawnattr_t *attr,
                             char *const argv[], char *const envp[]);

static fn_execve      orig_execve;
static fn_posix_spawn orig_posix_spawn;
static fn_posix_spawn orig_posix_spawnp;

#define SB_INSERT_KEY     "DYLD_INSERT_LIBRARIES="
#define SB_INSERT_KEY_LEN (sizeof(SB_INSERT_KEY) - 1)

static int sb_target_keeps_insert(const char *path) {
    if (!path)
        return 1;
    const char *base = strrchr(path, '/');
    base = base ? base + 1 : path;
    return strcmp(base, "steam_osx") == 0
        || strcmp(base, "Steam Helper") == 0;
}

static char **sb_without_insert(char *const envp[]) {
    if (!envp)
        return NULL;

    int count = 0;
    int found = 0;
    for (int i = 0; envp[i]; i++) {
        if (strncmp(envp[i], SB_INSERT_KEY, SB_INSERT_KEY_LEN) == 0)
            found = 1;
        count++;
    }
    if (!found)
        return NULL;

    char **clean = malloc(sizeof(char *) * (size_t)(count + 1));
    if (!clean) {
        SB_WARN("[spawn] cannot allocate a stripped environment, insert passed through");
        return NULL;
    }

    int j = 0;
    for (int i = 0; envp[i]; i++) {
        if (strncmp(envp[i], SB_INSERT_KEY, SB_INSERT_KEY_LEN) != 0)
            clean[j++] = envp[i];
    }
    clean[j] = NULL;
    return clean;
}

static int sb_hook_execve(const char *path, char *const argv[], char *const envp[]) {
    if (sb_target_keeps_insert(path))
        return orig_execve(path, argv, envp);

    char **clean = sb_without_insert(envp);
    if (!clean)
        return orig_execve(path, argv, envp);

    SB_DBG("[spawn] execve '%s' without the insert", path);
    int rc = orig_execve(path, argv, (char *const *)clean);
    free(clean);
    return rc;
}

static int sb_spawn_without_insert(fn_posix_spawn orig, const char *api,
                                   pid_t *pid, const char *path,
                                   const posix_spawn_file_actions_t *fa,
                                   const posix_spawnattr_t *attr,
                                   char *const argv[], char *const envp[]) {
    if (sb_target_keeps_insert(path))
        return orig(pid, path, fa, attr, argv, envp);

    char **clean = sb_without_insert(envp);
    if (!clean)
        return orig(pid, path, fa, attr, argv, envp);

    SB_DBG("[spawn] %s '%s' without the insert", api, path);
    int rc = orig(pid, path, fa, attr, argv, (char *const *)clean);
    free(clean);
    return rc;
}

static int sb_hook_posix_spawn(pid_t *pid, const char *path,
                               const posix_spawn_file_actions_t *fa,
                               const posix_spawnattr_t *attr,
                               char *const argv[], char *const envp[]) {
    return sb_spawn_without_insert(orig_posix_spawn, "posix_spawn",
                                   pid, path, fa, attr, argv, envp);
}

static int sb_hook_posix_spawnp(pid_t *pid, const char *path,
                                const posix_spawn_file_actions_t *fa,
                                const posix_spawnattr_t *attr,
                                char *const argv[], char *const envp[]) {
    return sb_spawn_without_insert(orig_posix_spawnp, "posix_spawnp",
                                   pid, path, fa, attr, argv, envp);
}

static void sb_hook_symbol(const char *sym, void *repl, void **orig) {
    void *addr = DobbySymbolResolver("libsystem_kernel.dylib", sym);
    if (!addr)
        addr = DobbySymbolResolver(NULL, sym);
    if (!addr) {
        SB_WARN("[spawn] %s: unresolved, children keep the insert", sym);
        return;
    }

    int rc = DobbyHook(addr, repl, orig);
    if (rc == 0)
        SB_LOG("[spawn] %s: hooked @ %p", sym, addr);
    else
        SB_WARN("[spawn] %s: DobbyHook failed rc=%d, children keep the insert", sym, rc);
}

void sb_hooks_spawn_install(void) {
    if (sb_hooks_env_lists_label("STEAMBRIDGE_DISABLE", "spawn")) {
        SB_WARN("[spawn] DISABLED via STEAMBRIDGE_DISABLE, children keep the insert");
        return;
    }

    sb_hook_symbol("execve",       (void *)sb_hook_execve,       (void **)&orig_execve);
    sb_hook_symbol("posix_spawn",  (void *)sb_hook_posix_spawn,  (void **)&orig_posix_spawn);
    sb_hook_symbol("posix_spawnp", (void *)sb_hook_posix_spawnp, (void **)&orig_posix_spawnp);
}
