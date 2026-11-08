#import "OVKMusicLayout.h"
#import "OVKImageRequests.h"
#import "OVKVideoSound.h"
#import "OVKMP4Audio.h"
#import "OVKPerformance.h"
#import "OVKDebug.h"
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
#import <SystemConfiguration/SystemConfiguration.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <netinet/in.h>
#import <math.h>
#import <limits.h>
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
#if DEBUG
    if (error && error.code != NSURLErrorCancelled) {
        OVKDebugLog(@"[Media] download failed (domain=%@, code=%ld, received=%llu bytes)",
                    error.domain, (long)error.code, self.received);
    }
#endif
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
NSString * const OVKNowPlayingChanged = @"OVKNowPlayingChanged";
static NSString * const OVKInlineAudioProgressChanged = @"OVKInlineAudioProgressChanged";
static void OVKNotifyNowPlaying(void) {
    [[NSNotificationCenter defaultCenter] postNotificationName:OVKNowPlayingChanged object:nil];
}
static void OVKShowCurrentMusic(UIViewController *controller);
static void OVKShowBundledVideo(NSString *name,UIViewController *controller);
static void OVKRouteRemoteControl(UIEvent *event);
static NSDictionary *OVKNowPlayingSnapshot(void);
static void OVKToggleNowPlaying(void);
static void OVKNextNowPlaying(void);
static NSString * const OVKAudioFavoritesChanged = @"OVKAudioFavoritesChanged";

static NSDictionary *OVKAudioFavoriteParameters(NSDictionary *item) {
    if (![item[@"type"] isEqualToString:@"audio"] || item[@"voice_message"]) return nil;
    NSDictionary *audio = OVKDictionary(item[@"object"]);
    long long owner = [OVKString(audio[@"owner_id"] ?: audio[@"oid"]) longLongValue];
    long long identifier = [OVKString(audio[@"id"] ?: audio[@"aid"]) longLongValue];
    if (!owner || identifier <= 0) return nil;
    return @{@"owner_id":@(owner), @"audio_id":@(identifier)};
}

static NSString *OVKAudioFavoriteID(NSDictionary *parameters) {
    if (!parameters) return nil;
    return [NSString stringWithFormat:@"%@_%@", parameters[@"owner_id"], parameters[@"audio_id"]];
}

static NSString *OVKCurrentCacheScope(void) {
    OVKAPI *api = [OVKAPI shared];
    return api.demo ? nil : OVKMusicCacheScope(api.server,api.userID);
}

static NSDictionary *OVKOfflineAudioMetadata(NSDictionary *item) {
    NSDictionary *params = OVKAudioFavoriteParameters(item);
    if (!params) return nil;
    NSDictionary *audio = OVKDictionary(item[@"object"]);
    NSDictionary *object = @{@"id":params[@"audio_id"], @"owner_id":params[@"owner_id"],
                             @"title":OVKString(audio[@"title"]), @"artist":OVKString(audio[@"artist"] ?: audio[@"performer"]),
                             @"added":@([OVKString(audio[@"added"]) boolValue])};
    return @{@"type":@"audio", @"title":OVKString(item[@"title"]), @"object":object};
}

static BOOL OVKOfflineError(NSError *error) {
    if (![error.domain isEqualToString:NSURLErrorDomain]) return NO;
    return error.code==NSURLErrorNotConnectedToInternet || error.code==NSURLErrorNetworkConnectionLost ||
           error.code==NSURLErrorCannotFindHost || error.code==NSURLErrorDNSLookupFailed ||
           error.code==NSURLErrorCannotConnectToHost;
}

static BOOL OVKNetworkUnavailable(void) {
    struct sockaddr_in address = {0};
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    SCNetworkReachabilityRef route = SCNetworkReachabilityCreateWithAddress(NULL,(const struct sockaddr *)&address);
    if (!route) return NO;
    SCNetworkReachabilityFlags flags = 0;
    BOOL known = SCNetworkReachabilityGetFlags(route,&flags);
    CFRelease(route);
    return known && !(flags & kSCNetworkReachabilityFlagsReachable);
}

static NSString *OVKAudioDownloadURL(NSString *raw) {
    NSURL *url = [NSURL URLWithString:raw];
    if (![@[@"http",@"https"] containsObject:url.scheme.lowercaseString ?: @""]) return nil;
    if ([@[@"mpd",@"m3u8",@"ogg",@"opus",@"flac",@"webm"] containsObject:url.pathExtension.lowercaseString ?: @""]) return nil;
    return raw;
}

static NSMutableDictionary *OVKCacheDownloads(void) {
    static NSMutableDictionary *downloads;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        downloads = [NSMutableDictionary dictionary];
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        for (NSString *name in @[@"OVKSessionChanged",@"OVKLogout"]) {
            [center addObserverForName:name object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
                NSArray *jobs = downloads.allValues;
                [downloads removeAllObjects];
                for (NSDictionary *state in jobs) {
                    id<OVKCancellable> task = state[@"task"];
                    [task cancel];
                }
            }];
        }
    });
    return downloads;
}

static void OVKNotifyCache(NSString *key, BOOL progress) {
    [[NSNotificationCenter defaultCenter] postNotificationName:OVKMusicCacheChanged object:key
                                                      userInfo:progress ? @{@"progress":@YES} : nil];
}

static void OVKDownloadCachedAudio(NSDictionary *item) {
    NSDictionary *params = OVKAudioFavoriteParameters(item);
    NSString *scope = OVKCurrentCacheScope(), *key = OVKAudioFavoriteID(params);
    if (!scope || !key || OVKMusicCacheURL(scope,key)) return;
    NSString *job = [scope stringByAppendingString:key];
    NSMutableDictionary *downloads = OVKCacheDownloads();
    if (downloads[job]) return;
    NSMutableDictionary *state = [@{@"percent":@(-1)} mutableCopy];
    downloads[job] = state;
    OVKNotifyCache(key,YES);
    void (^finish)(NSError *) = ^(NSError *error) {
        if (downloads[job]!=state) return;
        [downloads removeObjectForKey:job];
        OVKNotifyCache(key,NO);
        if (error && [scope isEqualToString:OVKCurrentCacheScope()]) OVKAlert(OVKL(@"Не удалось скачать трек"),error.localizedDescription);
    };
    void (^download)(NSString *) = ^(NSString *address) {
        if (downloads[job]!=state) return;
        if (!address) {
            finish([NSError errorWithDomain:@"OVKMusicCache" code:1 userInfo:@{NSLocalizedDescriptionKey:OVKL(@"Сервер не выдал совместимый аудиофайл.")}]);
            return;
        }
        id<OVKCancellable> task = [OVKMedia download:address limit:256ULL*1024*1024 progress:^(float progress) {
            NSInteger percent = progress < 0 ? -1 : (NSInteger)(progress*100);
            if (downloads[job]!=state || [state[@"percent"] integerValue]==percent) return;
            state[@"percent"] = @(percent);
            OVKNotifyCache(key,YES);
        } completion:^(NSURL *file,NSError *error) {
            if (!error && downloads[job]==state) {
                NSFileHandle *input = [NSFileHandle fileHandleForReadingAtPath:file.path];
                NSData *header = [input readDataOfLength:64];
                [input closeFile];
                const char *format = OVKMediaContainer(header.bytes,header.length);
                NSURL *sourceURL = [NSURL URLWithString:address];
                NSString *suffix = format ? [NSString stringWithUTF8String:format] : sourceURL.pathExtension.lowercaseString;
                if ([suffix isEqualToString:@"mp4"]) suffix = @"m4a";
                if (!OVKStoreMusicCacheFile(scope,key,file,suffix,OVKOfflineAudioMetadata(item),&error) && !error) {
                    error = [NSError errorWithDomain:@"OVKMusicCache" code:2 userInfo:@{NSLocalizedDescriptionKey:OVKL(@"Сервер не выдал совместимый аудиофайл.")}];
                }
            }
            if (file) [[NSFileManager defaultManager] removeItemAtURL:file error:NULL];
            finish(error);
        }];
        if (task && downloads[job]==state) state[@"task"] = task;
    };
    NSString *address = OVKAudioDownloadURL(OVKString(item[@"url"]));
    if (address) { download(address); return; }
    [[OVKAPI shared] call:@"audio.getById" parameters:@{@"audios":key} completion:^(id result,NSError *error) {
        if (error) { finish(error); return; }
        NSArray *items = [result isKindOfClass:[NSArray class]] ? result : OVKArray(OVKDictionary(result)[@"items"]);
        download(OVKAudioDownloadURL(OVKMediaURL(OVKString(OVKDictionary(items.count ? items[0] : nil)[@"url"]))));
    }];
}

static UIImage *OVKMusicHeart(UIColor *color) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(22,20), NO, 0);
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(11,19)];
    [path addCurveToPoint:CGPointMake(1,7) controlPoint1:CGPointMake(8,16) controlPoint2:CGPointMake(1,12)];
    [path addCurveToPoint:CGPointMake(11,4) controlPoint1:CGPointMake(1,1) controlPoint2:CGPointMake(8,-1)];
    [path addCurveToPoint:CGPointMake(21,7) controlPoint1:CGPointMake(14,-1) controlPoint2:CGPointMake(21,1)];
    [path addCurveToPoint:CGPointMake(11,19) controlPoint1:CGPointMake(21,12) controlPoint2:CGPointMake(14,16)];
    [path closePath];
    [color setFill];
    [path fill];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

