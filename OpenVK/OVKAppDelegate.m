#import "OVKUI.h"
#import "OVKAPI.h"
@implementation OVKAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(showLogin) name:@"OVKLogout" object:nil];
    if ([[OVKAPI shared] restore]) [self showClient]; else [self showLogin];
    [self.window makeKeyAndVisible]; return YES;
}
- (void)showLogin {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[[OVKLoginController alloc] init]]; OVKStyleNavigation(nav);
    [self.window.rootViewController dismissViewControllerAnimated:NO completion:nil]; self.window.rootViewController = nav;
}
- (void)showClient {
    self.window.rootViewController = [[OVKRootController alloc] init];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end
