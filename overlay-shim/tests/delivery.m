#import <objc/runtime.h>

#import <dlfcn.h>
#import <stdlib.h>

#import "check.h"

static int delivery_by_dlopen(void)
{
	const char *path = getenv("STEAMBRIDGE_OVERLAY_SHIM");

	SKIP_IF(path == NULL, "STEAMBRIDGE_OVERLAY_SHIM names the shim to load");

	void *shim = dlopen(path, RTLD_NOW | RTLD_LOCAL);
	CHECK(shim != NULL, "%s does not load: %s", path, dlerror());

	void (*install)(void) = (void (*)(void))dlsym(shim, "sb_overlay_shim_install");
	CHECK(install != NULL, "%s exports no sb_overlay_shim_install", path);

	install();
	printf("%-14s %s\n", "delivery", "dlopen, dlsym, install");

	return 0;
}


static int gl_present_handle(void)
{
	void *gl = dlopen("/System/Library/Frameworks/OpenGL.framework/OpenGL",
	                  RTLD_LAZY | RTLD_LOCAL);

	CHECK(gl != NULL, "OpenGL does not load: %s", dlerror());

	void *appkit = dlopen("/System/Library/Frameworks/AppKit.framework/AppKit",
	                      RTLD_LAZY | RTLD_LOCAL);

	CHECK(appkit != NULL, "AppKit does not load: %s", dlerror());

	Class context = objc_getClass("NSOpenGLContext");

	CHECK(context != NULL, "AppKit carries no NSOpenGLContext");
	CHECK(class_getInstanceMethod(context, sel_registerName("flushBuffer")) != NULL,
	      "NSOpenGLContext carries no flushBuffer to stand in for");
	CHECK(class_getInstanceMethod(context, sel_registerName("CGLContextObj")) != NULL,
	      "NSOpenGLContext carries no CGLContextObj");
	CHECK(dlsym(RTLD_DEFAULT, "CGLFlushDrawable") != NULL,
	      "CGLFlushDrawable has no address for the interpose table to match");

	printf("%-14s %s\n", "gl present", "NSOpenGLContext flushBuffer");

	return 0;
}

int main(void)
{
	int rc = delivery_by_dlopen();

	if (rc != 0)
		return rc;

	return gl_present_handle();
}
