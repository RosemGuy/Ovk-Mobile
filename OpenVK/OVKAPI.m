#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif
#import "OVKAPI.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#import "OVKDebug.h"
#import "OVKTrust.h"
NSString *OVKString(id v) { return [v isKindOfClass:[NSString class]] ? v : ([v isKindOfClass:[NSNumber class]] ? [v stringValue] : @""); }
NSDictionary *OVKDictionary(id v) { return [v isKindOfClass:[NSDictionary class]] ? v : @{}; }
NSArray *OVKArray(id v) { return [v isKindOfClass:[NSArray class]] ? v : @[]; }
NSString *OVKEncode(NSString *v) {
    return CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(NULL, (__bridge CFStringRef)v, NULL, CFSTR("!*'();:@&=+$,/?%#[]\" "), kCFStringEncodingUTF8));
}
NSDictionary *OVKQuery(NSString *query) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *pair in [query componentsSeparatedByString:@"&"]) {
        NSRange equal = [pair rangeOfString:@"="];
        if (equal.location == NSNotFound) continue;
        NSString *key = [[[pair substringToIndex:equal.location] stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        NSString *val = [[[pair substringFromIndex:equal.location+1] stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        if (key && val) result[key] = val;
    }
    return result;
}
static id OVKCleanJSON(id value) {
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        for (NSString *key in value) { id item = OVKCleanJSON(value[key]); if (item) result[key] = item; }
        return result;
    }
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *result = [NSMutableArray array];
        for (id item in value) { id clean = OVKCleanJSON(item); if (clean) [result addObject:clean]; }
        return result;
    }
    return value == [NSNull null] ? nil : value;
}
static NSError *OVKError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"OpenVK" code:code userInfo:@{NSLocalizedDescriptionKey:message ?: @"Ошибка сервера"}];
}
NSString *OVKCacheHash(NSString *text) {
    NSData *data=[text dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    NSMutableString *key=[NSMutableString stringWithCapacity:sizeof(digest)*2];
    for (NSUInteger i=0;i<sizeof(digest);i++) [key appendFormat:@"%02x",(unsigned int)digest[i]];
    return key;
}
static dispatch_queue_t OVKResponseCacheQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue=dispatch_queue_create("org.openvk.mobile.responses",DISPATCH_QUEUE_SERIAL); });
    return queue;
}
void OVKTrimDiskCache(NSURL *directory, NSUInteger byteLimit, NSUInteger entryLimit) {
    NSFileManager *manager=[NSFileManager defaultManager];
    NSArray *keys=@[NSURLContentModificationDateKey,NSURLFileSizeKey];
    NSArray *files=[manager contentsOfDirectoryAtURL:directory includingPropertiesForKeys:keys options:NSDirectoryEnumerationSkipsHiddenFiles error:NULL];
    files=[files sortedArrayUsingComparator:^NSComparisonResult(NSURL *a,NSURL *b) {
        NSDate *first=nil,*second=nil;
        [a getResourceValue:&first forKey:NSURLContentModificationDateKey error:NULL];
        [b getResourceValue:&second forKey:NSURLContentModificationDateKey error:NULL];
        return [(second ?: [NSDate distantPast]) compare:(first ?: [NSDate distantPast])];
    }];
    NSUInteger bytes=0,index=0;
    for (NSURL *file in files) {
        NSNumber *size=nil;
        [file getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];
        bytes+=size.unsignedIntegerValue;
        if (++index>entryLimit || bytes>byteLimit) [manager removeItemAtURL:file error:NULL];
    }
}
// One request owns its connection until completion. All callbacks run on the main thread.
@interface OVKRequest : NSObject <NSURLConnectionDataDelegate, OVKCancellable>
@property (strong, nonatomic) NSURLConnection *connection;
@property (strong, nonatomic) NSMutableData *data;
@property (strong, nonatomic) NSURL *origin;
@property (copy, nonatomic) OVKCompletion completion;
@property (assign, nonatomic) NSInteger status;
@property (assign, atomic) NSUInteger parseGeneration;
@property (assign, nonatomic) BOOL tokenResponse;
@property (assign, nonatomic) BOOL uploadResponse;
@property (copy, nonatomic) NSString *mimeType;
@property (copy, nonatomic) NSString *responseServer;
#if DEBUG
@property (assign, nonatomic) NSUInteger debugRequestID;
@property (assign, nonatomic) NSTimeInterval debugStartedAt;
#endif
- (void)start:(NSURLRequest *)request completion:(OVKCompletion)completion;
@end
@implementation OVKRequest
- (void)start:(NSURLRequest *)request completion:(OVKCompletion)completion {
    self.completion = completion; self.origin = request.URL; self.data = [NSMutableData data];
#if DEBUG
    static NSUInteger nextRequestID;
    @synchronized ([OVKRequest class]) {
        self.debugRequestID = ++nextRequestID;
    }
    self.debugStartedAt = [[NSProcessInfo processInfo] systemUptime];
    OVKDebugLog(@"[API #%lu] %@ %@:%@%@", (unsigned long)self.debugRequestID,
                request.HTTPMethod, self.origin.host, self.origin.port ?: @443, self.uploadResponse ? @"/[upload]" : self.origin.path);
#endif
    NSMutableURLRequest *configured = [request mutableCopy];
    [configured setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [configured setValue:[OVKAPI requestUserAgent] forHTTPHeaderField:@"User-Agent"];
    configured.HTTPShouldHandleCookies = !self.uploadResponse; request = configured;
    self.connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:YES];
    if (!self.connection) [self finish:nil error:OVKError(-1,@"Не удалось создать подключение")];
}
- (void)cancel { [self finish:nil error:OVKError(NSURLErrorCancelled,@"Вход отменён")]; }
- (void)finish:(id)result error:(NSError *)error {
    OVKCompletion callback = self.completion;
#if DEBUG
    if (callback) {
        NSTimeInterval elapsed = [[NSProcessInfo processInfo] systemUptime] - self.debugStartedAt;
        OVKDebugLog(@"[API #%lu] %@ in %.2fs (HTTP %ld, domain=%@, code=%ld)",
                    (unsigned long)self.debugRequestID, error ? @"failed" : @"completed",
                    elapsed, (long)self.status, error.domain ?: @"-", (long)error.code);
    }
#endif
    self.completion = nil; ++self.parseGeneration; self.data=nil; [self.connection cancel]; self.connection = nil;
    if (callback) callback(result,error);
}
- (void)connection:(NSURLConnection *)connection willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    if (![challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) { [challenge.sender performDefaultHandlingForAuthenticationChallenge:challenge]; return; }
    NSString *host = challenge.protectionSpace.host;
    NSString *path = [[NSBundle mainBundle] pathForResource:@"ISRG-Root-X1" ofType:@"cer"];
    NSData *root = path ? [NSData dataWithContentsOfFile:path] : nil;
    BOOL sameHost = [host caseInsensitiveCompare:self.origin.host ?: @""] == NSOrderedSame;
    if (sameHost && OVKEvaluateServerTrust(challenge.protectionSpace.serverTrust,host,root)) {
        [challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge];
    } else {
        OVKDebugLog(@"[API #%lu] TLS trust rejected", (unsigned long)self.debugRequestID);
        [challenge.sender cancelAuthenticationChallenge:challenge];
        NSString *message = [NSString stringWithFormat:@"Не удалось проверить сертификат %@. Проверены имя сервера, срок действия и цепочка доверия, включая ISRG Root X1. Системная дата: %@.",host,[NSDate date]];
        [self finish:nil error:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorServerCertificateUntrusted userInfo:@{NSLocalizedDescriptionKey:message}]];
    }
}
- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response {
    if (!response) return request;
    NSURL *url = request.URL;
    if (![url.scheme isEqualToString:self.origin.scheme] || ![url.host isEqualToString:self.origin.host] || ![(url.port ?: @443) isEqual:(self.origin.port ?: @443)]) {
        OVKDebugLog(@"[API #%lu] redirect blocked (HTTP %ld)",
                    (unsigned long)self.debugRequestID, (long)[(NSHTTPURLResponse *)response statusCode]);
        [self finish:nil error:OVKError(-2,@"API перенаправляет на другой сервер. Укажите его адрес на экране входа.")]; return nil;
    }
    return request;
}
- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)response { return nil; }
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    self.status = [(NSHTTPURLResponse *)response statusCode]; self.mimeType = response.MIMEType;
    NSDictionary *headers = [(NSHTTPURLResponse *)response allHeaderFields];
    self.responseServer = OVKString(headers[@"Server"] ?: headers[@"server"]); [self.data setLength:0];
}
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    if (self.data.length + data.length > 8*1024*1024) { [self finish:nil error:OVKError(-3,@"Ответ сервера слишком большой")]; return; }
    [self.data appendData:data];
}
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    // Older NSURLConnection may surface a 401 validation JSON as cancelled authentication.
    if (self.tokenResponse && self.status == 401 && self.data.length && [error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorUserCancelledAuthentication) { [self connectionDidFinishLoading:connection]; return; }
    if (self.uploadResponse && [error.domain isEqualToString:NSURLErrorDomain] && error.code==NSURLErrorSecureConnectionFailed) {
        // Log only the host and error codes because the upload path can contain a signature.
        NSError *underlying=error.userInfo[NSUnderlyingErrorKey];
        OVKDebugLog(@"[API #%lu] photo upload TLS host=%@ underlying=%@/%ld",
                    (unsigned long)self.debugRequestID,self.origin.host,underlying.domain ?: @"-",(long)underlying.code);
        NSString *message=[NSString stringWithFormat:@"Не удалось установить защищённое соединение с сервером загрузки %@ (SSL %ld).",self.origin.host,(long)error.code];
        error=[NSError errorWithDomain:error.domain code:error.code userInfo:@{NSLocalizedDescriptionKey:message,NSUnderlyingErrorKey:error}];
    }
    [self finish:nil error:error];
}
- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    NSData *payload=self.data; self.data=nil; NSUInteger generation=++self.parseGeneration;
    static dispatch_queue_t queue; static dispatch_once_t once; dispatch_once(&once, ^{ queue=dispatch_queue_create("org.openvk.mobile.json",DISPATCH_QUEUE_SERIAL); dispatch_set_target_queue(queue,dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW,0)); });
    dispatch_async(queue, ^{ @autoreleasepool {
        if (generation!=self.parseGeneration) return;
        NSError *error=nil; id json=payload ? [NSJSONSerialization JSONObjectWithData:payload options:0 error:&error] : nil;
        BOOL valid=[json isKindOfClass:[NSDictionary class]]; NSDictionary *root=valid ? OVKDictionary(OVKCleanJSON(json)) : @{};
        dispatch_async(dispatch_get_main_queue(), ^{ if (generation!=self.parseGeneration || !self.completion) return; [self completeJSON:root valid:valid error:error]; });
    } });
}
- (void)completeJSON:(NSDictionary *)root valid:(BOOL)valid error:(NSError *)parseError {
    if (parseError || !valid) {
        OVKDebugLog(@"[API #%lu] expected a JSON object (HTML=%d, parser code=%ld)",
                    (unsigned long)self.debugRequestID, [self.mimeType isEqualToString:@"text/html"],
                    (long)parseError.code);
        NSString *path=self.uploadResponse ? @"/[upload]" : (self.origin.path ?: @"");
        NSString *diagnostic = [NSString stringWithFormat:@"HTTP %ld: ответ не является JSON.\nАдрес: %@%@\nТип: %@; сервер: %@\nUser-Agent: %@\n%@",(long)self.status,self.origin.host ?: @"",path,self.mimeType ?: @"не указан",self.responseServer.length ? self.responseServer : @"не указан",[OVKAPI requestUserAgent], self.status == 403 ? @"Сервер отказал в запросе. Это не ответ API о неверном пароле." : @"Проверьте адрес API и доступ к серверу."];
        [self finish:nil error:OVKError((self.status < 200 || self.status >= 300) ? self.status : -4,diagnostic)]; return;
    }
    if (self.tokenResponse) {
        NSString *token = OVKString(root[@"access_token"]);
        if (self.status >= 200 && self.status < 300 && token.length) { [self finish:root error:nil]; return; }
        NSDictionary *failure = OVKDictionary(root[@"error"]); if (!failure.count) failure = root;
        NSString *message = OVKString(failure[@"error_msg"] ?: failure[@"error_description"] ?: failure[@"error"]);
        NSInteger code = [OVKString(failure[@"error_code"]) integerValue];
        NSString *reason = OVKString(failure[@"error"]);
        BOOL twoFactor = [reason isEqualToString:@"need_validation"] || root[@"validation_sid"] || [message rangeOfString:@"2FA" options:NSCaseInsensitiveSearch].location != NSNotFound;
        if (twoFactor) {
            OVKDebugLog(@"[API #%lu] two-factor authentication required", (unsigned long)self.debugRequestID);
            reason = @"need_validation";
            message = @"Сервер запросил одноразовый код двухфакторной авторизации.";
        } else if (code == 28 || [reason isEqualToString:@"invalid_password"]) { reason = @"invalid_password"; message = @"Неверный логин или пароль аккаунта выбранного инстанса."; }
        else if (root[@"request_uri"]) message = @"Сервер требует дополнительную веб-проверку. Используйте альтернативный веб-вход.";
        if (!message.length) message = [NSString stringWithFormat:@"Сервер не выдал токен (HTTP %ld). Проверьте логин, пароль и адрес инстанса.",(long)self.status];
        NSDictionary *info = @{NSLocalizedDescriptionKey:message,@"OVKAuthReason":reason.length ? reason : @"server_error"};
        [self finish:nil error:[NSError errorWithDomain:@"OpenVK" code:code ?: ((self.status >= 200 && self.status < 300) ? -6 : self.status) userInfo:info]]; return;
    }
    NSDictionary *failure = OVKDictionary(root[@"error"]);
    if (failure.count || root[@"error_code"]) {
        if (!failure.count) failure = root;
        [self finish:nil error:OVKError([failure[@"error_code"] integerValue],OVKString(failure[@"error_msg"]))]; return;
    }
    if ([root[@"error"] isKindOfClass:[NSString class]]) { [self finish:nil error:OVKError(self.status,OVKString(root[@"error_description"] ?: root[@"error"]))]; return; }
    if (self.status < 200 || self.status >= 300) { [self finish:nil error:OVKError(self.status,[NSString stringWithFormat:@"HTTP %ld: %@",(long)self.status,OVKString(root[@"message"]).length ? OVKString(root[@"message"]) : @"запрос отклонён сервером"])]; return; }
    if (self.uploadResponse) { [self finish:root error:nil]; return; }
    if (!root[@"response"] || root[@"response"] == [NSNull null]) { [self finish:nil error:OVKError(-5,@"В ответе API отсутствует response")]; return; }
    [self finish:root[@"response"] error:nil];
}
@end
@interface OVKAPI ()
@property (assign, nonatomic, readwrite) NSInteger keychainStatus;
@property (assign, nonatomic, readwrite) BOOL protectedSessionStore;
@end
@implementation OVKAPI
+ (NSString *)requestUserAgent { return @"curl"; }
+ (OVKAPI *)shared { static OVKAPI *api; static dispatch_once_t once; dispatch_once(&once, ^{ api = [[OVKAPI alloc] init]; api.server = @"https://api.openvk.org"; api.siteServer = @"https://openvk.org";
    NSString *savedAPI = [[NSUserDefaults standardUserDefaults] stringForKey:@"OVKSelectedAPI"]; NSString *savedSite = [[NSUserDefaults standardUserDefaults] stringForKey:@"OVKSelectedSite"];
    if (savedAPI.length && savedSite.length) { NSString *validAPI = [OVKAPI validatedServer:savedAPI]; NSString *validSite = [OVKAPI validatedServer:savedSite]; if (validAPI && validSite && ![validSite isEqualToString:@"https://openvk.xyz"]) { api.server = validAPI; api.siteServer = validSite; } }
 }); return api; }
