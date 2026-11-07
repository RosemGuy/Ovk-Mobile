#import "OVKUI.h"
#import "OVKAPI.h"
static NSArray *OVKCachedMenuOrder;
NSArray *OVKMenuOrder(void) {
    if (OVKCachedMenuOrder) return OVKCachedMenuOrder;
    NSArray *defaults=@[@"profile",@"news",@"notifications",@"dialogs",@"friends",@"groups",@"photo",@"audio",@"video",@"archive",@"settings"];
    NSMutableArray *result=[NSMutableArray array]; for (id saved in [[NSUserDefaults standardUserDefaults] arrayForKey:@"OVKMenuOrder"]) { id mode=[saved isEqual:@"web"] ? @"archive" : saved; if ([defaults containsObject:mode] && ![result containsObject:mode]) [result addObject:mode]; }
    for (NSUInteger i=0;i<defaults.count;i++) { NSString *mode=defaults[i]; if ([result containsObject:mode]) continue; NSUInteger insertion=0; for (NSUInteger j=i;j>0;j--) { NSUInteger previous=[result indexOfObject:defaults[j-1]]; if (previous!=NSNotFound) { insertion=previous+1; break; } } [result insertObject:mode atIndex:insertion]; } OVKCachedMenuOrder=[result copy]; return OVKCachedMenuOrder;
}
NSString *OVKMenuTitle(NSString *mode) {
    static NSDictionary *titles; static dispatch_once_t once; dispatch_once(&once, ^{ titles=@{@"notifications":@"Ответы",@"groups":@"Группы",@"friends":@"Друзья",@"photo":@"Фотографии",@"dialogs":@"Сообщения",@"news":@"Новости",@"profile":@"Моя страница",@"audio":@"Музыка",@"video":@"Видеозаписи",@"archive":@"Архив записей",@"settings":@"Настройки"}; }); return OVKL(titles[mode] ?: mode);
}
@implementation OVKMenuOrderController
- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section { OVKThemeSection(view); }
- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section { OVKThemeSection(view); }
- (void)viewDidLoad { [super viewDidLoad]; self.title=OVKL(@"Порядок меню"); OVKThemeTable(self.tableView); self.tableView.editing=YES; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return OVKMenuOrder().count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path { UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil]; cell.textLabel.text=OVKMenuTitle(OVKMenuOrder()[path.row]); cell.showsReorderControl=YES; OVKThemeCell(cell); return cell; }
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)path { return UITableViewCellEditingStyleNone; }
- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)path { return NO; }
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)path { return YES; }
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination { NSMutableArray *order=[OVKMenuOrder() mutableCopy]; id item=order[source.row]; [order removeObjectAtIndex:source.row]; [order insertObject:item atIndex:destination.row]; [[NSUserDefaults standardUserDefaults] setObject:order forKey:@"OVKMenuOrder"]; OVKCachedMenuOrder=nil; [[NSNotificationCenter defaultCenter] postNotificationName:@"OVKMenuOrderChanged" object:nil]; }
@end
@interface OVKAccountsController ()
@property (strong, nonatomic) NSArray *accounts;
@end
@implementation OVKAccountsController
- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section { OVKThemeSection(view); }
- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section { OVKThemeSection(view); }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; self.title=OVKL(@"Аккаунты"); self.accounts=[[OVKAPI shared] savedAccounts]; OVKThemeTable(self.tableView); [self.tableView reloadData]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section==0 ? self.accounts.count : 1; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return section==1 ? OVKL(@"Добавление аккаунта сохраняет остальные сеансы. Пароли не сохраняются.") : nil; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if (path.section==1) cell.textLabel.text=OVKL(@"Добавить аккаунт");
    else { NSDictionary *account=self.accounts[path.row]; NSString *name=OVKString(account[@"name"]); cell.textLabel.text=name.length ? name : [NSString stringWithFormat:@"ID %@",account[@"id"]]; cell.detailTextLabel.text=account[@"server"]; if ([OVKString(account[@"server"]) isEqual:[OVKAPI shared].server] && [OVKString(account[@"id"]) isEqual:OVKString([OVKAPI shared].userID)]) cell.accessoryType=UITableViewCellAccessoryCheckmark; }
    OVKThemeCell(cell); return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path { [tableView deselectRowAtIndexPath:path animated:YES]; if (path.section==1) { [[OVKAPI shared] beginAddingAccount]; return; } if (![[OVKAPI shared] switchToAccount:self.accounts[path.row]]) OVKAlert(OVKL(@"Аккаунты"),[[OVKAPI shared] keychainErrorDescription]); }
@end
