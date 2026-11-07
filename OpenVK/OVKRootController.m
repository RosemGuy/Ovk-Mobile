#import "OVKSetup.h"
#import "OVKSocial.h"
#import "OVKPerformance.h"
#import "OVKLanguage.h"
#import "OVKUI.h"
#import "OVKAPI.h"
#import "OVKMedia.h"
#import "OVKMusic.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>
static UIImage *OVKMenuGlyph(void) {
    static UIImage *image; static dispatch_once_t once; dispatch_once(&once, ^{
        UIImage *source=[UIImage imageNamed:@"Menu"]; UIGraphicsBeginImageContextWithOptions(source.size,NO,source.scale); [source drawAtPoint:CGPointZero]; [[UIColor whiteColor] setFill]; UIRectFillUsingBlendMode((CGRect){CGPointZero,source.size},kCGBlendModeSourceIn); image=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
    }); return image;
}
@interface OVKSidebarCell : UITableViewCell
@property (assign, nonatomic) BOOL compact;
@end
@implementation OVKSidebarCell
- (void)layoutSubviews { [super layoutSubviews]; CGFloat scale=[[UIScreen mainScreen] scale],x=self.compact ? (self.bounds.size.width-31)/2 : 10.5,y=(self.bounds.size.height-31)/2; self.imageView.contentMode=UIViewContentModeScaleAspectFit; self.imageView.frame=CGRectMake(round(x*scale)/scale,round(y*scale)/scale,31,31); self.textLabel.frame=CGRectMake(50,0,MAX(0,self.bounds.size.width-58),self.bounds.size.height); }
@end
@interface OVKAppearanceController : UITableViewController
@end
@implementation OVKAppearanceController
- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section { OVKThemeSection(view); }
- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section { OVKThemeSection(view); }
- (id)init { self=[super initWithStyle:UITableViewStyleGrouped]; if (self) self.title=OVKL(@"Оформление"); return self; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section==2 ? OVKThemeColors().count : 2; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return section==0 ? OVKL(@"Тема") : (section==1 ? OVKL(@"Текст записей") : OVKL(@"Цвет")); }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; OVKThemeTable(self.tableView); OVKStyleNavigation(self.navigationController); [self.tableView reloadData]; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path { UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil]; BOOL selected;
    if (path.section==0) { cell.textLabel.text=path.row ? OVKL(@"Тёмная") : OVKL(@"Светлая"); selected=OVKDarkTheme()==(path.row==1); }
    else if (path.section==2) { NSString *color=OVKThemeColors()[path.row]; NSDictionary *names=@{@"blue":OVKL(@"Синий"),@"purple":OVKL(@"Фиолетовый"),@"red":OVKL(@"Красный"),@"green":OVKL(@"Зелёный"),@"orange":OVKL(@"Оранжевый"),@"pink":OVKL(@"Розовый")}; cell.textLabel.text=names[color]; selected=[OVKThemeColor() isEqualToString:color]; }
    else { cell.textLabel.text=path.row ? OVKL(@"Крупный") : OVKL(@"Обычный"); cell.textLabel.font=[UIFont systemFontOfSize:path.row ? 17 : 14]; selected=[[NSUserDefaults standardUserDefaults] boolForKey:@"OVKLargeFeedText"]==(path.row==1); }
    cell.accessoryType=selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone; OVKThemeCell(cell); return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path { if (path.section==0) { OVKSetDarkTheme(path.row==1); OVKThemeTable(tableView); } else if (path.section==2) { OVKSetThemeColor(OVKThemeColors()[path.row]); } else { [[NSUserDefaults standardUserDefaults] setBool:path.row==1 forKey:@"OVKLargeFeedText"]; [[NSNotificationCenter defaultCenter] postNotificationName:@"OVKAppearanceChanged" object:nil]; } [tableView reloadData]; }