+ (NSString *)validatedServer:(NSString *)input {
    NSString *value = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([value rangeOfString:@"://"].location == NSNotFound) value = [@"https://" stringByAppendingString:value];
    NSURL *url = [NSURL URLWithString:value];
    if (![url.scheme.lowercaseString isEqualToString:@"https"] || !url.host.length || url.user || url.password || url.query || url.fragment || (url.path.length && ![url.path isEqualToString:@"/"])) return nil;
    return [NSString stringWithFormat:@"https://%@%@",url.host.lowercaseString,url.port ? [NSString stringWithFormat:@":%@",url.port] : @""];
}
- (id<OVKCancellable>)checkConnection:(OVKCompletion)completion {
    NSURL *url = [NSURL URLWithString:[self.server stringByAppendingString:@"/method/ovk.test?v=5.131"]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20]; request.HTTPShouldHandleCookies = YES;
    OVKRequest *task = [[OVKRequest alloc] init]; [task start:request completion:completion]; return task;
}
- (id<OVKCancellable>)authenticateUsername:(NSString *)username password:(NSString *)password code:(NSString *)code completion:(OVKCompletion)completion {
    NSMutableDictionary *params = [@{@"username":username,@"password":password,@"grant_type":@"password",@"v":@"5.131",@"2fa_supported":@"1",@"client_name":@"openvk_legacy_ios"} mutableCopy];
    if (code.length) params[@"code"] = code;
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *key in [[params allKeys] sortedArrayUsingSelector:@selector(compare:)]) [parts addObject:[NSString stringWithFormat:@"%@=%@",OVKEncode(key),OVKEncode(OVKString(params[key]))]];
    NSURL *url = [NSURL URLWithString:[self.server stringByAppendingString:@"/token"]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];
    request.HTTPMethod = @"POST"; request.HTTPShouldHandleCookies = YES;
    [request setValue:@"application/x-www-form-urlencoded; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = [[parts componentsJoinedByString:@"&"] dataUsingEncoding:NSUTF8StringEncoding];
    OVKRequest *task = [[OVKRequest alloc] init]; task.tokenResponse = YES;
    [task start:request completion:completion]; return task;
}
- (NSMutableDictionary *)keychainQuery {
    return [@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:@"OpenVKClassic.Session",(__bridge id)kSecAttrAccount:@"current"} mutableCopy];
}
- (NSString *)sessionFile {
    NSString *base=[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES) objectAtIndex:0];
    return [[base stringByAppendingPathComponent:@"Ovk-Mobile"] stringByAppendingPathComponent:@"sessions.json"];
}
- (NSDictionary *)readVault {
    NSData *data=nil; NSString *file=[self sessionFile];
    if ([[NSFileManager defaultManager] fileExistsAtPath:file]) {
        data=[NSData dataWithContentsOfFile:file]; if (!data) { self.keychainStatus=errSecInteractionNotAllowed; return nil; }
        self.protectedSessionStore=YES;
    } else {
        NSMutableDictionary *q=[self keychainQuery]; q[(__bridge id)kSecReturnData]=@YES; CFTypeRef value=NULL;
        self.keychainStatus=SecItemCopyMatching((__bridge CFDictionaryRef)q,&value);
        if (self.keychainStatus==errSecItemNotFound) return @{};
        if (self.keychainStatus!=errSecSuccess) return nil;
        data=CFBridgingRelease(value); self.protectedSessionStore=NO;
    }
    id value=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![value isKindOfClass:[NSDictionary class]]) { self.keychainStatus=errSecDecode; return nil; }
    return value;
}
- (NSArray *)accountsInVault:(NSDictionary *)vault {
    NSMutableArray *valid=[NSMutableArray array]; NSArray *raw=[vault[@"accounts"] isKindOfClass:[NSArray class]] ? vault[@"accounts"] : (vault[@"token"] ? @[vault] : @[]);
    for (id value in raw) { NSDictionary *entry=OVKDictionary(value); if ([OVKAPI validatedServer:OVKString(entry[@"server"])] && OVKString(entry[@"token"]).length && [entry[@"id"] longLongValue]>0) [valid addObject:entry]; }
    return valid;
}
- (BOOL)canUseProtectedSessionStore {
#if TARGET_OS_IPHONE
    // -25308 can also occur with signing/securityd restrictions while the device is unlocked.
    if (![[UIApplication sharedApplication] isProtectedDataAvailable]) return NO;
    return self.keychainStatus==-34018 || self.keychainStatus==errSecNotAvailable || self.keychainStatus==errSecAuthFailed || self.keychainStatus==errSecInteractionNotAllowed;
#else
    return NO;
#endif
}
- (BOOL)writeVault:(NSDictionary *)vault {
    NSData *data=[NSJSONSerialization dataWithJSONObject:vault options:0 error:NULL]; if (!data) return NO;
    NSMutableDictionary *q=[self keychainQuery]; NSDictionary *attributes=@{(__bridge id)kSecValueData:data,(__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly};
    OSStatus status=SecItemUpdate((__bridge CFDictionaryRef)q,(__bridge CFDictionaryRef)attributes);
    if (status==errSecItemNotFound) { [q addEntriesFromDictionary:attributes]; status=SecItemAdd((__bridge CFDictionaryRef)q,NULL); if (status==errSecDuplicateItem) status=SecItemUpdate((__bridge CFDictionaryRef)[self keychainQuery],(__bridge CFDictionaryRef)attributes); }
    self.keychainStatus=status;
    OVKDebugLog(@"[Session] Keychain write status=%ld", (long)status);
    if (status==errSecSuccess) { if ([[NSFileManager defaultManager] fileExistsAtPath:[self sessionFile]] && ![[NSFileManager defaultManager] removeItemAtPath:[self sessionFile] error:NULL]) return NO; self.protectedSessionStore=NO; return YES; }
#if TARGET_OS_IPHONE
    if ([self canUseProtectedSessionStore]) {
        NSString *file=[self sessionFile],*directory=[file stringByDeletingLastPathComponent];
        NSDictionary *dirAttributes=@{NSFileProtectionKey:NSFileProtectionComplete,NSFilePosixPermissions:@0700};
        if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:dirAttributes error:NULL]) return NO;
        if (![data writeToFile:file options:NSDataWritingAtomic|NSDataWritingFileProtectionComplete error:NULL]) return NO;
        if (![[NSFileManager defaultManager] setAttributes:@{NSFileProtectionKey:NSFileProtectionComplete,NSFilePosixPermissions:@0600} ofItemAtPath:file error:NULL]) { [[NSFileManager defaultManager] removeItemAtPath:file error:NULL]; return NO; }
        NSURL *url=[NSURL fileURLWithPath:directory]; if (![url setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:NULL]) { [[NSFileManager defaultManager] removeItemAtPath:file error:NULL]; return NO; }
        self.protectedSessionStore=YES;
        OVKDebugLog(@"[Session] saved to protected file");
        return YES;
    }
