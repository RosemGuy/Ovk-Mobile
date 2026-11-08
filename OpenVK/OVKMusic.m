#import "OVKLanguage.h"
#import "OVKMusic.h"
#import "OVKMedia.h"
#import "OVKUI.h"
#import "OVKAPI.h"
BOOL OVKExperimentalMusic(void) { return YES; }
BOOL OVKExperimentalVideo(void) { return YES; }
@interface OVKMusicController () <UISearchBarDelegate>
@property (strong, nonatomic) UISegmentedControl *tabs;
@property (strong, nonatomic) UIViewController *current;
@property (strong, nonatomic) OVKLibraryController *favorites;
@property (strong, nonatomic) OVKLibraryController *feed;
@property (strong, nonatomic) OVKLibraryController *searchResults;
@property (strong, nonatomic) UISearchBar *searchBar;
@end
@implementation OVKMusicController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=OVKL(@"Музыка"); self.view.backgroundColor=[UIColor whiteColor];
    OVKConfigureEdges(self);
    self.tabs=[[UISegmentedControl alloc] initWithItems:@[OVKL(@"Избранные"),OVKL(@"Новые")]];
    self.tabs.segmentedControlStyle=UISegmentedControlStyleBar;
    self.tabs.frame=CGRectMake(10,8,self.view.bounds.size.width-20,30);
    self.tabs.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    self.tabs.selectedSegmentIndex=[[NSUserDefaults standardUserDefaults] integerForKey:@"OVKMusicTab"]==1 ? 1 : 0;
    [self.tabs addTarget:self action:@selector(selectTab) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.tabs];
    [self showMusicBarItems];
    [self selectTab];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.title=OVKL(@"Музыка");
    self.view.backgroundColor=OVKThemeBackground();
    [self.tabs setTitle:OVKL(@"Избранные") forSegmentAtIndex:0];
    [self.tabs setTitle:OVKL(@"Новые") forSegmentAtIndex:1];
    self.searchBar.placeholder=OVKL(@"Поиск музыки");
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.searchBar resignFirstResponder];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutMusicList];
}
- (void)layoutMusicList {
    CGFloat top = self.searchBar ? 44 : 46;
    self.current.view.frame = CGRectMake(0,top,self.view.bounds.size.width,MAX(0,self.view.bounds.size.height-top));
}
- (void)showMusicBarItems {
    UIBarButtonItem *search = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSearch target:self action:@selector(openSearch)];
    search.accessibilityLabel = OVKL(@"Поиск музыки");
    self.navigationItem.rightBarButtonItem = search;
}
- (void)selectTab {
    if (self.searchBar) return;
    NSInteger index = self.tabs.selectedSegmentIndex;
    [[NSUserDefaults standardUserDefaults] setInteger:index forKey:@"OVKMusicTab"];
    if (index==1) {
        if (!self.feed) self.feed=[[OVKLibraryController alloc] initForAudioFeed];
        [self showList:self.feed];
    } else {
        if (!self.favorites) self.favorites=[[OVKLibraryController alloc] initForAudioFavorites];
        [self showList:self.favorites];
    }
}
- (void)showList:(UIViewController *)next {
    if (next==self.current) { [self layoutMusicList]; return; }
    [self.current willMoveToParentViewController:nil]; [self.current.view removeFromSuperview]; [self.current removeFromParentViewController];
    self.current=next;
    [self addChildViewController:next];
    [self layoutMusicList];
    [self.view addSubview:next.view];
    [next didMoveToParentViewController:self];
}
- (void)openSearch {
    if (self.searchBar) return;
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,44)];
    self.searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.searchBar.placeholder = OVKL(@"Поиск музыки");
    self.searchBar.delegate = self;
    self.tabs.hidden = YES;
    [self.view addSubview:self.searchBar];
    UIBarButtonItem *cancel = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(closeSearch)];
    self.navigationItem.rightBarButtonItems = @[cancel];
    self.searchResults = [[OVKLibraryController alloc] initForAudioSearch];
    [self showList:self.searchResults];
    [self.searchBar becomeFirstResponder];
}
- (void)closeSearch {
    [self.searchBar resignFirstResponder];
    self.searchBar.delegate = nil;
    [self.searchBar removeFromSuperview];
    self.searchBar = nil;
    [self.searchResults setAudioSearchQuery:@""];
    self.searchResults = nil;
    self.tabs.hidden = NO;
    [self showMusicBarItems];
    [self selectTab];
}
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self.searchResults setAudioSearchQuery:searchText];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [self.searchResults submitAudioSearch];
    [searchBar resignFirstResponder];
}
@end

static NSString *OVKSelectedMusicCacheScope(void) {
    OVKAPI *api = [OVKAPI shared];
    return api.demo ? nil : OVKMusicCacheScope(api.server,api.userID);
}

static NSString *OVKMusicSize(unsigned long long bytes) {
    return [NSString localizedStringWithFormat:OVKL(@"%.2f МБ"),bytes/1048576.0];
}

static void OVKDeleteCachedTracks(NSString *scope, NSArray *entries) {
    NSError *failure = nil;
    for (NSDictionary *entry in entries) {
        NSError *error = nil;
        if (!OVKRemoveMusicCacheEntry(scope,entry[@"key"],&error)) failure = error;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:OVKMusicCacheChanged object:nil];
    if (failure) OVKAlert(OVKL(@"Не удалось удалить трек из кэша"),failure.localizedDescription);
}

