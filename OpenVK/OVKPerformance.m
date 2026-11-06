#import "OVKPerformance.h"
BOOL OVKLowMemoryDevice(void) {
    static BOOL low; static dispatch_once_t once; dispatch_once(&once, ^{ low=[[NSProcessInfo processInfo] physicalMemory]<=512ULL*1024*1024; }); return low;
}
NSUInteger OVKPreviewPixelLimit(void) { return OVKLowMemoryDevice() ? 384 : 512; }
NSUInteger OVKFullPhotoPixelLimit(void) { return OVKLowMemoryDevice() ? 1024 : 2048; }
NSUInteger OVKPageSize(void) { return OVKLowMemoryDevice() ? 10 : 20; }
