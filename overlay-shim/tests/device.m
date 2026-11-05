#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "check.h"

typedef id (*new_queue_fn)(id, SEL);


static int absent_selectors(Class target, const char *stage, const char *const *selectors)
{
	int gone = 0;

	for (int i = 0; selectors[i] != NULL; i++) {
		if (class_getInstanceMethod(target, sel_registerName(selectors[i])) != NULL)
			continue;

		printf("FAIL: %s class %s carries no %s\n", stage, class_getName(target),
		       selectors[i]);
		gone++;
	}

	if (gone == 0)
		printf("%-14s %s\n", stage, class_getName(target));

	return gone;
}

int main(void)
{
	static const char *const device_selectors[] = {
		"newRenderPipelineStateWithDescriptor:error:", "newCommandQueue",
		"newCommandQueueWithMaxCommandBufferCount:", "newMTL4CommandQueue", NULL
	};
	static const char *const queue_selectors[] = {
		"commandBuffer", "commandBufferWithUnretainedReferences", "device", NULL
	};
	static const char *const buffer_selectors[] = { "renderCommandEncoderWithDescriptor:", NULL };
	static const char *const encoder_selectors[] = { "setRenderPipelineState:", "endEncoding", NULL };
	static const char *const mtl4_selectors[] = { "signalDrawable:", "signalEvent:value:", NULL };
	static const char *const layer_selectors[] = { "setPixelFormat:", "setColorspace:", "setDevice:", NULL };

	id<MTLDevice> device = MTLCreateSystemDefaultDevice();
	SKIP_IF(device == nil, "no Metal device on this machine");

	SEL new_mtl4 = sel_registerName("newMTL4CommandQueue");
	SKIP_IF(![device respondsToSelector:new_mtl4], "the Metal 4 interfaces are not on this system");

	id<MTLCommandQueue> queue = [device newCommandQueue];
	CHECK(queue != nil, "newCommandQueue came back nil");

	id<MTLCommandBuffer> buffer = [queue commandBuffer];
	CHECK(buffer != nil, "commandBuffer came back nil");

	MTLTextureDescriptor *td = [MTLTextureDescriptor
	    texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
	                                 width:16
	                                height:16
	                             mipmapped:NO];
	td.usage = MTLTextureUsageRenderTarget;
	id<MTLTexture> target = [device newTextureWithDescriptor:td];
	CHECK(target != nil, "newTextureWithDescriptor: came back nil");

	MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
	rp.colorAttachments[0].texture = target;
	id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:rp];
	CHECK(encoder != nil, "renderCommandEncoderWithDescriptor: came back nil");

	id mtl4 = ((new_queue_fn)objc_msgSend)(device, new_mtl4);
	CHECK(mtl4 != nil, "newMTL4CommandQueue came back nil");

	int gone = 0;
	gone += absent_selectors(object_getClass(device), "device", device_selectors);
	gone += absent_selectors(object_getClass(queue), "mtl3 queue", queue_selectors);
	gone += absent_selectors(object_getClass(buffer), "buffer", buffer_selectors);
	gone += absent_selectors(object_getClass(encoder), "encoder", encoder_selectors);
	gone += absent_selectors(object_getClass(mtl4), "mtl4 queue", mtl4_selectors);
	gone += absent_selectors([CAMetalLayer class], "layer", layer_selectors);

	[encoder endEncoding];

	Class again3 = object_getClass([device newCommandQueue]);
	CHECK(again3 == object_getClass(queue), "two mtl3 queues, classes %s and %s",
	      class_getName(object_getClass(queue)), class_getName(again3));

	Class again4 = object_getClass(((new_queue_fn)objc_msgSend)(device, new_mtl4));
	CHECK(again4 == object_getClass(mtl4), "two mtl4 queues, classes %s and %s",
	      class_getName(object_getClass(mtl4)), class_getName(again4));

	CHECK(object_getClass(mtl4) != object_getClass(queue),
	      "one class %s backs both queue kinds, so hooking one hooks the other",
	      class_getName(object_getClass(queue)));

	return gone == 0 ? 0 : 1;
}