@end
@interface OVKLanguageController : UITableViewController
@end
@implementation OVKLanguageController
- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section { OVKThemeSection(view); }
- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section { OVKThemeSection(view); }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; OVKThemeTable(self.tableView); OVKStyleNavigation(self.navigationController); [self.tableView reloadData]; }
- (id)init { self=[super initWithStyle:UITableViewStyleGrouped]; if (self) self.title=OVKL(@"Язык"); return self; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 2; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path { UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil]; cell.textLabel.text=path.row==0 ? @"Русский" : @"English"; cell.accessoryType=(path.row==1)==OVKLanguageIsEnglish() ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone; OVKThemeCell(cell); return cell; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path { [tableView deselectRowAtIndexPath:path animated:YES]; OVKSetLanguage(path.row==1 ? @"en" : @"ru"); self.title=OVKL(@"Язык"); [self.tableView reloadData]; }
@end
@interface OVKSettingsController : UITableViewController <UIAlertViewDelegate>
@end
@implementation OVKSettingsController
- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section { OVKThemeSection(view); }
- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section { OVKThemeSection(view); }
- (id)init { self = [super initWithStyle:UITableViewStyleGrouped]; if (self) self.title = OVKL(@"Настройки"); return self; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 1 ? 6 : (section==0 ? 2 : 1); }
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path { return path.section == 0 ? 66 : 50; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @[OVKL(@"Аккаунт"),OVKL(@"Приложение"),@""][section]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == 0 ? [NSString stringWithFormat:@"%@\n%@",OVKL(@"Управляйте сохранёнными аккаунтами разных инстансов в разделе «Аккаунты»."),[OVKAPI shared].protectedSessionStore ? OVKL(@"Сеансы: защищённое хранилище приложения") : @"Keychain"] : (section == 2 ? OVKL(@"Выход удаляет токен с устройства.") : nil);
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if (path.section==0 && path.row==1) { cell.textLabel.text=OVKL(@"Аккаунты"); cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; }
    else if (path.section == 0) { cell.textLabel.text = OVKL(@"Инстанс"); cell.detailTextLabel.numberOfLines = 2; cell.detailTextLabel.text = [OVKAPI shared].demo ? OVKL(@"Демонстрация без аккаунта") : [NSString stringWithFormat:@"%@\nAPI: %@",[OVKAPI shared].siteServer ?: [OVKAPI shared].server,[OVKAPI shared].server]; }
    else if (path.section == 1) {
        cell.textLabel.text=@[@"Ovk-Mobile alpha",OVKL(@"Оформление"),OVKL(@"Настройка клиента"),OVKL(@"Язык"),OVKL(@"Очистить кэш изображений"),OVKL(@"Порядок меню")][path.row];
        cell.detailTextLabel.text=@[OVKL(@"Версия 1.0"),OVKL(@"Тема, цвет и размер текста"),OVKL(@"Язык, тема и цвет"),OVKLanguageIsEnglish() ? @"English" : @"Русский",OVKL(@"Освободить память от загруженных изображений"),OVKL(@"Перетащите пункты в нужном порядке")][path.row];
        if (path.row==0 || path.row==1 || path.row==3 || path.row==5) cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
        if (path.row==2) { cell.imageView.image=[UIImage imageNamed:@"Settings"]; cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; }
    }
    else { cell.textLabel.text = OVKL(@"Выйти из аккаунта"); cell.textLabel.textColor = [UIColor colorWithRed:.65 green:.18 blue:.18 alpha:1]; }
    OVKThemeCell(cell); return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section==1 && path.row==0) [self.navigationController pushViewController:[[OVKAboutController alloc] init] animated:YES];
    if (path.section==0 && path.row==1) [self.navigationController pushViewController:[[OVKAccountsController alloc] initWithStyle:UITableViewStyleGrouped] animated:YES];
    if (path.section==1 && path.row==5) [self.navigationController pushViewController:[[OVKMenuOrderController alloc] initWithStyle:UITableViewStyleGrouped] animated:YES];
    if (path.section==1 && path.row==1) [self.navigationController pushViewController:[[OVKAppearanceController alloc] init] animated:YES];
    if (path.section==1 && path.row==4) { [OVKMedia clearImageCache]; OVKAlert(OVKL(@"Кэш очищен"),OVKL(@"Кэш изображений в памяти очищен. Открытые фотографии останутся на экране.")); }
    if (path.section==1 && path.row==3) [self.navigationController pushViewController:[[OVKLanguageController alloc] init] animated:YES];
    if (path.section==1 && path.row==2) [self.navigationController pushViewController:[[OVKSetupController alloc] init] animated:YES];
    if (path.section == 2) [[[UIAlertView alloc] initWithTitle:OVKL(@"Выйти?") message:OVKL(@"Сохранённый токен будет удалён с устройства.") delegate:self cancelButtonTitle:OVKL(@"Отмена") otherButtonTitles:OVKL(@"Выйти"),nil] show];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; self.title=OVKL(@"Настройки"); OVKThemeTable(self.tableView); [self.tableView reloadData]; }
- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index { if (index == 1) [[OVKAPI shared] logout]; }
@end
@interface OVKRootController () <UITableViewDataSource,UITableViewDelegate>
@property (strong, nonatomic) NSArray *menuModesCache;
@property (strong, nonatomic) UITableView *menu;
@property (strong, nonatomic) NSMutableDictionary *sections;
@property (strong, nonatomic) UINavigationController *active;
@property (strong, nonatomic) UIButton *cover;
@property (strong, nonatomic) UILabel *nameLabel;
@property (strong, nonatomic) UILabel *statusLabel;
@property (strong, nonatomic) OVKRemoteImageView *profileImage;
@property (copy, nonatomic) NSString *selected;
@property (assign, nonatomic) BOOL opened;
@end
@implementation OVKRootController
- (CGFloat)menuWidth { return UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad ? ([self.selected isEqualToString:@"dialogs"] ? 64 : 240) : MIN(280,self.view.bounds.size.width-55); }
- (void)viewDidLoad {
    [super viewDidLoad]; self.sections = [NSMutableDictionary dictionary]; self.view.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"SidebarTexture"]]; self.view.clipsToBounds = YES;
    OVKConfigureEdges(self);
    self.menu = [[UITableView alloc] initWithFrame:CGRectMake(0,0,[self menuWidth],self.view.bounds.size.height) style:UITableViewStylePlain]; self.menu.autoresizingMask = UIViewAutoresizingFlexibleHeight; self.menu.backgroundColor = self.view.backgroundColor; self.menu.separatorColor = [UIColor colorWithWhite:0 alpha:.25]; self.menu.dataSource = self; self.menu.delegate = self; self.menu.rowHeight = 45; self.menu.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero]; [self.view addSubview:self.menu];
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0,0,[self menuWidth],86)];
    OVKRemoteImageView *avatar = [[OVKRemoteImageView alloc] initWithImage:[UIImage imageNamed:@"Avatar"]]; avatar.frame = CGRectMake(15,20,45,45); [header addSubview:avatar]; self.profileImage = avatar; avatar.contentMode = UIViewContentModeScaleAspectFill; avatar.clipsToBounds = YES;
    self.nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(73,19,[self menuWidth]-85,25)]; self.nameLabel.backgroundColor = [UIColor clearColor]; self.nameLabel.textColor = [UIColor whiteColor]; self.nameLabel.font = [UIFont boldSystemFontOfSize:17]; self.nameLabel.text = OVKL(@"Моя страница"); [header addSubview:self.nameLabel];
    UILabel *instance = [[UILabel alloc] initWithFrame:CGRectMake(73,46,[self menuWidth]-85,19)]; instance.backgroundColor = [UIColor clearColor]; instance.textColor = [UIColor colorWithWhite:.6 alpha:1]; instance.font = [UIFont systemFontOfSize:12]; instance.text = [OVKAPI shared].demo ? OVKL(@"Демонстрация") : @""; instance.numberOfLines=2; instance.frame=CGRectMake(73,44,[self menuWidth]-85,32); self.statusLabel=instance; [header addSubview:instance];
    UIButton *profile = [UIButton buttonWithType:UIButtonTypeCustom]; profile.frame = header.bounds; [profile addTarget:self action:@selector(profile) forControlEvents:UIControlEventTouchUpInside]; [header addSubview:profile]; header.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"MenuHeader"]]; self.menu.tableHeaderView = header;
    UISwipeGestureRecognizer *left = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(closeMenu)]; left.direction = UISwipeGestureRecognizerDirectionLeft; [self.menu addGestureRecognizer:left];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:@"OVKThemeChanged" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(experimentalChanged:) name:@"OVKExperimentalChanged" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(languageChanged:) name:@"OVKLanguageChanged" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(menuOrderChanged:) name:@"OVKMenuOrderChanged" object:nil];
    [self showSection:@"news" title:OVKL(@"Новости")];
    NSString *session = [[OVKAPI shared].token copy]; BOOL demo = [OVKAPI shared].demo;
    [[OVKAPI shared] call:@"users.get" parameters:@{@"fields":@"photo_100,status"} completion:^(id result,NSError *error) {
        if (demo != [OVKAPI shared].demo || (!demo && ![session isEqualToString:[OVKAPI shared].token])) return;
        if (!error && OVKArray(result).count) { NSDictionary *user = OVKDictionary(result[0]); self.nameLabel.text = [NSString stringWithFormat:@"%@ %@",OVKString(user[@"first_name"]),OVKString(user[@"last_name"])];
            [self.profileImage load:OVKString(user[@"photo_100"])]; self.statusLabel.text=OVKString(user[@"status"]); }

    }];
}
- (void)themeChanged:(NSNotification *)note {
    [self menuOrderChanged:nil];
    for (NSString *mode in self.sections) { UINavigationController *nav=self.sections[mode]; OVKStyleNavigation(nav); UIViewController *root=[nav.viewControllers objectAtIndex:0]; UIButton *button=(UIButton *)root.navigationItem.leftBarButtonItem.customView; if ([button isKindOfClass:[UIButton class]]) { OVKStyleAssetButton(button,@"NavButton"); [button setBackgroundImage:OVKThemeStretch(@"NavButtonPressed") forState:UIControlStateHighlighted]; } }
}
- (void)languageChanged:(NSNotification *)note {
    [self.menu reloadData];
    // Keep navigation stacks and the current player alive when changing language.
    for (NSString *mode in self.sections) { UINavigationController *nav=self.sections[mode]; UIViewController *page=[nav.viewControllers objectAtIndex:0]; page.title=[self menuTitle:mode]; }
}
- (void)menuOrderChanged:(NSNotification *)note { self.menuModesCache=nil; [self.menu reloadData]; NSUInteger index=[[self menuModes] indexOfObject:self.selected]; if (index!=NSNotFound) [self.menu selectRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:0] animated:NO scrollPosition:UITableViewScrollPositionNone]; }
- (NSArray *)menuModes { if (self.menuModesCache) return self.menuModesCache; NSMutableArray *modes=[OVKMenuOrder() mutableCopy]; if (!OVKExperimentalVideo()) [modes removeObject:@"video"]; self.menuModesCache=[modes copy]; return self.menuModesCache; }
- (NSString *)menuTitle:(NSString *)mode { return OVKMenuTitle(mode); }
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; BOOL pad=UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad; CGFloat side=pad ? [self menuWidth] : 0; self.menu.frame=CGRectMake(0,0,[self menuWidth],self.view.bounds.size.height); BOOL compact=pad && [self.selected isEqualToString:@"dialogs"]; self.nameLabel.hidden=compact; self.statusLabel.hidden=compact; self.profileImage.frame=CGRectMake(compact ? 9.5 : 15,20,45,45); CGAffineTransform transform=self.active.view.transform; self.active.view.transform=CGAffineTransformIdentity; self.active.view.frame=CGRectMake(side,0,self.view.bounds.size.width-side,self.view.bounds.size.height); self.active.view.transform=pad ? CGAffineTransformIdentity : transform; if (pad) { self.active.view.transform=CGAffineTransformIdentity; [self.cover removeFromSuperview]; self.cover=nil; self.opened=NO; } }
- (void)experimentalChanged:(NSNotification *)note { self.menuModesCache=nil; [self.menu reloadData]; if ([self.selected isEqualToString:@"video"] && !OVKExperimentalVideo()) [self showSection:@"audio" title:OVKL(@"Музыка")]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [self menuModes].count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    OVKSidebarCell *cell=(OVKSidebarCell *)[tableView dequeueReusableCellWithIdentifier:@"sidebar"];
    if (!cell) { cell=[[OVKSidebarCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"sidebar"]; cell.backgroundView=[[UIImageView alloc] init]; cell.selectedBackgroundView=[[UIImageView alloc] init]; }
    NSString *mode=[self menuModes][path.row];
    NSString *icon=@{@"notifications":@"Answers",@"groups":@"Groups",@"friends":@"Friends",@"photo":@"PhotoMedia",@"dialogs":@"Messages",@"news":@"News",@"profile":@"Profile",@"audio":@"AudioMedia",@"video":@"VideoMedia",@"archive":@"News",@"settings":@"Settings"}[mode];
    cell.compact=UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad && [self.selected isEqualToString:@"dialogs"]; cell.textLabel.hidden=cell.compact; cell.accessibilityLabel=[self menuTitle:mode];
    cell.textLabel.text=[self menuTitle:mode]; cell.textLabel.font=[UIFont boldSystemFontOfSize:17]; cell.textLabel.textColor=[UIColor colorWithWhite:.83 alpha:1]; cell.textLabel.backgroundColor=[UIColor clearColor]; cell.textLabel.shadowColor=[UIColor blackColor]; cell.textLabel.shadowOffset=CGSizeMake(0,-1);
    cell.imageView.image=[UIImage imageNamed:icon]; ((UIImageView *)cell.backgroundView).image=[UIImage imageNamed:@"MenuRow"]; ((UIImageView *)cell.selectedBackgroundView).image=OVKThemeChrome(@"MenuSelected"); cell.textLabel.highlightedTextColor=[UIColor whiteColor]; return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    NSString *mode=[self menuModes][path.row];
    [self showSection:mode title:[self menuTitle:mode]];
}
- (void)profile { [self showSection:@"profile" title:OVKL(@"Моя страница")]; }
- (void)showSection:(NSString *)mode title:(NSString *)title {
    [self closeMenu];
    UINavigationController *nav = self.sections[mode];
    if (!nav) {
        UIViewController *page;
        if ([mode isEqualToString:@"settings"]) page = [[OVKSettingsController alloc] init];
        else if ([mode isEqualToString:@"dialogs"] && UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad) page=[[OVKMessagesController alloc] init];
        else if ([mode isEqualToString:@"audio"]) page=[[OVKMusicController alloc] init];
        else if ([@[@"photo",@"video"] containsObject:mode]) page = [[OVKLibraryController alloc] initWithKind:mode identifier:[OVKAPI shared].userID title:title];
        else if ([mode isEqualToString:@"groups"] || [mode isEqualToString:@"notifications"]) page=[[OVKSocialController alloc] initWithSection:mode];
        else page = [[OVKListController alloc] initWithMode:mode identifier:[OVKAPI shared].userID title:title];
        nav = [[OVKNavigationController alloc] initWithRootViewController:page]; OVKStyleNavigation(nav); if ([page isKindOfClass:[OVKMessagesController class]]) [nav setNavigationBarHidden:YES animated:NO]; self.sections[mode] = nav;
    }
    if (self.active != nav) {
        [self.active willMoveToParentViewController:nil]; [self.active.view removeFromSuperview]; [self.active removeFromParentViewController];
        self.active = nav; [self addChildViewController:nav]; nav.view.frame = self.view.bounds; nav.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; [self.view addSubview:nav.view]; [nav didMoveToParentViewController:self];
        if (nav.view.tag != 2101) { nav.view.tag = 2101; UISwipeGestureRecognizer *right = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeOpen)]; right.direction = UISwipeGestureRecognizerDirectionRight; [nav.view addGestureRecognizer:right]; }
    }
    self.selected = mode; [self.menu reloadData];
    [self.view setNeedsLayout];
    NSArray *menuModes=[self menuModes];
    NSUInteger selectedRow = [menuModes indexOfObject:mode];
    if (selectedRow != NSNotFound) [self.menu selectRowAtIndexPath:[NSIndexPath indexPathForRow:selectedRow inSection:0] animated:NO scrollPosition:UITableViewScrollPositionNone];
    UIViewController *root = [nav.viewControllers objectAtIndex:0];
    UIButton *menuButton = [UIButton buttonWithType:UIButtonTypeCustom]; menuButton.frame = CGRectMake(0,0,40,30); OVKStyleAssetButton(menuButton,@"NavButton"); [menuButton setImage:OVKMenuGlyph() forState:UIControlStateNormal]; menuButton.accessibilityLabel = OVKL(@"Меню"); [menuButton addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside]; root.navigationItem.leftBarButtonItem = UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad ? nil : [[UIBarButtonItem alloc] initWithCustomView:menuButton];
}
- (void)swipeOpen { if (self.active.viewControllers.count == 1 && !self.opened) [self toggleMenu]; }
- (void)toggleMenu {
    if (UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad) return;
    if (self.opened) { [self closeMenu]; return; }
    self.opened = YES; [self.active.view endEditing:YES];
    self.cover = [UIButton buttonWithType:UIButtonTypeCustom]; self.cover.frame = self.active.view.bounds; self.cover.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; self.cover.backgroundColor = [UIColor colorWithWhite:0 alpha:.12]; [self.cover addTarget:self action:@selector(closeMenu) forControlEvents:UIControlEventTouchUpInside]; [self.active.view addSubview:self.cover];
    self.active.view.layer.shadowColor = [UIColor blackColor].CGColor; self.active.view.layer.shadowOpacity = OVKLowMemoryDevice() ? 0 : .6; self.active.view.layer.shadowRadius = 6;
    if (!OVKLowMemoryDevice()) self.active.view.layer.shadowPath=[UIBezierPath bezierPathWithRect:self.active.view.bounds].CGPath;
    [UIView animateWithDuration:.23 animations:^{ self.active.view.transform = CGAffineTransformMakeTranslation([self menuWidth],0); }];
}
- (void)closeMenu {
    self.opened = NO; [self.cover removeFromSuperview]; self.cover = nil;
    [UIView animateWithDuration:.2 animations:^{ self.active.view.transform = CGAffineTransformIdentity; }];
}
- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations {
    UIViewController *presented=self.presentedViewController;
    if (presented && !presented.isBeingDismissed && presented.modalPresentationStyle==UIModalPresentationFullScreen) return presented.supportedInterfaceOrientations;
    return self.active ? self.active.supportedInterfaceOrientations : UIInterfaceOrientationMaskPortrait;
}
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning]; for (NSString *mode in [self.sections allKeys]) if (![mode isEqualToString:self.selected] && ![mode isEqualToString:@"audio"]) [self.sections removeObjectForKey:mode];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end
