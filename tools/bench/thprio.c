#include <libproc.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/proc_info.h>

int main(int argc, char **argv) {
	if (argc < 2) { fprintf(stderr, "usage: thprio PID\n"); return 2; }
	int pid = atoi(argv[1]);
	uint64_t ids[4096];
	int n = proc_pidinfo(pid, PROC_PIDLISTTHREADS, 0, ids, sizeof ids);
	if (n <= 0) { perror("proc_pidinfo"); return 1; }
	n /= sizeof(uint64_t);
	printf("%-5s %-5s %-6s %10s  %s\n", "base", "cur", "policy", "cpu_s", "name");
	for (int i = 0; i < n; i++) {
		struct proc_threadinfo ti;
		if (proc_pidinfo(pid, PROC_PIDTHREADINFO, ids[i], &ti, sizeof ti) <= 0) continue;
		double cpu = (ti.pth_user_time + ti.pth_system_time) / 1e9;
		printf("%-5d %-5d %-6s %10.2f  %s\n", ti.pth_priority, ti.pth_curpri,
			ti.pth_policy == 1 ? "TS" : ti.pth_policy == 2 ? "RR" : ti.pth_policy == 4 ? "FIFO" : "?",
			cpu, ti.pth_name);
	}
	return 0;
}