#endif
    return NO;
}
- (BOOL)save {
    if (!self.server.length || !self.token.length || self.userID.longLongValue<=0) { self.keychainStatus=errSecParam; return NO; }
    NSDictionary *old=[self readVault];
    // Never overwrite an existing protected vault that could not be read.
    if (!old && [[NSFileManager defaultManager] fileExistsAtPath:[self sessionFile]]) return NO;
    if (!old && ![self canUseProtectedSessionStore]) return NO;
    NSMutableDictionary *entry=[@{@"server":self.server,@"site":self.siteServer ?: self.server,@"token":self.token,@"id":self.userID,@"name":self.accountName ?: @""} mutableCopy];
    NSMutableArray *accounts=[NSMutableArray array];
    for (NSDictionary *account in [self accountsInVault:old]) if (!([OVKString(account[@"server"]) isEqual:self.server] && [OVKString(account[@"id"]) isEqual:OVKString(self.userID)])) [accounts addObject:account];
    [accounts addObject:[entry copy]]; entry[@"accounts"]=accounts; return [self writeVault:entry];
}
- (NSArray *)savedAccounts {
    NSMutableArray *metadata=[NSMutableArray array]; for (NSDictionary *entry in [self accountsInVault:[self readVault]]) [metadata addObject:@{@"server":entry[@"server"],@"id":entry[@"id"],@"name":OVKString(entry[@"name"])}]; return metadata;
}
- (BOOL)activateEntry:(NSDictionary *)entry {
    NSString *server=[OVKAPI validatedServer:OVKString(entry[@"server"])]; if (!server || !OVKString(entry[@"token"]).length || [entry[@"id"] longLongValue]<=0) return NO;
    self.server=server; self.siteServer=[OVKAPI validatedServer:OVKString(entry[@"site"])] ?: ([server isEqualToString:@"https://api.openvk.org"] ? @"https://openvk.org" : server); self.token=entry[@"token"]; self.userID=entry[@"id"]; self.accountName=OVKString(entry[@"name"]); self.demo=NO; return YES;
}
- (BOOL)switchToAccount:(NSDictionary *)account {
    NSDictionary *vault=[self readVault];
    for (NSDictionary *entry in [self accountsInVault:vault]) if ([OVKString(entry[@"server"]) isEqual:OVKString(account[@"server"])] && [OVKString(entry[@"id"]) isEqual:OVKString(account[@"id"])]) {
        NSMutableDictionary *next=[entry mutableCopy]; next[@"accounts"]=[self accountsInVault:vault]; if (![self writeVault:next]) return NO;
        [[NSNotificationCenter defaultCenter] postNotificationName:@"OVKSessionChanged" object:nil]; [self activateEntry:entry]; [[NSNotificationCenter defaultCenter] postNotificationName:@"OVKAccountChanged" object:nil]; return YES;
    } return NO;
}
- (void)beginAddingAccount { [[NSNotificationCenter defaultCenter] postNotificationName:@"OVKSessionChanged" object:nil]; self.token=nil; self.userID=nil; self.accountName=nil; self.demo=NO; [[NSNotificationCenter defaultCenter] postNotificationName:@"OVKLogout" object:nil]; }
- (NSString *)keychainErrorDescription {
    NSString *reason=@"Система не разрешила сохранить сеанс.";
    if (self.keychainStatus==-34018) reason=@"В подписи приложения отсутствуют или не совпадают права Keychain. Нужна корректная повторная подпись IPA.";
    else if (self.keychainStatus==errSecInteractionNotAllowed) reason=@"Keychain запретил доступ к сеансу. Если устройство заблокировано, разблокируйте его и повторите вход. На разблокированном устройстве также не удалось записать резервное защищённое хранилище.";
    else if (self.keychainStatus==errSecNotAvailable) reason=@"Системная служба Keychain недоступна.";
    else if (self.keychainStatus==errSecAuthFailed) reason=@"Система отклонила доступ приложения к Keychain.";
    return [NSString stringWithFormat:@"%@\nКод Keychain: %ld.\nВход работает до завершения приложения; после перезапуска потребуется войти снова.",reason,(long)self.keychainStatus];
}
- (BOOL)restore {
    BOOL restored = [self activateEntry:[self readVault]];
    OVKDebugLog(@"[Session] restore=%@ (Keychain status=%ld, protected file=%d)",
                restored ? @"success" : @"no active session", (long)self.keychainStatus,
                self.protectedSessionStore);
    return restored;
}
- (void)logout {
    NSURL *serverURL = [NSURL URLWithString:self.server];
    NSString *host = [serverURL host];
    NSURL *siteURL = [NSURL URLWithString:self.siteServer ?: self.server]; NSString *siteHost = [siteURL host];
    for (NSHTTPCookie *cookie in [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies]) {
        NSString *domain = [cookie.domain hasPrefix:@"."] ? [cookie.domain substringFromIndex:1] : cookie.domain;
        if ([host isEqualToString:domain] || [host hasSuffix:[@"." stringByAppendingString:domain]] || [siteHost isEqualToString:domain] || [siteHost hasSuffix:[@"." stringByAppendingString:domain]]) [[NSHTTPCookieStorage sharedHTTPCookieStorage] deleteCookie:cookie];
    }
    NSDictionary *vault=[self readVault]; if (!vault) return; NSMutableArray *remaining=[NSMutableArray array];
    for (NSDictionary *entry in [self accountsInVault:vault]) if (!([OVKString(entry[@"server"]) isEqual:self.server] && [OVKString(entry[@"id"]) isEqual:OVKString(self.userID)])) [remaining addObject:entry];
    if (remaining.count) { NSMutableDictionary *next=[remaining[0] mutableCopy]; next[@"accounts"]=remaining; if (![self writeVault:next]) return; }
    else {
        OSStatus status=SecItemDelete((__bridge CFDictionaryRef)[self keychainQuery]);
        if (status!=errSecSuccess && status!=errSecItemNotFound) {
            self.keychainStatus=status; if (!self.protectedSessionStore || ![self writeVault:@{}]) return;
            // An empty protected vault prevents an inaccessible old Keychain token from reappearing.
        } else if ([[NSFileManager defaultManager] fileExistsAtPath:[self sessionFile]] && ![[NSFileManager defaultManager] removeItemAtPath:[self sessionFile] error:NULL]) return;
    }
    self.token = nil; self.userID = nil; self.demo = NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"OVKLogout" object:nil];
}
- (void)call:(NSString *)method parameters:(NSDictionary *)parameters completion:(OVKCompletion)completion {
    if (self.demo) {
        NSString *path = [[NSBundle mainBundle] pathForResource:@"Demo" ofType:@"json"];
        NSDictionary *fixtures = OVKDictionary([NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] options:0 error:NULL]);
        id response = fixtures[method];
        if ([method isEqualToString:@"newsfeed.getGlobal"]) response = fixtures[@"newsfeed.get"];
        if ([method isEqualToString:@"audio.getFeed"]) response = fixtures[@"audio.get"];
        if ([method isEqualToString:@"audio.search"]) {
            NSString *query = OVKString(parameters[@"q"]);
            NSMutableArray *matches = [NSMutableArray array];
            for (NSDictionary *audio in OVKArray(OVKDictionary(fixtures[@"audio.get"])[@"items"])) {
                NSString *text = [NSString stringWithFormat:@"%@ %@", OVKString(audio[@"artist"]), OVKString(audio[@"title"])];
                if (query.length && [text rangeOfString:query options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch].location != NSNotFound) {
                    [matches addObject:audio];
                }
            }
            response = @{@"count":@(matches.count), @"items":matches};
        }
        if ([method isEqualToString:@"users.get"] && parameters[@"user_ids"]) {
            NSMutableArray *users = [NSMutableArray array];
            for (NSDictionary *user in OVKArray(fixtures[@"demo.users"])) if ([OVKString(user[@"id"]) isEqualToString:OVKString(parameters[@"user_ids"])]) [users addObject:user];
            response = users;
        }
        if ([method isEqualToString:@"wall.get"]) {
            NSMutableArray *posts = [NSMutableArray array];
            for (NSDictionary *post in OVKArray(fixtures[@"demo.posts"])) if (![OVKString(parameters[@"filter"]) isEqualToString:@"archived"]) if ([OVKString(post[@"owner_id"]) isEqualToString:OVKString(parameters[@"owner_id"])]) { if ([OVKString(parameters[@"filter"]) isEqualToString:@"owner"] && ![OVKString(post[@"from_id"]) isEqualToString:OVKString(post[@"owner_id"])]) continue; [posts addObject:post]; }
            response = @{@"count":@(posts.count),@"items":posts,@"profiles":fixtures[@"demo.users"],@"groups":OVKArray(OVKDictionary(fixtures[@"groups.get"])[@"items"])};
        }
        if ([method isEqualToString:@"groups.getById"]) { NSMutableArray *groups=[NSMutableArray array]; for (NSDictionary *group in OVKArray(fixtures[@"groups.getById"])) if ([OVKString(group[@"id"]) isEqualToString:OVKString(parameters[@"group_id"])]) [groups addObject:group]; response=groups; }
        if ([method isEqualToString:@"wall.getComments"]) {
            NSMutableArray *comments=[NSMutableArray array];
            for (NSDictionary *comment in OVKArray(OVKDictionary(fixtures[@"wall.getComments"])[@"items"])) if ([OVKString(comment[@"owner_id"]) isEqualToString:OVKString(parameters[@"owner_id"])] && [OVKString(comment[@"post_id"]) isEqualToString:OVKString(parameters[@"post_id"])]) [comments addObject:comment];
            response=@{@"count":@(comments.count),@"items":comments,@"can_post":@1,@"profiles":fixtures[@"demo.users"] ?: @[],@"groups":@[]};
        }
        if ([method isEqualToString:@"wall.getById"]) {
            NSMutableArray *posts=[NSMutableArray array];
            for (NSDictionary *post in OVKArray(fixtures[@"demo.posts"])) { NSString *key=[NSString stringWithFormat:@"%@_%@",OVKString(post[@"owner_id"]),OVKString(post[@"id"])]; if ([OVKString(parameters[@"posts"]) isEqualToString:key]) [posts addObject:post]; }
            response=@{@"items":posts,@"profiles":fixtures[@"demo.users"] ?: @[]};
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(response,response ? nil : OVKError(-10,@"В деморежиме отправка отключена")); }); return;
    }
    if (!self.token.length) {
        OVKDebugLog(@"[API] %@ skipped: no active session", method);
        completion(nil,OVKError(5,@"Войдите в аккаунт")); return;
    }
    NSString *sessionToken = [self.token copy];
    NSMutableDictionary *params = [parameters mutableCopy]; params[@"v"] = @"5.131"; params[@"access_token"] = self.token;
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *key in [[params allKeys] sortedArrayUsingSelector:@selector(compare:)]) [parts addObject:[NSString stringWithFormat:@"%@=%@",OVKEncode(key),OVKEncode(OVKString(params[key]))]];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/method/%@",self.server,method]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];
    request.HTTPMethod = @"POST"; request.HTTPShouldHandleCookies = YES;
    [request setValue:[@"Bearer " stringByAppendingString:self.token] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/x-www-form-urlencoded; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = [[parts componentsJoinedByString:@"&"] dataUsingEncoding:NSUTF8StringEncoding];
    OVKRequest *task = [[OVKRequest alloc] init];
    [task start:request completion:^(id response, NSError *error) {
        if (![sessionToken isEqualToString:self.token]) return;
        completion(response,error);
        if ([error.domain isEqualToString:@"OpenVK"] && error.code == 5) {
            OVKDebugLog(@"[Session] API rejected the session (code=5)");
            [self logout];
        }
    }];
}
- (void)uploadWallJPEG:(NSData *)jpeg completion:(OVKCompletion)completion {
    [self uploadJPEG:jpeg messagePeer:nil completion:completion];
}
- (void)uploadMessageJPEG:(NSData *)jpeg peer:(NSNumber *)peer completion:(OVKCompletion)completion {
    [self uploadJPEG:jpeg messagePeer:peer completion:completion];
}
- (void)uploadJPEG:(NSData *)jpeg messagePeer:(NSNumber *)peer completion:(OVKCompletion)completion {
    NSString *session=[self.token copy], *server=[self.server copy];
    if (!session.length || self.demo || !jpeg.length || jpeg.length>8*1024*1024) {
        completion(nil,OVKError(-7,@"Войдите в аккаунт и выберите фотографию размером до 8 МБ."));
        return;
    }
    // Upload URLs are pre-signed. Send the file without the API token, then save it through the authenticated endpoint.
    NSString *uploadMethod=peer ? @"photos.getMessagesUploadServer" : @"photos.getWallUploadServer";
    [self call:uploadMethod parameters:peer ? @{@"peer_id":peer} : @{} completion:^(id response,NSError *error) {
        if (error) { completion(nil,error); return; }
        NSURL *base=[NSURL URLWithString:[server stringByAppendingString:@"/"]];
        NSURL *url=[[NSURL URLWithString:OVKString(OVKDictionary(response)[@"upload_url"]) relativeToURL:base] absoluteURL];
        if (![url.scheme.lowercaseString isEqualToString:@"https"] || !url.host.length || url.user || url.password || !OVKString(OVKDictionary(response)[@"upload_url"]).length) {
            completion(nil,OVKError(-7,@"Сервер не предоставил защищённый адрес загрузки."));
            return;
        }
        NSString *boundary=[[NSProcessInfo processInfo] globallyUniqueString];
        NSString *header=[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"image.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n",boundary];
        NSMutableData *body=[NSMutableData dataWithData:[header dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:jpeg];
        [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n",boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:90];
        request.HTTPMethod=@"POST"; request.HTTPBody=body;
        [request setValue:[@"multipart/form-data; boundary=" stringByAppendingString:boundary] forHTTPHeaderField:@"Content-Type"];
        OVKRequest *upload=[[OVKRequest alloc] init]; upload.uploadResponse=YES;
        [upload start:request completion:^(id result,NSError *uploadError) {
            if (![session isEqualToString:self.token] || ![server isEqualToString:self.server]) {
                completion(nil,OVKError(-7,@"Сеанс изменился. Выберите фотографию снова.")); return;
            }
            if (uploadError) { completion(nil,uploadError); return; }
            NSDictionary *payload=OVKDictionary(result);
            if ([payload[@"response"] isKindOfClass:[NSDictionary class]]) payload=payload[@"response"];
            NSString *photo=OVKString(payload[@"photo"]), *hash=OVKString(payload[@"hash"]);
            if (!photo.length || !hash.length) { completion(nil,OVKError(-7,@"Сервер не подтвердил загрузку фотографии.")); return; }
            NSMutableDictionary *params=[@{@"photo":photo,@"hash":hash} mutableCopy];
            if (!peer) params[@"wallpost"]=@0;
            NSString *uploadServer=OVKString(payload[@"server"]);
            NSScanner *scanner=[NSScanner scannerWithString:uploadServer];
            NSInteger numericServer=0;
            if ([scanner scanInteger:&numericServer] && scanner.isAtEnd) params[@"server"]=@(numericServer);
            [self call:peer ? @"photos.saveMessagesPhoto" : @"photos.saveWallPhoto" parameters:params completion:completion];
        }];
    }];
}
- (NSString *)cacheRevisionKey:(NSString *)method scope:(NSString *)scope peer:(NSNumber *)peer {
    return [NSString stringWithFormat:@"OVKResponseRevision.%@.%@.%@",scope,method,OVKString(peer)];
}
- (void)invalidateCachedMethod:(NSString *)method peer:(NSNumber *)peer {
    if (!self.token.length || !self.userID || self.demo) return;
    NSString *scope=OVKCacheHash([NSString stringWithFormat:@"%@/%@",self.server,self.userID]);
    NSString *key=[self cacheRevisionKey:method scope:scope peer:peer];
    NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
    // A write advances only its endpoint's revision. Old in-flight reads can only populate the old revision.
    [defaults setInteger:[defaults integerForKey:key]+1 forKey:key];
}
- (void)call:(NSString *)method parameters:(NSDictionary *)parameters cached:(void (^)(id))cached completion:(OVKCompletion)completion {
    if (self.demo || !self.token.length || !self.userID || !cached) {
        [self call:method parameters:parameters completion:completion];
        return;
    }
    NSString *server=[self.server copy], *token=[self.token copy];
    NSArray *keys=[[parameters allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *parts=[NSMutableArray arrayWithCapacity:keys.count];
    for (NSString *key in keys) [parts addObject:[NSString stringWithFormat:@"%@=%@",OVKEncode(key),OVKEncode(OVKString(parameters[key]))]];
    NSString *scope=OVKCacheHash([NSString stringWithFormat:@"%@/%@",server,self.userID]);
    NSNumber *peer=[method isEqualToString:@"messages.getHistory"] ? parameters[@"peer_id"] : nil;
    NSString *revisionKey=[self cacheRevisionKey:method scope:scope peer:peer];
    NSInteger revision=[[NSUserDefaults standardUserDefaults] integerForKey:revisionKey];
    NSString *route=[NSString stringWithFormat:@"%@?%@",method,[parts componentsJoinedByString:@"&"]];
    if (revision) route=[route stringByAppendingFormat:@"#%ld",(long)revision];
    NSString *name=OVKCacheHash(route);
    NSURL *root=[[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] lastObject];
    NSURL *cacheRoot=[root URLByAppendingPathComponent:@"OpenVKResponses-v1" isDirectory:YES];
    NSURL *directory=[cacheRoot URLByAppendingPathComponent:scope isDirectory:YES];
    NSURL *file=[directory URLByAppendingPathComponent:name];
    dispatch_async(OVKResponseCacheQueue(), ^{
        NSData *data=[NSData dataWithContentsOfURL:file];
        id saved=data.length && data.length<=768*1024 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![self.token isEqualToString:token] || ![self.server isEqualToString:server]) return;
            if (saved) cached(saved);
            [self call:method parameters:parameters completion:^(id response,NSError *error) {
                if (!error && [NSJSONSerialization isValidJSONObject:response]) dispatch_async(OVKResponseCacheQueue(), ^{
                    NSData *payload=[NSJSONSerialization dataWithJSONObject:response options:0 error:NULL];
                    if (!payload.length || payload.length>768*1024) return;
                    NSFileManager *manager=[NSFileManager defaultManager];
                    if (![manager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:NULL]) return;
                    NSDataWritingOptions options=NSDataWritingAtomic;
#if TARGET_OS_IPHONE
                    options|=NSDataWritingFileProtectionComplete;
#endif
                    if ([payload writeToURL:file options:options error:NULL]) OVKTrimDiskCache(directory,24*1024*1024,160);
                });
                completion(response,error);
            }];
        });
    });
}
@end
