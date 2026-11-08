#import <Foundation/Foundation.h>
typedef void (^OVKCompletion)(id result, NSError *error);
NSString *OVKString(id value);
NSDictionary *OVKDictionary(id value);
NSArray *OVKArray(id value);
NSString *OVKEncode(NSString *value);
NSDictionary *OVKQuery(NSString *query);
NSString *OVKCacheHash(NSString *text);
void OVKTrimDiskCache(NSURL *directory, NSUInteger byteLimit, NSUInteger entryLimit);
@protocol OVKCancellable <NSObject>
- (void)cancel;
@end
@interface OVKAPI : NSObject
@property (copy, nonatomic) NSString *server;
@property (copy, nonatomic) NSString *siteServer;
@property (copy, nonatomic) NSString *token;
@property (strong, nonatomic) NSNumber *userID;
@property (assign, nonatomic) BOOL demo;
@property (assign, nonatomic, readonly) NSInteger keychainStatus;
@property (copy, nonatomic) NSString *accountName;
@property (assign, nonatomic, readonly) BOOL protectedSessionStore;
- (NSString *)keychainErrorDescription;
- (NSArray *)savedAccounts;
- (BOOL)switchToAccount:(NSDictionary *)account;
- (void)beginAddingAccount;
+ (OVKAPI *)shared;
+ (NSString *)requestUserAgent;
+ (NSString *)validatedServer:(NSString *)input;
- (void)call:(NSString *)method parameters:(NSDictionary *)parameters completion:(OVKCompletion)completion;
- (void)call:(NSString *)method parameters:(NSDictionary *)parameters cached:(void (^)(id response))cached completion:(OVKCompletion)completion;
- (void)uploadWallJPEG:(NSData *)jpeg completion:(OVKCompletion)completion;
- (void)uploadMessageJPEG:(NSData *)jpeg peer:(NSNumber *)peer completion:(OVKCompletion)completion;
- (void)invalidateCachedMethod:(NSString *)method peer:(NSNumber *)peer;
- (id<OVKCancellable>)authenticateUsername:(NSString *)username password:(NSString *)password code:(NSString *)code completion:(OVKCompletion)completion;
- (id<OVKCancellable>)checkConnection:(OVKCompletion)completion;
- (BOOL)restore;
- (BOOL)save;
- (void)logout;
@end
