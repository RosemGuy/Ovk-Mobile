#import "OVKMusicLayout.h"
#import "OVKVideoSound.h"
#import "OVKMP4Audio.h"
#import "OVKPerformance.h"
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
#import <string.h>
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
static NSCache *OVKImageCache(void) { static NSCache *cache; static dispatch_once_t once; dispatch_once(&once, ^{ cache=[[NSCache alloc] init]; cache.totalCostLimit=OVKImageCacheByteLimit(); cache.countLimit=OVKImageCacheCountLimit(); }); return cache; }
static NSOperationQueue *OVKImageDecodeQueue(void) {
    static NSOperationQueue *queue; static dispatch_once_t once; dispatch_once(&once, ^{ queue=[[NSOperationQueue alloc] init]; queue.name=@"Ovk-Mobile image decoding"; queue.maxConcurrentOperationCount=OVKLowMemoryDevice() ? 1 : 2; }); return queue;
}
@interface OVKImageTask : NSObject <OVKCancellable>
@property (assign, atomic) BOOL cancelled;
@property (strong, nonatomic) id<OVKCancellable> download;
@property (strong, nonatomic) NSOperation *operation;
@property (strong, nonatomic) NSURL *file;
@end
@implementation OVKImageTask
- (void)cancel { self.cancelled=YES; [self.download cancel]; self.download=nil; [self.operation cancel]; self.operation=nil; if (self.file) [[NSFileManager defaultManager] removeItemAtURL:self.file error:NULL]; self.file=nil; }
@end
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
+ (id<OVKCancellable>)image:(NSString *)url completion:(void (^)(UIImage *,NSError *))completion { return [self image:url maxPixelSize:OVKPreviewPixelLimit() completion:completion]; }
+ (id<OVKCancellable>)image:(NSString *)url maxPixelSize:(NSUInteger)pixels completion:(void (^)(UIImage *,NSError *))completion {
    pixels=MAX(64,MIN(OVKFullPhotoPixelLimit(),pixels));
    NSString *source = OVKMediaURL(url);
    NSCache *cache=OVKImageCache(); NSUInteger cacheGeneration=OVKImageCacheGeneration;
    if ([source hasPrefix:@"demo:"]) { UIImage *image = [UIImage imageNamed:[source substringFromIndex:5]]; dispatch_async(dispatch_get_main_queue(), ^{ completion(image,image ? nil : MediaError(8,OVKL(@"Нет демоизображения"))); }); return nil; }
    NSString *cacheKey=[NSString stringWithFormat:@"%lu:%@",(unsigned long)pixels,source];
    UIImage *saved = [cache objectForKey:cacheKey];
    if (saved) { dispatch_async(dispatch_get_main_queue(), ^{ completion(saved,nil); }); return nil; }
    OVKImageTask *ticket=[[OVKImageTask alloc] init];
    ticket.download=[self download:source limit:20*1024*1024 progress:nil completion:^(NSURL *file,NSError *error) {
        ticket.download=nil;
        if (ticket.cancelled) { if (file) [[NSFileManager defaultManager] removeItemAtURL:file error:NULL]; return; }
        if (error) { completion(nil,error); return; }
        ticket.file=file;
        NSBlockOperation *operation=[NSBlockOperation blockOperationWithBlock:^{ @autoreleasepool {
            if (ticket.cancelled) return;
            NSDictionary *inputOptions=@{(__bridge id)kCGImageSourceShouldCache:@NO};
            CGImageSourceRef input=CGImageSourceCreateWithURL((__bridge CFURLRef)file,(__bridge CFDictionaryRef)inputOptions); CGImageRef image=NULL;
            if (input) { NSDictionary *options=@{(__bridge id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(__bridge id)kCGImageSourceThumbnailMaxPixelSize:@(pixels),(__bridge id)kCGImageSourceCreateThumbnailWithTransform:@YES,(__bridge id)kCGImageSourceShouldCache:@YES}; image=CGImageSourceCreateThumbnailAtIndex(input,0,(__bridge CFDictionaryRef)options); CFRelease(input); }
            // Decode the small thumbnail on this worker, avoiding first-draw decompression during scrolling.
            UIImage *decoded=nil;
            if (image && !ticket.cancelled) {
                size_t width=CGImageGetWidth(image),height=CGImageGetHeight(image); CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
                CGContextRef bitmap=CGBitmapContextCreate(NULL,width,height,8,0,space,kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little); CGColorSpaceRelease(space);
                if (bitmap) { CGContextDrawImage(bitmap,CGRectMake(0,0,width,height),image); CGImageRef ready=CGBitmapContextCreateImage(bitmap); if (ready) { decoded=[UIImage imageWithCGImage:ready]; CGImageRelease(ready); } CGContextRelease(bitmap); }
            }
            if (image) CGImageRelease(image); [[NSFileManager defaultManager] removeItemAtURL:file error:NULL];
            dispatch_async(dispatch_get_main_queue(), ^{
                ticket.operation=nil; ticket.file=nil; if (ticket.cancelled) return;
                if (decoded && cacheGeneration==OVKImageCacheGeneration) [cache setObject:decoded forKey:cacheKey cost:CGImageGetWidth(decoded.CGImage)*CGImageGetHeight(decoded.CGImage)*4];
                completion(decoded,decoded ? nil : MediaError(9,OVKL(@"Не удалось прочитать изображение")));
            });
        } }];
        operation.threadPriority=.25; ticket.operation=operation; [OVKImageDecodeQueue() addOperation:operation];
    }];
    return ticket;
}
@end
@interface OVKRemoteImageView ()
@property (strong, nonatomic) id<OVKCancellable> task;
@property (assign, nonatomic) BOOL imageReady;
@property (assign, nonatomic) NSUInteger loadedPixelSize;
@end
@implementation OVKRemoteImageView
@synthesize maxPixelSize = _maxPixelSize;
- (void)load:(NSString *)url {
    NSString *source=OVKMediaURL(url); CGFloat edge=MAX(self.bounds.size.width,self.bounds.size.height);
    NSUInteger pixels=self.maxPixelSize ?: (edge>0 ? (NSUInteger)ceil(edge*[[UIScreen mainScreen] scale]) : OVKPreviewPixelLimit()); pixels=MAX(64,MIN(OVKPreviewPixelLimit(),pixels));
    if ([source isEqualToString:self.source] && self.loadedPixelSize==pixels && (self.task || self.imageReady)) return;
    self.source=nil; [self.task cancel]; self.task=nil; self.source=source; self.loadedPixelSize=pixels; self.imageReady=NO; self.image=[UIImage imageNamed:@"Avatar"];
    if (!source.length) return;
    __weak OVKRemoteImageView *weakSelf=self;
    self.task=[OVKMedia image:source maxPixelSize:pixels completion:^(UIImage *image,NSError *error) { if (![weakSelf.source isEqualToString:source] || weakSelf.loadedPixelSize!=pixels) return; weakSelf.task=nil; if (image) { weakSelf.imageReady=YES; weakSelf.image=image; } }];
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
@property (strong, nonatomic) UIToolbar *photoTopBar;
@property (strong, nonatomic) UIBarButtonItem *photoCounter;
@property (strong, nonatomic) UIActivityIndicatorView *photoSpinner;
@property (assign, nonatomic) BOOL photoControlsHidden;
@property (assign, nonatomic) BOOL photoNavigationWasHidden;
@property (assign, nonatomic) BOOL photoStatusWasHidden;
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
    UITapGestureRecognizer *singleTap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(togglePhotoControls)]; [singleTap requireGestureRecognizerToFail:doubleTap]; [self.scroll addGestureRecognizer:singleTap];
    self.photoSpinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite]; self.photoSpinner.hidesWhenStopped=YES; [self.view addSubview:self.photoSpinner];
    self.photoTopBar=[[UIToolbar alloc] init]; self.photoTopBar.barStyle=UIBarStyleBlack; self.photoTopBar.translucent=YES; [self.view addSubview:self.photoTopBar];
    UIBarButtonItem *done=[[UIBarButtonItem alloc] initWithTitle:OVKL(@"Готово") style:UIBarButtonItemStyleDone target:self action:@selector(closePhoto)];
    UIBarButtonItem *flex=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil]; self.photoCounter=[[UIBarButtonItem alloc] initWithTitle:self.title style:UIBarButtonItemStylePlain target:nil action:nil]; self.photoCounter.enabled=NO; self.photoTopBar.items=@[done,flex,self.photoCounter];
    self.status = [[UILabel alloc] initWithFrame:CGRectMake(10,15,self.view.bounds.size.width-20,60)]; self.status.autoresizingMask = UIViewAutoresizingFlexibleWidth; self.status.backgroundColor = [UIColor clearColor]; self.status.textColor = [UIColor whiteColor]; self.status.textAlignment = NSTextAlignmentCenter; self.status.font = [UIFont systemFontOfSize:13]; self.status.numberOfLines = 3; self.status.text = OVKL(@"Загрузка фотографии…"); [self.view addSubview:self.status];
    if (self.photos.count>1) {
        self.photoToolbar=[[UIToolbar alloc] init]; self.photoToolbar.barStyle=UIBarStyleBlack; self.photoToolbar.translucent=YES; [self.view addSubview:self.photoToolbar];
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
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; self.photoNavigationWasHidden=self.navigationController.navigationBarHidden; self.photoStatusWasHidden=[UIApplication sharedApplication].statusBarHidden; [self.navigationController setNavigationBarHidden:YES animated:animated]; [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationNone]; }
- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskAllButUpsideDown; }
- (BOOL)prefersStatusBarHidden { return YES; }
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [self.navigationController setNavigationBarHidden:self.photoNavigationWasHidden animated:animated]; [[UIApplication sharedApplication] setStatusBarHidden:self.photoStatusWasHidden withAnimation:UIStatusBarAnimationNone]; }
- (void)closePhoto { ++self.photoGeneration; [self.task cancel]; self.task=nil; if (self.navigationController.presentingViewController) [self.navigationController dismissViewControllerAnimated:YES completion:^{ [UIViewController attemptRotationToDeviceOrientation]; }]; else [self.navigationController popViewControllerAnimated:YES]; }
- (void)togglePhotoControls { self.photoControlsHidden=!self.photoControlsHidden; self.photoTopBar.hidden=self.photoControlsHidden; self.photoToolbar.hidden=self.photoControlsHidden; }
- (void)loadPhoto {
    NSUInteger generation=++self.photoGeneration; [self.task cancel]; self.task=nil; self.scroll.zoomScale=1; self.photo.image=nil; self.status.hidden=YES; [self.photoSpinner startAnimating];
    __weak OVKPhotoController *weakSelf = self;
    self.task = [OVKMedia image:self.url maxPixelSize:OVKFullPhotoPixelLimit() completion:^(UIImage *image,NSError *error) {
        OVKPhotoController *page = weakSelf; if (!page || generation!=page.photoGeneration) return; page.task = nil;
        [page.photoSpinner stopAnimating];
        if (!image) { page.status.hidden=NO; page.status.text=error.localizedDescription; return; }
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
    self.photoCounter.title=self.title;
    self.previousPhoto.enabled=self.photoIndex>0; self.nextPhoto.enabled=self.photoIndex+1<self.photos.count;
}
- (void)showPicture:(NSUInteger)index { if (index>=self.photos.count || index==self.photoIndex) return; self.photoIndex=index; self.url=OVKString(OVKDictionary(self.photos[index])[@"url"]); [self updatePhotoControls]; [self loadPhoto]; }
- (void)previousPicture { if (self.photoIndex>0) [self showPicture:self.photoIndex-1]; }
- (void)nextPicture { [self showPicture:self.photoIndex+1]; }
- (void)swipePicture:(UISwipeGestureRecognizer *)swipe { if (self.scroll.zoomScale>1.01) return; if (swipe.direction==UISwipeGestureRecognizerDirectionLeft) [self nextPicture]; else [self previousPicture]; }
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture { return self.scroll.zoomScale<=1.01; }
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; CGFloat toolbar=self.photos.count>1 ? 44 : 0; CGSize size=self.view.bounds.size; self.scroll.frame=CGRectMake(0,0,size.width,size.height); self.photoTopBar.frame=CGRectMake(0,0,size.width,44); self.photoSpinner.center=CGPointMake(size.width/2,size.height/2); self.status.frame=CGRectMake(20,size.height/2+20,size.width-40,60); self.photoToolbar.frame=CGRectMake(0,size.height-toolbar,size.width,toolbar); [self fitPhoto]; }
- (void)viewDidDisappear:(BOOL)animated { [super viewDidDisappear:animated]; if ([self isMovingFromParentViewController] || !self.parentViewController) { ++self.photoGeneration; [self.task cancel]; self.task=nil; } }
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView { return self.photo; }
- (void)dealloc { [_task cancel]; _scroll.delegate = nil; }
@end
void OVKPresentPhoto(UIViewController *presenter, OVKPhotoController *photo) {
    UINavigationController *navigation=[[OVKNavigationController alloc] initWithRootViewController:photo];
    navigation.modalPresentationStyle=UIModalPresentationFullScreen;
    [presenter presentViewController:navigation animated:YES completion:nil];
}
@interface OVKPlaybackController : UIViewController <UIAlertViewDelegate,UITableViewDataSource,UITableViewDelegate>
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
@property (assign, nonatomic) BOOL containerHasAudio;
@property (assign, nonatomic) BOOL enteringVideoFullscreen;
@property (assign, nonatomic) BOOL playbackNavigationWasHidden;
@property (strong, nonatomic) UIButton *videoClose;
@property (strong, nonatomic) OVKLocalAudio *music;
@property (assign, nonatomic) BOOL musicPrepared;
@property (strong, nonatomic) UIView *musicView;
@property (strong, nonatomic) UIView *musicTimeline;
@property (strong, nonatomic) UIView *musicTransport;
@property (strong, nonatomic) OVKRemoteImageView *musicCover;
@property (strong, nonatomic) UITableView *musicQueueTable;
@property (strong, nonatomic) UILabel *musicRemaining;
@property (strong, nonatomic) UILabel *musicQueueLabel;
@property (strong, nonatomic) MPVolumeView *musicVolume;
@property (strong, nonatomic) MPVolumeView *musicRoute;
@property (strong, nonatomic) NSArray *musicButtons;
@property (strong, nonatomic) UIButton *musicRepeat;
@property (strong, nonatomic) UIButton *musicShuffle;
@property (strong, nonatomic) UILabel *musicRepeatOne;
@property (assign, nonatomic) BOOL musicQueueVisible;
@property (assign, nonatomic) NSInteger repeatMode;
@property (assign, nonatomic) BOOL shuffleEnabled;
@property (strong, nonatomic) NSArray *playOrder;
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
    [super viewDidLoad]; self.playbackNavigationWasHidden=self.navigationController.navigationBarHidden; self.audioTask=UIBackgroundTaskInvalid; self.title = OVKString(self.item[@"title"]);
    OVKConfigureEdges(self);
    self.view.backgroundColor=[UIColor blackColor];
    self.status = [[UILabel alloc] initWithFrame:CGRectMake(20,24,self.view.bounds.size.width-40,100)]; self.status.autoresizingMask = UIViewAutoresizingFlexibleWidth; self.status.backgroundColor = [UIColor clearColor]; self.status.textColor=[UIColor whiteColor]; self.status.font = [UIFont boldSystemFontOfSize:16]; self.status.textAlignment = NSTextAlignmentCenter; self.status.numberOfLines = 4; self.status.text = self.title; [self.view addSubview:self.status];
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
    self.status.hidden=YES; self.progress.hidden=YES; self.spinner.activityIndicatorViewStyle=UIActivityIndicatorViewStyleWhite;
    if ([self.item[@"type"] isEqualToString:@"video"]) {
        self.videoClose=[UIButton buttonWithType:UIButtonTypeCustom]; self.videoClose.frame=CGRectMake(8,8,80,44); [self.videoClose setTitle:OVKL(@"Готово") forState:UIControlStateNormal]; self.videoClose.titleLabel.font=[UIFont boldSystemFontOfSize:15]; [self.videoClose addTarget:self action:@selector(backToMusic) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:self.videoClose];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(videoExitedFullscreen:) name:MPMoviePlayerDidExitFullscreenNotification object:nil];
    }
    [self resolveAndLoad];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if ([self.item[@"type"] isEqualToString:@"video"]) [self.navigationController setNavigationBarHidden:YES animated:animated];
    if (![self.item[@"type"] isEqualToString:@"video"]) { [self.navigationController.navigationBar setBackgroundImage:[UIImage imageNamed:@"MusicNavigation"] forBarMetrics:UIBarMetricsDefault]; self.navigationController.navigationBar.barStyle=UIBarStyleBlack; }
}
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; if (![self.item[@"type"] isEqualToString:@"video"]) { UIResponder *responder=(UIResponder *)[UIApplication sharedApplication].delegate; [responder becomeFirstResponder]; } }
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; if ([self.item[@"type"] isEqualToString:@"video"]) { if (!self.enteringVideoFullscreen && !self.movie.fullscreen) [self stop]; if (!self.enteringVideoFullscreen && !self.movie.fullscreen) [self.navigationController setNavigationBarHidden:self.playbackNavigationWasHidden animated:animated]; } self.navigationController.navigationBar.barStyle=UIBarStyleDefault; OVKStyleNavigation(self.navigationController); }
- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations {
    if (UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad) return UIInterfaceOrientationMaskAll;
    return [self.item[@"type"] isEqualToString:@"video"] ? UIInterfaceOrientationMaskAllButUpsideDown : UIInterfaceOrientationMaskPortrait;
}
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
    [self failPlayback:message];
    if ([self externalURL].length) [[[UIAlertView alloc] initWithTitle:OVKL(@"Нет прямого медиафайла") message:message delegate:self cancelButtonTitle:OVKL(@"Закрыть") otherButtonTitles:OVKL(@"Открыть в Safari"),nil] show];
}
- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index { if (alert.tag==281) { if (index==1) [self saveVideoForInspection]; return; } if (index == 1) [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[self externalURL]]]; }
- (void)resolveAndLoad {
    if (self.task || self.movie || self.music || self.asset || self.resolving) return; self.stopped = NO; [self beginAudioTask]; self.progress.hidden = NO; self.status.text = OVKL(@"Получаем адрес медиафайла…"); [self.spinner startAnimating];
    BOOL isVideo=[self.item[@"type"] isEqualToString:@"video"];
    if (!isVideo && !self.musicView) [self buildMusicPlayer];
    self.status.hidden=YES; self.progress.hidden=YES; [self.view bringSubviewToFront:self.spinner];
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
            if (media.count) { NSMutableDictionary *updated=[page.item mutableCopy]; updated[@"object"]=OVKMergeVideoMetadata(OVKDictionary(page.item[@"object"]),media); page.item=updated; }
            if (page.videoURLs.count) { [page loadNextVideo]; return; }
        }
        if (error || !url.length) { [page unavailable:error.localizedDescription ?: OVKL(@"Эта запись доступна только через веб-плеер или сервер не выдаёт файл.")]; return; }
        NSMutableDictionary *item = [page.item mutableCopy]; item[@"object"] = media; item[@"url"] = url; page.item = item; [page loadURL:url];
    }];
}
- (void)loadURL:(NSString *)url {
    NSURL *address = [NSURL URLWithString:url];
    NSString *extension = address.pathExtension.lowercaseString ?: @"";
    if ([@[@"m3u8",@"mpd",@"ogg",@"opus",@"webm"] containsObject:extension]) { if ([self.item[@"type"] isEqualToString:@"video"]) [self rejectVideo:OVKL(@"Этот формат не поддерживается встроенным проигрывателем старой iOS.")]; else [self unavailable:OVKL(@"Этот формат не поддерживается встроенным проигрывателем старой iOS.")]; return; }
    self.status.text = OVKL(@"Загрузка записи перед воспроизведением…"); self.progress.progress = 0;
    __weak OVKPlaybackController *weakSelf = self;
    self.task = [OVKMedia download:url limit:256ULL*1024*1024 progress:^(float value) {
        weakSelf.progress.progress = value < 0 ? 0 : value; weakSelf.status.text = value < 0 ? OVKL(@"Загрузка записи…") : [NSString stringWithFormat:OVKL(@"Загрузка записи… %d%%"),(int)(value*100)];
    } completion:^(NSURL *file,NSError *error) {
        OVKPlaybackController *page = weakSelf;
        if (!page || page.stopped) { if (file) [[NSFileManager defaultManager] removeItemAtURL:file error:NULL]; return; }
        page.task = nil; page.progress.hidden = YES; [page.spinner stopAnimating];
        if (error) { if (error.code != NSURLErrorCancelled) { if ([page.item[@"type"] isEqualToString:@"video"]) [page rejectVideo:error.localizedDescription]; else [page failPlayback:error.localizedDescription]; } return; }
        NSFileHandle *input=[NSFileHandle fileHandleForReadingAtPath:file.path]; NSData *header=[input readDataOfLength:64]; [input closeFile];
        const char *detected=OVKMediaContainer(header.bytes,header.length);
        NSString *container=detected ? [NSString stringWithUTF8String:detected] : @"unknown";
        [page.diagnostics addObject:[NSString stringWithFormat:@"Контейнер файла: %@",container]];
        if ([@[@"ogg",@"flac",@"webm"] containsObject:container]) { [[NSFileManager defaultManager] removeItemAtURL:file error:NULL]; NSString *message=[NSString stringWithFormat:OVKL(@"Сервер прислал %@. Штатный декодер iOS 6 этот формат не поддерживает."),container]; if ([page.item[@"type"] isEqualToString:@"video"]) [page rejectVideo:message]; else [page failPlayback:message]; return; }
        NSString *suffix=detected ? container : ([@[@"mp3",@"m4a",@"mp4",@"aac",@"wav",@"caf",@"aif",@"aiff",@"mov"] containsObject:extension] ? extension : @"bin");
        if ([container isEqualToString:@"mp4"] && ![page.item[@"type"] isEqualToString:@"video"]) suffix=@"m4a";
        NSURL *named = [NSURL fileURLWithPath:[file.path stringByAppendingPathExtension:suffix]];
        if (![[NSFileManager defaultManager] moveItemAtURL:file toURL:named error:&error]) { [[NSFileManager defaultManager] removeItemAtURL:file error:NULL]; [page failPlayback:error.localizedDescription]; return; }
        [page clearPlaybackFile];
        page.localFile = named; page.temporaryFile=YES;
        if (![page.item[@"type"] isEqualToString:@"video"]) [[NSFileManager defaultManager] setAttributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:named.path error:NULL]; [page beginPlayback];
    }];
}
- (void)beginPlayback {
    self.status.hidden=YES; self.status.text = OVKL(@"Подготовка записи…"); [self.spinner startAnimating];
    NSUInteger generation=++self.playbackGeneration;
    self.prepareDeadline=[NSTimer timerWithTimeInterval:25 target:self selector:@selector(prepareTimedOut) userInfo:nil repeats:NO]; [[NSRunLoop mainRunLoop] addTimer:self.prepareDeadline forMode:NSRunLoopCommonModes];
    if (![self.item[@"type"] isEqualToString:@"video"]) { [self prepareLocalAudio]; return; }
    // Inspect locally downloaded data asynchronously. No AVAudioPlayer file open/prepare on the UI thread.
    self.asset=[AVURLAsset URLAssetWithURL:self.localFile options:nil];
    NSURL *inspectionFile=self.localFile; AVURLAsset *inspectedAsset=self.asset; BOOL mayRecoverSound=!self.mergingSound;
    __weak OVKPlaybackController *weakSelf=self;
    [self.asset loadValuesAsynchronouslyForKeys:@[@"playable",@"tracks",@"duration"] completionHandler:^{
        NSData *bytes=[NSData dataWithContentsOfURL:inspectionFile options:NSDataReadingMappedIfSafe error:NULL];
        OVKMP4AudioInfo raw=OVKInspectMP4Audio(bytes.bytes,bytes.length);
        NSURL *recovered=nil;
        if (mayRecoverSound && raw.audioTracks && [inspectedAsset statusOfValueForKey:@"tracks" error:NULL]==AVKeyValueStatusLoaded && ![inspectedAsset tracksWithMediaType:AVMediaTypeAudio].count) {
            NSString *suffix=(raw.objectType==0x69 || raw.objectType==0x6b || (raw.codecCount && !memcmp(raw.codecs[0],".mp3",4))) ? @"mp3" : @"aac";
            NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"ovk-recovered-%@.%@",[[NSProcessInfo processInfo] globallyUniqueString],suffix]];
            if (OVKExtractMP4Audio(bytes.bytes,bytes.length,path.fileSystemRepresentation)) recovered=[NSURL fileURLWithPath:path];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            OVKPlaybackController *page=weakSelf; if (!page || page.stopped || generation!=page.playbackGeneration) { if (recovered) [[NSFileManager defaultManager] removeItemAtURL:recovered error:NULL]; return; }
            page.containerHasAudio=raw.valid && raw.audioTracks>0;
            if (raw.valid) {
                NSMutableArray *codecs=[NSMutableArray array];
                for (unsigned i=0;i<raw.codecCount;i++) { NSString *codec=[[NSString alloc] initWithBytes:raw.codecs[i] length:4 encoding:NSASCIIStringEncoding]; [codecs addObject:codec ?: @"????"]; }
                [page.diagnostics addObject:[NSString stringWithFormat:@"MP4 raw: audio=%u, codecs=%@, object=0x%02X, AOT=%u",raw.audioTracks,[codecs componentsJoinedByString:@", "],raw.objectType,raw.audioObjectType]];
            }
            if (recovered) { [page.diagnostics addObject:@"Аудиопакеты извлечены из MP4; готовим отдельную дорожку"]; [page prepareVideoSoundFile:recovered]; return; }
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
        [page configureMusicNavigation];
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
            if (!audio && !OVKString(self.item[@"local_path"]).length && self.candidateIndex<self.videoURLs.count) { [self rejectVideo:OVKL(@"В этом варианте нет аудиодорожки; пробуем следующий файл")]; return; }
            AVAssetTrack *sound=OVKPreferredVideoAudioTrack(self.asset);
            for (AVAssetTrack *track in [self.asset tracksWithMediaType:AVMediaTypeAudio]) for (id description in track.formatDescriptions) {
                FourCharCode codec=CMFormatDescriptionGetMediaSubType((__bridge CMFormatDescriptionRef)description);
                [self.diagnostics addObject:[NSString stringWithFormat:@"Audio codec %c%c%c%c; enabled=%d",(int)(codec>>24)&255,(int)(codec>>16)&255,(int)(codec>>8)&255,(int)codec&255,track.enabled]];
            }
            if (sound && !self.mergingSound && OVKVideoAudioNeedsConversion(sound) && OVKVideoAudioURL(OVKDictionary(self.item[@"object"])).length) { [self fetchVideoSound]; return; }
            if (sound && !self.mergingSound && (!sound.enabled || sound.preferredVolume<=0 || OVKVideoAudioNeedsConversion(sound))) { [self exportVideoWithSound:self.asset]; return; }
            if (!audio) {
                NSString *message=self.containerHasAudio ? OVKL(@"iOS не распознаёт кодек аудиодорожки") : OVKL(@"iOS не обнаружила аудиодорожку");
                [self.diagnostics addObject:message]; self.navigationItem.prompt=message;
            }
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
        page.enteringVideoFullscreen=YES; [page.movie setFullscreen:YES animated:YES]; page.enteringVideoFullscreen=NO; [page.movie play];
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
    self.status.hidden=YES; self.status.text=OVKL(@"Загрузка звуковой дорожки…"); self.progress.hidden=YES;
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
        [page prepareVideoSoundFile:named];
    }];
}
- (void)prepareVideoSoundFile:(NSURL *)file {
    self.soundFile=file; self.soundAsset=[AVURLAsset URLAssetWithURL:file options:nil];
    self.status.hidden=YES; self.status.text=OVKL(@"Соединяем видео и звук…");
    [self.prepareDeadline invalidate]; self.prepareDeadline=[NSTimer timerWithTimeInterval:40 target:self selector:@selector(prepareTimedOut) userInfo:nil repeats:NO]; [[NSRunLoop mainRunLoop] addTimer:self.prepareDeadline forMode:NSRunLoopCommonModes];
    NSUInteger generation=self.playbackGeneration; __weak OVKPlaybackController *weakSelf=self;
    [self.soundAsset loadValuesAsynchronouslyForKeys:@[@"tracks",@"duration"] completionHandler:^{ dispatch_async(dispatch_get_main_queue(), ^{
        OVKPlaybackController *owner=weakSelf; if (!owner || owner.stopped || generation!=owner.playbackGeneration) return;
        NSError *failure=nil;
        if ([owner.soundAsset statusOfValueForKey:@"tracks" error:&failure]!=AVKeyValueStatusLoaded || [owner.soundAsset statusOfValueForKey:@"duration" error:&failure]!=AVKeyValueStatusLoaded) { [owner rejectVideo:failure.localizedDescription ?: OVKL(@"Не удалось открыть звуковую дорожку")]; return; }
        [owner exportVideoWithSound:owner.soundAsset];
    }); }];
}

