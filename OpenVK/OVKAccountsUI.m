#import "OVKUI.h"
#import "OVKAPI.h"
NSArray *OVKMenuOrder(void) {
    NSArray *defaults=@[@"profile",@"news",@"dialogs",@"friends",@"photo",@"audio",@"video",@"archive",@"settings"];
    NSMutableArray *result=[NSMutableArray array]; for (id saved in [[NSUserDefaults standardUserDefaults] arrayForKey:@"OVKMenuOrder"]) { id mode=[saved isEqual:@"web"] ? @"archive" : saved; if ([defaults containsObject:mode] && ![result containsObject:mode]) [result addObject:mode]; }
    for (NSString *mode in defaults) if (![result containsObject:mode]) [result addObject:mode]; return result;
}
NSString *OVKMenuTitle(NSString *mode) { return @{@"friends":OVKL(@"Друзья"),@"photo":OVKL(@"Фотографии"),@"dialogs":OVKL(@"Сообщения"),@"news":OVKL(@"Новости"),@"profile":OVKL(@"Моя страница"),@"audio":OVKL(@"Музыка"),@"video":OVKL(@"Видеозаписи"),@"archive":OVKL(@"Архив записей"),@"settings":OVKL(@"Настройки")}[mode]; }
@implementation OVKMenuOrderController
- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section { OVKThemeSection(view); }
- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section { OVKThemeSection(view); }
- (void)viewDidLoad { [super viewDidLoad]; self.title=OVKL(@"Порядок меню"); OVKThemeTable(self.tableView); self.tableView.editing=YES; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return OVKMenuOrder().count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path { UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil]; cell.textLabel.text=OVKMenuTitle(OVKMenuOrder()[path.row]); cell.showsReorderControl=YES; OVKThemeCell(cell); return cell; }
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)path { return UITableViewCellEditingStyleNone; }
- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)path { return NO; }
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)path { return YES; }
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination { NSMutableArray *order=[OVKMenuOrder() mutableCopy]; id item=order[source.row]; [order removeObjectAtIndex:source.row]; [order insertObject:item atIndex:destination.row]; [[NSUserDefaults standardUserDefaults] setObject:order forKey:@"OVKMenuOrder"]; [[NSNotificationCenter defaultCenter] postNotificationName:@"OVKMenuOrderChanged" object:nil]; }
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