static NSUInteger OVKImageCacheGeneration=0;
static NSUInteger OVKImageDiskGeneration=0;
static NSURL *OVKImageCacheDirectory(void) {
    NSURL *caches=[[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] lastObject];
    return [caches URLByAppendingPathComponent:@"OpenVKImages-v1" isDirectory:YES];
}
static dispatch_queue_t OVKImageDiskQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue=dispatch_queue_create("org.openvk.mobile.image-disk",DISPATCH_QUEUE_SERIAL); });
    return queue;
}
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
+ (void)clearStoredImageCache {
    [self clearImageCache];
    ++OVKImageDiskGeneration;
    dispatch_async(OVKImageDiskQueue(), ^{ [[NSFileManager defaultManager] removeItemAtURL:OVKImageCacheDirectory() error:NULL]; });
}
+ (void)showCurrentMusicFrom:(UIViewController *)controller { OVKShowCurrentMusic(controller); }
+ (NSDictionary *)nowPlaying { return OVKNowPlayingSnapshot(); }
+ (void)toggleNowPlaying { OVKToggleNowPlaying(); }
+ (void)nextNowPlaying { OVKNextNowPlaying(); }
+ (void)cancelCurrentMusicCacheDownloads {
    NSString *scope = OVKCurrentCacheScope();
    if (!scope) return;
    NSMutableDictionary *downloads = OVKCacheDownloads();
    for (NSString *job in downloads.allKeys) {
        if (![job hasPrefix:scope]) continue;
        id<OVKCancellable> task = downloads[job][@"task"];
        [downloads removeObjectForKey:job];
        [task cancel];
    }
    OVKNotifyCache(nil,NO);
}
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
    static OVKImageRequests *requests; static dispatch_once_t once; dispatch_once(&once, ^{ requests=[[OVKImageRequests alloc] init]; });
    NSUInteger limit=MAX(64,MIN(OVKFullPhotoPixelLimit(),pixels)); NSString *source=OVKMediaURL(url);
    NSString *key=[NSString stringWithFormat:@"%lu:%lu:%@",(unsigned long)OVKImageCacheGeneration,(unsigned long)limit,source];
    return [requests subscribeKey:key loader:^id<OVKCancellable>(OVKSharedImageCompletion done) {
        return [self unsharedImage:source maxPixelSize:limit completion:^(UIImage *image,NSError *error) { done(image,error); }];
    } completion:^(id image,NSError *error) { if (completion) completion(image,error); }];
}
+ (id<OVKCancellable>)unsharedImage:(NSString *)url maxPixelSize:(NSUInteger)pixels completion:(void (^)(UIImage *,NSError *))completion {
    pixels=MAX(64,MIN(OVKFullPhotoPixelLimit(),pixels));
    NSString *source = OVKMediaURL(url);
    NSCache *cache=OVKImageCache(); NSUInteger cacheGeneration=OVKImageCacheGeneration;
    if ([source hasPrefix:@"demo:"]) { UIImage *image = [UIImage imageNamed:[source substringFromIndex:5]]; dispatch_async(dispatch_get_main_queue(), ^{ completion(image,image ? nil : MediaError(8,OVKL(@"Нет демоизображения"))); }); return nil; }
    OVKAPI *api=[OVKAPI shared];
    NSString *scope=OVKMusicCacheScope(api.server,api.userID);
    NSURL *directory=scope && !api.demo ? [OVKImageCacheDirectory() URLByAppendingPathComponent:scope isDirectory:YES] : nil;
    NSURL *diskFile=[directory URLByAppendingPathComponent:OVKCacheHash(source)];
    NSUInteger diskGeneration=OVKImageDiskGeneration;
    NSString *cacheKey=[NSString stringWithFormat:@"%@:%lu:%@",scope ?: @"",(unsigned long)pixels,source];
    UIImage *saved = [cache objectForKey:cacheKey];
    if (saved) { dispatch_async(dispatch_get_main_queue(), ^{ completion(saved,nil); }); return nil; }
    OVKImageTask *ticket=[[OVKImageTask alloc] init];
    void (^decode)(NSURL *,BOOL)=^(NSURL *file,BOOL fromDisk) {
        if (ticket.cancelled) { if (!fromDisk) [[NSFileManager defaultManager] removeItemAtURL:file error:NULL]; return; }
        if (!fromDisk) ticket.file=file;
        NSBlockOperation *operation=[NSBlockOperation blockOperationWithBlock:^{ @autoreleasepool {
            if (ticket.cancelled) return;
            NSDictionary *inputOptions=@{(__bridge id)kCGImageSourceShouldCache:@NO};
            CGImageSourceRef input=CGImageSourceCreateWithURL((__bridge CFURLRef)file,(__bridge CFDictionaryRef)inputOptions); CGImageRef image=NULL;
            if (input) { NSDictionary *options=@{(__bridge id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(__bridge id)kCGImageSourceThumbnailMaxPixelSize:@(pixels),(__bridge id)kCGImageSourceCreateThumbnailWithTransform:@YES,(__bridge id)kCGImageSourceShouldCache:@YES}; image=CGImageSourceCreateThumbnailAtIndex(input,0,(__bridge CFDictionaryRef)options); CFRelease(input); }
            // Decode the small thumbnail on this worker, avoiding first-draw decompression during scrolling.
            CGImageRef ready=NULL;
            if (image && !ticket.cancelled) {
                size_t width=CGImageGetWidth(image),height=CGImageGetHeight(image); CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
                CGContextRef bitmap=CGBitmapContextCreate(NULL,width,height,8,0,space,kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little); CGColorSpaceRelease(space);
                if (bitmap) { CGContextDrawImage(bitmap,CGRectMake(0,0,width,height),image); ready=CGBitmapContextCreateImage(bitmap); CGContextRelease(bitmap); }
            }
            if (image) CGImageRelease(image);
            NSData *stored=nil;
            if (!fromDisk) {
                NSNumber *size=nil;
                if (ready && diskFile && !ticket.cancelled && [file getResourceValue:&size forKey:NSURLFileSizeKey error:NULL] && size.unsignedIntegerValue<=512*1024) {
                    stored=[NSData dataWithContentsOfURL:file];
                }
                [[NSFileManager defaultManager] removeItemAtURL:file error:NULL];
            } else if (!ready && !ticket.cancelled) [[NSFileManager defaultManager] removeItemAtURL:file error:NULL];
            dispatch_async(dispatch_get_main_queue(), ^{
                UIImage *decoded=ready && !ticket.cancelled ? [UIImage imageWithCGImage:ready] : nil;
                if (ready) CGImageRelease(ready);
                ticket.operation=nil; ticket.file=nil; if (ticket.cancelled) return;
                if (!decoded && fromDisk) {
                    ticket.download=[self image:source maxPixelSize:pixels completion:^(UIImage *fresh,NSError *error) {
                        ticket.download=nil;
                        if (!ticket.cancelled) completion(fresh,error);
                    }];
                    return;
                }
                if (stored.length && diskGeneration==OVKImageDiskGeneration) dispatch_async(OVKImageDiskQueue(), ^{
                    NSFileManager *manager=[NSFileManager defaultManager];
                    if (![manager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:NULL]) return;
                    if ([stored writeToURL:diskFile options:NSDataWritingAtomic|NSDataWritingFileProtectionComplete error:NULL]) OVKTrimDiskCache(directory,32*1024*1024,240);
                });
                if (decoded && cacheGeneration==OVKImageCacheGeneration) [cache setObject:decoded forKey:cacheKey cost:CGImageGetWidth(decoded.CGImage)*CGImageGetHeight(decoded.CGImage)*4];
                completion(decoded,decoded ? nil : MediaError(9,OVKL(@"Не удалось прочитать изображение")));
            });
        } }];
        operation.threadPriority=.25; ticket.operation=operation; [OVKImageDecodeQueue() addOperation:operation];
    };
    if (diskFile && [[NSFileManager defaultManager] fileExistsAtPath:diskFile.path]) decode(diskFile,YES);
    else ticket.download=[self download:source limit:20*1024*1024 progress:nil completion:^(NSURL *file,NSError *error) {
        ticket.download=nil;
        if (error) { if (!ticket.cancelled) completion(nil,error); return; }
        decode(file,NO);
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
// Keep orientation notifications active while media is visible (including
// the playback controller). UIKit remains responsible for rotation.
@interface OVKMediaRotationObserver : NSObject
@end
@implementation OVKMediaRotationObserver
- (id)init {
    self=[super init]; if (self) {
        [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deviceTurned:) name:UIDeviceOrientationDidChangeNotification object:nil];
    } return self;
}
- (void)deviceTurned:(NSNotification *)notification {
    UIDeviceOrientation orientation=[UIDevice currentDevice].orientation;
    if (UIDeviceOrientationIsPortrait(orientation) || UIDeviceOrientationIsLandscape(orientation)) dispatch_async(dispatch_get_main_queue(), ^{ [UIViewController attemptRotationToDeviceOrientation]; });
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications]; }
@end
// Keep a separate, correctly named file alive until Photos or the share sheet finishes.
static NSURL *OVKStageExportFile(NSURL *source, BOOL video, BOOL move, NSError **error) {
    NSString *extension=source.pathExtension;
    if (!video) {
        CGImageSourceRef image=CGImageSourceCreateWithURL((__bridge CFURLRef)source,NULL);
        if (image) {
            NSString *type=(__bridge NSString *)CGImageSourceGetType(image);
            NSDictionary *extensions=@{@"public.jpeg":@"jpg",@"public.png":@"png",@"com.compuserve.gif":@"gif",
                                       @"public.tiff":@"tiff",@"com.microsoft.bmp":@"bmp",@"public.heic":@"heic",
                                       @"org.webmproject.webp":@"webp"};
            extension=type ? extensions[type] : nil;
            CFRelease(image);
        }
    }
    if (!extension.length) {
        if (error) *error=MediaError(1,OVKL(@"Не удалось определить формат файла"));
        return nil;
    }
    NSString *identifier=[[NSProcessInfo processInfo] globallyUniqueString];
    NSString *name=[NSString stringWithFormat:@"%@-%@.%@",video ? @"Video" : @"Photo",identifier,extension];
    NSURL *destination=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    NSFileManager *files=[NSFileManager defaultManager];
    if (move) return [files moveItemAtURL:source toURL:destination error:error] ? destination : nil;
    if ([files linkItemAtURL:source toURL:destination error:NULL]) return destination;
    return [files copyItemAtURL:source toURL:destination error:error] ? destination : nil;
}

@interface OVKMediaExportMenu : NSObject <UIActionSheetDelegate,UIPopoverControllerDelegate>
@property (weak, nonatomic) UIViewController *owner;
@property (strong, nonatomic) UIBarButtonItem *anchor;
@property (strong, nonatomic) UIActionSheet *menu;
@property (strong, nonatomic) UIPopoverController *popover;
@property (strong, nonatomic) NSURL *sharedFile;
@property (strong, nonatomic) ALAssetsLibrary *library;
@property (copy, nonatomic) NSString *photoURL;
@property (strong, nonatomic) NSURL *videoURL;
@property (assign, nonatomic) BOOL busy;
- (void)showFrom:(UIViewController *)owner item:(UIBarButtonItem *)item photo:(NSString *)photo video:(NSURL *)video;
@end

@implementation OVKMediaExportMenu
- (void)showFrom:(UIViewController *)owner item:(UIBarButtonItem *)item photo:(NSString *)photo video:(NSURL *)video {
    if (self.menu || self.busy || (!photo.length && !video)) return;
    self.owner=owner; self.anchor=item; self.photoURL=photo; self.videoURL=video;
    self.menu=[[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:OVKL(@"Отмена")
                           destructiveButtonTitle:nil otherButtonTitles:OVKL(@"Сохранить в Галерею"),OVKL(@"Поделиться"),nil];
    [self.menu showFromBarButtonItem:item animated:YES];
}
- (void)actionSheet:(UIActionSheet *)sheet didDismissWithButtonIndex:(NSInteger)index {
    NSString *photo=self.photoURL;
    NSURL *video=self.videoURL;
    self.menu=nil; self.photoURL=nil; self.videoURL=nil;
    if (index!=0 && index!=1) { self.anchor=nil; return; }
    self.busy=YES;
    OVKDownloadCompletion ready=^(NSURL *file,NSError *error) {
        if (!file || !self.owner.view.window) { [self finishFile:file error:error saved:NO]; return; }
        if (index==0) [self saveFile:file video:video!=nil];
        else [self shareFile:file];
    };
    if (video) {
        // Pin the file before leaving the main queue, where playback can discard it.
        NSError *error=nil;
        NSURL *file=OVKStageExportFile(video,YES,NO,&error);
        ready(file,error);
        return;
    }
    NSString *source=OVKMediaURL(photo);
    if ([source hasPrefix:@"demo:"] && ![source pathExtension].length) source=[source stringByAppendingPathExtension:@"png"];
    NSString *scope=OVKCurrentCacheScope();
    NSURL *cached=scope ? [[OVKImageCacheDirectory() URLByAppendingPathComponent:scope isDirectory:YES] URLByAppendingPathComponent:OVKCacheHash(source)] : nil;
    dispatch_async(OVKImageDiskQueue(), ^{
        NSURL *file=cached ? OVKStageExportFile(cached,NO,NO,NULL) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (file) { ready(file,nil); return; }
            if (!self.owner.view.window) { ready(nil,nil); return; }
            [OVKMedia download:source limit:20*1024*1024 progress:nil completion:^(NSURL *download,NSError *downloadError) {
                if (!download) { ready(nil,downloadError); return; }
                dispatch_async(OVKImageDiskQueue(), ^{
                    NSError *error=nil;
                    NSURL *file=OVKStageExportFile(download,NO,YES,&error);
                    if (!file) [[NSFileManager defaultManager] removeItemAtURL:download error:NULL];
                    dispatch_async(dispatch_get_main_queue(), ^{ ready(file,error); });
                });
            }];
        });
    });
}
- (void)finishFile:(NSURL *)file error:(NSError *)error saved:(BOOL)saved {
    if (file) [[NSFileManager defaultManager] removeItemAtURL:file error:NULL];
    self.busy=NO; self.anchor=nil; self.library=nil;
    if (!self.owner.view.window) return;
    if (error) OVKAlert(OVKL(@"Не удалось экспортировать файл"),error.localizedDescription);
    else if (saved) OVKAlert(OVKL(@"Сохранено в Галерее"),nil);
}
- (void)saveFile:(NSURL *)file video:(BOOL)video {
    self.library=[[ALAssetsLibrary alloc] init];
    void (^finished)(NSURL *,NSError *)=^(NSURL *asset,NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self finishFile:file error:error saved:asset!=nil]; });
    };
    if (video) {
        if (![self.library videoAtPathIsCompatibleWithSavedPhotosAlbum:file]) {
            [self finishFile:file error:MediaError(1,OVKL(@"Галерея не поддерживает формат этого видео")) saved:NO];
            return;
        }
        [self.library writeVideoAtPathToSavedPhotosAlbum:file completionBlock:finished];
        return;
    }
    NSError *error=nil;
    NSData *image=[NSData dataWithContentsOfURL:file options:NSDataReadingMappedIfSafe error:&error];
    if (image) [self.library writeImageDataToSavedPhotosAlbum:image metadata:nil completionBlock:finished];
    else [self finishFile:file error:error saved:NO];
}
- (void)shareFile:(NSURL *)file {
    UIViewController *owner=self.owner;
    if (!owner.view.window || owner.presentedViewController) { [self finishFile:file error:nil saved:NO]; return; }
    UIActivityViewController *share=[[UIActivityViewController alloc] initWithActivityItems:@[file] applicationActivities:nil];
    self.sharedFile=file;
    __weak OVKMediaExportMenu *weakSelf=self;
    share.completionHandler=^(NSString *type,BOOL completed) {
        dispatch_async(dispatch_get_main_queue(), ^{
            OVKMediaExportMenu *menu=weakSelf;
            if ([menu.sharedFile isEqual:file]) [menu finishSharing];
            else [[NSFileManager defaultManager] removeItemAtURL:file error:NULL];
        });
    };
    if (UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad) {
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000
        if ([share respondsToSelector:@selector(popoverPresentationController)]) {
            share.popoverPresentationController.barButtonItem=self.anchor;
            [owner presentViewController:share animated:YES completion:nil];
            return;
        }
#endif
        self.popover=[[UIPopoverController alloc] initWithContentViewController:share];
        self.popover.delegate=self;
        [self.popover presentPopoverFromBarButtonItem:self.anchor permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
    } else [owner presentViewController:share animated:YES completion:nil];
}
- (void)finishSharing {
    NSURL *file=self.sharedFile;
    if (!file) return;
    self.sharedFile=nil;
    self.popover.delegate=nil;
    [self.popover dismissPopoverAnimated:YES];
    self.popover=nil;
    [self finishFile:file error:nil saved:NO];
}
- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController { [self finishSharing]; }
- (void)dealloc {
    _menu.delegate=nil;
    if (_menu.visible) [_menu dismissWithClickedButtonIndex:_menu.cancelButtonIndex animated:NO];
    _popover.delegate=nil;
    if (_popover.popoverVisible) [_popover dismissPopoverAnimated:NO];
    if (_popover && _sharedFile) [[NSFileManager defaultManager] removeItemAtURL:_sharedFile error:NULL];
}
@end

@interface OVKPhotoController () <UIScrollViewDelegate,UIGestureRecognizerDelegate>
@property (copy, nonatomic) NSString *url;
@property (strong, nonatomic) OVKMediaRotationObserver *rotationObserver;
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
@property (strong, nonatomic) UIBarButtonItem *photoActions;
@property (strong, nonatomic) OVKMediaExportMenu *exportMenu;
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
    UIBarButtonItem *flex=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil]; self.photoCounter=[[UIBarButtonItem alloc] initWithTitle:self.title style:UIBarButtonItemStylePlain target:nil action:nil]; self.photoCounter.enabled=NO;
    UIBarButtonItem *rightSpace=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    self.photoActions=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(showPhotoActions:)];
    self.photoActions.accessibilityLabel=OVKL(@"Поделиться");
    self.photoTopBar.items=@[done,flex,self.photoCounter,rightSpace,self.photoActions];
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
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; if (!self.rotationObserver) self.rotationObserver=[[OVKMediaRotationObserver alloc] init]; self.photoNavigationWasHidden=self.navigationController.navigationBarHidden; self.photoStatusWasHidden=[UIApplication sharedApplication].statusBarHidden; [self.navigationController setNavigationBarHidden:YES animated:animated]; [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationNone]; }
- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskAllButUpsideDown; }
- (BOOL)prefersStatusBarHidden { return YES; }
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; [UIViewController attemptRotationToDeviceOrientation]; }
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; self.rotationObserver=nil; [self.navigationController setNavigationBarHidden:self.photoNavigationWasHidden animated:animated]; [[UIApplication sharedApplication] setStatusBarHidden:self.photoStatusWasHidden withAnimation:UIStatusBarAnimationNone]; }
- (void)closePhoto { ++self.photoGeneration; [self.task cancel]; self.task=nil; if (self.navigationController.presentingViewController) [self.navigationController dismissViewControllerAnimated:YES completion:^{ [UIViewController attemptRotationToDeviceOrientation]; }]; else [self.navigationController popViewControllerAnimated:YES]; }
- (void)togglePhotoControls { self.photoControlsHidden=!self.photoControlsHidden; self.photoTopBar.hidden=self.photoControlsHidden; self.photoToolbar.hidden=self.photoControlsHidden; }
- (void)loadPhoto {
    NSUInteger generation=++self.photoGeneration; [self.task cancel]; self.task=nil; self.scroll.zoomScale=1; self.photo.image=nil; self.status.hidden=YES; [self.photoSpinner startAnimating];
    self.photoActions.enabled=NO;
    __weak OVKPhotoController *weakSelf = self;
    self.task = [OVKMedia image:self.url maxPixelSize:OVKFullPhotoPixelLimit() completion:^(UIImage *image,NSError *error) {
        OVKPhotoController *page = weakSelf; if (!page || generation!=page.photoGeneration) return; page.task = nil;
        [page.photoSpinner stopAnimating];
        if (!image) { page.status.hidden=NO; page.status.text=error.localizedDescription; return; }
        page.photo.image = image; page.photoActions.enabled=YES; page.status.hidden = YES; page.scroll.zoomScale = 1; [page fitPhoto];
    }];
}
- (void)showPhotoActions:(UIBarButtonItem *)item {
    if (!self.exportMenu) self.exportMenu=[[OVKMediaExportMenu alloc] init];
    [self.exportMenu showFrom:self item:item photo:self.url video:nil];
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
@property (strong, nonatomic) OVKMediaExportMenu *exportMenu;
@property (assign, nonatomic) BOOL temporaryFile;
@property (assign, nonatomic) NSTimeInterval nowPlayingUpdated;
@property (assign, nonatomic) BOOL nowPlayingWasPlaying;
@property (assign, nonatomic) UIBackgroundTaskIdentifier audioTask;
@property (strong, nonatomic) AVPlayer *movie;
@property (strong, nonatomic) AVPlayerLayer *videoLayer;
@property (strong, nonatomic) NSTimer *videoTimer;
@property (strong, nonatomic) UIView *videoControls;
@property (strong, nonatomic) UIButton *videoPlay;
@property (strong, nonatomic) UISlider *videoSeek;
@property (copy, nonatomic) NSString *videoAuthor;
@property (assign, nonatomic) BOOL videoVisible;
@property (assign, nonatomic) BOOL videoAtEnd;
@property (assign, nonatomic) BOOL nowPlayingAvailable;
@property (assign, nonatomic) BOOL publishedPlaying;
@property (assign, nonatomic) BOOL pendingOfflineAlert;
@property (assign, nonatomic) BOOL inlineAudio;
@property (assign, nonatomic) NSInteger inlineProgressSecond;
@property (strong, nonatomic) AVURLAsset *soundAsset;
@property (strong, nonatomic) NSURL *soundFile;
@property (strong, nonatomic) AVAssetExportSession *exporter;
@property (assign, nonatomic) BOOL triedOriginalVideo;
@property (assign, nonatomic) BOOL silentVideo;
@property (assign, nonatomic) BOOL triedAudioConversion;
@property (assign, nonatomic) BOOL containerHasAudio;
@property (strong, nonatomic) OVKMediaRotationObserver *rotationObserver;
@property (assign, nonatomic) BOOL playbackNavigationWasHidden;
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
@property (strong, nonatomic) UIButton *musicFavorite;
@property (strong, nonatomic) NSMutableDictionary *musicFavoriteChanges;
@property (assign, nonatomic) BOOL savingMusicFavorite;
@property (strong, nonatomic) UILabel *musicRepeatOne;
@property (assign, nonatomic) BOOL musicQueueVisible;
@property (assign, nonatomic) NSUInteger renderedMusicModes;
@property (assign, nonatomic) long renderedElapsedSecond;
@property (assign, nonatomic) long renderedRemainingSecond;
@property (assign, nonatomic) BOOL musicPlayConfigured;
@property (assign, nonatomic) BOOL renderedMusicPlaying;
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
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(movieEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(movieFailed:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:nil];
    self.spinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray]; self.spinner.center=CGPointMake(self.view.bounds.size.width/2,178); self.spinner.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin; self.spinner.hidesWhenStopped=YES; [self.view addSubview:self.spinner];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationPausing:) name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationResuming:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioFavoritesChanged:) name:OVKAudioFavoritesChanged object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioInterrupted:) name:AVAudioSessionInterruptionNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(accountLoggedOut:) name:@"OVKSessionChanged" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(accountLoggedOut:) name:@"OVKLogout" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(experimentalChanged:) name:@"OVKExperimentalChanged" object:nil];
    self.status.hidden=YES; self.progress.hidden=YES; self.spinner.activityIndicatorViewStyle=UIActivityIndicatorViewStyleWhite;
    [self resolveAndLoad];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.playbackNavigationWasHidden = self.navigationController.navigationBarHidden;
    [self.navigationController setNavigationBarHidden:NO animated:animated];
    [self.navigationController.navigationBar setBackgroundImage:OVKThemeStretch(@"MusicNavigation") forBarMetrics:UIBarMetricsDefault];
    self.navigationController.navigationBar.barStyle=UIBarStyleBlack;
    if ([self.item[@"type"] isEqualToString:@"video"]) {
        if (!self.rotationObserver) self.rotationObserver=[[OVKMediaRotationObserver alloc] init];
        self.videoVisible=YES;
        if ([UIApplication sharedApplication].applicationState==UIApplicationStateActive) self.videoLayer.player=self.movie;
    }
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [UIViewController attemptRotationToDeviceOrientation];
    UIResponder *responder=(UIResponder *)[UIApplication sharedApplication].delegate;
    [responder becomeFirstResponder];
    if (self.pendingOfflineAlert) {
        self.pendingOfflineAlert=NO;
        OVKAlert(OVKL(@"Музыка"),OVKL(@"Этот трек не загружен в Кэш"));
    }
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.videoVisible=NO;
    self.videoLayer.player=nil;
    self.rotationObserver=nil;
    [self.navigationController setNavigationBarHidden:self.playbackNavigationWasHidden animated:animated];
    self.navigationController.navigationBar.barStyle=UIBarStyleDefault;
    OVKStyleNavigation(self.navigationController);
}
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
- (void)accountLoggedOut:(NSNotification *)note { [self stop]; if (OVKCurrentMusic==self) { OVKCurrentMusic=nil; OVKNotifyNowPlaying(); } }
- (void)experimentalChanged:(NSNotification *)note { if (([self.item[@"type"] isEqualToString:@"audio"] && !OVKString(self.item[@"local_path"]).length && !OVKExperimentalMusic()) || ([self.item[@"type"] isEqualToString:@"video"] && !OVKExperimentalVideo())) [self stop]; }
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
    self.pendingOfflineAlert=NO;
    BOOL isVideo=[self.item[@"type"] isEqualToString:@"video"];
    if (isVideo) { self.triedOriginalVideo=NO; self.silentVideo=NO; self.triedAudioConversion=NO; }
    if (OVKCurrentMusic==self) OVKNotifyNowPlaying();
    if (!isVideo && !self.musicView) [self buildMusicPlayer];
    self.status.hidden=YES; self.progress.hidden=YES; [self.view bringSubviewToFront:self.spinner];
    self.diagnostics=[NSMutableArray array];
    NSString *local=OVKString(self.item[@"local_path"]);
    if (local.length) {
        if (![[NSFileManager defaultManager] fileExistsAtPath:local]) { [self failPlayback:OVKL(@"Локальный файл не найден")]; return; }
        self.localFile=[NSURL fileURLWithPath:local]; self.temporaryFile=NO; [self beginPlayback]; return;
    }
    if (!isVideo) {
        NSString *key = OVKAudioFavoriteID(OVKAudioFavoriteParameters(self.item));
        NSURL *cached = OVKMusicCacheURL(OVKCurrentCacheScope(),key);
        if (cached) {
            NSString *name = [@"ovk-offline-" stringByAppendingString:[[NSProcessInfo processInfo] globallyUniqueString]];
            NSURL *link = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[name stringByAppendingPathExtension:cached.pathExtension]]];
            self.temporaryFile = [[NSFileManager defaultManager] linkItemAtURL:cached toURL:link error:NULL];
            self.localFile = self.temporaryFile ? link : cached;
            [self beginPlayback];
            return;
        }
        BOOL demo = [OVKAPI shared].demo;
        if (!demo && OVKNetworkUnavailable()) { [self unavailableOfflineAudio]; return; }
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
        if (!video && OVKOfflineError(error)) { [page unavailableOfflineAudio]; return; }
        if (error || !url.length) { [page unavailable:error.localizedDescription ?: OVKL(@"Эта запись доступна только через веб-плеер или сервер не выдаёт файл.")]; return; }
        NSMutableDictionary *item = [page.item mutableCopy]; item[@"object"] = media; item[@"url"] = url; page.item = item; [page updateMusicFavorite]; [page loadURL:url];
    }];
}
- (void)unavailableOfflineAudio {
    NSString *message = OVKL(@"Этот трек не загружен в Кэш");
    [self failPlayback:message];
    if (self.view.window) OVKAlert(OVKL(@"Музыка"),message);
    else self.pendingOfflineAlert=YES;
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
        if (error) {
            if (error.code != NSURLErrorCancelled) {
                if ([page.item[@"type"] isEqualToString:@"video"]) [page rejectVideo:error.localizedDescription];
                else if (OVKOfflineError(error)) [page unavailableOfflineAudio];
                else [page failPlayback:error.localizedDescription];
            }
            return;
        }
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
    if (![self.item[@"type"] isEqualToString:@"video"]) {
        if (OVKString(self.item[@"local_path"]).length) [self loadLocalTrackTags:generation];
        [self prepareLocalAudio];
        return;
    }
    // Inspect locally downloaded data asynchronously. No AVAudioPlayer file open/prepare on the UI thread.
    self.asset=[AVURLAsset URLAssetWithURL:self.localFile options:nil];
    NSURL *inspectionFile=self.localFile; AVURLAsset *inspectedAsset=self.asset;
    __weak OVKPlaybackController *weakSelf=self;
    [self.asset loadValuesAsynchronouslyForKeys:@[@"playable",@"tracks",@"duration"] completionHandler:^{
        NSData *bytes=[NSData dataWithContentsOfURL:inspectionFile options:NSDataReadingMappedIfSafe error:NULL];
        OVKMP4AudioInfo raw=OVKInspectMP4Audio(bytes.bytes,bytes.length);
        NSURL *recovered=nil;
        if (raw.audioTracks && (raw.objectType==0x6b || raw.objectType==0x69 ||
            ([inspectedAsset statusOfValueForKey:@"tracks" error:NULL]==AVKeyValueStatusLoaded && ![inspectedAsset tracksWithMediaType:AVMediaTypeAudio].count))) {
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
- (void)loadLocalTrackTags:(NSUInteger)generation {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:self.localFile options:nil];
    __weak OVKPlaybackController *weakSelf = self;
    [asset loadValuesAsynchronouslyForKeys:@[@"commonMetadata"] completionHandler:^{
        if ([asset statusOfValueForKey:@"commonMetadata" error:NULL]!=AVKeyValueStatusLoaded) return;
        NSArray *tags = asset.commonMetadata;
        AVMetadataItem *titleTag = [[AVMetadataItem metadataItemsFromArray:tags withKey:AVMetadataCommonKeyTitle keySpace:AVMetadataKeySpaceCommon] lastObject];
        AVMetadataItem *artistTag = [[AVMetadataItem metadataItemsFromArray:tags withKey:AVMetadataCommonKeyArtist keySpace:AVMetadataKeySpaceCommon] lastObject];
        NSString *title = titleTag.stringValue, *artist = artistTag.stringValue;
        if (!title.length && !artist.length) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            OVKPlaybackController *page = weakSelf;
            if (!page || page.stopped || generation!=page.playbackGeneration) return;
            NSMutableDictionary *updated = [page.item mutableCopy];
            updated[@"object"] = @{@"title":title ?: @"", @"artist":artist ?: @""};
            page.item = updated;
            if (OVKCurrentMusic==page) OVKNotifyNowPlaying();
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
        BOOL openingMiniPlayer = !page.nowPlayingAvailable;
        page.nowPlayingAvailable=YES;
        if (openingMiniPlayer && OVKCurrentMusic==page) OVKNotifyNowPlaying();
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
            if (!audio && OVKVideoAudioURL(OVKDictionary(self.item[@"object"])).length) { [self fetchVideoSound]; return; }
            AVAssetTrack *sound=OVKPreferredVideoAudioTrack(self.asset);
            for (AVAssetTrack *track in [self.asset tracksWithMediaType:AVMediaTypeAudio]) for (id description in track.formatDescriptions) {
                FourCharCode codec=CMFormatDescriptionGetMediaSubType((__bridge CMFormatDescriptionRef)description);
                [self.diagnostics addObject:[NSString stringWithFormat:@"Audio codec %c%c%c%c; enabled=%d",(int)(codec>>24)&255,(int)(codec>>16)&255,(int)(codec>>8)&255,(int)codec&255,track.enabled]];
            }
            if (sound && OVKVideoAudioNeedsConversion(sound) && OVKVideoAudioURL(OVKDictionary(self.item[@"object"])).length) { [self fetchVideoSound]; return; }
            if (sound && (!sound.enabled || sound.preferredVolume<=0 || OVKVideoAudioNeedsConversion(sound))) { [self exportVideoWithSound:self.asset]; return; }
            if (!audio) {
                NSString *message=self.containerHasAudio ? OVKL(@"iOS не распознаёт кодек аудиодорожки") : OVKL(@"iOS не обнаружила аудиодорожку");
                [self.diagnostics addObject:message]; self.navigationItem.prompt=message;
            }
        } else [self.diagnostics addObject:@"Предварительная проверка недоступна; пробуем системный плеер"];
        self.triedOriginalVideo=YES;
        [self prepareVideoPlayerWithAsset:self.asset];
    }
}
- (void)prepareVideoPlayerWithAsset:(AVAsset *)asset {
    if (self.sessionOwner) [self pauseOutputAndReleaseSession];
    [self.videoTimer invalidate]; self.videoTimer=nil;
    [self.movie pause]; self.movie=nil;
    self.videoLayer.player=nil; [self.videoLayer removeFromSuperlayer]; self.videoLayer=nil;
    [self.videoControls removeFromSuperview]; self.videoControls=nil;
    self.started=NO; self.nowPlayingAvailable=NO;
    [self.prepareDeadline invalidate];
    self.prepareDeadline=[NSTimer timerWithTimeInterval:25 target:self selector:@selector(prepareTimedOut) userInfo:nil repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:self.prepareDeadline forMode:NSRunLoopCommonModes];
    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
    self.movie = [AVPlayer playerWithPlayerItem:item];
    BOOL presenting = self.videoVisible && [UIApplication sharedApplication].applicationState==UIApplicationStateActive;
    self.videoLayer = [AVPlayerLayer playerLayerWithPlayer:presenting ? self.movie : nil];
    self.videoLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    [self.view.layer insertSublayer:self.videoLayer atIndex:0];
    self.videoControls = [[UIView alloc] init];
    self.videoControls.backgroundColor = [UIColor colorWithWhite:0 alpha:.75];
    [self.view addSubview:self.videoControls];
    self.videoPlay = [UIButton buttonWithType:UIButtonTypeCustom];
    self.videoPlay.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.videoPlay.imageEdgeInsets = UIEdgeInsetsMake(10,12,10,12);
    [self.videoPlay addTarget:self action:@selector(toggleVideo) forControlEvents:UIControlEventTouchUpInside];
    [self.videoControls addSubview:self.videoPlay];
    self.videoSeek = [[UISlider alloc] init];
    self.videoSeek.continuous = NO;
    [self.videoSeek addTarget:self action:@selector(seekVideo) forControlEvents:UIControlEventValueChanged];
    [self.videoControls addSubview:self.videoSeek];
    self.videoTimer = [NSTimer timerWithTimeInterval:.25 target:self selector:@selector(videoTick) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.videoTimer forMode:NSRunLoopCommonModes];
    self.videoAtEnd=NO;
    [self resolveVideoAuthor];
    [self.view setNeedsLayout];
    [self videoTick];
}
- (void)resolveVideoAuthor {
    if (self.videoAuthor.length) return;
    NSDictionary *video = OVKDictionary(self.item[@"object"]);
    NSString *name = OVKString(video[@"author"]);
    if (name.length) { self.videoAuthor=name; return; }
    long long owner = [OVKString(video[@"owner_id"]) longLongValue];
    if (!owner || ![OVKAPI shared].token.length || [OVKAPI shared].demo) return;
    __weak OVKPlaybackController *weakSelf = self;
    NSDictionary *params = owner>0 ? @{@"user_ids":@(owner)} : @{@"group_id":@(-owner)};
    [[OVKAPI shared] call:owner>0 ? @"users.get" : @"groups.getById" parameters:params completion:^(id result,NSError *error) {
        OVKPlaybackController *page = weakSelf;
        if (!page || page.stopped || error) return;
        NSArray *owners = [result isKindOfClass:[NSArray class]] ? result : OVKArray(OVKDictionary(result)[@"groups"]);
        NSDictionary *profile = OVKDictionary(owners.count ? owners[0] : nil);
        NSString *author = owner>0 ? [NSString stringWithFormat:@"%@ %@",OVKString(profile[@"first_name"]),OVKString(profile[@"last_name"])] : OVKString(profile[@"name"]);
        page.videoAuthor = [author stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (OVKCurrentMusic==page) OVKNotifyNowPlaying();
    }];
}
- (void)videoTick {
    AVPlayerItem *item = self.movie.currentItem;
    if (!item || self.stopped) return;
    if (item.status==AVPlayerItemStatusFailed) {
        [self tryVideoFallback:item.error.localizedDescription ?: OVKL(@"iOS не смогла воспроизвести этот вариант записи.")];
        return;
    }
    BOOL ready = item.status==AVPlayerItemStatusReadyToPlay;
    if (ready && !self.started && (self.wantsPlayback || (!self.nowPlayingAvailable && !self.videoAtEnd))) [self startPreparedPlayback];
    BOOL playing = self.movie.rate>0;
    self.videoPlay.enabled = ready;
    NSString *icon = playing ? @"PauseTrack" : @"PlayTrack";
    [self.videoPlay setImage:[UIImage imageNamed:icon] forState:UIControlStateNormal];
    self.videoPlay.accessibilityLabel = playing ? OVKL(@"Пауза") : OVKL(@"Воспроизвести");
    double duration = CMTimeGetSeconds(item.duration), position = CMTimeGetSeconds(self.movie.currentTime);
    self.videoSeek.enabled = ready && isfinite(duration) && duration>0;
    if (!self.videoSeek.tracking && self.videoSeek.enabled && isfinite(position)) self.videoSeek.value=position/duration;
    [self publishPlayingState];
}
- (void)tryVideoFallback:(NSString *)reason {
    if (reason.length) [self.diagnostics addObject:reason];
    if (self.asset && !self.triedOriginalVideo) {
        self.triedOriginalVideo=YES;
        [self.diagnostics addObject:OVKL(@"Пробуем исходное видео без пересборки")];
        [self prepareVideoPlayerWithAsset:self.asset];
        return;
    }
    if (!self.silentVideo) {
        NSArray *tracks=[self.asset tracksWithMediaType:AVMediaTypeVideo];
        AVAssetTrack *source=tracks.count ? tracks[0] : nil;
        if (source && CMTIMERANGE_IS_VALID(source.timeRange)) {
            AVMutableComposition *composition=[AVMutableComposition composition];
            AVMutableCompositionTrack *track=[composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
            if ([track insertTimeRange:source.timeRange ofTrack:source atTime:kCMTimeZero error:NULL]) {
                track.preferredTransform=source.preferredTransform;
                self.silentVideo=YES;
                self.navigationItem.prompt=OVKL(@"Видео без звука");
                [self.diagnostics addObject:OVKL(@"Видео без звука")];
                [self prepareVideoPlayerWithAsset:composition];
                return;
            }
        }
    }
    [self rejectVideo:reason];
}
- (void)seekVideo {
    double duration = CMTimeGetSeconds(self.movie.currentItem.duration);
    if (!isfinite(duration) || duration<=0) return;
    if (self.videoSeek.value<1) self.videoAtEnd=NO;
    [self.movie seekToTime:CMTimeMakeWithSeconds(duration*self.videoSeek.value,600)];
}
- (void)toggleVideo {
    if (self.movie.currentItem.status!=AVPlayerItemStatusReadyToPlay) return;
    if (self.movie.rate>0 || self.activationPending || self.started) {
        self.wantsPlayback=NO;
        self.started=NO;
        [self pauseOutputAndReleaseSession];
    } else {
        if (self.videoAtEnd) [self.movie seekToTime:kCMTimeZero];
        self.videoAtEnd=NO;
        self.wantsPlayback=YES;
        [self startPreparedPlayback];
    }
    [self publishPlayingState];
}
- (void)publishPlayingState {
    if (OVKCurrentMusic!=self || !self.nowPlayingAvailable) return;
    BOOL playing = self.music ? self.music.playing : self.movie.rate>0;
    if (playing==self.publishedPlaying) return;
    self.publishedPlaying=playing;
    OVKNotifyNowPlaying();
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
        page.started=YES; [page.prepareDeadline invalidate]; page.prepareDeadline=nil; [page.spinner stopAnimating]; page.status.hidden=YES;
        UIBarButtonItem *actions=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:page action:@selector(showVideoActions:)];
        actions.accessibilityLabel=OVKL(@"Поделиться");
        page.navigationItem.rightBarButtonItems=@[actions,[[UIBarButtonItem alloc] initWithTitle:OVKL(@"Сведения") style:UIBarButtonItemStylePlain target:page action:@selector(showVideoInfo)]];
        [page.diagnostics addObject:@"Команда play"];
        BOOL openingMiniPlayer = !page.nowPlayingAvailable;
        page.nowPlayingAvailable=YES;
        [page.movie play];
        if (openingMiniPlayer && OVKCurrentMusic==page) OVKNotifyNowPlaying();
        [page publishPlayingState];
    });
}
- (void)pauseOutputAndReleaseSession {
    NSString *owner=self.sessionOwner; self.sessionOwner=nil; self.activationPending=NO;
    if (self.music) [self.music pauseWithCompletion:^{ OVKDeactivateSession(owner); }];
    else { [self.movie pause]; OVKDeactivateSession(owner); }
}
- (void)pauseForSystem {
    BOOL playing=self.activationPending || (self.music ? self.music.playing : self.movie.rate>0);
    self.wantsPlayback=playing || (!self.started && self.wantsPlayback); self.started=NO;
    [self pauseOutputAndReleaseSession];
    [self publishPlayingState];
}
- (void)applicationPausing:(NSNotification *)note { self.videoLayer.player=nil; }
- (void)applicationResuming:(NSNotification *)note {
    if ([UIApplication sharedApplication].applicationState==UIApplicationStateActive && self.videoVisible) self.videoLayer.player=self.movie;
    if (!self.stopped && self.wantsPlayback) { if (self.music) [self musicReady]; else [self videoTick]; }
}
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
        if (error) { [page tryVideoFallback:error.localizedDescription]; return; }
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
        if ([owner.soundAsset statusOfValueForKey:@"tracks" error:&failure]!=AVKeyValueStatusLoaded || [owner.soundAsset statusOfValueForKey:@"duration" error:&failure]!=AVKeyValueStatusLoaded) { [owner tryVideoFallback:failure.localizedDescription ?: OVKL(@"Не удалось открыть звуковую дорожку")]; return; }
        [owner exportVideoWithSound:owner.soundAsset];
    }); }];
}