- (void)exportVideoWithSound:(AVAsset *)sound {
    NSError *failure=nil; AVMutableComposition *composition=OVKVideoComposition(self.asset,sound,&failure);
    if (!composition) { [self rejectVideo:failure.localizedDescription]; return; }
    BOOL convert=OVKVideoAudioNeedsConversion(OVKPreferredVideoAudioTrack(sound));
    NSString *preset=convert ? AVAssetExportPresetMediumQuality : AVAssetExportPresetPassthrough;
    self.exporter=[[AVAssetExportSession alloc] initWithAsset:composition presetName:preset];
    NSString *type=convert ? AVFileTypeMPEG4 : AVFileTypeQuickTimeMovie;
    if (!self.exporter || ![self.exporter.supportedFileTypes containsObject:type]) { [self rejectVideo:OVKL(@"iOS не поддерживает сборку этих дорожек")]; return; }
    [self.prepareDeadline invalidate]; self.prepareDeadline=[NSTimer timerWithTimeInterval:convert ? 180 : 40 target:self selector:@selector(prepareTimedOut) userInfo:nil repeats:NO]; [[NSRunLoop mainRunLoop] addTimer:self.prepareDeadline forMode:NSRunLoopCommonModes];
    NSURL *joined=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"ovk-joined-%@.%@",[[NSProcessInfo processInfo] globallyUniqueString],convert ? @"mp4" : @"mov"]]];
    self.exporter.outputURL=joined; self.exporter.outputFileType=type;
    self.status.hidden=YES; self.status.text=OVKL(convert ? @"Подготовка совместимого видео и звука…" : @"Соединяем видео и звук…");
    [self.diagnostics addObject:convert ? @"Преобразование системным декодером в MP4/H.264/AAC" : @"Пересборка контейнера с явной звуковой дорожкой"];
    AVAssetExportSession *session=self.exporter; NSUInteger generation=self.playbackGeneration;
    __weak OVKPlaybackController *weakSelf=self;
    [session exportAsynchronouslyWithCompletionHandler:^{ dispatch_async(dispatch_get_main_queue(), ^{
        OVKPlaybackController *result=weakSelf;
        if (!result || result.stopped || generation!=result.playbackGeneration) { [[NSFileManager defaultManager] removeItemAtURL:joined error:NULL]; return; }
        if (session.status!=AVAssetExportSessionStatusCompleted) { [[NSFileManager defaultManager] removeItemAtURL:joined error:NULL]; [result rejectVideo:session.error.localizedDescription ?: OVKL(@"Не удалось соединить дорожки")]; return; }
        result.exporter=nil; [result.prepareDeadline invalidate]; result.prepareDeadline=nil; [result.asset cancelLoading]; result.asset=nil;
        [result clearPlaybackFile]; result.localFile=joined; result.temporaryFile=YES;
        if (result.soundFile) [[NSFileManager defaultManager] removeItemAtURL:result.soundFile error:NULL]; result.soundFile=nil; result.soundAsset=nil; result.mergingSound=YES; [result beginPlayback];
    }); }];
}
- (void)loadNextVideo {
    self.mergingSound=NO; self.navigationItem.prompt=nil;
    if (self.stopped) return;
    if (self.candidateIndex>=self.videoURLs.count) { [self failPlayback:OVKL(@"Не удалось открыть вариант видео со звуком. Нажмите «Сведения», чтобы посмотреть результат проверки.")]; return; }
    NSString *url=self.videoURLs[self.candidateIndex++]; [self loadURL:url];
}
- (void)rejectVideo:(NSString *)reason {
    [self.diagnostics addObject:reason ?: OVKL(@"Ошибка варианта видео")]; [self releasePlayer];
    [self clearPlaybackFile];
    [self loadNextVideo];
}
- (void)configureMusicNavigation {
    if (!self.musicView) return;
    self.navigationItem.rightBarButtonItems=nil;
    self.navigationItem.rightBarButtonItem=nil;
    if (UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad) return;
    UIBarButtonItem *queue=[[UIBarButtonItem alloc] initWithTitle:self.musicQueueVisible ? OVKL(@"Обложка") : OVKL(@"Очередь") style:UIBarButtonItemStylePlain target:self action:@selector(toggleMusicQueue)];
    [queue setBackgroundImage:[[UIImage imageNamed:@"MusicButton"] resizableImageWithCapInsets:UIEdgeInsetsMake(5,7,5,7)] forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
    self.navigationItem.rightBarButtonItem=queue;
}
- (void)buildMusicPlayer {
    if (self.musicView) { [self updateMusicModes]; [self musicReady]; return; }
    if (!self.queue.count) { self.queue=@[self.item]; self.queueIndex=0; }
    self.musicView=[[UIView alloc] initWithFrame:self.view.bounds]; self.musicView.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; self.musicView.backgroundColor=[UIColor blackColor]; [self.view addSubview:self.musicView];
    self.musicTimeline=[[UIImageView alloc] initWithImage:[[UIImage imageNamed:@"MusicPanel"] resizableImageWithCapInsets:UIEdgeInsetsMake(3,3,3,3)]]; self.musicTimeline.userInteractionEnabled=YES; [self.musicView addSubview:self.musicTimeline];
    self.musicQueueLabel=[[UILabel alloc] init]; self.musicTime=[[UILabel alloc] init]; self.musicRemaining=[[UILabel alloc] init];
    for (UILabel *label in @[self.musicQueueLabel,self.musicTime,self.musicRemaining]) { label.backgroundColor=[UIColor clearColor]; label.textColor=[UIColor whiteColor]; label.font=[UIFont boldSystemFontOfSize:12]; label.textAlignment=NSTextAlignmentCenter; [self.musicTimeline addSubview:label]; }
    self.musicQueueLabel.text=[NSString stringWithFormat:OVKL(@"%lu из %lu"),(unsigned long)(self.queueIndex+1),(unsigned long)self.queue.count];
    self.musicSeek=[[UISlider alloc] init]; self.musicSeek.continuous=NO; [self.musicSeek addTarget:self action:@selector(seekMusic) forControlEvents:UIControlEventValueChanged]; [self.musicTimeline addSubview:self.musicSeek];
    self.musicRepeat=[UIButton buttonWithType:UIButtonTypeCustom]; [self.musicRepeat addTarget:self action:@selector(toggleRepeat) forControlEvents:UIControlEventTouchUpInside]; [self.musicTimeline addSubview:self.musicRepeat];
    self.musicShuffle=[UIButton buttonWithType:UIButtonTypeCustom]; [self.musicShuffle addTarget:self action:@selector(toggleShuffle) forControlEvents:UIControlEventTouchUpInside]; [self.musicTimeline addSubview:self.musicShuffle];
    self.musicRepeatOne=[[UILabel alloc] initWithFrame:CGRectMake(31,2,10,12)]; self.musicRepeatOne.text=@"1"; self.musicRepeatOne.textColor=[UIColor whiteColor]; self.musicRepeatOne.backgroundColor=[UIColor clearColor]; self.musicRepeatOne.font=[UIFont boldSystemFontOfSize:10]; [self.musicRepeat addSubview:self.musicRepeatOne];
    self.musicCover=[[OVKRemoteImageView alloc] initWithImage:[UIImage imageNamed:@"MusicCover"]]; self.musicCover.contentMode=UIViewContentModeScaleAspectFit; [self.musicView addSubview:self.musicCover];
    NSDictionary *object=OVKDictionary(self.item[@"object"]),*album=OVKDictionary(object[@"album"]);
    CGFloat titleWidth=MAX(90,MIN(280,self.view.bounds.size.width-170)); UIView *heading=[[UIView alloc] initWithFrame:CGRectMake(0,0,titleWidth,40)];
    NSArray *lines=@[OVKString(object[@"artist"]),OVKString(object[@"title"]).length ? OVKString(object[@"title"]) : self.title,OVKString(album[@"title"])];
    for (NSUInteger i=0;i<3;i++) { UILabel *line=[[UILabel alloc] initWithFrame:CGRectMake(0,i*13,titleWidth,13)]; line.autoresizingMask=UIViewAutoresizingFlexibleWidth; line.text=lines[i]; line.font=i==1 ? [UIFont boldSystemFontOfSize:12] : [UIFont systemFontOfSize:11]; line.textColor=i==1 ? [UIColor whiteColor] : [UIColor lightGrayColor]; line.backgroundColor=[UIColor clearColor]; line.textAlignment=NSTextAlignmentCenter; [heading addSubview:line]; } self.navigationItem.titleView=heading;
    NSString *coverURL=OVKPhotoSource(OVKDictionary(album[@"thumb"])); if (coverURL.length) [self.musicCover load:coverURL];
    self.musicQueueTable=[[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain]; self.musicQueueTable.delegate=self; self.musicQueueTable.dataSource=self; self.musicQueueTable.rowHeight=48; self.musicQueueTable.backgroundColor=[UIColor colorWithWhite:.16 alpha:1]; self.musicQueueTable.separatorColor=[UIColor colorWithWhite:.28 alpha:1]; self.musicQueueTable.tableFooterView=[[UIView alloc] initWithFrame:CGRectZero]; [self.musicView addSubview:self.musicQueueTable];
    self.musicTransport=[[UIImageView alloc] initWithImage:[[UIImage imageNamed:@"MusicPanel"] resizableImageWithCapInsets:UIEdgeInsetsMake(3,3,3,3)]]; self.musicTransport.userInteractionEnabled=YES; [self.musicView addSubview:self.musicTransport];
    NSMutableArray *buttons=[NSMutableArray array];
    for (NSUInteger i=0;i<3;i++) { UIButton *button=[UIButton buttonWithType:UIButtonTypeCustom]; [button setImage:[UIImage imageNamed:@[@"PreviousTrack",@"PauseTrack",@"NextTrack"][i]] forState:UIControlStateNormal]; button.accessibilityLabel=@[OVKL(@"Предыдущий трек"),OVKL(@"Пауза"),OVKL(@"Следующий трек")][i]; if (i==1) { self.musicPlay=button; [button addTarget:self action:@selector(toggleMusic) forControlEvents:UIControlEventTouchUpInside]; } else { button.tag=i==0 ? -1 : 1; [button addTarget:self action:@selector(changeTrack:) forControlEvents:UIControlEventTouchUpInside]; } [self.musicTransport addSubview:button]; [buttons addObject:button]; } self.musicButtons=buttons;
    self.musicRoute=[[MPVolumeView alloc] init]; self.musicRoute.showsVolumeSlider=NO; self.musicRoute.showsRouteButton=YES; [self.musicTimeline addSubview:self.musicRoute];
    self.musicVolume=[[MPVolumeView alloc] init]; self.musicVolume.showsRouteButton=NO; [self.musicTransport addSubview:self.musicVolume];
    self.musicTimer=[NSTimer timerWithTimeInterval:OVKLowMemoryDevice() ? .5 : .3 target:self selector:@selector(refreshLocalAudio) userInfo:nil repeats:YES]; [[NSRunLoop mainRunLoop] addTimer:self.musicTimer forMode:NSRunLoopCommonModes];
    self.navigationItem.hidesBackButton=YES; UIBarButtonItem *back=[[UIBarButtonItem alloc] initWithTitle:OVKL(@"Музыка") style:UIBarButtonItemStylePlain target:self action:@selector(backToMusic)]; [back setBackgroundImage:[[UIImage imageNamed:@"MusicButton"] resizableImageWithCapInsets:UIEdgeInsetsMake(5,7,5,7)] forState:UIControlStateNormal barMetrics:UIBarMetricsDefault]; self.navigationItem.leftBarButtonItem=back;
    [self configureMusicNavigation]; [self updateMusicModes]; [self.view setNeedsLayout]; [self musicReady];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.spinner.center=CGPointMake(self.view.bounds.size.width/2,self.view.bounds.size.height/2);
    if (!self.musicView) return;
    CGFloat width=self.view.bounds.size.width,height=self.view.bounds.size.height; BOOL pad=UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad;
    OVKMusicLayout layout=OVKMusicPlayerLayout(width,height,pad,self.musicQueueVisible);
    self.musicView.frame=self.view.bounds;
    self.musicTimeline.frame=CGRectMake(layout.timeline.x,layout.timeline.y,layout.timeline.width,layout.timeline.height);
    self.musicCover.frame=CGRectMake(layout.cover.x,layout.cover.y,layout.cover.width,layout.cover.height); self.musicCover.hidden=!layout.showCover;
    self.musicQueueTable.frame=CGRectMake(layout.queue.x,layout.queue.y,layout.queue.width,layout.queue.height); self.musicQueueTable.hidden=!layout.showQueue;
    self.musicTransport.frame=CGRectMake(layout.transport.x,layout.transport.y,layout.transport.width,layout.transport.height);
    self.musicQueueLabel.frame=CGRectMake(60,4,width-120,20); self.musicTime.frame=CGRectMake(10,28,52,24); self.musicRemaining.frame=CGRectMake(width-64,28,54,24); self.musicSeek.frame=CGRectMake(70,26,width-140,28);
    self.musicRoute.frame=CGRectMake(width/2-22,53,44,30);
    self.musicRepeat.frame=CGRectMake(10,53,44,30); self.musicShuffle.frame=CGRectMake(width-54,53,44,30);
    for (NSUInteger i=0;i<self.musicButtons.count;i++) ((UIButton *)self.musicButtons[i]).frame=CGRectMake(width/2-32+((NSInteger)i-1)*96,4,64,52);
    CGFloat volumeWidth=MIN(560,width-40); self.musicVolume.frame=CGRectMake((width-volumeWidth)/2,64,volumeWidth,28);
}
- (void)toggleMusicQueue { self.musicQueueVisible=!self.musicQueueVisible; [self configureMusicNavigation]; [self.view setNeedsLayout]; if (self.musicQueueVisible && self.queueIndex<self.queue.count) [self.musicQueueTable scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:self.queueIndex inSection:0] atScrollPosition:UITableViewScrollPositionMiddle animated:NO]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.queue.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"music-queue"]; if (!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"music-queue"];
    NSDictionary *item=OVKDictionary(self.queue[path.row]),*object=OVKDictionary(item[@"object"]); cell.textLabel.text=OVKString(object[@"title"]).length ? OVKString(object[@"title"]) : OVKString(item[@"title"]); cell.textLabel.font=[UIFont systemFontOfSize:15]; cell.textLabel.textColor=path.row==self.queueIndex ? [UIColor colorWithRed:.4 green:.7 blue:1 alpha:1] : [UIColor whiteColor]; cell.detailTextLabel.text=OVKString(OVKDictionary(item[@"object"])[@"artist"]); cell.detailTextLabel.textColor=[UIColor lightGrayColor]; cell.backgroundColor=[UIColor colorWithWhite:path.row==self.queueIndex ? .23 : .16 alpha:1]; cell.contentView.backgroundColor=cell.backgroundColor; cell.accessoryType=UITableViewCellAccessoryNone; cell.indentationWidth=16; cell.indentationLevel=2;
    UILabel *number=(UILabel *)[cell.contentView viewWithTag:3201]; if (!number) { number=[[UILabel alloc] initWithFrame:CGRectMake(5,0,30,48)]; number.tag=3201; number.backgroundColor=[UIColor clearColor]; number.textAlignment=NSTextAlignmentCenter; number.font=[UIFont boldSystemFontOfSize:14]; [cell.contentView addSubview:number]; } number.text=path.row==self.queueIndex ? (self.music.playing ? @"▶" : @"II") : [NSString stringWithFormat:@"%ld",(long)path.row+1]; number.textColor=cell.textLabel.textColor; return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path { [tableView deselectRowAtIndexPath:path animated:YES]; if (self.musicPrepared && (NSUInteger)path.row!=self.queueIndex) [self playQueueIndex:path.row]; }
- (void)toggleRepeat { self.repeatMode=(self.repeatMode+1)%3; [self updateMusicModes]; }
- (void)toggleShuffle { self.shuffleEnabled=!self.shuffleEnabled; self.playOrder=nil; [self updateMusicModes]; }
- (NSArray *)orderedQueue {
    if (!self.shuffleEnabled) return nil;
    if (self.playOrder.count!=self.queue.count) { NSMutableArray *order=[NSMutableArray arrayWithObject:@(self.queueIndex)]; NSMutableArray *rest=[NSMutableArray array]; for (NSUInteger i=0;i<self.queue.count;i++) if (i!=self.queueIndex) [rest addObject:@(i)]; for (NSUInteger n=rest.count;n>1;n--) [rest exchangeObjectAtIndex:n-1 withObjectAtIndex:arc4random_uniform((uint32_t)n)]; [order addObjectsFromArray:rest]; self.playOrder=order; } return self.playOrder;
}
- (NSInteger)nextMusicIndex:(NSInteger)direction automatic:(BOOL)automatic {
    NSArray *order=[self orderedQueue]; NSUInteger position=order ? [order indexOfObject:@(self.queueIndex)] : self.queueIndex; if (position==NSNotFound) return -1;
    long next=OVKMusicNextPosition(self.queue.count,position,(int)direction,(int)self.repeatMode,automatic); if (next<0) return -1; return order ? [order[next] integerValue] : next;
}
- (void)updateMusicModes {
    self.musicPlay.enabled=self.musicPrepared; self.musicSeek.enabled=self.musicPrepared;
    [self.musicRepeat setImage:[UIImage imageNamed:self.repeatMode ? @"MusicRepeatActive" : @"MusicRepeat"] forState:UIControlStateNormal]; self.musicRepeatOne.hidden=self.repeatMode!=2; self.musicRepeat.accessibilityLabel=OVKL(@"Повтор"); self.musicRepeat.accessibilityValue=@[OVKL(@"Выключен"),OVKL(@"Вся очередь"),OVKL(@"Один трек")][self.repeatMode];
    [self.musicShuffle setImage:[UIImage imageNamed:self.shuffleEnabled ? @"MusicShuffleActive" : @"MusicShuffle"] forState:UIControlStateNormal]; self.musicShuffle.accessibilityLabel=OVKL(@"Перемешать"); self.musicShuffle.accessibilityValue=self.shuffleEnabled ? OVKL(@"Включено") : OVKL(@"Выключен");
    if (self.musicButtons.count==3) { UIButton *previous=self.musicButtons[0],*next=self.musicButtons[2]; previous.enabled=self.musicPrepared && (self.musicPosition>3 || [self nextMusicIndex:-1 automatic:NO]>=0); next.enabled=self.musicPrepared && [self nextMusicIndex:1 automatic:NO]>=0; previous.alpha=previous.enabled ? 1 : .3; next.alpha=next.enabled ? 1 : .3; }
}
- (void)playQueueIndex:(NSInteger)index {
    if (index<0 || index>=(NSInteger)self.queue.count) return;
    if ((NSUInteger)index==self.queueIndex) { [self.music seek:0]; self.started=NO; [self startPreparedPlayback]; return; }
    [self releasePlayer]; [self clearPlaybackFile]; self.queueIndex=index; self.item=self.queue[index]; self.title=OVKString(self.item[@"title"]); [self resolveAndLoad];
}
- (void)refreshLocalAudio { [self.music refresh]; }
- (void)musicReady { if (!self.stopped && self.music && self.musicPrepared && !self.started) [self startPreparedPlayback]; }
- (void)toggleMusic {
    if (!self.musicPrepared) return;
    if (self.music.playing || self.activationPending) { self.wantsPlayback=NO; self.started=NO; [self pauseOutputAndReleaseSession]; }
    else { if (self.musicDuration>0 && self.musicPosition>=self.musicDuration-.05) [self.music seek:0]; self.started=NO; [self startPreparedPlayback]; }
    [self updateMusic];
}
- (void)seekMusic { self.nowPlayingUpdated=0; double duration=self.musicDuration; if (isfinite(duration) && duration>0) [self.music seek:duration*self.musicSeek.value]; }
- (void)updateMusic {
    if (self.music.completed && self.started) {
        self.started=NO;
        NSInteger next=[self nextMusicIndex:1 automatic:YES]; if (next>=0) { [self playQueueIndex:next]; return; }
        self.wantsPlayback=NO; [self pauseOutputAndReleaseSession];
    }
    self.musicPosition=self.music.currentTime; self.musicDuration=self.music.duration; if (!self.view.window) { [self updateNowPlaying]; return; } double now=self.musicPosition, total=self.musicDuration; if (!isfinite(now)) now=0; if (!isfinite(total) || total<=0) total=0;
    if (!self.musicSeek.tracking) self.musicSeek.value=total>0 ? now/total : 0;
    self.musicTime.text=[NSString stringWithFormat:@"%ld:%02ld",(long)now/60,(long)now%60]; long remaining=(long)ceil(MAX(0,total-now)); self.musicRemaining.text=total>0 ? [NSString stringWithFormat:@"−%ld:%02ld",remaining/60,remaining%60] : @"−–:––"; [self updateMusicModes];
    UITableViewCell *current=[self.musicQueueTable cellForRowAtIndexPath:[NSIndexPath indexPathForRow:self.queueIndex inSection:0]]; ((UILabel *)[current.contentView viewWithTag:3201]).text=self.music.playing ? @"▶" : @"II";
    [self.musicPlay setImage:[UIImage imageNamed:self.music.playing ? @"PauseTrack" : @"PlayTrack"] forState:UIControlStateNormal]; self.musicPlay.accessibilityLabel=self.music.playing ? OVKL(@"Пауза") : OVKL(@"Воспроизвести"); [self updateNowPlaying];
}
- (void)changeTrack:(UIButton *)sender { if (sender.tag<0 && self.musicPosition>3) { [self.music seek:0]; return; } [self playQueueIndex:[self nextMusicIndex:sender.tag automatic:NO]]; }
- (void)movieReady:(NSNotification *)note {
    if (![NSThread isMainThread]) { __weak OVKPlaybackController *weakSelf=self; dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf movieReady:note]; }); return; }
    if (self.stopped || !self.movie || (note && note.object!=self.movie) || self.started) return;
    if (!self.movie.isPreparedToPlay && !(self.movie.loadState & MPMovieLoadStatePlayable)) return;
    [self startPreparedPlayback];
}
- (void)prepareTimedOut { if ([self.item[@"type"] isEqualToString:@"video"]) [self rejectVideo:OVKL(@"Истекло время подготовки варианта видео")]; else [self failPlayback:OVKL(@"Проигрыватель не смог подготовить запись за 25 секунд. Нажмите обновление, чтобы повторить.")]; }
- (void)releasePlayer {
    ++self.playbackGeneration; self.nowPlayingUpdated=0; [self endAudioTask]; [self.prepareDeadline invalidate];
    [self.musicTimer invalidate]; self.musicTimer=nil;
    OVKLocalAudio *audio=self.music; NSString *owner=self.sessionOwner;
    [audio stopWithCompletion:^{ OVKDeactivateSession(owner); }]; self.music=nil; self.musicPrepared=NO; [self.musicView removeFromSuperview]; self.musicView=nil; self.musicQueueTable.dataSource=nil; self.musicQueueTable.delegate=nil; self.musicQueueTable=nil; self.musicTimeline=nil; self.musicTransport=nil; self.musicCover=nil; self.musicVolume=nil; self.musicRoute=nil; self.musicButtons=nil; self.musicRepeat=nil; self.musicShuffle=nil; self.musicRepeatOne=nil; self.musicQueueLabel=nil; self.musicRemaining=nil; self.musicTime=nil; self.musicSeek=nil; self.musicPlay=nil; self.prepareDeadline=nil;
    [self.exporter cancelExport]; self.exporter=nil; [self.soundAsset cancelLoading]; self.soundAsset=nil;
    if (self.soundFile) [[NSFileManager defaultManager] removeItemAtURL:self.soundFile error:NULL]; self.soundFile=nil;
    [self.asset cancelLoading]; self.asset=nil; self.started=NO;
    MPMoviePlayerController *movie=self.movie; self.movie=nil; [movie stop]; [movie.view removeFromSuperview];
    if (!audio) OVKDeactivateSession(self.sessionOwner); self.sessionOwner=nil; self.activationPending=NO; self.wantsPlayback=NO;
    if (OVKCurrentMusic==self) { MPNowPlayingInfoCenter *center=[MPNowPlayingInfoCenter defaultCenter]; center.nowPlayingInfo=nil; }
}
- (void)failPlayback:(NSString *)message {
    if ([self.item[@"type"] isEqualToString:@"video"]) [self.navigationController setNavigationBarHidden:NO animated:NO];
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
    NSString *message=[NSString stringWithFormat:@"%@\nВыход: %@\nfiles: %@\n%@",state,[ports componentsJoinedByString:@", "],[keys componentsJoinedByString:@", "],[self.diagnostics componentsJoinedByString:@"\n"]];
    UIAlertView *alert=[[UIAlertView alloc] initWithTitle:OVKL(@"Проверка воспроизведения") message:message delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil];
    if (self.localFile && [self.item[@"type"] isEqualToString:@"video"]) [alert addButtonWithTitle:OVKL(@"Сохранить файл")]; alert.tag=281; [alert show];
}
- (void)saveVideoForInspection {
    if (!self.localFile) return;
    NSString *documents=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES) objectAtIndex:0];
    NSString *name=[NSString stringWithFormat:@"Video-check-%@.%@",[[NSProcessInfo processInfo] globallyUniqueString],self.localFile.pathExtension ?: @"mp4"];
    NSString *path=[documents stringByAppendingPathComponent:name]; NSError *error=nil;
    if (![[NSFileManager defaultManager] copyItemAtPath:self.localFile.path toPath:path error:&error]) { OVKAlert(OVKL(@"Ошибка"),error.localizedDescription); return; }
    [[self.diagnostics componentsJoinedByString:@"\n"] writeToFile:[path stringByAppendingString:@".txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    OVKAlert(OVKL(@"Файл сохранён"),path);
}
- (void)videoExitedFullscreen:(NSNotification *)note {
    if (note.object!=self.movie || self.stopped) return;
    [self stop]; [self.navigationController setNavigationBarHidden:self.playbackNavigationWasHidden animated:NO];
    if (self.navigationController.topViewController==self) [self.navigationController popViewControllerAnimated:NO]; [UIViewController attemptRotationToDeviceOrientation];
}
- (void)movieEnded:(NSNotification *)note {
    if (![NSThread isMainThread]) { __weak OVKPlaybackController *weakSelf=self; dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf movieEnded:note]; }); return; }
    if (note.object!=self.movie || self.stopped) return;
    NSInteger reason=[note.userInfo[MPMoviePlayerPlaybackDidFinishReasonUserInfoKey] integerValue];
    if (reason==MPMovieFinishReasonUserExited) { [self stop]; [self.navigationController setNavigationBarHidden:self.playbackNavigationWasHidden animated:NO]; if (self.navigationController.topViewController==self) [self.navigationController popViewControllerAnimated:NO]; return; }
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
- (void)openPhotoTile:(UIButton *)sender { if ((NSUInteger)sender.tag>=self.attachments.count) return; OVKPresentPhoto(self,[[OVKPhotoController alloc] initWithPhotos:self.attachments index:sender.tag]); }
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
        OVKPhotoController *photo = [[OVKPhotoController alloc] initWithPhotos:photos index:[photos indexOfObject:item]]; OVKPresentPhoto(self,photo); }
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
    NSUInteger pageSize=OVKPageSize(); NSDictionary *params = @{@"owner_id":self.identifier,@"count":@(pageSize),@"offset":@(append ? self.offset : 0),@"photo_sizes":@1};
    [[OVKAPI shared] call:method parameters:params completion:^(id result,NSError *error) {
        self.loading = NO; [self.refreshControl endRefreshing];
        if (error) { [self.moreButton setTitle:OVKL(@"Повторить загрузку") forState:UIControlStateNormal]; OVKAlert(OVKL(@"Не удалось загрузить раздел"),error.localizedDescription); return; }
        NSArray *items = [result isKindOfClass:[NSArray class]] ? result : OVKArray(OVKDictionary(result)[@"items"]);
        NSMutableArray *raw = [NSMutableArray array]; for (id item in items) if ([item isKindOfClass:[NSDictionary class]]) [raw addObject:@{@"type":self.kind,self.kind:item}];
        NSArray *normal = OVKPlayableAttachments(@{@"attachments":raw});
        NSMutableArray *combined = append ? [self.attachments mutableCopy] : [NSMutableArray array]; [combined addObjectsFromArray:normal]; [self replaceAttachments:combined]; self.offset = append ? self.offset + items.count : items.count;
        NSNumber *count = OVKDictionary(result)[@"count"]; self.more = ![OVKAPI shared].demo && items.count >= pageSize && (!count || self.offset < [count unsignedIntegerValue]);
        self.tableView.separatorStyle=[self isPhotoGrid] ? UITableViewCellSeparatorStyleNone : UITableViewCellSeparatorStyleSingleLine; self.tableView.backgroundColor=[self isPhotoGrid] ? [UIColor colorWithWhite:.12 alpha:1] : OVKThemeBackground(); [self.moreButton setTitleColor:[self isPhotoGrid] ? [UIColor lightGrayColor] : OVKBlue() forState:UIControlStateNormal];
        [self.moreButton setTitle:self.more ? OVKL(@"Показать ещё") : (self.attachments.count ? OVKL(@"Обновить") : OVKL(@"Здесь пока ничего нет — обновить")) forState:UIControlStateNormal]; [self.tableView reloadData];
    }];
}
@end
