#include "../hooks/hook_spawn.c"

#include <stdio.h>

int   sb_log_level = 0;
FILE *sb_log_file  = NULL;

int DobbyHook(void *address, void *replace_call, void **origin_call) {
    (void)address; (void)replace_call; (void)origin_call;
    return -1;
}

void *DobbySymbolResolver(const char *image_name, const char *symbol_name) {
    (void)image_name; (void)symbol_name;
    return NULL;
}

int sb_hooks_env_lists_label(const char *var, const char *label) {
    (void)var; (void)label;
    return 0;
}

static int failures;

static void check(int ok, const char *what) {
    if (!ok) {
        printf("FAIL %s\n", what);
        failures++;
    }
}

static void keeps(const char *path, int want, const char *what) {
    check(sb_target_keeps_insert(path) == want, what);
}

static void survives(char *const envp[], const char *const want[], const char *what) {
    char **got = sb_without_insert(envp);
    if (!want) {
        check(got == NULL, what);
        free(got);
        return;
    }
    if (!got) {
        check(0, what);
        return;
    }
    int i = 0;
    for (; want[i] && got[i]; i++) {
        if (strcmp(want[i], got[i]) != 0)
            break;
    }
    check(want[i] == NULL && got[i] == NULL, what);
    free(got);
}

int main(void) {
    keeps("/Applications/Steam.app/Contents/MacOS/steam_osx", 1, "an absolute steam_osx keeps it");
    keeps("/Users/x/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/steam_osx",
          1, "the AppBundle copy of steam_osx keeps it");
    keeps("steam_osx", 1, "a bare steam_osx keeps it");
    keeps(NULL, 1, "an unnamed target keeps it");

    keeps("/bin/sh", 0, "sh loses it");
    keeps("/bin/bash", 0, "bash loses it");
    keeps("/usr/sbin/lsof", 0, "lsof loses it");
    keeps("/bin/launchctl", 0, "launchctl loses it");
    keeps("/Applications/Steam.app/Contents/MacOS/Steam Helper", 1,
          "the helper keeps it for the webpatch interpose");
    keeps("/Applications/Steam.app/Contents/MacOS/steam_osx_helper", 0,
          "a name starting with steam_osx loses it");

    survives(NULL, NULL, "a null environment is left alone");

    char *plain[] = { (char *)"PATH=/bin", (char *)"HOME=/Users/x", NULL };
    survives(plain, NULL, "an environment without the insert is not copied");

    char *with[] = { (char *)"PATH=/bin",
                     (char *)"DYLD_INSERT_LIBRARIES=/Applications/Steam.app/Contents/MacOS/steambridge.dylib",
                     (char *)"HOME=/Users/x", NULL };
    const char *without[] = { "PATH=/bin", "HOME=/Users/x", NULL };
    survives(with, without, "the insert is taken out and the rest kept in order");

    char *only[] = { (char *)"DYLD_INSERT_LIBRARIES=/x.dylib", NULL };
    const char *empty[] = { NULL };
    survives(only, empty, "an environment of nothing but the insert comes back empty");

    char *shim[] = { (char *)"STEAM_DYLD_INSERT_LIBRARIES=/overlay.dylib", NULL };
    survives(shim, NULL, "the overlay's own variable is not the insert");

    char *longer[] = { (char *)"DYLD_INSERT_LIBRARIES_EXTRA=/x.dylib", NULL };
    survives(longer, NULL, "a longer name sharing the prefix is not the insert");

    char *twice[] = { (char *)"DYLD_INSERT_LIBRARIES=/a.dylib",
                      (char *)"PATH=/bin",
                      (char *)"DYLD_INSERT_LIBRARIES=/b.dylib", NULL };
    const char *once[] = { "PATH=/bin", NULL };
    survives(twice, once, "every copy of the insert is taken out");

    if (failures) {
        printf("==> spawn env: %d check(s) failed\n", failures);
        return 1;
    }
    printf("==> spawn env: steam_osx and Steam Helper keep the insert, every other child loses it\n");
    return 0;
}
