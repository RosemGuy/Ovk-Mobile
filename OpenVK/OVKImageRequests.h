#import "OVKAPI.h"
typedef void (^OVKSharedImageCompletion)(id image, NSError *error);
typedef id<OVKCancellable> (^OVKSharedImageLoader)(OVKSharedImageCompletion completion);
@interface OVKImageRequests : NSObject
- (id<OVKCancellable>)subscribeKey:(NSString *)key loader:(OVKSharedImageLoader)loader completion:(OVKSharedImageCompletion)completion;
@end