- (void)exportVideoWithSound:(AVAsset *)sound {
    AVAssetTrack *audio=OVKPreferredVideoAudioTrack(sound);
    if (!audio) { [self tryVideoFallback:OVKL(@"Не удалось открыть звуковую дорожку")]; return; }
    if (!OVKVideoAudioNeedsConversion(audio) || self.triedAudioConversion) {
        NSError *failure=nil;
        AVMutableComposition *composition=OVKVideoComposition(self.asset,sound,&failure);
        if (!composition) { [self tryVideoFallback:failure.localizedDescription]; return; }
        [self.diagnostics addObject:OVKL(@"Воспроизводим видео с отдельной звуковой дорожкой")];
        [self prepareVideoPlayerWithAsset:composition];
        return;
    }
    self.triedAudioConversion=YES;
    self.exporter=[[AVAssetExportSession alloc] initWithAsset:sound presetName:AVAssetExportPresetAppleM4A];
    if (![self.exporter.supportedFileTypes containsObject:AVFileTypeAppleM4A]) {
        self.exporter=nil;
        [self tryVideoFallback:OVKL(@"Не удалось преобразовать звуковую дорожку")];
        return;
    }
    [self.prepareDeadline invalidate];
    self.prepareDeadline=[NSTimer timerWithTimeInterval:90 target:self selector:@selector(prepareTimedOut) userInfo:nil repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:self.prepareDeadline forMode:NSRunLoopCommonModes];
    NSString *name=[NSString stringWithFormat:@"ovk-sound-%@.m4a",[[NSProcessInfo processInfo] globallyUniqueString]];
    NSURL *converted=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    self.exporter.outputURL=converted; self.exporter.outputFileType=AVFileTypeAppleM4A;
    [self.diagnostics addObject:OVKL(@"Преобразуем отдельно звук в AAC")];
    AVAssetExportSession *session=self.exporter;
    NSUInteger generation=self.playbackGeneration;
    __weak OVKPlaybackController *weakSelf=self;
    [session exportAsynchronouslyWithCompletionHandler:^{ dispatch_async(dispatch_get_main_queue(), ^{
        OVKPlaybackController *page=weakSelf;
        if (!page || page.stopped || generation!=page.playbackGeneration || page.exporter!=session) {
            [[NSFileManager defaultManager] removeItemAtURL:converted error:NULL];
            return;
        }
        page.exporter=nil;
        if (session.status!=AVAssetExportSessionStatusCompleted) {
            [[NSFileManager defaultManager] removeItemAtURL:converted error:NULL];
            [page tryVideoFallback:session.error.localizedDescription ?: OVKL(@"Не удалось преобразовать звуковую дорожку")];
            return;
        }
        if (page.soundFile) [[NSFileManager defaultManager] removeItemAtURL:page.soundFile error:NULL];
        [page prepareVideoSoundFile:converted];
    }); }];
}

