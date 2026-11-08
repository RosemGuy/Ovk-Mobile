#import "OVKPerformance.h"
#import <objc/runtime.h>
#import "OVKLanguage.h"
#import "OVKUI.h"
#import "OVKAPI.h"
#import "OVKMedia.h"
#import "OVKMusic.h"
#import "OVKWall.h"
#import "OVKWallModel.h"
#import "OVKFeedLayout.h"
#import "OVKSocial.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>
UIColor *OVKBlue(void) { return OVKThemeAccent(); }
void OVKAlert(NSString *title, NSString *message) { [[[UIAlertView alloc] initWithTitle:title message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show]; }
void OVKConfigureEdges(UIViewController *controller) {
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 70000
    if ([controller respondsToSelector:@selector(setEdgesForExtendedLayout:)]) controller.edgesForExtendedLayout=UIRectEdgeNone;
#else
    (void)controller;
#endif
}
void OVKStyleNavigation(UINavigationController *nav) {
    nav.navigationBar.tintColor = OVKBlue(); nav.navigationBar.translucent = NO;
    UIImage *button = OVKThemeStretch(@"NavButton");
    UIImage *pressed = OVKThemeStretch(@"NavButtonPressed");
    [[UIBarButtonItem appearance] setBackgroundImage:button forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
    [[UIBarButtonItem appearance] setBackgroundImage:pressed forState:UIControlStateHighlighted barMetrics:UIBarMetricsDefault];
    [[UIBarButtonItem appearance] setBackButtonBackgroundImage:OVKThemeStretch(@"BackButton") forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
    [[UIBarButtonItem appearance] setBackButtonBackgroundImage:OVKThemeStretch(@"BackButtonPressed") forState:UIControlStateHighlighted barMetrics:UIBarMetricsDefault];
    [[UIBarButtonItem appearance] setTitleTextAttributes:@{UITextAttributeTextColor:[UIColor whiteColor],UITextAttributeTextShadowColor:[UIColor colorWithWhite:0 alpha:.55],UITextAttributeTextShadowOffset:[NSValue valueWithUIOffset:UIOffsetMake(0,-1)],UITextAttributeFont:[UIFont boldSystemFontOfSize:12]} forState:UIControlStateNormal];
    [nav.navigationBar setBackgroundImage:OVKThemeStretch(@"Navigation") forBarMetrics:UIBarMetricsDefault];
    for (UIViewController *page in nav.viewControllers) {
        NSMutableArray *items=[NSMutableArray array]; if (page.navigationItem.leftBarButtonItem) [items addObject:page.navigationItem.leftBarButtonItem]; if (page.navigationItem.rightBarButtonItem) [items addObject:page.navigationItem.rightBarButtonItem];
        for (UIBarButtonItem *item in items) if (!item.customView) { [item setBackgroundImage:button forState:UIControlStateNormal barMetrics:UIBarMetricsDefault]; [item setBackgroundImage:pressed forState:UIControlStateHighlighted barMetrics:UIBarMetricsDefault]; }
    }
    nav.navigationBar.titleTextAttributes = @{UITextAttributeTextColor:[UIColor whiteColor],UITextAttributeTextShadowColor:[UIColor colorWithWhite:0 alpha:.55],UITextAttributeTextShadowOffset:[NSValue valueWithUIOffset:UIOffsetMake(0,-1)],UITextAttributeFont:[UIFont boldSystemFontOfSize:19]};
}
static CGFloat OVKFeedTextSize(void) { return [[NSUserDefaults standardUserDefaults] boolForKey:@"OVKLargeFeedText"] ? 17 : 14; }
static NSString *OVKName(NSDictionary *user) {
    NSString *name = [[NSString stringWithFormat:@"%@ %@",OVKString(user[@"first_name"]),OVKString(user[@"last_name"])] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    return name.length ? name : OVKString(user[@"name"]);
}
static NSString *OVKDate(id timestamp) {
    if (![timestamp respondsToSelector:@selector(doubleValue)] || [timestamp doubleValue] <= 0) return @"";
    static NSDateFormatter *format=nil; static NSInteger language=-1; NSInteger selected=OVKLanguageIsEnglish(); if (!format || language!=selected) { format=[[NSDateFormatter alloc] init]; language=selected; format.locale=[[NSLocale alloc] initWithLocaleIdentifier:selected ? @"en_US" : @"ru_RU"]; format.dateFormat=selected ? @"d MMM yyyy HH:mm" : @"d MMM yyyy 'в' HH:mm"; }
    return [format stringFromDate:[NSDate dateWithTimeIntervalSince1970:[timestamp doubleValue]]];
}
static NSString *OVKCompactDate(id timestamp,BOOL timeOnly) {
    NSTimeInterval seconds=[OVKString(timestamp) doubleValue]; if (seconds<=0) return @"";
    static NSDateFormatter *clock,*day; static NSInteger language=-1; NSInteger selected=OVKLanguageIsEnglish();
    if (!clock || language!=selected) { language=selected; NSLocale *locale=[[NSLocale alloc] initWithLocaleIdentifier:selected ? @"en_US" : @"ru_RU"]; clock=[[NSDateFormatter alloc] init]; clock.locale=locale; clock.dateFormat=@"HH:mm"; day=[[NSDateFormatter alloc] init]; day.locale=locale; day.dateFormat=@"d MMM"; }
    NSDate *date=[NSDate dateWithTimeIntervalSince1970:seconds]; return [(timeOnly || [[NSDate date] timeIntervalSinceDate:date]<86400 ? clock : day) stringFromDate:date];
}
static NSArray *OVKPostAttachments(NSDictionary *post) {
    static char key; NSDictionary *saved=objc_getAssociatedObject(post,&key);
    NSString *context=[NSString stringWithFormat:@"%@|%@|%d",[OVKAPI shared].siteServer ?: @"",[OVKAPI shared].server ?: @"",OVKLanguageIsEnglish()];
    if ([saved[@"context"] isEqualToString:context]) return saved[@"items"];
    NSArray *items=OVKPlayableAttachments(post); objc_setAssociatedObject(post,&key,@{@"context":context,@"items":items},OBJC_ASSOCIATION_RETAIN_NONATOMIC); return items;
}
static NSString *OVKAttachmentText(NSDictionary *post,BOOL inlineAudio) {
    NSMutableArray *names = [NSMutableArray array];
    for (id value in OVKArray(post[@"attachments"])) {
        NSDictionary *attachment = OVKDictionary(value); NSString *type = OVKString(attachment[@"type"]);
        if ([type isEqualToString:@"photo"]) continue;
        if (inlineAudio && [type isEqualToString:@"audio"]) continue;
        NSDictionary *labels = @{@"photo":OVKL(@"Фотография"),@"video":OVKL(@"Видеозапись"),@"audio":OVKL(@"Аудиозапись"),@"doc":OVKL(@"Документ"),@"poll":OVKL(@"Опрос"),@"link":OVKL(@"Ссылка")};
        NSString *title = OVKString(OVKDictionary(attachment[type])[@"title"]);
        [names addObject:[NSString stringWithFormat:@"[%@] %@",labels[type] ?: type,title]];
    }
    if (OVKArray(post[@"copy_history"]).count) [names addObject:OVKL(@"[Прикреплена запись — откройте в браузере]")];
    return [names componentsJoinedByString:@"\n"];
}
static NSString *OVKPostBody(NSDictionary *post,BOOL inlineAudio) {
    if (([OVKString(post[@"explicit"]) boolValue] || [OVKString(post[@"is_explicit"]) boolValue])) return OVKL(@"Содержимое 18+ скрыто. Доступно на сайте OpenVK.");
    NSString *text = OVKString(post[@"text"]); NSString *attachments = OVKAttachmentText(post,inlineAudio);
    return text.length || attachments.length ? [NSString stringWithFormat:@"%@%@%@",text,text.length && attachments.length ? @"\n\n" : @"",attachments] : (OVKPostAttachments(post).count ? @"" : OVKL(@"Запись без текста"));
}
static NSString *OVKPhotoURL(NSDictionary *post) {
    for (NSDictionary *item in OVKPostAttachments(post)) if ([item[@"type"] isEqualToString:@"photo"]) return OVKString(item[@"preview"]).length ? item[@"preview"] : item[@"url"];
    return @"";
}
static NSArray *OVKPostPhotos(NSDictionary *post) { NSMutableArray *photos=[NSMutableArray array]; for (NSDictionary *item in OVKPostAttachments(post)) if ([item[@"type"] isEqualToString:@"photo"]) [photos addObject:item]; return photos; }
static CGSize OVKChatPhotoSize(NSDictionary *post,CGFloat width) {
    NSArray *photos=OVKPostPhotos(post);
    if (!photos.count) return CGSizeZero;
    NSDictionary *photo=OVKDictionary(OVKDictionary(photos[0])[@"object"]);
    CGFloat w=[OVKString(photo[@"width"]) doubleValue], h=[OVKString(photo[@"height"]) doubleValue];
    if (w<=0 || h<=0) for (id value in OVKArray(photo[@"sizes"])) {
        NSDictionary *size=OVKDictionary(value);
        CGFloat sw=[OVKString(size[@"width"]) doubleValue], sh=[OVKString(size[@"height"]) doubleValue];
        if (sw>0 && sh>0) { w=sw; h=sh; }
    }
    width=MAX(1,width);
    if (!isfinite(w) || !isfinite(h) || w<=0 || h<=0) return CGSizeMake(width,MIN(165,width));
    CGFloat scale=MIN(width/w,235/h);
    return CGSizeMake(MAX(1,floor(w*scale)),MAX(1,floor(h*scale)));
}
static CGFloat OVKPostPhotoHeight(NSDictionary *post,CGFloat width,BOOL collage) {
    NSUInteger count=OVKPostPhotos(post).count; if (collage && count>1) return count==2 ? MIN(260,width*.62) : MIN(280,width*.65);
    for (NSDictionary *item in OVKPostAttachments(post)) {
        if (![item[@"type"] isEqualToString:@"photo"]) continue;
        NSDictionary *photo=OVKDictionary(item[@"object"]); double w=[OVKString(photo[@"width"]) doubleValue], h=[OVKString(photo[@"height"]) doubleValue];
        if (w<=0 || h<=0) for (id value in OVKArray(photo[@"sizes"])) { NSDictionary *size=OVKDictionary(value); double sw=[OVKString(size[@"width"]) doubleValue],sh=[OVKString(size[@"height"]) doubleValue]; if (sw>0 && sh>0) { w=sw; h=sh; } }
        return w>0 && h>0 ? MIN(400,MAX(100,width*h/w)) : 190;
    }
    return 0;
}
// The artwork remains 29pt tall; the control has a full 44pt touch target.
@interface OVKMessageSendButton : UIButton
@end
@implementation OVKMessageSendButton
- (CGRect)backgroundRectForBounds:(CGRect)bounds { return CGRectMake(0,(bounds.size.height-29)/2,bounds.size.width,29); }
@end
@interface OVKMessageField : UITextField
@end
@implementation OVKMessageField
- (CGRect)textRectForBounds:(CGRect)bounds { return CGRectInset(bounds,12,0); }
- (CGRect)editingRectForBounds:(CGRect)bounds { return [self textRectForBounds:bounds]; }
- (CGRect)placeholderRectForBounds:(CGRect)bounds { return [self textRectForBounds:bounds]; }
@end
static UIImage *OVKSendPlane(void) {
    static UIImage *image;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(19,19),NO,0);
        CGContextRef context=UIGraphicsGetCurrentContext();
        // Fit the supplied SVG viewBox (0, -0.5, 17, 17) into the button glyph.
        CGContextScaleCTM(context,19.0/17.0,19.0/17.0);
        CGContextTranslateCTM(context,0,.5);
        [[UIColor whiteColor] setFill];
        CGContextMoveToPoint(context,17,1.042);
        CGContextAddLineToPoint(context,11.436,14.954);
        CGContextAddLineToPoint(context,7.958,11.477);
        CGContextAddLineToPoint(context,8.653,13.563);
        CGContextAddLineToPoint(context,7.03,14.958);
        CGContextAddLineToPoint(context,7.03,11.563);
        CGContextAddLineToPoint(context,14.984,3.375);
        CGContextAddLineToPoint(context,6.047,9.969);
        CGContextAddLineToPoint(context,1,8.694);
        CGContextClosePath(context);
        CGContextEOFillPath(context);
        image=UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    });
    return image;
}
@interface OVKCell : UITableViewCell
@property (strong, nonatomic) OVKRemoteImageView *avatar;
@property (strong, nonatomic) UILabel *heading;
@property (strong, nonatomic) UILabel *bodyLabel;
@property (strong, nonatomic) UILabel *stamp;
@property (strong, nonatomic) OVKRemoteImageView *photo;
@property (assign, nonatomic) CGFloat photoDisplayHeight;
@property (assign, nonatomic) NSUInteger photoCount;
@property (strong, nonatomic) NSArray *extraPhotos;
@property (strong, nonatomic) UILabel *morePhotos;
@property (strong, nonatomic) UIView *postHeader;
@property (strong, nonatomic) UIView *postFooter;
@property (strong, nonatomic) UIButton *commentButton;
@property (strong, nonatomic) UIButton *likeButton;
@property (copy, nonatomic) void (^likeTapped)(void);
@property (assign, nonatomic) BOOL liked;
@property (copy, nonatomic) void (^photoIndexTapped)(NSUInteger index);
@property (copy, nonatomic) void (^commentTapped)(void);
@property (copy, nonatomic) void (^photoTapped)(void);
@property (assign, nonatomic) BOOL postStyle;
@property (assign, nonatomic) BOOL peopleStyle;
@property (assign, nonatomic) BOOL dialogStyle;
@property (assign, nonatomic) BOOL activeDialog;
@property (assign, nonatomic) BOOL conversationGroup;
@property (strong, nonatomic) UIImageView *groupGlyph;
@property (strong, nonatomic) UIImageView *unreadBadgeSkin;
@property (strong, nonatomic) OVKRemoteImageView *previewAvatar;
@property (copy, nonatomic) NSString *measuredText;
@property (assign, nonatomic) CGFloat measuredWidth;
@property (assign, nonatomic) CGFloat measuredFontSize;
@property (assign, nonatomic) CGSize measuredBodySize;
@property (assign, nonatomic) BOOL unread;
@property (assign, nonatomic) BOOL chatStyle;
@property (assign, nonatomic) BOOL outgoing;
@property (strong, nonatomic) UIImageView *bubble;
@property (strong, nonatomic) UILabel *quotedMessage;
@property (strong, nonatomic) UIButton *postMenuButton;
@property (strong, nonatomic) OVKInlineAudioView *inlineAudio;
@property (copy, nonatomic) void (^postMenuTapped)(void);
@property (copy, nonatomic) NSString *bubbleArtworkKey;
@property (strong, nonatomic) CAGradientLayer *photoGloss;
@property (assign, nonatomic) CGFloat chatPhotoWidth;
@property (strong, nonatomic) UILabel *metrics;
@property (strong, nonatomic) UILabel *likes;
@property (strong, nonatomic) UIImageView *likeIcon;
@property (strong, nonatomic) UILabel *unreadBadge;
@property (copy, nonatomic) void (^avatarTapped)(void);
@end
@implementation OVKCell
- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.avatar = [[OVKRemoteImageView alloc] init]; if ([self.avatar respondsToSelector:@selector(setMaxPixelSize:)]) self.avatar.maxPixelSize=OVKLowMemoryDevice() ? 96 : 128; self.avatar.contentMode = UIViewContentModeScaleAspectFill; self.avatar.clipsToBounds = YES; self.avatar.userInteractionEnabled = YES; [self.avatar addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapAvatar)]]; self.avatar.layer.borderWidth = 1; self.avatar.layer.borderColor = [UIColor colorWithWhite:0 alpha:.2].CGColor;
        self.bubble = [[UIImageView alloc] init]; self.bubble.userInteractionEnabled=NO; [self.contentView addSubview:self.bubble];
        self.quotedMessage=[[UILabel alloc] init]; self.quotedMessage.numberOfLines=2;
        self.quotedMessage.font=[UIFont systemFontOfSize:11];
        [self.contentView addSubview:self.quotedMessage];
        self.postHeader=[[UIView alloc] init]; self.postHeader.backgroundColor=[UIColor colorWithRed:.92 green:.945 blue:.96 alpha:1]; [self.contentView addSubview:self.postHeader];
        self.postFooter=[[UIView alloc] init]; self.postFooter.backgroundColor=[UIColor colorWithRed:.96 green:.97 blue:.98 alpha:1]; [self.contentView addSubview:self.postFooter];
        self.postMenuButton=[UIButton buttonWithType:UIButtonTypeCustom];
        self.postMenuButton.titleLabel.font=[UIFont boldSystemFontOfSize:22];
        [self.postMenuButton setTitle:@"⋯" forState:UIControlStateNormal];
        [self.postMenuButton addTarget:self action:@selector(tapPostMenu) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:self.postMenuButton];
        self.metrics = [[UILabel alloc] init]; self.metrics.font = [UIFont systemFontOfSize:11]; self.metrics.textColor = [UIColor colorWithRed:.48 green:.55 blue:.62 alpha:1]; self.metrics.backgroundColor = [UIColor clearColor]; [self.contentView addSubview:self.metrics];
        self.likes = [[UILabel alloc] init]; self.likes.font=[UIFont boldSystemFontOfSize:11]; self.likes.textColor=OVKBlue(); self.likes.backgroundColor=[UIColor clearColor]; self.likes.textAlignment=NSTextAlignmentRight; [self.contentView addSubview:self.likes];
        self.likeIcon=[[UIImageView alloc] init]; self.likeIcon.contentMode=UIViewContentModeScaleAspectFit; [self.contentView addSubview:self.likeIcon];
        self.heading = [[UILabel alloc] init]; self.heading.font = [UIFont boldSystemFontOfSize:14]; self.heading.textColor = OVKBlue();
        self.bodyLabel = [[UILabel alloc] init]; self.bodyLabel.font = [UIFont systemFontOfSize:14]; self.bodyLabel.numberOfLines = 0;
        self.photo = [[OVKRemoteImageView alloc] init]; self.photo.contentMode = UIViewContentModeScaleAspectFit; self.photo.hidden = YES; self.photo.clipsToBounds=YES; self.photo.userInteractionEnabled=YES; [self.photo addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapPhoto)]];
        NSMutableArray *extra=[NSMutableArray array];
        for (NSUInteger index=1;index<3;index++) { OVKRemoteImageView *image=[[OVKRemoteImageView alloc] init]; image.tag=index; image.contentMode=UIViewContentModeScaleAspectFill; image.clipsToBounds=YES; image.userInteractionEnabled=YES; [image addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapExtra:)]]; [self.contentView addSubview:image]; [extra addObject:image]; } self.extraPhotos=extra;
        self.morePhotos=[[UILabel alloc] init]; self.morePhotos.backgroundColor=[UIColor colorWithWhite:0 alpha:.5]; self.morePhotos.textColor=[UIColor whiteColor]; self.morePhotos.font=[UIFont boldSystemFontOfSize:23]; self.morePhotos.textAlignment=NSTextAlignmentCenter; [self.contentView addSubview:self.morePhotos];
        self.commentButton=[UIButton buttonWithType:UIButtonTypeCustom]; self.commentButton.accessibilityLabel=OVKL(@"Комментарии"); [self.commentButton addTarget:self action:@selector(tapComments) forControlEvents:UIControlEventTouchUpInside]; [self.contentView addSubview:self.commentButton];
        self.unreadBadge=[[UILabel alloc] init]; self.unreadBadge.backgroundColor=OVKBlue(); self.unreadBadge.textColor=[UIColor whiteColor]; self.unreadBadge.font=[UIFont boldSystemFontOfSize:12]; self.unreadBadge.textAlignment=NSTextAlignmentCenter; self.unreadBadge.layer.cornerRadius=9; self.unreadBadge.clipsToBounds=YES; [self.contentView addSubview:self.unreadBadge];
        self.unreadBadge.backgroundColor=[UIColor clearColor]; self.unreadBadge.layer.cornerRadius=0;
        self.unreadBadgeSkin=[[UIImageView alloc] init]; [self.contentView insertSubview:self.unreadBadgeSkin belowSubview:self.unreadBadge];
        self.groupGlyph=[[UIImageView alloc] init]; self.groupGlyph.contentMode=UIViewContentModeScaleAspectFit; [self.contentView addSubview:self.groupGlyph];
        self.previewAvatar=[[OVKRemoteImageView alloc] init]; self.previewAvatar.maxPixelSize=48; self.previewAvatar.contentMode=UIViewContentModeScaleAspectFill; self.previewAvatar.clipsToBounds=YES; self.previewAvatar.hidden=YES; [self.contentView addSubview:self.previewAvatar];
        self.likeButton=[UIButton buttonWithType:UIButtonTypeCustom]; [self.likeButton addTarget:self action:@selector(tapLike) forControlEvents:UIControlEventTouchUpInside]; [self.contentView addSubview:self.likeButton];
        self.stamp = [[UILabel alloc] init]; self.stamp.font = [UIFont systemFontOfSize:11]; self.stamp.textColor = [UIColor grayColor];
        for (UIView *v in @[self.avatar,self.heading,self.bodyLabel,self.stamp,self.photo]) [self.contentView addSubview:v];
        self.selectionStyle = UITableViewCellSelectionStyleBlue;
        if (![reuseIdentifier isEqualToString:@"chat"]) self.backgroundView = [[UIImageView alloc] initWithImage:OVKThemeStretch(@"CellPanel")];
        self.heading.backgroundColor = [UIColor clearColor]; self.bodyLabel.backgroundColor = [UIColor clearColor]; self.stamp.backgroundColor = [UIColor clearColor];
    }
    return self;
}
- (void)tapPostMenu { if (self.postMenuTapped) self.postMenuTapped(); }
- (void)tapExtra:(UITapGestureRecognizer *)tap { if (self.photoIndexTapped) self.photoIndexTapped(tap.view.tag); }
- (void)tapLike { if (self.likeTapped) self.likeTapped(); }
- (void)tapComments { if (self.commentTapped) self.commentTapped(); }
- (void)tapPhoto { if (self.photoTapped) self.photoTapped(); }
- (void)tapAvatar { if (self.avatarTapped) self.avatarTapped(); }
- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated { [super setHighlighted:highlighted animated:animated]; if (self.dialogStyle || self.chatStyle) [self setNeedsLayout]; }
- (void)setSelected:(BOOL)selected animated:(BOOL)animated { [super setSelected:selected animated:animated]; if (self.dialogStyle || self.chatStyle) [self setNeedsLayout]; }
- (void)layoutSubviews {
    [super layoutSubviews]; CGFloat width = self.contentView.bounds.size.width; CGFloat height = self.contentView.bounds.size.height;
    CGFloat photoHeight = self.photo.hidden ? 0 : self.photoDisplayHeight;
    self.unreadBadge.hidden=!self.dialogStyle || !self.unread; self.unreadBadgeSkin.hidden=self.unreadBadge.hidden;
    self.groupGlyph.hidden=!self.dialogStyle || !self.conversationGroup; self.groupGlyph.image=OVKThemeIcon(@"MessageGroupGlyph");
    self.previewAvatar.hidden=!self.dialogStyle || !self.previewAvatar.source.length;
    self.bodyLabel.textColor=OVKThemeText(); self.stamp.textColor=OVKThemeSecondary(); self.heading.textColor=OVKDarkTheme() ? OVKThemeText() : OVKThemeAccent();
    self.contentView.opaque=!self.chatStyle; self.postHeader.opaque=YES; self.postFooter.opaque=YES;
    self.contentView.backgroundColor=self.chatStyle ? [UIColor clearColor] : OVKThemeSurface();
    self.postHeader.backgroundColor=OVKPostHeaderColor();
    self.postFooter.backgroundColor=OVKPostFooterColor();
    self.metrics.textColor=OVKThemeSecondary(); self.likes.textColor=OVKThemeAccent();
    self.postHeader.hidden=!self.postStyle; self.postFooter.hidden=!self.postStyle; self.commentButton.hidden=!self.postStyle;
    self.postMenuButton.hidden=!self.postStyle || !self.postMenuTapped;
    self.inlineAudio.hidden=!(self.postStyle || self.chatStyle) || !self.inlineAudio.tracks.count;
    self.quotedMessage.hidden=!self.chatStyle || !self.quotedMessage.text.length;
    self.postHeader.frame=CGRectMake(0,0,width,54); self.postFooter.frame=CGRectMake(0,height-48,width,48);
    for (NSUInteger index=0;index<self.extraPhotos.count;index++) { UIImageView *image=self.extraPhotos[index]; image.hidden=!self.postStyle || self.photoCount<index+2; }
    self.morePhotos.hidden=!self.postStyle || self.photoCount<=3;
    self.bubble.hidden = !self.chatStyle; self.metrics.hidden = !self.postStyle; self.likes.hidden = !self.postStyle; self.likeButton.hidden=!self.postStyle; self.likeIcon.hidden=!self.postStyle; self.likeIcon.image=OVKThemeIcon(self.liked ? @"PostLikeActive" : @"PostLike");
    self.photoGloss.hidden=!self.chatStyle || self.photo.hidden;
    if (!self.chatStyle) { self.photo.layer.cornerRadius=0; self.photo.layer.borderWidth=0; }
    self.heading.hidden = self.chatStyle; self.avatar.hidden = self.chatStyle && (self.outgoing || !self.conversationGroup);
    self.backgroundView.hidden = self.chatStyle || OVKDarkTheme();
    if (self.dialogStyle) {
        self.backgroundView.hidden=YES; BOOL selected=self.activeDialog || self.selected || self.highlighted; self.contentView.backgroundColor=selected ? OVKThemeAccent() : (self.unread ? (OVKDarkTheme() ? [UIColor colorWithRed:.22 green:.28 blue:.35 alpha:1] : [UIColor colorWithRed:.88 green:.91 blue:.94 alpha:1]) : OVKThemeSurface());
        self.avatar.frame=CGRectMake(8,12,50,50); self.avatar.layer.cornerRadius=0;
        CGFloat headingX=self.conversationGroup ? 88 : 68;
        self.groupGlyph.frame=CGRectMake(68,15,15,11);
        self.heading.font=[UIFont boldSystemFontOfSize:15]; self.heading.textColor=selected ? [UIColor whiteColor] : OVKThemeText(); self.heading.frame=CGRectMake(headingX,9,MAX(35,width-headingX-82),22);
        self.stamp.textAlignment=NSTextAlignmentRight; self.stamp.frame=CGRectMake(width-80,11,70,18);
        CGFloat previewX=self.previewAvatar.hidden ? 68 : 96;
        self.previewAvatar.frame=CGRectMake(68,36,23,23);
        self.bodyLabel.font=[UIFont systemFontOfSize:14]; self.bodyLabel.textColor=selected ? [UIColor whiteColor] : OVKThemeSecondary(); self.stamp.textColor=self.bodyLabel.textColor; self.bodyLabel.numberOfLines=2; self.bodyLabel.frame=CGRectMake(previewX,34,MAX(30,width-previewX-(self.unread ? 45 : 10)),34);
        self.unreadBadge.frame=CGRectMake(width-39,38,29,27); self.unreadBadgeSkin.frame=self.unreadBadge.frame; self.unreadBadgeSkin.image=OVKThemeStretch(@"MessageUnreadBadge");
        self.photo.hidden=YES;
    } else if (self.chatStyle) {
        CGFloat maxWidth=MAX(45,width-(self.conversationGroup && !self.outgoing ? 114 : 74));
        CGFloat textWidth=maxWidth-22;
        if (self.measuredWidth!=textWidth || self.measuredFontSize!=self.bodyLabel.font.pointSize || ![self.measuredText isEqualToString:self.bodyLabel.text]) {
            self.measuredText=self.bodyLabel.text; self.measuredWidth=textWidth; self.measuredFontSize=self.bodyLabel.font.pointSize;
            self.measuredBodySize=[self.bodyLabel.text sizeWithFont:self.bodyLabel.font constrainedToSize:CGSizeMake(textWidth,20000) lineBreakMode:NSLineBreakByWordWrapping];
        }
        CGSize bodySize=self.measuredBodySize;
        CGFloat quoteHeight=self.quotedMessage.hidden ? 0 : 34;
        CGFloat audioHeight=[OVKInlineAudioView heightForTracks:self.inlineAudio.tracks];
        CGFloat bubbleWidth=audioHeight>0 ? maxWidth : MIN(maxWidth,MAX(quoteHeight ? 142 : 50,MAX(ceil(bodySize.width)+22,self.photo.hidden ? 0 : self.chatPhotoWidth+22)));
        CGFloat x=self.outgoing ? width-bubbleWidth-8 : (self.conversationGroup ? 48 : 8);
        BOOL pressed=self.selected || self.highlighted;
        NSString *art=self.outgoing ? (pressed ? @"BubbleOutgoingSelected" : @"BubbleOutgoing") : (pressed ? @"BubbleIncomingSelected" : @"BubbleIncoming");
        NSString *key=[NSString stringWithFormat:@"%@/%@/%d",art,OVKThemeColor(),OVKDarkTheme()];
        if (![self.bubbleArtworkKey isEqualToString:key]) {
            self.bubbleArtworkKey=key;
            // Stretch the middle of the sprite while preserving its corners and tail.
            self.bubble.image=[OVKThemeChrome(art) resizableImageWithCapInsets:UIEdgeInsetsMake(15,18,15,18) resizingMode:UIImageResizingModeStretch];
        }
        self.bubble.frame=CGRectMake(x,5,bubbleWidth,height-10);
        self.avatar.frame = CGRectMake(8,MAX(6,height-38),30,30);
        self.quotedMessage.frame=CGRectMake(x+11,11,bubbleWidth-22,30);
        self.quotedMessage.textColor=OVKThemeAccent();
        self.quotedMessage.backgroundColor=[OVKPostFooterColor() colorWithAlphaComponent:.8];
        self.quotedMessage.clipsToBounds=YES; self.quotedMessage.layer.cornerRadius=4;
        self.bodyLabel.frame=CGRectMake(x+11,12+quoteHeight,bubbleWidth-22,ceil(bodySize.height));
        self.photo.frame=CGRectMake(x+11,height-14-photoHeight-audioHeight,MIN(bubbleWidth-22,self.chatPhotoWidth),photoHeight);
        self.inlineAudio.frame=CGRectMake(x+11,height-14-audioHeight,bubbleWidth-22,audioHeight);
        self.photo.contentMode=UIViewContentModeScaleAspectFit;
        self.photo.layer.cornerRadius=11;
        self.photo.layer.borderWidth=1.0/[UIScreen mainScreen].scale;
        self.photo.layer.borderColor=[UIColor colorWithWhite:0 alpha:.26].CGColor;
        if (!self.photo.hidden) {
            if (!self.photoGloss) {
                self.photoGloss=[CAGradientLayer layer];
                self.photoGloss.colors=@[(__bridge id)[UIColor colorWithWhite:1 alpha:.30].CGColor,(__bridge id)[UIColor colorWithWhite:1 alpha:0].CGColor];
                [self.photo.layer addSublayer:self.photoGloss];
            }
            [CATransaction begin]; [CATransaction setDisableActions:YES];
            self.photoGloss.hidden=NO;
            self.photoGloss.frame=CGRectMake(0,0,self.photo.bounds.size.width,MIN(32,photoHeight*.25));
            [CATransaction commit];
        }
        self.stamp.frame=CGRectMake(self.outgoing ? MAX(0,x-58) : x+bubbleWidth+4,height-23,54,14); self.stamp.textAlignment=self.outgoing ? NSTextAlignmentRight : NSTextAlignmentLeft;
    } else if (self.postStyle) {
        CGFloat audioHeight=[OVKInlineAudioView heightForTracks:self.inlineAudio.tracks];
        self.stamp.textAlignment=NSTextAlignmentLeft;
        self.avatar.frame = CGRectMake(8,7,36,36); self.heading.frame = CGRectMake(53,6,width-(self.postMenuButton.hidden ? 63 : 96),21);
        self.postMenuButton.frame=CGRectMake(width-43,3,39,39);
        [self.postMenuButton setTitleColor:OVKThemeAccent() forState:UIControlStateNormal];
        self.postMenuButton.accessibilityLabel=OVKL(@"Действия с записью");
        self.stamp.frame = CGRectMake(53,28,width-63,15);
        self.bodyLabel.frame = CGRectMake(8,60,width-16,MAX(20,height-116-photoHeight-audioHeight));
        // Keep attachments below the text and above the fixed comment/like footer.
        CGFloat y=height-52-photoHeight-audioHeight;
        self.photo.frame=CGRectMake(0,y,width,photoHeight); self.photo.contentMode=self.photoCount>1 ? UIViewContentModeScaleAspectFill : UIViewContentModeScaleAspectFit;
        self.inlineAudio.frame=CGRectMake(8,height-50-audioHeight,MAX(0,width-16),audioHeight);
        OVKPhotoRect frames[3]; unsigned visible=OVKFeedPhotoLayout((unsigned)self.photoCount,width,photoHeight,frames);
        NSArray *images=@[self.photo,self.extraPhotos[0],self.extraPhotos[1]];
        for (unsigned index=0;index<visible;index++) { UIView *image=images[index]; OVKPhotoRect frame=frames[index]; image.frame=CGRectMake(frame.x,y+frame.y,frame.width,frame.height); }
        if (visible==3) self.morePhotos.frame=((UIView *)self.extraPhotos[1]).frame;
        CGFloat half=floor(width/2);
        self.commentButton.frame=CGRectMake(0,height-48,half,48);
        self.commentButton.accessibilityLabel=[NSString stringWithFormat:OVKL(@"Комментарии · %@"),self.metrics.text ?: @"0"];
        [self.commentButton setTitleColor:OVKThemeAccent() forState:UIControlStateNormal];
        self.commentButton.titleLabel.font=[UIFont boldSystemFontOfSize:13];
        [self.commentButton setTitle:self.metrics.text forState:UIControlStateNormal];
        [self.commentButton setImage:OVKThemeIcon(@"PostComment") forState:UIControlStateNormal];
        self.commentButton.imageEdgeInsets=UIEdgeInsetsMake(0,-5,0,5);
        self.metrics.hidden=YES; self.likes.font=[UIFont boldSystemFontOfSize:13];
        self.likeIcon.alpha=(self.liked ? 1 : .65)*(self.likeButton.enabled ? 1 : .35);
        self.likes.textColor=self.liked ? OVKThemeAccent() : OVKThemeSecondary();
        self.likeButton.frame=CGRectMake(half,height-48,width-half,48);
        self.likeButton.accessibilityLabel=self.liked ? OVKL(@"Убрать отметку «Нравится»") : OVKL(@"Нравится");
        self.likeButton.accessibilityValue=self.likes.text;
        CGFloat likeCenter=(width+half)/2;
        self.likeIcon.frame=CGRectMake(likeCenter-22,height-32,16,16);
        self.likes.frame=CGRectMake(likeCenter,height-42,44,34);
        self.likes.textAlignment=NSTextAlignmentLeft;
    } else if (self.peopleStyle) {
        // Keep the avatar and the two lines centered in the compact 60-point row.
        self.avatar.frame=CGRectMake(10,floor((height-40)/2),40,40);
        self.heading.frame=CGRectMake(60,floor((height-38)/2),MAX(0,width-70),20);
        self.bodyLabel.frame=CGRectMake(60,CGRectGetMaxY(self.heading.frame),MAX(0,width-70),18);
        self.bodyLabel.textColor=[OVKThemeText() colorWithAlphaComponent:.60];
        self.stamp.hidden=YES;
        self.photo.hidden=YES;
    } else {
        self.stamp.textAlignment=NSTextAlignmentLeft;
        self.avatar.frame = CGRectMake(10,12,45,45); self.heading.frame = CGRectMake(65,10,width-78,20);
        self.bodyLabel.frame = CGRectMake(65,34,width-78,MAX(20,height-60-photoHeight));
        self.photo.frame = CGRectMake(65,height-22-photoHeight,width-78,photoHeight-8);
        self.stamp.frame = CGRectMake(65,height-22,width-78,16);
    }
}

