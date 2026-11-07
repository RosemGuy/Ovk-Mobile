#import "OVKPerformance.h"
static unsigned long long OVKPhysicalMemory(void) {
    static unsigned long long memory; static dispatch_once_t once;
    dispatch_once(&once, ^{ memory=[[NSProcessInfo processInfo] physicalMemory]; }); return memory;
}
BOOL OVKLowMemoryDevice(void) { return OVKPhysicalMemory()<=512ULL*1024*1024; }
// A7 devices such as iPhone 5s have 1 GiB shared with the OS. Keep a
// smaller working set even though they use the native 64-bit executable.
BOOL OVKConstrainedMemoryDevice(void) { return OVKPhysicalMemory()<=1024ULL*1024*1024; }
NSUInteger OVKPreviewPixelLimit(void) { return OVKLowMemoryDevice() ? 384 : (OVKConstrainedMemoryDevice() ? 480 : 512); }
NSUInteger OVKFullPhotoPixelLimit(void) { return OVKConstrainedMemoryDevice() ? 1024 : 2048; }
NSUInteger OVKPageSize(void) { return OVKLowMemoryDevice() ? 10 : (OVKConstrainedMemoryDevice() ? 15 : 20); }
NSUInteger OVKImageCacheByteLimit(void) { return (OVKLowMemoryDevice() ? 4 : (OVKConstrainedMemoryDevice() ? 8 : 16))*1024*1024; }
NSUInteger OVKImageCacheCountLimit(void) { return OVKLowMemoryDevice() ? 32 : (OVKConstrainedMemoryDevice() ? 48 : 80); }
