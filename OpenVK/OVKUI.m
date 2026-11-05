#import "OVKUI.h"
#import "OVKAPI.h"
#import "OVKMedia.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>
UIColor *OVKBlue(void) { return [UIColor colorWithRed:79.0/255 green:114.0/255 blue:153.0/255 alpha:1]; }
void OVKAlert(NSString *title, NSString *message) { [[[UIAlertView alloc] initWithTitle:title message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show]; }
void OVKStyleNavigation(UINavigationController *nav) {
    nav.navigationBar.tintColor = OVKBlue(); nav.navigationBar.translucent = NO;
    UIImage *button = [[UIImage imageNamed:@"NavButton"] resizableImageWithCapInsets:UIEdgeInsetsMake(6,10,6,10)];
    UIImage *pressed = [[UIImage imageNamed:@"NavButtonPressed"] resizableImageWithCapInsets:UIEdgeInsetsMake(6,10,6,10)];
    [[UIBarButtonItem appearance] setBackgroundImage:button forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
    [[UIBarButtonItem appearance] setBackgroundImage:pressed forState:UIControlStateHighlighted barMetrics:UIBarMetricsDefault];
    [[UIBarButtonItem appearance] setBackButtonBackgroundImage:[[UIImage imageNamed:@"BackButton"] resizableImageWithCapInsets:UIEdgeInsetsMake(6,15,6,8)] forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
    [[UIBarButtonItem appearance] setBackButtonBackgroundImage:[[UIImage imageNamed:@"BackButtonPressed"] resizableImageWithCapInsets:UIEdgeInsetsMake(6,15,6,8)] forState:UIControlStateHighlighted barMetrics:UIBarMetricsDefault];
    [[UIBarButtonItem appearance] setTitleTextAttributes:@{UITextAttributeTextColor:[UIColor whiteColor],UITextAttributeTextShadowColor:[UIColor colorWithWhite:0 alpha:.55],UITextAttributeTextShadowOffset:[NSValue valueWithUIOffset:UIOffsetMake(0,-1)],UITextAttributeFont:[UIFont boldSystemFontOfSize:12]} forState:UIControlStateNormal];
    [nav.navigationBar setBackgroundImage:[UIImage imageNamed:@"Navigation"] forBarMetrics:UIBarMetricsDefault];
    nav.navigationBar.titleTextAttributes = @{UITextAttributeTextColor:[UIColor whiteColor],UITextAttributeTextShadowColor:[UIColor colorWithWhite:0 alpha:.55],UITextAttributeTextShadowOffset:[NSValue valueWithUIOffset:UIOffsetMake(0,-1)],UITextAttributeFont:[UIFont boldSystemFontOfSize:19]};
}
static NSString *OVKName(NSDictionary *user) {
    NSString *name = [[NSString stringWithFormat:@"%@ %@",OVKString(user[@"first_name"]),OVKString(user[@"last_name"])] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    return name.length ? name : OVKString(user[@"name"]);
}
static NSString *OVKDate(id timestamp) {
    if (![timestamp respondsToSelector:@selector(doubleValue)] || [timestamp doubleValue] <= 0) return @"";
    NSDateFormatter *format = [[NSDateFormatter alloc] init]; format.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"ru_RU"]; format.dateFormat = @"d MMM yyyy 'в' HH:mm";
    return [format stringFromDate:[NSDate dateWithTimeIntervalSince1970:[timestamp doubleValue]]];
}
static NSString *OVKAttachmentText(NSDictionary *post) {
    NSMutableArray *names = [NSMutableArray array];
    for (id value in OVKArray(post[@"attachments"])) {
        NSDictionary *attachment = OVKDictionary(value); NSString *type = OVKString(attachment[@"type"]);
        if ([type isEqualToString:@"photo"]) continue;
        NSDictionary *labels = @{@"photo":@"Фотография",@"video":@"Видеозапись",@"audio":@"Аудиозапись",@"doc":@"Документ",@"poll":@"Опрос",@"link":@"Ссылка"};
        NSString *title = OVKString(OVKDictionary(attachment[type])[@"title"]);
        [names addObject:[NSString stringWithFormat:@"[%@] %@",labels[type] ?: type,title]];
    }
    if (OVKArray(post[@"copy_history"]).count) [names addObject:@"[Прикреплена запись — откройте в браузере]"];
    return [names componentsJoinedByString:@"\n"];
}
static NSString *OVKPostBody(NSDictionary *post) {
    if ([post[@"explicit"] boolValue]) return @"Содержимое 18+ скрыто. Доступно на сайте OpenVK.";
    NSString *text = OVKString(post[@"text"]); NSString *attachments = OVKAttachmentText(post);
    return text.length || attachments.length ? [NSString stringWithFormat:@"%@%@%@",text,text.length && attachments.length ? @"\n\n" : @"",attachments] : @"Запись без текста";
}
static NSString *OVKPhotoURL(NSDictionary *post) {
    for (NSDictionary *item in OVKPlayableAttachments(post)) if ([item[@"type"] isEqualToString:@"photo"]) return item[@"url"];
    return @"";
}
static CGFloat OVKPostPhotoHeight(NSDictionary *post,CGFloat width) {
    for (NSDictionary *item in OVKPlayableAttachments(post)) {
        if (![item[@"type"] isEqualToString:@"photo"]) continue;
        NSDictionary *photo=OVKDictionary(item[@"object"]); double w=[OVKString(photo[@"width"]) doubleValue], h=[OVKString(photo[@"height"]) doubleValue];
        if (w<=0 || h<=0) for (id value in OVKArray(photo[@"sizes"])) { NSDictionary *size=OVKDictionary(value); double sw=[OVKString(size[@"width"]) doubleValue],sh=[OVKString(size[@"height"]) doubleValue]; if (sw>0 && sh>0) { w=sw; h=sh; } }
        return w>0 && h>0 ? MIN(400,MAX(100,width*h/w)) : 190;
    }
    return 0;
}
@interface OVKCell : UITableViewCell
@property (strong, nonatomic) OVKRemoteImageView *avatar;
@property (strong, nonatomic) UILabel *heading;
@property (strong, nonatomic) UILabel *bodyLabel;
@property (strong, nonatomic) UILabel *stamp;
@property (strong, nonatomic) OVKRemoteImageView *photo;
@property (assign, nonatomic) CGFloat photoDisplayHeight;
@property (copy, nonatomic) void (^photoTapped)(void);
@property (assign, nonatomic) BOOL postStyle;
@property (assign, nonatomic) BOOL chatStyle;
@property (assign, nonatomic) BOOL outgoing;
@property (strong, nonatomic) UIImageView *bubble;
@property (strong, nonatomic) UILabel *metrics;
@property (strong, nonatomic) UILabel *likes;
@property (copy, nonatomic) void (^avatarTapped)(void);
@end
@implementation OVKCell
- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.avatar = [[OVKRemoteImageView alloc] init]; self.avatar.contentMode = UIViewContentModeScaleAspectFill; self.avatar.clipsToBounds = YES; self.avatar.userInteractionEnabled = YES; [self.avatar addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapAvatar)]]; self.avatar.layer.borderWidth = 1; self.avatar.layer.borderColor = [UIColor colorWithWhite:0 alpha:.2].CGColor;
        self.bubble = [[UIImageView alloc] init]; [self.contentView addSubview:self.bubble];
        self.metrics = [[UILabel alloc] init]; self.metrics.font = [UIFont systemFontOfSize:11]; self.metrics.textColor = [UIColor colorWithRed:.48 green:.55 blue:.62 alpha:1]; self.metrics.backgroundColor = [UIColor clearColor]; [self.contentView addSubview:self.metrics];
        self.likes = [[UILabel alloc] init]; self.likes.font=[UIFont boldSystemFontOfSize:11]; self.likes.textColor=OVKBlue(); self.likes.backgroundColor=[UIColor clearColor]; self.likes.textAlignment=NSTextAlignmentRight; [self.contentView addSubview:self.likes];
        self.heading = [[UILabel alloc] init]; self.heading.font = [UIFont boldSystemFontOfSize:14]; self.heading.textColor = OVKBlue();
        self.bodyLabel = [[UILabel alloc] init]; self.bodyLabel.font = [UIFont systemFontOfSize:14]; self.bodyLabel.numberOfLines = 0;
        self.photo = [[OVKRemoteImageView alloc] init]; self.photo.contentMode = UIViewContentModeScaleAspectFit; self.photo.hidden = YES; self.photo.userInteractionEnabled=YES; [self.photo addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapPhoto)]];
        self.stamp = [[UILabel alloc] init]; self.stamp.font = [UIFont systemFontOfSize:11]; self.stamp.textColor = [UIColor grayColor];
        for (UIView *v in @[self.avatar,self.heading,self.bodyLabel,self.stamp,self.photo]) [self.contentView addSubview:v];
        self.selectionStyle = UITableViewCellSelectionStyleBlue; self.backgroundView = [[UIImageView alloc] initWithImage:[[UIImage imageNamed:@"CellPanel"] resizableImageWithCapInsets:UIEdgeInsetsMake(3,0,3,0)]]; self.heading.backgroundColor = [UIColor clearColor]; self.bodyLabel.backgroundColor = [UIColor clearColor]; self.stamp.backgroundColor = [UIColor clearColor];
    }
    return self;
}
- (void)tapPhoto { if (self.photoTapped) self.photoTapped(); }
- (void)tapAvatar { if (self.avatarTapped) self.avatarTapped(); }
- (void)layoutSubviews {
    [super layoutSubviews]; CGFloat width = self.contentView.bounds.size.width; CGFloat height = self.contentView.bounds.size.height;
    CGFloat photoHeight = self.photo.hidden ? 0 : self.photoDisplayHeight;
    self.bubble.hidden = !self.chatStyle; self.metrics.hidden = !self.postStyle; self.likes.hidden = !self.postStyle;
    self.heading.hidden = self.chatStyle; self.avatar.hidden = self.chatStyle && self.outgoing;
    self.backgroundView.hidden = self.chatStyle;
    if (self.chatStyle) {
        CGFloat maxWidth = width-76;
        CGSize bodySize = [self.bodyLabel.text sizeWithFont:self.bodyLabel.font constrainedToSize:CGSizeMake(maxWidth-22,20000) lineBreakMode:NSLineBreakByWordWrapping];
        CGFloat bubbleWidth = self.photo.hidden ? MIN(maxWidth,MAX(115,ceil(bodySize.width)+22)) : maxWidth;
        CGFloat x = self.outgoing ? width-bubbleWidth-10 : 48;
        self.bubble.image = [[UIImage imageNamed:self.outgoing ? @"BubbleOutgoing" : @"BubbleIncoming"] resizableImageWithCapInsets:UIEdgeInsetsMake(8,8,8,8)];
        self.bubble.frame = CGRectMake(x,6,bubbleWidth,height-12);
        self.avatar.frame = CGRectMake(8,MAX(6,height-38),30,30);
        self.bodyLabel.frame = CGRectMake(x+11,14,bubbleWidth-22,ceil(bodySize.height));
        self.photo.frame = CGRectMake(x+8,height-32-photoHeight,bubbleWidth-16,photoHeight);
        self.stamp.frame = CGRectMake(x+8,height-27,bubbleWidth-16,14); self.stamp.textAlignment=NSTextAlignmentRight;
    } else if (self.postStyle) {
        self.stamp.textAlignment=NSTextAlignmentLeft;
        self.avatar.frame = CGRectMake(10,10,36,36); self.heading.frame = CGRectMake(56,8,width-66,21);
        self.stamp.frame = CGRectMake(56,30,width-66,15);
        self.bodyLabel.frame = CGRectMake(10,56,width-20,MAX(20,height-100-photoHeight));
        self.photo.frame = CGRectMake(10,height-40-photoHeight,width-20,photoHeight);
        self.metrics.frame = CGRectMake(10,height-31,width/2-10,24); self.likes.frame=CGRectMake(width/2,height-31,width/2-10,24);
    } else {
        self.stamp.textAlignment=NSTextAlignmentLeft;
        self.avatar.frame = CGRectMake(10,12,45,45); self.heading.frame = CGRectMake(65,10,width-78,20);
        self.bodyLabel.frame = CGRectMake(65,34,width-78,MAX(20,height-60-photoHeight));
        self.photo.frame = CGRectMake(65,height-22-photoHeight,width-78,photoHeight-8);
        self.stamp.frame = CGRectMake(65,height-22,width-78,16);
    }
}

