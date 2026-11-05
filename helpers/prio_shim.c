#include <mach/mach.h>
#include <mach/thread_policy.h>
#include <pthread.h>
#include <pthread/qos.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DYLD_INTERPOSE(_replacement, _replacee) \
	__attribute__((used)) static struct { \
		const void *replacement; \
		const void *replacee; \
	} _interpose_##_replacee __attribute__((section("__DATA,__interpose"))) = { \
		(const void *)(unsigned long)&_replacement, \
		(const void *)(unsigned long)&_replacee \
	};

enum { mode_off, mode_mr, mode_floor };

static int prio_mode = mode_mr;
static int prio_floor = -26;
static int prio_qos;
static int prio_log;
static integer_t prio_latency;
static integer_t prio_throughput;

__attribute__((constructor))
static void prio_init(void) {
	const char *m = getenv("STEAMBRIDGE_PRIO_MODE");
	if (m && !strcmp(m, "off")) {
		prio_mode = mode_off;
	} else if (m && !strncmp(m, "floor", 5)) {
		prio_mode = mode_floor;
		prio_floor = atoi(m + 5);
	}
	const char *q = getenv("STEAMBRIDGE_PRIO_QOS");
	prio_qos = q && *q == '1';
	const char *lat = getenv("STEAMBRIDGE_PRIO_LATENCY");
	if (lat && !strcmp(lat, "0")) {
		prio_latency = LATENCY_QOS_TIER_0;
	} else if (lat && !strcmp(lat, "1")) {
		prio_latency = LATENCY_QOS_TIER_1;
	}
	const char *tp = getenv("STEAMBRIDGE_PRIO_THROUGHPUT");
	if (tp && !strcmp(tp, "0")) {
		prio_throughput = THROUGHPUT_QOS_TIER_0;
	}
	const char *l = getenv("STEAMBRIDGE_PRIO_LOG");
	prio_log = l && *l == '1';
	const char *s = getenv("STEAMBRIDGE_PRIO_SERVER_QOS");
	if (s && !strcmp(s, "ui")) {
		pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);
	} else if (s && !strcmp(s, "ui-init")) {
		pthread_set_qos_class_self_np(QOS_CLASS_USER_INITIATED, 0);
	}
	if (prio_log) {
		fprintf(stderr, "prio-shim: mode=%d floor=%d qos=%d latency=%#x throughput=%#x\n",
			prio_mode, prio_floor, prio_qos, prio_latency, prio_throughput);
	}
}

static integer_t lift_importance(integer_t imp) {
	switch (prio_mode) {
	case mode_mr:
		if (imp == -31) return -26;
		if (imp == -27) return -25;
		return imp;
	case mode_floor:
		return imp < prio_floor ? prio_floor : imp;
	default:
		return imp;
	}
}

static kern_return_t prio_thread_policy_set(thread_act_t thread,
	thread_policy_flavor_t flavor, thread_policy_t info,
	mach_msg_type_number_t count) {
	if (!info || (prio_mode == mode_off && !prio_latency && !prio_throughput)) {
		return thread_policy_set(thread, flavor, info, count);
	}
	integer_t v;
	switch (flavor) {
	case THREAD_PRECEDENCE_POLICY:
		if (prio_mode == mode_off || count < THREAD_PRECEDENCE_POLICY_COUNT) break;
		struct thread_precedence_policy prec = *(struct thread_precedence_policy *)info;
		v = prec.importance;
		prec.importance = lift_importance(v);
		if (prio_log) {
			fprintf(stderr, "prio-shim: port %u importance %d -> %d\n",
				thread, v, prec.importance);
		}
		return thread_policy_set(thread, flavor, (thread_policy_t)&prec, count);
	case THREAD_THROUGHPUT_QOS_POLICY:
		if (count < THREAD_THROUGHPUT_QOS_POLICY_COUNT) break;
		struct thread_throughput_qos_policy tp = *(struct thread_throughput_qos_policy *)info;
		v = tp.thread_throughput_qos_tier;
		if (prio_throughput) {
			tp.thread_throughput_qos_tier = prio_throughput;
		} else if (prio_qos && prio_mode != mode_off &&
			v >= THROUGHPUT_QOS_TIER_3 && v <= THROUGHPUT_QOS_TIER_5) {
			tp.thread_throughput_qos_tier = THROUGHPUT_QOS_TIER_1;
		} else {
			break;
		}
		if (prio_log) {
			fprintf(stderr, "prio-shim: port %u throughput %#x -> %#x\n",
				thread, v, tp.thread_throughput_qos_tier);
		}
		return thread_policy_set(thread, flavor, (thread_policy_t)&tp, count);
	case THREAD_LATENCY_QOS_POLICY:
		if (count < THREAD_LATENCY_QOS_POLICY_COUNT) break;
		struct thread_latency_qos_policy lp = *(struct thread_latency_qos_policy *)info;
		v = lp.thread_latency_qos_tier;
		if (prio_latency) {
			lp.thread_latency_qos_tier = prio_latency;
		} else if (prio_qos && prio_mode != mode_off &&
			v >= LATENCY_QOS_TIER_3 && v <= LATENCY_QOS_TIER_5) {
			lp.thread_latency_qos_tier = LATENCY_QOS_TIER_1;
		} else {
			break;
		}
		if (prio_log) {
			fprintf(stderr, "prio-shim: port %u latency %#x -> %#x\n",
				thread, v, lp.thread_latency_qos_tier);
		}
		return thread_policy_set(thread, flavor, (thread_policy_t)&lp, count);
	}
	return thread_policy_set(thread, flavor, info, count);
}

DYLD_INTERPOSE(prio_thread_policy_set, thread_policy_set)
