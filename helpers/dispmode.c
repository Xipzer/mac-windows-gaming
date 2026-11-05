#include <ApplicationServices/ApplicationServices.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void print_mode(CGDisplayModeRef m) {
	printf("%zu %zu %zu %zu %.0f\n",
		CGDisplayModeGetWidth(m), CGDisplayModeGetHeight(m),
		CGDisplayModeGetPixelWidth(m), CGDisplayModeGetPixelHeight(m),
		CGDisplayModeGetRefreshRate(m));
}

static CFArrayRef all_modes(CGDirectDisplayID d) {
	const void *k[] = { kCGDisplayShowDuplicateLowResolutionModes };
	const void *v[] = { kCFBooleanTrue };
	CFDictionaryRef opt = CFDictionaryCreate(NULL, k, v, 1,
		&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFArrayRef modes = CGDisplayCopyAllDisplayModes(d, opt);
	CFRelease(opt);
	return modes;
}

int main(int argc, char **argv) {
	CGDirectDisplayID d = CGMainDisplayID();
	CGDisplayModeRef cur = CGDisplayCopyDisplayMode(d);
	if (argc < 2 || !strcmp(argv[1], "get")) {
		print_mode(cur);
		return 0;
	}
	CFArrayRef modes = all_modes(d);
	if (!strcmp(argv[1], "list")) {
		for (CFIndex i = 0; i < CFArrayGetCount(modes); i++)
			print_mode((CGDisplayModeRef)CFArrayGetValueAtIndex(modes, i));
		return 0;
	}
	if (strcmp(argv[1], "set") || argc < 4) {
		fprintf(stderr, "usage: dispmode get | list | set PTW PTH [HZ]\n");
		return 2;
	}
	size_t w = strtoul(argv[2], NULL, 10), h = strtoul(argv[3], NULL, 10);
	double hz = argc > 4 ? atof(argv[4]) : CGDisplayModeGetRefreshRate(cur);
	CGDisplayModeRef best = NULL;
	for (CFIndex i = 0; i < CFArrayGetCount(modes); i++) {
		CGDisplayModeRef m = (CGDisplayModeRef)CFArrayGetValueAtIndex(modes, i);
		if (CGDisplayModeGetWidth(m) != w || CGDisplayModeGetHeight(m) != h) continue;
		if (CGDisplayModeGetPixelWidth(m) != 2 * w || CGDisplayModeGetPixelHeight(m) != 2 * h) continue;
		if (!CGDisplayModeIsUsableForDesktopGUI(m)) continue;
		double r = CGDisplayModeGetRefreshRate(m);
		if (!best || (r == hz && CGDisplayModeGetRefreshRate(best) != hz)) best = m;
	}
	if (!best) {
		fprintf(stderr, "dispmode: no %zux%zu HiDPI mode\n", w, h);
		return 1;
	}
	print_mode(cur);
	if (CGDisplayModeGetWidth(cur) == w && CGDisplayModeGetHeight(cur) == h &&
		CGDisplayModeGetPixelWidth(cur) == 2 * w &&
		CGDisplayModeGetRefreshRate(cur) == CGDisplayModeGetRefreshRate(best))
		return 0;
	CGDisplayConfigRef cfg;
	if (CGBeginDisplayConfiguration(&cfg) != kCGErrorSuccess) return 1;
	CGConfigureDisplayWithDisplayMode(cfg, d, best, NULL);
	CGError err = CGCompleteDisplayConfiguration(cfg, kCGConfigureForSession);
	if (err != kCGErrorSuccess) {
		fprintf(stderr, "dispmode: CGCompleteDisplayConfiguration failed %d\n", err);
		return 1;
	}
	return 0;
}
