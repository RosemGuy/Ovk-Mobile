#import "OVKUI.h"
#import "OVKAPI.h"
#import "OVKMedia.h"
#import <QuartzCore/QuartzCore.h>
@interface OVKSettingsController : UITableViewController <UIAlertViewDelegate>
@end
@implementation OVKSettingsController
- (id)init { self = [super initWithStyle:UITableViewStyleGrouped]; if (self) self.title = @"Настройки"; return self; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 1 ? 2 : 1; }
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path { return path.section == 0 ? 66 : 50; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @[@"Аккаунт",@"Приложение",@""][section]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == 0 ? @"Чтобы сменить инстанс, выйдите из аккаунта. Токены разных серверов не смешиваются." : (section == 2 ? @"Выход удаляет токен с устройства." : nil);
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if (path.section == 0) { cell.textLabel.text = @"Инстанс"; cell.detailTextLabel.numberOfLines = 2; cell.detailTextLabel.text = [OVKAPI shared].demo ? @"Демонстрация без аккаунта" : [NSString stringWithFormat:@"%@\nAPI: %@",[OVKAPI shared].siteServer ?: [OVKAPI shared].server,[OVKAPI shared].server]; }
    else if (path.section == 1) { cell.textLabel.text = path.row ? @"Оформление" : @"Ovk-Mobile alpha"; cell.detailTextLabel.text = path.row ? @"В духе VK App 2.1 • iOS 6" : @"Неофициальный клиент OpenVK"; }
    else { cell.textLabel.text = @"Выйти из аккаунта"; cell.textLabel.textColor = [UIColor colorWithRed:.65 green:.18 blue:.18 alpha:1]; }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section == 2) [[[UIAlertView alloc] initWithTitle:@"Выйти?" message:@"Сохранённый токен будет удалён с устройства." delegate:self cancelButtonTitle:@"Отмена" otherButtonTitles:@"Выйти",nil] show];
}
- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index { if (index == 1) [[OVKAPI shared] logout]; }
@end
@interface OVKRootController () <UITableViewDataSource,UITableViewDelegate>
@property (strong, nonatomic) UITableView *menu;
@property (strong, nonatomic) NSMutableDictionary *sections;
@property (strong, nonatomic) UINavigationController *active;
@property (strong, nonatomic) UIButton *cover;
@property (strong, nonatomic) UILabel *nameLabel;
@property (strong, nonatomic) OVKRemoteImageView *profileImage;
@property (copy, nonatomic) NSString *selected;
@property (assign, nonatomic) BOOL opened;
@end
@implementation OVKRootController
- (CGFloat)menuWidth { return MIN(280,self.view.bounds.size.width-55); }
- (void)viewDidLoad {
    [super viewDidLoad]; self.sections = [NSMutableDictionary dictionary]; self.view.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"SidebarTexture"]]; self.view.clipsToBounds = YES;
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) self.edgesForExtendedLayout = UIRectEdgeNone;
    self.menu = [[UITableView alloc] initWithFrame:CGRectMake(0,0,[self menuWidth],self.view.bounds.size.height) style:UITableViewStylePlain]; self.menu.autoresizingMask = UIViewAutoresizingFlexibleHeight; self.menu.backgroundColor = self.view.backgroundColor; self.menu.separatorColor = [UIColor colorWithWhite:0 alpha:.25]; self.menu.dataSource = self; self.menu.delegate = self; self.menu.rowHeight = 45; self.menu.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero]; [self.view addSubview:self.menu];
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0,0,[self menuWidth],86)];
    OVKRemoteImageView *avatar = [[OVKRemoteImageView alloc] initWithImage:[UIImage imageNamed:@"Avatar"]]; avatar.frame = CGRectMake(15,20,45,45); [header addSubview:avatar]; self.profileImage = avatar; avatar.contentMode = UIViewContentModeScaleAspectFill; avatar.clipsToBounds = YES;
    self.nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(73,19,[self menuWidth]-85,25)]; self.nameLabel.backgroundColor = [UIColor clearColor]; self.nameLabel.textColor = [UIColor whiteColor]; self.nameLabel.font = [UIFont boldSystemFontOfSize:17]; self.nameLabel.text = @"Моя страница"; [header addSubview:self.nameLabel];
    UILabel *instance = [[UILabel alloc] initWithFrame:CGRectMake(73,46,[self menuWidth]-85,19)]; instance.backgroundColor = [UIColor clearColor]; instance.textColor = [UIColor colorWithWhite:.6 alpha:1]; instance.font = [UIFont systemFontOfSize:12]; NSURL *serverURL = [NSURL URLWithString:[OVKAPI shared].siteServer ?: [OVKAPI shared].server]; instance.text = [OVKAPI shared].demo ? @"Демонстрация" : [serverURL host]; [header addSubview:instance];
    UIButton *profile = [UIButton buttonWithType:UIButtonTypeCustom]; profile.frame = header.bounds; [profile addTarget:self action:@selector(profile) forControlEvents:UIControlEventTouchUpInside]; [header addSubview:profile]; header.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"MenuHeader"]]; self.menu.tableHeaderView = header;
    UISwipeGestureRecognizer *left = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(closeMenu)]; left.direction = UISwipeGestureRecognizerDirectionLeft; [self.menu addGestureRecognizer:left];
    [self showSection:@"news" title:@"Новости"];
    NSString *session = [[OVKAPI shared].token copy]; BOOL demo = [OVKAPI shared].demo;
    [[OVKAPI shared] call:@"users.get" parameters:@{@"fields":@"photo_100"} completion:^(id result,NSError *error) {
        if (demo != [OVKAPI shared].demo || (!demo && ![session isEqualToString:[OVKAPI shared].token])) return;
        if (!error && OVKArray(result).count) { NSDictionary *user = OVKDictionary(result[0]); self.nameLabel.text = [NSString stringWithFormat:@"%@ %@",OVKString(user[@"first_name"]),OVKString(user[@"last_name"])];
            [self.profileImage load:OVKString(user[@"photo_100"])]; }

    }];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 9; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    NSArray *titles = @[@"Друзья",@"Фотографии",@"Сообщения",@"Новости",@"Моя страница",@"Аудиозаписи",@"Видеозаписи",@"Сайт инстанса ↗",@"Настройки"];
    NSArray *icons = @[@"Friends",@"PhotoMedia",@"Messages",@"News",@"Profile",@"AudioMedia",@"VideoMedia",@"Web",@"Settings"];
    cell.textLabel.text = titles[path.row]; cell.textLabel.font = [UIFont boldSystemFontOfSize:17]; cell.textLabel.shadowColor = [UIColor blackColor]; cell.textLabel.shadowOffset = CGSizeMake(0,-1); cell.textLabel.backgroundColor = [UIColor clearColor]; cell.backgroundView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"MenuRow"]]; cell.textLabel.textColor = [UIColor colorWithWhite:.83 alpha:1]; cell.backgroundColor = self.menu.backgroundColor; cell.imageView.image = [UIImage imageNamed:icons[path.row]];
    UIImageView *selection = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"MenuSelected"]]; cell.selectedBackgroundView = selection; cell.textLabel.highlightedTextColor = [UIColor whiteColor];
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    if (path.row == 7) {
        if ([OVKAPI shared].demo) { OVKAlert(@"Демонстрация",@"Войдите в аккаунт, чтобы открыть сайт своего инстанса."); return; }
        NSString *server = [OVKAPI shared].siteServer ?: [OVKAPI shared].server; if ([server isEqualToString:@"https://api.openvk.org"]) server = @"https://openvk.org";
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:server]]; return;
    }
    NSArray *modes = @[@"friends",@"photo",@"dialogs",@"news",@"profile",@"audio",@"video",@"web",@"settings"];
    NSArray *titles = @[@"Друзья",@"Фотографии",@"Сообщения",@"Новости",@"Моя страница",@"Аудиозаписи",@"Видеозаписи",@"Сайт",@"Настройки"];
    [self showSection:modes[path.row] title:titles[path.row]];
}
- (void)profile { [self showSection:@"profile" title:@"Моя страница"]; }
- (void)showSection:(NSString *)mode title:(NSString *)title {
    [self closeMenu];
    UINavigationController *nav = self.sections[mode];
    if (!nav) {
        UIViewController *page;
        if ([mode isEqualToString:@"settings"]) page = [[OVKSettingsController alloc] init];
        else if ([@[@"photo",@"video",@"audio"] containsObject:mode]) page = [[OVKLibraryController alloc] initWithKind:mode identifier:[OVKAPI shared].userID title:title];
        else page = [[OVKListController alloc] initWithMode:mode identifier:[OVKAPI shared].userID title:title];
        nav = [[UINavigationController alloc] initWithRootViewController:page]; OVKStyleNavigation(nav); self.sections[mode] = nav;
    }
    if (self.active != nav) {
        [self.active willMoveToParentViewController:nil]; [self.active.view removeFromSuperview]; [self.active removeFromParentViewController];
        self.active = nav; [self addChildViewController:nav]; nav.view.frame = self.view.bounds; nav.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; [self.view addSubview:nav.view]; [nav didMoveToParentViewController:self];
        if (nav.view.tag != 2101) { nav.view.tag = 2101; UISwipeGestureRecognizer *right = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeOpen)]; right.direction = UISwipeGestureRecognizerDirectionRight; [nav.view addGestureRecognizer:right]; }
    }
    self.selected = mode;
    NSArray *menuModes = @[@"friends",@"photo",@"dialogs",@"news",@"profile",@"audio",@"video",@"web",@"settings"];
    NSUInteger selectedRow = [menuModes indexOfObject:mode];
    if (selectedRow != NSNotFound) [self.menu selectRowAtIndexPath:[NSIndexPath indexPathForRow:selectedRow inSection:0] animated:NO scrollPosition:UITableViewScrollPositionNone];
    UIViewController *root = [nav.viewControllers objectAtIndex:0];
    UIButton *menuButton = [UIButton buttonWithType:UIButtonTypeCustom]; menuButton.frame = CGRectMake(0,0,34,34); [menuButton setBackgroundImage:[[UIImage imageNamed:@"NavButton"] resizableImageWithCapInsets:UIEdgeInsetsMake(6,10,6,10)] forState:UIControlStateNormal]; [menuButton setImage:[UIImage imageNamed:@"Menu"] forState:UIControlStateNormal]; menuButton.accessibilityLabel = @"Меню"; [menuButton addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside]; root.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:menuButton];
}
- (void)swipeOpen { if (self.active.viewControllers.count == 1 && !self.opened) [self toggleMenu]; }
- (void)toggleMenu {
    if (self.opened) { [self closeMenu]; return; }
    self.opened = YES; [self.active.view endEditing:YES];
    self.cover = [UIButton buttonWithType:UIButtonTypeCustom]; self.cover.frame = self.active.view.bounds; self.cover.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; self.cover.backgroundColor = [UIColor colorWithWhite:0 alpha:.12]; [self.cover addTarget:self action:@selector(closeMenu) forControlEvents:UIControlEventTouchUpInside]; [self.active.view addSubview:self.cover];
    self.active.view.layer.shadowColor = [UIColor blackColor].CGColor; self.active.view.layer.shadowOpacity = .6; self.active.view.layer.shadowRadius = 6;
    [UIView animateWithDuration:.23 animations:^{ self.active.view.transform = CGAffineTransformMakeTranslation([self menuWidth],0); }];
}
- (void)closeMenu {
    self.opened = NO; [self.cover removeFromSuperview]; self.cover = nil;
    [UIView animateWithDuration:.2 animations:^{ self.active.view.transform = CGAffineTransformIdentity; }];
}
@end
