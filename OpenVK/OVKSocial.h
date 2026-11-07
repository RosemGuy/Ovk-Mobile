#import "OVKUI.h"
@interface OVKSocialController : UIViewController
- (id)initWithSection:(NSString *)section;
@end
@interface OVKGroupController : OVKListController
- (id)initWithGroup:(NSNumber *)groupID title:(NSString *)title;
@end