@end
@interface OVKListController () <UIAlertViewDelegate,UIActionSheetDelegate,UITableViewDataSource,UITableViewDelegate,UISearchBarDelegate,UITextFieldDelegate,UIGestureRecognizerDelegate>
@property (strong, nonatomic) UITableView *tableView;
@property (strong, nonatomic) UIRefreshControl *refreshControl;
@property (strong, nonatomic) UISearchBar *search;
@property (strong, nonatomic) UIView *composerBar;
@property (strong, nonatomic) UITextField *messageField;
@property (strong, nonatomic) UIButton *sendButton;
@property (strong, nonatomic) UIButton *chatAttachButton;
@property (strong, nonatomic) UIView *chatReplyBar;
@property (strong, nonatomic) UILabel *chatReplyLabel;
@property (strong, nonatomic) UIButton *chatReplyCancel;
@property (copy, nonatomic) NSDictionary *chatReply;
@property (copy, nonatomic) NSDictionary *swipedChatMessage;
@property (copy, nonatomic) NSDictionary *messageToEdit;
@property (strong, nonatomic) UIButton *chatTitleButton;
@property (strong, nonatomic) UIBarButtonItem *chatEditItem;
@property (strong, nonatomic) UIBarButtonItem *chatDeleteItem;
@property (strong, nonatomic) UIActivityIndicatorView *chatLoadingSpinner;
@property (strong, nonatomic) UIBarButtonItem *chatLoadingItem;
@property (assign, nonatomic) BOOL deletingMessages;
@property (assign, nonatomic) CGFloat keyboardHeight;
@property (assign, nonatomic) BOOL sending;
@property (strong, nonatomic) NSNumber *pendingRandomID;
@property (copy, nonatomic) NSString *pendingMessage;
@property (strong, nonatomic) NSMutableDictionary *rowHeights;
@property (strong, nonatomic) NSMutableSet *postRequests;
@property (strong, nonatomic) NSDictionary *actionPost;
@property (strong, nonatomic) NSArray *postActions;
@property (strong, nonatomic) UIPopoverController *sharePopover;
@property (copy, nonatomic) NSString *mode;
@property (copy, nonatomic) NSString *selectedDialogPeer;
@property (strong, nonatomic) NSNumber *identifier;
@property (strong, nonatomic) NSMutableArray *items;
@property (strong, nonatomic) NSMutableDictionary *people;
@property (strong, nonatomic) NSDictionary *user;
@property (assign, nonatomic) NSInteger friendshipStatus;
@property (assign, nonatomic) BOOL friendshipLoading;
@property (assign, nonatomic) BOOL friendshipChanging;
@property (assign, nonatomic) NSUInteger friendshipGeneration;
@property (copy, nonatomic) NSString *friendshipError;
@property (strong, nonatomic) NSArray *profilePhotos;
@property (assign, nonatomic) BOOL profileInfo;
@property (assign, nonatomic) BOOL ownerOnly;
@property (strong, nonatomic) UISegmentedControl *profileTabs;
@property (strong, nonatomic) NSDictionary *singlePost;
@property (copy, nonatomic) NSString *nextCursor;
@property (assign, nonatomic) BOOL loading;
@property (assign, nonatomic) BOOL needsWallRefresh;
@property (assign, nonatomic) CGFloat layoutWidth;
@property (assign, nonatomic) BOOL more;
@property (assign, nonatomic) NSUInteger generation;
@property (strong, nonatomic) UIButton *footer;
@property (strong, nonatomic) UIView *footerContainer;
@property (strong, nonatomic) UILabel *notice;
@property (strong, nonatomic) UISegmentedControl *newsTabs;
@property (strong, nonatomic) UIActivityIndicatorView *historySpinner;
@property (assign, nonatomic) BOOL instanceNews;
@property (assign, nonatomic) BOOL historyTriggerPending;
@property (assign, nonatomic) BOOL historyAutomaticFailed;
@property (assign, nonatomic) NSUInteger historyOffset;
@property (assign, nonatomic) NSTimeInterval lastRefreshStarted;
@end
@implementation OVKListController
@synthesize messageDraft = _messageDraft;
- (NSString *)messageDraft { return self.messageField ? self.messageField.text : _messageDraft; }
- (void)setMessageDraft:(NSString *)text { _messageDraft=[text copy]; self.messageField.text=text; }
- (BOOL)hasPendingMessage { return self.sending; }
- (id)initWithMode:(NSString *)mode identifier:(NSNumber *)identifier title:(NSString *)title {
    self = [super init];
    if (self) { self.rowHeights=[NSMutableDictionary dictionary]; self.postRequests=[NSMutableSet set]; self.friendshipStatus=-1; self.mode = mode; self.identifier = identifier; self.title = title; self.items = [NSMutableArray array]; self.people = [NSMutableDictionary dictionary]; }
    return self;
}
- (BOOL)isProfile { return [self.mode isEqualToString:@"profile"]; }
- (BOOL)isChat { return [self.mode isEqualToString:@"chat"]; }
- (BOOL)isPeopleList { return [@[@"friends",@"followers",@"mutual"] containsObject:self.mode]; }
- (CGFloat)wallContentWidth { return self.tableView.bounds.size.width; }
- (void)setWallHeaderView:(UIView *)header {
    self.tableView.tableHeaderView=header;
}
- (id)initWithPostObject:(NSDictionary *)post profiles:(NSArray *)profiles groups:(NSArray *)groups {
    self=[self initWithMode:@"post" identifier:nil title:OVKL(@"Запись")]; if (self) { self.singlePost=post; [self indexPeople:@{@"profiles":profiles ?: @[],@"groups":groups ?: @[]}]; } return self;
}
- (BOOL)isFeed { return [self.mode isEqualToString:@"news"] || [self.mode isEqualToString:@"archive"] || [self isProfile] || [self isPost] || [self.mode isEqualToString:@"groupWall"]; }
- (BOOL)isPost { return [self.mode isEqualToString:@"post"]; }
- (void)viewDidLoad {
    [super viewDidLoad]; OVKConfigureEdges(self);
    self.tableView=[[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain]; self.tableView.dataSource=self; self.tableView.delegate=self; self.tableView.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; [self.view addSubview:self.tableView];
    self.tableView.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"Linen"]]; self.tableView.separatorColor = [UIColor colorWithWhite:.87 alpha:1];
    if ([self isChat]) { self.tableView.separatorStyle=UITableViewCellSeparatorStyleNone; self.tableView.backgroundColor=[UIColor colorWithRed:.88 green:.91 blue:.94 alpha:1]; }
    if (![self isChat]) { self.refreshControl = [[UIRefreshControl alloc] init]; [self.tableView addSubview:self.refreshControl]; [self.refreshControl addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged]; }
    self.notice = [[UILabel alloc] initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,35)];
    self.notice.autoresizingMask=UIViewAutoresizingFlexibleWidth; self.notice.numberOfLines=2;
    self.notice.textAlignment=NSTextAlignmentCenter; self.notice.font=[UIFont systemFontOfSize:12];
    self.notice.backgroundColor=[UIColor clearColor]; self.tableView.tableHeaderView=self.notice;
    self.footer = [UIButton buttonWithType:UIButtonTypeCustom]; self.footer.frame = CGRectMake(0,8,180,33); self.footer.titleLabel.font = [UIFont boldSystemFontOfSize:13]; [self.footer setTitleColor:OVKBlue() forState:UIControlStateNormal]; [self.footer addTarget:self action:@selector(loadMore) forControlEvents:UIControlEventTouchUpInside]; OVKStyleAssetButton(self.footer,@"FooterButton"); self.footerContainer=[[UIView alloc] initWithFrame:CGRectMake(0,0,self.tableView.bounds.size.width,50)]; [self.footerContainer addSubview:self.footer]; self.tableView.tableFooterView = self.footerContainer;
    if ([self.mode isEqualToString:@"news"] || ([self isProfile] && [self.identifier isEqual:[OVKAPI shared].userID])) self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose target:self action:@selector(compose)];
    if ([self.mode isEqualToString:@"news"]) {
        self.newsTabs=[[UISegmentedControl alloc] initWithItems:@[OVKL(@"Подписки"),OVKL(@"Все")]];
        self.newsTabs.segmentedControlStyle=UISegmentedControlStyleBar;
        self.newsTabs.frame=CGRectMake(0,0,155,30);
        self.newsTabs.selectedSegmentIndex=0;
        [self.newsTabs addTarget:self action:@selector(newsScopeChanged) forControlEvents:UIControlEventValueChanged];
        self.navigationItem.titleView=self.newsTabs;
    }
    if ([self.mode isEqualToString:@"dialogs"] || [self isPeopleList]) { self.search=[[UISearchBar alloc] initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,44)]; self.search.placeholder=[self isPeopleList] ? OVKL(@"Поиск людей") : OVKL(@"Поиск диалогов"); self.search.delegate=self; self.search.tintColor=[UIColor colorWithRed:.74 green:.78 blue:.81 alpha:1]; self.search.autoresizingMask=UIViewAutoresizingFlexibleWidth; self.tableView.tableHeaderView=self.search; }
    if ([self isChat]) {
        self.tableView.tableFooterView=nil;
        UIButton *titleButton=[UIButton buttonWithType:UIButtonTypeCustom]; titleButton.frame=CGRectMake(0,0,MAX(82,MIN(245,self.view.bounds.size.width-180)),40); titleButton.titleLabel.font=[UIFont boldSystemFontOfSize:14]; titleButton.titleLabel.numberOfLines=2; titleButton.titleLabel.textAlignment=NSTextAlignmentCenter; [titleButton setTitle:self.title forState:UIControlStateNormal]; [titleButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal]; titleButton.enabled=self.identifier.longLongValue>0 && self.identifier.longLongValue<2000000000LL; [titleButton addTarget:self action:@selector(openChatProfile) forControlEvents:UIControlEventTouchUpInside]; self.chatTitleButton=titleButton; self.navigationItem.titleView=titleButton;
        [self configureChatActions];
        UIView *history=[[UIView alloc] initWithFrame:CGRectMake(0,0,self.tableView.bounds.size.width,40)];
        self.historySpinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        self.historySpinner.center=CGPointMake(22,20); self.historySpinner.hidesWhenStopped=YES;
        [history addSubview:self.historySpinner];
        self.notice.frame=CGRectMake(40,0,MAX(0,history.bounds.size.width-80),40);
        self.notice.textAlignment=NSTextAlignmentCenter; [history addSubview:self.notice];
        self.tableView.tableHeaderView=history;
        self.composerBar=[[UIView alloc] init]; self.composerBar.backgroundColor=[UIColor colorWithPatternImage:[UIImage imageNamed:@"SectionBar"]]; [self.view addSubview:self.composerBar];
        self.chatAttachButton=[UIButton buttonWithType:UIButtonTypeCustom];
        self.chatAttachButton.titleLabel.font=[UIFont boldSystemFontOfSize:21];
        [self.chatAttachButton setTitle:@"+" forState:UIControlStateNormal];
        self.chatAttachButton.accessibilityLabel=OVKL(@"Добавить вложение");
        [self.chatAttachButton addTarget:self action:@selector(openChatAttachmentComposer) forControlEvents:UIControlEventTouchUpInside];
        [self.composerBar addSubview:self.chatAttachButton];
        self.chatReplyBar=[[UIView alloc] init]; self.chatReplyBar.hidden=YES; [self.composerBar addSubview:self.chatReplyBar];
        self.chatReplyLabel=[[UILabel alloc] init]; self.chatReplyLabel.numberOfLines=2; self.chatReplyLabel.font=[UIFont systemFontOfSize:12];
        self.chatReplyLabel.backgroundColor=[UIColor clearColor]; [self.chatReplyBar addSubview:self.chatReplyLabel];
        self.chatReplyCancel=[UIButton buttonWithType:UIButtonTypeCustom]; [self.chatReplyCancel setTitle:@"×" forState:UIControlStateNormal];
        self.chatReplyCancel.titleLabel.font=[UIFont boldSystemFontOfSize:20]; self.chatReplyCancel.accessibilityLabel=OVKL(@"Отменить ответ");
        [self.chatReplyCancel addTarget:self action:@selector(clearChatReply) forControlEvents:UIControlEventTouchUpInside]; [self.chatReplyBar addSubview:self.chatReplyCancel];
        self.messageField=[[OVKMessageField alloc] init]; self.messageField.borderStyle=UITextBorderStyleRoundedRect; self.messageField.font=[UIFont systemFontOfSize:15]; self.messageField.placeholder=OVKL(@"Написать сообщение"); self.messageField.delegate=self; self.messageField.returnKeyType=UIReturnKeySend; self.messageField.contentVerticalAlignment=UIControlContentVerticalAlignmentCenter; [self.composerBar addSubview:self.messageField];
        self.messageField.text=_messageDraft; [self.messageField addTarget:self action:@selector(chatDraftChanged) forControlEvents:UIControlEventEditingChanged];
        self.sendButton=[[OVKMessageSendButton alloc] initWithFrame:CGRectZero]; [self.sendButton setImage:OVKSendPlane() forState:UIControlStateNormal]; self.sendButton.accessibilityLabel=OVKL(@"Отправить"); [self.sendButton addTarget:self action:@selector(sendMessage) forControlEvents:UIControlEventTouchUpInside]; [self.composerBar addSubview:self.sendButton];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(chatKeyboard:) name:UIKeyboardWillChangeFrameNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(chatKeyboard:) name:UIKeyboardWillHideNotification object:nil];
    }
    if ([self isProfile]) {
        self.profileTabs=[[UISegmentedControl alloc] initWithItems:@[OVKL(@"Профиль"),OVKL(@"Информация")]]; self.profileTabs.segmentedControlStyle=UISegmentedControlStyleBar; self.profileTabs.frame=CGRectMake(0,0,170,30); self.profileTabs.selectedSegmentIndex=0; [self.profileTabs addTarget:self action:@selector(profileTabChanged:) forControlEvents:UIControlEventValueChanged]; self.navigationItem.titleView=self.profileTabs;
        self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(profileActions)];
    }
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:@"OVKThemeChanged" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appearanceChanged:) name:@"OVKAppearanceChanged" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(languageChanged:) name:@"OVKLanguageChanged" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(wallChanged:) name:@"OVKWallChanged" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(revalidateVisibleList:) name:UIApplicationDidBecomeActiveNotification object:nil];
    if ([self isFeed]) { UILongPressGestureRecognizer *press=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(postHeld:)]; press.minimumPressDuration=.6; [self.tableView addGestureRecognizer:press]; }
    [self applyTheme];
    if ([self isPost]) { [self.items addObject:self.singlePost ?: @{}]; self.notice.text = OVKL(@"Запись"); [self.footer setTitle:OVKL(@"Комментарии и ответы") forState:UIControlStateNormal]; self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(openPost)]; }
    else [self refresh];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self revalidateIfNeeded];
}
- (void)revalidateVisibleList:(NSNotification *)note {
    if (self.view.window && self.navigationController.topViewController==self) [self revalidateIfNeeded];
}
- (void)revalidateIfNeeded {
    if (![self isPost] && !self.loading && self.lastRefreshStarted>0 && [NSDate timeIntervalSinceReferenceDate]-self.lastRefreshStarted>25) [self refresh];
}
- (void)applyTheme {
    OVKThemeTable(self.tableView); if ([self isChat] && !OVKDarkTheme()) self.tableView.backgroundColor=[UIColor colorWithRed:.88 green:.91 blue:.94 alpha:1];
    self.notice.backgroundColor=[UIColor clearColor]; self.notice.textColor=OVKThemeSecondary();
    [self.chatAttachButton setTitleColor:OVKThemeAccent() forState:UIControlStateNormal];
    [self.chatReplyCancel setTitleColor:OVKThemeAccent() forState:UIControlStateNormal];
    self.chatReplyBar.backgroundColor=OVKPostFooterColor(); self.chatReplyLabel.textColor=OVKThemeText();
    OVKThemeButtons(self.view);
    self.composerBar.backgroundColor=[UIColor colorWithPatternImage:OVKThemeChrome(@"MessageBar")]; self.messageField.borderStyle=UITextBorderStyleNone; self.messageField.background=OVKThemeStretch(@"MessageField"); self.messageField.backgroundColor=[UIColor clearColor];
    OVKStyleAssetButton(self.sendButton,@"SendButton"); [self.sendButton setBackgroundImage:OVKThemeStretch(@"SendButtonPressed") forState:UIControlStateHighlighted]; [self.sendButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal]; self.messageField.textColor=OVKThemeText(); self.messageField.keyboardAppearance=OVKDarkTheme() ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
    self.search.tintColor=OVKDarkTheme() ? [UIColor colorWithWhite:.2 alpha:1] : [UIColor colorWithRed:.74 green:.78 blue:.81 alpha:1];
    self.profileTabs.tintColor=OVKThemeAccent();
    self.newsTabs.tintColor=OVKThemeAccent();
    OVKStyleAssetButton(self.footer,@"FooterButton"); [self.footer setTitleColor:OVKThemeAccent() forState:UIControlStateNormal];
}
- (void)themeChanged:(NSNotification *)note { [self applyTheme]; [self.tableView reloadData]; if ([self isProfile]) [self updateProfileHeader]; }
- (void)didReceiveMemoryWarning { [super didReceiveMemoryWarning]; [self.rowHeights removeAllObjects]; }
- (void)appearanceChanged:(NSNotification *)note { [self.rowHeights removeAllObjects]; if ([self isFeed]) [self.tableView reloadData]; }
- (void)languageChanged:(NSNotification *)note { [self.rowHeights removeAllObjects];
    if ([self isChat]) [self updateChatActions];
    [self.newsTabs setTitle:OVKL(@"Подписки") forSegmentAtIndex:0];
    [self.newsTabs setTitle:OVKL(@"Все") forSegmentAtIndex:1];
    self.search.placeholder=[self isPeopleList] ? OVKL(@"Поиск людей") : OVKL(@"Поиск диалогов"); self.messageField.placeholder=OVKL(@"Написать сообщение"); self.sendButton.accessibilityLabel=OVKL(@"Отправить");
    if ([self isProfile]) { [self.profileTabs setTitle:OVKL(@"Профиль") forSegmentAtIndex:0]; [self.profileTabs setTitle:OVKL(@"Информация") forSegmentAtIndex:1]; [self updateProfileHeader]; }
    self.notice.text=self.items.count ? @"" : OVKL(@"Пока ничего нет");
    [self.footer setTitle:[self isPost] ? OVKL(@"Комментарии и ответы") : (self.more ? OVKL(@"Показать ещё") : OVKL(@"Обновить")) forState:UIControlStateNormal]; [self.tableView reloadData];
}
- (void)askLogout { [[[UIAlertView alloc] initWithTitle:OVKL(@"Выйти из аккаунта?") message:OVKL(@"Токен будет удалён с устройства. Для отзыва всех сеансов используйте настройки безопасности OpenVK.") delegate:self cancelButtonTitle:OVKL(@"Отмена") otherButtonTitles:OVKL(@"Выйти"),nil] show]; }
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag==1002) { if (buttonIndex!=alertView.cancelButtonIndex) [self performPostAction:@"delete" post:self.actionPost]; return; }
    if (alertView.tag==1004) { if (buttonIndex!=alertView.cancelButtonIndex) [self deleteSelectedMessagesForEveryone:buttonIndex==alertView.firstOtherButtonIndex+1]; return; }
    if (buttonIndex==1) [[OVKAPI shared] logout];
}
- (void)refresh {
    if ([self isChat] && (self.tableView.editing || self.deletingMessages)) { self.needsWallRefresh=YES; return; }
    if ([self isPost]) { [self refreshPost]; return; }
    if (self.loading) { if ([self isChat]) self.needsWallRefresh=YES; [self.refreshControl endRefreshing]; return; }
    self.nextCursor = nil; [self fetch:NO];
}
- (void)newsScopeChanged {
    self.instanceNews=self.newsTabs.selectedSegmentIndex==1;
    self.generation++;
    self.loading=NO; self.more=NO; self.nextCursor=nil;
    [self.items removeAllObjects]; [self.people removeAllObjects]; [self.rowHeights removeAllObjects];
    [self.tableView reloadData];
    [self.tableView setContentOffset:CGPointMake(0,-self.tableView.contentInset.top) animated:NO];
    [self refresh];
}
- (void)loadMore {
    if ([self isPost]) { [self openCommentsFor:self.singlePost]; return; }
    if (self.loading || ([self isChat] && self.tableView.editing)) return;
    if ([self isChat] && !self.more && self.items.count) return;
    self.historyAutomaticFailed=NO;
    [self fetch:self.items.count > 0 && self.more];
}
- (void)scrollViewDidScroll:(UIScrollView *)scroll {
    if (![self isChat] || scroll!=self.tableView || self.tableView.editing || self.loading || !self.more || self.historyTriggerPending || self.historyAutomaticFailed) return;
    if ((!scroll.dragging && !scroll.decelerating) || scroll.contentOffset.y+scroll.contentInset.top>65) return;
    self.historyTriggerPending=YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.historyTriggerPending=NO;
        if (self.view.window && !self.tableView.editing && !self.loading && self.more && self.tableView.contentOffset.y+self.tableView.contentInset.top<=65) [self fetch:YES];
    });
}
- (void)scrollViewWillBeginDragging:(UIScrollView *)scroll {
    if ([self isChat] && scroll==self.tableView) self.historyAutomaticFailed=NO;
}
- (void)indexPeople:(NSDictionary *)response {
    for (id value in OVKArray(response[@"profiles"])) { NSDictionary *person = OVKDictionary(value); if (person[@"id"]) self.people[OVKString(person[@"id"])] = person; }
    for (id value in OVKArray(response[@"groups"])) { NSDictionary *group = OVKDictionary(value); if (group[@"id"]) self.people[OVKString(@(-[group[@"id"] longLongValue]))] = group; }
}
- (void)collectFriendsFor:(NSNumber *)user offset:(NSUInteger)offset items:(NSMutableDictionary *)items completion:(OVKCompletion)completion {
    NSDictionary *params=@{@"user_id":user,@"offset":@(offset),@"count":@100,@"fields":@"photo_100,photo_50,online"};
    __block id saved=nil;
    [[OVKAPI shared] call:@"friends.get" parameters:params cached:^(id result) { saved=result; } completion:^(id result,NSError *error) {
        NSDictionary *response=OVKDictionary(result ?: saved);
        if (![response[@"items"] isKindOfClass:[NSArray class]]) { completion(nil,error); return; }
        NSArray *page=response[@"items"];
        NSUInteger before=items.count;
        for (id value in page) {
            NSDictionary *person=OVKDictionary(value);
            NSString *key=OVKString(person[@"id"]);
            if (key.length) items[key]=person;
        }
        NSUInteger next=offset+page.count, total=[OVKString(response[@"count"]) integerValue];
        if (page.count && items.count>before && (total ? next<total : page.count>=100)) {
            [self collectFriendsFor:user offset:next items:items completion:completion];
        } else completion(items,nil);
    }];
}
- (void)fetchMutual {
    NSNumber *me=[OVKAPI shared].userID;
    if (!me || [me isEqual:self.identifier]) { self.notice.text=OVKL(@"Пока ничего нет"); return; }
    self.loading=YES;
    NSUInteger generation=++self.generation;
    self.notice.text=OVKL(@"Загрузка…");
    [self collectFriendsFor:me offset:0 items:[NSMutableDictionary dictionary] completion:^(id mine,NSError *firstError) {
        if (generation!=self.generation) return;
        if (!mine) {
            self.loading=NO; self.notice.text=firstError.localizedDescription ?: OVKL(@"Не удалось загрузить раздел");
            [self.refreshControl endRefreshing]; return;
        }
        [self collectFriendsFor:self.identifier offset:0 items:[NSMutableDictionary dictionary] completion:^(id theirs,NSError *error) {
            if (generation!=self.generation) return;
            self.loading=NO; [self.refreshControl endRefreshing];
            if (!theirs) { self.notice.text=error.localizedDescription ?: OVKL(@"Не удалось загрузить раздел"); return; }
            NSMutableArray *common=[NSMutableArray array];
            for (NSString *key in mine) if (theirs[key]) [common addObject:theirs[key]];
            [common sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) { return [OVKName(a) localizedCaseInsensitiveCompare:OVKName(b)]; }];
            [self applyListResponse:@{@"items":common,@"count":@(common.count)} append:NO offset:0 pageSize:NSUIntegerMax];
        }];
    }];
}
- (BOOL)applyListResponse:(id)result append:(BOOL)append offset:(NSUInteger)offset pageSize:(NSUInteger)pageSize {
    NSDictionary *response=OVKDictionary(result);
    if (![response[@"items"] isKindOfClass:[NSArray class]]) return NO;
    NSArray *incoming=response[@"items"];
    if ([self.mode isEqualToString:@"followers"] && response[@"count"] && [OVKString(response[@"count"]) integerValue]==0) incoming=@[];
    BOOL chat=[self isChat], latest=NO;
    CGFloat anchorDelta=0;
    NSDictionary *anchor=nil;
    if (chat && self.items.count) {
        // Keep the first visible message and its pixel offset when older pages change every row index.
        CGFloat bottom=MAX(-self.tableView.contentInset.top,self.tableView.contentSize.height-self.tableView.bounds.size.height+self.tableView.contentInset.bottom);
        latest=self.tableView.contentOffset.y>=bottom-42;
        NSIndexPath *first=nil;
        for (NSIndexPath *path in self.tableView.indexPathsForVisibleRows) if (!first || path.row<first.row) first=path;
        if (first && (NSUInteger)first.row<self.items.count) {
            anchor=self.items[first.row];
            anchorDelta=self.tableView.contentOffset.y-CGRectGetMinY([self.tableView rectForRowAtIndexPath:first]);
        }
    }
    [self.rowHeights removeAllObjects];
    if (!append && !chat) {
        [self.items removeAllObjects]; [self.people removeAllObjects];
        if (self.user[@"id"]) self.people[OVKString(self.user[@"id"])]=self.user;
    }
    [self indexPeople:response];
    if (chat) {
        self.items=[OVKMergeChatHistory(self.items,incoming,append) mutableCopy];
        self.historyOffset=append ? MAX(self.historyOffset,offset+incoming.count) : MAX(incoming.count,self.items.count);
    } else if ([self isPeopleList]) {
        for (id value in incoming) {
            NSDictionary *person=OVKDictionary(value);
            if (!person.count) person=OVKDictionary(self.people[OVKString(value)]);
            if (person[@"id"]) [self.items addObject:person];
        }
    } else {
        for (id value in incoming) if ([value isKindOfClass:[NSDictionary class]]) [self.items addObject:value];
    }
    self.nextCursor=OVKString(response[@"next_from"]);
    NSUInteger loaded=chat ? self.historyOffset : offset+incoming.count;
    NSUInteger total=[OVKString(response[@"count"]) integerValue];
    self.more=![OVKAPI shared].demo && (self.nextCursor.length || (incoming.count>=pageSize && (!total || loaded<total)));
    self.notice.text=self.items.count ? @"" : OVKL(@"Пока ничего нет");
    if ([self.mode isEqualToString:@"archive"] && !self.items.count) self.notice.text=OVKL(@"Архив пуст. Здесь показываются записи, ранее перенесённые в архив OpenVK.");
    if (self.tableView.tableHeaderView==self.notice || (!self.tableView.tableHeaderView && ![self isProfile])) {
        self.tableView.tableHeaderView=self.items.count ? nil : self.notice;
    }
    [self.footer setTitle:self.more ? OVKL(@"Показать ещё") : OVKL(@"Обновить") forState:UIControlStateNormal];
    [self.tableView reloadData];
    if (chat) {
        if (!append && (!anchor || latest)) [self scrollToLatest];
        else if (anchor) {
            NSString *key=OVKChatMessageKey(anchor);
            NSUInteger index=[self.items indexOfObjectPassingTest:^BOOL(NSDictionary *message,NSUInteger idx,BOOL *stop) {
                return message==anchor || (key.length && [OVKChatMessageKey(message) isEqualToString:key]);
            }];
            if (index!=NSNotFound) {
                [self.tableView layoutIfNeeded];
                CGRect row=[self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:0]];
                [self.tableView setContentOffset:CGPointMake(0,CGRectGetMinY(row)+anchorDelta) animated:NO];
            }
        }
    }
    if ([self.mode isEqualToString:@"archive"]) self.tableView.tableFooterView=self.items.count ? self.footerContainer : nil;
    if ([self isProfile]) [self updateProfileHeader];
    if (chat) [self updateChatActions];
    return YES;
}
- (void)fetch:(BOOL)append {
    if (!append) self.lastRefreshStarted=[NSDate timeIntervalSinceReferenceDate];
    if ([self.mode isEqualToString:@"mutual"]) { [self fetchMutual]; return; }
    self.loading = YES; NSUInteger generation = ++self.generation;
    [self.footer setTitle:OVKL(@"Загрузка…") forState:UIControlStateNormal];
    if (!self.items.count || ([self isChat] && append)) self.notice.text=OVKL(@"Загрузка…");
    [self.historySpinner startAnimating];
    if ([self isChat]) [self updateChatActions];
    if ([self isProfile] && !append) {
        [self loadFriendship];
        void (^showUser)(id)=^(id result) {
            if (generation != self.generation) return;
            if (OVKArray(result).count) { self.user = OVKDictionary(result[0]); if (self.user[@"id"]) self.people[OVKString(self.user[@"id"])] = self.user; [self updateProfileHeader]; }
        };
        [[OVKAPI shared] call:@"users.get" parameters:@{@"user_ids":self.identifier,@"fields":@"photo_100,photo_200,photo_max_orig,status,online,city,about,counters,verified,common_count,rating"} cached:^(id result) {
            if (!self.user.count) showUser(result);
        } completion:^(id result,NSError *error) { if (!error) showUser(result); }];
    }
    if ([self isProfile] && !append) {
        void (^showPhotos)(id)=^(id result) {
            if (generation!=self.generation) return;
            NSArray *raw=[result isKindOfClass:[NSArray class]] ? OVKArray(result) : OVKArray(OVKDictionary(result)[@"items"]);
            NSMutableArray *attachments=[NSMutableArray array]; for (id photo in raw) if ([photo isKindOfClass:[NSDictionary class]]) [attachments addObject:@{@"type":@"photo",@"photo":photo}];
            self.profilePhotos=OVKPostAttachments(@{@"attachments":attachments}); [self updateProfileHeader];
        };
        [[OVKAPI shared] call:@"photos.getAll" parameters:@{@"owner_id":self.identifier,@"count":@4,@"offset":@0,@"photo_sizes":@1} cached:^(id result) {
            if (!self.profilePhotos.count) showPhotos(result);
        } completion:^(id result,NSError *error) { if (!error) showPhotos(result); }];
    }
    BOOL chat=[self isChat];
    NSUInteger pageSize=OVKPageSize();
    NSUInteger offset=append ? (chat ? self.historyOffset : self.items.count) : 0;
    NSMutableDictionary *params = [@{@"count":@(pageSize),@"offset":@(offset),@"extended":@1,@"fields":@"photo_100,photo_50,online"} mutableCopy];
    NSString *method = self.instanceNews ? @"newsfeed.getGlobal" : @"newsfeed.get";
    if ([self isPeopleList]) {
        method = [self.mode isEqualToString:@"followers"] ? @"users.getFollowers" : @"friends.get";
        params[@"user_id"] = self.identifier ?: [OVKAPI shared].userID ?: @0;
    }
    else if ([self.mode isEqualToString:@"dialogs"]) method = @"messages.getConversations";
    else if ([self.mode isEqualToString:@"archive"]) { method=@"wall.get"; params[@"owner_id"]=[OVKAPI shared].userID; params[@"filter"]=@"archived"; }
    else if ([self.mode isEqualToString:@"groupWall"]) { method=@"wall.get"; params[@"owner_id"]=self.identifier; params[@"filter"]=@"all"; }
    else if ([self isProfile]) { method = @"wall.get"; params[@"owner_id"] = self.identifier; params[@"filter"]=self.ownerOnly ? @"owner" : @"all"; }
    else if (chat) { method = @"messages.getHistory"; params[@"peer_id"] = self.identifier; }
    else if (append && self.nextCursor.length) { params[@"start_from"] = self.nextCursor; [params removeObjectForKey:@"offset"]; }
    __block BOOL cachedPage=NO;
    [[OVKAPI shared] call:method parameters:params cached:^(id result) {
        if (generation!=self.generation || (!chat && (append || self.items.count))) return;
        if (chat && !append && self.items.count) return;
        cachedPage=[self applyListResponse:result append:append offset:offset pageSize:pageSize];
    } completion:^(id result, NSError *error) {
        if (generation != self.generation) return;
        self.loading=NO;
        [self.refreshControl endRefreshing]; [self.historySpinner stopAnimating];
        if (chat) [self updateChatActions];
        NSUInteger countBefore=self.items.count;
        if (error || ![self applyListResponse:result append:append offset:offset pageSize:pageSize]) {
            self.historyAutomaticFailed=chat && append && !cachedPage;
            self.notice.text=self.items.count && !chat ? @"" : (error.localizedDescription ?: OVKL(@"Формат ответа этого сервера не поддерживается"));
            [self.footer setTitle:OVKL(@"Повторить загрузку") forState:UIControlStateNormal];
        } else self.historyAutomaticFailed=chat && append && !cachedPage && countBefore==self.items.count;
        [self finishPendingWallRefresh];
    }];
}

