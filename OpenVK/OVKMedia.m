#import "OVKLanguage.h"
#import "OVKMedia.h"
#import "OVKTrust.h"
#import "OVKPlaybackSession.h"
#import "OVKLocalAudio.h"
#import "OVKMusic.h"
#import "OVKMediaFormat.h"
#import "OVKUI.h"
#import <ImageIO/ImageIO.h>
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import <stdio.h>
static NSError *MediaError(NSInteger code,NSString *message) { return [NSError errorWithDomain:@"OpenVKMedia" code:code userInfo:@{NSLocalizedDescriptionKey:message}]; }
// The coordinator runs these blocking platform calls on its serial worker queue.
static OVKPlaybackSession *OVKAudioCoordinator(void) {
    static OVKPlaybackSession *coordinator; static dispatch_once_t once;
    dispatch_once(&once, ^{
        coordinator=[[OVKPlaybackSession alloc] initWithActivation:^NSError *{
            NSError *error=nil; AVAudioSession *session=[AVAudioSession sharedInstance];
            BOOL success=[session setCategory:AVAudioSessionCategoryPlayback error:&error] && [session setActive:YES error:&error];
            return success ? nil : (error ?: MediaError(20,OVKL(@"Не удалось активировать звук")));
        } deactivation:^{ [[AVAudioSession sharedInstance] setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:NULL]; }];
    }); return coordinator;
}
static void OVKActivateSession(NSString *owner,void (^completion)(NSError *)) { [OVKAudioCoordinator() activateForOwner:owner completion:completion]; }
static void OVKDeactivateSession(NSString *owner) { if (owner) [OVKAudioCoordinator() deactivateForOwner:owner completion:nil]; }
@interface OVKDownload : NSObject <NSURLConnectionDataDelegate,OVKCancellable>
@property (strong, nonatomic) NSURLConnection *connection;
@property (strong, nonatomic) NSOutputStream *output;
@property (strong, nonatomic) NSURL *currentURL;
@property (copy, nonatomic) NSString *path;
@property (copy, nonatomic) OVKDownloadCompletion completion;
@property (copy, nonatomic) void (^progress)(float);
@property (assign, nonatomic) unsigned long long received;
@property (assign, nonatomic) unsigned long long limit;
@property (assign, nonatomic) long long expected;
@property (assign, nonatomic) NSUInteger redirects;
@property (assign, nonatomic) BOOL finished;
@property (assign, nonatomic) BOOL checkLength;
@property (strong, nonatomic) NSTimer *deadline;
- (void)start:(NSString *)url;
@end
@implementation OVKDownload
- (void)start:(NSString *)url {
    self.currentURL = [NSURL URLWithString:url];
    if (!self.currentURL) { [self finish:nil error:MediaError(1,OVKL(@"Нет адреса медиафайла"))]; return; }
    self.path = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"ovk-media-" stringByAppendingString:[[NSProcessInfo processInfo] globallyUniqueString]]];
    self.output = [NSOutputStream outputStreamToFileAtPath:self.path append:NO]; [self.output open];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.currentURL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:60]; request.HTTPShouldHandleCookies = YES; [request setValue:[OVKAPI requestUserAgent] forHTTPHeaderField:@"User-Agent"];
    // Media GETs never receive the API token or Authorization header.
    self.connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO];
    [self.connection scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes]; [self.connection start];
    self.deadline = [NSTimer timerWithTimeInterval:180 target:self selector:@selector(timedOut) userInfo:nil repeats:NO]; [[NSRunLoop mainRunLoop] addTimer:self.deadline forMode:NSRunLoopCommonModes];
    if (!self.connection) [self finish:nil error:MediaError(2,OVKL(@"Не удалось начать загрузку"))];
}
- (void)timedOut { [self finish:nil error:MediaError(NSURLErrorTimedOut,OVKL(@"Время загрузки истекло. Проверьте сеть и повторите."))]; }
- (void)finish:(NSURL *)file error:(NSError *)error {
    if (self.finished) return; self.finished = YES; [self.deadline invalidate]; self.deadline=nil; [self.output close]; self.output = nil;
    [self.connection cancel]; self.connection = nil;
    if (!file && self.path) [[NSFileManager defaultManager] removeItemAtPath:self.path error:NULL];
    OVKDownloadCompletion callback = self.completion; self.completion = nil; self.progress = nil; if (callback) callback(file,error);
}
- (void)cancel { [self finish:nil error:MediaError(NSURLErrorCancelled,OVKL(@"Загрузка отменена"))]; }
- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response {
    NSString *scheme = request.URL.scheme.lowercaseString;
    if (request.URL.user || request.URL.password || ![@[@"https",@"http"] containsObject:scheme ?: @""] || ([self.currentURL.scheme isEqualToString:@"https"] && ![scheme isEqualToString:@"https"]) || (response && ++self.redirects > 8)) { [self finish:nil error:MediaError(3,OVKL(@"Недопустимое перенаправление медиафайла"))]; return nil; }
    self.currentURL = request.URL; NSMutableURLRequest *redirect = [request mutableCopy]; [redirect setValue:[OVKAPI requestUserAgent] forHTTPHeaderField:@"User-Agent"]; return redirect;
}
- (void)connection:(NSURLConnection *)connection willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    if (![challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) { [challenge.sender performDefaultHandlingForAuthenticationChallenge:challenge]; return; }
    NSString *path = [[NSBundle mainBundle] pathForResource:@"ISRG-Root-X1" ofType:@"cer"]; NSData *root = path ? [NSData dataWithContentsOfFile:path] : nil;
    if ([challenge.protectionSpace.host caseInsensitiveCompare:self.currentURL.host ?: @""] == NSOrderedSame && OVKEvaluateServerTrust(challenge.protectionSpace.serverTrust,challenge.protectionSpace.host,root)) [challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge];
    else { [challenge.sender cancelAuthenticationChallenge:challenge]; [self finish:nil error:MediaError(-1202,OVKL(@"Не удалось проверить сертификат сервера медиа"))]; }
}
- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)response { return nil; }
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    NSInteger status = [(NSHTTPURLResponse *)response statusCode];
    if (status < 200 || status >= 300) { [self finish:nil error:MediaError(status,[NSString stringWithFormat:OVKL(@"Медиа-сервер вернул HTTP %ld"),(long)status])]; return; }
    NSString *mime = response.MIMEType.lowercaseString ?: @"";
    if ([mime hasPrefix:@"text/"] || [mime rangeOfString:@"json"].location != NSNotFound || [mime rangeOfString:@"mpegurl"].location != NSNotFound) { [self finish:nil error:MediaError(4,OVKL(@"Вместо медиа сервер вернул страницу, плейлист или ошибку"))]; return; }
    self.expected = response.expectedContentLength;
    NSString *encoding=@""; NSString *range=@"";
    NSDictionary *headers=[(NSHTTPURLResponse *)response allHeaderFields];
    for (NSString *key in headers) { if ([key caseInsensitiveCompare:@"Content-Encoding"]==NSOrderedSame) encoding=OVKString(headers[key]); if ([key caseInsensitiveCompare:@"Content-Range"]==NSOrderedSame) range=OVKString(headers[key]); }
    self.checkLength=(!encoding.length || [encoding caseInsensitiveCompare:@"identity"]==NSOrderedSame) && self.expected>=0;
    if (status==206) {
        unsigned long long start=0,end=0,total=0;
        if (sscanf([range UTF8String],"bytes %llu-%llu/%llu",&start,&end,&total)!=3 || start!=0 || total==0 || end!=total-1) { [self finish:nil error:MediaError(21,OVKL(@"Сервер прислал лишь часть медиафайла. Воспроизведение неполного файла отменено."))]; return; }
    }
    if (self.expected > 0 && (unsigned long long)self.expected > self.limit) [self finish:nil error:MediaError(5,OVKL(@"Файл слишком большой для загрузки в этом клиенте"))];
}
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    if (self.finished) return;
    if (self.received + data.length > self.limit) { [self finish:nil error:MediaError(5,OVKL(@"Превышен максимальный размер медиафайла"))]; return; }
    const uint8_t *bytes = data.bytes; NSUInteger left = data.length;
    while (left) { NSInteger written = [self.output write:bytes maxLength:left]; if (written <= 0) { [self finish:nil error:MediaError(6,OVKL(@"Не удалось записать файл. Проверьте свободное место."))]; return; } bytes += written; left -= written; }
    self.received += data.length; if (self.progress) self.progress(self.expected > 0 ? MIN(1,(double)self.received/self.expected) : -1);
}
- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    if (self.checkLength && self.received!=(unsigned long long)self.expected) { [self finish:nil error:MediaError(22,OVKL(@"Загрузка медиа оборвалась: размер файла не совпадает с ответом сервера."))]; return; }
    if (!self.received) { [self finish:nil error:MediaError(7,OVKL(@"Сервер вернул пустой файл"))]; return; }
    [self finish:[NSURL fileURLWithPath:self.path] error:nil];
}
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error { [self finish:nil error:error]; }
@end
@class OVKPlaybackController;
static OVKPlaybackController *OVKCurrentMusic;
static void OVKShowCurrentMusic(UIViewController *controller);
static void OVKShowBundledVideo(NSString *name,UIViewController *controller);
static void OVKRouteRemoteControl(UIEvent *event);
static NSUInteger OVKImageCacheGeneration=0;
static NSCache *OVKImageCache(void) { static NSCache *cache; static dispatch_once_t once; dispatch_once(&once, ^{ cache=[[NSCache alloc] init]; cache.totalCostLimit=16*1024*1024; cache.countLimit=80; }); return cache; }
@implementation OVKMedia
+ (void)showBundledVideo:(NSString *)name from:(UIViewController *)controller { OVKShowBundledVideo(name,controller); }
+ (void)clearImageCache { ++OVKImageCacheGeneration; [OVKImageCache() removeAllObjects]; }
+ (void)showCurrentMusicFrom:(UIViewController *)controller { OVKShowCurrentMusic(controller); }
+ (void)handleRemoteControl:(UIEvent *)event { OVKRouteRemoteControl(event); }
+ (id<OVKCancellable>)download:(NSString *)url limit:(unsigned long long)limit progress:(void (^)(float))progress completion:(OVKDownloadCompletion)completion {
    OVKDownload *task = [[OVKDownload alloc] init]; task.limit = limit; task.progress = progress; task.completion = completion;
    // Always start asynchronously so callers can retain a cancellable before completion.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (task.finished) return;
        NSString *source = OVKMediaURL(url);
        if (!source.length) { [task finish:nil error:MediaError(1,OVKL(@"Нет корректного адреса медиафайла"))]; return; }
        if ([source hasPrefix:@"demo:"]) {
            NSString *name = [source substringFromIndex:5]; NSString *path = [[NSBundle mainBundle] pathForResource:[name stringByDeletingPathExtension] ofType:[name pathExtension]];
            NSString *copy = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"ovk-demo-" stringByAppendingString:[[NSProcessInfo processInfo] globallyUniqueString]]];
            NSError *error = nil;
            if (!path || ![[NSFileManager defaultManager] copyItemAtPath:path toPath:copy error:&error]) { [task finish:nil error:error ?: MediaError(8,OVKL(@"Нет демомедиа"))]; return; }
            task.path = copy; [task finish:[NSURL fileURLWithPath:copy] error:nil]; return;
        }
        [task start:source];
    }); return task;
}
+ (id<OVKCancellable>)image:(NSString *)url completion:(void (^)(UIImage *,NSError *))completion { return [self image:url maxPixelSize:512 completion:completion]; }
+ (id<OVKCancellable>)image:(NSString *)url maxPixelSize:(NSUInteger)pixels completion:(void (^)(UIImage *,NSError *))completion {
    pixels=MAX(64,MIN(2048,pixels));
    NSString *source = OVKMediaURL(url);
    NSCache *cache=OVKImageCache(); NSUInteger cacheGeneration=OVKImageCacheGeneration;
    if ([source hasPrefix:@"demo:"]) { UIImage *image = [UIImage imageNamed:[source substringFromIndex:5]]; dispatch_async(dispatch_get_main_queue(), ^{ completion(image,image ? nil : MediaError(8,OVKL(@"Нет демоизображения"))); }); return nil; }
    NSString *cacheKey=[NSString stringWithFormat:@"%lu:%@",(unsigned long)pixels,source];
    UIImage *saved = [cache objectForKey:cacheKey];
    if (saved) { dispatch_async(dispatch_get_main_queue(), ^{ completion(saved,nil); }); return nil; }
    return [self download:source limit:20*1024*1024 progress:nil completion:^(NSURL *file,NSError *error) {
        if (error) { completion(nil,error); return; }
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), ^{
            CGImageSourceRef input = CGImageSourceCreateWithURL((__bridge CFURLRef)file,NULL); CGImageRef image = NULL;
            if (input) { NSDictionary *options = @{(__bridge id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(__bridge id)kCGImageSourceThumbnailMaxPixelSize:@(pixels),(__bridge id)kCGImageSourceCreateThumbnailWithTransform:@YES}; image = CGImageSourceCreateThumbnailAtIndex(input,0,(__bridge CFDictionaryRef)options); CFRelease(input); }
            UIImage *decoded = image ? [UIImage imageWithCGImage:image] : nil; if (image) CGImageRelease(image);
            [[NSFileManager defaultManager] removeItemAtURL:file error:NULL];
            dispatch_async(dispatch_get_main_queue(), ^{ if (decoded && cacheGeneration==OVKImageCacheGeneration) [cache setObject:decoded forKey:cacheKey cost:(NSUInteger)(decoded.size.width*decoded.size.height*4)]; completion(decoded,decoded ? nil : MediaError(9,OVKL(@"Не удалось прочитать изображение"))); });
        });
    }];
}
@end
@interface OVKRemoteImageView ()
@property (strong, nonatomic) id<OVKCancellable> task;
@end
@implementation OVKRemoteImageView
- (void)load:(NSString *)url {
    self.source = nil; [self.task cancel]; self.task = nil; self.source = OVKMediaURL(url); self.image = [UIImage imageNamed:@"Avatar"];
    if (!self.source.length) return;
    NSString *source = [self.source copy]; __weak OVKRemoteImageView *weakSelf = self;
    self.task = [OVKMedia image:source completion:^(UIImage *image,NSError *error) { if (![weakSelf.source isEqualToString:source]) return; weakSelf.task = nil; if (image) weakSelf.image = image; }];
}
- (void)dealloc { [_task cancel]; }
@end
@interface OVKPhotoController () <UIScrollViewDelegate,UIGestureRecognizerDelegate>
@property (copy, nonatomic) NSString *url;
@property (strong, nonatomic) UIScrollView *scroll;
@property (strong, nonatomic) UIImageView *photo;
@property (strong, nonatomic) UILabel *status;
@property (strong, nonatomic) id<OVKCancellable> task;
@property (assign, nonatomic) NSUInteger photoGeneration;
@property (strong, nonatomic) NSArray *photos;
@property (assign, nonatomic) NSUInteger photoIndex;
@property (strong, nonatomic) UIToolbar *photoToolbar;
@property (strong, nonatomic) UIBarButtonItem *previousPhoto;
@property (strong, nonatomic) UIBarButtonItem *nextPhoto;
@end
@implementation OVKPhotoController
- (id)initWithURL:(NSString *)url title:(NSString *)title { self = [super initWithNibName:nil bundle:nil]; if (self) { self.url = url; self.title = title; } return self; }
- (id)initWithPhotos:(NSArray *)photos index:(NSUInteger)index {
    if (!photos.count) return [self initWithURL:@"" title:OVKL(@"Фотография")];
    index=MIN(index,photos.count-1); self=[self initWithURL:OVKString(OVKDictionary(photos[index])[@"url"]) title:OVKL(@"Фотография")];
    if (self) { self.photos=[photos copy]; self.photoIndex=index; } return self;
}
- (void)viewDidLoad {
    [super viewDidLoad]; OVKConfigureEdges(self);
    self.view.backgroundColor = [UIColor blackColor]; self.scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds]; self.scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; self.scroll.delegate = self; self.scroll.maximumZoomScale = 4; self.scroll.bouncesZoom=YES; self.scroll.showsHorizontalScrollIndicator=NO; self.scroll.showsVerticalScrollIndicator=NO; [self.view addSubview:self.scroll];
    self.photo = [[UIImageView alloc] initWithFrame:self.scroll.bounds]; self.photo.contentMode = UIViewContentModeScaleAspectFit; [self.scroll addSubview:self.photo]; UITapGestureRecognizer *doubleTap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(zoomPhoto:)]; doubleTap.numberOfTapsRequired=2; [self.scroll addGestureRecognizer:doubleTap];
    self.status = [[UILabel alloc] initWithFrame:CGRectMake(10,15,self.view.bounds.size.width-20,60)]; self.status.autoresizingMask = UIViewAutoresizingFlexibleWidth; self.status.backgroundColor = [UIColor clearColor]; self.status.textColor = [UIColor whiteColor]; self.status.textAlignment = NSTextAlignmentCenter; self.status.font = [UIFont systemFontOfSize:13]; self.status.numberOfLines = 3; self.status.text = OVKL(@"Загрузка фотографии…"); [self.view addSubview:self.status];
    if (self.photos.count>1) {
        self.photoToolbar=[[UIToolbar alloc] init]; self.photoToolbar.barStyle=UIBarStyleBlack; self.photoToolbar.translucent=NO; [self.view addSubview:self.photoToolbar];
        self.previousPhoto=[[UIBarButtonItem alloc] initWithTitle:OVKL(@"Назад") style:UIBarButtonItemStylePlain target:self action:@selector(previousPicture)];
        self.nextPhoto=[[UIBarButtonItem alloc] initWithTitle:OVKL(@"Вперёд") style:UIBarButtonItemStylePlain target:self action:@selector(nextPicture)];
        UIBarButtonItem *space=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil]; self.photoToolbar.items=@[self.previousPhoto,space,self.nextPhoto];
        for (NSNumber *direction in @[@(UISwipeGestureRecognizerDirectionLeft),@(UISwipeGestureRecognizerDirectionRight)]) {
            UISwipeGestureRecognizer *swipe=[[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipePicture:)]; swipe.direction=[direction unsignedIntegerValue]; swipe.delegate=self; [self.scroll addGestureRecognizer:swipe]; [self.scroll.panGestureRecognizer requireGestureRecognizerToFail:swipe];
        }
    }
    [self updatePhotoControls];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(loadPhoto)]; [self loadPhoto];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.navigationController.navigationBar setBackgroundImage:[UIImage imageNamed:@"MusicNavigation"] forBarMetrics:UIBarMetricsDefault]; self.navigationController.navigationBar.barStyle=UIBarStyleBlack; }
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; self.navigationController.navigationBar.barStyle=UIBarStyleDefault; OVKStyleNavigation(self.navigationController); }
- (void)loadPhoto {
    NSUInteger generation=++self.photoGeneration; [self.task cancel]; self.task=nil; self.scroll.zoomScale=1; self.photo.image=nil; self.status.hidden = NO; self.status.text = OVKL(@"Загрузка фотографии…");
    __weak OVKPhotoController *weakSelf = self;
    self.task = [OVKMedia image:self.url maxPixelSize:2048 completion:^(UIImage *image,NSError *error) {
        OVKPhotoController *page = weakSelf; if (!page || generation!=page.photoGeneration) return; page.task = nil;
        if (!image) { page.status.text = error.localizedDescription; return; }
        page.photo.image = image; page.status.hidden = YES; page.scroll.zoomScale = 1; [page fitPhoto];
    }];
}
- (void)fitPhoto {
    if (!self.photo.image || self.scroll.zoomScale!=1) return;
    CGSize area=self.scroll.bounds.size, image=self.photo.image.size;
    if (image.width<=0 || image.height<=0) return;
    CGFloat scale=MIN(area.width/image.width,area.height/image.height);
    self.photo.frame=CGRectMake(0,0,image.width*scale,image.height*scale); self.scroll.contentSize=self.photo.bounds.size; [self centerPhoto];
}
- (void)centerPhoto { CGSize area=self.scroll.bounds.size; CGRect frame=self.photo.frame; frame.origin.x=MAX(0,(area.width-frame.size.width)/2); frame.origin.y=MAX(0,(area.height-frame.size.height)/2); self.photo.frame=frame; }
- (void)scrollViewDidZoom:(UIScrollView *)scrollView { [self centerPhoto]; }
- (void)zoomPhoto:(UITapGestureRecognizer *)tap {
    if (!self.photo.image) return;
    if (self.scroll.zoomScale>1.05) { [self.scroll setZoomScale:1 animated:YES]; return; }
    CGPoint point=[tap locationInView:self.photo]; CGSize area=self.scroll.bounds.size; CGFloat scale=MIN(2.5,self.scroll.maximumZoomScale);
    [self.scroll zoomToRect:CGRectMake(point.x-area.width/(2*scale),point.y-area.height/(2*scale),area.width/scale,area.height/scale) animated:YES];
}
- (void)updatePhotoControls {
    if (self.photos.count>1) self.title=[NSString stringWithFormat:OVKL(@"%lu из %lu"),(unsigned long)(self.photoIndex+1),(unsigned long)self.photos.count];
    self.previousPhoto.enabled=self.photoIndex>0; self.nextPhoto.enabled=self.photoIndex+1<self.photos.count;
}
- (void)showPicture:(NSUInteger)index { if (index>=self.photos.count || index==self.photoIndex) return; self.photoIndex=index; self.url=OVKString(OVKDictionary(self.photos[index])[@"url"]); [self updatePhotoControls]; [self loadPhoto]; }
- (void)previousPicture { if (self.photoIndex>0) [self showPicture:self.photoIndex-1]; }
- (void)nextPicture { [self showPicture:self.photoIndex+1]; }
- (void)swipePicture:(UISwipeGestureRecognizer *)swipe { if (self.scroll.zoomScale>1.01) return; if (swipe.direction==UISwipeGestureRecognizerDirectionLeft) [self nextPicture]; else [self previousPicture]; }
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture { return self.scroll.zoomScale<=1.01; }
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; CGFloat toolbar=self.photos.count>1 ? 44 : 0; CGSize size=self.view.bounds.size; self.scroll.frame=CGRectMake(0,0,size.width,size.height-toolbar); self.photoToolbar.frame=CGRectMake(0,size.height-toolbar,size.width,toolbar); [self fitPhoto]; }
- (void)viewDidDisappear:(BOOL)animated { [super viewDidDisappear:animated]; if ([self isMovingFromParentViewController] || !self.parentViewController) { ++self.photoGeneration; [self.task cancel]; self.task=nil; } }
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView { return self.photo; }
- (void)dealloc { [_task cancel]; _scroll.delegate = nil; }
@end
@interface OVKPlaybackController : UIViewController <UIAlertViewDelegate>
@property (strong, nonatomic) NSDictionary *item;
@property (strong, nonatomic) id<OVKCancellable> task;
@property (strong, nonatomic) NSURL *localFile;
@property (assign, nonatomic) BOOL temporaryFile;
@property (assign, nonatomic) NSTimeInterval nowPlayingUpdated;
@property (assign, nonatomic) BOOL nowPlayingWasPlaying;
@property (assign, nonatomic) UIBackgroundTaskIdentifier audioTask;
@property (strong, nonatomic) MPMoviePlayerController *movie;
@property (strong, nonatomic) AVURLAsset *soundAsset;
@property (strong, nonatomic) NSURL *soundFile;
@property (strong, nonatomic) AVAssetExportSession *exporter;
@property (assign, nonatomic) BOOL mergingSound;
@property (strong, nonatomic) OVKLocalAudio *music;
@property (assign, nonatomic) BOOL musicPrepared;
@property (strong, nonatomic) UIView *musicView;
@property (strong, nonatomic) UIButton *musicPlay;
@property (strong, nonatomic) UISlider *musicSeek;
@property (strong, nonatomic) UILabel *musicTime;
@property (strong, nonatomic) NSTimer *musicTimer;
@property (assign, nonatomic) double musicPosition;
@property (assign, nonatomic) double musicDuration;
@property (assign, nonatomic) NSInteger lastStartupSecond;
@property (strong, nonatomic) NSArray *queue;
@property (assign, nonatomic) NSUInteger queueIndex;
@property (strong, nonatomic) NSMutableArray *videoURLs;
@property (assign, nonatomic) NSUInteger candidateIndex;
@property (strong, nonatomic) NSMutableArray *diagnostics;
@property (strong, nonatomic) UILabel *status;
@property (strong, nonatomic) UIProgressView *progress;
@property (strong, nonatomic) UIActivityIndicatorView *spinner;
@property (strong, nonatomic) NSTimer *prepareDeadline;
@property (strong, nonatomic) AVURLAsset *asset;
@property (assign, nonatomic) NSUInteger playbackGeneration;
@property (assign, nonatomic) BOOL started;
@property (copy, nonatomic) NSString *sessionOwner;
@property (assign, nonatomic) BOOL activationPending;
@property (assign, nonatomic) BOOL wantsPlayback;
@property (assign, nonatomic) BOOL stopped;
@property (assign, nonatomic) BOOL resolving;
@end
@implementation OVKPlaybackController
- (void)viewDidLoad {
    [super viewDidLoad]; self.audioTask=UIBackgroundTaskInvalid; self.title = OVKString(self.item[@"title"]);
    OVKConfigureEdges(self);
    self.view.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"Linen"]];
    self.status = [[UILabel alloc] initWithFrame:CGRectMake(20,24,self.view.bounds.size.width-40,100)]; self.status.autoresizingMask = UIViewAutoresizingFlexibleWidth; self.status.backgroundColor = [UIColor clearColor]; self.status.textColor = OVKBlue(); self.status.font = [UIFont boldSystemFontOfSize:16]; self.status.textAlignment = NSTextAlignmentCenter; self.status.numberOfLines = 4; self.status.text = self.title; [self.view addSubview:self.status];
    self.progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar]; self.progress.frame = CGRectMake(30,144,self.view.bounds.size.width-60,12); self.progress.autoresizingMask = UIViewAutoresizingFlexibleWidth; [self.view addSubview:self.progress];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(resolveAndLoad)];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(movieEnded:) name:MPMoviePlayerPlaybackDidFinishNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(movieReady:) name:MPMoviePlayerLoadStateDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(movieReady:) name:MPMediaPlaybackIsPreparedToPlayDidChangeNotification object:nil];
    self.spinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray]; self.spinner.center=CGPointMake(self.view.bounds.size.width/2,178); self.spinner.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin; self.spinner.hidesWhenStopped=YES; [self.view addSubview:self.spinner];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationPausing:) name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationResuming:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioInterrupted:) name:AVAudioSessionInterruptionNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(accountLoggedOut:) name:@"OVKSessionChanged" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(accountLoggedOut:) name:@"OVKLogout" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(experimentalChanged:) name:@"OVKExperimentalChanged" object:nil];
    [self resolveAndLoad];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (![self.item[@"type"] isEqualToString:@"video"]) { [self.navigationController.navigationBar setBackgroundImage:[UIImage imageNamed:@"MusicNavigation"] forBarMetrics:UIBarMetricsDefault]; self.navigationController.navigationBar.barStyle=UIBarStyleBlack; }
}
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; if (![self.item[@"type"] isEqualToString:@"video"]) { UIResponder *responder=(UIResponder *)[UIApplication sharedApplication].delegate; [responder becomeFirstResponder]; } }
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; if ([self.item[@"type"] isEqualToString:@"video"]) [self stop]; self.navigationController.navigationBar.barStyle=UIBarStyleDefault; OVKStyleNavigation(self.navigationController); }
- (void)beginAudioTask {
    if (self.audioTask!=UIBackgroundTaskInvalid || [self.item[@"type"] isEqualToString:@"video"]) return;
    __weak OVKPlaybackController *weakSelf=self;
    self.audioTask=[[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{ OVKPlaybackController *page=weakSelf; if (page) [page failPlayback:OVKL(@"Подготовка музыки в фоне не успела завершиться. Откройте плеер и повторите.")]; }];
}
- (void)endAudioTask { if (self.audioTask!=UIBackgroundTaskInvalid) { [[UIApplication sharedApplication] endBackgroundTask:self.audioTask]; self.audioTask=UIBackgroundTaskInvalid; } }
- (void)clearPlaybackFile { if (self.temporaryFile && self.localFile) [[NSFileManager defaultManager] removeItemAtURL:self.localFile error:NULL]; self.localFile=nil; self.temporaryFile=NO; }
- (void)accountLoggedOut:(NSNotification *)note { [self stop]; if (OVKCurrentMusic==self) OVKCurrentMusic=nil; }
- (void)experimentalChanged:(NSNotification *)note { if (([self.item[@"type"] isEqualToString:@"audio"] && !OVKString(self.item[@"local_path"]).length && !OVKExperimentalMusic()) || ([self.item[@"type"] isEqualToString:@"video"] && !OVKExperimentalVideo())) [self stop]; }
- (void)backToMusic { [self.navigationController popViewControllerAnimated:YES]; }
- (void)updateNowPlaying {
    if (OVKCurrentMusic!=self || !self.music) return;
    NSTimeInterval now=[NSDate timeIntervalSinceReferenceDate];
    if (self.nowPlayingUpdated>0 && now-self.nowPlayingUpdated<5 && self.nowPlayingWasPlaying==self.music.playing) return;
    self.nowPlayingUpdated=now; self.nowPlayingWasPlaying=self.music.playing;
    NSDictionary *object=OVKDictionary(self.item[@"object"]);
    NSMutableDictionary *info=[@{MPMediaItemPropertyTitle:OVKString(object[@"title"]).length ? OVKString(object[@"title"]) : OVKString(self.item[@"title"]),MPMediaItemPropertyArtist:OVKString(object[@"artist"]),MPMediaItemPropertyPlaybackDuration:@(self.musicDuration),MPNowPlayingInfoPropertyElapsedPlaybackTime:@(self.musicPosition),MPNowPlayingInfoPropertyPlaybackRate:@(self.music.playing ? 1.0 : 0.0)} mutableCopy];
    MPNowPlayingInfoCenter *center=[MPNowPlayingInfoCenter defaultCenter]; center.nowPlayingInfo=info;
}
- (NSString *)externalURL {
    NSDictionary *object = OVKDictionary(self.item[@"object"]); NSString *player = OVKMediaURL(OVKString(object[@"player"])); if (player.length) return player;
    NSString *owner = OVKString(object[@"owner_id"]), *identifier = OVKString(object[@"id"]);
    if (owner.length && identifier.length && [self.item[@"type"] isEqualToString:@"video"]) return [NSString stringWithFormat:@"%@/video%@_%@",[OVKAPI shared].siteServer,owner,identifier];
    return @"";
}
- (void)unavailable:(NSString *)message {
    self.progress.hidden = YES; [self.spinner stopAnimating]; self.status.text = message;
    if ([self externalURL].length) [[[UIAlertView alloc] initWithTitle:OVKL(@"Нет прямого медиафайла") message:message delegate:self cancelButtonTitle:OVKL(@"Закрыть") otherButtonTitles:OVKL(@"Открыть в Safari"),nil] show];
}
- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index { if (index == 1) [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[self externalURL]]]; }
- (void)resolveAndLoad {
    if (self.task || self.movie || self.music || self.asset || self.resolving) return; self.stopped = NO; [self beginAudioTask]; self.progress.hidden = NO; self.status.text = OVKL(@"Получаем адрес медиафайла…"); [self.spinner startAnimating];
    BOOL isVideo=[self.item[@"type"] isEqualToString:@"video"];
    self.diagnostics=[NSMutableArray array];
    NSString *local=OVKString(self.item[@"local_path"]);
    if (local.length) {
        if (![[NSFileManager defaultManager] fileExistsAtPath:local]) { [self failPlayback:OVKL(@"Локальный файл не найден")]; return; }
        self.localFile=[NSURL fileURLWithPath:local]; self.temporaryFile=NO; [self beginPlayback]; return;
    }
    if ((isVideo && !OVKExperimentalVideo()) || (!isVideo && !OVKExperimentalMusic())) { [self failPlayback:OVKL(@"Включите этот раздел в Настройки → Экспериментальное.")]; return; }

    if (isVideo) { self.videoURLs=[OVKVideoURLs(OVKDictionary(self.item[@"object"])) mutableCopy]; NSString *url=OVKString(self.item[@"url"]); if (url.length && ![self.videoURLs containsObject:url]) [self.videoURLs addObject:url]; self.candidateIndex=0; }
    if (!isVideo && OVKString(self.item[@"url"]).length) { [self loadURL:self.item[@"url"]]; return; }
    NSDictionary *object = OVKDictionary(self.item[@"object"]); NSString *owner = OVKString(object[@"owner_id"]), *identifier = OVKString(object[@"id"]);
    if (isVideo && ( !owner.length || !identifier.length || [OVKAPI shared].demo) && self.videoURLs.count) { [self loadNextVideo]; return; }
    if (!owner.length || !identifier.length || [OVKAPI shared].demo) { [self unavailable:OVKL(@"Сервер не предоставил прямую ссылку на запись.")]; return; }
    self.resolving = YES; BOOL video = [self.item[@"type"] isEqualToString:@"video"];
    NSDictionary *params = @{(video ? @"videos" : @"audios"):[NSString stringWithFormat:@"%@_%@",owner,identifier]};
    __weak OVKPlaybackController *weakSelf = self;
    [[OVKAPI shared] call:video ? @"video.get" : @"audio.getById" parameters:params completion:^(id result,NSError *error) {
        OVKPlaybackController *page = weakSelf; if (!page || page.stopped) return; page.resolving = NO;
        NSArray *items = [result isKindOfClass:[NSArray class]] ? result : OVKArray(OVKDictionary(result)[@"items"]);
        NSDictionary *media = items.count ? OVKDictionary(items[0]) : @{};
        NSString *url = video ? OVKDirectVideoURL(media) : OVKMediaURL(OVKString(media[@"url"]));
        if (video) {
            for (NSString *candidate in OVKVideoURLs(media)) if (![page.videoURLs containsObject:candidate]) [page.videoURLs addObject:candidate];
            if (media.count) { NSMutableDictionary *updated=[page.item mutableCopy]; updated[@"object"]=media; page.item=updated; }
            if (page.videoURLs.count) { [page loadNextVideo]; return; }
        }
        if (error || !url.length) { [page unavailable:error.localizedDescription ?: OVKL(@"Эта запись доступна только через веб-плеер или сервер не выдаёт файл.")]; return; }
        NSMutableDictionary *item = [page.item mutableCopy]; item[@"object"] = media; item[@"url"] = url; page.item = item; [page loadURL:url];
    }];
}
- (void)loadURL:(NSString *)url {
    NSURL *address = [NSURL URLWithString:url];
    NSString *extension = address.pathExtension.lowercaseString ?: @"";
    if ([@[@"m3u8",@"mpd",@"ogg",@"opus",@"webm"] containsObject:extension]) { [self unavailable:OVKL(@"Этот формат не поддерживается встроенным проигрывателем старой iOS.")]; return; }
    self.status.text = OVKL(@"Загрузка записи перед воспроизведением…"); self.progress.progress = 0;
    __weak OVKPlaybackController *weakSelf = self;
    self.task = [OVKMedia download:url limit:256ULL*1024*1024 progress:^(float value) {
        weakSelf.progress.progress = value < 0 ? 0 : value; weakSelf.status.text = value < 0 ? OVKL(@"Загрузка записи…") : [NSString stringWithFormat:OVKL(@"Загрузка записи… %d%%"),(int)(value*100)];
    } completion:^(NSURL *file,NSError *error) {
        OVKPlaybackController *page = weakSelf;
        if (!page || page.stopped) { if (file) [[NSFileManager defaultManager] removeItemAtURL:file error:NULL]; return; }
        page.task = nil; page.progress.hidden = YES; [page.spinner stopAnimating];
        if (error) { if (error.code != NSURLErrorCancelled) { if ([page.item[@"type"] isEqualToString:@"video"]) [page rejectVideo:error.localizedDescription]; else page.status.text=error.localizedDescription; } return; }
        NSFileHandle *input=[NSFileHandle fileHandleForReadingAtPath:file.path]; NSData *header=[input readDataOfLength:64]; [input closeFile];
        const char *detected=OVKMediaContainer(header.bytes,header.length);
        NSString *container=detected ? [NSString stringWithUTF8String:detected] : @"unknown";
        [page.diagnostics addObject:[NSString stringWithFormat:@"Контейнер файла: %@",container]];
        if ([@[@"ogg",@"flac",@"webm"] containsObject:container]) { [[NSFileManager defaultManager] removeItemAtURL:file error:NULL]; [page failPlayback:[NSString stringWithFormat:OVKL(@"Сервер прислал %@. Штатный декодер iOS 6 этот формат не поддерживает."),container]]; return; }
        NSString *suffix=detected ? container : ([@[@"mp3",@"m4a",@"mp4",@"aac",@"wav",@"caf",@"aif",@"aiff",@"mov"] containsObject:extension] ? extension : @"bin");
        if ([container isEqualToString:@"mp4"] && ![page.item[@"type"] isEqualToString:@"video"]) suffix=@"m4a";
        NSURL *named = [NSURL fileURLWithPath:[file.path stringByAppendingPathExtension:suffix]];
        if (![[NSFileManager defaultManager] moveItemAtURL:file toURL:named error:&error]) { [[NSFileManager defaultManager] removeItemAtURL:file error:NULL]; page.status.text = error.localizedDescription; return; }
        [page clearPlaybackFile];
        page.localFile = named; page.temporaryFile=YES;
        if (![page.item[@"type"] isEqualToString:@"video"]) [[NSFileManager defaultManager] setAttributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:named.path error:NULL]; [page beginPlayback];
    }];
}
- (void)beginPlayback {
    self.status.hidden=NO; self.status.text = OVKL(@"Подготовка записи…"); [self.spinner startAnimating];
    NSUInteger generation=++self.playbackGeneration;
    self.prepareDeadline=[NSTimer timerWithTimeInterval:25 target:self selector:@selector(prepareTimedOut) userInfo:nil repeats:NO]; [[NSRunLoop mainRunLoop] addTimer:self.prepareDeadline forMode:NSRunLoopCommonModes];
    if (![self.item[@"type"] isEqualToString:@"video"]) { [self prepareLocalAudio]; return; }
    // Inspect locally downloaded data asynchronously. No AVAudioPlayer file open/prepare on the UI thread.
    self.asset=[AVURLAsset URLAssetWithURL:self.localFile options:nil];
    __weak OVKPlaybackController *weakSelf=self;
    [self.asset loadValuesAsynchronouslyForKeys:@[@"playable",@"tracks",@"duration"] completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            OVKPlaybackController *page=weakSelf; if (!page || page.stopped || generation!=page.playbackGeneration) return;
            [page assetPrepared];
        });
    }];
}
- (void)prepareLocalAudio {
    self.musicPrepared=NO;
    self.activationPending=YES; NSString *owner=[[NSProcessInfo processInfo] globallyUniqueString]; self.sessionOwner=owner;
    NSUInteger generation=self.playbackGeneration; __weak OVKPlaybackController *weakSelf=self;
    OVKActivateSession(owner, ^void(NSError *error) {
        OVKPlaybackController *page=weakSelf;
        if (!page || page.stopped || generation!=page.playbackGeneration || ![page.sessionOwner isEqualToString:owner]) { OVKDeactivateSession(owner); return; }
        if (error) { [page failPlayback:error.localizedDescription]; return; }
        OVKLocalAudio *audio=[[OVKLocalAudio alloc] init]; page.music=audio;
        [audio prepareURL:page.localFile completion:^void(NSError *failure) {
            OVKPlaybackController *ready=weakSelf;
            if (!ready || ready.stopped || generation!=ready.playbackGeneration || ready.music!=audio) { [audio stop]; return; }
            ready.activationPending=NO;
            if (failure) { [ready failPlayback:failure.localizedDescription]; return; }
            ready.musicPrepared=YES; ready.musicDuration=audio.duration; ready.musicPosition=0; ready.lastStartupSecond=-1;
            __weak OVKLocalAudio *weakAudio=audio;
            audio.changed=^void(NSError *decodeError) { OVKPlaybackController *screen=weakSelf; if (!screen || screen.music!=weakAudio || screen.stopped) return; if (decodeError) [screen failPlayback:decodeError.localizedDescription]; else [screen updateMusic]; };
            [ready buildMusicPlayer];
        }];
    });
}
- (void)playReadyAudio {
    if (!self.music || self.stopped || self.activationPending) return;
    self.activationPending=YES; self.wantsPlayback=YES;
    NSUInteger generation=self.playbackGeneration; __weak OVKPlaybackController *weakSelf=self;
    OVKLocalAudio *audio=self.music;
    [audio playWithCompletion:^void(NSError *error) {
        OVKPlaybackController *page=weakSelf; if (!page || page.stopped || generation!=page.playbackGeneration || page.music!=audio) return;
        page.activationPending=NO;
        if (error) { [page failPlayback:error.localizedDescription]; return; }
        if (!page.wantsPlayback || (!page.music && [UIApplication sharedApplication].applicationState!=UIApplicationStateActive)) { [audio pause]; return; }
        page.started=YES; [page.prepareDeadline invalidate]; page.prepareDeadline=nil; [page.spinner stopAnimating]; page.status.hidden=YES;
        page.navigationItem.rightBarButtonItems=@[[[UIBarButtonItem alloc] initWithTitle:OVKL(@"Сведения") style:UIBarButtonItemStylePlain target:page action:@selector(showVideoInfo)]];
        [[page.navigationItem.rightBarButtonItems objectAtIndex:0] setBackgroundImage:[[UIImage imageNamed:@"MusicButton"] resizableImageWithCapInsets:UIEdgeInsetsMake(5,7,5,7)] forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
        [page endAudioTask]; [page.diagnostics addObject:@"AVAudioPlayer: play выполнен"]; [page updateMusic];
    }];
}
- (void)assetPrepared {
    NSError *error=nil; BOOL video=[self.item[@"type"] isEqualToString:@"video"];
    AVKeyValueStatus playable=[self.asset statusOfValueForKey:@"playable" error:&error];
    AVKeyValueStatus tracks=[self.asset statusOfValueForKey:@"tracks" error:&error];
    if (!video && (playable!=AVKeyValueStatusLoaded || !self.asset.playable || tracks!=AVKeyValueStatusLoaded)) { [self failPlayback:error.localizedDescription ?: OVKL(@"iOS не смогла прочитать аудио")]; return; }
    if (video) {
        if (tracks==AVKeyValueStatusLoaded) {
            NSUInteger audio=[self.asset tracksWithMediaType:AVMediaTypeAudio].count;
            [self.diagnostics addObject:[NSString stringWithFormat:@"Вариант %lu: видео %lu, аудио %lu (предварительно)",(unsigned long)self.candidateIndex,(unsigned long)[self.asset tracksWithMediaType:AVMediaTypeVideo].count,(unsigned long)audio]];
            if (!audio && !self.mergingSound && OVKVideoAudioURL(OVKDictionary(self.item[@"object"])).length) { [self fetchVideoSound]; return; }
        } else [self.diagnostics addObject:@"Предварительная проверка недоступна; пробуем системный плеер"];
        // AVURLAsset's track inspection is diagnostic, not a veto for the movie player.
        self.movie=[[MPMoviePlayerController alloc] initWithContentURL:self.localFile];
        if (!self.movie) { [self rejectVideo:OVKL(@"Не удалось создать проигрыватель")]; return; }
        self.movie.movieSourceType=MPMovieSourceTypeFile; self.movie.shouldAutoplay=NO;
        self.movie.controlStyle=MPMovieControlStyleFullscreen; self.movie.scalingMode=MPMovieScalingModeAspectFit;
        self.movie.view.frame=self.view.bounds; self.movie.view.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; [self.view addSubview:self.movie.view];
        [self.movie prepareToPlay]; [self movieReady:nil];
    }
}
- (void)startPreparedPlayback {
    if (self.stopped || self.activationPending || self.started || (self.music && !self.musicPrepared)) return;
    [self beginAudioTask]; [self.diagnostics addObject:@"Запрос запуска готового плеера"];
    if (!self.music && [UIApplication sharedApplication].applicationState!=UIApplicationStateActive) { self.wantsPlayback=YES; return; }
    if (self.music && self.sessionOwner) { [self playReadyAudio]; return; }
    self.activationPending=YES; self.wantsPlayback=YES;
    NSString *owner=[[NSProcessInfo processInfo] globallyUniqueString]; self.sessionOwner=owner;
    NSUInteger generation=self.playbackGeneration; __weak OVKPlaybackController *weakSelf=self;
    OVKActivateSession(owner, ^void(NSError *error) {
        OVKPlaybackController *page=weakSelf;
        if (!page || page.stopped || generation!=page.playbackGeneration || ![page.sessionOwner isEqualToString:owner]) { OVKDeactivateSession(owner); return; }
        page.activationPending=NO; [page.diagnostics addObject:error ? OVKL(@"Ошибка активации аудиосессии") : @"Аудиосессия включена"];
        if (error) { [page failPlayback:error.localizedDescription]; return; }
        if (!page.wantsPlayback || (!page.music && [UIApplication sharedApplication].applicationState!=UIApplicationStateActive)) { OVKDeactivateSession(owner); page.sessionOwner=nil; return; }
        if (page.music) { [page playReadyAudio]; return; }
        page.started=YES; [page.prepareDeadline invalidate]; page.prepareDeadline=nil; [page.spinner stopAnimating]; page.status.hidden=YES; page.navigationItem.rightBarButtonItems=@[[[UIBarButtonItem alloc] initWithTitle:OVKL(@"Сведения") style:UIBarButtonItemStylePlain target:page action:@selector(showVideoInfo)]];
        [page.diagnostics addObject:@"Команда play"];
        [page.movie play];
    });
}
- (void)pauseOutputAndReleaseSession {
    NSString *owner=self.sessionOwner; self.sessionOwner=nil; self.activationPending=NO;
    if (self.music) [self.music pauseWithCompletion:^{ OVKDeactivateSession(owner); }];
    else { [self.movie pause]; OVKDeactivateSession(owner); }
}
- (void)pauseForSystem {
    BOOL playing=self.activationPending || (self.music ? self.music.playing : self.movie.playbackState==MPMoviePlaybackStatePlaying);
    self.wantsPlayback=playing || (!self.started && self.wantsPlayback); self.started=NO;
    [self pauseOutputAndReleaseSession];
}
- (void)applicationPausing:(NSNotification *)note { if (!self.stopped && self.movie) [self pauseForSystem]; }
- (void)applicationResuming:(NSNotification *)note { if (!self.stopped && self.wantsPlayback) { if (self.music) [self musicReady]; else [self movieReady:nil]; } }
- (void)audioInterrupted:(NSNotification *)note {
    if (![NSThread isMainThread]) { __weak OVKPlaybackController *weakSelf=self; dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf audioInterrupted:note]; }); return; }
    if ([note.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue]==AVAudioSessionInterruptionTypeBegan) { [self pauseForSystem]; return; }
    if ([note.userInfo[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue] & AVAudioSessionInterruptionOptionShouldResume) [self applicationResuming:nil];
    else self.wantsPlayback=NO;
}
- (void)fetchVideoSound {
    [self.prepareDeadline invalidate]; self.prepareDeadline=nil;
    self.status.hidden=NO; self.status.text=OVKL(@"Загрузка звуковой дорожки…"); self.progress.hidden=NO;
    NSString *url=OVKVideoAudioURL(OVKDictionary(self.item[@"object"])); NSUInteger generation=self.playbackGeneration;
    __weak OVKPlaybackController *weakSelf=self;
    self.task=[OVKMedia download:url limit:64ULL*1024*1024 progress:^(float value) { weakSelf.progress.progress=MAX(0,value); } completion:^(NSURL *file,NSError *error) {
        OVKPlaybackController *page=weakSelf; if (!page || page.stopped || generation!=page.playbackGeneration) { if (file) [[NSFileManager defaultManager] removeItemAtURL:file error:NULL]; return; }
        page.task=nil; page.progress.hidden=YES;
        if (error) { [page rejectVideo:error.localizedDescription]; return; }
        NSURL *soundURL=[NSURL URLWithString:url]; NSString *extension=soundURL.pathExtension.lowercaseString;
        if (![@[@"m4a",@"mp3",@"mp4",@"aac",@"wav",@"mov"] containsObject:extension ?: @""]) extension=@"m4a";
        NSURL *named=[NSURL fileURLWithPath:[file.path stringByAppendingPathExtension:extension]];
        NSError *renameError=nil; if (![[NSFileManager defaultManager] moveItemAtURL:file toURL:named error:&renameError]) { [[NSFileManager defaultManager] removeItemAtURL:file error:NULL]; [page rejectVideo:renameError.localizedDescription]; return; }
        page.soundFile=named; page.soundAsset=[AVURLAsset URLAssetWithURL:named options:nil];
        page.prepareDeadline=[NSTimer timerWithTimeInterval:40 target:page selector:@selector(prepareTimedOut) userInfo:nil repeats:NO]; [[NSRunLoop mainRunLoop] addTimer:page.prepareDeadline forMode:NSRunLoopCommonModes];
        [page.soundAsset loadValuesAsynchronouslyForKeys:@[@"tracks",@"duration"] completionHandler:^{ dispatch_async(dispatch_get_main_queue(), ^{
            OVKPlaybackController *owner=weakSelf; if (!owner || owner.stopped || generation!=owner.playbackGeneration) return;
            NSError *failure=nil;
            if ([owner.soundAsset statusOfValueForKey:@"tracks" error:&failure]!=AVKeyValueStatusLoaded || [owner.soundAsset statusOfValueForKey:@"duration" error:&failure]!=AVKeyValueStatusLoaded) { [owner rejectVideo:failure.localizedDescription ?: OVKL(@"Не удалось открыть звуковую дорожку")]; return; }
            NSArray *audio=[owner.soundAsset tracksWithMediaType:AVMediaTypeAudio], *video=[owner.asset tracksWithMediaType:AVMediaTypeVideo];
            if (!audio.count || !video.count) { [owner rejectVideo:OVKL(@"Отдельная звуковая дорожка не читается на этой iOS")]; return; }
            AVMutableComposition *composition=[AVMutableComposition composition];
            AVMutableCompositionTrack *v=[composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
            AVMutableCompositionTrack *a=[composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
            AVAssetTrack *videoTrack=video[0]; CMTime duration=owner.asset.duration; CMTime audioDuration=owner.soundAsset.duration; if (!CMTIME_IS_NUMERIC(duration) || !CMTIME_IS_NUMERIC(audioDuration) || CMTimeCompare(duration,kCMTimeZero)<=0 || CMTimeCompare(audioDuration,kCMTimeZero)<=0) { [owner rejectVideo:OVKL(@"Не удалось определить длительность дорожек")]; return; }
            if (![v insertTimeRange:CMTimeRangeMake(kCMTimeZero,duration) ofTrack:videoTrack atTime:kCMTimeZero error:&failure] || ![a insertTimeRange:CMTimeRangeMake(kCMTimeZero,CMTimeMinimum(duration,audioDuration)) ofTrack:audio[0] atTime:kCMTimeZero error:&failure]) { [owner rejectVideo:failure.localizedDescription ?: OVKL(@"Не удалось соединить дорожки")]; return; }
            v.preferredTransform=videoTrack.preferredTransform;
            owner.exporter=[[AVAssetExportSession alloc] initWithAsset:composition presetName:AVAssetExportPresetPassthrough];
            if (!owner.exporter || ![owner.exporter.supportedFileTypes containsObject:AVFileTypeQuickTimeMovie]) { [owner rejectVideo:OVKL(@"iOS не поддерживает сборку этих дорожек")]; return; }
            NSURL *joined=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"ovk-joined-%@.mov",[[NSProcessInfo processInfo] globallyUniqueString]]]];
            owner.exporter.outputURL=joined; owner.exporter.outputFileType=AVFileTypeQuickTimeMovie; owner.status.text=OVKL(@"Соединяем видео и звук…");
            AVAssetExportSession *session=owner.exporter;
            [session exportAsynchronouslyWithCompletionHandler:^{ dispatch_async(dispatch_get_main_queue(), ^{
                OVKPlaybackController *result=weakSelf; if (!result || result.stopped || generation!=result.playbackGeneration) { [[NSFileManager defaultManager] removeItemAtURL:joined error:NULL]; return; }
                if (session.status!=AVAssetExportSessionStatusCompleted) { [[NSFileManager defaultManager] removeItemAtURL:joined error:NULL]; [result rejectVideo:session.error.localizedDescription ?: OVKL(@"Не удалось соединить дорожки")]; return; }
                result.exporter=nil; [result.prepareDeadline invalidate]; result.prepareDeadline=nil; [result.asset cancelLoading]; result.asset=nil;
                [result clearPlaybackFile]; result.localFile=joined; result.temporaryFile=YES;
                [[NSFileManager defaultManager] removeItemAtURL:result.soundFile error:NULL]; result.soundFile=nil; result.soundAsset=nil; result.mergingSound=YES; [result beginPlayback];
            }); }];
        }); }];
    }];
}
- (void)loadNextVideo {
    self.mergingSound=NO;
    if (self.stopped) return;
    if (self.candidateIndex>=self.videoURLs.count) { [self failPlayback:OVKL(@"Не удалось открыть вариант видео со звуком. Нажмите «Сведения», чтобы посмотреть результат проверки.")]; return; }
    NSString *url=self.videoURLs[self.candidateIndex++]; [self loadURL:url];
}
- (void)rejectVideo:(NSString *)reason {
    [self.diagnostics addObject:reason ?: OVKL(@"Ошибка варианта видео")]; [self releasePlayer];
    [self clearPlaybackFile];
    [self loadNextVideo];
}
- (void)buildMusicPlayer {
    self.musicView=[[UIView alloc] initWithFrame:self.view.bounds]; self.musicView.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; self.musicView.backgroundColor=[UIColor blackColor]; [self.view addSubview:self.musicView];
    CGFloat width=self.view.bounds.size.width, height=self.view.bounds.size.height;
    CGFloat controls=140, art=MIN(width,MAX(80,height-controls));
    OVKRemoteImageView *cover=[[OVKRemoteImageView alloc] initWithImage:[UIImage imageNamed:@"MusicCover"]]; cover.frame=CGRectMake((width-art)/2,0,art,art); cover.contentMode=UIViewContentModeScaleAspectFit; cover.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin; [self.musicView addSubview:cover];
    NSDictionary *object=OVKDictionary(self.item[@"object"]); NSDictionary *album=OVKDictionary(object[@"album"]);
    CGFloat titleWidth=MAX(100,MIN(220,width-170)); UIView *heading=[[UIView alloc] initWithFrame:CGRectMake(0,0,titleWidth,40)]; heading.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    NSArray *lines=@[OVKString(object[@"artist"]),OVKString(object[@"title"]).length ? OVKString(object[@"title"]) : self.title,OVKString(album[@"title"])];
    for (NSUInteger i=0;i<3;i++) { UILabel *line=[[UILabel alloc] initWithFrame:CGRectMake(0,i*13,titleWidth,13)]; line.autoresizingMask=UIViewAutoresizingFlexibleWidth; line.text=lines[i]; line.font=i==1 ? [UIFont boldSystemFontOfSize:12] : [UIFont systemFontOfSize:11]; line.textColor=i==1 ? [UIColor whiteColor] : [UIColor lightGrayColor]; line.backgroundColor=[UIColor clearColor]; line.textAlignment=NSTextAlignmentCenter; [heading addSubview:line]; }
    self.navigationItem.titleView=heading;
     NSString *coverURL=OVKPhotoSource(OVKDictionary(album[@"thumb"])); if (coverURL.length) [cover load:coverURL];
    UIView *panel=[[UIImageView alloc] initWithImage:[[UIImage imageNamed:@"MusicPanel"] resizableImageWithCapInsets:UIEdgeInsetsMake(3,3,3,3)]]; panel.userInteractionEnabled=YES; panel.frame=CGRectMake(0,height-controls,width,controls); panel.autoresizingMask=UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleWidth; [self.musicView addSubview:panel];
    self.musicSeek=[[UISlider alloc] initWithFrame:CGRectMake(18,8,width-36,24)]; self.musicSeek.autoresizingMask=UIViewAutoresizingFlexibleWidth; self.musicSeek.continuous=NO; [self.musicSeek addTarget:self action:@selector(seekMusic) forControlEvents:UIControlEventValueChanged]; [panel addSubview:self.musicSeek];
    self.musicTime=[[UILabel alloc] initWithFrame:CGRectMake(20,33,width-40,18)]; self.musicTime.autoresizingMask=UIViewAutoresizingFlexibleWidth; self.musicTime.textAlignment=NSTextAlignmentCenter; self.musicTime.textColor=[UIColor lightGrayColor]; self.musicTime.backgroundColor=[UIColor clearColor]; self.musicTime.font=[UIFont systemFontOfSize:11]; [panel addSubview:self.musicTime];
    for (NSUInteger i=0;i<3;i++) { UIButton *button=[UIButton buttonWithType:UIButtonTypeCustom]; button.frame=CGRectMake(i*width/3,50,width/3,48); button.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin; [button setImage:[UIImage imageNamed:@[@"PreviousTrack",@"PauseTrack",@"NextTrack"][i]] forState:UIControlStateNormal]; button.accessibilityLabel=@[OVKL(@"Предыдущий трек"),OVKL(@"Пауза"),OVKL(@"Следующий трек")][i]; if (i==1) { self.musicPlay=button; [button addTarget:self action:@selector(toggleMusic) forControlEvents:UIControlEventTouchUpInside]; } else { button.tag=i==0 ? -1 : 1; button.enabled=i==0 ? self.queueIndex>0 : self.queueIndex+1<self.queue.count; button.alpha=button.enabled ? 1 : .3; [button addTarget:self action:@selector(changeTrack:) forControlEvents:UIControlEventTouchUpInside]; } [panel addSubview:button]; }
    MPVolumeView *volume=[[MPVolumeView alloc] initWithFrame:CGRectMake(25,107,width-50,28)]; volume.autoresizingMask=UIViewAutoresizingFlexibleWidth; volume.showsRouteButton=YES; [panel addSubview:volume];
    self.musicTimer=[NSTimer timerWithTimeInterval:.3 target:self selector:@selector(refreshLocalAudio) userInfo:nil repeats:YES]; [[NSRunLoop mainRunLoop] addTimer:self.musicTimer forMode:NSRunLoopCommonModes];
    self.navigationItem.hidesBackButton=YES;
    UIBarButtonItem *back=[[UIBarButtonItem alloc] initWithTitle:OVKL(@"Музыка") style:UIBarButtonItemStylePlain target:self action:@selector(backToMusic)];
    [back setBackgroundImage:[[UIImage imageNamed:@"MusicButton"] resizableImageWithCapInsets:UIEdgeInsetsMake(5,7,5,7)] forState:UIControlStateNormal barMetrics:UIBarMetricsDefault]; self.navigationItem.leftBarButtonItem=back;
    [self musicReady];
}
- (void)refreshLocalAudio { [self.music refresh]; }
- (void)musicReady { if (!self.stopped && self.music && self.musicPrepared && !self.started) [self startPreparedPlayback]; }
- (void)toggleMusic {
    if (self.music.playing || self.activationPending) { self.wantsPlayback=NO; self.started=NO; [self pauseOutputAndReleaseSession]; }
    else { if (self.musicDuration>0 && self.musicPosition>=self.musicDuration-.05) [self.music seek:0]; self.started=NO; [self startPreparedPlayback]; }
    [self updateMusic];
}
- (void)seekMusic { self.nowPlayingUpdated=0; double duration=self.musicDuration; if (isfinite(duration) && duration>0) [self.music seek:duration*self.musicSeek.value]; }
- (void)updateMusic {
    if (self.music.completed && self.started) {
        self.started=NO;
        if (self.queueIndex+1<self.queue.count) { UIButton *next=[UIButton buttonWithType:UIButtonTypeCustom]; next.tag=1; [self changeTrack:next]; return; }
        self.wantsPlayback=NO; [self pauseOutputAndReleaseSession];
    }
    self.musicPosition=self.music.currentTime; self.musicDuration=self.music.duration; double now=self.musicPosition, total=self.musicDuration; if (!isfinite(now)) now=0; if (!isfinite(total) || total<=0) total=0;
    if (!self.musicSeek.tracking) self.musicSeek.value=total>0 ? now/total : 0;
    self.musicTime.text=[NSString stringWithFormat:@"%ld:%02ld  /  %ld:%02ld",(long)now/60,(long)now%60,(long)llround(total)/60,(long)llround(total)%60];
    [self.musicPlay setImage:[UIImage imageNamed:self.music.playing ? @"PauseTrack" : @"PlayTrack"] forState:UIControlStateNormal]; self.musicPlay.accessibilityLabel=self.music.playing ? OVKL(@"Пауза") : OVKL(@"Воспроизвести"); [self updateNowPlaying];
}
- (void)changeTrack:(UIButton *)sender {
    NSInteger index=(NSInteger)self.queueIndex+sender.tag; if (index<0 || index>=(NSInteger)self.queue.count) return;
    [self releasePlayer]; [self clearPlaybackFile];
    self.queueIndex=index; self.item=self.queue[index]; self.title=OVKString(self.item[@"title"]); [self resolveAndLoad];
}
- (void)movieReady:(NSNotification *)note {
    if (![NSThread isMainThread]) { __weak OVKPlaybackController *weakSelf=self; dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf movieReady:note]; }); return; }
    if (self.stopped || !self.movie || (note && note.object!=self.movie) || self.started) return;
    if (!self.movie.isPreparedToPlay && !(self.movie.loadState & MPMovieLoadStatePlayable)) return;
    [self startPreparedPlayback];
}
- (void)prepareTimedOut { [self failPlayback:OVKL(@"Проигрыватель не смог подготовить запись за 25 секунд. Нажмите обновление, чтобы повторить.")]; }
- (void)releasePlayer {
    ++self.playbackGeneration; self.nowPlayingUpdated=0; [self endAudioTask]; [self.prepareDeadline invalidate];
    [self.musicTimer invalidate]; self.musicTimer=nil;
    OVKLocalAudio *audio=self.music; NSString *owner=self.sessionOwner;
    [audio stopWithCompletion:^{ OVKDeactivateSession(owner); }]; self.music=nil; self.musicPrepared=NO; [self.musicView removeFromSuperview]; self.musicView=nil; self.prepareDeadline=nil;
    [self.exporter cancelExport]; self.exporter=nil; [self.soundAsset cancelLoading]; self.soundAsset=nil;
    if (self.soundFile) [[NSFileManager defaultManager] removeItemAtURL:self.soundFile error:NULL]; self.soundFile=nil;
    [self.asset cancelLoading]; self.asset=nil; self.started=NO;
    MPMoviePlayerController *movie=self.movie; self.movie=nil; [movie stop]; [movie.view removeFromSuperview];
    if (!audio) OVKDeactivateSession(self.sessionOwner); self.sessionOwner=nil; self.activationPending=NO; self.wantsPlayback=NO;
    if (OVKCurrentMusic==self) { MPNowPlayingInfoCenter *center=[MPNowPlayingInfoCenter defaultCenter]; center.nowPlayingInfo=nil; }
}
- (void)failPlayback:(NSString *)message {
    [self releasePlayer]; [self.spinner stopAnimating]; self.progress.hidden=YES; self.status.hidden=NO; self.status.text=message;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(resolveAndLoad)];
    if ([self.item[@"type"] isEqualToString:@"video"]) self.navigationItem.rightBarButtonItems=@[self.navigationItem.rightBarButtonItem,[[UIBarButtonItem alloc] initWithTitle:OVKL(@"Сведения") style:UIBarButtonItemStylePlain target:self action:@selector(showVideoInfo)]];
}
- (void)showVideoInfo {
    NSArray *keys=[OVKDictionary(OVKDictionary(self.item[@"object"])[@"files"]) allKeys];
    if ([self.asset statusOfValueForKey:@"tracks" error:NULL]==AVKeyValueStatusLoaded) {
        for (AVAssetTrack *track in self.asset.tracks) {
            NSMutableArray *formats=[NSMutableArray array];
            for (id description in track.formatDescriptions) {
                FourCharCode code=CMFormatDescriptionGetMediaSubType((__bridge CMFormatDescriptionRef)description);
                char text[5]={(char)(code>>24),(char)(code>>16),(char)(code>>8),(char)code,0};
                NSString *format=[NSString stringWithCString:text encoding:NSASCIIStringEncoding]; if (format) [formats addObject:format];
            }
            NSString *entry=[NSString stringWithFormat:@"%@: %@",track.mediaType,[formats componentsJoinedByString:@", "]]; if (![self.diagnostics containsObject:entry]) [self.diagnostics addObject:entry];
        }
    }
    if (self.music.codecDescription.length && ![self.diagnostics containsObject:self.music.codecDescription]) [self.diagnostics addObject:self.music.codecDescription];
    AVAudioSession *audioSession=[AVAudioSession sharedInstance];
    AVAudioSessionRouteDescription *route=audioSession.currentRoute;
    NSMutableArray *ports=[NSMutableArray array]; for (AVAudioSessionPortDescription *port in route.outputs) [ports addObject:port.portType ?: @"?"];
    NSString *state=self.music ? [NSString stringWithFormat:@"AVAudioPlayer playing=%d, time=%.2f/%.2f",self.music.playing,self.musicPosition,self.musicDuration] : [NSString stringWithFormat:@"Movie state=%ld, load=%lu",(long)self.movie.playbackState,(unsigned long)self.movie.loadState];
    OVKAlert(OVKL(@"Проверка воспроизведения"),[NSString stringWithFormat:@"%@\nВыход: %@\nfiles: %@\n%@",state,[ports componentsJoinedByString:@", "],[keys componentsJoinedByString:@", "],[self.diagnostics componentsJoinedByString:@"\n"]]);
}
- (void)movieEnded:(NSNotification *)note {
    if (![NSThread isMainThread]) { __weak OVKPlaybackController *weakSelf=self; dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf movieEnded:note]; }); return; }
    if (note.object!=self.movie || self.stopped) return;
    NSInteger reason=[note.userInfo[MPMoviePlayerPlaybackDidFinishReasonUserInfoKey] integerValue];
    if (reason==MPMovieFinishReasonUserExited) { [self.navigationController popViewControllerAnimated:YES]; return; }
    if (reason==MPMovieFinishReasonPlaybackError) {
        NSError *error=note.userInfo[@"error"]; NSString *message=error.localizedDescription ?: OVKL(@"iOS не смогла воспроизвести этот вариант записи.");
        if (self.candidateIndex<self.videoURLs.count) [self rejectVideo:message]; else [self failPlayback:message];
    }
}
- (void)stop { self.stopped=YES; [self.task cancel]; self.task=nil; [self releasePlayer]; [self.spinner stopAnimating]; }
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; [_task cancel]; [_prepareDeadline invalidate]; [_asset cancelLoading]; [_soundAsset cancelLoading]; [_exporter cancelExport]; if (_soundFile) [[NSFileManager defaultManager] removeItemAtURL:_soundFile error:NULL]; [_musicTimer invalidate]; NSString *owner=_sessionOwner; if (_music) [_music stopWithCompletion:^{ OVKDeactivateSession(owner); }]; else OVKDeactivateSession(owner); [_movie stop]; if (_temporaryFile && _localFile) [[NSFileManager defaultManager] removeItemAtURL:_localFile error:NULL]; }