- (void)loadNextVideo {
    self.triedAudioConversion=NO; self.triedOriginalVideo=NO; self.silentVideo=NO; self.navigationItem.prompt=nil;
    if (self.stopped) return;
    if (self.candidateIndex>=self.videoURLs.count) { [self failPlayback:OVKL(@"Не удалось открыть вариант видео со звуком. Нажмите «Сведения», чтобы посмотреть результат проверки.")]; return; }
    NSString *url=self.videoURLs[self.candidateIndex++]; [self loadURL:url];
}
- (void)rejectVideo:(NSString *)reason {
    self.nowPlayingAvailable=NO;
    if (OVKCurrentMusic==self) OVKNotifyNowPlaying();
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
    [queue setBackgroundImage:OVKThemeStretch(@"MusicButton") forState:UIControlStateNormal barMetrics:UIBarMetricsDefault]; [queue setBackgroundImage:OVKThemeStretch(@"MusicButtonPressed") forState:UIControlStateHighlighted barMetrics:UIBarMetricsDefault];
    self.navigationItem.rightBarButtonItem=queue;
}
- (void)buildMusicPlayer {
    if (self.musicView) { [self updateMusicModes]; [self musicReady]; return; }
    self.renderedMusicModes=NSUIntegerMax; self.renderedElapsedSecond=-1; self.renderedRemainingSecond=-2; self.musicPlayConfigured=NO;
    if (!self.queue.count) { self.queue=@[self.item]; self.queueIndex=0; }
    self.musicView=[[UIView alloc] initWithFrame:self.view.bounds]; self.musicView.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; self.musicView.backgroundColor=[UIColor blackColor]; [self.view addSubview:self.musicView];
    self.musicTimeline=[[UIImageView alloc] initWithImage:OVKThemeStretch(@"MusicPanel")]; self.musicTimeline.userInteractionEnabled=YES; [self.musicView addSubview:self.musicTimeline];
    self.musicQueueLabel=[[UILabel alloc] init]; self.musicTime=[[UILabel alloc] init]; self.musicRemaining=[[UILabel alloc] init];
    for (UILabel *label in @[self.musicQueueLabel,self.musicTime,self.musicRemaining]) { label.backgroundColor=[UIColor clearColor]; label.textColor=[UIColor whiteColor]; label.font=[UIFont boldSystemFontOfSize:12]; label.textAlignment=NSTextAlignmentCenter; [self.musicTimeline addSubview:label]; }
    self.musicQueueLabel.text=[NSString stringWithFormat:OVKL(@"%lu из %lu"),(unsigned long)(self.queueIndex+1),(unsigned long)self.queue.count];
    self.musicSeek=[[UISlider alloc] init]; self.musicSeek.continuous=NO; [self.musicSeek addTarget:self action:@selector(seekMusic) forControlEvents:UIControlEventValueChanged]; [self.musicTimeline addSubview:self.musicSeek];
    self.musicRepeat=[UIButton buttonWithType:UIButtonTypeCustom]; [self.musicRepeat addTarget:self action:@selector(toggleRepeat) forControlEvents:UIControlEventTouchUpInside]; [self.musicTimeline addSubview:self.musicRepeat];
    self.musicShuffle=[UIButton buttonWithType:UIButtonTypeCustom]; [self.musicShuffle addTarget:self action:@selector(toggleShuffle) forControlEvents:UIControlEventTouchUpInside]; [self.musicTimeline addSubview:self.musicShuffle];
    self.musicFavorite = [UIButton buttonWithType:UIButtonTypeCustom];
    self.musicFavorite.adjustsImageWhenDisabled = NO;
    static UIImage *emptyHeart, *filledHeart;
    static dispatch_once_t heartOnce;
    dispatch_once(&heartOnce, ^{
        emptyHeart = OVKMusicHeart([UIColor colorWithWhite:.58 alpha:1]);
        filledHeart = OVKMusicHeart([UIColor colorWithRed:.91 green:.24 blue:.30 alpha:1]);
    });
    [self.musicFavorite setImage:emptyHeart forState:UIControlStateNormal];
    [self.musicFavorite setImage:filledHeart forState:UIControlStateSelected];
    [self.musicFavorite setImage:filledHeart forState:UIControlStateSelected|UIControlStateHighlighted];
    [self.musicFavorite setImage:filledHeart forState:UIControlStateSelected|UIControlStateDisabled];
    [self.musicFavorite addTarget:self action:@selector(toggleMusicFavorite) forControlEvents:UIControlEventTouchUpInside];
    [self.musicTimeline addSubview:self.musicFavorite];
    [self updateMusicFavorite];
    self.musicRepeatOne=[[UILabel alloc] initWithFrame:CGRectMake(31,2,10,12)]; self.musicRepeatOne.text=@"1"; self.musicRepeatOne.textColor=[UIColor whiteColor]; self.musicRepeatOne.backgroundColor=[UIColor clearColor]; self.musicRepeatOne.font=[UIFont boldSystemFontOfSize:10]; [self.musicRepeat addSubview:self.musicRepeatOne];
    self.musicCover=[[OVKRemoteImageView alloc] initWithImage:[UIImage imageNamed:@"MusicCover"]]; self.musicCover.contentMode=UIViewContentModeScaleAspectFit; [self.musicView addSubview:self.musicCover];
    NSDictionary *object=OVKDictionary(self.item[@"object"]),*album=OVKDictionary(object[@"album"]);
    CGFloat titleWidth=MAX(90,MIN(280,self.view.bounds.size.width-170)); UIView *heading=[[UIView alloc] initWithFrame:CGRectMake(0,0,titleWidth,40)];
    NSArray *lines=@[OVKString(object[@"artist"]),OVKString(object[@"title"]).length ? OVKString(object[@"title"]) : self.title,OVKString(album[@"title"])];
    for (NSUInteger i=0;i<3;i++) { UILabel *line=[[UILabel alloc] initWithFrame:CGRectMake(0,i*13,titleWidth,13)]; line.autoresizingMask=UIViewAutoresizingFlexibleWidth; line.text=lines[i]; line.font=i==1 ? [UIFont boldSystemFontOfSize:12] : [UIFont systemFontOfSize:11]; line.textColor=i==1 ? [UIColor whiteColor] : [UIColor lightGrayColor]; line.backgroundColor=[UIColor clearColor]; line.textAlignment=NSTextAlignmentCenter; [heading addSubview:line]; } self.navigationItem.titleView=heading;
    NSString *coverURL=OVKPhotoSource(OVKDictionary(album[@"thumb"])); if (coverURL.length) [self.musicCover load:coverURL];
    self.musicQueueTable=[[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain]; self.musicQueueTable.delegate=self; self.musicQueueTable.dataSource=self; self.musicQueueTable.rowHeight=48; self.musicQueueTable.backgroundColor=[UIColor colorWithWhite:.16 alpha:1]; self.musicQueueTable.separatorColor=[UIColor colorWithWhite:.28 alpha:1]; self.musicQueueTable.tableFooterView=[[UIView alloc] initWithFrame:CGRectZero]; [self.musicView addSubview:self.musicQueueTable];
    self.musicQueueTable.allowsSelectionDuringEditing=YES;
    [self.musicQueueTable setEditing:YES animated:NO];
    self.musicTransport=[[UIImageView alloc] initWithImage:OVKThemeStretch(@"MusicPanel")]; self.musicTransport.userInteractionEnabled=YES; [self.musicView addSubview:self.musicTransport];
    NSMutableArray *buttons=[NSMutableArray array];
    for (NSUInteger i=0;i<3;i++) { UIButton *button=[UIButton buttonWithType:UIButtonTypeCustom]; [button setImage:[UIImage imageNamed:@[@"PreviousTrack",@"PauseTrack",@"NextTrack"][i]] forState:UIControlStateNormal]; button.accessibilityLabel=@[OVKL(@"Предыдущий трек"),OVKL(@"Пауза"),OVKL(@"Следующий трек")][i]; if (i==1) { self.musicPlay=button; [button addTarget:self action:@selector(toggleMusic) forControlEvents:UIControlEventTouchUpInside]; } else { button.tag=i==0 ? -1 : 1; [button addTarget:self action:@selector(changeTrack:) forControlEvents:UIControlEventTouchUpInside]; } [self.musicTransport addSubview:button]; [buttons addObject:button]; } self.musicButtons=buttons;
    self.musicRoute=[[MPVolumeView alloc] init]; self.musicRoute.showsVolumeSlider=NO; self.musicRoute.showsRouteButton=YES; [self.musicTimeline addSubview:self.musicRoute];
    self.musicVolume=[[MPVolumeView alloc] init]; self.musicVolume.showsRouteButton=NO; [self.musicTransport addSubview:self.musicVolume];
    self.musicTimer=[NSTimer timerWithTimeInterval:OVKLowMemoryDevice() ? .5 : .3 target:self selector:@selector(refreshLocalAudio) userInfo:nil repeats:YES]; [[NSRunLoop mainRunLoop] addTimer:self.musicTimer forMode:NSRunLoopCommonModes];
    [self configureMusicNavigation]; [self updateMusicModes]; [self.view setNeedsLayout]; [self musicReady];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.spinner.center=CGPointMake(self.view.bounds.size.width/2,self.view.bounds.size.height/2);
    if (self.videoLayer) {
        CGRect bounds = self.view.bounds;
        self.videoLayer.frame = bounds;
        self.videoControls.frame = CGRectMake(0,MAX(0,bounds.size.height-50),bounds.size.width,50);
        self.videoPlay.frame = CGRectMake(0,0,50,50);
        self.videoSeek.frame = CGRectMake(58,0,MAX(0,bounds.size.width-72),50);
    }
    if (!self.musicView) return;
    CGFloat width=self.view.bounds.size.width,height=self.view.bounds.size.height; BOOL pad=UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad;
    OVKMusicLayout layout=OVKMusicPlayerLayout(width,height,pad,self.musicQueueVisible);
    self.musicView.frame=self.view.bounds;
    self.musicTimeline.frame=CGRectMake(layout.timeline.x,layout.timeline.y,layout.timeline.width,layout.timeline.height);
    self.musicCover.frame=CGRectMake(layout.cover.x,layout.cover.y,layout.cover.width,layout.cover.height); self.musicCover.hidden=!layout.showCover;
    self.musicQueueTable.frame=CGRectMake(layout.queue.x,layout.queue.y,layout.queue.width,layout.queue.height); self.musicQueueTable.hidden=!layout.showQueue;
    self.musicTransport.frame=CGRectMake(layout.transport.x,layout.transport.y,layout.transport.width,layout.transport.height);
    self.musicQueueLabel.frame=CGRectMake(60,4,width-120,20); self.musicTime.frame=CGRectMake(10,28,52,24); self.musicRemaining.frame=CGRectMake(width-64,28,54,24); self.musicSeek.frame=CGRectMake(70,26,width-140,28);
    self.musicFavorite.frame=CGRectMake(width/2-22,53,44,30);
    self.musicRoute.frame=CGRectMake(width/2+26,53,44,30);
    self.musicRepeat.frame=CGRectMake(10,53,44,30); self.musicShuffle.frame=CGRectMake(width-54,53,44,30);
    for (NSUInteger i=0;i<self.musicButtons.count;i++) ((UIButton *)self.musicButtons[i]).frame=CGRectMake(width/2-32+((NSInteger)i-1)*96,4,64,52);
    CGFloat volumeWidth=MIN(560,width-40); self.musicVolume.frame=CGRectMake((width-volumeWidth)/2,64,volumeWidth,28);
}
- (void)toggleMusicQueue { self.musicQueueVisible=!self.musicQueueVisible; [self configureMusicNavigation]; [self.view setNeedsLayout]; if (self.musicQueueVisible && self.queueIndex<self.queue.count) [self.musicQueueTable scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:self.queueIndex inSection:0] atScrollPosition:UITableViewScrollPositionMiddle animated:NO]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.queue.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"music-queue"]; if (!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"music-queue"];
    cell.showsReorderControl=self.queue.count>1;
    NSDictionary *item=OVKDictionary(self.queue[path.row]),*object=OVKDictionary(item[@"object"]); cell.textLabel.text=OVKString(object[@"title"]).length ? OVKString(object[@"title"]) : OVKString(item[@"title"]); cell.textLabel.font=[UIFont systemFontOfSize:15]; cell.textLabel.textColor=path.row==self.queueIndex ? [UIColor colorWithRed:.4 green:.7 blue:1 alpha:1] : [UIColor whiteColor]; cell.detailTextLabel.text=OVKString(OVKDictionary(item[@"object"])[@"artist"]); cell.detailTextLabel.textColor=[UIColor lightGrayColor]; cell.backgroundColor=[UIColor colorWithWhite:path.row==self.queueIndex ? .23 : .16 alpha:1]; cell.contentView.backgroundColor=cell.backgroundColor; cell.accessoryType=UITableViewCellAccessoryNone; cell.indentationWidth=16; cell.indentationLevel=2;
    UILabel *number=(UILabel *)[cell.contentView viewWithTag:3201]; if (!number) { number=[[UILabel alloc] initWithFrame:CGRectMake(5,0,30,48)]; number.tag=3201; number.backgroundColor=[UIColor clearColor]; number.textAlignment=NSTextAlignmentCenter; number.font=[UIFont boldSystemFontOfSize:14]; [cell.contentView addSubview:number]; } number.text=path.row==self.queueIndex ? (self.music.playing ? @"▶" : @"II") : [NSString stringWithFormat:@"%ld",(long)path.row+1]; number.textColor=cell.textLabel.textColor; return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path { [tableView deselectRowAtIndexPath:path animated:YES]; if (self.musicPrepared && (NSUInteger)path.row!=self.queueIndex) [self playQueueIndex:path.row]; }
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)path { return UITableViewCellEditingStyleNone; }
- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)path { return NO; }
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)path { return self.queue.count>1; }
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    NSUInteger source=from.row, destination=to.row;
    if (source==destination || source>=self.queue.count || destination>=self.queue.count) return;
    NSMutableArray *order = [self.queue mutableCopy];
    id track = order[source];
    [order removeObjectAtIndex:source];
    [order insertObject:track atIndex:destination];
    if (self.queueIndex==source) self.queueIndex=destination;
    else if (source<self.queueIndex && destination>=self.queueIndex) self.queueIndex--;
    else if (source>self.queueIndex && destination<=self.queueIndex) self.queueIndex++;
    self.queue=order;
    self.playOrder=nil;
    self.musicQueueLabel.text=[NSString stringWithFormat:OVKL(@"%lu из %lu"),(unsigned long)(self.queueIndex+1),(unsigned long)self.queue.count];
    [self updateMusicModes];
    [self performSelector:@selector(reloadQueuePositions) withObject:nil afterDelay:0];
    OVKNotifyNowPlaying();
}
- (void)reloadQueuePositions { [self.musicQueueTable reloadData]; }
- (void)toggleRepeat { self.repeatMode=(self.repeatMode+1)%3; [self updateMusicModes]; OVKNotifyNowPlaying(); }
- (void)toggleShuffle { self.shuffleEnabled=!self.shuffleEnabled; self.playOrder=nil; [self updateMusicModes]; OVKNotifyNowPlaying(); }
- (BOOL)musicIsFavorite {
    NSString *path = OVKString(self.item[@"local_path"]);
    if (path.length) return OVKLocalMusicIsFavorite(path);
    NSString *identifier = OVKAudioFavoriteID(OVKAudioFavoriteParameters(self.item));
    NSNumber *changed = identifier ? self.musicFavoriteChanges[identifier] : nil;
    return changed ? changed.boolValue : [OVKString(OVKDictionary(self.item[@"object"])[@"added"]) boolValue];
}
- (void)updateMusicFavorite {
    if (!self.musicFavorite) return;
    OVKAPI *api = [OVKAPI shared];
    BOOL local = OVKString(self.item[@"local_path"]).length > 0;
    BOOL canSave = local || (api.token.length && !api.demo && OVKAudioFavoriteParameters(self.item));
    BOOL favorite = [self musicIsFavorite];
    self.musicFavorite.selected = favorite;
    self.musicFavorite.enabled = canSave && !self.savingMusicFavorite;
    self.musicFavorite.alpha = canSave ? 1 : .5;
    self.musicFavorite.accessibilityLabel = favorite ? OVKL(@"Убрать из избранного") : OVKL(@"Добавить в избранное");
}
- (void)audioFavoritesChanged:(NSNotification *)note {
    if (!self.musicFavoriteChanges) self.musicFavoriteChanges = [NSMutableDictionary dictionary];
    self.musicFavoriteChanges[note.object] = note.userInfo[@"favorite"];
    [self updateMusicFavorite];
}
- (void)toggleMusicFavorite {
    if (!self.musicFavorite.enabled) return;
    BOOL favorite = ![self musicIsFavorite];
    NSString *path = OVKString(self.item[@"local_path"]);
    if (path.length) {
        OVKSetLocalMusicFavorite(path, favorite);
        [self updateMusicFavorite];
        return;
    }
    NSDictionary *parameters = OVKAudioFavoriteParameters(self.item);
    NSString *identifier = OVKAudioFavoriteID(parameters);
    if (!identifier) return;
    self.savingMusicFavorite = YES;
    [self updateMusicFavorite];
    __weak OVKPlaybackController *weakSelf = self;
    [[OVKAPI shared] call:favorite ? @"audio.add" : @"audio.delete" parameters:parameters completion:^(id result, NSError *error) {
        OVKPlaybackController *page = weakSelf;
        page.savingMusicFavorite = NO;
        if (error) {
            [page updateMusicFavorite];
            if (page.view.window) OVKAlert(OVKL(@"Не удалось изменить избранное"), error.localizedDescription);
            return;
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:OVKAudioFavoritesChanged object:identifier
                                                          userInfo:@{@"favorite":@(favorite)}];
    }];
}
- (NSArray *)orderedQueue {
    if (!self.shuffleEnabled) return nil;
    if (self.playOrder.count!=self.queue.count) { NSMutableArray *order=[NSMutableArray arrayWithObject:@(self.queueIndex)]; NSMutableArray *rest=[NSMutableArray array]; for (NSUInteger i=0;i<self.queue.count;i++) if (i!=self.queueIndex) [rest addObject:@(i)]; for (NSUInteger n=rest.count;n>1;n--) [rest exchangeObjectAtIndex:n-1 withObjectAtIndex:arc4random_uniform((uint32_t)n)]; [order addObjectsFromArray:rest]; self.playOrder=order; } return self.playOrder;
}
- (NSInteger)nextMusicIndex:(NSInteger)direction automatic:(BOOL)automatic {
    NSArray *order=[self orderedQueue]; NSUInteger position=order ? [order indexOfObject:@(self.queueIndex)] : self.queueIndex; if (position==NSNotFound) return -1;
    long next=OVKMusicNextPosition(self.queue.count,position,(int)direction,(int)self.repeatMode,automatic); if (next<0) return -1; return order ? [order[next] integerValue] : next;
}
- (void)updateMusicModes {
    BOOL previousEnabled=self.musicPrepared && (self.musicPosition>3 || [self nextMusicIndex:-1 automatic:NO]>=0);
    BOOL nextEnabled=self.musicPrepared && [self nextMusicIndex:1 automatic:NO]>=0;
    NSUInteger modes=(self.musicPrepared ? 1 : 0) | ((NSUInteger)self.repeatMode<<1) | (self.shuffleEnabled ? 8 : 0) | (previousEnabled ? 16 : 0) | (nextEnabled ? 32 : 0);
    if (self.renderedMusicModes==modes) return; self.renderedMusicModes=modes;
    self.musicPlay.enabled=self.musicPrepared; self.musicSeek.enabled=self.musicPrepared;
    [self.musicRepeat setImage:[UIImage imageNamed:self.repeatMode ? @"MusicRepeatActive" : @"MusicRepeat"] forState:UIControlStateNormal]; self.musicRepeatOne.hidden=self.repeatMode!=2; self.musicRepeat.accessibilityLabel=OVKL(@"Повтор"); self.musicRepeat.accessibilityValue=@[OVKL(@"Выключен"),OVKL(@"Вся очередь"),OVKL(@"Один трек")][self.repeatMode];
    [self.musicShuffle setImage:[UIImage imageNamed:self.shuffleEnabled ? @"MusicShuffleActive" : @"MusicShuffle"] forState:UIControlStateNormal]; self.musicShuffle.accessibilityLabel=OVKL(@"Перемешать"); self.musicShuffle.accessibilityValue=self.shuffleEnabled ? OVKL(@"Включено") : OVKL(@"Выключен");
    if (self.musicButtons.count==3) { UIButton *previous=self.musicButtons[0],*next=self.musicButtons[2]; previous.enabled=previousEnabled; next.enabled=nextEnabled; previous.alpha=previous.enabled ? 1 : .3; next.alpha=next.enabled ? 1 : .3; }
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
        self.nowPlayingAvailable=NO;
        self.publishedPlaying=NO;
        OVKNotifyNowPlaying();
    }
    [self publishPlayingState];
    self.musicPosition=self.music.currentTime; self.musicDuration=self.music.duration;
    // Update all visible inline controls from this one playback clock, even when the full player is offscreen.
    NSInteger second=isfinite(self.musicPosition) ? (NSInteger)self.musicPosition : 0;
    if (OVKCurrentMusic==self && self.musicPrepared && second!=self.inlineProgressSecond) {
        self.inlineProgressSecond=second;
        [[NSNotificationCenter defaultCenter] postNotificationName:OVKInlineAudioProgressChanged object:nil];
    }
    if (!self.view.window) { [self updateNowPlaying]; return; }
    double now=self.musicPosition, total=self.musicDuration; if (!isfinite(now)) now=0; if (!isfinite(total) || total<=0) total=0;
    if (!self.musicSeek.tracking) self.musicSeek.value=total>0 ? now/total : 0;
    long elapsed=(long)now, remaining=total>0 ? (long)ceil(MAX(0,total-now)) : -1;
    if (self.renderedElapsedSecond!=elapsed) { self.renderedElapsedSecond=elapsed; self.musicTime.text=[NSString stringWithFormat:@"%ld:%02ld",elapsed/60,elapsed%60]; }
    if (self.renderedRemainingSecond!=remaining) { self.renderedRemainingSecond=remaining; self.musicRemaining.text=remaining>=0 ? [NSString stringWithFormat:@"−%ld:%02ld",remaining/60,remaining%60] : @"−–:––"; }
    [self updateMusicModes];
    if (!self.musicPlayConfigured || self.renderedMusicPlaying!=self.music.playing) {
        self.musicPlayConfigured=YES; self.renderedMusicPlaying=self.music.playing;
        UITableViewCell *current=[self.musicQueueTable cellForRowAtIndexPath:[NSIndexPath indexPathForRow:self.queueIndex inSection:0]]; ((UILabel *)[current.contentView viewWithTag:3201]).text=self.music.playing ? @"▶" : @"II";
        [self.musicPlay setImage:[UIImage imageNamed:self.music.playing ? @"PauseTrack" : @"PlayTrack"] forState:UIControlStateNormal]; self.musicPlay.accessibilityLabel=self.music.playing ? OVKL(@"Пауза") : OVKL(@"Воспроизвести");
    } [self updateNowPlaying];
}
- (void)changeTrack:(UIButton *)sender { if (sender.tag<0 && self.musicPosition>3) { [self.music seek:0]; return; } [self playQueueIndex:[self nextMusicIndex:sender.tag automatic:NO]]; }
- (void)prepareTimedOut {
    if ([self.item[@"type"] isEqualToString:@"video"]) {
        [self.exporter cancelExport]; self.exporter=nil;
        [self tryVideoFallback:OVKL(@"Истекло время подготовки варианта видео")];
    } else [self failPlayback:OVKL(@"Проигрыватель не смог подготовить запись за 25 секунд. Нажмите обновление, чтобы повторить.")];
}
- (void)releasePlayer {
    ++self.playbackGeneration; self.nowPlayingUpdated=0; [self endAudioTask]; [self.prepareDeadline invalidate];
    [self.musicTimer invalidate]; self.musicTimer=nil;
    OVKLocalAudio *audio=self.music; NSString *owner=self.sessionOwner;
    [audio stopWithCompletion:^{ OVKDeactivateSession(owner); }]; self.music=nil; self.musicPrepared=NO; [self.musicView removeFromSuperview]; self.musicView=nil; self.musicQueueTable.dataSource=nil; self.musicQueueTable.delegate=nil; self.musicQueueTable=nil; self.musicTimeline=nil; self.musicTransport=nil; self.musicCover=nil; self.musicVolume=nil; self.musicRoute=nil; self.musicButtons=nil; self.musicRepeat=nil; self.musicShuffle=nil; self.musicFavorite=nil; self.musicRepeatOne=nil; self.musicQueueLabel=nil; self.musicRemaining=nil; self.musicTime=nil; self.musicSeek=nil; self.musicPlay=nil; self.prepareDeadline=nil;
    [self.exporter cancelExport]; self.exporter=nil; [self.soundAsset cancelLoading]; self.soundAsset=nil;
    if (self.soundFile) [[NSFileManager defaultManager] removeItemAtURL:self.soundFile error:NULL]; self.soundFile=nil;
    [self.asset cancelLoading]; self.asset=nil; self.started=NO;
    [self.videoTimer invalidate]; self.videoTimer=nil;
    [self.movie pause]; self.movie=nil;
    self.videoLayer.player=nil; [self.videoLayer removeFromSuperlayer]; self.videoLayer=nil;
    [self.videoControls removeFromSuperview]; self.videoControls=nil; self.videoPlay=nil; self.videoSeek=nil;
    if (!audio) OVKDeactivateSession(self.sessionOwner); self.sessionOwner=nil; self.activationPending=NO; self.wantsPlayback=NO;
    self.publishedPlaying=NO;
    self.inlineProgressSecond=-1;
    if (OVKCurrentMusic==self) { MPNowPlayingInfoCenter *center=[MPNowPlayingInfoCenter defaultCenter]; center.nowPlayingInfo=nil; }
}
- (void)failPlayback:(NSString *)message {
    if ([self.item[@"type"] isEqualToString:@"video"]) [self.navigationController setNavigationBarHidden:NO animated:NO];
    [self releasePlayer]; [self.spinner stopAnimating]; self.progress.hidden=YES; self.status.hidden=NO; self.status.text=message;
    self.nowPlayingAvailable=NO;
    if (OVKCurrentMusic==self) OVKNotifyNowPlaying();
    if (self.inlineAudio && !self.view.window && [UIApplication sharedApplication].applicationState==UIApplicationStateActive) OVKAlert(OVKL(@"Музыка"),message);
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(resolveAndLoad)];
    if ([self.item[@"type"] isEqualToString:@"video"]) self.navigationItem.rightBarButtonItems=@[self.navigationItem.rightBarButtonItem,[[UIBarButtonItem alloc] initWithTitle:OVKL(@"Сведения") style:UIBarButtonItemStylePlain target:self action:@selector(showVideoInfo)]];
}
- (void)showVideoActions:(UIBarButtonItem *)item {
    if (!self.exportMenu) self.exportMenu=[[OVKMediaExportMenu alloc] init];
    [self.exportMenu showFrom:self item:item photo:nil video:self.localFile];
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
    NSString *state=self.music ? [NSString stringWithFormat:@"AVAudioPlayer playing=%d, time=%.2f/%.2f",self.music.playing,self.musicPosition,self.musicDuration] : [NSString stringWithFormat:@"AVPlayer status=%ld, rate=%.2f",(long)self.movie.currentItem.status,self.movie.rate];
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
- (void)movieEnded:(NSNotification *)note {
    if (![NSThread isMainThread]) { __weak OVKPlaybackController *weakSelf=self; dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf movieEnded:note]; }); return; }
    if (note.object!=self.movie.currentItem || self.stopped) return;
    self.videoAtEnd=YES; self.started=NO; self.wantsPlayback=NO; self.nowPlayingAvailable=NO;
    [self pauseOutputAndReleaseSession];
    [self videoTick];
    if (OVKCurrentMusic==self) OVKNotifyNowPlaying();
}
- (void)movieFailed:(NSNotification *)note {
    if (![NSThread isMainThread]) { __weak OVKPlaybackController *weakSelf=self; dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf movieFailed:note]; }); return; }
    if (note.object!=self.movie.currentItem || self.stopped) return;
    NSError *error=note.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey];
    [self tryVideoFallback:error.localizedDescription ?: OVKL(@"iOS не смогла воспроизвести этот вариант записи.")];
}
- (void)stop {
    self.rotationObserver=nil;
    self.stopped=YES; self.nowPlayingAvailable=NO;
    [self.task cancel]; self.task=nil;
    [self releasePlayer]; [self clearPlaybackFile]; [self.spinner stopAnimating];
    if (OVKCurrentMusic==self) OVKNotifyNowPlaying();
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; [_task cancel]; [_prepareDeadline invalidate]; [_asset cancelLoading]; [_soundAsset cancelLoading]; [_exporter cancelExport]; if (_soundFile) [[NSFileManager defaultManager] removeItemAtURL:_soundFile error:NULL]; [_musicTimer invalidate]; [_videoTimer invalidate]; NSString *owner=_sessionOwner; if (_music) [_music stopWithCompletion:^{ OVKDeactivateSession(owner); }]; else OVKDeactivateSession(owner); [_movie pause]; if (_temporaryFile && _localFile) [[NSFileManager defaultManager] removeItemAtURL:_localFile error:NULL]; }

