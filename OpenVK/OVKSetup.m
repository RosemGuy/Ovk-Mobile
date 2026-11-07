#import "OVKSetup.h"
#import "OVKUI.h"
static NSString * const OVKSetupFinishedKey=@"OVKClientSetupCompleted";
@interface OVKSetupController ()
@property (strong, nonatomic) UIButton *continueButton;
@end
@implementation OVKSetupController
- (id)init { return [super initWithStyle:UITableViewStyleGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; OVKConfigureEdges(self);
    self.navigationItem.hidesBackButton=YES;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:OVKL(@"Готово") style:UIBarButtonItemStyleDone target:self action:@selector(finishSetup)];
    UIView *footer=[[UIView alloc] initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,66)];
    self.continueButton=[UIButton buttonWithType:UIButtonTypeCustom]; self.continueButton.titleLabel.font=[UIFont boldSystemFontOfSize:15]; [self.continueButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal]; [self.continueButton addTarget:self action:@selector(finishSetup) forControlEvents:UIControlEventTouchUpInside]; [footer addSubview:self.continueButton]; self.tableView.tableFooterView=footer;
    [self updateAppearance];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self updateAppearance]; }
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; CGFloat width=MIN(320,self.view.bounds.size.width-32); self.continueButton.frame=CGRectMake((self.view.bounds.size.width-width)/2,12,width,33); }
- (void)updateAppearance {
    self.title=OVKL(@"Настройка клиента"); self.navigationItem.rightBarButtonItem.title=OVKL(@"Готово"); OVKThemeTable(self.tableView); OVKStyleNavigation(self.navigationController);
    [self.continueButton setTitle:OVKL(@"Продолжить") forState:UIControlStateNormal]; OVKStyleAssetButton(self.continueButton,@"ProfileBlueButton");
    UIView *header=[[UIView alloc] initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,146)];
    UIImageView *logo=[[UIImageView alloc] initWithImage:OVKThemeLogo()]; logo.frame=CGRectMake((header.bounds.size.width-68)/2,12,68,68); logo.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin; logo.contentMode=UIViewContentModeScaleAspectFit; [header addSubview:logo];
    UILabel *welcome=[[UILabel alloc] initWithFrame:CGRectMake(16,88,header.bounds.size.width-32,48)]; welcome.autoresizingMask=UIViewAutoresizingFlexibleWidth; welcome.backgroundColor=[UIColor clearColor]; welcome.textColor=OVKThemeText(); welcome.font=[UIFont systemFontOfSize:15]; welcome.textAlignment=NSTextAlignmentCenter; welcome.numberOfLines=2; welcome.text=OVKL(@"Выберите язык, тему и цвет. Их можно изменить позже в настройках."); [header addSubview:welcome]; self.tableView.tableHeaderView=header;
    [self.tableView reloadData]; [self.view setNeedsLayout];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section==2 ? OVKThemeColors().count : 2; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @[OVKL(@"Язык"),OVKL(@"Тема"),OVKL(@"Цвет")][section]; }
- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section { OVKThemeSection(view); }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"setup"];
    if (!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"setup"];
    BOOL selected=NO;
    if (path.section==0) { cell.textLabel.text=path.row==0 ? @"Русский" : @"English"; selected=OVKLanguageIsEnglish()==(path.row==1); }
    else if (path.section==1) { cell.textLabel.text=OVKL(path.row==0 ? @"Светлая" : @"Тёмная"); selected=OVKDarkTheme()==(path.row==1); }
    else { NSString *color=OVKThemeColors()[path.row]; NSDictionary *titles=@{@"blue":@"Синий",@"purple":@"Фиолетовый",@"red":@"Красный",@"green":@"Зелёный",@"orange":@"Оранжевый",@"pink":@"Розовый"}; cell.textLabel.text=OVKL(titles[color]); selected=[OVKThemeColor() isEqualToString:color]; }
    cell.accessoryType=selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone; OVKThemeCell(cell); return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:NO];
    if (path.section==0) OVKSetLanguage(path.row==0 ? @"ru" : @"en"); else if (path.section==1) OVKSetDarkTheme(path.row==1); else OVKSetThemeColor(OVKThemeColors()[path.row]);
    [self updateAppearance];
}
- (void)finishSetup {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:OVKSetupFinishedKey];
    if (self.completed) self.completed(); else [self.navigationController popViewControllerAnimated:YES];
}
@end
