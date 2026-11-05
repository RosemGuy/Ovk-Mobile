#import <Foundation/Foundation.h>
#import "OVKPlaybackSession.h"
static void Expect(BOOL ok,const char *message) { if (!ok) { fprintf(stderr,"FAIL: %s\n",message); exit(1); } }
int main(void) {
    @autoreleasepool {
        __block NSInteger activations=0,deactivations=0; __block BOOL done=NO;
        dispatch_semaphore_t gate=dispatch_semaphore_create(0);
        OVKPlaybackSession *session=[[OVKPlaybackSession alloc] initWithActivation:^NSError *{
            Expect(![NSThread isMainThread],"Activation must not block main thread");
            if (++activations==1) dispatch_semaphore_wait(gate,DISPATCH_TIME_FOREVER);
            return nil;
        } deactivation:^{ Expect(![NSThread isMainThread],"Deactivation must not block main thread"); ++deactivations; }];
        [session activateForOwner:@"old" completion:^(NSError *error) { Expect([NSThread isMainThread] && !error,"Main-thread activation completion"); }];
        // These calls must return even while the first platform activation is blocked.
        [session activateForOwner:@"new" completion:nil];
        [session deactivateForOwner:@"old" completion:^{
            Expect(deactivations==0,"Stale release must not disable the new player");
            [session deactivateForOwner:@"new" completion:^{ Expect(activations==2 && deactivations==1,"Current owner releases once"); done=YES; }];
        }];
        dispatch_semaphore_signal(gate);
        NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
        while (!done && [deadline timeIntervalSinceNow]>0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        Expect(done,"Session queue must complete");
        __block BOOL failedDone=NO;
        OVKPlaybackSession *failed=[[OVKPlaybackSession alloc] initWithActivation:^NSError *{ return [NSError errorWithDomain:@"Test" code:1 userInfo:nil]; } deactivation:^{ Expect(NO,"Failed activation does not acquire ownership"); }];
        [failed activateForOwner:@"failed" completion:^(NSError *error) { Expect(error.code==1,"Activation error propagated"); [failed deactivateForOwner:@"failed" completion:^{ failedDone=YES; }]; }];
        deadline=[NSDate dateWithTimeIntervalSinceNow:5];
        while (!failedDone && [deadline timeIntervalSinceNow]>0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        Expect(failedDone,"Failure completion"); puts("PASS: nonblocking session operations, ownership, main-thread callbacks, errors");
    } return 0;
}
