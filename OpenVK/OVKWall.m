#import "OVKLanguage.h"
#import "OVKWall.h"
#import "OVKWallModel.h"
#import "OVKAPI.h"
#import "OVKUI.h"
#import "OVKMedia.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>
static UIImage *OVKAttachmentImage(UIImage *photo, CGFloat longestSide) {
    if (!photo) return nil;
    CGFloat longest=MAX(photo.size.width,photo.size.height);
    if (longest<=0) return nil;
    CGFloat scale=MIN(1,longestSide/longest);
    CGSize size=CGSizeMake(MAX(1,floor(photo.size.width*scale)),MAX(1,floor(photo.size.height*scale)));
    UIGraphicsBeginImageContextWithOptions(size,YES,1);
    [photo drawInRect:(CGRect){CGPointZero,size}];
    UIImage *image=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
    return image;
}
@interface OVKVideoUploadPage : UIViewController <UIWebViewDelegate>
@property (strong, nonatomic) NSURL *origin;
@property (copy, nonatomic) void (^received)(NSString *reference);
@property (strong, nonatomic) UIWebView *browser;
@end
@implementation OVKVideoUploadPage
- (void)viewDidLoad {
    [super viewDidLoad]; OVKConfigureEdges(self);
    self.title=OVKL(@"Видео из Галереи");
    self.browser=[[UIWebView alloc] initWithFrame:self.view.bounds];
    self.browser.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    self.browser.scalesPageToFit=YES;
    self.browser.delegate=self; [self.view addSubview:self.browser];
    NSURL *url=[NSURL URLWithString:@"/videos/upload" relativeToURL:self.origin];
    [self.browser loadRequest:[NSURLRequest requestWithURL:url.absoluteURL]];
}
- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)type {
    NSURL *url=request.URL;
    if ([url.scheme isEqualToString:@"about"]) return YES;
    if (![url.scheme isEqualToString:@"https"] || ![url.host.lowercaseString isEqualToString:self.origin.host.lowercaseString] ||
        ![(url.port ?: @443) isEqual:self.origin.port ?: @443]) return NO;
    if ([url isEqual:request.mainDocumentURL] && [self acceptVideoURL:url]) return NO;
    return YES;
}
- (BOOL)acceptVideoURL:(NSURL *)url {
    if (!self.received || ![url.scheme isEqualToString:@"https"] ||
        ![url.host.lowercaseString isEqualToString:self.origin.host.lowercaseString] ||
        ![(url.port ?: @443) isEqual:self.origin.port ?: @443] || ![url.path hasPrefix:@"/video"]) return NO;
    NSString *reference=[url.path substringFromIndex:1];
    NSRange match=[reference rangeOfString:@"^video-?[0-9]+_[1-9][0-9]*$" options:NSRegularExpressionSearch];
    if (match.location==NSNotFound || match.length!=reference.length) return NO;
    void (^callback)(NSString *)=self.received; self.received=nil;
    callback(reference);
    [self.navigationController popViewControllerAnimated:YES];
    return YES;
}
- (void)webViewDidFinishLoad:(UIWebView *)webView {
    NSString *address=[webView stringByEvaluatingJavaScriptFromString:@"document.location.href"];
    if (address.length) [self acceptVideoURL:[NSURL URLWithString:address]];
}
- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
    if (error.code!=NSURLErrorCancelled && error.code!=102) OVKAlert(OVKL(@"Видео из Галереи"),error.localizedDescription);
}
- (void)dealloc { _browser.delegate=nil; [_browser stopLoading]; }
@end

