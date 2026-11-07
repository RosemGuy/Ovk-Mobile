#import "OVKUI.h"
#import "OVKAPI.h"
#import "OVKPerformance.h"
#import "OVKMessagesLayout.h"
@interface OVKMessagesController ()
@property (strong, nonatomic) UINavigationController *dialogsNavigation;
@property (strong, nonatomic) UINavigationController *chatNavigation;
@property (strong, nonatomic) UIView *divider;
@property (strong, nonatomic) UILabel *emptyLabel;
@property (strong, nonatomic) NSMutableDictionary *chats;
@property (strong, nonatomic) NSMutableArray *recentChats;
@property (copy, nonatomic) NSString *selectedPeer;
@end
@implementation OVKMessagesController
- (void)viewDidLoad {
    [super viewDidLoad]; OVKConfigureEdges(self); self.chats=[NSMutableDictionary dictionary]; self.recentChats=[NSMutableArray array];
    OVKListController *dialogs=[[OVKListController alloc] initWithMode:@"dialogs" identifier:[OVKAPI shared].userID title:OVKL(@"Сообщения")]; __weak OVKMessagesController *weakSelf=self;
    dialogs.dialogSelected=^(NSNumber *peer,NSString *title) { [weakSelf showChat:peer title:title]; };
    self.dialogsNavigation=[[OVKNavigationController alloc] initWithRootViewController:dialogs];
    UIViewController *empty=[[UIViewController alloc] init]; empty.title=OVKL(@"Сообщения");
    self.chatNavigation=[[OVKNavigationController alloc] initWithRootViewController:empty];
    for (UINavigationController *navigation in @[self.dialogsNavigation,self.chatNavigation]) { [self addChildViewController:navigation]; [self.view addSubview:navigation.view]; [navigation didMoveToParentViewController:self]; }
    self.emptyLabel=[[UILabel alloc] initWithFrame:empty.view.bounds]; self.emptyLabel.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; self.emptyLabel.backgroundColor=[UIColor clearColor]; self.emptyLabel.textAlignment=NSTextAlignmentCenter; self.emptyLabel.font=[UIFont systemFontOfSize:17]; self.emptyLabel.numberOfLines=3; [empty.view addSubview:self.emptyLabel];
    self.divider=[[UIView alloc] init]; [self.view addSubview:self.divider];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTheme:) name:@"OVKThemeChanged" object:nil]; [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateLanguage:) name:@"OVKLanguageChanged" object:nil];
    [self updateTheme:nil]; [self updateLanguage:nil];
}
- (void)updateLanguage:(NSNotification *)note { self.title=OVKL(@"Сообщения"); ((UIViewController *)[self.dialogsNavigation.viewControllers objectAtIndex:0]).title=self.title; self.emptyLabel.text=OVKL(@"Выберите диалог слева"); if (!self.selectedPeer) ((UIViewController *)[self.chatNavigation.viewControllers objectAtIndex:0]).title=self.title; }
- (void)updateTheme:(NSNotification *)note { self.view.backgroundColor=OVKThemeBackground(); self.emptyLabel.superview.backgroundColor=OVKThemeBackground(); self.emptyLabel.textColor=OVKThemeSecondary(); self.divider.backgroundColor=OVKDarkTheme() ? [UIColor colorWithWhite:.3 alpha:1] : [UIColor colorWithWhite:.65 alpha:1]; OVKStyleNavigation(self.dialogsNavigation); OVKStyleNavigation(self.chatNavigation); }
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; OVKMessagesLayout layout=OVKMessagesColumns(self.view.bounds.size.width); CGFloat height=self.view.bounds.size.height; self.dialogsNavigation.view.frame=CGRectMake(0,0,layout.listWidth,height); self.chatNavigation.view.frame=CGRectMake(layout.chatX,0,layout.chatWidth,height); self.divider.frame=CGRectMake(layout.listWidth,0,1,height); }
- (void)showChat:(NSNumber *)peer title:(NSString *)title {
    NSString *key=OVKString(peer); if ([key isEqualToString:self.selectedPeer]) { [self.chatNavigation popToRootViewControllerAnimated:YES]; return; }
    [self.chatNavigation.view endEditing:YES]; OVKListController *chat=self.chats[key]; if (!chat) { chat=[[OVKListController alloc] initWithMode:@"chat" identifier:peer title:title]; self.chats[key]=chat; }
    self.selectedPeer=key; [self.recentChats removeObject:key]; [self.recentChats addObject:key];
    [self.chatNavigation setViewControllers:@[chat] animated:NO]; [self trimChats:NO];
}
- (void)trimChats:(BOOL)memoryWarning { NSUInteger limit=memoryWarning ? 1 : (OVKLowMemoryDevice() ? 2 : 4); for (NSString *key in [self.recentChats copy]) { if (self.chats.count<=limit) break; OVKListController *chat=self.chats[key]; if ([key isEqualToString:self.selectedPeer] || [chat hasPendingMessage] || chat.messageDraft.length) continue; [self.chats removeObjectForKey:key]; [self.recentChats removeObject:key]; } }
- (void)didReceiveMemoryWarning { [super didReceiveMemoryWarning]; [self trimChats:YES]; }
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [self.chatNavigation.view endEditing:YES]; }
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end
