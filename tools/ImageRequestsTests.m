#import <Foundation/Foundation.h>
#import "OVKImageRequests.h"
@interface TestImageTask : NSObject <OVKCancellable>
@property (assign, nonatomic) BOOL cancelled;
@end
@implementation TestImageTask
- (void)cancel { self.cancelled=YES; }
@end
static void Check(BOOL ok,const char *message) { if (!ok) { fprintf(stderr,"FAIL: %s\n",message); exit(1); } }
static void Pump(void) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]]; }
int main(void) { @autoreleasepool {
    OVKImageRequests *requests=[[OVKImageRequests alloc] init];
    __block unsigned starts=0,deliveries=0; __block OVKSharedImageCompletion pending=nil;
    TestImageTask *task=[[TestImageTask alloc] init];
    OVKSharedImageLoader loader=^id<OVKCancellable>(OVKSharedImageCompletion done) { ++starts; pending=[done copy]; return task; };
    OVKSharedImageCompletion receive=^(id image,NSError *error) { Check([NSThread isMainThread],"deliver on main"); Check([image isEqual:@"decoded"] && !error,"shared result preserved"); ++deliveries; };
    id<OVKCancellable> first=[requests subscribeKey:@"128:avatar" loader:loader completion:receive];
    [requests subscribeKey:@"128:avatar" loader:loader completion:receive];
    Check(starts==0,"subscribe returns before loader starts"); Pump(); Check(starts==1,"duplicate image needs one loader");
    [first cancel]; Pump(); Check(!task.cancelled,"one subscriber cannot cancel another");
    pending(@"decoded",nil); Pump(); Check(deliveries==1,"cancelled subscriber not delivered");
    TestImageTask *cancelTask=[[TestImageTask alloc] init]; __block OVKSharedImageCompletion late=nil;
    id<OVKCancellable> last=[requests subscribeKey:@"128:other" loader:^id<OVKCancellable>(OVKSharedImageCompletion done) { late=[done copy]; return cancelTask; } completion:receive];
    Pump(); [last cancel]; Pump(); Check(cancelTask.cancelled,"last cancellation stops underlying work");
    late(@"decoded",nil); Pump(); Check(deliveries==1,"late completion after cancellation ignored");
    __block unsigned failures=0;
    [requests subscribeKey:@"failed" loader:^id<OVKCancellable>(OVKSharedImageCompletion done) { done(nil,[NSError errorWithDomain:@"test" code:1 userInfo:nil]); return [[TestImageTask alloc] init]; } completion:^(id value,NSError *error) { Check(error!=nil,"failure passed to caller"); ++failures; }];
    Pump(); Pump(); Check(failures==1,"synchronous failure delivered asynchronously once");
    [requests subscribeKey:@"failed" loader:loader completion:receive]; Pump(); Check(starts==2,"failed requests can be retried"); pending(@"decoded",nil); Pump(); Check(deliveries==2,"retry succeeds");
    id<OVKCancellable> early=[requests subscribeKey:@"early" loader:loader completion:receive]; [early cancel]; Pump(); Check(starts==2,"cancel before subscription avoids network work");
    NSMutableArray *pendingSizes=[NSMutableArray array];
    OVKSharedImageLoader sized=^id<OVKCancellable>(OVKSharedImageCompletion done) { [pendingSizes addObject:[done copy]]; return [[TestImageTask alloc] init]; };
    [requests subscribeKey:@"128:same-image" loader:sized completion:receive]; [requests subscribeKey:@"512:same-image" loader:sized completion:receive];
    Pump(); Check(pendingSizes.count==2,"different decode sizes must not share a low-resolution result");
    for (id object in pendingSizes) { OVKSharedImageCompletion done=(OVKSharedImageCompletion)object; done(@"decoded",nil); } Pump(); Check(deliveries==4,"both resolutions delivered");
    puts("PASS: image request coalescing, subscriber cancellation, late results and retry");
} return 0; }
