#include "../../feats/webpatch.c"

#include <stdio.h>
#include <string.h>

int sb_log_level = 0;
FILE *sb_log_file = NULL;

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "component") == 0) {
        fputs(SB_CX_OPTIONS_COMPONENT, stdout);
        return 0;
    }
    if (argc == 2 && strcmp(argv[1], "statement") == 0) {
        fputs(SB_CX_OPTIONS_STATEMENT, stdout);
        return 0;
    }
    fputs("usage: emit component|statement\n", stderr);
    return 2;
}
