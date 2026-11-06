#import "OVKLanguage.h"
#import "OVKUI.h"
#import "OVKAPI.h"
#import "OVKMusic.h"
#import "OVKMedia.h"
@implementation OVKAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(showLogin) name:@"OVKLogout" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(showClient) name:@"OVKAccountChanged" object:nil];
    if ([[OVKAPI shared] restore]) [self showClient]; else [self showLogin];
    [self.window makeKeyAndVisible]; [[UIApplication sharedApplication] beginReceivingRemoteControlEvents]; [self becomeFirstResponder]; return YES;
}
- (void)showLogin {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[[OVKLoginController alloc] init]]; OVKStyleNavigation(nav);
    [self.window.rootViewController dismissViewControllerAnimated:NO completion:nil]; self.window.rootViewController = nav;
}
- (void)showClient {
    self.window.rootViewController = [[OVKRootController alloc] init];
}
- (BOOL)canBecomeFirstResponder { return YES; }
- (void)remoteControlReceivedWithEvent:(UIEvent *)event { [OVKMedia handleRemoteControl:event]; }
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)source annotation:(id)annotation {
    if (!url.isFileURL) return NO;
    __block UIBackgroundTaskIdentifier importTask=UIBackgroundTaskInvalid;
    importTask=[application beginBackgroundTaskWithExpirationHandler:^{ if (importTask!=UIBackgroundTaskInvalid) { [application endBackgroundTask:importTask]; importTask=UIBackgroundTaskInvalid; } }];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), ^{
        NSError *error=nil; BOOL success=OVKImportAudioURL(url,&error);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (importTask!=UIBackgroundTaskInvalid) { [application endBackgroundTask:importTask]; importTask=UIBackgroundTaskInvalid; }
            if (!success) { OVKAlert(@"Не удалось добавить музыку",error.localizedDescription); return; }
            [[NSNotificationCenter defaultCenter] postNotificationName:@"OVKLocalMusicChanged" object:nil];
            UIViewController *root=self.window.rootViewController;
            void (^show)(void)=^{
                OVKMusicController *music=[[OVKMusicController alloc] init]; UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:music]; OVKStyleNavigation(nav);
                music.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:OVKL(@"Готово") style:UIBarButtonItemStyleDone target:self action:@selector(closeImportedMusic)];
                [root presentViewController:nav animated:YES completion:nil];
            };
            if (root.presentedViewController) [root dismissViewControllerAnimated:NO completion:show]; else show();
        });
    }); return YES;
}
- (void)closeImportedMusic { [self.window.rootViewController dismissViewControllerAnimated:YES completion:nil]; }
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end
