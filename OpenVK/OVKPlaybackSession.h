#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
// Serializes the blocking platform API and keeps release tied to its requesting player.
@interface OVKPlaybackSession : NSObject {
    dispatch_queue_t _queue;
    NSString *_owner;
}
- (id)initWithActivation:(NSError *(^)(void))activate deactivation:(void (^)(void))deactivate;
- (void)activateForOwner:(NSString *)owner completion:(void (^)(NSError *))completion;
- (void)deactivateForOwner:(NSString *)owner completion:(void (^)(void))completion;
@end
