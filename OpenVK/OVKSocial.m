#import "OVKSocial.h"
#import "OVKSocialModel.h"
#import "OVKAPI.h"
#import "OVKMedia.h"
#import "OVKPerformance.h"
#import <math.h>
#import <stdlib.h>
static NSString *SocialName(NSDictionary *person) {
    NSString *name=OVKString(person[@"name"]); if (name.length) return name;
    return [[NSString stringWithFormat:@"%@ %@",OVKString(person[@"first_name"]),OVKString(person[@"last_name"])] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}
@interface OVKSocialController () <UITableViewDataSource,UITableViewDelegate,UISearchBarDelegate>
@property (copy, nonatomic) NSString *section;
@property (strong, nonatomic) UITableView *table;
@property (strong, nonatomic) UIRefreshControl *refresh;
@property (strong, nonatomic) UILabel *notice;
@property (strong, nonatomic) UIButton *moreButton;
@property (strong, nonatomic) UISearchBar *search;
@property (strong, nonatomic) NSMutableArray *items;
@property (strong, nonatomic) NSMutableDictionary *people;
@property (copy, nonatomic) NSString *query;
@property (assign, nonatomic) NSUInteger generation;
@property (assign, nonatomic) NSUInteger offset;
@property (assign, nonatomic) BOOL loading;
@property (assign, nonatomic) BOOL more;
@property (assign, nonatomic) BOOL opening;
@property (assign, nonatomic) NSTimeInterval lastViewed;
@end
@implementation OVKSocialController
- (id)initWithSection:(NSString *)section { self=[super initWithNibName:nil bundle:nil]; if (self) { self.section=section; self.query=@""; self.items=[NSMutableArray array]; self.people=[NSMutableDictionary dictionary]; self.title=OVKMenuTitle(section); } return self; }
- (BOOL)isGroups { return [self.section isEqualToString:@"groups"]; }
- (void)viewDidLoad {
    [super viewDidLoad]; OVKConfigureEdges(self);
    self.table=[[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain]; self.table.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; self.table.dataSource=self; self.table.delegate=self; self.table.rowHeight=[self isGroups] ? 82 : 112; [self.view addSubview:self.table];
    self.refresh=[[UIRefreshControl alloc] init]; [self.refresh addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged]; [self.table addSubview:self.refresh];
    self.notice=[[UILabel alloc] initWithFrame:CGRectMake(0,0,320,44)]; self.notice.font=[UIFont systemFontOfSize:12]; self.notice.numberOfLines=2; self.notice.textAlignment=NSTextAlignmentCenter;
    UIView *header=[[UIView alloc] initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,[self isGroups] ? 88 : 44)];
    if ([self isGroups]) { self.search=[[UISearchBar alloc] initWithFrame:CGRectMake(0,0,header.bounds.size.width,44)]; self.search.autoresizingMask=UIViewAutoresizingFlexibleWidth; self.search.placeholder=OVKL(@"Поиск групп"); self.search.delegate=self; [header addSubview:self.search]; }
    self.notice.frame=CGRectMake(0,[self isGroups] ? 44 : 0,header.bounds.size.width,44); self.notice.autoresizingMask=UIViewAutoresizingFlexibleWidth; [header addSubview:self.notice]; self.table.tableHeaderView=header;
    self.moreButton=[UIButton buttonWithType:UIButtonTypeCustom]; self.moreButton.frame=CGRectMake(0,0,320,44); self.moreButton.titleLabel.font=[UIFont boldSystemFontOfSize:14]; [self.moreButton addTarget:self action:@selector(moreTapped) forControlEvents:UIControlEventTouchUpInside]; self.table.tableFooterView=self.moreButton;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:@"OVKThemeChanged" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(languageChanged:) name:@"OVKLanguageChanged" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(groupsChanged:) name:@"OVKGroupsChanged" object:nil];
    if (![self isGroups]) self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:OVKL(@"Прочитано") style:UIBarButtonItemStylePlain target:self action:@selector(markViewed)];
    [self themeChanged:nil]; [self reload];
}
- (void)themeChanged:(NSNotification *)note { OVKThemeTable(self.table); self.view.backgroundColor=OVKThemeBackground(); self.notice.backgroundColor=OVKThemeSurface(); self.notice.textColor=OVKThemeSecondary(); self.search.tintColor=OVKThemeAccent(); [self.moreButton setTitleColor:OVKThemeAccent() forState:UIControlStateNormal]; [self.table reloadData]; }
- (void)languageChanged:(NSNotification *)note { self.title=OVKMenuTitle(self.section); self.search.placeholder=OVKL(@"Поиск групп"); self.navigationItem.rightBarButtonItem.title=OVKL(@"Прочитано"); [self.moreButton setTitle:self.more ? OVKL(@"Показать ещё") : OVKL(@"Обновить") forState:UIControlStateNormal]; [self.table reloadData]; }
- (void)groupsChanged:(NSNotification *)note { if ([self isGroups] && !self.query.length) [self reload]; }
- (void)reload { [self fetch:NO]; }
- (void)moreTapped { if (!self.loading) [self fetch:self.more]; }
- (void)fetch:(BOOL)append {
    if (append && self.loading) return;
    self.loading=YES; NSUInteger generation=++self.generation; NSUInteger count=OVKPageSize();
    self.notice.text=OVKL(@"Загрузка…"); self.moreButton.enabled=NO;
    NSMutableDictionary *parameters=[@{@"count":@(count),@"offset":@(append ? self.offset : 0)} mutableCopy];
    NSString *method=@"notifications.get";
    if ([self isGroups]) { method=self.query.length ? @"groups.search" : @"groups.get"; parameters[@"extended"]=@1; parameters[@"fields"]=@"photo_100,members_count,is_member,description,verified"; if (self.query.length) parameters[@"q"]=self.query; else parameters[@"user_id"]=[OVKAPI shared].userID ?: @0; }
    __weak OVKSocialController *weakSelf=self;
    [[OVKAPI shared] call:method parameters:parameters completion:^(id result,NSError *error) {
        OVKSocialController *page=weakSelf; if (!page || generation!=page.generation) return;
        page.loading=NO; page.moreButton.enabled=YES; [page.refresh endRefreshing];
        if (error) { page.notice.text=error.localizedDescription; [page.moreButton setTitle:OVKL(@"Повторить") forState:UIControlStateNormal]; return; }
        if (![result isKindOfClass:[NSArray class]] && ![OVKDictionary(result)[@"items"] isKindOfClass:[NSArray class]]) { page.notice.text=OVKL(@"Формат ответа этого сервера не поддерживается"); [page.moreButton setTitle:OVKL(@"Повторить") forState:UIControlStateNormal]; return; }
        NSArray *incoming=OVKSocialItems(result); NSDictionary *response=OVKDictionary(result);
        if (!append) page.lastViewed=[OVKString(response[@"last_viewed"]) doubleValue];
        if (!append) { [page.items removeAllObjects]; [page.people removeAllObjects]; page.offset=0; }
        [page.items addObjectsFromArray:incoming]; page.offset+=incoming.count;
        for (id value in OVKArray(response[@"profiles"])) { NSDictionary *person=OVKDictionary(value); if (person[@"id"]) page.people[OVKString(person[@"id"])]=person; }
        for (id value in OVKArray(response[@"groups"])) { NSDictionary *group=OVKDictionary(value); if (group[@"id"]) page.people[OVKString(@(-[OVKString(group[@"id"]) longLongValue]))]=group; }
        page.more=![OVKAPI shared].demo && incoming.count>=count && (!response[@"count"] || page.offset<[OVKString(response[@"count"]) integerValue]);
        page.notice.text=page.items.count ? OVKL(@"Потяните вниз для обновления") : OVKL([page isGroups] ? @"Группы не найдены" : @"Новых уведомлений нет");
        [page.moreButton setTitle:page.more ? OVKL(@"Показать ещё") : OVKL(@"Обновить") forState:UIControlStateNormal]; [page.table reloadData];
    }];
}
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text { self.query=[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]; ++self.generation; self.loading=NO; [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reload) object:nil]; [self performSelector:@selector(reload) withObject:nil afterDelay:.4]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reload) object:nil]; [self reload]; }
- (void)markViewed { if (self.loading || self.opening) return; self.navigationItem.rightBarButtonItem.enabled=NO; __weak OVKSocialController *weakSelf=self; [[OVKAPI shared] call:@"notifications.markAsViewed" parameters:@{} completion:^(id result,NSError *error) { OVKSocialController *page=weakSelf; if (!page) return; page.navigationItem.rightBarButtonItem.enabled=YES; if (error) OVKAlert(OVKL(@"Ответы"),error.localizedDescription); else [page reload]; }]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.items.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"social"];
    if (!cell) { cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"social"]; OVKRemoteImageView *avatar=[[OVKRemoteImageView alloc] initWithFrame:CGRectMake(10,12,54,54)]; avatar.tag=501; avatar.contentMode=UIViewContentModeScaleAspectFill; avatar.clipsToBounds=YES; avatar.maxPixelSize=108; [cell.contentView addSubview:avatar]; cell.indentationLevel=4; cell.indentationWidth=16; }
    NSDictionary *item=self.items[indexPath.row]; NSNumber *actor=OVKNotificationActor(item); NSDictionary *person=[self isGroups] ? item : OVKDictionary(self.people[OVKString(actor)]);
    NSString *name=SocialName(person); cell.textLabel.text=name.length ? name : ([self isGroups] ? OVKL(@"Группа") : OVKL(@"Уведомление")); cell.textLabel.font=[UIFont boldSystemFontOfSize:14]; cell.textLabel.numberOfLines=1;
    if ([self isGroups]) cell.detailTextLabel.text=[NSString stringWithFormat:OVKL(@"Участников: %@"),OVKString(item[@"members_count"]).length ? OVKString(item[@"members_count"]) : @"—"];
    else {
        NSDictionary *feedback=OVKDictionary(item[@"feedback"]); NSString *text=OVKString(feedback[@"text"]); NSArray *feedbackItems=OVKArray(feedback[@"items"]); if (!text.length && feedbackItems.count) text=OVKString(OVKDictionary(feedbackItems[0])[@"text"]);
        NSDate *date=[NSDate dateWithTimeIntervalSince1970:[OVKString(item[@"date"]) doubleValue]]; static NSDateFormatter *formatter; if (!formatter) { formatter=[[NSDateFormatter alloc] init]; formatter.dateFormat=@"dd.MM.yy HH:mm"; }
        cell.detailTextLabel.text=[NSString stringWithFormat:@"%@%@\n%@",OVKNotificationSummary(item),text.length ? [@"\n" stringByAppendingString:text] : @"",[formatter stringFromDate:date]];
    }
    cell.detailTextLabel.numberOfLines=4; cell.detailTextLabel.font=[UIFont systemFontOfSize:12]; cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; OVKThemeCell(cell);
    if (![self isGroups] && self.lastViewed>0 && [OVKString(item[@"date"]) doubleValue]>self.lastViewed) cell.backgroundView.backgroundColor=OVKDarkTheme() ? [UIColor colorWithRed:.20 green:.25 blue:.31 alpha:1] : [UIColor colorWithRed:.90 green:.94 blue:.97 alpha:1];
    OVKRemoteImageView *avatar=(OVKRemoteImageView *)[cell.contentView viewWithTag:501]; [avatar load:OVKString(person[@"photo_100"] ?: person[@"photo_50"])]; if (!avatar.source.length) avatar.image=[UIImage imageNamed:[self isGroups] ? @"GroupPlaceholder" : @"Answers"];
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES]; [self.view endEditing:YES]; if (self.opening) return;
    NSDictionary *item=self.items[path.row]; if ([self isGroups]) { long long identifier=[OVKString(item[@"id"]) longLongValue]; if (identifier>0) [self.navigationController pushViewController:[[OVKGroupController alloc] initWithGroup:@(identifier) title:SocialName(item)] animated:YES]; return; }
    NSDictionary *post=OVKNotificationPost(item);
    if (post) {
        self.opening=YES; __weak OVKSocialController *weakSelf=self;
        [[OVKAPI shared] call:@"wall.getById" parameters:@{@"posts":[NSString stringWithFormat:@"%@_%@",post[@"owner_id"],post[@"id"]],@"extended":@1} completion:^(id result,NSError *error) {
            OVKSocialController *page=weakSelf; if (!page) return; page.opening=NO; NSArray *posts=OVKSocialItems(result);
            if (error || !posts.count) { OVKAlert(OVKL(@"Запись"),error.localizedDescription ?: OVKL(@"Запись недоступна")); return; }
            if (page.navigationController.topViewController==page) [page.navigationController pushViewController:[[OVKListController alloc] initWithPostObject:posts[0] profiles:OVKArray(OVKDictionary(result)[@"profiles"]) groups:OVKArray(OVKDictionary(result)[@"groups"])] animated:YES];
        }]; return;
    }
    NSNumber *actor=OVKNotificationActor(item); if (actor.longLongValue>0) [self.navigationController pushViewController:[[OVKListController alloc] initWithMode:@"profile" identifier:actor title:SocialName(OVKDictionary(self.people[OVKString(actor)]))] animated:YES];
    else if (actor.longLongValue<0) [self.navigationController pushViewController:[[OVKGroupController alloc] initWithGroup:@(-actor.longLongValue) title:SocialName(OVKDictionary(self.people[OVKString(actor)]))] animated:YES];
    else OVKAlert(OVKL(@"Уведомление"),OVKNotificationSummary(item));
}
- (void)dealloc { [NSObject cancelPreviousPerformRequestsWithTarget:self]; [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end

// Preserve the base wall controller's alert handling for likes and post actions.
@interface OVKListController (SocialAlertForwarding)
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex;
@end
@interface OVKGroupController () <UIAlertViewDelegate>
@property (strong, nonatomic) NSNumber *groupID;
@property (strong, nonatomic) NSDictionary *group;
@property (strong, nonatomic) UIButton *membership;
@property (assign, nonatomic) BOOL changingMembership;
@property (assign, nonatomic) NSUInteger groupGeneration;
@property (assign, nonatomic) CGFloat headerWidth;
@end
@implementation OVKGroupController
- (id)initWithGroup:(NSNumber *)groupID title:(NSString *)title { self=[super initWithMode:@"groupWall" identifier:@(-llabs(groupID.longLongValue)) title:title]; if (self) self.groupID=@(llabs(groupID.longLongValue)); return self; }
- (void)viewDidLoad { [super viewDidLoad]; [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(groupThemeChanged:) name:@"OVKThemeChanged" object:nil]; [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(groupThemeChanged:) name:@"OVKLanguageChanged" object:nil]; self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(loadGroup)]; [self updateGroupHeader]; [self loadGroup]; }
- (void)groupThemeChanged:(NSNotification *)note { [self updateGroupHeader]; }
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; if (fabs(self.headerWidth-[self wallContentWidth])>.5) [self updateGroupHeader]; }
- (void)loadGroup {
    self.navigationItem.rightBarButtonItem.enabled=NO; NSUInteger generation=++self.groupGeneration; __weak OVKGroupController *weakSelf=self;
    [[OVKAPI shared] call:@"groups.getById" parameters:@{@"group_id":self.groupID,@"fields":@"description,members_count,is_member,can_post,photo_100,photo_200,verified"} completion:^(id result,NSError *error) {
        OVKGroupController *page=weakSelf; if (!page || generation!=page.groupGeneration) return;
        page.navigationItem.rightBarButtonItem.enabled=YES;
        NSArray *groups=[result isKindOfClass:[NSArray class]] ? OVKSocialItems(result) : OVKSocialItems(OVKDictionary(result)[@"groups"] ?: result);
        if (error || !groups.count) { page.changingMembership=NO; [page updateGroupHeader]; if (error) OVKAlert(OVKL(@"Группа"),error.localizedDescription); return; }
        page.group=groups[0]; page.changingMembership=NO; page.title=SocialName(page.group); [page updateGroupHeader];
    }];
}
- (void)updateGroupHeader {
    CGFloat width=[self wallContentWidth]; if (width<1) return; self.headerWidth=width;
    UIView *header=[[UIView alloc] initWithFrame:CGRectMake(0,0,width,228)]; header.backgroundColor=OVKDarkTheme() ? [UIColor colorWithRed:.14 green:.18 blue:.23 alpha:1] : [UIColor colorWithRed:.20 green:.26 blue:.33 alpha:1];
    OVKRemoteImageView *avatar=[[OVKRemoteImageView alloc] initWithFrame:CGRectMake(12,12,76,76)]; avatar.contentMode=UIViewContentModeScaleAspectFill; avatar.clipsToBounds=YES; [header addSubview:avatar]; [avatar load:OVKString(self.group[@"photo_200"] ?: self.group[@"photo_100"])]; if (!avatar.source.length) avatar.image=[UIImage imageNamed:@"GroupPlaceholder"];
    UILabel *name=[[UILabel alloc] initWithFrame:CGRectMake(100,10,width-112,44)]; name.backgroundColor=[UIColor clearColor]; name.textColor=[UIColor whiteColor]; name.font=[UIFont boldSystemFontOfSize:16]; name.numberOfLines=2; name.text=SocialName(self.group).length ? SocialName(self.group) : self.title; if ([OVKString(self.group[@"verified"]) boolValue]) name.text=[name.text stringByAppendingString:@" ✓"]; [header addSubview:name];
    UILabel *count=[[UILabel alloc] initWithFrame:CGRectMake(100,58,width-112,28)]; count.backgroundColor=[UIColor clearColor]; count.textColor=[UIColor lightGrayColor]; count.font=[UIFont systemFontOfSize:12]; count.text=[NSString stringWithFormat:OVKL(@"Участников: %@"),OVKString(self.group[@"members_count"]).length ? OVKString(self.group[@"members_count"]) : @"—"]; [header addSubview:count];
    self.membership=[UIButton buttonWithType:UIButtonTypeCustom]; self.membership.frame=CGRectMake(12,100,(width-36)/2,33); self.membership.titleLabel.font=[UIFont boldSystemFontOfSize:14]; [self.membership setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal]; [self.membership setBackgroundImage:[OVKThemeChrome(@"ProfileBlueButton") resizableImageWithCapInsets:UIEdgeInsetsMake(6,7,6,7)] forState:UIControlStateNormal]; [self.membership addTarget:self action:@selector(membershipTapped) forControlEvents:UIControlEventTouchUpInside];
    BOOL known=[self.group[@"is_member"] respondsToSelector:@selector(boolValue)]; [self.membership setTitle:self.changingMembership ? OVKL(@"Обновление…") : OVKL([OVKString(self.group[@"is_member"]) boolValue] ? @"Вы подписаны" : @"Подписаться") forState:UIControlStateNormal]; self.membership.enabled=known && !self.changingMembership; self.membership.alpha=self.membership.enabled ? 1 : .5; [header addSubview:self.membership];
    UIButton *photos=[UIButton buttonWithType:UIButtonTypeCustom]; photos.frame=CGRectMake(24+(width-36)/2,100,(width-36)/2,33); photos.titleLabel.font=[UIFont boldSystemFontOfSize:14]; [photos setTitle:OVKL(@"Фотографии") forState:UIControlStateNormal]; [photos setTitleColor:OVKThemeText() forState:UIControlStateNormal]; [photos setBackgroundImage:[OVKThemeChrome(@"FooterButton") resizableImageWithCapInsets:UIEdgeInsetsMake(15,7,15,7)] forState:UIControlStateNormal]; [photos addTarget:self action:@selector(openGroupPhotos) forControlEvents:UIControlEventTouchUpInside]; [header addSubview:photos];
    UILabel *description=[[UILabel alloc] initWithFrame:CGRectMake(12,145,width-24,72)]; description.backgroundColor=[UIColor clearColor]; description.textColor=[UIColor colorWithWhite:.9 alpha:1]; description.font=[UIFont systemFontOfSize:13]; description.numberOfLines=4; description.text=OVKString(self.group[@"description"]); [header addSubview:description]; [self setWallHeaderView:header];
}
- (void)openGroupPhotos { [self.navigationController pushViewController:[[OVKLibraryController alloc] initWithKind:@"photo" identifier:@(-self.groupID.longLongValue)] animated:YES]; }
- (void)membershipTapped { if (self.changingMembership) return; if ([OVKString(self.group[@"is_member"]) boolValue]) { UIAlertView *alert=[[UIAlertView alloc] initWithTitle:OVKL(@"Отписаться от группы?") message:self.title delegate:self cancelButtonTitle:OVKL(@"Отмена") otherButtonTitles:OVKL(@"Отписаться"),nil]; alert.tag=734; [alert show]; } else [self changeMembership:NO]; }
- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index { if (alert.tag==734) { if (index==1) [self changeMembership:YES]; } else [super alertView:alert clickedButtonAtIndex:index]; }
- (void)changeMembership:(BOOL)leave {
    if (self.changingMembership) return; self.changingMembership=YES; self.navigationItem.rightBarButtonItem.enabled=NO; [self updateGroupHeader]; __weak OVKGroupController *weakSelf=self;
    [[OVKAPI shared] call:leave ? @"groups.leave" : @"groups.join" parameters:@{@"group_id":self.groupID} completion:^(id result,NSError *error) {
        OVKGroupController *page=weakSelf; if (!page) return;
        if (error) { page.changingMembership=NO; page.navigationItem.rightBarButtonItem.enabled=YES; [page updateGroupHeader]; OVKAlert(OVKL(@"Группа"),error.localizedDescription); return; }
        [page loadGroup]; [[NSNotificationCenter defaultCenter] postNotificationName:@"OVKGroupsChanged" object:nil];
    }];
}
@end