@end
static void OVKDetachPlayback(OVKPlaybackController *player) {
    UINavigationController *nav = player.navigationController;
    if (![nav.viewControllers containsObject:player]) return;
    NSMutableArray *stack = [nav.viewControllers mutableCopy];
    [stack removeObject:player];
    [nav setViewControllers:stack animated:NO];
}
static void OVKPresentPlayback(OVKPlaybackController *player, UINavigationController *nav) {
    if (!nav) return;
    if (OVKCurrentMusic) {
        [OVKCurrentMusic stop];
        OVKDetachPlayback(OVKCurrentMusic);
    }
    OVKCurrentMusic=player;
    [nav pushViewController:player animated:YES];
}
static void OVKShowBundledVideo(NSString *name,UIViewController *controller) {
    NSString *path=[[NSBundle mainBundle] pathForResource:name ofType:@"mp4"]; if (!path || !controller.navigationController) return;
    OVKPlaybackController *player=[[OVKPlaybackController alloc] init]; player.item=@{@"type":@"video",@"title":OVKL(@"Директор дабстепа"),@"local_path":path,@"object":@{}};
    OVKPresentPlayback(player,controller.navigationController);
}
static void OVKShowCurrentMusic(UIViewController *controller) {
    if (!OVKCurrentMusic.nowPlayingAvailable || OVKCurrentMusic.stopped) return;
    UINavigationController *nav=controller.navigationController;
    if (!nav || nav.topViewController==OVKCurrentMusic) return;
    OVKDetachPlayback(OVKCurrentMusic);
    [nav pushViewController:OVKCurrentMusic animated:YES];
}
static NSDictionary *OVKNowPlayingSnapshot(void) {
    OVKPlaybackController *player = OVKCurrentMusic;
    if (!player.nowPlayingAvailable || player.stopped) return nil;
    BOOL video = [player.item[@"type"] isEqualToString:@"video"];
    NSDictionary *object = OVKDictionary(player.item[@"object"]);
    NSString *title = OVKString(object[@"title"]);
    if (!title.length) title = OVKString(player.item[@"title"]);
    NSString *subtitle = video ? player.videoAuthor : OVKString(object[@"artist"] ?: object[@"performer"]);
    if (!subtitle.length) subtitle = video ? OVKL(@"Видео") : (OVKString(player.item[@"local_path"]).length ? OVKL(@"На устройстве") : @"OpenVK");
    BOOL ready = video ? player.movie.currentItem.status==AVPlayerItemStatusReadyToPlay : player.musicPrepared;
    return @{@"title":title, @"subtitle":subtitle, @"video":@(video), @"ready":@(ready),
             @"playing":@(video ? player.movie.rate>0 : player.music.playing),
             @"next":@(!video && ready && [player nextMusicIndex:1 automatic:NO]>=0)};
}
static void OVKToggleNowPlaying(void) {
    if ([OVKCurrentMusic.item[@"type"] isEqualToString:@"video"]) [OVKCurrentMusic toggleVideo];
    else [OVKCurrentMusic toggleMusic];
}
static void OVKNextNowPlaying(void) {
    if (OVKCurrentMusic.musicPrepared) [OVKCurrentMusic playQueueIndex:[OVKCurrentMusic nextMusicIndex:1 automatic:NO]];
}
static void OVKRouteRemoteControl(UIEvent *event) {
    OVKPlaybackController *player=OVKCurrentMusic; if (!player || player.stopped || event.type!=UIEventTypeRemoteControl) return;
    BOOL playing = player.music.playing || player.movie.rate>0;
    switch (event.subtype) {
        case UIEventSubtypeRemoteControlTogglePlayPause: OVKToggleNowPlaying(); break;
        case UIEventSubtypeRemoteControlPlay: if (!playing && !player.activationPending) OVKToggleNowPlaying(); break;
        case UIEventSubtypeRemoteControlPause: case UIEventSubtypeRemoteControlStop: if (playing || player.activationPending) OVKToggleNowPlaying(); break;
        case UIEventSubtypeRemoteControlNextTrack: case UIEventSubtypeRemoteControlPreviousTrack: { UIButton *command=[UIButton buttonWithType:UIButtonTypeCustom]; command.tag=event.subtype==UIEventSubtypeRemoteControlNextTrack ? 1 : -1; [player changeTrack:command]; break; }
        default: break;
    }
}
static NSString *OVKInlineTrackKey(NSDictionary *item) {
    NSString *key=OVKAudioFavoriteID(OVKAudioFavoriteParameters(item));
    return key ?: OVKString(item[@"url"]);
}
static BOOL OVKInlineTrackIsCurrent(NSDictionary *item) {
    NSString *key=OVKInlineTrackKey(item);
    return !OVKCurrentMusic.stopped && key.length && [key isEqualToString:OVKInlineTrackKey(OVKCurrentMusic.item)] &&
           [OVKCurrentMusic.item[@"type"] isEqualToString:@"audio"];
}
static void OVKPlayInlineTrack(NSArray *tracks, NSUInteger index) {
    if (index>=tracks.count) return;
    NSDictionary *track=tracks[index];
    if (OVKInlineTrackIsCurrent(track)) {
        if (OVKCurrentMusic.musicPrepared) { [OVKCurrentMusic toggleMusic]; return; }
        if (OVKCurrentMusic.task || OVKCurrentMusic.resolving || OVKCurrentMusic.music || OVKCurrentMusic.activationPending) return;
    }
    if (OVKCurrentMusic) {
        [OVKCurrentMusic stop];
        OVKDetachPlayback(OVKCurrentMusic);
    }
    OVKPlaybackController *player=[[OVKPlaybackController alloc] init];
    player.inlineAudio=YES; player.inlineProgressSecond=-1;
    player.item=track; player.queue=tracks; player.queueIndex=index;
    OVKCurrentMusic=player;
    // The normal playback controller owns the audio session and queue. Loading its view starts playback without pushing it.
    (void)player.view;
    OVKNotifyNowPlaying();
}