@end
static void OVKShowBundledVideo(NSString *name,UIViewController *controller) {
    NSString *path=[[NSBundle mainBundle] pathForResource:name ofType:@"mp4"]; if (!path || !controller.navigationController) return;
    if (OVKCurrentMusic) { OVKCurrentMusic.wantsPlayback=NO; OVKCurrentMusic.started=NO; [OVKCurrentMusic pauseOutputAndReleaseSession]; }
    OVKPlaybackController *player=[[OVKPlaybackController alloc] init]; player.item=@{@"type":@"video",@"title":OVKL(@"Директор дабстепа"),@"local_path":path,@"object":@{}}; [controller.navigationController pushViewController:player animated:YES];
}
static void OVKShowCurrentMusic(UIViewController *controller) {
    if (!OVKCurrentMusic || OVKCurrentMusic.stopped) { OVKAlert(OVKL(@"Музыка"),OVKL(@"Выберите аудиозапись для воспроизведения.")); return; }
    UINavigationController *nav=controller.navigationController; if (!nav) return;
    UINavigationController *old=OVKCurrentMusic.navigationController;
    if (old==nav && [nav.viewControllers containsObject:OVKCurrentMusic]) { [nav popToViewController:OVKCurrentMusic animated:YES]; return; }
    if (old) { NSMutableArray *stack=[old.viewControllers mutableCopy]; [stack removeObject:OVKCurrentMusic]; [old setViewControllers:stack animated:NO]; }
    [nav pushViewController:OVKCurrentMusic animated:YES];
}
static void OVKRouteRemoteControl(UIEvent *event) {
    OVKPlaybackController *player=OVKCurrentMusic; if (!player || player.stopped || event.type!=UIEventTypeRemoteControl) return;
    switch (event.subtype) {
        case UIEventSubtypeRemoteControlTogglePlayPause: [player toggleMusic]; break;
        case UIEventSubtypeRemoteControlPlay: if (!player.music.playing && !player.activationPending) [player toggleMusic]; break;
        case UIEventSubtypeRemoteControlPause: case UIEventSubtypeRemoteControlStop: if (player.music.playing || player.activationPending) [player toggleMusic]; break;
        case UIEventSubtypeRemoteControlNextTrack: case UIEventSubtypeRemoteControlPreviousTrack: { UIButton *command=[UIButton buttonWithType:UIButtonTypeCustom]; command.tag=event.subtype==UIEventSubtypeRemoteControlNextTrack ? 1 : -1; [player changeTrack:command]; break; }
        default: break;
    }
}
@interface OVKAttachmentsController ()
@property (strong, nonatomic) NSArray *attachments;
@property (strong, nonatomic) NSArray *allAttachments;
@end
@implementation OVKAttachmentsController
- (id)initWithAttachments:(NSArray *)attachments title:(NSString *)title { self = [super initWithStyle:UITableViewStylePlain]; if (self) { [self replaceAttachments:attachments]; self.title = title; } return self; }
- (void)replaceAttachments:(NSArray *)attachments {
    self.allAttachments=[attachments copy];
    NSMutableArray *visible=[NSMutableArray array];
    for (NSDictionary *item in attachments) {
        NSString *type=OVKString(item[@"type"]);
        if ([type isEqualToString:@"video"] && !OVKExperimentalVideo()) continue;
        if ([type isEqualToString:@"audio"] && !OVKString(item[@"local_path"]).length && !OVKExperimentalMusic()) continue;
        [visible addObject:item];
    } self.attachments=visible; if (self.isViewLoaded) [self.tableView reloadData];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self attachmentThemeChanged:nil]; }