- (void)updateProfileHeader {
    if (!self.user.count) return;
    CGFloat width=self.tableView.bounds.size.width, photoHeight=self.profilePhotos.count ? 66 : 0, filterY=244+photoHeight;
    UIView *header=[[UIView alloc] initWithFrame:CGRectMake(0,0,width,filterY+36)];
    UIView *background=[[UIView alloc] initWithFrame:header.bounds]; background.backgroundColor=OVKProfilePanelColor(); background.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; [header addSubview:background];
    OVKRemoteImageView *avatar=[[OVKRemoteImageView alloc] initWithFrame:CGRectMake(8,10,80,80)]; avatar.contentMode=UIViewContentModeScaleAspectFill; avatar.clipsToBounds=YES; avatar.layer.borderWidth=1; avatar.layer.borderColor=[UIColor colorWithWhite:0 alpha:.45].CGColor; [avatar load:OVKString(self.user[@"photo_200"] ?: self.user[@"photo_100"])]; avatar.userInteractionEnabled=YES; [avatar addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openProfilePhoto)]]; [header addSubview:avatar];
    UILabel *name=[[UILabel alloc] initWithFrame:CGRectMake(100,10,width-110,38)]; name.text=[OVKName(self.user) stringByAppendingString:[OVKString(self.user[@"verified"]) boolValue] ? @" ✓" : @""]; name.numberOfLines=2; name.font=[UIFont boldSystemFontOfSize:16]; name.textColor=[UIColor whiteColor]; name.backgroundColor=[UIColor clearColor]; name.shadowColor=[UIColor blackColor]; name.shadowOffset=CGSizeMake(0,-1); [header addSubview:name];
    UILabel *status=[[UILabel alloc] initWithFrame:CGRectMake(100,50,width-110,40)]; status.numberOfLines=3; status.font=[UIFont systemFontOfSize:11]; status.textColor=[UIColor colorWithRed:.7 green:.75 blue:.8 alpha:1]; status.backgroundColor=[UIColor clearColor]; NSString *city=OVKString(OVKDictionary(self.user[@"city"])[@"title"]); status.text=[NSString stringWithFormat:@"%@%@%@\n%@",[OVKString(self.user[@"online"]) boolValue] ? OVKL(@"В сети") : OVKL(@"Не в сети"),city.length ? @" · " : @"",city,OVKString(self.user[@"status"])]; [header addSubview:status];
    id rawRating=self.user[@"rating"]; NSString *rating=OVKString(rawRating); double numericRating=0; NSScanner *ratingScanner=[NSScanner scannerWithString:rating];
    if (rating.length && [ratingScanner scanDouble:&numericRating] && [ratingScanner isAtEnd] && isfinite(numericRating)) { UILabel *badge=[[UILabel alloc] initWithFrame:CGRectMake(8,80,80,18)]; badge.backgroundColor=[UIColor colorWithWhite:0 alpha:.65]; badge.textColor=[UIColor colorWithRed:.95 green:.82 blue:.43 alpha:1]; badge.textAlignment=NSTextAlignmentCenter; badge.font=[UIFont boldSystemFontOfSize:11]; badge.text=[NSString stringWithFormat:@"★ %@",rating]; badge.accessibilityLabel=[NSString stringWithFormat:OVKL(@"Рейтинг: %@"),rating]; [header addSubview:badge]; }
    BOOL own=[self.identifier isEqual:[OVKAPI shared].userID]; CGFloat buttonWidth=own ? width-16 : (width-20)/2;
    for (NSUInteger i=0;i<(own ? 1 : 2);i++) {
        UIButton *button=[UIButton buttonWithType:UIButtonTypeCustom]; button.frame=CGRectMake(8+i*(buttonWidth+4),100,buttonWidth,33);
        OVKStyleAssetButton(button,i==0 ? @"ProfileBlueButton" : @"FooterButton");
        [button setTitle:i==0 ? (own ? OVKL(@"Новая запись") : OVKL(@"Сообщение")) : [self friendshipTitle] forState:UIControlStateNormal]; [button setTitleColor:i==0 ? [UIColor whiteColor] : (OVKDarkTheme() ? OVKThemeText() : [UIColor colorWithRed:.25 green:.31 blue:.38 alpha:1]) forState:UIControlStateNormal]; button.titleLabel.font=[UIFont boldSystemFontOfSize:12];
        [button addTarget:self action:i==0 ? (own ? @selector(compose) : @selector(openChat)) : @selector(friendshipTapped) forControlEvents:UIControlEventTouchUpInside];
        if (i==1) { button.enabled=!self.friendshipLoading && !self.friendshipChanging && self.friendshipStatus!=1 && self.friendshipStatus!=3; button.alpha=button.enabled ? 1 : .75; button.accessibilityLabel=[self friendshipTitle]; } [header addSubview:button];
    }
    NSDictionary *counters=OVKDictionary(self.user[@"counters"]); NSArray *keys=@[@"friends",@"mutual_friends",@"followers",@"photos",@"videos",@"audios"];
    NSArray *titles=@[OVKL(@"ДРУЗЬЯ"),OVKL(@"ОБЩИЕ"),OVKL(@"ПОДПИСЧИКИ"),OVKL(@"ФОТОГРАФИИ"),OVKL(@"ВИДЕО"),OVKL(@"АУДИО")];
    for (NSUInteger i=0;i<6;i++) {
        CGFloat tileWidth=(width-26)/3; CGRect frame=CGRectMake(8+(i%3)*(tileWidth+5),138+(i/3)*51,tileWidth,46);
        UIImageView *tile=[[UIImageView alloc] initWithImage:OVKThemeStretch(@"ProfileCounter")]; tile.frame=frame; [header addSubview:tile];
        id value=counters[keys[i]]; if (i==1 && ![value respondsToSelector:@selector(integerValue)]) value=self.user[@"common_count"];
        UILabel *count=[[UILabel alloc] initWithFrame:CGRectMake(0,3,tileWidth,23)]; count.text=[value respondsToSelector:@selector(integerValue)] ? [NSString stringWithFormat:@"%ld",(long)[value integerValue]] : @"—"; count.font=[UIFont boldSystemFontOfSize:18]; count.textAlignment=NSTextAlignmentCenter; count.textColor=[UIColor colorWithWhite:.87 alpha:1]; count.backgroundColor=[UIColor clearColor]; [tile addSubview:count];
        UILabel *label=[[UILabel alloc] initWithFrame:CGRectMake(0,27,tileWidth,12)]; label.text=titles[i]; label.font=[UIFont boldSystemFontOfSize:8]; label.textColor=[UIColor colorWithWhite:.58 alpha:1]; label.textAlignment=NSTextAlignmentCenter; label.backgroundColor=[UIColor clearColor]; [tile addSubview:label];
        UIButton *tap=[UIButton buttonWithType:UIButtonTypeCustom]; tap.frame=frame; tap.tag=i-1; tap.accessibilityLabel=titles[i];
        SEL action=i==0 ? @selector(openProfileFriends) : (i==1 ? @selector(openMutualFriends) : (i==2 ? @selector(openFollowers) : @selector(openProfileLibrary:)));
        [tap addTarget:self action:action forControlEvents:UIControlEventTouchUpInside]; [header addSubview:tap];
    }
    if (photoHeight) for (NSUInteger i=0;i<MIN((NSUInteger)4,self.profilePhotos.count);i++) {
        CGFloat size=(width-28)/4; CGRect frame=CGRectMake(8+i*(size+4),246,size,58);
        OVKRemoteImageView *photo=[[OVKRemoteImageView alloc] initWithFrame:frame]; photo.contentMode=UIViewContentModeScaleAspectFill; photo.clipsToBounds=YES; [photo load:self.profilePhotos[i][@"preview"]]; [header addSubview:photo];
        UIButton *tap=[UIButton buttonWithType:UIButtonTypeCustom]; tap.frame=frame; tap.tag=i; tap.accessibilityLabel=OVKL(@"Фотография"); [tap addTarget:self action:@selector(profilePhotoTapped:) forControlEvents:UIControlEventTouchUpInside]; [header addSubview:tap];
    }
    UIImageView *bar=[[UIImageView alloc] initWithImage:OVKThemeChrome(@"SectionBar")]; bar.frame=CGRectMake(0,filterY,width,36); bar.userInteractionEnabled=YES; [header addSubview:bar];
    UISegmentedControl *filter=[[UISegmentedControl alloc] initWithItems:@[OVKL(@"Все записи"),OVKL(@"Записи автора")]]; filter.segmentedControlStyle=UISegmentedControlStyleBar; filter.frame=CGRectMake(8,5,width-52,26); filter.selectedSegmentIndex=self.ownerOnly ? 1 : 0; [filter addTarget:self action:@selector(wallFilter:) forControlEvents:UIControlEventValueChanged]; [bar addSubview:filter];
    if (own) { UIButton *write=[UIButton buttonWithType:UIButtonTypeCustom]; write.frame=CGRectMake(width-38,3,32,30); [write setImage:[UIImage imageNamed:@"ComposeGlyph"] forState:UIControlStateNormal]; write.accessibilityLabel=OVKL(@"Новая запись"); [write addTarget:self action:@selector(compose) forControlEvents:UIControlEventTouchUpInside]; [bar addSubview:write]; }
    OVKThemeButtons(header);
    self.tableView.tableHeaderView=header; self.tableView.tableFooterView=self.profileInfo ? nil : self.footerContainer;
}
// Status values follow friends.areFriends: 0 none, 1 outgoing, 2 incoming, 3 friends.
- (NSString *)friendshipTitle {
    if (self.friendshipChanging) return OVKL(@"Сохранение…");
    if (self.friendshipLoading) return OVKL(@"Проверка…");
    switch (self.friendshipStatus) {
        case 0: return OVKL(@"Подписаться");
        case 1: return OVKL(@"Вы подписаны");
        case 2: return OVKL(@"Принять заявку");
        case 3: return OVKL(@"Друг ✓");
        default: return OVKL(@"Проверить дружбу");
    }
}
- (void)loadFriendship {
    if (![self isProfile] || [self.identifier isEqual:[OVKAPI shared].userID] || self.friendshipChanging) return;
    if ([OVKAPI shared].demo) { self.friendshipStatus=3; self.friendshipLoading=NO; [self updateProfileHeader]; return; }
    NSUInteger generation=++self.friendshipGeneration; self.friendshipLoading=YES; self.friendshipError=nil; [self updateProfileHeader];
    [[OVKAPI shared] call:@"friends.areFriends" parameters:@{@"user_ids":self.identifier} completion:^void(id result,NSError *error) {
        if (generation!=self.friendshipGeneration) return;
        self.friendshipLoading=NO; self.friendshipStatus=-1;
        for (id value in OVKArray(result)) { NSDictionary *entry=OVKDictionary(value); id status=entry[@"friend_status"]; if ([OVKString(entry[@"user_id"]) isEqualToString:OVKString(self.identifier)] && [status respondsToSelector:@selector(integerValue)] && [status integerValue]>=0 && [status integerValue]<=3) { self.friendshipStatus=[status integerValue]; break; } }
        if (self.friendshipStatus<0) self.friendshipError=error.localizedDescription ?: OVKL(@"Сервер не вернул статус дружбы.");
        [self updateProfileHeader];
    }];
}
- (void)friendshipTapped {
    if (self.friendshipLoading || self.friendshipChanging || [self.identifier isEqual:[OVKAPI shared].userID]) return;
    if (self.friendshipStatus<0) { if (self.friendshipError.length) OVKAlert(OVKL(@"Дружба"),self.friendshipError); [self loadFriendship]; return; }
    if (self.friendshipStatus==1 || self.friendshipStatus==3) return;
    if ([OVKAPI shared].demo) { OVKAlert(OVKL(@"Демонстрация"),OVKL(@"Для изменения подписки войдите в аккаунт.")); return; }
    self.friendshipChanging=YES; ++self.friendshipGeneration; [self updateProfileHeader];
    [[OVKAPI shared] call:@"friends.add" parameters:@{@"user_id":self.identifier} completion:^void(id result,NSError *error) {
        self.friendshipChanging=NO;
        // Re-read the server status even after an uncertain network result; never retry the write automatically.
        if (error) OVKAlert(OVKL(@"Не удалось изменить подписку"),error.localizedDescription);
        [self loadFriendship];
    }];
}
- (void)profilePhotoTapped:(UIButton *)button { OVKPresentPhoto(self,[[OVKPhotoController alloc] initWithPhotos:self.profilePhotos index:button.tag]); }
- (void)openProfileFriends { [self.navigationController pushViewController:[[OVKListController alloc] initWithMode:@"friends" identifier:self.identifier title:OVKL(@"Друзья")] animated:YES]; }
- (void)wallFilter:(UISegmentedControl *)filter { if (self.loading) { filter.selectedSegmentIndex=self.ownerOnly ? 1 : 0; return; } self.ownerOnly=filter.selectedSegmentIndex==1; [self refresh]; }
- (void)showProfileInfo { self.profileInfo=YES; self.profileTabs.selectedSegmentIndex=1; self.tableView.tableFooterView=nil; [self.tableView reloadData]; }
- (void)profileTabChanged:(UISegmentedControl *)tabs { self.profileInfo=tabs.selectedSegmentIndex==1; self.tableView.tableFooterView=self.profileInfo ? nil : self.footerContainer; [self.tableView reloadData]; }
- (NSArray *)profileDetails { NSString *city=OVKString(OVKDictionary(self.user[@"city"])[@"title"]); return @[@[OVKL(@"Статус"),OVKString(self.user[@"status"])],@[OVKL(@"Город"),city],@[OVKL(@"О себе"),OVKString(self.user[@"about"])]]; }
- (void)showProfileLibrary:(NSString *)kind title:(NSString *)title {
    OVKLibraryController *library=[[OVKLibraryController alloc] initWithKind:kind identifier:self.identifier title:title];
    [library enableCollectionSearch];
    [self.navigationController pushViewController:library animated:YES];
}
- (void)openProfilePhotos { [self showProfileLibrary:@"photo" title:OVKL(@"Фотографии")]; }
- (void)openMutualFriends { [self.navigationController pushViewController:[[OVKListController alloc] initWithMode:@"mutual" identifier:self.identifier title:OVKL(@"Общие друзья")] animated:YES]; }
- (void)openFollowers { [self.navigationController pushViewController:[[OVKListController alloc] initWithMode:@"followers" identifier:self.identifier title:OVKL(@"Подписчики")] animated:YES]; }
- (void)openProfileLibrary:(UIButton *)sender {
    NSArray *kinds=@[@"photo",@"video",@"audio"]; NSArray *titles=@[OVKL(@"Фотографии"),OVKL(@"Видеозаписи"),OVKL(@"Аудиозаписи")];
    NSUInteger index=sender.tag-2; if (index>=kinds.count) return;
    if ((index==1 && !OVKExperimentalVideo()) || (index==2 && !OVKExperimentalMusic())) { OVKAlert(OVKL(@"Экспериментальное"),OVKL(@"Включите этот раздел в настройках приложения.")); return; }
    [self showProfileLibrary:kinds[index] title:titles[index]];
}
- (NSArray *)visibleItems {
    NSString *query=[self.search.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!query.length) return self.items;
    NSMutableArray *matches=[NSMutableArray array]; for (NSDictionary *item in self.items) if ([[self headingFor:item] rangeOfString:query options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch].location!=NSNotFound || [[self bodyFor:item] rangeOfString:query options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch].location!=NSNotFound) [matches addObject:item]; return matches;
}
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText { [self.tableView reloadData]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }
- (NSDictionary *)postAt:(NSUInteger)index {
    NSArray *items=[self visibleItems];
    return index<items.count ? OVKDictionary(items[index]) : @{};
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews]; CGFloat width=self.view.bounds.size.width,height=self.view.bounds.size.height; CGFloat contentWidth=UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad ? MIN(720,width) : width; CGFloat margin=(width-contentWidth)/2;
    // The optional quote sits above the 44-point composer, so the keyboard never covers either control row.
    CGFloat replyHeight=self.chatReply ? 42 : 0, bar=[self isChat] ? 44+replyHeight : 0;
    CGFloat tableHeight=MAX(0,height-bar-self.keyboardHeight);
    self.tableView.frame=CGRectMake(margin,0,contentWidth,tableHeight);
    self.composerBar.frame=CGRectMake(margin,tableHeight,contentWidth,bar);
    self.chatAttachButton.frame=CGRectMake(3,replyHeight,35,44);
    self.messageField.frame=CGRectMake(41,replyHeight+1,MAX(0,contentWidth-116),41);
    self.sendButton.frame=CGRectMake(contentWidth-67,replyHeight,59,44);
    self.chatReplyBar.frame=CGRectMake(0,0,contentWidth,replyHeight);
    self.chatReplyLabel.frame=CGRectMake(12,3,MAX(0,contentWidth-55),36);
    self.chatReplyCancel.frame=CGRectMake(contentWidth-42,0,42,42);
    self.footer.frame=CGRectMake((contentWidth-180)/2,8,180,33);
    self.view.backgroundColor=OVKThemeBackground(); if (fabs(self.layoutWidth-contentWidth)>.5) { self.layoutWidth=contentWidth; [self.rowHeights removeAllObjects]; if ([self isProfile]) [self updateProfileHeader]; [self.tableView reloadData]; }
}
- (void)chatKeyboard:(NSNotification *)note {
    if (!self.view.window) { self.keyboardHeight=0; return; }
    CGRect keyboard=[self.view convertRect:[note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil]; self.keyboardHeight=[note.name isEqualToString:UIKeyboardWillHideNotification] ? 0 : CGRectGetHeight(CGRectIntersection(self.view.bounds,keyboard));
    if (!isfinite(self.keyboardHeight)) self.keyboardHeight=0;
    [UIView animateWithDuration:[note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue] animations:^{ [self.view setNeedsLayout]; [self.view layoutIfNeeded]; } completion:^(BOOL finished) { [self scrollToLatest]; }];
}
- (void)scrollToLatest { if ([self isChat] && self.items.count) [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:self.items.count-1 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:NO]; }
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [self.view endEditing:YES]; }
- (void)openChatProfile { if (self.identifier.longLongValue>0 && self.identifier.longLongValue<2000000000LL) [self.navigationController pushViewController:[[OVKListController alloc] initWithMode:@"profile" identifier:self.identifier title:self.title] animated:YES]; }
- (void)chatDraftChanged { if (self.draftChanged) self.draftChanged(self.messageField.text ?: @""); }
- (BOOL)textFieldShouldReturn:(UITextField *)field { [self sendMessage]; return NO; }
- (void)configureChatActions {
    self.tableView.allowsMultipleSelectionDuringEditing=YES;
    self.chatEditItem=[[UIBarButtonItem alloc] initWithTitle:OVKL(@"Редактировать") style:UIBarButtonItemStylePlain target:self action:@selector(toggleChatEditing)];
    self.chatDeleteItem=[[UIBarButtonItem alloc] initWithTitle:OVKL(@"Удалить") style:UIBarButtonItemStyleDone target:self action:@selector(confirmDeleteSelectedMessages)];
    self.chatLoadingSpinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.chatLoadingSpinner.accessibilityLabel=OVKL(@"Загрузка…");
    self.chatLoadingItem=[[UIBarButtonItem alloc] initWithCustomView:self.chatLoadingSpinner];
    UILongPressGestureRecognizer *hold=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(chatMessageHeld:)];
    hold.minimumPressDuration=.55; hold.delegate=self; [self.tableView addGestureRecognizer:hold];
    UISwipeGestureRecognizer *reply=[[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(replyToChatMessage:)];
    reply.direction=UISwipeGestureRecognizerDirectionRight; reply.delegate=self; [self.tableView addGestureRecognizer:reply];
    [self updateChatActions];
}
- (void)updateChatActions {
    BOOL editing=self.tableView.editing;
    self.chatEditItem.title=editing ? OVKL(@"Готово") : OVKL(@"Редактировать");
    self.chatEditItem.enabled=!self.deletingMessages && (editing || (!self.loading && self.items.count && ![OVKAPI shared].demo));
    self.chatDeleteItem.enabled=!self.deletingMessages && self.tableView.indexPathsForSelectedRows.count>0;
    self.chatDeleteItem.title=OVKL(@"Удалить");
    self.chatAttachButton.enabled=!editing && !self.sending;
    self.messageField.enabled=!editing && !self.sending;
    self.sendButton.enabled=!editing && !self.sending;
    // API reads and bulk writes have no known total, so the navigation item shows indeterminate activity.
    if (self.loading || self.deletingMessages) {
        [self.chatLoadingSpinner startAnimating];
        self.navigationItem.rightBarButtonItems=@[self.chatLoadingItem,self.chatEditItem];
    } else {
        [self.chatLoadingSpinner stopAnimating];
        self.navigationItem.rightBarButtonItems=editing && self.tableView.indexPathsForSelectedRows.count ? @[self.chatDeleteItem,self.chatEditItem] : @[self.chatEditItem];
    }
    self.navigationItem.titleView=editing ? nil : self.chatTitleButton;
}
- (void)toggleChatEditing {
    if (self.loading || self.deletingMessages || self.sending) return;
    [self.view endEditing:YES];
    BOOL editing=!self.tableView.editing;
    [self.tableView setEditing:editing animated:YES];
    [self updateChatActions];
    if (!editing) [self finishPendingWallRefresh];
}
- (NSArray *)selectedOwnMessageIDs {
    // Selection is translated to global message IDs before the network call, never sent as table indexes.
    NSMutableArray *keys=[NSMutableArray array];
    for (NSIndexPath *path in self.tableView.indexPathsForSelectedRows) {
        NSDictionary *message=[self postAt:(NSUInteger)path.row];
        if (OVKIsOwnChatMessage(message,[OVKAPI shared].userID)) [keys addObject:OVKChatMessageKey(message)];
    }
    return keys;
}
- (void)confirmDeleteSelectedMessages {
    if (![self selectedOwnMessageIDs].count || self.deletingMessages) return;
    UIAlertView *alert=[[UIAlertView alloc] initWithTitle:OVKL(@"Удалить выбранные сообщения?") message:nil delegate:self cancelButtonTitle:OVKL(@"Отмена")
                                     otherButtonTitles:OVKL(@"Удалить у меня"),OVKL(@"Удалить у всех"),nil];
    alert.tag=1004; [alert show];
}
- (void)deleteSelectedMessagesForEveryone:(BOOL)everyone {
    NSArray *keys=[self selectedOwnMessageIDs];
    if (!keys.count || self.deletingMessages) return;
    self.deletingMessages=YES; [self updateChatActions];
    [self deleteMessageIDs:keys offset:0 forEveryone:everyone confirmed:[NSMutableArray array] completion:^(id result,NSError *error) {
        self.deletingMessages=NO;
        NSArray *confirmed=OVKArray(result);
        if (confirmed.count) {
            // Drop only acknowledged IDs. The batch can partially succeed on the server.
            NSSet *removed=[NSSet setWithArray:confirmed];
            NSIndexSet *rows=[self.items indexesOfObjectsPassingTest:^BOOL(NSDictionary *message,NSUInteger index,BOOL *stop) {
                return [removed containsObject:OVKChatMessageKey(message)];
            }];
            [self.items removeObjectsAtIndexes:rows];
            self.historyOffset=self.historyOffset>rows.count ? self.historyOffset-rows.count : 0;
            [self.rowHeights removeAllObjects];
            [[OVKAPI shared] invalidateCachedMethod:@"messages.getHistory" peer:self.identifier];
            [[OVKAPI shared] invalidateCachedMethod:@"messages.getConversations" peer:nil];
            [self.tableView reloadData];
            if (confirmed.count==keys.count) [self.tableView setEditing:NO animated:YES];
            else {
                NSSet *requested=[NSSet setWithArray:keys];
                [self.items enumerateObjectsUsingBlock:^(NSDictionary *message,NSUInteger index,BOOL *stop) {
                    NSString *key=OVKChatMessageKey(message);
                    if ([requested containsObject:key] && ![removed containsObject:key]) {
                        [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:0] animated:NO scrollPosition:UITableViewScrollPositionNone];
                    }
                }];
            }
        }
        [self updateChatActions];
        if (confirmed.count<keys.count) OVKAlert(OVKL(@"Не удалось удалить все сообщения"),error.localizedDescription ?: OVKL(@"Некоторые сообщения остались в чате."));
        if (!self.tableView.editing && confirmed.count) { self.needsWallRefresh=NO; [self refresh]; }
    }];
}
- (void)deleteMessageIDs:(NSArray *)keys offset:(NSUInteger)offset forEveryone:(BOOL)everyone confirmed:(NSMutableArray *)confirmed completion:(OVKCompletion)completion {
    const NSUInteger batchLimit=100;
    NSUInteger count=MIN(batchLimit,keys.count-offset);
    NSArray *batch=[keys subarrayWithRange:NSMakeRange(offset,count)];
    NSDictionary *params=@{@"peer_id":self.identifier,@"message_ids":[batch componentsJoinedByString:@","],@"delete_for_all":@(everyone)};
    [[OVKAPI shared] call:@"messages.delete" parameters:params completion:^(id result,NSError *error) {
        if (!error) [confirmed addObjectsFromArray:OVKConfirmedMessageDeletions(result,batch)];
        // A transport failure stops later batches but keeps the earlier acknowledgments.
        if (error || offset+count>=keys.count) { completion(confirmed,error); return; }
        [self deleteMessageIDs:keys offset:offset+count forEveryone:everyone confirmed:confirmed completion:completion];
    }];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    if (![self isChat] || self.tableView.editing || self.sending || self.presentedViewController || [OVKAPI shared].demo) return NO;
    NSIndexPath *path=[self.tableView indexPathForRowAtPoint:[touch locationInView:self.tableView]];
    if (!path) return NO;
    NSDictionary *message=[self postAt:(NSUInteger)path.row];
    BOOL own=OVKIsOwnChatMessage(message,[OVKAPI shared].userID);
    if ([gesture isKindOfClass:[UISwipeGestureRecognizer class]]) {
        // Capture the touched message before an incoming page can shift the row under the gesture.
        self.swipedChatMessage=!own && [OVKString(message[@"id"]) longLongValue]>0 ? message : nil;
        return self.swipedChatMessage!=nil;
    }
    return own && !self.loading;
}
- (void)chatMessageHeld:(UILongPressGestureRecognizer *)press {
    if (press.state!=UIGestureRecognizerStateBegan) return;
    NSIndexPath *path=[self.tableView indexPathForRowAtPoint:[press locationInView:self.tableView]];
    NSDictionary *message=path ? [self postAt:(NSUInteger)path.row] : nil;
    if (!OVKIsOwnChatMessage(message,[OVKAPI shared].userID) || (message[@"can_edit"] && ![OVKString(message[@"can_edit"]) boolValue])) return;
    self.messageToEdit=message;
    [self.view endEditing:YES];
    UIActionSheet *sheet=[[UIActionSheet alloc] initWithTitle:OVKL(@"Сообщение") delegate:self cancelButtonTitle:OVKL(@"Отмена") destructiveButtonTitle:nil otherButtonTitles:OVKL(@"Редактировать"),nil];
    sheet.tag=1003;
    if (UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad) {
        CGPoint point=[press locationInView:self.tableView];
        [sheet showFromRect:CGRectMake(point.x,point.y,1,1) inView:self.tableView animated:YES];
    } else [sheet showInView:self.view];
}
- (void)replyToChatMessage:(UISwipeGestureRecognizer *)swipe {
    NSIndexPath *path=[self.tableView indexPathForRowAtPoint:[swipe locationInView:self.tableView]];
    NSDictionary *message=self.swipedChatMessage; self.swipedChatMessage=nil;
    if ([OVKString(message[@"id"]) longLongValue]<=0 || OVKIsOwnChatMessage(message,[OVKAPI shared].userID)) return;
    self.chatReply=message;
    // A different reply target is a different message, even if the draft text is unchanged.
    self.pendingRandomID=nil;
    NSString *text=OVKString(message[@"text"]);
    self.chatReplyLabel.text=[NSString stringWithFormat:@"%@\n%@",[self headingFor:message],text.length ? text : OVKL(@"Вложение")];
    self.chatReplyBar.hidden=NO; [self.view setNeedsLayout];
    UITableViewCell *cell=path && [OVKChatMessageKey([self postAt:(NSUInteger)path.row]) isEqualToString:OVKChatMessageKey(message)] ? [self.tableView cellForRowAtIndexPath:path] : nil;
    cell.contentView.transform=CGAffineTransformMakeTranslation(18,0);
    [UIView animateWithDuration:.18 animations:^{ cell.contentView.transform=CGAffineTransformIdentity; }];
    [self.messageField becomeFirstResponder];
}
- (void)clearChatReply {
    self.chatReply=nil; self.pendingRandomID=nil;
    self.chatReplyBar.hidden=YES; [self.view setNeedsLayout];
}
- (void)showEditor:(OVKComposeController *)editor {
    [self.view endEditing:YES];
    UINavigationController *nav=[[OVKNavigationController alloc] initWithRootViewController:editor];
    OVKStyleNavigation(nav); [self presentViewController:nav animated:YES completion:nil];
}
- (void)openChatAttachmentComposer {
    if (self.tableView.editing || self.sending) return;
    OVKComposeController *editor=[[OVKComposeController alloc] init];
    editor.message=YES; editor.identifier=self.identifier;
    editor.initialText=self.messageDraft;
    if (self.chatReply) {
        editor.replyID=@([OVKString(self.chatReply[@"id"]) longLongValue]);
        editor.replyName=[self headingFor:self.chatReply];
    }
    editor.showAttachmentPickerOnOpen=YES;
    __weak OVKListController *weakSelf=self;
    editor.sent=^{ [weakSelf clearSentChatDraft]; [weakSelf refresh]; };
    [self showEditor:editor];
}
- (void)openMessageEditor:(NSDictionary *)message {
    OVKComposeController *editor=[[OVKComposeController alloc] init];
    editor.message=YES; editor.identifier=self.identifier; editor.editingMessage=message;
    __weak OVKListController *weakSelf=self;
    editor.sent=^{ [weakSelf refresh]; };
    editor.savedMessage=^(NSDictionary *edited) {
        OVKListController *page=weakSelf;
        NSString *key=OVKChatMessageKey(edited);
        NSUInteger index=[page.items indexOfObjectPassingTest:^BOOL(NSDictionary *item,NSUInteger idx,BOOL *stop) { return [OVKChatMessageKey(item) isEqualToString:key]; }];
        if (page && index!=NSNotFound && index<page.items.count) {
            page.items[index]=edited;
            [page.rowHeights removeObjectForKey:@(index)];
            [page.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:index inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
        }
    };
    [self showEditor:editor];
}
- (void)clearSentChatDraft {
    self.messageDraft=@""; [self chatDraftChanged]; [self clearChatReply];
    self.pendingRandomID=nil; self.pendingMessage=nil;
}
- (void)sendMessage {
    if (self.sending) return;
    if ([OVKAPI shared].demo) { OVKAlert(OVKL(@"Демонстрация"),OVKL(@"Отправка сообщений доступна после входа.")); return; }
    if (![self.pendingMessage isEqualToString:self.messageField.text]) { self.pendingRandomID=nil; self.pendingMessage=[self.messageField.text copy]; }
    if (!self.pendingRandomID) self.pendingRandomID=@(arc4random_uniform(2147483646)+1);
    NSError *error=nil; NSMutableDictionary *params=[OVKWallWriteParameters(@"message",self.identifier,nil,nil,self.messageField.text,self.pendingRandomID,&error) mutableCopy];
    if (!params) { OVKAlert(OVKL(@"Сообщение"),error.localizedDescription); return; }
    if (self.chatReply) params[@"reply_to"]=@([OVKString(self.chatReply[@"id"]) longLongValue]);
    self.sending=YES; [self updateChatActions];
    [[OVKAPI shared] call:@"messages.send" parameters:params completion:^void(id result,NSError *error) {
        self.sending=NO; [self updateChatActions];
        if (error) { OVKAlert(OVKL(@"Не удалось отправить"),error.localizedDescription); return; }
        [self clearSentChatDraft]; [self refresh];
    }];
}
- (NSDictionary *)personFor:(NSDictionary *)item {
    id identifier = item[@"from_id"] ?: item[@"source_id"] ?: item[@"owner_id"];
    return OVKDictionary(self.people[OVKString(identifier)]);
}
- (NSString *)headingFor:(NSDictionary *)item {
    if ([self isPeopleList]) return OVKName(item);
    if ([self.mode isEqualToString:@"dialogs"]) {
        NSDictionary *conversation = OVKDictionary(item[@"conversation"]); NSDictionary *peer = OVKDictionary(conversation[@"peer"]);
        NSString *title = OVKString(OVKDictionary(conversation[@"chat_settings"])[@"title"]);
        NSString *name = OVKName(OVKDictionary(self.people[OVKString(peer[@"id"])]));
        return title.length ? title : (name.length ? name : [NSString stringWithFormat:OVKL(@"Диалог %@"),OVKString(peer[@"id"])]);
    }
    NSString *name = OVKName([self personFor:item]);
    return name.length ? name : [NSString stringWithFormat:@"%@ %@",[self isChat] ? OVKL(@"Пользователь") : OVKL(@"Автор"),OVKString(item[@"from_id"] ?: item[@"source_id"])];
}
- (NSString *)bodyFor:(NSDictionary *)item {
    if ([self isPeopleList]) return [item[@"online"] boolValue] ? OVKL(@"В сети") : OVKL(@"Не в сети");
    if ([self.mode isEqualToString:@"dialogs"]) {
        NSDictionary *message = OVKDictionary(item[@"last_message"]); NSString *text = OVKString(message[@"text"]);
        return [NSString stringWithFormat:@"%@%@",[message[@"out"] boolValue] ? OVKL(@"Вы: ") : @"",text.length ? text : OVKL(@"[Вложение]")];
    }
    return OVKPostBody(item,[self isFeed] || [self isChat]);
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return ([self isProfile] && self.profileInfo) ? [self profileDetails].count : [self visibleItems].count; }
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)path {
    return [self isChat] && OVKIsOwnChatMessage([self postAt:(NSUInteger)path.row],[OVKAPI shared].userID);
}
- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)path {
    if (tableView.editing && [self isChat] && (self.deletingMessages || ![self tableView:tableView canEditRowAtIndexPath:path])) return nil;
    return path;
}
- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)path {
    if ([self isChat] && tableView.editing) [self updateChatActions];
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isProfile] && self.profileInfo) { NSArray *detail=[self profileDetails][indexPath.row]; CGSize size=[OVKString(detail[1]) sizeWithFont:[UIFont systemFontOfSize:14] constrainedToSize:CGSizeMake(tableView.bounds.size.width-110,10000) lineBreakMode:NSLineBreakByWordWrapping]; return MAX(50,ceil(size.height)+22); }
    if ([self.mode isEqualToString:@"dialogs"]) return 74;
    if ([self isPeopleList]) return 60;
    NSDictionary *post=[self postAt:indexPath.row]; NSNumber *row=@(indexPath.row); NSDictionary *cached=self.rowHeights[row];
    if (cached[@"post"]==post && [cached[@"width"] doubleValue]==tableView.bounds.size.width) return [cached[@"height"] doubleValue];
    NSString *text = [self bodyFor:post];
    BOOL groupIncoming=[self isChat] && self.identifier.longLongValue>=2000000000LL && ![OVKString(post[@"out"]) boolValue] && ![OVKString(post[@"from_id"]) isEqualToString:OVKString([OVKAPI shared].userID)];
    CGFloat textWidth=tableView.bounds.size.width-([self isChat] ? (groupIncoming ? 136 : 96) : ([self isFeed] ? 16 : 78));
    CGSize size = [text sizeWithFont:[UIFont systemFontOfSize:[self isFeed] ? OVKFeedTextSize() : 14] constrainedToSize:CGSizeMake(MAX(100,textWidth),([self isPost] || [self isChat]) ? 20000 : 110) lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat photoWidth=tableView.bounds.size.width-([self isChat] ? (groupIncoming ? 136 : 96) : ([self isFeed] ? 0 : 94));
    CGFloat imageHeight=[self isChat] ? OVKChatPhotoSize(post,photoWidth).height : OVKPostPhotoHeight(post,photoWidth,[self isFeed]);
    CGFloat quoteHeight=[self isChat] && OVKDictionary(post[@"reply_message"]).count ? 34 : 0;
    CGFloat audioHeight=([self isFeed] || [self isChat]) ? [OVKInlineAudioView heightForTracks:[OVKInlineAudioView tracksFromAttachments:OVKPostAttachments(post)]] : 0;
    CGFloat height=[self isChat] ? MAX(46,ceil(size.height)+26+imageHeight+quoteHeight+audioHeight) : MAX(86,ceil(size.height)+([self isFeed] ? 116 : 62))+imageHeight+audioHeight;
    self.rowHeights[row]=@{@"post":post,@"width":@(tableView.bounds.size.width),@"height":@(height)}; return height;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isProfile] && self.profileInfo) { UITableViewCell *info=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue2 reuseIdentifier:nil]; NSArray *detail=[self profileDetails][indexPath.row]; info.textLabel.text=detail[0]; info.detailTextLabel.text=OVKString(detail[1]).length ? detail[1] : OVKL(@"Не указано"); info.detailTextLabel.numberOfLines=0; info.detailTextLabel.font=[UIFont systemFontOfSize:14]; info.textLabel.font=[UIFont systemFontOfSize:12]; info.selectionStyle=UITableViewCellSelectionStyleNone; OVKThemeCell(info); return info; }
    NSString *reuse=[self isChat] ? @"chat" : ([self isPeopleList] ? @"person" : @"entry");
    OVKCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
    if (!cell) cell = [[OVKCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuse];
    cell.peopleStyle=[self isPeopleList];
    NSDictionary *item = [self postAt:indexPath.row];
    BOOL groupIncoming=[self isChat] && self.identifier.longLongValue>=2000000000LL && ![OVKString(item[@"out"]) boolValue] && ![OVKString(item[@"from_id"]) isEqualToString:OVKString([OVKAPI shared].userID)];
    NSString *photoURL = OVKPhotoURL(item);
    CGFloat photoWidth=tableView.bounds.size.width-([self isChat] ? (groupIncoming ? 136 : 96) : ([self isFeed] ? 0 : 94));
    CGSize chatSize=[self isChat] ? OVKChatPhotoSize(item,photoWidth) : CGSizeZero;
    cell.chatPhotoWidth=chatSize.width;
    cell.photoDisplayHeight=[self isChat] ? chatSize.height : OVKPostPhotoHeight(item,photoWidth,[self isFeed]);
    cell.photo.hidden=!photoURL.length;
    [cell.photo load:photoURL];
    NSArray *photos=OVKPostPhotos(item); cell.photoCount=photos.count;
    for (NSUInteger index=0;index<cell.extraPhotos.count;index++) { OVKRemoteImageView *image=cell.extraPhotos[index]; if ([self isFeed] && index+1<photos.count) [image load:photos[index+1][@"preview"] ?: photos[index+1][@"url"]]; else [image load:@""]; }
    cell.morePhotos.text=photos.count>3 ? [NSString stringWithFormat:@"+%lu",(unsigned long)(photos.count-3)] : @"";
    cell.activeDialog=self.dialogSelected && [self.selectedDialogPeer isEqualToString:OVKString(OVKDictionary(OVKDictionary(item[@"conversation"])[@"peer"])[@"id"])]; cell.dialogStyle=[self.mode isEqualToString:@"dialogs"]; cell.unread=[OVKDictionary(item[@"conversation"])[@"unread_count"] integerValue]>0;
    cell.conversationGroup=([self isChat] && self.identifier.longLongValue>=2000000000LL) || (cell.dialogStyle && [OVKString(OVKDictionary(OVKDictionary(item[@"conversation"])[@"peer"])[@"id"]) longLongValue]>=2000000000LL);
    cell.selectionStyle=[self isChat] ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleBlue;
    NSDictionary *last=OVKDictionary(item[@"last_message"]); NSDictionary *sender=OVKDictionary(self.people[OVKString(last[@"from_id"])]);
    [cell.previewAvatar load:cell.dialogStyle && [OVKString(last[@"out"]) boolValue] ? OVKString(sender[@"photo_50"] ?: sender[@"photo_100"]) : @""];
    cell.chatStyle = [self isChat]; cell.outgoing = [item[@"out"] boolValue] || [OVKString(item[@"from_id"]) isEqualToString:OVKString([OVKAPI shared].userID)]; cell.postStyle = [self isFeed]; cell.bodyLabel.font=[UIFont systemFontOfSize:[self isFeed] ? OVKFeedTextSize() : 14]; cell.heading.text = [self headingFor:item]; cell.bodyLabel.text = [self bodyFor:item];
    NSArray *inlineTracks=(cell.postStyle || cell.chatStyle) ? [OVKInlineAudioView tracksFromAttachments:OVKPostAttachments(item)] : @[];
    if (inlineTracks.count && !cell.inlineAudio) {
        cell.inlineAudio=[[OVKInlineAudioView alloc] initWithFrame:CGRectZero];
        [cell.contentView addSubview:cell.inlineAudio];
    }
    cell.inlineAudio.tracks=inlineTracks;
    NSDictionary *quote=OVKDictionary(item[@"reply_message"]);
    NSString *quoteText=OVKString(quote[@"text"]);
    cell.quotedMessage.text=cell.chatStyle && quote.count ? [NSString stringWithFormat:@"%@\n%@",[self headingFor:quote],quoteText.length ? quoteText : OVKL(@"Вложение")] : nil;
    NSDictionary *person = [self isPeopleList] ? item : [self personFor:item];
    if ([self.mode isEqualToString:@"dialogs"]) person = OVKDictionary(self.people[OVKString(OVKDictionary(OVKDictionary(item[@"conversation"])[@"peer"])[@"id"])]);
    if ([OVKString(person[@"verified"]) boolValue] && [self isFeed]) cell.heading.text=[cell.heading.text stringByAppendingString:@" ✓"];
    [cell.avatar load:cell.chatStyle && (cell.outgoing || !cell.conversationGroup) ? @"" : OVKString(person[@"photo_100"] ?: person[@"photo_50"])]; if (cell.dialogStyle && cell.conversationGroup && !cell.avatar.source.length) cell.avatar.image=[UIImage imageNamed:@"GroupPlaceholder"];
    NSString *avatarURL = OVKString(person[@"photo_max_orig"] ?: person[@"photo_200"] ?: person[@"photo_100"] ?: person[@"photo_50"]);
    __weak OVKListController *weakSelf = self; cell.photoTapped=^{
        NSMutableArray *photos=[NSMutableArray array]; for (NSDictionary *attachment in OVKPostAttachments(item)) if ([attachment[@"type"] isEqualToString:@"photo"]) [photos addObject:attachment];
        if (photos.count) OVKPresentPhoto(weakSelf,[[OVKPhotoController alloc] initWithPhotos:photos index:0]);
    };
    BOOL manageable=cell.postStyle && ![OVKAPI shared].demo && (OVKPostAllowsAction(item,@"edit",[OVKAPI shared].userID) || OVKPostAllowsAction(item,@"delete",[OVKAPI shared].userID));
    cell.postMenuTapped=nil;
    if (manageable) {
        __weak OVKCell *weakCell=cell;
        cell.postMenuTapped=^{
            OVKListController *page=weakSelf;
            if (page) [page showPostActions:item atPoint:[weakCell convertPoint:CGPointMake(weakCell.bounds.size.width-22,22) toView:page.tableView]];
        };
    }
    cell.photoIndexTapped=^(NSUInteger index) { if (index<photos.count) OVKPresentPhoto(weakSelf,[[OVKPhotoController alloc] initWithPhotos:photos index:index]); };
    cell.commentTapped=^{ [weakSelf openCommentsFor:item]; };
    cell.liked=[OVKDictionary(item[@"likes"])[@"user_likes"] boolValue]; cell.likeButton.enabled=OVKPostAllowsAction(item,@"like",[OVKAPI shared].userID) && ![self.postRequests containsObject:[self postRequestKey:item]]; cell.likeTapped=^{ [weakSelf togglePostLike:item]; };
    id rawProfileID=[self isPeopleList] ? item[@"id"] : (item[@"from_id"] ?: item[@"source_id"] ?: person[@"id"]);
    if ([self.mode isEqualToString:@"dialogs"]) rawProfileID=OVKDictionary(OVKDictionary(item[@"conversation"])[@"peer"])[@"id"];
    NSNumber *profileID=@([OVKString(rawProfileID) longLongValue]); BOOL userProfile=profileID.longLongValue>0 && (![self.mode isEqualToString:@"dialogs"] || profileID.longLongValue<2000000000LL);
    cell.avatarTapped = ^{ if (userProfile) [weakSelf.navigationController pushViewController:[[OVKListController alloc] initWithMode:@"profile" identifier:profileID title:OVKName(person)] animated:YES]; else if (profileID.longLongValue<0) [weakSelf.navigationController pushViewController:[[OVKGroupController alloc] initWithGroup:@(-profileID.longLongValue) title:OVKName(person)] animated:YES]; else if (avatarURL.length) OVKPresentPhoto(weakSelf,[[OVKPhotoController alloc] initWithURL:avatarURL title:OVKL(@"Аватар")]); };
    NSDictionary *message = [self.mode isEqualToString:@"dialogs"] ? OVKDictionary(item[@"last_message"]) : item;
    NSString *date = OVKDate(message[@"date"]); NSInteger unread = [OVKDictionary(item[@"conversation"])[@"unread_count"] integerValue];
    cell.unreadBadge.text=unread>99 ? @"99+" : [NSString stringWithFormat:@"%ld",(long)unread];
    cell.stamp.text = unread ? [NSString stringWithFormat:@"%ld новых • %@",(long)unread,date] : date;
    if (cell.dialogStyle || cell.chatStyle) cell.stamp.text=OVKCompactDate(message[@"date"],cell.chatStyle);
    NSString *comments=OVKString(OVKDictionary(item[@"comments"])[@"count"]); NSString *likes=OVKString(OVKDictionary(item[@"likes"])[@"count"]);
    cell.metrics.text = comments.length ? comments : @"0";
    cell.likes.text = likes.length ? likes : @"0";
    [cell setNeedsLayout];
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isChat] && tableView.editing) { [self updateChatActions]; return; }
    [tableView deselectRowAtIndexPath:indexPath animated:YES]; if ([self isProfile] && self.profileInfo) return; NSDictionary *item = [self postAt:indexPath.row];
    if ([self isChat] || [self isPost]) { if (OVKPostAttachments(item).count) [self openAttachmentsForPost:item]; return; }
    if ([self isPeopleList]) {
        if (![item[@"id"] respondsToSelector:@selector(integerValue)]) return;
        [self.navigationController pushViewController:[[OVKListController alloc] initWithMode:@"profile" identifier:item[@"id"] title:OVKName(item)] animated:YES];
    } else if ([self.mode isEqualToString:@"dialogs"]) {
        NSNumber *peer = OVKDictionary(OVKDictionary(item[@"conversation"])[@"peer"])[@"id"]; if (![peer respondsToSelector:@selector(integerValue)]) return;
        if (self.dialogSelected) { self.selectedDialogPeer=OVKString(peer); [tableView reloadData]; self.dialogSelected(peer,[self headingFor:item]); } else [self.navigationController pushViewController:[[OVKListController alloc] initWithMode:@"chat" identifier:peer title:[self headingFor:item]] animated:YES];
    } else {
        OVKListController *post = [[OVKListController alloc] initWithMode:@"post" identifier:nil title:OVKL(@"Запись")]; post.singlePost = item; post.people = [self.people mutableCopy]; [self.navigationController pushViewController:post animated:YES];
    }
}
- (void)openCommentsFor:(NSDictionary *)post { if (!OVKPostReference(post)) { OVKAlert(OVKL(@"Комментарии"),OVKL(@"Не удалось определить адрес записи.")); return; } [self.navigationController pushViewController:[[OVKCommentsController alloc] initWithPost:post] animated:YES]; }
- (void)refreshPost {
    NSDictionary *reference=OVKPostReference(self.singlePost); if (!reference || self.loading) { [self.refreshControl endRefreshing]; return; }
    self.loading=YES; NSUInteger generation=++self.generation;
    NSString *posts=[NSString stringWithFormat:@"%@_%@",reference[@"owner_id"],reference[@"post_id"]];
    [[OVKAPI shared] call:@"wall.getById" parameters:@{@"posts":posts,@"extended":@1,@"fields":@"photo_100,verified"} completion:^void(id result,NSError *error) {
        if (generation!=self.generation) return; self.loading=NO; [self finishPendingWallRefresh]; [self.refreshControl endRefreshing];
        NSArray *posts=[result isKindOfClass:[NSArray class]] ? result : OVKArray(OVKDictionary(result)[@"items"]);
        if (error) { self.notice.text=error.localizedDescription; return; }
        if (posts.count && [posts[0] isKindOfClass:[NSDictionary class]]) { [self.rowHeights removeAllObjects]; self.singlePost=posts[0]; self.items=[NSMutableArray arrayWithObject:self.singlePost]; [self indexPeople:OVKDictionary(result)]; self.notice.text=OVKL(@"Запись"); [self.tableView reloadData]; }
    }];
}
- (void)finishPendingWallRefresh {
    if (!self.needsWallRefresh) return; self.needsWallRefresh=NO;
    __weak OVKListController *weakSelf=self; dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf refresh]; });
}
- (void)wallChanged:(NSNotification *)note {
    NSDictionary *changed=OVKDictionary(note.object); BOOL relevant=[self.mode isEqualToString:@"news"];
    if ([self.mode isEqualToString:@"archive"]) relevant=[OVKString([OVKAPI shared].userID) isEqualToString:OVKString(changed[@"owner_id"])];
    if ([self isProfile]) relevant=[OVKString(self.identifier) isEqualToString:OVKString(changed[@"owner_id"])];
    if ([self isPost]) { NSDictionary *ref=OVKPostReference(self.singlePost); relevant=[OVKString(ref[@"owner_id"]) isEqualToString:OVKString(changed[@"owner_id"])] && [OVKString(ref[@"post_id"]) isEqualToString:OVKString(changed[@"post_id"])]; }
    if (!relevant) return; if (self.loading) { self.needsWallRefresh=YES; return; } [self refresh];
}
- (NSString *)profileURL { return [NSString stringWithFormat:@"%@/id%@",[OVKAPI shared].siteServer ?: [OVKAPI shared].server,self.identifier]; }
- (void)profileActions { UIActionSheet *sheet=[[UIActionSheet alloc] initWithTitle:OVKName(self.user) delegate:self cancelButtonTitle:OVKL(@"Отмена") destructiveButtonTitle:nil otherButtonTitles:OVKL(@"Открыть в Safari"),OVKL(@"Скопировать ссылку"),nil]; [sheet showInView:self.view]; }
- (void)actionSheet:(UIActionSheet *)sheet didDismissWithButtonIndex:(NSInteger)index {
    if (sheet.tag==1003) {
        NSDictionary *message=self.messageToEdit; self.messageToEdit=nil;
        if (index>=0 && index!=sheet.cancelButtonIndex && message) [self openMessageEditor:message];
        return;
    }
    if (sheet.tag==1001) {
    if (index==sheet.cancelButtonIndex || index<0 || (NSUInteger)index>=self.postActions.count) return;
    NSString *action=self.postActions[index]; NSDictionary *post=self.actionPost;
    if ([action isEqual:@"share"]) { [self sharePost:post]; return; }
    if ([action isEqual:@"edit"]) {
        OVKComposeController *editor=[[OVKComposeController alloc] init];
        editor.identifier=OVKPostReference(post)[@"owner_id"]; editor.editingPost=post;
        [self showEditor:editor]; return;
    }
    if ([action isEqual:@"delete"]) { UIAlertView *alert=[[UIAlertView alloc] initWithTitle:OVKL(@"Удалить запись?") message:OVKL(@"Запись будет удалена со стены.") delegate:self cancelButtonTitle:OVKL(@"Отмена") otherButtonTitles:OVKL(@"Удалить"),nil]; alert.tag=1002; [alert show]; return; }
    [self performPostAction:action post:post]; return;
} if (index==0) [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[self profileURL]]]; if (index==1) { UIPasteboard *pasteboard=[UIPasteboard generalPasteboard]; pasteboard.string=[self profileURL]; } }
- (NSString *)postRequestKey:(NSDictionary *)post { NSDictionary *ref=OVKPostReference(post); return ref ? [NSString stringWithFormat:@"%@_%@",ref[@"owner_id"],ref[@"post_id"]] : @""; }
- (void)togglePostLike:(NSDictionary *)post {
    NSString *key=[self postRequestKey:post]; if (!key.length || [self.postRequests containsObject:key] || self.loading) return;
    if ([OVKAPI shared].demo) { OVKAlert(OVKL(@"Демонстрация"),OVKL(@"Для отметок и действий с записями войдите в аккаунт.")); return; }
    NSDictionary *params=OVKPostActionParameters(post,@"like",[OVKAPI shared].userID); if (!params) return;
    BOOL liked=[OVKDictionary(post[@"likes"])[@"user_likes"] boolValue]; [self.postRequests addObject:key]; [self.tableView reloadData];
    [[OVKAPI shared] call:liked ? @"likes.delete" : @"likes.add" parameters:params completion:^void(id result,NSError *error) {
        [self.postRequests removeObject:key]; if (error) { [self.tableView reloadData]; OVKAlert(OVKL(@"Не удалось изменить отметку"),error.localizedDescription); return; }
        // Read the authoritative post after the write; no guessed counts or automatic write retries.
        [[NSNotificationCenter defaultCenter] postNotificationName:@"OVKWallChanged" object:OVKPostReference(post)]; if (!self.loading) [self refresh];
    }];
}
- (void)postHeld:(UILongPressGestureRecognizer *)press {
    if (press.state!=UIGestureRecognizerStateBegan || self.presentedViewController || ([self isProfile] && self.profileInfo)) return;
    NSIndexPath *path=[self.tableView indexPathForRowAtPoint:[press locationInView:self.tableView]]; if (!path || (NSUInteger)path.row>=[self visibleItems].count) return;
    [self showPostActions:[self postAt:path.row] atPoint:[press locationInView:self.tableView]];
}
- (void)showPostActions:(NSDictionary *)post atPoint:(CGPoint)point {
    if (!OVKPostReference(post) || self.presentedViewController) return;
    self.actionPost=post; NSMutableArray *actions=[NSMutableArray array];
    UIActionSheet *sheet=[[UIActionSheet alloc] initWithTitle:OVKL(@"Запись") delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil]; sheet.tag=1001;
    NSString *archive=[post[@"is_archived"] boolValue] || [self.mode isEqual:@"archive"] ? @"reveal" : @"archive";
    NSString *pin=[post[@"is_pinned"] boolValue] ? @"unpin" : @"pin";
    NSDictionary *names=@{@"archive":OVKL(@"В архив"),@"reveal":OVKL(@"Вернуть на стену"),@"pin":OVKL(@"Закрепить"),@"unpin":OVKL(@"Открепить"),@"edit":OVKL(@"Редактировать"),@"delete":OVKL(@"Удалить"),@"share":OVKL(@"Поделиться")};
    for (NSString *action in @[@"edit",archive,@"delete",pin,@"share"]) if ([action isEqual:@"share"] || OVKPostAllowsAction(post,action,[OVKAPI shared].userID)) { NSInteger index=[sheet addButtonWithTitle:names[action]]; if ([action isEqual:@"delete"]) sheet.destructiveButtonIndex=index; [actions addObject:action]; }
    self.postActions=actions; sheet.cancelButtonIndex=[sheet addButtonWithTitle:OVKL(@"Отмена")];
    if (UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad) [sheet showFromRect:CGRectMake(point.x,point.y,1,1) inView:self.tableView animated:YES];
    else [sheet showInView:self.view];
}
- (void)sharePost:(NSDictionary *)post {
    NSDictionary *ref=OVKPostReference(post); NSString *site=[OVKAPI shared].siteServer ?: [OVKAPI shared].server; if (!ref || !site.length || [OVKAPI shared].demo) return;
    NSURL *url=[NSURL URLWithString:[NSString stringWithFormat:@"%@/wall%@_%@",site,ref[@"owner_id"],ref[@"post_id"]]]; if (!url) return;
    UIActivityViewController *share=[[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    if (UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad) { self.sharePopover=[[UIPopoverController alloc] initWithContentViewController:share]; [self.sharePopover presentPopoverFromRect:CGRectMake(self.view.bounds.size.width/2,self.view.bounds.size.height/2,1,1) inView:self.view permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES]; }
    else [self presentViewController:share animated:YES completion:nil];
}
- (void)performPostAction:(NSString *)action post:(NSDictionary *)post {
    if ([OVKAPI shared].demo) { OVKAlert(OVKL(@"Демонстрация"),OVKL(@"Для отметок и действий с записями войдите в аккаунт.")); return; }
    NSString *key=[self postRequestKey:post]; NSDictionary *params=OVKPostActionParameters(post,action,[OVKAPI shared].userID); if (!params || [self.postRequests containsObject:key]) return;
    [self.postRequests addObject:key];
    [[OVKAPI shared] call:[@"wall." stringByAppendingString:action] parameters:params completion:^void(id result,NSError *error) {
        [self.postRequests removeObject:key]; if (error || ![result respondsToSelector:@selector(integerValue)] || [result integerValue]!=1) { OVKAlert(OVKL(@"Действие не выполнено"),error.localizedDescription ?: OVKL(@"Сервер не подтвердил изменение записи.")); return; }
        for (NSString *route in @[@"wall.get",@"wall.getById",@"newsfeed.get",@"newsfeed.getGlobal"]) [[OVKAPI shared] invalidateCachedMethod:route peer:nil];
        if ([action isEqualToString:@"delete"]) {
            // Discard any feed response that started before the confirmed deletion.
            if (self.loading) { self.generation++; self.loading=NO; [self.refreshControl endRefreshing]; }
            NSIndexSet *rows=[self.items indexesOfObjectsPassingTest:^BOOL(NSDictionary *item,NSUInteger idx,BOOL *stop) { return [[self postRequestKey:item] isEqualToString:key]; }];
            [self.items removeObjectsAtIndexes:rows]; [self.rowHeights removeAllObjects]; [self.tableView reloadData];
        }
        if ([self isPost] && [@[@"delete",@"archive",@"reveal"] containsObject:action]) { self.mode=@"removed"; [self.navigationController popViewControllerAnimated:YES]; }
        [[NSNotificationCenter defaultCenter] postNotificationName:@"OVKWallChanged" object:OVKPostReference(post)];
    }];
}
- (void)openAttachmentsForPost:(NSDictionary *)post {
    NSArray *items = OVKPostAttachments(post);
    if (!items.count) { if ([self isPost]) [self openPost]; return; }
    [self.navigationController pushViewController:[[OVKAttachmentsController alloc] initWithAttachments:items title:OVKL(@"Вложения")] animated:YES];
}
- (void)openProfilePhoto {
    NSString *url = OVKString(self.user[@"photo_max_orig"] ?: self.user[@"photo_200"] ?: self.user[@"photo_100"]);
    if (url.length) OVKPresentPhoto(self,[[OVKPhotoController alloc] initWithURL:url title:OVKL(@"Аватар")]);
}
- (void)openPost {
    NSDictionary *post = self.singlePost; NSString *owner = OVKString(post[@"owner_id"] ?: post[@"source_id"] ?: post[@"from_id"]); NSString *identifier = OVKString(post[@"id"] ?: post[@"post_id"]);
    if (!owner.length || !identifier.length || [OVKAPI shared].demo) { OVKAlert(OVKL(@"Деморежим"),OVKL(@"Эта запись существует только в демоверсии.")); return; }
    // The API host may also serve web routes; users can use their instance's redirect to the web domain.
    NSString *host = [OVKAPI shared].siteServer ?: [OVKAPI shared].server; if ([host isEqualToString:@"https://api.openvk.org"]) host = @"https://openvk.org";
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/wall%@_%@",host,owner,identifier]]];
}
- (void)openChat { [self.navigationController pushViewController:[[OVKListController alloc] initWithMode:@"chat" identifier:self.identifier title:OVKName(self.user)] animated:YES]; }
- (void)compose {
    OVKComposeController *compose = [[OVKComposeController alloc] init]; compose.identifier = [self isChat] ? self.identifier : [OVKAPI shared].userID; compose.message = [self isChat]; __weak OVKListController *weakSelf = self; if ([self isChat]) compose.sent = ^{ [weakSelf refresh]; };
    UINavigationController *nav = [[OVKNavigationController alloc] initWithRootViewController:compose]; OVKStyleNavigation(nav); [self presentViewController:nav animated:YES completion:nil];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end

@implementation OVKNavigationController
- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations {
    UIViewController *presented=self.presentedViewController;
    if (presented && !presented.isBeingDismissed && presented.modalPresentationStyle==UIModalPresentationFullScreen) return presented.supportedInterfaceOrientations;
    UIViewController *page=self.topViewController;
    if ([page isKindOfClass:[OVKPhotoController class]] || [page isKindOfClass:NSClassFromString(@"OVKPlaybackController")]) return page.supportedInterfaceOrientations;
    return UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskPortrait;
}
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation { return UIInterfaceOrientationPortrait; }
@end
