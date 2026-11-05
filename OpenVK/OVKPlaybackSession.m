#import "OVKPlaybackSession.h"
@interface OVKPlaybackSession ()
@property (copy, nonatomic) NSError *(^activation)(void);
@property (copy, nonatomic) void (^deactivation)(void);
@end
@implementation OVKPlaybackSession
- (id)initWithActivation:(NSError *(^)(void))activate deactivation:(void (^)(void))deactivate {
    self=[super init]; if (self) { _queue=dispatch_queue_create("org.openvk.classic.audio-session",DISPATCH_QUEUE_SERIAL); self.activation=activate; self.deactivation=deactivate; } return self;
}
- (void)activateForOwner:(NSString *)owner completion:(void (^)(NSError *))completion {
    NSString *token=[owner copy];
    dispatch_async(_queue, ^{
        NSError *error=self.activation(); if (!error) self->_owner=token;
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
    });
}
- (void)deactivateForOwner:(NSString *)owner completion:(void (^)(void))completion {
    NSString *token=[owner copy];
    dispatch_async(_queue, ^{
        if (token && [self->_owner isEqualToString:token]) { self.deactivation(); self->_owner=nil; }
        if (completion) dispatch_async(dispatch_get_main_queue(),completion);
    });
}
@end
