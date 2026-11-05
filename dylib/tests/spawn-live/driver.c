#include <spawn.h>
#include <sys/wait.h>
extern char **environ;
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    char *a[] = { argv[1], NULL };
    pid_t pid;
    int st = 0;
    if (posix_spawn(&pid, argv[1], NULL, NULL, a, environ) != 0) return 111;
    waitpid(pid, &st, 0);
    return 0;
}