@interface OVKComposeController () <UIActionSheetDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (strong, nonatomic) UITextView *textView;
@property (assign, nonatomic) BOOL sending;
@property (assign, nonatomic) BOOL uploading;
@property (copy, nonatomic) NSString *pendingText;
@property (strong, nonatomic) NSNumber *randomID;
@property (strong, nonatomic) UIToolbar *tools;
@property (strong, nonatomic) UIBarButtonItem *attachItem;
@property (strong, nonatomic) UILabel *attachmentSummary;
@property (strong, nonatomic) UIScrollView *attachmentStrip;
@property (strong, nonatomic) NSMutableArray *attachments;
@property (copy, nonatomic) NSArray *originalAttachmentReferences;
@property (assign, nonatomic) BOOL unsupportedExistingAttachments;
@property (strong, nonatomic) UIPopoverController *galleryPopover;
@property (assign, nonatomic) CGFloat keyboardHeight;
@end
@implementation OVKComposeController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=self.message ? OVKL(@"Сообщение") : (self.postID ? OVKL(@"Комментарий") : OVKL(@"Новая запись"));
    if (self.editingPost) self.title=OVKL(@"Редактировать запись");
    if (self.editingMessage) self.title=OVKL(@"Редактировать сообщение");
    self.view.backgroundColor=OVKThemeSurface();
    OVKConfigureEdges(self);
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:OVKL(@"Отмена") style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
    NSString *sendTitle=(self.editingPost || self.editingMessage) ? OVKL(@"Сохранить") : (self.message ? OVKL(@"Отправить") : (self.postID ? OVKL(@"Ответить") : OVKL(@"Опубликовать")));
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:sendTitle style:UIBarButtonItemStyleDone target:self action:@selector(send)];
    CGFloat top=self.replyName.length ? 30 : 0;
    if (top) { UILabel *reply=[[UILabel alloc] initWithFrame:CGRectMake(10,0,self.view.bounds.size.width-20,30)]; reply.autoresizingMask=UIViewAutoresizingFlexibleWidth; reply.text=[NSString stringWithFormat:OVKL(@"Ответ: %@"),self.replyName]; reply.font=[UIFont systemFontOfSize:12]; reply.textColor=OVKBlue(); reply.backgroundColor=[UIColor clearColor]; [self.view addSubview:reply]; }
    self.textView=[[UITextView alloc] initWithFrame:CGRectMake(0,top,self.view.bounds.size.width,self.view.bounds.size.height-top)]; self.textView.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; self.textView.font=[UIFont systemFontOfSize:16]; self.textView.backgroundColor=OVKThemeSurface(); self.textView.textColor=OVKThemeText(); self.textView.keyboardAppearance=OVKDarkTheme() ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault; [self.view addSubview:self.textView];
    self.textView.text=self.initialText ?: OVKString((self.editingPost ?: self.editingMessage)[@"text"]);
    self.attachments=[NSMutableArray array];
    self.tools=[[UIToolbar alloc] init];
    self.attachItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(chooseAttachment)];
    self.attachItem.accessibilityLabel=OVKL(@"Добавить вложение");
    UIBarButtonItem *space=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *done=[[UIBarButtonItem alloc] initWithTitle:OVKL(@"Готово") style:UIBarButtonItemStyleDone target:self action:@selector(hideKeyboard)];
    self.tools.items=(self.message || !self.postID) ? @[self.attachItem,space,done] : @[space,done];
    [self.view addSubview:self.tools];
    self.attachmentSummary=[[UILabel alloc] init];
    self.attachmentSummary.font=[UIFont systemFontOfSize:12]; self.attachmentSummary.backgroundColor=OVKThemeSurface(); self.attachmentSummary.textColor=OVKThemeSecondary();
    [self.view addSubview:self.attachmentSummary];
    self.attachmentStrip=[[UIScrollView alloc] init];
    self.attachmentStrip.showsHorizontalScrollIndicator=NO;
    [self.view addSubview:self.attachmentStrip];
    [self importExistingAttachments];
    self.originalAttachmentReferences=[self attachmentReferencesForRequest];
    [self updateAttachmentSummary];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboard:) name:UIKeyboardWillChangeFrameNotification object:nil];
    if (!self.showAttachmentPickerOnOpen) [self.textView becomeFirstResponder];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.showAttachmentPickerOnOpen) { self.showAttachmentPickerOnOpen=NO; [self chooseAttachment]; }
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.navigationController.navigationBar setBackgroundImage:[UIImage imageNamed:@"MusicNavigation"] forBarMetrics:UIBarMetricsDefault]; self.navigationController.navigationBar.barStyle=UIBarStyleBlack; [self.navigationItem.leftBarButtonItem setBackgroundImage:OVKThemeStretch(@"MusicButton") forState:UIControlStateNormal barMetrics:UIBarMetricsDefault]; }
- (void)hideKeyboard { [self.textView resignFirstResponder]; }
- (void)keyboard:(NSNotification *)note {
    CGRect frame=[self.view convertRect:[note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
    CGRect overlap=CGRectIntersection(self.view.bounds,frame);
    self.keyboardHeight=CGRectIsNull(overlap) ? 0 : CGRectGetHeight(overlap);
    [self.view setNeedsLayout];
    [UIView animateWithDuration:[note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue] animations:^{ [self.view layoutIfNeeded]; }];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width=self.view.bounds.size.width, top=self.replyName.length ? 30 : 0;
    CGFloat toolbarY=MAX(top,self.view.bounds.size.height-self.keyboardHeight-40);
    // Reserve fixed-height attachment cards above the toolbar, leaving the remaining height for text.
    CGFloat summary=self.attachmentSummary.text.length ? 24 : 0;
    CGFloat strip=self.attachments.count ? 72 : 0;
    self.tools.frame=CGRectMake(0,toolbarY,width,40);
    self.attachmentSummary.frame=CGRectMake(10,toolbarY-summary,MAX(0,width-20),summary);
    self.attachmentStrip.frame=CGRectMake(0,toolbarY-summary-strip,width,strip);
    self.textView.frame=CGRectMake(0,top,width,MAX(0,toolbarY-summary-strip-top));
}
- (void)updateAttachmentSummary {
    self.attachmentSummary.text=self.uploading ? OVKL(@"Загрузка фотографии…") : (self.attachments.count ? [NSString stringWithFormat:OVKL(@"Вложений: %lu"),(unsigned long)self.attachments.count] : @"");
    self.attachItem.enabled=!self.uploading && !self.sending;
    self.navigationItem.rightBarButtonItem.enabled=!self.uploading && !self.sending;
    [self renderAttachmentStrip];
    [self.view setNeedsLayout];
}
- (void)renderAttachmentStrip {
    for (UIView *view in [self.attachmentStrip.subviews copy]) [view removeFromSuperview];
    const CGFloat cardWidth=88, cardSpacing=8;
    [self.attachments enumerateObjectsUsingBlock:^(NSDictionary *item,NSUInteger index,BOOL *stop) {
        UIView *card=[[UIView alloc] initWithFrame:CGRectMake(8+index*(cardWidth+cardSpacing),2,cardWidth,66)];
        card.backgroundColor=OVKPostFooterColor(); card.layer.cornerRadius=5;
        [self.attachmentStrip addSubview:card];
        OVKRemoteImageView *image=[[OVKRemoteImageView alloc] initWithFrame:CGRectMake(4,4,cardWidth-8,42)];
        image.clipsToBounds=YES; image.contentMode=UIViewContentModeScaleAspectFit;
        NSString *kind=item[@"type"];
        UIImage *local=item[@"image"];
        if (local) image.image=local;
        else if (OVKString(item[@"preview"]).length) {
            image.contentMode=UIViewContentModeScaleAspectFill;
            image.layer.cornerRadius=3; [image load:item[@"preview"]];
        } else image.image=[UIImage imageNamed:[kind isEqualToString:@"audio"] ? @"AudioMedia" : ([kind isEqualToString:@"video"] ? @"VideoMedia" : @"PhotoMedia")];
        [card addSubview:image];
        UILabel *label=[[UILabel alloc] initWithFrame:CGRectMake(4,47,cardWidth-8,17)];
        label.text=item[@"title"]; label.textColor=OVKThemeText(); label.backgroundColor=[UIColor clearColor];
        label.font=[UIFont systemFontOfSize:11]; label.textAlignment=NSTextAlignmentCenter;
        [card addSubview:label];
        UIButton *remove=[UIButton buttonWithType:UIButtonTypeCustom];
        remove.frame=CGRectMake(cardWidth-30,0,30,30);
        [remove setTitle:@"×" forState:UIControlStateNormal];
        [remove setTitleColor:OVKThemeText() forState:UIControlStateNormal];
        remove.titleLabel.font=[UIFont boldSystemFontOfSize:18];
        remove.backgroundColor=[OVKThemeSurface() colorWithAlphaComponent:.9];
        remove.layer.cornerRadius=5; remove.tag=(NSInteger)index;
        remove.accessibilityLabel=OVKL(@"Убрать вложение");
        remove.enabled=!self.sending && !self.uploading;
        [remove addTarget:self action:@selector(removeAttachment:) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:remove];
    }];
    self.attachmentStrip.contentSize=CGSizeMake(8+self.attachments.count*(cardWidth+cardSpacing),72);
}
- (void)removeAttachment:(UIButton *)button {
    if (self.sending || self.uploading || (NSUInteger)button.tag>=self.attachments.count) return;
    [self.attachments removeObjectAtIndex:(NSUInteger)button.tag];
    [self updateAttachmentSummary];
}
- (void)importExistingAttachments {
    NSDictionary *original=self.editingPost ?: self.editingMessage;
    for (id value in OVKArray(original[@"attachments"])) {
        NSDictionary *entry=OVKDictionary(value);
        NSString *type=OVKString(entry[@"type"]);
        NSDictionary *object=OVKDictionary(entry[type]);
        NSString *reference=OVKAttachmentReference(type,object);
        NSArray *playable=OVKPlayableAttachments(@{@"attachments":@[entry]});
        NSDictionary *preview=playable.count ? playable[0] : @{};
        // The API replaces the complete attachment list on edit. Refuse to silently drop an unknown attachment.
        if (!reference || (self.editingPost && [type isEqualToString:@"wall"])) {
            self.unsupportedExistingAttachments=YES;
            continue;
        }
        [self.attachments addObject:@{@"reference":reference,@"type":type,
                                      @"title":preview[@"title"] ?: (object[@"title"] ?: OVKL(@"Вложение")),
                                      @"preview":preview[@"preview"] ?: @""}];
    }
}
- (void)addAttachmentReference:(NSString *)reference title:(NSString *)title type:(NSString *)type preview:(NSString *)preview image:(UIImage *)image {
    if (!reference.length || self.attachments.count>=10) return;
    for (NSDictionary *item in self.attachments) if ([item[@"reference"] isEqualToString:reference]) return;
    NSMutableDictionary *entry=[@{@"reference":reference,@"title":title ?: OVKL(@"Вложение"),@"type":type,@"preview":preview ?: @""} mutableCopy];
    if (image) entry[@"image"]=image;
    [self.attachments addObject:entry];
    [self updateAttachmentSummary];
}
- (void)chooseAttachment {
    if (self.sending || self.uploading) return;
    if ([OVKAPI shared].demo) { OVKAlert(OVKL(@"Демонстрация"),OVKL(@"Для публикации войдите в свой аккаунт.")); return; }
    [self hideKeyboard];
    UIActionSheet *sheet=[[UIActionSheet alloc] initWithTitle:OVKL(@"Добавить вложение") delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    for (NSString *name in @[OVKL(@"Фото OpenVK"),OVKL(@"Музыка OpenVK"),OVKL(@"Видео OpenVK"),OVKL(@"Галерея")]) [sheet addButtonWithTitle:name];
    sheet.cancelButtonIndex=[sheet addButtonWithTitle:OVKL(@"Отмена")];
    [sheet showFromBarButtonItem:self.attachItem animated:YES];
}
- (void)actionSheet:(UIActionSheet *)sheet didDismissWithButtonIndex:(NSInteger)index {
    if (index==sheet.cancelButtonIndex || index<0) return;
    if (self.attachments.count>=10) { OVKAlert(OVKL(@"Вложения"),OVKL(@"Можно прикрепить до 10 вложений.")); return; }
    if (sheet.tag==1) {
        if (index==0) [self openPhotoGallery];
        if (index==1) [self openVideoGallery];
        return;
    }
    if (index==3) {
        // The instance's web form owns the video picker and upload.
        UIActionSheet *gallery=[[UIActionSheet alloc] initWithTitle:OVKL(@"Галерея") delegate:self cancelButtonTitle:OVKL(@"Отмена") destructiveButtonTitle:nil otherButtonTitles:OVKL(@"Фотография"),OVKL(@"Видео"),nil];
        gallery.tag=1;
        [gallery showFromBarButtonItem:self.attachItem animated:YES];
        return;
    }
    NSArray *kinds=@[@"photo",@"audio",@"video"];
    NSArray *titles=@[OVKL(@"Фотографии"),OVKL(@"Аудиозаписи"),OVKL(@"Видеозаписи")];
    if ((NSUInteger)index>=kinds.count) return;
    OVKLibraryController *picker=[[OVKLibraryController alloc] initWithKind:kinds[index] identifier:[OVKAPI shared].userID title:titles[index]];
    [picker enableCollectionSearch];
    __weak OVKComposeController *weakSelf=self;
    picker.selectedAttachment=^(NSDictionary *attachment) {
        [weakSelf addLibraryAttachment:attachment];
        [weakSelf.navigationController popViewControllerAnimated:YES];
    };
    [self.navigationController pushViewController:picker animated:YES];
}
- (void)addLibraryAttachment:(NSDictionary *)attachment {
    NSDictionary *object=OVKDictionary(attachment[@"object"]);
    NSString *type=OVKString(attachment[@"type"]);
    NSString *reference=OVKAttachmentReference(type,object);
    if (!reference) { OVKAlert(OVKL(@"Вложения"),OVKL(@"Не удалось определить адрес вложения.")); return; }
    NSString *title=OVKString(attachment[@"title"]);
    NSString *preview=OVKString(attachment[@"preview"]);
    if (!preview.length && [type isEqualToString:@"audio"]) preview=OVKPhotoSource(OVKDictionary(OVKDictionary(object[@"album"])[@"thumb"]));
    [self addAttachmentReference:reference title:title.length ? title : nil type:type preview:preview image:attachment[@"image"]];
}
- (void)openPhotoGallery {
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) return;
    UIImagePickerController *picker=[[UIImagePickerController alloc] init];
    picker.sourceType=UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate=self;
    if (UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad) {
        self.galleryPopover=[[UIPopoverController alloc] initWithContentViewController:picker];
        [self.galleryPopover presentPopoverFromBarButtonItem:self.attachItem permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
    } else [self presentViewController:picker animated:YES completion:nil];
}
- (void)closePhotoGallery {
    if (self.galleryPopover) { [self.galleryPopover dismissPopoverAnimated:YES]; self.galleryPopover=nil; }
    else [self dismissViewControllerAnimated:YES completion:nil];
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker { [self closePhotoGallery]; }
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *photo=info[UIImagePickerControllerOriginalImage];
    [self closePhotoGallery];
    if (!photo || photo.size.width<=0 || photo.size.height<=0) return;
    // Keep only a thumbnail in the draft. The larger JPEG lives until its upload finishes.
    UIImage *thumbnail=OVKAttachmentImage(photo,150);
    NSData *jpeg=UIImageJPEGRepresentation(OVKAttachmentImage(photo,1600),.84);
    self.uploading=YES; [self updateAttachmentSummary];
    __weak OVKComposeController *weakSelf=self;
    OVKCompletion completion=^(id result,NSError *error) {
        OVKComposeController *page=weakSelf; if (!page) return;
        page.uploading=NO; [page updateAttachmentSummary];
        if (error) { if (page.view.window) OVKAlert(OVKL(@"Фото из Галереи"),error.localizedDescription); return; }
        NSArray *items=OVKArray(result);
        NSDictionary *object=items.count ? OVKDictionary(items[0]) : OVKDictionary(result);
        NSMutableDictionary *attachment=[@{@"type":@"photo",@"title":OVKL(@"Фотография"),@"object":object} mutableCopy];
        if (thumbnail) attachment[@"image"]=thumbnail;
        [page addLibraryAttachment:attachment];
    };
    if (self.message) [[OVKAPI shared] uploadMessageJPEG:jpeg peer:self.identifier completion:completion];
    else [[OVKAPI shared] uploadWallJPEG:jpeg completion:completion];
}
- (void)openVideoGallery {
    NSString *site=[OVKAPI shared].siteServer ?: [OVKAPI shared].server;
    OVKVideoUploadPage *page=[[OVKVideoUploadPage alloc] init];
    page.origin=[NSURL URLWithString:site];
    __weak OVKComposeController *weakSelf=self;
    page.received=^(NSString *reference) { [weakSelf addUploadedVideo:reference]; };
    [self.navigationController pushViewController:page animated:YES];
}
- (void)addUploadedVideo:(NSString *)reference {
    [self addAttachmentReference:reference title:OVKL(@"Видеозапись") type:@"video" preview:nil image:nil];
    if (![reference hasPrefix:@"video"] || reference.length<=5) return;
    __weak OVKComposeController *weakSelf=self;
    [[OVKAPI shared] call:@"video.get" parameters:@{@"videos":[reference substringFromIndex:5]} completion:^(id result,NSError *error) {
        OVKComposeController *page=weakSelf; if (!page || error) return;
        NSArray *items=[result isKindOfClass:[NSArray class]] ? result : OVKArray(OVKDictionary(result)[@"items"]);
        NSDictionary *video=OVKDictionary(items.count ? items[0] : nil);
        if (!video.count) return;
        NSArray *media=OVKPlayableAttachments(@{@"attachments":@[@{@"type":@"video",@"video":video}]});
        NSDictionary *item=media.count ? media[0] : nil;
        NSUInteger index=[page.attachments indexOfObjectPassingTest:^BOOL(NSDictionary *entry,NSUInteger idx,BOOL *stop) {
            return [entry[@"reference"] isEqualToString:reference];
        }];
        if (!item || index==NSNotFound) return;
        page.attachments[index]=@{@"reference":reference,@"type":@"video",@"title":item[@"title"] ?: OVKL(@"Видеозапись"),@"preview":item[@"preview"] ?: @""};
        [page updateAttachmentSummary];
    }];
}
- (NSArray *)attachmentReferencesForRequest {
    NSMutableArray *references=[NSMutableArray arrayWithCapacity:self.attachments.count];
    for (NSDictionary *attachment in self.attachments) [references addObject:attachment[@"reference"]];
    return references;
}
- (void)cancel { if (!self.sending && !self.uploading) [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)send {
    if (self.sending || self.uploading) return;
    NSArray *references=[self attachmentReferencesForRequest];
    NSString *attachmentString=[references componentsJoinedByString:@","];
    NSString *text=[self.textView.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    BOOL changedAttachments=![references isEqualToArray:self.originalAttachmentReferences];
    if (self.unsupportedExistingAttachments && (!self.editingPost || changedAttachments || !text.length)) {
        OVKAlert(OVKL(@"Не отправлено"),OVKL(@"Эту запись или сообщение нельзя сохранить без потери исходных вложений."));
        return;
    }
    // Reuse the send nonce on a retry only while the draft, reply and attachments are identical.
    NSString *signature=[NSString stringWithFormat:@"%@\n%@\n%@",self.replyID ?: @0,attachmentString,text ?: @""];
    if (![self.pendingText isEqualToString:signature]) { self.pendingText=signature; self.randomID=@(arc4random_uniform(2147483646)+1); }
    NSString *kind=self.message ? @"message" : (self.postID ? @"comment" : @"post");
    NSError *validation=nil;
    NSMutableDictionary *params=[OVKWallWriteParameters(kind,self.identifier,self.postID,self.replyID,self.textView.text,self.randomID,&validation) mutableCopy];
    if (attachmentString.length && self.identifier.longLongValue!=0 && (self.message || [kind isEqualToString:@"post"])) {
        if (!params) params=[@{(self.message ? @"peer_id" : @"owner_id"):self.identifier,@"message":@""} mutableCopy];
        params[self.message ? @"attachment" : @"attachments"]=attachmentString;
    }
    if (!params) { OVKAlert(OVKL(@"Не отправлено"),validation.localizedDescription ?: OVKL(@"Введите текст")); return; }
    if ([OVKAPI shared].demo) { OVKAlert(OVKL(@"Демонстрация"),OVKL(@"Для публикации войдите в свой аккаунт.")); return; }
    NSString *method=self.message ? @"messages.send" : (self.postID ? @"wall.createComment" : @"wall.post");
    NSDictionary *postReference=OVKPostReference(self.editingPost);
    if (self.editingPost) {
        if (!postReference || !OVKPostAllowsAction(self.editingPost,@"edit",[OVKAPI shared].userID)) return;
        [params addEntriesFromDictionary:postReference];
        // OpenVK keeps the old attachments for an omitted value and removes them for the explicit sentinel.
        if (changedAttachments) params[@"attachments"]=attachmentString.length ? attachmentString : @"remove";
        else if (text.length) [params removeObjectForKey:@"attachments"];
        method=@"wall.edit";
    } else if (self.editingMessage) {
        if (!OVKIsOwnChatMessage(self.editingMessage,[OVKAPI shared].userID)) return;
        params[@"message_id"]=self.editingMessage[@"id"];
        params[@"attachment"]=attachmentString;
        params[@"keep_forward_messages"]=@1;
        [params removeObjectForKey:@"random_id"];
        method=@"messages.edit";
    } else if (self.message) {
        params[@"random_id"]=self.randomID;
        if (self.replyID.longLongValue>0) params[@"reply_to"]=self.replyID;
    }
    self.sending=YES; self.textView.editable=NO; self.navigationItem.leftBarButtonItem.enabled=NO; self.navigationItem.rightBarButtonItem.enabled=NO;
    [self updateAttachmentSummary];
    [[OVKAPI shared] call:method parameters:params completion:^void(id result,NSError *error) {
        self.sending=NO; self.textView.editable=YES; self.navigationItem.leftBarButtonItem.enabled=YES; self.navigationItem.rightBarButtonItem.enabled=YES;
        [self updateAttachmentSummary];
        if (error || ((self.editingPost || self.editingMessage) && [OVKString(result) isEqualToString:@"0"])) {
            OVKAlert(OVKL(@"Не отправлено"),error.localizedDescription ?: OVKL(@"Сервер не подтвердил изменение."));
            return;
        }
        OVKAPI *api=[OVKAPI shared];
        if (self.editingMessage) {
            [api invalidateCachedMethod:@"messages.getHistory" peer:self.identifier];
            [api invalidateCachedMethod:@"messages.getConversations" peer:nil];
            if (self.savedMessage) {
                void (^update)(NSDictionary *)=self.savedMessage;
                NSMutableDictionary *local=[self.editingMessage mutableCopy];
                local[@"text"]=text ?: @"";
                update(local);
                [api call:@"messages.getById" parameters:@{@"message_ids":self.editingMessage[@"id"]} completion:^(id response,NSError *fetchError) {
                    NSArray *items=[response isKindOfClass:[NSArray class]] ? response : OVKArray(OVKDictionary(response)[@"items"]);
                    if (!fetchError && items.count && [items[0] isKindOfClass:[NSDictionary class]]) update(items[0]);
                }];
            }
        }
        if (!self.message) {
            if (self.editingPost) for (NSString *route in @[@"wall.get",@"wall.getById",@"newsfeed.get",@"newsfeed.getGlobal"]) [api invalidateCachedMethod:route peer:nil];
            NSDictionary *changed=postReference ?: (self.postID ? @{@"owner_id":self.identifier,@"post_id":self.postID} : @{@"owner_id":self.identifier});
            [[NSNotificationCenter defaultCenter] postNotificationName:@"OVKWallChanged" object:changed];
        }
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
    self.notice=[[UILabel alloc] initWithFrame:CGRectMake(0,0,320,30)]; self.notice.numberOfLines=2; self.notice.textAlignment=NSTextAlignmentCenter; self.notice.font=[UIFont systemFontOfSize:12]; self.notice.textColor=OVKThemeSecondary(); self.notice.backgroundColor=OVKThemeSurface(); self.tableView.tableHeaderView=self.notice;
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
    void (^show)(id)=^(id result) {
        if (generation!=self.generation) return;
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
    };
    [[OVKAPI shared] call:@"wall.getComments" parameters:params cached:^(id result) {
        if (!append && !self.items.count) show(result);
    } completion:^(id result,NSError *error) {
        if (generation!=self.generation) return; self.loading=NO; [self.refreshControl endRefreshing];
        if (error) { if (!self.items.count) self.notice.text=error.localizedDescription; [self.moreButton setTitle:OVKL(@"Повторить") forState:UIControlStateNormal]; return; }
        show(result);
    }];
}
- (NSString *)nameFor:(NSDictionary *)comment { NSDictionary *person=OVKDictionary(self.people[OVKString(comment[@"from_id"])]); NSString *name=OVKString(person[@"name"]); if (!name.length) name=[[NSString stringWithFormat:@"%@ %@",OVKString(person[@"first_name"]),OVKString(person[@"last_name"])] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]; return name.length ? name : OVKL(@"Пользователь"); }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.items.count; }
- (NSDictionary *)commentPhoto:(NSDictionary *)comment {
    for (NSDictionary *item in OVKPlayableAttachments(comment)) if ([item[@"type"] isEqualToString:@"photo"]) return item;
    return nil;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path {
    NSDictionary *item=self.items[path.row];
    NSString *message=OVKString(item[@"text"]);
    CGSize text=[message sizeWithFont:[UIFont systemFontOfSize:14] constrainedToSize:CGSizeMake(MAX(1,tableView.bounds.size.width-62),20000) lineBreakMode:NSLineBreakByWordWrapping];
    NSArray *attachments=OVKPlayableAttachments(item);
    NSArray *audio=[OVKInlineAudioView tracksFromAttachments:attachments];
    CGFloat media=[self commentPhoto:item] ? 122 : (attachments.count>audio.count ? 25 : 0);
    return MAX(58,48+(message.length ? ceil(text.height)+4 : 0)+media+[OVKInlineAudioView heightForTracks:audio]);
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    NSDictionary *item=self.items[path.row]; UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil]; CGFloat width=tableView.bounds.size.width;
    OVKRemoteImageView *avatar=[[OVKRemoteImageView alloc] initWithFrame:CGRectMake(9,9,34,34)]; avatar.contentMode=UIViewContentModeScaleAspectFill; avatar.clipsToBounds=YES; avatar.layer.cornerRadius=3; NSDictionary *person=OVKDictionary(self.people[OVKString(item[@"from_id"])]); [avatar load:OVKString(person[@"photo_100"] ?: person[@"photo_50"])]; [cell.contentView addSubview:avatar]; if ([OVKString(item[@"from_id"]) longLongValue]>0) { avatar.userInteractionEnabled=YES; avatar.tag=[OVKString(item[@"from_id"]) integerValue]; [avatar addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(commentAvatarTapped:)]]; }
    CGFloat textWidth=MAX(1,width-62);
    UILabel *name=[[UILabel alloc] initWithFrame:CGRectMake(52,6,textWidth,19)]; name.font=[UIFont boldSystemFontOfSize:13]; name.text=[self nameFor:item]; [cell.contentView addSubview:name];
    NSString *text=OVKString(item[@"text"]); CGSize size=[text sizeWithFont:[UIFont systemFontOfSize:14] constrainedToSize:CGSizeMake(textWidth,20000) lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat bodyHeight=text.length ? ceil(size.height) : 0;
    UILabel *body=[[UILabel alloc] initWithFrame:CGRectMake(52,26,textWidth,bodyHeight)]; body.font=[UIFont systemFontOfSize:14]; body.numberOfLines=0; body.text=text; [cell.contentView addSubview:body];
    CGFloat y=CGRectGetMaxY(body.frame)+(bodyHeight ? 4 : 0);
    NSArray *attachments=OVKPlayableAttachments(item);
    NSArray *audio=[OVKInlineAudioView tracksFromAttachments:attachments];
    NSDictionary *photo=[self commentPhoto:item];
    if (photo) {
        OVKRemoteImageView *preview=[[OVKRemoteImageView alloc] initWithFrame:CGRectMake(52,y,MIN(180,textWidth),116)];
        preview.contentMode=UIViewContentModeScaleAspectFit;
        preview.backgroundColor=OVKPostFooterColor();
        preview.clipsToBounds=YES; preview.layer.cornerRadius=3;
        [preview load:OVKString(photo[@"preview"] ?: photo[@"url"])]; [cell.contentView addSubview:preview]; y+=122;
    } else if (attachments.count>audio.count) {
        UILabel *media=[[UILabel alloc] initWithFrame:CGRectMake(52,y,textWidth,21)];
        media.text=OVKL(@"Вложения"); media.font=[UIFont boldSystemFontOfSize:12];
        [cell.contentView addSubview:media]; y+=25;
    }
    if (audio.count) {
        CGFloat playerHeight=[OVKInlineAudioView heightForTracks:audio];
        OVKInlineAudioView *player=[[OVKInlineAudioView alloc] initWithFrame:CGRectMake(52,y,textWidth,playerHeight)];
        player.tracks=audio; [cell.contentView addSubview:player];
        y+=playerHeight;
    }
    UILabel *stamp=[[UILabel alloc] initWithFrame:CGRectMake(52,y,textWidth,17)]; stamp.font=[UIFont systemFontOfSize:11]; stamp.textColor=[UIColor grayColor]; NSTimeInterval time=[OVKString(item[@"date"]) doubleValue]; NSDateFormatter *format=[[NSDateFormatter alloc] init]; format.dateFormat=OVKLanguageIsEnglish() ? @"d MMM HH:mm" : @"d MMM 'в' HH:mm"; format.locale=[[NSLocale alloc] initWithLocaleIdentifier:OVKLanguageIsEnglish() ? @"en_US" : @"ru_RU"]; stamp.text=[NSString stringWithFormat:@"%@%@",time>0 ? [format stringFromDate:[NSDate dateWithTimeIntervalSince1970:time]] : @"",OVKString(item[@"reply_to_comment"]).length ? OVKL(@" · ответ") : @""]; [cell.contentView addSubview:stamp];
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
