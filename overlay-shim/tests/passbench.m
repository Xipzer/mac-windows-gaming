#import <Metal/Metal.h>
#import <stdio.h>
#import <mach/mach_time.h>

#define BATCHES 200
#define PASSES  200

int main(void)
{
	id<MTLDevice> device = MTLCreateSystemDefaultDevice();
	id<MTLCommandQueue> queue = [device newCommandQueue];

	MTLTextureDescriptor *td = [MTLTextureDescriptor
	    texture2DDescriptorWithPixelFormat:MTLPixelFormatRGB10A2Unorm
	                                 width:64
	                                height:64
	                             mipmapped:NO];
	td.usage = MTLTextureUsageRenderTarget;
	id<MTLTexture> target = [device newTextureWithDescriptor:td];

	MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
	rp.colorAttachments[0].texture = target;
	rp.colorAttachments[0].loadAction = MTLLoadActionLoad;
	rp.colorAttachments[0].storeAction = MTLStoreActionStore;

	mach_timebase_info_data_t tb;
	mach_timebase_info(&tb);

	uint64_t start = mach_absolute_time();
	for (int b = 0; b < BATCHES; b++) {
		id<MTLCommandBuffer> cb = [queue commandBuffer];
		for (int i = 0; i < PASSES; i++) {
			id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:rp];
			[e endEncoding];
		}
		[cb commit];
	}
	uint64_t elapsed = mach_absolute_time() - start;

	double ns = (double)elapsed * tb.numer / tb.denom;
	printf("passbench: %d passes in %.2f ms = %.0f ns/pass\n", BATCHES * PASSES,
	       ns / 1e6, ns / (BATCHES * PASSES));
	return 0;
}
