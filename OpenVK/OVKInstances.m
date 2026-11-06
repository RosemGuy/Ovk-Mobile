#import "OVKLanguage.h"
#import "OVKUI.h"
#import "OVKAPI.h"
// Protocol/interaction reference: OvkisserLiteiOS, archive 76f30a71ca684e09c85c42ba0c4d8841c818147f.
// Independently implemented; no source or artwork from that project is included.
@interface OVKAddInstanceController : UIViewController
@property (strong, nonatomic) UITextField *siteField;
@property (strong, nonatomic) UITextField *apiField;
@property (copy, nonatomic) void (^saved)(void);
@end
@implementation OVKAddInstanceController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = OVKL(@"Новый инстанс");
    OVKConfigureEdges(self);
    self.view.backgroundColor = [UIColor colorWithWhite:.95 alpha:1];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:OVKL(@"Добавить") style:UIBarButtonItemStyleDone target:self action:@selector(saveInstance)];
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds]; scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; scroll.contentSize = CGSizeMake(320,330); [self.view addSubview:scroll];
    CGFloat width = self.view.bounds.size.width;
    self.siteField = [[UITextField alloc] initWithFrame:CGRectMake(16,25,width-32,40)]; self.apiField = [[UITextField alloc] initWithFrame:CGRectMake(16,80,width-32,40)];
    self.siteField.placeholder = OVKL(@"Сайт: example.org"); self.apiField.placeholder = OVKL(@"API-домен, если отличается");
    for (UITextField *field in @[self.siteField,self.apiField]) { field.borderStyle = UITextBorderStyleRoundedRect; field.keyboardType = UIKeyboardTypeURL; field.autocapitalizationType = UITextAutocapitalizationTypeNone; field.autocorrectionType = UITextAutocorrectionTypeNo; field.autoresizingMask = UIViewAutoresizingFlexibleWidth; field.font = [UIFont systemFontOfSize:14]; [scroll addSubview:field]; }
    UILabel *help = [[UILabel alloc] initWithFrame:CGRectMake(16,139,width-32,95)]; help.backgroundColor = [UIColor clearColor]; help.font = [UIFont systemFontOfSize:13]; help.textColor = [UIColor grayColor]; help.numberOfLines = 0; help.autoresizingMask = UIViewAutoresizingFlexibleWidth; help.text = OVKL(@"Укажите домен сервера OpenVK. Если API работает на том же домене, второе поле оставьте пустым. Адреса сохранятся в списке; аккаунт и пароль в списке не хранятся."); [scroll addSubview:help];
}
- (void)saveInstance {
    NSString *site = [OVKAPI validatedServer:self.siteField.text];
    NSString *input = [self.apiField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *api = input.length ? [OVKAPI validatedServer:input] : site;
    if (!site || !api) { OVKAlert(OVKL(@"Неверный адрес"),OVKL(@"Введите HTTPS-домен без пути и параметров. Префикс https:// можно не указывать.")); return; }
    [OVKInstancesController rememberSite:site api:api]; [self.view endEditing:YES]; if (self.saved) self.saved(); [self.navigationController popViewControllerAnimated:YES];
}
@end
@interface OVKInstancesController ()
@property (strong, nonatomic) NSArray *instances;
@property (copy, nonatomic) void (^selection)(NSString *,NSString *);
@end
@implementation OVKInstancesController
+ (NSArray *)entries {
    NSMutableArray *result = [@[@{@"site":@"https://openvk.xyz",@"api":@"https://openvk.xyz"},@{@"site":@"https://openvk.org",@"api":@"https://api.openvk.org"}] mutableCopy];
    for (id value in OVKArray([[NSUserDefaults standardUserDefaults] arrayForKey:@"OVKSavedInstances"])) {
        NSDictionary *entry = OVKDictionary(value); NSString *site = OVKString(entry[@"site"]); NSString *api = OVKString(entry[@"api"]);
        if (!site.length || !api.length || ![OVKAPI validatedServer:site] || ![OVKAPI validatedServer:api]) continue;
        BOOL duplicate = NO;
        for (NSDictionary *existing in result) if ([existing[@"site"] isEqual:site] && [existing[@"api"] isEqual:api]) duplicate = YES;
        if (!duplicate) [result addObject:@{@"site":site,@"api":api}];
    }
    return result;
}
+ (void)rememberSite:(NSString *)site api:(NSString *)api {
    NSMutableArray *entries = [[self entries] mutableCopy];
    BOOL duplicate = NO; for (NSDictionary *entry in entries) if ([entry[@"site"] isEqual:site] && [entry[@"api"] isEqual:api]) duplicate = YES;
    if (!duplicate) [entries addObject:@{@"site":site,@"api":api}];
    [[NSUserDefaults standardUserDefaults] setObject:entries forKey:@"OVKSavedInstances"];
}
- (id)initWithSelection:(void (^)(NSString *,NSString *))selection {
    self = [super initWithStyle:UITableViewStylePlain]; if (self) { self.selection = selection; self.title = OVKL(@"Инстансы OpenVK"); } return self;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:OVKL(@"Закрыть") style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addInstance)];
    self.tableView.rowHeight = 65;
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; self.instances = [[self class] entries]; [self.tableView reloadData]; }
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)addInstance { OVKAddInstanceController *add = [[OVKAddInstanceController alloc] init]; [self.navigationController pushViewController:add animated:YES]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.instances.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    NSDictionary *entry = self.instances[path.row]; UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    NSURL *siteURL = [NSURL URLWithString:entry[@"site"]]; cell.textLabel.text = [siteURL host]; cell.textLabel.textColor = OVKBlue(); cell.detailTextLabel.text = [@"API: " stringByAppendingString:entry[@"api"]]; cell.detailTextLabel.font = [UIFont systemFontOfSize:11]; cell.detailTextLabel.numberOfLines = 2;
    if ([entry[@"site"] isEqual:[OVKAPI shared].siteServer] && [entry[@"api"] isEqual:[OVKAPI shared].server]) cell.accessoryType = UITableViewCellAccessoryCheckmark;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    NSDictionary *entry = self.instances[path.row]; [tableView deselectRowAtIndexPath:path animated:YES];
    [self dismissViewControllerAnimated:YES completion:^{ if (self.selection) self.selection(entry[@"site"],entry[@"api"]); }];
}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)path { return path.row >= 2; }
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if (style != UITableViewCellEditingStyleDelete || path.row < 2) return;
    NSMutableArray *entries = [self.instances mutableCopy]; [entries removeObjectAtIndex:path.row]; [[NSUserDefaults standardUserDefaults] setObject:entries forKey:@"OVKSavedInstances"]; self.instances = entries; [tableView deleteRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationAutomatic];
}
@end
