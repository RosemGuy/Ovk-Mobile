#import <UIKit/UIKit.h>
#import "OVKLanguage.h"
#import "OVKTheme.h"
UIColor *OVKBlue(void);
void OVKAlert(NSString *title, NSString *message);
void OVKConfigureEdges(UIViewController *controller);
void OVKStyleNavigation(UINavigationController *navigation);
@interface OVKLoginController : UIViewController
@end
@interface OVKListController : UIViewController
- (id)initWithMode:(NSString *)mode identifier:(NSNumber *)identifier title:(NSString *)title;
@property (copy, nonatomic) void (^dialogSelected)(NSNumber *peer,NSString *title);
@property (copy, nonatomic) NSString *messageDraft;
@property (copy, nonatomic) void (^draftChanged)(NSString *text);
- (BOOL)hasPendingMessage;
- (void)setWallHeaderView:(UIView *)header;
- (CGFloat)wallContentWidth;
- (id)initWithPostObject:(NSDictionary *)post profiles:(NSArray *)profiles groups:(NSArray *)groups;
@end
@interface OVKAppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
- (void)showClient;
@end
@interface OVKRootController : UIViewController
- (void)toggleMenu;
@end
@interface OVKInstancesController : UITableViewController
- (id)initWithSelection:(void (^)(NSString *site, NSString *api))selection;
+ (void)rememberSite:(NSString *)site api:(NSString *)api;
@end

NSArray *OVKMenuOrder(void);
NSString *OVKMenuTitle(NSString *mode);
@interface OVKAccountsController : UITableViewController
@end
@interface OVKMenuOrderController : UITableViewController
@end

@interface OVKAboutController : UIViewController
@end

@interface OVKMessagesController : UIViewController
@end

@interface OVKNavigationController : UINavigationController
@end
