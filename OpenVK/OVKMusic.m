#import "OVKLanguage.h"
#import "OVKMusic.h"
#import "OVKMedia.h"
#import "OVKUI.h"
#import "OVKAPI.h"
BOOL OVKExperimentalMusic(void) { return YES; }
BOOL OVKExperimentalVideo(void) { return [[NSUserDefaults standardUserDefaults] boolForKey:@"ExperimentalVideo"]; }
@implementation OVKExperimentalController
- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section { OVKThemeSection(view); }
- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section { OVKThemeSection(view); }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; OVKThemeTable(self.tableView); [self.tableView reloadData]; }
- (id)init { self=[super initWithStyle:UITableViewStyleGrouped]; if (self) self.title=OVKL(@"Экспериментальное"); return self; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 1; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return OVKL(@"Видео — экспериментальный раздел. Музыка OpenVK доступна в разделе «Музыка»."); }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text=index.row ? OVKL(@"Музыка OpenVK") : OVKL(@"Видеозаписи"); cell.imageView.image=[UIImage imageNamed:index.row ? @"AudioMedia" : @"VideoMedia"];
    UISwitch *toggle=[[UISwitch alloc] init]; toggle.tag=index.row; toggle.on=index.row ? OVKExperimentalMusic() : OVKExperimentalVideo(); [toggle addTarget:self action:@selector(changed:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView=toggle; cell.selectionStyle=UITableViewCellSelectionStyleNone; OVKThemeCell(cell); return cell;
}
- (void)changed:(UISwitch *)toggle {
    [[NSUserDefaults standardUserDefaults] setBool:toggle.on forKey:toggle.tag ? @"ExperimentalOpenVKMusic" : @"ExperimentalVideo"];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"OVKExperimentalChanged" object:nil];
}
@end
@interface OVKLocalMusicController : OVKAttachmentsController
@end
@implementation OVKLocalMusicController
- (id)init { return [super initWithAttachments:@[] title:OVKL(@"На устройстве")]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.refreshControl=[[UIRefreshControl alloc] init]; [self.refreshControl addTarget:self action:@selector(reloadFiles) forControlEvents:UIControlEventValueChanged];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadFiles) name:@"OVKLocalMusicChanged" object:nil];
    [self reloadFiles];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadFiles]; }
- (void)reloadFiles {
    NSArray *items=OVKLocalMusicItems();
    [self replaceAttachments:items]; [self.refreshControl endRefreshing];
    UILabel *hint=[[UILabel alloc] initWithFrame:CGRectMake(12,0,self.view.bounds.size.width-24,items.count ? 48 : 120)]; hint.numberOfLines=0; hint.textAlignment=NSTextAlignmentCenter; hint.font=[UIFont systemFontOfSize:13]; hint.textColor=[UIColor grayColor]; hint.backgroundColor=[UIColor clearColor];
    hint.text=items.count ? OVKL(@"Музыка, сохранённая в приложении") : OVKL(@"Добавьте MP3, M4A или WAV через iTunes → Программы → Общие файлы → Ovk-Mobile.\nИли откройте аудиофайл в Ovk-Mobile из другого приложения.");
    self.tableView.tableHeaderView=hint;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end
@interface OVKMusicController ()
@property (strong, nonatomic) UISegmentedControl *tabs;
@property (strong, nonatomic) UIViewController *current;
@property (strong, nonatomic) OVKLocalMusicController *local;
@property (strong, nonatomic) OVKLibraryController *remote;
@end
@implementation OVKMusicController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=OVKL(@"Музыка"); self.view.backgroundColor=[UIColor whiteColor];
    OVKConfigureEdges(self);
    self.tabs=[[UISegmentedControl alloc] initWithItems:@[OVKL(@"На устройстве")]]; self.tabs.segmentedControlStyle=UISegmentedControlStyleBar; self.tabs.frame=CGRectMake(10,8,self.view.bounds.size.width-20,30); self.tabs.autoresizingMask=UIViewAutoresizingFlexibleWidth; self.tabs.selectedSegmentIndex=0; [self.tabs addTarget:self action:@selector(selectTab) forControlEvents:UIControlEventValueChanged]; [self.view addSubview:self.tabs];
    self.local=[[OVKLocalMusicController alloc] init];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:OVKL(@"Плеер") style:UIBarButtonItemStylePlain target:self action:@selector(nowPlaying)];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTabs) name:@"OVKExperimentalChanged" object:nil]; [self updateTabs];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; self.title=OVKL(@"Музыка"); self.view.backgroundColor=OVKThemeBackground(); [self.tabs setTitle:OVKL(@"На устройстве") forSegmentAtIndex:0]; self.navigationItem.rightBarButtonItem.title=OVKL(@"Плеер"); }
- (void)updateTabs {
    if (OVKExperimentalMusic() && self.tabs.numberOfSegments==1) [self.tabs insertSegmentWithTitle:@"OpenVK" atIndex:1 animated:NO];
    if (!OVKExperimentalMusic() && self.tabs.numberOfSegments>1) { [self.tabs removeSegmentAtIndex:1 animated:NO]; self.tabs.selectedSegmentIndex=0; self.remote=nil; }
    [self selectTab];
}
- (void)selectTab {
    UIViewController *next=self.local;
    if (self.tabs.selectedSegmentIndex==1 && OVKExperimentalMusic()) { if (![OVKAPI shared].demo && ![OVKAPI shared].token.length) { self.tabs.selectedSegmentIndex=0; OVKAlert(@"OpenVK",OVKL(@"Для музыки сервера войдите в аккаунт.")); [self selectTab]; return; } if (!self.remote) self.remote=[[OVKLibraryController alloc] initWithKind:@"audio" identifier:[OVKAPI shared].userID title:@"OpenVK"]; next=self.remote; }
    if (next==self.current) return;
    [self.current willMoveToParentViewController:nil]; [self.current.view removeFromSuperview]; [self.current removeFromParentViewController];
    self.current=next; [self addChildViewController:next]; next.view.frame=CGRectMake(0,46,self.view.bounds.size.width,self.view.bounds.size.height-46); next.view.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; [self.view addSubview:next.view]; [next didMoveToParentViewController:self];
}
- (void)nowPlaying { [OVKMedia showCurrentMusicFrom:self]; }
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end
