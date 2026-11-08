#ifndef OVKDebug_h
#define OVKDebug_h

#import <Foundation/Foundation.h>

// Log only diagnostic metadata. Request and response contents may contain credentials.
#if DEBUG
#define OVKDebugLog(format, ...) NSLog(@"[Ovk-Mobile] " format, ##__VA_ARGS__)
#else
#define OVKDebugLog(...) ((void)0)
#endif

#endif
