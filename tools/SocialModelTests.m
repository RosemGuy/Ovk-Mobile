#import <Foundation/Foundation.h>
#import "OVKSocialModel.h"
static void Check(BOOL ok,const char *message) { if (!ok) { fprintf(stderr,"FAIL: %s\n",message); exit(1); } }
int main(void) { @autoreleasepool {
    Check(OVKSocialItems(@{@"items":@[@1,[NSNull null],@{@"id":@2}]}).count==1,"Malformed list entries skipped");
    Check(OVKSocialItems(@[@{@"id":@1}]).count==1,"Legacy array response accepted");
    Check([OVKNotificationActor(@{@"feedback":@{@"items":@[@{@"from_id":@7}]}}) isEqual:@7],"Actor in grouped feedback");
    Check([OVKNotificationActor(@{@"feedback":@{@"from_id":@(-3)}}) isEqual:@(-3)],"Community actor remains negative");
    Check(!OVKNotificationActor(@{@"feedback":[NSNull null]}),"Missing actor safe");
    Check(!OVKNotificationActor(@{@"from_id":@"12broken"}),"Malformed actor is not a real user ID");
    NSDictionary *post=OVKNotificationPost(@{@"type":@"like_post",@"parent":@{@"owner_id":@(-3),@"id":@99}});
    Check([post[@"owner_id"] isEqual:@(-3)] && [post[@"id"] isEqual:@99],"Notification targets group wall post");
    Check(!OVKNotificationPost(@{@"type":@"like_photo",@"parent":@{@"owner_id":@1,@"id":@99}}),"Photo ID never mistaken for post");
    Check(!OVKNotificationPost(@{@"type":@"like_comment",@"parent":@{@"owner_id":@1,@"id":@99}}),"Comment ID never mistaken for post");
    Check([OVKNotificationPost(@{@"type":@"reply_comment",@"parent":@{@"owner_id":@1,@"id":@99,@"post_id":@17}})[@"id"] isEqual:@17],"Explicit parent post ID takes precedence");
    Check(OVKNotificationSummary(@{@"type":@"future_event"}).length>0,"Unknown notification has readable fallback");
    puts("PASS: social responses, notification actors and precise post navigation");
} return 0; }
