#import "OVKLanguage.h"
#import "OVKWall.h"
#import "OVKWallModel.h"
#import "OVKAPI.h"
#import "OVKUI.h"
#import "OVKMedia.h"
@interface OVKComposeController ()
@property (strong, nonatomic) UITextView *textView;
@property (assign, nonatomic) BOOL sending;
@property (copy, nonatomic) NSString *pendingText;
@property (strong, nonatomic) NSNumber *randomID;
@end
@implementation OVKComposeController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=self.message ? OVKL(@"Сообщение") : (self.postID ? OVKL(@"Комментарий") : OVKL(@"Новая запись"));
    self.view.backgroundColor=OVKThemeSurface();
    OVKConfigureEdges(self);
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:OVKL(@"Отмена") style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:self.message ? OVKL(@"Отправить") : (self.postID ? OVKL(@"Ответить") : OVKL(@"Опубликовать")) style:UIBarButtonItemStyleDone target:self action:@selector(send)];
    CGFloat top=self.replyName.length ? 30 : 0;
    if (top) { UILabel *reply=[[UILabel alloc] initWithFrame:CGRectMake(10,0,self.view.bounds.size.width-20,30)]; reply.autoresizingMask=UIViewAutoresizingFlexibleWidth; reply.text=[NSString stringWithFormat:OVKL(@"Ответ: %@"),self.replyName]; reply.font=[UIFont systemFontOfSize:12]; reply.textColor=OVKBlue(); reply.backgroundColor=[UIColor clearColor]; [self.view addSubview:reply]; }
    self.textView=[[UITextView alloc] initWithFrame:CGRectMake(0,top,self.view.bounds.size.width,self.view.bounds.size.height-top)]; self.textView.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; self.textView.font=[UIFont systemFontOfSize:16]; self.textView.backgroundColor=OVKThemeSurface(); self.textView.textColor=OVKThemeText(); self.textView.keyboardAppearance=OVKDarkTheme() ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault; [self.view addSubview:self.textView];
    UIToolbar *bar=[[UIToolbar alloc] initWithFrame:CGRectMake(0,0,320,38)]; bar.items=@[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],[[UIBarButtonItem alloc] initWithTitle:OVKL(@"Готово") style:UIBarButtonItemStyleDone target:self action:@selector(hideKeyboard)]]; self.textView.inputAccessoryView=bar;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboard:) name:UIKeyboardWillChangeFrameNotification object:nil]; [self.textView becomeFirstResponder];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.navigationController.navigationBar setBackgroundImage:[UIImage imageNamed:@"MusicNavigation"] forBarMetrics:UIBarMetricsDefault]; self.navigationController.navigationBar.barStyle=UIBarStyleBlack; [self.navigationItem.leftBarButtonItem setBackgroundImage:OVKThemeStretch(@"MusicButton") forState:UIControlStateNormal barMetrics:UIBarMetricsDefault]; }
