#import "OVKImageRequests.h"
@interface OVKImageSubscriber : NSObject <OVKCancellable>
@property (assign, atomic) BOOL cancelled;
@property (copy, nonatomic) OVKSharedImageCompletion completion;
@property (copy, nonatomic) void (^cancelBlock)(void);
@end
@implementation OVKImageSubscriber
- (void)cancel {
    self.cancelled=YES;
    dispatch_async(dispatch_get_main_queue(), ^{ void (^cancel)(void)=self.cancelBlock; self.cancelBlock=nil; self.completion=nil; if (cancel) cancel(); });
}
@end
@interface OVKImageFlight : NSObject
@property (strong, nonatomic) NSMutableArray *subscribers;
@property (strong, nonatomic) id<OVKCancellable> task;
@end
@implementation OVKImageFlight
@end
@interface OVKImageRequests ()
@property (strong, nonatomic) NSMutableDictionary *flights;
@end
@implementation OVKImageRequests
- (id)init { self=[super init]; if (self) self.flights=[NSMutableDictionary dictionary]; return self; }
- (id<OVKCancellable>)subscribeKey:(NSString *)key loader:(OVKSharedImageLoader)loader completion:(OVKSharedImageCompletion)completion {
    OVKImageSubscriber *subscriber=[[OVKImageSubscriber alloc] init]; subscriber.completion=completion;
    // All flight/subscriber mutations are serialized on main. Even a cached or
    // synchronously completed loader delivers after the subscription is returned.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (subscriber.cancelled) return;
        OVKImageFlight *flight=self.flights[key]; BOOL start=flight==nil;
        if (!flight) { flight=[[OVKImageFlight alloc] init]; flight.subscribers=[NSMutableArray array]; self.flights[key]=flight; }
        [flight.subscribers addObject:subscriber];
        __weak OVKImageRequests *weakSelf=self; __weak OVKImageFlight *weakFlight=flight; __weak OVKImageSubscriber *weakSubscriber=subscriber;
        subscriber.cancelBlock=^{
            OVKImageRequests *owner=weakSelf; OVKImageFlight *active=weakFlight; OVKImageSubscriber *cancelled=weakSubscriber;
            if (!owner || !active) return; if (cancelled) [active.subscribers removeObjectIdenticalTo:cancelled];
            if (!active.subscribers.count && owner.flights[key]==active) { [owner.flights removeObjectForKey:key]; id<OVKCancellable> task=active.task; active.task=nil; [task cancel]; }
        };
        if (!start) return;
        flight.task=loader(^(id image,NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                OVKImageRequests *owner=weakSelf; if (!owner || owner.flights[key]!=flight) return;
                [owner.flights removeObjectForKey:key]; flight.task=nil;
                NSArray *subscribers=[flight.subscribers copy]; [flight.subscribers removeAllObjects];
                for (OVKImageSubscriber *listener in subscribers) { listener.cancelBlock=nil; OVKSharedImageCompletion deliver=listener.completion; listener.completion=nil; if (!listener.cancelled && deliver) deliver(image,error); }
            });
        });
    }); return subscriber;
}
@end