@end
@interface OVKComposeController : UIViewController
@property (strong, nonatomic) UITextView *textView;
@property (strong, nonatomic) NSNumber *identifier;
@property (assign, nonatomic) BOOL message;
@property (copy, nonatomic) void (^sent)(void);
@property (assign, nonatomic) BOOL sending;
@property (copy, nonatomic) NSString *pendingText;
@property (strong, nonatomic) NSNumber *randomID;
@end
@implementation OVKComposeController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = self.message ? @"Новое сообщение" : @"Новая запись";
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) self.edgesForExtendedLayout = UIRectEdgeNone;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Отмена" style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Отправить" style:UIBarButtonItemStyleDone target:self action:@selector(send)];
    self.textView = [[UITextView alloc] initWithFrame:self.view.bounds]; self.textView.font = [UIFont systemFontOfSize:16]; self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; [self.view addSubview:self.textView];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboard:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [self.textView becomeFirstResponder];
}
- (void)keyboard:(NSNotification *)note {
    CGRect frame = [self.view convertRect:[note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
    CGFloat bottom = MAX(0,CGRectGetMaxY(self.view.bounds)-CGRectGetMinY(frame));
    self.textView.contentInset = UIEdgeInsetsMake(0,0,bottom,0); self.textView.scrollIndicatorInsets = self.textView.contentInset;
}
- (void)cancel { if (!self.sending) [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)send {
    if (self.sending) return;
    NSString *text = [self.textView.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!text.length) { OVKAlert(@"Пустой текст",@"Напишите сообщение перед отправкой."); return; }
    self.sending = YES; self.navigationItem.rightBarButtonItem.enabled = NO; self.navigationItem.leftBarButtonItem.enabled = NO;
    if (![self.pendingText isEqualToString:text]) { self.pendingText = text; self.randomID = @(arc4random_uniform(2147483646)+1); }
    NSDictionary *parameters = self.message ? @{@"peer_id":self.identifier,@"message":text,@"random_id":self.randomID} : @{@"owner_id":self.identifier,@"message":text};
    [[OVKAPI shared] call:self.message ? @"messages.send" : @"wall.post" parameters:parameters completion:^(id response, NSError *error) {
        self.sending = NO; self.navigationItem.rightBarButtonItem.enabled = YES; self.navigationItem.leftBarButtonItem.enabled = YES;
        if (error) { OVKAlert(@"Не отправлено",[error.localizedDescription stringByAppendingString:@"\nТекст сохранён в редакторе. При сетевой ошибке проверьте историю перед повтором."]); return; }
        if (self.sent) self.sent(); [self dismissViewControllerAnimated:YES completion:nil];
    }];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end
@interface OVKListController () <UIAlertViewDelegate>
@property (copy, nonatomic) NSString *mode;
@property (strong, nonatomic) NSNumber *identifier;
@property (strong, nonatomic) NSMutableArray *items;
@property (strong, nonatomic) NSMutableDictionary *people;
@property (strong, nonatomic) NSDictionary *user;
@property (strong, nonatomic) NSDictionary *singlePost;
@property (copy, nonatomic) NSString *nextCursor;
@property (assign, nonatomic) BOOL loading;
@property (assign, nonatomic) BOOL more;
@property (assign, nonatomic) NSUInteger generation;
@property (strong, nonatomic) UIButton *footer;
@property (strong, nonatomic) UILabel *notice;
@end
@implementation OVKListController
- (id)initWithMode:(NSString *)mode identifier:(NSNumber *)identifier title:(NSString *)title {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) { self.mode = mode; self.identifier = identifier; self.title = title; self.items = [NSMutableArray array]; self.people = [NSMutableDictionary dictionary]; }
    return self;
}
- (BOOL)isProfile { return [self.mode isEqualToString:@"profile"]; }
- (BOOL)isChat { return [self.mode isEqualToString:@"chat"]; }
- (BOOL)isFeed { return [self.mode isEqualToString:@"news"] || [self isProfile] || [self isPost]; }
- (BOOL)isPost { return [self.mode isEqualToString:@"post"]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"Linen"]]; self.tableView.separatorColor = [UIColor colorWithWhite:.87 alpha:1];
    if ([self isChat]) { self.tableView.separatorStyle=UITableViewCellSeparatorStyleNone; self.tableView.backgroundColor=[UIColor colorWithRed:.88 green:.91 blue:.94 alpha:1]; }
    self.refreshControl = [[UIRefreshControl alloc] init]; [self.refreshControl addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
    self.notice = [[UILabel alloc] initWithFrame:CGRectMake(0,0,320,45)]; self.notice.numberOfLines = 0; self.notice.textAlignment = NSTextAlignmentCenter; self.notice.font = [UIFont systemFontOfSize:12]; self.notice.textColor = [UIColor grayColor]; self.notice.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"SectionBar"]]; self.notice.shadowColor = [UIColor whiteColor]; self.notice.shadowOffset = CGSizeMake(0,1); self.tableView.tableHeaderView = self.notice;
    self.footer = [UIButton buttonWithType:UIButtonTypeCustom]; self.footer.frame = CGRectMake(0,0,320,48); self.footer.titleLabel.font = [UIFont boldSystemFontOfSize:13]; [self.footer setTitleColor:OVKBlue() forState:UIControlStateNormal]; [self.footer addTarget:self action:@selector(loadMore) forControlEvents:UIControlEventTouchUpInside]; [self.footer setBackgroundImage:[[UIImage imageNamed:@"FooterButton"] resizableImageWithCapInsets:UIEdgeInsetsMake(3,4,3,4)] forState:UIControlStateNormal]; self.tableView.tableFooterView = self.footer;
    if ([self isChat] || ([self isProfile] && [self.identifier isEqual:[OVKAPI shared].userID])) self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose target:self action:@selector(compose)];
    if ([self isPost]) { [self.items addObject:self.singlePost ?: @{}]; self.notice.text = @"Запись"; [self.footer setTitle:OVKPlayableAttachments(self.singlePost).count ? @"Открыть фото, видео и аудио" : @"Открыть запись в браузере" forState:UIControlStateNormal]; self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(openPost)]; }
    else [self refresh];
}
- (void)askLogout { [[[UIAlertView alloc] initWithTitle:@"Выйти из аккаунта?" message:@"Токен будет удалён с устройства. Для отзыва всех сеансов используйте настройки безопасности OpenVK." delegate:self cancelButtonTitle:@"Отмена" otherButtonTitles:@"Выйти",nil] show]; }
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex { if (buttonIndex == 1) [[OVKAPI shared] logout]; }
- (void)refresh {
    if ([self isPost]) { [self.refreshControl endRefreshing]; return; }
    if (self.loading) { [self.refreshControl endRefreshing]; return; }
    self.nextCursor = nil; [self fetch:NO];
}
- (void)loadMore {
    if ([self isPost]) { [self openAttachmentsForPost:self.singlePost]; return; }
    if (self.loading) return;
    [self fetch:self.items.count > 0 && self.more];
}
- (void)indexPeople:(NSDictionary *)response {
    for (id value in OVKArray(response[@"profiles"])) { NSDictionary *person = OVKDictionary(value); if (person[@"id"]) self.people[OVKString(person[@"id"])] = person; }
    for (id value in OVKArray(response[@"groups"])) { NSDictionary *group = OVKDictionary(value); if (group[@"id"]) self.people[OVKString(@(-[group[@"id"] longLongValue]))] = group; }
}
- (void)fetch:(BOOL)append {
    self.loading = YES; NSUInteger generation = ++self.generation;
    [self.footer setTitle:@"Загрузка…" forState:UIControlStateNormal]; self.notice.text = [OVKAPI shared].demo ? @"Демонстрация • вымышленные данные" : @"Обновление…";
    if ([self isProfile] && !append) {
        [[OVKAPI shared] call:@"users.get" parameters:@{@"user_ids":self.identifier,@"fields":@"photo_100,photo_200,photo_max_orig,status,online,city,about,counters"} completion:^(id result, NSError *error) {
            if (generation != self.generation) return;
            if (!error && OVKArray(result).count) { self.user = OVKDictionary(result[0]); if (self.user[@"id"]) self.people[OVKString(self.user[@"id"])] = self.user; [self updateProfileHeader]; }
            else if (error) { self.notice.text = error.localizedDescription; }
        }];
    }
    NSMutableDictionary *params = [@{@"count":@20,@"offset":@(append ? self.items.count : 0),@"extended":@1,@"fields":@"photo_100,photo_50,online"} mutableCopy];
    NSString *method = @"newsfeed.get";
    if ([self.mode isEqualToString:@"friends"]) { method = @"friends.get"; params[@"user_id"] = [OVKAPI shared].userID; }
    else if ([self.mode isEqualToString:@"dialogs"]) method = @"messages.getConversations";
    else if ([self isProfile]) { method = @"wall.get"; params[@"owner_id"] = self.identifier; }
    else if ([self isChat]) { method = @"messages.getHistory"; params[@"peer_id"] = self.identifier; }
    else if (append && self.nextCursor.length) { params[@"start_from"] = self.nextCursor; [params removeObjectForKey:@"offset"]; }
    [[OVKAPI shared] call:method parameters:params completion:^(id result, NSError *error) {
        if (generation != self.generation) return;
        self.loading = NO; [self.refreshControl endRefreshing];
        if (error) { self.notice.text = error.localizedDescription; [self.footer setTitle:@"Повторить загрузку" forState:UIControlStateNormal]; return; }
        NSDictionary *response = OVKDictionary(result);
        if (![result isKindOfClass:[NSDictionary class]] || ![response[@"items"] isKindOfClass:[NSArray class]]) {
            self.notice.text = @"Формат ответа этого сервера не поддерживается"; [self.footer setTitle:@"Повторить" forState:UIControlStateNormal]; return;
        }
        if (!append) { [self.items removeAllObjects]; [self.people removeAllObjects]; if (self.user[@"id"]) self.people[OVKString(self.user[@"id"])] = self.user; }
        [self indexPeople:response]; NSArray *incoming = OVKArray(response[@"items"]);
        for (id value in incoming) { if ([value isKindOfClass:[NSDictionary class]]) [self.items addObject:value]; }
        self.nextCursor = OVKString(response[@"next_from"]);
        self.more = ![OVKAPI shared].demo && (self.nextCursor.length || (incoming.count >= 20 && (!response[@"count"] || self.items.count < [response[@"count"] unsignedIntegerValue])));
        self.notice.text = [OVKAPI shared].demo ? @"Демонстрация • вымышленные данные" : (self.items.count ? @"Обновлено • потяните вниз для обновления" : @"Пока ничего нет");
        [self.footer setTitle:self.more ? @"Показать ещё" : @"Обновить" forState:UIControlStateNormal]; [self.tableView reloadData];
        if ([self isProfile]) [self updateProfileHeader];
    }];
}
- (void)updateProfileHeader {
    if (!self.user.count) return;
    CGFloat width = self.tableView.bounds.size.width;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0,0,width,272)];
    UIImageView *backdrop = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"ProfilePanel"]]; backdrop.frame = header.bounds; backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; [header addSubview:backdrop];
    OVKRemoteImageView *avatar = [[OVKRemoteImageView alloc] initWithFrame:CGRectMake(8,10,74,74)]; avatar.contentMode = UIViewContentModeScaleAspectFill; avatar.clipsToBounds = YES; avatar.layer.cornerRadius = 3; avatar.layer.borderWidth = 1; avatar.layer.borderColor = [UIColor colorWithWhite:0 alpha:.4].CGColor; [avatar load:OVKString(self.user[@"photo_100"])]; [header addSubview:avatar]; avatar.userInteractionEnabled = YES; [avatar addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openProfilePhoto)]];
    UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(92,10,width-104,38)]; name.numberOfLines = 2; name.font = [UIFont boldSystemFontOfSize:16]; name.textColor = [UIColor whiteColor]; name.shadowColor = [UIColor blackColor]; name.shadowOffset = CGSizeMake(0,-1); name.text = OVKName(self.user); name.backgroundColor = [UIColor clearColor]; [header addSubview:name];
    UILabel *status = [[UILabel alloc] initWithFrame:CGRectMake(92,49,width-104,36)]; status.numberOfLines = 2; status.font = [UIFont systemFontOfSize:11]; status.textColor = [UIColor colorWithRed:.66 green:.72 blue:.78 alpha:1]; status.backgroundColor = [UIColor clearColor]; status.text = [NSString stringWithFormat:@"%@\n%@",[self.user[@"online"] boolValue] ? @"Online" : @"Не в сети",OVKString(self.user[@"status"])]; [header addSubview:status];
    UIButton *action = [UIButton buttonWithType:UIButtonTypeCustom]; action.frame = CGRectMake(8,94,width-16,30); [action setBackgroundImage:[[UIImage imageNamed:@"NavButton"] resizableImageWithCapInsets:UIEdgeInsetsMake(6,10,6,10)] forState:UIControlStateNormal]; [action setTitle:[self.identifier isEqual:[OVKAPI shared].userID] ? @"Фотографии" : @"Написать сообщение" forState:UIControlStateNormal]; action.titleLabel.font = [UIFont boldSystemFontOfSize:12]; [action setTitleShadowColor:[UIColor colorWithWhite:0 alpha:.6] forState:UIControlStateNormal]; action.titleLabel.shadowOffset = CGSizeMake(0,-1); [action addTarget:self action:[self.identifier isEqual:[OVKAPI shared].userID] ? @selector(openProfilePhotos) : @selector(openChat) forControlEvents:UIControlEventTouchUpInside]; [header addSubview:action];
    NSDictionary *counters = OVKDictionary(self.user[@"counters"]);
    NSArray *keys = @[@"friends",@"followers",@"photos",@"videos",@"audios",@"groups"];
    NSArray *titles = @[@"ДРУЗЬЯ",@"ПОДПИСЧИКИ",@"ФОТОГРАФИИ",@"ВИДЕО",@"АУДИО",@"ГРУППЫ"];
    for (NSUInteger i=0;i<keys.count;i++) {
        NSUInteger columns = 3; NSUInteger column = i<3 ? i : i-3;
        CGFloat gap=5, tileWidth=(width-16-gap*(columns-1))/columns;
        CGRect frame=CGRectMake(8+column*(tileWidth+gap),132+(i<3 ? 0 : 47),tileWidth,42);
        UIImageView *tile=[[UIImageView alloc] initWithImage:[[UIImage imageNamed:@"ProfileCounter"] resizableImageWithCapInsets:UIEdgeInsetsMake(3,3,3,3)]]; tile.frame=frame; tile.layer.cornerRadius=3; tile.clipsToBounds=YES; [header addSubview:tile];
        id value=counters[keys[i]]; UILabel *count=[[UILabel alloc] initWithFrame:CGRectMake(0,3,tileWidth,22)]; count.text=[value respondsToSelector:@selector(integerValue)] ? [NSString stringWithFormat:@"%ld",(long)[value integerValue]] : @"—"; count.font=[UIFont boldSystemFontOfSize:18]; count.textAlignment=NSTextAlignmentCenter; count.textColor=[UIColor colorWithWhite:.86 alpha:1]; count.backgroundColor=[UIColor clearColor]; [tile addSubview:count];
        UILabel *caption=[[UILabel alloc] initWithFrame:CGRectMake(0,25,tileWidth,13)]; caption.text=titles[i]; caption.font=[UIFont boldSystemFontOfSize:8]; caption.textAlignment=NSTextAlignmentCenter; caption.textColor=[UIColor colorWithWhite:.58 alpha:1]; caption.backgroundColor=[UIColor clearColor]; [tile addSubview:caption];
        if (i>=2 && i<=4) { UIButton *button=[UIButton buttonWithType:UIButtonTypeCustom]; button.frame=frame; button.tag=i; button.accessibilityLabel=titles[i]; [button addTarget:self action:@selector(openProfileLibrary:) forControlEvents:UIControlEventTouchUpInside]; [header addSubview:button]; }
    }
    self.notice.frame = CGRectMake(0,234,width,38); self.notice.text = [OVKAPI shared].demo ? @"Все записи • деморежим" : @"Все записи"; [header addSubview:self.notice]; self.tableView.tableHeaderView = header;
}
- (void)openProfilePhotos { [self.navigationController pushViewController:[[OVKLibraryController alloc] initWithKind:@"photo" identifier:self.identifier title:@"Фотографии"] animated:YES]; }
- (void)openProfileLibrary:(UIButton *)sender {
    NSArray *kinds=@[@"photo",@"video",@"audio"]; NSArray *titles=@[@"Фотографии",@"Видеозаписи",@"Аудиозаписи"];
    NSUInteger index=sender.tag-2; if (index>=kinds.count) return;
    [self.navigationController pushViewController:[[OVKLibraryController alloc] initWithKind:kinds[index] identifier:self.identifier title:titles[index]] animated:YES];
}
- (NSDictionary *)postAt:(NSUInteger)index { return OVKDictionary(self.items[index]); }
- (NSDictionary *)personFor:(NSDictionary *)item {
    id identifier = item[@"from_id"] ?: item[@"source_id"] ?: item[@"owner_id"];
    return OVKDictionary(self.people[OVKString(identifier)]);
}
- (NSString *)headingFor:(NSDictionary *)item {
    if ([self.mode isEqualToString:@"friends"]) return OVKName(item);
    if ([self.mode isEqualToString:@"dialogs"]) {
        NSDictionary *conversation = OVKDictionary(item[@"conversation"]); NSDictionary *peer = OVKDictionary(conversation[@"peer"]);
        NSString *title = OVKString(OVKDictionary(conversation[@"chat_settings"])[@"title"]);
        NSString *name = OVKName(OVKDictionary(self.people[OVKString(peer[@"id"])]));
        return title.length ? title : (name.length ? name : [NSString stringWithFormat:@"Диалог %@",OVKString(peer[@"id"])]);
    }
    NSString *name = OVKName([self personFor:item]);
    return name.length ? name : [NSString stringWithFormat:@"%@ %@",[self isChat] ? @"Пользователь" : @"Автор",OVKString(item[@"from_id"] ?: item[@"source_id"])];
}
- (NSString *)bodyFor:(NSDictionary *)item {
    if ([self.mode isEqualToString:@"friends"]) return [item[@"online"] boolValue] ? @"Online" : @"Не в сети";
    if ([self.mode isEqualToString:@"dialogs"]) {
        NSDictionary *message = OVKDictionary(item[@"last_message"]); NSString *text = OVKString(message[@"text"]);
        return [NSString stringWithFormat:@"%@%@",[message[@"out"] boolValue] ? @"Вы: " : @"",text.length ? text : @"[Вложение]"];
    }
    return OVKPostBody(item);
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.items.count; }
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *text = [self bodyFor:[self postAt:indexPath.row]];
    CGFloat textWidth=tableView.bounds.size.width-([self isChat] ? 98 : ([self isFeed] ? 20 : 78));
    CGSize size = [text sizeWithFont:[UIFont systemFontOfSize:14] constrainedToSize:CGSizeMake(MAX(100,textWidth),([self isPost] || [self isChat]) ? 20000 : 110) lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat imageHeight=OVKPostPhotoHeight([self postAt:indexPath.row],tableView.bounds.size.width-([self isChat] ? 92 : ([self isFeed] ? 20 : 94)));
    if ([self isChat]) return MAX(62,ceil(size.height)+48+imageHeight);
    return MAX(86,ceil(size.height)+([self isFeed] ? 100 : 62)) + imageHeight;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    OVKCell *cell = [tableView dequeueReusableCellWithIdentifier:@"entry"];
    if (!cell) cell = [[OVKCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"entry"];
    NSDictionary *item = [self postAt:indexPath.row];
    NSString *photoURL = OVKPhotoURL(item); cell.photoDisplayHeight=OVKPostPhotoHeight(item,tableView.bounds.size.width-([self isChat] ? 92 : ([self isFeed] ? 20 : 94))); cell.photo.hidden = !photoURL.length; if (photoURL.length) [cell.photo load:photoURL];
    cell.chatStyle = [self isChat]; cell.outgoing = [item[@"out"] boolValue] || [OVKString(item[@"from_id"]) isEqualToString:OVKString([OVKAPI shared].userID)]; cell.postStyle = [self isFeed]; cell.heading.text = [self headingFor:item]; cell.bodyLabel.text = [self bodyFor:item];
    NSDictionary *person = [self.mode isEqualToString:@"friends"] ? item : [self personFor:item];
    if ([self.mode isEqualToString:@"dialogs"]) person = OVKDictionary(self.people[OVKString(OVKDictionary(OVKDictionary(item[@"conversation"])[@"peer"])[@"id"])]);
    [cell.avatar load:OVKString(person[@"photo_100"] ?: person[@"photo_50"])];
    NSString *avatarURL = OVKString(person[@"photo_max_orig"] ?: person[@"photo_200"] ?: person[@"photo_100"] ?: person[@"photo_50"]);
    __weak OVKListController *weakSelf = self; cell.photoTapped=^{
        NSMutableArray *photos=[NSMutableArray array]; for (NSDictionary *attachment in OVKPlayableAttachments(item)) if ([attachment[@"type"] isEqualToString:@"photo"]) [photos addObject:attachment];
        if (photos.count) [weakSelf.navigationController pushViewController:[[OVKPhotoController alloc] initWithPhotos:photos index:0] animated:YES];
    }; cell.avatarTapped = ^{ if (avatarURL.length) [weakSelf.navigationController pushViewController:[[OVKPhotoController alloc] initWithURL:avatarURL title:@"Аватар"] animated:YES]; };
    NSDictionary *message = [self.mode isEqualToString:@"dialogs"] ? OVKDictionary(item[@"last_message"]) : item;
    NSString *date = OVKDate(message[@"date"]); NSInteger unread = [OVKDictionary(item[@"conversation"])[@"unread_count"] integerValue];
    cell.stamp.text = unread ? [NSString stringWithFormat:@"%ld новых • %@",(long)unread,date] : date;
    NSString *comments=OVKString(OVKDictionary(item[@"comments"])[@"count"]); NSString *likes=OVKString(OVKDictionary(item[@"likes"])[@"count"]);
    cell.metrics.text = [NSString stringWithFormat:@"Комментарии %@",comments.length ? comments : @"0"];
    cell.likes.text = [NSString stringWithFormat:@"♥ %@",likes.length ? likes : @"0"];
    [cell setNeedsLayout];
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES]; NSDictionary *item = [self postAt:indexPath.row];
    if ([self isChat] || [self isPost]) { if (OVKPlayableAttachments(item).count) [self openAttachmentsForPost:item]; return; }
    if ([self.mode isEqualToString:@"friends"]) {
        if (![item[@"id"] respondsToSelector:@selector(integerValue)]) return;
        [self.navigationController pushViewController:[[OVKListController alloc] initWithMode:@"profile" identifier:item[@"id"] title:OVKName(item)] animated:YES];
    } else if ([self.mode isEqualToString:@"dialogs"]) {
        NSNumber *peer = OVKDictionary(OVKDictionary(item[@"conversation"])[@"peer"])[@"id"]; if (![peer respondsToSelector:@selector(integerValue)]) return;
        [self.navigationController pushViewController:[[OVKListController alloc] initWithMode:@"chat" identifier:peer title:[self headingFor:item]] animated:YES];
    } else {
        OVKListController *post = [[OVKListController alloc] initWithMode:@"post" identifier:nil title:@"Запись"]; post.singlePost = item; post.people = [self.people mutableCopy]; [self.navigationController pushViewController:post animated:YES];
    }
}
- (void)openAttachmentsForPost:(NSDictionary *)post {
    NSArray *items = OVKPlayableAttachments(post);
    if (!items.count) { if ([self isPost]) [self openPost]; return; }
    [self.navigationController pushViewController:[[OVKAttachmentsController alloc] initWithAttachments:items title:@"Вложения"] animated:YES];
}
- (void)openProfilePhoto {
    NSString *url = OVKString(self.user[@"photo_max_orig"] ?: self.user[@"photo_200"] ?: self.user[@"photo_100"]);
    if (url.length) [self.navigationController pushViewController:[[OVKPhotoController alloc] initWithURL:url title:@"Аватар"] animated:YES];
}
- (void)openPost {
    NSDictionary *post = self.singlePost; NSString *owner = OVKString(post[@"owner_id"] ?: post[@"source_id"] ?: post[@"from_id"]); NSString *identifier = OVKString(post[@"id"] ?: post[@"post_id"]);
    if (!owner.length || !identifier.length || [OVKAPI shared].demo) { OVKAlert(@"Деморежим",@"Эта запись существует только в демоверсии."); return; }
    // The API host may also serve web routes; users can use their instance's redirect to the web domain.
    NSString *host = [OVKAPI shared].siteServer ?: [OVKAPI shared].server; if ([host isEqualToString:@"https://api.openvk.org"]) host = @"https://openvk.org";
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/wall%@_%@",host,owner,identifier]]];
}
- (void)openChat { [self.navigationController pushViewController:[[OVKListController alloc] initWithMode:@"chat" identifier:self.identifier title:OVKName(self.user)] animated:YES]; }
- (void)compose {
    OVKComposeController *compose = [[OVKComposeController alloc] init]; compose.identifier = self.identifier; compose.message = [self isChat]; __weak OVKListController *weakSelf = self; compose.sent = ^{ [weakSelf refresh]; };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:compose]; OVKStyleNavigation(nav); [self presentViewController:nav animated:YES completion:nil];
}
@end