@interface OVKInlineAudioView ()
@property (copy, nonatomic) NSArray *trackRows;
@end
static const CGFloat OVKInlineAudioRowHeight=47;
@implementation OVKInlineAudioView
@synthesize tracks=_tracks;
+ (NSArray *)tracksFromAttachments:(NSArray *)attachments {
    NSMutableArray *tracks=[NSMutableArray array];
    for (NSDictionary *attachment in attachments) {
        if ([attachment[@"type"] isEqualToString:@"audio"] && !attachment[@"voice_message"]) [tracks addObject:attachment];
    }
    return tracks;
}
+ (CGFloat)heightForTracks:(NSArray *)tracks { return tracks.count*OVKInlineAudioRowHeight; }
- (id)initWithFrame:(CGRect)frame {
    self=[super initWithFrame:frame];
    if (self) {
        NSNotificationCenter *center=[NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(playbackChanged:) name:OVKNowPlayingChanged object:nil];
        [center addObserver:self selector:@selector(playbackChanged:) name:OVKInlineAudioProgressChanged object:nil];
        [center addObserver:self selector:@selector(playbackChanged:) name:@"OVKThemeChanged" object:nil];
    }
    return self;
}
- (void)setTracks:(NSArray *)tracks {
    if ([_tracks isEqualToArray:tracks]) { [self playbackChanged:nil]; return; }
    _tracks=[tracks copy];
    for (UIView *row in self.trackRows) [row removeFromSuperview];
    NSMutableArray *rows=[NSMutableArray array];
    [_tracks enumerateObjectsUsingBlock:^(NSDictionary *track,NSUInteger index,BOOL *stop) {
        UIView *row=[[UIView alloc] init];
        row.layer.cornerRadius=5;
        UIButton *button=[UIButton buttonWithType:UIButtonTypeCustom]; button.tag=1;
        button.imageView.contentMode=UIViewContentModeScaleAspectFit;
        button.imageEdgeInsets=UIEdgeInsetsMake(11,11,11,11);
        [button addTarget:self action:@selector(playPressed:) forControlEvents:UIControlEventTouchUpInside];
        [row addSubview:button];
        UIActivityIndicatorView *spinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
        spinner.tag=5; spinner.hidesWhenStopped=YES; spinner.userInteractionEnabled=NO;
        [row addSubview:spinner];
        UILabel *title=[[UILabel alloc] init]; title.tag=2; title.font=[UIFont boldSystemFontOfSize:13];
        title.backgroundColor=[UIColor clearColor]; title.text=track[@"title"]; [row addSubview:title];
        UILabel *time=[[UILabel alloc] init]; time.tag=3; time.font=[UIFont systemFontOfSize:11];
        time.textAlignment=NSTextAlignmentRight; time.backgroundColor=[UIColor clearColor]; [row addSubview:time];
        UIProgressView *progress=[[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        progress.tag=4; [row addSubview:progress];
        [self addSubview:row]; [rows addObject:row];
    }];
    self.trackRows=rows;
    [self playbackChanged:nil];
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width=self.bounds.size.width;
    // A 44-point row fits a full-size play target while keeping title and progress aligned.
    [self.trackRows enumerateObjectsUsingBlock:^(UIView *row,NSUInteger index,BOOL *stop) {
        row.frame=CGRectMake(0,index*OVKInlineAudioRowHeight,width,44);
        [row viewWithTag:1].frame=CGRectMake(4,2,40,40);
        [row viewWithTag:5].center=CGPointMake(24,22);
        [row viewWithTag:2].frame=CGRectMake(51,3,MAX(0,width-100),22);
        [row viewWithTag:3].frame=CGRectMake(MAX(0,width-47),3,41,22);
        [row viewWithTag:4].frame=CGRectMake(51,31,MAX(0,width-60),8);
    }];
}
- (void)playPressed:(UIButton *)button {
    NSUInteger index=[self.trackRows indexOfObjectIdenticalTo:button.superview];
    if (index!=NSNotFound) OVKPlayInlineTrack(self.tracks,index);
}
- (void)playbackChanged:(NSNotification *)note {
    [self.trackRows enumerateObjectsUsingBlock:^(UIView *row,NSUInteger index,BOOL *stop) {
        NSDictionary *track=self.tracks[index];
        BOOL current=OVKInlineTrackIsCurrent(track);
        BOOL playing=current && OVKCurrentMusic.music.playing;
        BOOL pending=current && !OVKCurrentMusic.musicPrepared && (OVKCurrentMusic.task || OVKCurrentMusic.resolving || OVKCurrentMusic.music || OVKCurrentMusic.activationPending);
        UIButton *button=(UIButton *)[row viewWithTag:1];
        UILabel *title=(UILabel *)[row viewWithTag:2], *time=(UILabel *)[row viewWithTag:3];
        UIProgressView *progress=(UIProgressView *)[row viewWithTag:4];
        UIActivityIndicatorView *spinner=(UIActivityIndicatorView *)[row viewWithTag:5];
        UIImage *icon=pending ? nil : [UIImage imageNamed:playing ? @"PauseTrack" : @"PlayTrack"];
        [button setImage:icon forState:UIControlStateNormal];
        if (pending) [spinner startAnimating]; else [spinner stopAnimating];
        button.accessibilityLabel=OVKL(playing ? @"Пауза" : (pending ? @"Загрузка…" : @"Воспроизвести"));
        button.enabled=!pending;
        if (!note || ![note.name isEqualToString:OVKInlineAudioProgressChanged]) {
            row.backgroundColor=OVKPostFooterColor();
            OVKStyleAssetButton(button,@"ProfileBlueButton");
            title.textColor=OVKThemeText(); time.textColor=OVKThemeSecondary();
            progress.progressTintColor=OVKThemeAccent();
        }
        double duration=current && OVKCurrentMusic.musicDuration>0 ? OVKCurrentMusic.musicDuration : [OVKString(OVKDictionary(track[@"object"])[@"duration"]) doubleValue];
        double position=current ? OVKCurrentMusic.musicPosition : 0;
        progress.progress=isfinite(position) && isfinite(duration) && duration>0 ? (float)MIN(1,MAX(0,position/duration)) : 0;
        double displayed=current && isfinite(position) ? position : duration;
        long seconds=isfinite(displayed) && displayed>=0 && displayed<LONG_MAX ? (long)displayed : 0;
        time.text=[NSString stringWithFormat:@"%ld:%02ld",seconds/60,seconds%60];
    }];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end
@interface OVKCacheButton : UIButton
@property (copy, nonatomic) NSString *trackKey;
@property (strong, nonatomic) NSNumber *percent;
@property (strong, nonatomic) UIActivityIndicatorView *indeterminate;
@end
@implementation OVKCacheButton
- (void)drawRect:(CGRect)rect {
    if (!self.percent || self.percent.integerValue<0) return;
    CGPoint center = CGPointMake(CGRectGetMidX(self.bounds),CGRectGetMidY(self.bounds));
    CGFloat start = -M_PI_2;
    UIBezierPath *ring = [UIBezierPath bezierPathWithArcCenter:center radius:12 startAngle:start endAngle:start+2*M_PI clockwise:YES];
    ring.lineWidth=2;
    [[OVKThemeAccent() colorWithAlphaComponent:.25] setStroke];
    [ring stroke];
    CGFloat fraction = MAX(.03,self.percent.doubleValue/100);
    UIBezierPath *progress = [UIBezierPath bezierPathWithArcCenter:center radius:12 startAngle:start endAngle:start+2*M_PI*fraction clockwise:YES];
    progress.lineWidth=2;
    [OVKThemeAccent() setStroke];
    [progress stroke];
}
@end

@interface OVKAttachmentsController ()
@property (strong, nonatomic) NSArray *attachments;
@property (strong, nonatomic) NSArray *allAttachments;
- (void)openPhotoTile:(UIButton *)sender;
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
- (void)viewDidLoad {
    [super viewDidLoad];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(attachmentThemeChanged:) name:@"OVKThemeChanged" object:nil];
    [center addObserver:self selector:@selector(experimentalAttachmentsChanged:) name:@"OVKExperimentalChanged" object:nil];
    [center addObserver:self selector:@selector(updateCacheButtons:) name:OVKMusicCacheChanged object:nil];
    self.tableView.rowHeight = 70;
    self.tableView.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"Linen"]];
}
- (void)configureCacheButton:(OVKCacheButton *)button {
    NSString *scope = OVKCurrentCacheScope();
    if (!scope || !button.trackKey.length) return;
    button.percent = OVKCacheDownloads()[[scope stringByAppendingString:button.trackKey]][@"percent"];
    BOOL cached = !button.percent && OVKMusicCacheURL(scope,button.trackKey)!=nil;
    if (button.percent && button.percent.integerValue<0) {
        if (!button.indeterminate) {
            button.indeterminate=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
            button.indeterminate.center=CGPointMake(CGRectGetMidX(button.bounds),CGRectGetMidY(button.bounds));
            button.indeterminate.hidesWhenStopped=YES;
            [button addSubview:button.indeterminate];
        }
        [button.indeterminate startAnimating];
    } else [button.indeterminate stopAnimating];
    [button setTitle:button.percent ? nil : (cached ? @"✓" : @"↓") forState:UIControlStateNormal];
    [button setTitleColor:OVKThemeAccent() forState:UIControlStateNormal];
    button.enabled = !cached && !button.percent;
    button.accessibilityLabel = cached ? OVKL(@"Загружено в кэш") : (button.percent ? OVKL(@"Загрузка…") : OVKL(@"Скачать трек"));
    button.accessibilityValue = button.percent.integerValue>=0 && button.percent ? [NSString stringWithFormat:@"%@%%",button.percent] : nil;
    [button setNeedsDisplay];
}
- (void)updateCacheButtons:(NSNotification *)note {
    for (UITableViewCell *cell in self.tableView.visibleCells) {
        if (![cell.accessoryView isKindOfClass:[OVKCacheButton class]]) continue;
        OVKCacheButton *button = (OVKCacheButton *)cell.accessoryView;
        if (!note.object || [note.object isEqual:button.trackKey]) [self configureCacheButton:button];
    }
}
- (void)downloadTrack:(OVKCacheButton *)button {
    for (NSDictionary *item in self.attachments) {
        if ([button.trackKey isEqualToString:OVKAudioFavoriteID(OVKAudioFavoriteParameters(item))]) {
            OVKDownloadCachedAudio(item);
            return;
        }
    }
}
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
    cell.indentationLevel = 6; [cell.contentView addSubview:preview]; OVKThemeCell(cell); cell.textLabel.textColor=OVKThemeAccent();
    NSString *trackKey = OVKAudioFavoriteID(OVKAudioFavoriteParameters(item));
    if (trackKey && OVKCurrentCacheScope()) {
        OVKCacheButton *button = [[OVKCacheButton alloc] initWithFrame:CGRectMake(0,0,42,44)];
        button.backgroundColor = [UIColor clearColor];
        button.titleLabel.font = [UIFont boldSystemFontOfSize:24];
        button.trackKey = trackKey;
        [button addTarget:self action:@selector(downloadTrack:) forControlEvents:UIControlEventTouchUpInside];
        [self configureCacheButton:button];
        cell.accessoryView = button;
        NSString *artist = OVKString(OVKDictionary(item[@"object"])[@"artist"]);
        if (artist.length) cell.detailTextLabel.text = artist;
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES]; if ([self isPhotoGrid]) return; NSDictionary *item = self.attachments[path.row];
    if ([item[@"type"] isEqualToString:@"photo"]) { NSMutableArray *photos=[NSMutableArray array]; for (NSDictionary *candidate in self.attachments) if ([candidate[@"type"] isEqualToString:@"photo"]) [photos addObject:candidate];
        OVKPhotoController *photo = [[OVKPhotoController alloc] initWithPhotos:photos index:[photos indexOfObject:item]]; OVKPresentPhoto(self,photo); }
    else {
        BOOL audio=[item[@"type"] isEqualToString:@"audio"];
        OVKPlaybackController *player=[[OVKPlaybackController alloc] init]; player.item=item;
        if (audio) { NSMutableArray *queue=[NSMutableArray array]; for (NSDictionary *candidate in self.attachments) if ([candidate[@"type"] isEqualToString:@"audio"]) [queue addObject:candidate]; player.queue=queue; player.queueIndex=[queue indexOfObject:item]; }
        OVKPresentPlayback(player,self.navigationController);
    }
}
@end
@interface OVKLibraryController () <UISearchBarDelegate>
@property (copy, nonatomic) NSString *kind;
@property (strong, nonatomic) NSNumber *identifier;
@property (strong, nonatomic) UIButton *moreButton;
@property (assign, nonatomic) NSUInteger offset;
@property (assign, nonatomic) BOOL loading;
@property (assign, nonatomic) BOOL more;
@property (copy, nonatomic) NSString *audioQuery;
@property (assign, nonatomic) NSUInteger libraryGeneration;
@property (assign, nonatomic) BOOL audioFavorites;
@property (assign, nonatomic) BOOL audioFeed;
@property (copy, nonatomic) NSArray *remoteFavorites;
@property (copy, nonatomic) NSArray *localSearchMatches;
@property (copy, nonatomic) NSArray *remoteSearchItems;
@property (strong, nonatomic) NSMutableSet *removingFavorites;
@property (assign, nonatomic) BOOL collectionSearchEnabled;
@property (copy, nonatomic) NSArray *collectionItems;
@property (strong, nonatomic) UISearchBar *collectionSearch;
@property (assign, nonatomic) NSUInteger collectionSearchPages;
@end
@implementation OVKLibraryController
- (id)initWithKind:(NSString *)kind identifier:(NSNumber *)identifier title:(NSString *)title {
    self = [super initWithAttachments:@[] title:title]; if (self) { self.kind = kind; self.identifier = identifier; } return self;
}
- (id)initForAudioSearch {
    self = [self initWithKind:@"audio" identifier:nil title:OVKL(@"Поиск музыки")];
    if (self) self.audioQuery = @"";
    return self;
}
- (void)enableCollectionSearch { self.collectionSearchEnabled=YES; }
- (void)toggleCollectionSearch {
    if (self.collectionSearch) {
        [self.collectionSearch resignFirstResponder];
        self.collectionSearch.delegate=nil; self.collectionSearch=nil; self.tableView.tableHeaderView=nil;
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(loadMoreCollectionMatches) object:nil];
        [self showCollectionItems];
        return;
    }
    self.collectionSearch=[[UISearchBar alloc] initWithFrame:CGRectMake(0,0,self.tableView.bounds.size.width,44)];
    self.collectionSearch.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    self.collectionSearch.placeholder=OVKL(@"Поиск в медиатеке");
    self.collectionSearch.delegate=self;
    self.tableView.tableHeaderView=self.collectionSearch;
    [self.tableView setContentOffset:CGPointMake(0,-self.tableView.contentInset.top) animated:NO];
    [self.collectionSearch becomeFirstResponder];
}
- (void)showCollectionItems {
    NSString *query=[self.collectionSearch.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!query.length) { [self replaceAttachments:self.collectionItems ?: @[]]; return; }
    NSMutableArray *matches=[NSMutableArray array];
    for (NSDictionary *item in self.collectionItems) {
        NSDictionary *object=OVKDictionary(item[@"object"]);
        NSString *text=[NSString stringWithFormat:@"%@ %@ %@",OVKString(item[@"title"]),OVKString(object[@"text"]),OVKString(object[@"description"])];
        if ([text rangeOfString:query options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch].location!=NSNotFound) [matches addObject:item];
    }
    [self replaceAttachments:matches];
}
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self showCollectionItems];
    self.collectionSearchPages=5;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(loadMoreCollectionMatches) object:nil];
    [self performSelector:@selector(loadMoreCollectionMatches) withObject:nil afterDelay:.4];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    self.collectionSearchPages=5;
    [self loadMoreCollectionMatches];
}
- (void)loadMoreCollectionMatches {
    NSString *query=[self.collectionSearch.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!query.length || !self.view.window || self.loading || !self.more || self.attachments.count || !self.collectionSearchPages) return;
    self.collectionSearchPages--;
    [self nextPage];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    if (self.selectedAttachment && ![self isPhotoGrid] && (NSUInteger)path.row<self.attachments.count) {
        [tableView deselectRowAtIndexPath:path animated:YES];
        self.selectedAttachment(self.attachments[path.row]);
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:path];
}
- (void)openPhotoTile:(UIButton *)sender {
    if (self.selectedAttachment && (NSUInteger)sender.tag<self.attachments.count) {
        self.selectedAttachment(self.attachments[sender.tag]);
        return;
    }
    [super openPhotoTile:sender];
}
- (id)initForAudioFavorites {
    self = [self initWithKind:@"audio" identifier:[OVKAPI shared].userID title:OVKL(@"Избранные")];
    if (self) {
        self.audioFavorites = YES;
        self.removingFavorites = [NSMutableSet set];
    }
    return self;
}
- (id)initForAudioFeed {
    self = [self initWithKind:@"audio" identifier:nil title:OVKL(@"Новые")];
    if (self) self.audioFeed = YES;
    return self;
}
- (NSString *)favoritesSnapshotKey {
    NSString *scope = OVKCurrentCacheScope();
    return scope ? [@"OVKMusicFavorites." stringByAppendingString:scope] : nil;
}
- (void)saveFavoritesSnapshot {
    NSString *key = [self favoritesSnapshotKey];
    if (!key) return;
    NSMutableArray *snapshot = [NSMutableArray array];
    for (NSDictionary *item in self.remoteFavorites) {
        NSDictionary *metadata = OVKOfflineAudioMetadata(item);
        if (metadata) [snapshot addObject:metadata];
        if (snapshot.count>=500) break;
    }
    [[NSUserDefaults standardUserDefaults] setObject:snapshot forKey:key];
}
- (void)showFavorites {
    NSMutableArray *favorites = [NSMutableArray array];
    for (NSDictionary *item in OVKLocalMusicItems()) {
        if (OVKLocalMusicIsFavorite(OVKString(item[@"local_path"]))) [favorites addObject:item];
    }
    [favorites addObjectsFromArray:self.remoteFavorites ?: @[]];
    [self replaceAttachments:favorites];
}
- (void)localLibraryChanged:(NSNotification *)note {
    [self showFavorites];
    if (![OVKAPI shared].token.length && ![OVKAPI shared].demo) self.moreButton.hidden=self.attachments.count>0;
}
- (void)showAudioSearchResults {
    [self replaceAttachments:[(self.localSearchMatches ?: @[]) arrayByAddingObjectsFromArray:self.remoteSearchItems ?: @[]]];
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.refreshControl = [[UIRefreshControl alloc] init]; [self.refreshControl addTarget:self action:@selector(refreshLibrary) forControlEvents:UIControlEventValueChanged];
    self.moreButton = [UIButton buttonWithType:UIButtonTypeCustom]; self.moreButton.frame = CGRectMake(0,0,320,48); [self.moreButton setTitleColor:OVKBlue() forState:UIControlStateNormal]; self.moreButton.titleLabel.font = [UIFont boldSystemFontOfSize:14]; [self.moreButton addTarget:self action:@selector(nextPage) forControlEvents:UIControlEventTouchUpInside]; self.tableView.tableFooterView = self.moreButton;
    if (self.collectionSearchEnabled) self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSearch target:self action:@selector(toggleCollectionSearch)];
    if ([self.kind isEqualToString:@"audio"]) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioLibraryChanged:)
                                                     name:OVKAudioFavoritesChanged object:nil];
    }
    if (self.audioFavorites) {
        NSString *key = [self favoritesSnapshotKey];
        if (key) self.remoteFavorites = [[NSUserDefaults standardUserDefaults] arrayForKey:key];
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(localLibraryChanged:) name:@"OVKLocalMusicFavoritesChanged" object:nil];
        [center addObserver:self selector:@selector(localLibraryChanged:) name:@"OVKLocalMusicChanged" object:nil];
        [self showFavorites];
    }
    if (self.audioQuery && !self.audioQuery.length) self.moreButton.hidden = YES;
    else [self refreshLibrary];
}
- (void)setAudioSearchQuery:(NSString *)query {
    if (!self.audioQuery) return;
    query = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    if ([self.audioQuery isEqualToString:query]) return;
    self.audioQuery = query;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runAudioSearch) object:nil];
    ++self.libraryGeneration;
    self.loading = NO;
    self.more = NO;
    self.offset = 0;
    NSMutableArray *matches = [NSMutableArray array];
    if (query.length) {
        for (NSDictionary *item in OVKLocalMusicItems()) {
            NSString *title = OVKString(item[@"title"]);
            if ([title rangeOfString:query options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch].location!=NSNotFound) [matches addObject:item];
        }
    }
    self.localSearchMatches=matches;
    self.remoteSearchItems=@[];
    [self showAudioSearchResults];
    if (!self.isViewLoaded) return;
    [self.refreshControl endRefreshing];
    [self.tableView setContentOffset:CGPointMake(0,-self.tableView.contentInset.top) animated:NO];
    self.moreButton.hidden = !query.length;
    if (query.length) {
        [self.moreButton setTitle:OVKL(@"Загрузка…") forState:UIControlStateNormal];
        [self performSelector:@selector(runAudioSearch) withObject:nil afterDelay:.35];
    }
}
- (void)submitAudioSearch {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runAudioSearch) object:nil];
    if (!self.offset) [self runAudioSearch];
}
- (void)runAudioSearch { [self refreshLibrary]; }
- (void)audioLibraryChanged:(NSNotification *)note {
    if (!self.audioFavorites && !self.audioQuery && !self.audioFeed && ![self.identifier isEqual:[OVKAPI shared].userID]) return;
    if (self.audioFavorites && ![note.userInfo[@"favorite"] boolValue]) {
        NSMutableArray *remaining = [NSMutableArray array];
        for (NSDictionary *item in self.remoteFavorites) {
            if (![note.object isEqual:OVKAudioFavoriteID(OVKAudioFavoriteParameters(item))]) [remaining addObject:item];
        }
        self.remoteFavorites = remaining;
        [self saveFavoritesSnapshot];
        [self showFavorites];
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runAudioSearch) object:nil];
    self.loading = NO;
    [self refreshLibrary];
}
- (void)refreshLibrary {
    if (self.loading || (self.audioQuery && !self.audioQuery.length)) {
        [self.refreshControl endRefreshing];
        return;
    }
    [self fetchLibrary:NO];
}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)path {
    if (!self.audioFavorites || path.row>=self.attachments.count) return NO;
    NSDictionary *item = self.attachments[path.row];
    if (OVKString(item[@"local_path"]).length) return YES;
    NSString *key = OVKAudioFavoriteID(OVKAudioFavoriteParameters(item));
    return key && [OVKAPI shared].token.length && ![self.removingFavorites containsObject:key];
}
- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)path { return @"−"; }
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if (style!=UITableViewCellEditingStyleDelete || ![self tableView:tableView canEditRowAtIndexPath:path]) return;
    NSDictionary *item = self.attachments[path.row];
    NSString *local = OVKString(item[@"local_path"]);
    if (local.length) { OVKSetLocalMusicFavorite(local,NO); return; }
    NSDictionary *params = OVKAudioFavoriteParameters(item);
    NSString *key = OVKAudioFavoriteID(params);
    [self.removingFavorites addObject:key];
    __weak OVKLibraryController *weakSelf = self;
    [[OVKAPI shared] call:@"audio.delete" parameters:params completion:^(id result,NSError *error) {
        [weakSelf.removingFavorites removeObject:key];
        if (error) {
            [weakSelf.tableView setEditing:NO animated:YES];
            OVKAlert(OVKL(@"Не удалось изменить избранное"),error.localizedDescription);
            return;
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:OVKAudioFavoritesChanged object:key userInfo:@{@"favorite":@NO}];
    }];
}
- (void)nextPage {
    if (self.loading || (self.audioQuery && !self.audioQuery.length)) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runAudioSearch) object:nil];
    [self fetchLibrary:self.more && self.offset>0];
}
- (void)fetchLibrary:(BOOL)append {
    if (self.audioQuery && ![OVKAPI shared].token.length && ![OVKAPI shared].demo) {
        [self.refreshControl endRefreshing];
        [self.moreButton setTitle:OVKL(@"Ничего не найдено") forState:UIControlStateNormal];
        self.moreButton.hidden=self.attachments.count>0;
        return;
    }
    if ((self.audioFavorites || self.audioFeed) && ![OVKAPI shared].token.length && ![OVKAPI shared].demo) {
        if (self.audioFavorites) [self showFavorites];
        [self.refreshControl endRefreshing];
        [self.moreButton setTitle:self.audioFeed ? OVKL(@"Для музыки сервера войдите в аккаунт.") : OVKL(@"В избранном пока нет музыки") forState:UIControlStateNormal];
        self.moreButton.hidden = self.audioFavorites && self.attachments.count;
        return;
    }
    NSUInteger generation = ++self.libraryGeneration;
    self.loading = YES; [self.moreButton setTitle:OVKL(@"Загрузка…") forState:UIControlStateNormal];
    NSString *method = [self.kind isEqualToString:@"photo"] ? @"photos.getAll" : ([self.kind isEqualToString:@"audio"] ? @"audio.get" : @"video.get");
    NSUInteger pageSize=OVKPageSize(), offset=append ? self.offset : 0;
    NSDictionary *params;
    if (self.audioQuery) {
        method = @"audio.search";
        params = @{@"q":self.audioQuery, @"count":@(pageSize), @"offset":@(offset)};
    } else if (self.audioFeed) {
        method = @"audio.getFeed";
        params = @{@"count":@(pageSize), @"offset":@(offset)};
    } else {
        params = @{@"owner_id":self.identifier ?: @0, @"count":@(pageSize), @"offset":@(offset), @"photo_sizes":@1};
    }
    __weak OVKLibraryController *weakSelf = self;
    void (^showLibrary)(id,BOOL)=^(id result,BOOL stale) {
        OVKLibraryController *self=weakSelf;
        if (!self || generation!=self.libraryGeneration) return;
        if (![result isKindOfClass:[NSArray class]] && ![OVKDictionary(result)[@"items"] isKindOfClass:[NSArray class]]) return;
        NSArray *items = [result isKindOfClass:[NSArray class]] ? result : OVKArray(OVKDictionary(result)[@"items"]);
        BOOL ownAudio = self.audioFavorites || (!self.audioQuery && !self.audioFeed && [self.kind isEqualToString:@"audio"] && [self.identifier isEqual:[OVKAPI shared].userID]);
        NSMutableArray *raw = [NSMutableArray array];
        for (id value in items) {
            if (![value isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *item = value;
            if (ownAudio && !item[@"added"]) {
                NSMutableDictionary *audio = [item mutableCopy];
                audio[@"added"] = @YES;
                item = audio;
            }
            [raw addObject:@{@"type":self.kind, self.kind:item}];
        }
        NSArray *normal = OVKPlayableAttachments(@{@"attachments":raw});
        NSArray *previous = self.audioFavorites ? self.remoteFavorites : (self.audioQuery ? self.remoteSearchItems : (self.collectionSearchEnabled ? self.collectionItems : self.attachments));
        NSMutableArray *combined = append && previous ? [previous mutableCopy] : [NSMutableArray array];
        [combined addObjectsFromArray:normal];
        if (self.audioFavorites) {
            self.remoteFavorites = combined;
            if (!stale) [self saveFavoritesSnapshot];
            [self showFavorites];
        } else if (self.audioQuery) {
            self.remoteSearchItems=combined;
            [self showAudioSearchResults];
        } else if (self.collectionSearchEnabled) {
            self.collectionItems=combined;
            [self showCollectionItems];
        } else [self replaceAttachments:combined];
        self.offset = offset + items.count;
        self.more = ![OVKAPI shared].demo && items.count >= pageSize;
        self.tableView.separatorStyle=[self isPhotoGrid] ? UITableViewCellSeparatorStyleNone : UITableViewCellSeparatorStyleSingleLine; self.tableView.backgroundColor=[self isPhotoGrid] ? [UIColor colorWithWhite:.12 alpha:1] : OVKThemeBackground(); [self.moreButton setTitleColor:[self isPhotoGrid] ? [UIColor lightGrayColor] : OVKBlue() forState:UIControlStateNormal];
        NSString *emptyTitle = (self.audioQuery || self.collectionSearch.text.length) ? OVKL(@"Ничего не найдено") : OVKL(@"Здесь пока ничего нет — обновить");
        [self.moreButton setTitle:self.more ? OVKL(@"Показать ещё") : (self.attachments.count ? OVKL(@"Обновить") : emptyTitle) forState:UIControlStateNormal];
    };
    [[OVKAPI shared] call:method parameters:params cached:^(id result) {
        OVKLibraryController *page=weakSelf;
        if (page && !append && (page.audioQuery || !page.attachments.count)) showLibrary(result,YES);
    } completion:^(id result,NSError *error) {
        OVKLibraryController *page=weakSelf;
        if (!page || generation!=page.libraryGeneration) return;
        page.loading=NO; [page.refreshControl endRefreshing];
        if (error) {
            [page.moreButton setTitle:OVKL(@"Повторить загрузку") forState:UIControlStateNormal];
            if (page.view.window && !page.attachments.count && !((page.audioFavorites || page.audioQuery) && OVKOfflineError(error))) OVKAlert(OVKL(@"Не удалось загрузить раздел"),error.localizedDescription);
            return;
        }
        showLibrary(result,NO);
        if (page.collectionSearch) [page loadMoreCollectionMatches];
    }];
}
@end
