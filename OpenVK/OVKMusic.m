#import "OVKLanguage.h"
#import "OVKMusic.h"
#import "OVKMedia.h"
#import "OVKUI.h"
#import "OVKAPI.h"
BOOL OVKExperimentalMusic(void) { return YES; }
BOOL OVKExperimentalVideo(void) { return YES; }
@interface OVKLocalMusicController : OVKAttachmentsController
@property (assign, nonatomic) BOOL scanning;
@property (assign, nonatomic) BOOL scanAgain;
@property (strong, nonatomic) NSArray *lastFileItems;
@property (strong, nonatomic) UILabel *libraryHint;
@end
@implementation OVKLocalMusicController
- (id)init { return [super initWithAttachments:@[] title:OVKL(@"На устройстве")]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.refreshControl=[[UIRefreshControl alloc] init]; [self.refreshControl addTarget:self action:@selector(reloadFiles) forControlEvents:UIControlEventValueChanged];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadFiles) name:@"OVKLocalMusicChanged" object:nil];
    [self reloadFiles];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; if (!self.scanning) [self reloadFiles]; }
- (void)reloadFiles {
    if (self.scanning) { self.scanAgain=YES; return; } self.scanning=YES;
    __weak OVKLocalMusicController *weakSelf=self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW,0), ^{ @autoreleasepool {
        NSArray *items=OVKLocalMusicItems();
        dispatch_async(dispatch_get_main_queue(), ^{
            OVKLocalMusicController *page=weakSelf; if (!page) return; page.scanning=NO;
            if (![page.lastFileItems isEqualToArray:items]) { page.lastFileItems=items; [page replaceAttachments:items]; }
            [page.refreshControl endRefreshing];
            if (!page.libraryHint) { page.libraryHint=[[UILabel alloc] init]; page.libraryHint.numberOfLines=0; page.libraryHint.textAlignment=NSTextAlignmentCenter; page.libraryHint.font=[UIFont systemFontOfSize:13]; page.libraryHint.backgroundColor=[UIColor clearColor]; }
            page.libraryHint.frame=CGRectMake(0,0,page.view.bounds.size.width,items.count ? 48 : 120); page.libraryHint.textColor=OVKThemeSecondary();
            page.libraryHint.text=items.count ? OVKL(@"Музыка, сохранённая в приложении") : OVKL(@"Добавьте MP3, M4A или WAV через iTunes → Программы → Общие файлы → Ovk-Mobile.\nИли откройте аудиофайл в Ovk-Mobile из другого приложения.");
            page.tableView.tableHeaderView=page.libraryHint;
            if (page.scanAgain) { page.scanAgain=NO; [page reloadFiles]; }
        });
    }});
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