@interface OVKCachedTracksController : OVKAttachmentsController
@property (copy, nonatomic) NSString *scope;
@property (copy, nonatomic) NSArray *entries;
@property (strong, nonatomic) UIBarButtonItem *deleteItem;
@end

@implementation OVKCachedTracksController
- (id)initWithScope:(NSString *)scope {
    self = [super initWithAttachments:@[] title:OVKL(@"Загруженные треки")];
    if (self) self.scope = scope;
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.allowsMultipleSelectionDuringEditing = YES;
    self.navigationItem.rightBarButtonItem = self.editButtonItem;
    self.deleteItem = [[UIBarButtonItem alloc] initWithTitle:OVKL(@"Удалить") style:UIBarButtonItemStyleDone target:self action:@selector(deleteSelectedTracks)];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cacheListChanged:) name:OVKMusicCacheChanged object:nil];
    [self cacheListChanged:nil];
}
- (void)cacheListChanged:(NSNotification *)note {
    if (note.userInfo[@"progress"]) return;
    NSMutableSet *selected = [NSMutableSet set];
    if (self.editing) {
        for (NSIndexPath *path in self.tableView.indexPathsForSelectedRows) {
            if (path.row<self.entries.count) [selected addObject:self.entries[path.row][@"key"]];
        }
    }
    self.entries = [OVKMusicCacheEntries(self.scope) sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [OVKString(a[@"item"][@"title"]) localizedCaseInsensitiveCompare:OVKString(b[@"item"][@"title"])];
    }];
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:self.entries.count];
    for (NSDictionary *entry in self.entries) [items addObject:entry[@"item"]];
    [self replaceAttachments:items];
    [self.entries enumerateObjectsUsingBlock:^(NSDictionary *entry,NSUInteger index,BOOL *stop) {
        if ([selected containsObject:entry[@"key"]]) {
            [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:0] animated:NO scrollPosition:UITableViewScrollPositionNone];
        }
    }];
    self.deleteItem.enabled = self.editing && self.tableView.indexPathsForSelectedRows.count>0;
}
- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];
    self.navigationItem.rightBarButtonItems = editing ? @[self.deleteItem,self.editButtonItem] : @[self.editButtonItem];
    self.deleteItem.enabled = NO;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    if (self.editing) { self.deleteItem.enabled = YES; return; }
    [super tableView:tableView didSelectRowAtIndexPath:path];
}
- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)path {
    self.deleteItem.enabled = tableView.indexPathsForSelectedRows.count>0;
}
- (void)deleteSelectedTracks {
    NSMutableArray *selected = [NSMutableArray array];
    for (NSIndexPath *path in self.tableView.indexPathsForSelectedRows) {
        if (path.row<self.entries.count) [selected addObject:self.entries[path.row]];
    }
    [self setEditing:NO animated:YES];
    OVKDeleteCachedTracks(self.scope,selected);
}
@end

@interface OVKMusicCacheController () <UIActionSheetDelegate>
@property (copy, nonatomic) NSString *scope;
@property (copy, nonatomic) NSArray *entries;
@property (assign, nonatomic) unsigned long long bytes;
@end

@implementation OVKMusicCacheController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = OVKL(@"Кэш музыки");
    self.scope = OVKSelectedMusicCacheScope();
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cacheChanged:) name:OVKMusicCacheChanged object:nil];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    OVKThemeTable(self.tableView);
    [self cacheChanged:nil];
}
- (void)cacheChanged:(NSNotification *)note {
    if (note.userInfo[@"progress"]) return;
    self.entries = OVKMusicCacheEntries(self.scope);
    unsigned long long bytes = 0;
    for (NSDictionary *entry in self.entries) bytes += [entry[@"size"] unsignedLongLongValue];
    self.bytes = bytes;
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 2; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    OVKThemeCell(cell);
    if (path.row==0) {
        cell.textLabel.text = OVKL(@"Загруженные треки");
        cell.detailTextLabel.text = [NSString stringWithFormat:OVKL(@"Треков: %lu · %@"),(unsigned long)self.entries.count,OVKMusicSize(self.bytes)];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.textLabel.text = OVKL(@"Очистить Кэш Музыки");
        cell.textLabel.textColor = self.entries.count ? [UIColor colorWithRed:.75 green:.18 blue:.18 alpha:1] : OVKThemeSecondary();
        cell.selectionStyle = self.entries.count ? UITableViewCellSelectionStyleBlue : UITableViewCellSelectionStyleNone;
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.row==0) {
        [self.navigationController pushViewController:[[OVKCachedTracksController alloc] initWithScope:self.scope] animated:YES];
    } else if (self.entries.count) {
        NSString *clear = [NSString stringWithFormat:OVKL(@"Очистить %@"),OVKMusicSize(self.bytes)];
        NSString *warning = OVKL(@"Вы больше не сможете слушать эти треки офлайн, пока не скачаете их снова.");
        UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:warning delegate:self cancelButtonTitle:OVKL(@"Отмена") destructiveButtonTitle:clear otherButtonTitles:nil];
        [sheet showInView:self.navigationController.view];
    }
}
- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
    if (index!=sheet.destructiveButtonIndex) return;
    [OVKMedia cancelCurrentMusicCacheDownloads];
    OVKDeleteCachedTracks(self.scope,OVKMusicCacheEntries(self.scope));
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end
