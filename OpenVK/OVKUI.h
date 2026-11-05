#import <UIKit/UIKit.h>
UIColor *OVKBlue(void);
void OVKAlert(NSString *title, NSString *message);
void OVKStyleNavigation(UINavigationController *navigation);
@interface OVKLoginController : UIViewController
@end
@interface OVKListController : UITableViewController
- (id)initWithMode:(NSString *)mode identifier:(NSNumber *)identifier title:(NSString *)title;
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