- (void)hideKeyboard { [self.textView resignFirstResponder]; }
- (void)keyboard:(NSNotification *)note { CGRect frame=[self.view convertRect:[note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil]; CGFloat bottom=MAX(0,CGRectGetMaxY(self.textView.frame)-CGRectGetMinY(frame)); self.textView.contentInset=UIEdgeInsetsMake(0,0,bottom,0); self.textView.scrollIndicatorInsets=self.textView.contentInset; }
- (void)cancel { if (!self.sending) [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)send {
    if (self.sending) return;
    if (![self.pendingText isEqualToString:self.textView.text]) { self.pendingText=self.textView.text; self.randomID=@(arc4random_uniform(2147483646)+1); }
    NSString *kind=self.message ? @"message" : (self.postID ? @"comment" : @"post"); NSError *validation=nil;
    NSDictionary *params=OVKWallWriteParameters(kind,self.identifier,self.postID,self.replyID,self.textView.text,self.randomID,&validation);
    if (!params) { OVKAlert(OVKL(@"Не отправлено"),validation.localizedDescription); return; }
    if ([OVKAPI shared].demo) { OVKAlert(OVKL(@"Демонстрация"),OVKL(@"Для публикации войдите в свой аккаунт.")); return; }
    self.sending=YES; self.textView.editable=NO; self.navigationItem.leftBarButtonItem.enabled=NO; self.navigationItem.rightBarButtonItem.enabled=NO;
    NSString *method=self.message ? @"messages.send" : (self.postID ? @"wall.createComment" : @"wall.post");
    [[OVKAPI shared] call:method parameters:params completion:^void(id result,NSError *error) {
        self.sending=NO; self.textView.editable=YES; self.navigationItem.leftBarButtonItem.enabled=YES; self.navigationItem.rightBarButtonItem.enabled=YES;
        if (error) { OVKAlert(OVKL(@"Не отправлено"),[NSString stringWithFormat:OVKL(@"%@\nТекст сохранён в редакторе. При обрыве сети проверьте, появилась ли запись, прежде чем повторять отправку."),error.localizedDescription]); return; }
        [[NSNotificationCenter defaultCenter] postNotificationName:@"OVKWallChanged" object:self.postID ? @{@"owner_id":self.identifier,@"post_id":self.postID} : @{@"owner_id":self.identifier}];
        if (self.sent) self.sent(); [self dismissViewControllerAnimated:YES completion:nil];
    }];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end
@interface OVKCommentsController ()
@property (strong, nonatomic) NSDictionary *post;
@property (strong, nonatomic) NSDictionary *reference;
@property (strong, nonatomic) NSMutableArray *items;
@property (strong, nonatomic) NSMutableDictionary *people;
@property (strong, nonatomic) UILabel *notice;
@property (strong, nonatomic) UIButton *moreButton;
@property (strong, nonatomic) NSDictionary *selectedComment;
@property (assign, nonatomic) NSInteger replyAction;
@property (assign, nonatomic) NSInteger mediaAction;
@property (assign, nonatomic) NSInteger profileAction;
@property (assign, nonatomic) BOOL loading;
@property (assign, nonatomic) BOOL more;
@property (assign, nonatomic) BOOL canPost;
@property (assign, nonatomic) NSUInteger generation;
@end
@implementation OVKCommentsController
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; OVKThemeTable(self.tableView); self.notice.backgroundColor=OVKThemeSurface(); self.notice.textColor=OVKThemeSecondary(); [self.moreButton setTitleColor:OVKThemeAccent() forState:UIControlStateNormal]; [self.tableView reloadData]; }
- (id)initWithPost:(NSDictionary *)post { self=[super initWithStyle:UITableViewStylePlain]; if (self) { self.post=post; self.reference=OVKPostReference(post); self.items=[NSMutableArray array]; self.people=[NSMutableDictionary dictionary]; self.title=OVKL(@"Комментарии"); self.canPost=![OVKDictionary(post[@"comments"])[@"can_post"] respondsToSelector:@selector(boolValue)] || [OVKDictionary(post[@"comments"])[@"can_post"] boolValue]; } return self; }
- (void)viewDidLoad {
    [super viewDidLoad]; OVKConfigureEdges(self);
    self.tableView.separatorColor=[UIColor colorWithWhite:.87 alpha:1]; self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:OVKL(@"Ответить") style:UIBarButtonItemStylePlain target:self action:@selector(addComment)]; self.navigationItem.rightBarButtonItem.enabled=self.canPost;
    self.notice=[[UILabel alloc] initWithFrame:CGRectMake(0,0,320,44)]; self.notice.numberOfLines=2; self.notice.textAlignment=NSTextAlignmentCenter; self.notice.font=[UIFont systemFontOfSize:12]; self.notice.textColor=[UIColor grayColor]; self.notice.backgroundColor=[UIColor colorWithPatternImage:[UIImage imageNamed:@"SectionBar"]]; self.tableView.tableHeaderView=self.notice;
    self.refreshControl=[[UIRefreshControl alloc] init]; [self.refreshControl addTarget:self action:@selector(refreshComments) forControlEvents:UIControlEventValueChanged];
    self.moreButton=[UIButton buttonWithType:UIButtonTypeCustom]; self.moreButton.frame=CGRectMake(0,0,320,44); [self.moreButton setTitleColor:OVKBlue() forState:UIControlStateNormal]; self.moreButton.titleLabel.font=[UIFont boldSystemFontOfSize:13]; [self.moreButton addTarget:self action:@selector(loadMore) forControlEvents:UIControlEventTouchUpInside]; self.tableView.tableFooterView=self.moreButton;
    [self refreshComments];
}
- (void)refreshComments { if (self.loading) { [self.refreshControl endRefreshing]; return; } [self fetch:NO]; }
- (void)loadMore { if (!self.loading) [self fetch:self.more]; }
- (void)fetch:(BOOL)append {
    if (!self.reference) { self.notice.text=OVKL(@"Не удалось определить адрес записи"); [self.refreshControl endRefreshing]; return; }
    self.loading=YES; NSUInteger generation=++self.generation; self.notice.text=OVKL(@"Загрузка комментариев…");
    NSMutableDictionary *params=[self.reference mutableCopy]; [params addEntriesFromDictionary:@{@"extended":@1,@"fields":@"photo_100,photo_50",@"sort":@"asc",@"count":@30,@"offset":@(append ? self.items.count : 0)}];
    [[OVKAPI shared] call:@"wall.getComments" parameters:params completion:^void(id result,NSError *error) {
        if (generation!=self.generation) return; self.loading=NO; [self.refreshControl endRefreshing];
        if (error) { self.notice.text=error.localizedDescription; [self.moreButton setTitle:OVKL(@"Повторить") forState:UIControlStateNormal]; return; }
        NSDictionary *response=OVKDictionary(result);
        if (![response[@"items"] isKindOfClass:[NSArray class]]) { self.notice.text=OVKL(@"Неизвестный формат комментариев"); return; }
        if (!append) { [self.items removeAllObjects]; [self.people removeAllObjects]; }
        NSArray *incoming=OVKArray(response[@"items"]); for (id value in incoming) if ([value isKindOfClass:[NSDictionary class]]) [self.items addObject:value];
        for (NSDictionary *person in OVKArray(response[@"profiles"])) if ([person isKindOfClass:[NSDictionary class]] && person[@"id"]) self.people[OVKString(person[@"id"])]=person;
        for (NSDictionary *group in OVKArray(response[@"groups"])) if ([group isKindOfClass:[NSDictionary class]] && group[@"id"]) self.people[OVKString(@(-[group[@"id"] longLongValue]))]=group;
        if ([response[@"can_post"] respondsToSelector:@selector(boolValue)]) self.canPost=[response[@"can_post"] boolValue]; self.navigationItem.rightBarButtonItem.enabled=self.canPost;
        NSUInteger total=[OVKString(response[@"count"]) integerValue]; self.more=![OVKAPI shared].demo && incoming.count>=30 && self.items.count<total;
        self.notice.text=self.items.count ? [NSString stringWithFormat:OVKL(@"Комментариев: %lu"),(unsigned long)total] : OVKL(@"Комментариев пока нет"); if (!self.canPost) self.notice.text=OVKL(@"Комментарии закрыты для публикации");
        [self.moreButton setTitle:self.more ? OVKL(@"Показать ещё") : OVKL(@"Обновить") forState:UIControlStateNormal]; [self.tableView reloadData];
    }];
}
- (NSString *)nameFor:(NSDictionary *)comment { NSDictionary *person=OVKDictionary(self.people[OVKString(comment[@"from_id"])]); NSString *name=OVKString(person[@"name"]); if (!name.length) name=[[NSString stringWithFormat:@"%@ %@",OVKString(person[@"first_name"]),OVKString(person[@"last_name"])] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]; return name.length ? name : OVKL(@"Пользователь"); }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.items.count; }
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path { NSDictionary *item=self.items[path.row]; CGSize text=[OVKString(item[@"text"]) sizeWithFont:[UIFont systemFontOfSize:14] constrainedToSize:CGSizeMake(tableView.bounds.size.width-72,20000) lineBreakMode:NSLineBreakByWordWrapping]; return MAX(82,ceil(text.height)+66)+(OVKPlayableAttachments(item).count ? 26 : 0); }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    NSDictionary *item=self.items[path.row]; UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil]; CGFloat width=tableView.bounds.size.width;
    OVKRemoteImageView *avatar=[[OVKRemoteImageView alloc] initWithFrame:CGRectMake(8,10,42,42)]; avatar.contentMode=UIViewContentModeScaleAspectFill; avatar.clipsToBounds=YES; NSDictionary *person=OVKDictionary(self.people[OVKString(item[@"from_id"])]); [avatar load:OVKString(person[@"photo_100"] ?: person[@"photo_50"])]; [cell.contentView addSubview:avatar]; if ([OVKString(item[@"from_id"]) longLongValue]>0) { avatar.userInteractionEnabled=YES; avatar.tag=[OVKString(item[@"from_id"]) integerValue]; [avatar addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(commentAvatarTapped:)]]; }
    UILabel *name=[[UILabel alloc] initWithFrame:CGRectMake(60,8,width-72,20)]; name.font=[UIFont boldSystemFontOfSize:13]; name.textColor=OVKBlue(); name.text=[self nameFor:item]; [cell.contentView addSubview:name];
    NSString *text=OVKString(item[@"text"]); CGSize size=[text sizeWithFont:[UIFont systemFontOfSize:14] constrainedToSize:CGSizeMake(width-72,20000) lineBreakMode:NSLineBreakByWordWrapping];
    UILabel *body=[[UILabel alloc] initWithFrame:CGRectMake(60,32,width-72,MAX(18,ceil(size.height)))]; body.font=[UIFont systemFontOfSize:14]; body.numberOfLines=0; body.text=text; [cell.contentView addSubview:body];
    UILabel *stamp=[[UILabel alloc] initWithFrame:CGRectMake(60,CGRectGetMaxY(body.frame)+6,width-72,18)]; stamp.font=[UIFont systemFontOfSize:11]; stamp.textColor=[UIColor grayColor]; NSTimeInterval time=[OVKString(item[@"date"]) doubleValue]; NSDateFormatter *format=[[NSDateFormatter alloc] init]; format.dateFormat=OVKLanguageIsEnglish() ? @"d MMM HH:mm" : @"d MMM 'в' HH:mm"; format.locale=[[NSLocale alloc] initWithLocaleIdentifier:OVKLanguageIsEnglish() ? @"en_US" : @"ru_RU"]; stamp.text=[NSString stringWithFormat:@"%@%@",time>0 ? [format stringFromDate:[NSDate dateWithTimeIntervalSince1970:time]] : @"",OVKString(item[@"reply_to_comment"]).length ? OVKL(@" · ответ") : @""]; [cell.contentView addSubview:stamp];
    if (OVKPlayableAttachments(item).count) { UILabel *media=[[UILabel alloc] initWithFrame:CGRectMake(60,CGRectGetMaxY(stamp.frame)+3,width-72,20)]; media.text=OVKL(@"Прикреплены вложения"); media.font=[UIFont systemFontOfSize:11]; media.textColor=OVKBlue(); [cell.contentView addSubview:media]; }
    OVKThemeCell(cell); for (UIView *view in cell.contentView.subviews) if ([view isKindOfClass:[UILabel class]]) { UILabel *label=(UILabel *)view; label.backgroundColor=[UIColor clearColor]; label.textColor=label==name ? OVKThemeAccent() : (label==stamp ? OVKThemeSecondary() : OVKThemeText()); }
    return cell;
}
- (void)commentAvatarTapped:(UITapGestureRecognizer *)tap { NSNumber *identifier=@(tap.view.tag); if (identifier.longLongValue>0) [self.navigationController pushViewController:[[OVKListController alloc] initWithMode:@"profile" identifier:identifier title:OVKL(@"Профиль")] animated:YES]; }
- (void)addComment { [self composeReply:nil]; }
- (void)composeReply:(NSDictionary *)comment {
    if (!self.canPost || !self.reference) return;
    OVKComposeController *editor=[[OVKComposeController alloc] init]; editor.identifier=self.reference[@"owner_id"]; editor.postID=self.reference[@"post_id"]; if (comment) { editor.replyID=@([OVKString(comment[@"id"]) longLongValue]); editor.replyName=[self nameFor:comment]; }
    __weak OVKCommentsController *weakSelf=self; editor.sent=^{ [weakSelf refreshComments]; };
    UINavigationController *nav=[[OVKNavigationController alloc] initWithRootViewController:editor]; OVKStyleNavigation(nav); [self presentViewController:nav animated:YES completion:nil];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES]; self.selectedComment=self.items[path.row]; self.replyAction=self.mediaAction=self.profileAction=NSNotFound;
    UIActionSheet *sheet=[[UIActionSheet alloc] initWithTitle:[self nameFor:self.selectedComment] delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    if (self.canPost) self.replyAction=[sheet addButtonWithTitle:OVKL(@"Ответить")];
    if (OVKPlayableAttachments(self.selectedComment).count) self.mediaAction=[sheet addButtonWithTitle:OVKL(@"Вложения")];
    if ([OVKString(self.selectedComment[@"from_id"]) longLongValue]>0) self.profileAction=[sheet addButtonWithTitle:OVKL(@"Профиль")];
    sheet.cancelButtonIndex=[sheet addButtonWithTitle:OVKL(@"Отмена")]; [sheet showInView:self.view];
}
- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
    if (index==self.replyAction) [self composeReply:self.selectedComment];
    else if (index==self.mediaAction) [self.navigationController pushViewController:[[OVKAttachmentsController alloc] initWithAttachments:OVKPlayableAttachments(self.selectedComment) title:OVKL(@"Вложения")] animated:YES];
    else if (index==self.profileAction) [self.navigationController pushViewController:[[OVKListController alloc] initWithMode:@"profile" identifier:@([OVKString(self.selectedComment[@"from_id"]) longLongValue]) title:[self nameFor:self.selectedComment]] animated:YES];
}

@end
