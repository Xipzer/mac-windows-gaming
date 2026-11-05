#import <Metal/Metal.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <unistd.h>

#import "check.h"

typedef id (*new_fn)(id, SEL);
typedef id (*dev_fn)(id, SEL);
typedef void (*sig_fn)(id, SEL, id, uint64_t);

int main(void)
{
	alarm(30);

	id<MTLDevice> device = MTLCreateSystemDefaultDevice();
	SKIP_IF(device == nil, "no Metal device on this machine");

	SEL new_mtl4 = sel_registerName("newMTL4CommandQueue");
	SKIP_IF(![device respondsToSelector:new_mtl4], "the Metal 4 interfaces are not on this system");

	id<MTLCommandQueue> mtl3 = [device newCommandQueue];
	id mtl4 = ((new_fn)objc_msgSend)(device, new_mtl4);
	id<MTLEvent> event = [device newEvent];
	CHECK(mtl3 != nil, "newCommandQueue came back nil");
	CHECK(mtl4 != nil, "newMTL4CommandQueue came back nil");
	CHECK(event != nil, "newEvent came back nil");

	id d3 = ((dev_fn)objc_msgSend)(mtl3, sel_registerName("device"));
	id d4 = ((dev_fn)objc_msgSend)(mtl4, sel_registerName("device"));
	CHECK(d3 == (id)device, "the mtl3 queue reports device %p, not %p", (void *)d3, (void *)device);
	CHECK(d4 == (id)device, "the mtl4 queue reports device %p, not %p", (void *)d4, (void *)device);

	((sig_fn)objc_msgSend)(mtl4, sel_registerName("signalEvent:value:"), event, 1);

	id<MTLCommandBuffer> buffer = [mtl3 commandBuffer];
	[buffer encodeWaitForEvent:event value:1];
	[buffer commit];
	[buffer waitUntilCompleted];

	CHECK([buffer status] == MTLCommandBufferStatusCompleted,
	      "the mtl3 buffer ended at status %ld waiting on an mtl4 signal",
	      (long)[buffer status]);
	CHECK([buffer error] == nil, "the mtl3 buffer failed: %s",
	      [[[buffer error] localizedDescription] UTF8String]);

	printf("an mtl4 signal released an mtl3 buffer on %s\n",
	       class_getName(object_getClass(device)));
	return 0;
}