- (void)attachmentThemeChanged:(NSNotification *)note { OVKThemeTable(self.tableView); [self.tableView reloadData]; }
- (void)experimentalAttachmentsChanged:(NSNotification *)note { [self replaceAttachments:self.allAttachments ?: @[]]; }
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)viewDidLoad { [super viewDidLoad]; [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(attachmentThemeChanged:) name:@"OVKThemeChanged" object:nil]; [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(experimentalAttachmentsChanged:) name:@"OVKExperimentalChanged" object:nil]; self.tableView.rowHeight = 70; self.tableView.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"Linen"]]; }
- (BOOL)isPhotoGrid { if (!self.attachments.count) return NO; for (NSDictionary *item in self.attachments) if (![item[@"type"] isEqualToString:@"photo"]) return NO; return YES; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [self isPhotoGrid] ? (self.attachments.count+2)/3 : self.attachments.count; }
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path { return [self isPhotoGrid] ? floor((tableView.bounds.size.width-16)/3)+4 : 70; }
- (void)openPhotoTile:(UIButton *)sender { if ((NSUInteger)sender.tag>=self.attachments.count) return; [self.navigationController pushViewController:[[OVKPhotoController alloc] initWithPhotos:self.attachments index:sender.tag] animated:YES]; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    if ([self isPhotoGrid]) {
        UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil]; cell.selectionStyle=UITableViewCellSelectionStyleNone; cell.backgroundColor=[UIColor colorWithWhite:.12 alpha:1];
        CGFloat size=floor((tableView.bounds.size.width-16)/3);
        for (NSUInteger col=0;col<3;col++) { NSUInteger index=path.row*3+col; if (index>=self.attachments.count) break;
            NSDictionary *photo=self.attachments[index]; CGRect frame=CGRectMake(4+col*(size+4),2,size,size);
            OVKRemoteImageView *image=[[OVKRemoteImageView alloc] initWithFrame:frame]; image.contentMode=UIViewContentModeScaleAspectFill; image.clipsToBounds=YES; [image load:photo[@"preview"]]; [cell.contentView addSubview:image];
            UIButton *button=[UIButton buttonWithType:UIButtonTypeCustom]; button.frame=frame; button.tag=index; button.accessibilityLabel=[NSString stringWithFormat:OVKL(@"Фотография %lu"),(unsigned long)(index+1)]; [button addTarget:self action:@selector(openPhotoTile:) forControlEvents:UIControlEventTouchUpInside]; [cell.contentView addSubview:button];
        } return cell;
    }
    NSDictionary *item = self.attachments[path.row]; UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil]; cell.textLabel.text = item[@"title"]; cell.textLabel.font = [UIFont boldSystemFontOfSize:14]; cell.textLabel.textColor = OVKBlue(); cell.textLabel.numberOfLines = 2; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    NSString *type = item[@"type"]; NSDictionary *types = @{@"photo":OVKL(@"Фотография — открыть"),@"audio":OVKL(@"Аудиозапись — воспроизвести"),@"video":OVKL(@"Видео — воспроизвести")}; cell.detailTextLabel.text = types[type]; NSString *local=OVKString(item[@"local_path"]); if (local.length) cell.detailTextLabel.text=[NSString stringWithFormat:OVKL(@"%@ · на устройстве"),local.pathExtension.uppercaseString];
    OVKRemoteImageView *preview = [[OVKRemoteImageView alloc] initWithFrame:CGRectMake(8,10,50,50)]; preview.contentMode = UIViewContentModeScaleAspectFill; preview.clipsToBounds = YES;
    if (OVKString(item[@"preview"]).length) [preview load:item[@"preview"]]; else preview.image = [UIImage imageNamed:[type isEqualToString:@"audio"] ? @"AudioMedia" : @"VideoMedia"];
    cell.indentationLevel = 6; [cell.contentView addSubview:preview]; OVKThemeCell(cell); cell.textLabel.textColor=OVKThemeAccent(); return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES]; if ([self isPhotoGrid]) return; NSDictionary *item = self.attachments[path.row];
    if ([item[@"type"] isEqualToString:@"photo"]) { NSMutableArray *photos=[NSMutableArray array]; for (NSDictionary *candidate in self.attachments) if ([candidate[@"type"] isEqualToString:@"photo"]) [photos addObject:candidate];
        OVKPhotoController *photo = [[OVKPhotoController alloc] initWithPhotos:photos index:[photos indexOfObject:item]]; [self.navigationController pushViewController:photo animated:YES]; }
    else {
        BOOL audio=[item[@"type"] isEqualToString:@"audio"];
        if (audio && OVKCurrentMusic) { [OVKCurrentMusic stop]; UINavigationController *oldNav=OVKCurrentMusic.navigationController; if (oldNav) { NSMutableArray *stack=[oldNav.viewControllers mutableCopy]; [stack removeObject:OVKCurrentMusic]; [oldNav setViewControllers:stack animated:NO]; } }
        else if (!audio && OVKCurrentMusic) { OVKCurrentMusic.wantsPlayback=NO; OVKCurrentMusic.started=NO; [OVKCurrentMusic pauseOutputAndReleaseSession]; }
        OVKPlaybackController *player=[[OVKPlaybackController alloc] init]; player.item=item;
        if (audio) { NSMutableArray *queue=[NSMutableArray array]; for (NSDictionary *candidate in self.attachments) if ([candidate[@"type"] isEqualToString:@"audio"]) [queue addObject:candidate]; player.queue=queue; player.queueIndex=[queue indexOfObject:item]; OVKCurrentMusic=player; }
        [self.navigationController pushViewController:player animated:YES];
    }
}
@end
@interface OVKLibraryController ()
@property (copy, nonatomic) NSString *kind;
@property (strong, nonatomic) NSNumber *identifier;
@property (strong, nonatomic) UIButton *moreButton;
@property (assign, nonatomic) NSUInteger offset;
@property (assign, nonatomic) BOOL loading;
@property (assign, nonatomic) BOOL more;
@end
@implementation OVKLibraryController
- (id)initWithKind:(NSString *)kind identifier:(NSNumber *)identifier title:(NSString *)title {
    self = [super initWithAttachments:@[] title:title]; if (self) { self.kind = kind; self.identifier = identifier; } return self;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.refreshControl = [[UIRefreshControl alloc] init]; [self.refreshControl addTarget:self action:@selector(refreshLibrary) forControlEvents:UIControlEventValueChanged];
    self.moreButton = [UIButton buttonWithType:UIButtonTypeCustom]; self.moreButton.frame = CGRectMake(0,0,320,48); [self.moreButton setTitleColor:OVKBlue() forState:UIControlStateNormal]; self.moreButton.titleLabel.font = [UIFont boldSystemFontOfSize:14]; [self.moreButton addTarget:self action:@selector(nextPage) forControlEvents:UIControlEventTouchUpInside]; self.tableView.tableFooterView = self.moreButton;
    [self refreshLibrary];
}
- (void)refreshLibrary { if (self.loading) { [self.refreshControl endRefreshing]; return; } [self fetchLibrary:NO]; }
- (void)nextPage { if (!self.loading) [self fetchLibrary:self.more && self.attachments.count > 0]; }
- (void)fetchLibrary:(BOOL)append {
    self.loading = YES; [self.moreButton setTitle:OVKL(@"Загрузка…") forState:UIControlStateNormal];
    NSString *method = [self.kind isEqualToString:@"photo"] ? @"photos.getAll" : ([self.kind isEqualToString:@"audio"] ? @"audio.get" : @"video.get");
    NSDictionary *params = @{@"owner_id":self.identifier,@"count":@20,@"offset":@(append ? self.offset : 0),@"photo_sizes":@1};
    [[OVKAPI shared] call:method parameters:params completion:^(id result,NSError *error) {
        self.loading = NO; [self.refreshControl endRefreshing];
        if (error) { [self.moreButton setTitle:OVKL(@"Повторить загрузку") forState:UIControlStateNormal]; OVKAlert(OVKL(@"Не удалось загрузить раздел"),error.localizedDescription); return; }
        NSArray *items = [result isKindOfClass:[NSArray class]] ? result : OVKArray(OVKDictionary(result)[@"items"]);
        NSMutableArray *raw = [NSMutableArray array]; for (id item in items) if ([item isKindOfClass:[NSDictionary class]]) [raw addObject:@{@"type":self.kind,self.kind:item}];
        NSArray *normal = OVKPlayableAttachments(@{@"attachments":raw});
        NSMutableArray *combined = append ? [self.attachments mutableCopy] : [NSMutableArray array]; [combined addObjectsFromArray:normal]; [self replaceAttachments:combined]; self.offset = append ? self.offset + items.count : items.count;
        NSNumber *count = OVKDictionary(result)[@"count"]; self.more = ![OVKAPI shared].demo && items.count >= 20 && (!count || self.offset < [count unsignedIntegerValue]);
        self.tableView.separatorStyle=[self isPhotoGrid] ? UITableViewCellSeparatorStyleNone : UITableViewCellSeparatorStyleSingleLine; self.tableView.backgroundColor=[self isPhotoGrid] ? [UIColor colorWithWhite:.12 alpha:1] : OVKThemeBackground(); [self.moreButton setTitleColor:[self isPhotoGrid] ? [UIColor lightGrayColor] : OVKBlue() forState:UIControlStateNormal];
        [self.moreButton setTitle:self.more ? OVKL(@"Показать ещё") : (self.attachments.count ? OVKL(@"Обновить") : OVKL(@"Здесь пока ничего нет — обновить")) forState:UIControlStateNormal]; [self.tableView reloadData];
    }];
}
@end
