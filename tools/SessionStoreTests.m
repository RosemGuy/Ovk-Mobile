#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import "OVKAPI.h"
static NSData *stored;
static OSStatus readFailure=errSecSuccess,writeFailure=errSecSuccess;
OSStatus SecItemCopyMatching(CFDictionaryRef query,CFTypeRef *result) {
    if (readFailure) return readFailure;
    if (!stored) return errSecItemNotFound;
    if (result) *result=CFBridgingRetain(stored);
    return errSecSuccess;
}
OSStatus SecItemUpdate(CFDictionaryRef query,CFDictionaryRef values) {
    if (writeFailure) return writeFailure;
    if (!stored) return errSecItemNotFound;
    stored=[(__bridge NSDictionary *)values objectForKey:(__bridge id)kSecValueData]; return errSecSuccess;
}
OSStatus SecItemAdd(CFDictionaryRef values,CFTypeRef *result) {
    if (writeFailure) return writeFailure;
    if (stored) return errSecDuplicateItem;
    stored=[(__bridge NSDictionary *)values objectForKey:(__bridge id)kSecValueData]; return errSecSuccess;
}
OSStatus SecItemDelete(CFDictionaryRef query) { stored=nil; return errSecSuccess; }
@interface SessionTestAPI : OVKAPI
@property (copy, nonatomic) NSString *testFile;
@end
@implementation SessionTestAPI
- (NSString *)sessionFile { return self.testFile; }
@end
static void Check(BOOL condition,NSString *message) { if (!condition) { NSLog(@"FAIL: %@",message); exit(1); } }
int main(void) { @autoreleasepool {
    SessionTestAPI *api=[[SessionTestAPI alloc] init]; api.testFile=[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
    NSDictionary *legacy=@{@"server":@"https://one.example",@"site":@"https://one.example",@"token":@"fixture-one",@"id":@1};
    stored=[NSJSONSerialization dataWithJSONObject:legacy options:0 error:NULL];
    Check([api restore] && [api.token isEqual:@"fixture-one"],@"legacy restore");
    api.accountName=@"First"; Check([api save],@"legacy migration");
    api.userID=@2; api.token=@"fixture-two"; api.accountName=@"Second"; Check([api save],@"second account saved");
    Check(api.savedAccounts.count==2,@"both accounts preserved");
    for (NSDictionary *metadata in api.savedAccounts) Check(metadata[@"token"]==nil,@"metadata contains no tokens");
    Check([api switchToAccount:@{@"server":@"https://one.example",@"id":@1}] && [api.token isEqual:@"fixture-one"],@"switch restores matching token");
    api.server=@"https://two.example"; api.siteServer=api.server; api.userID=@1; api.token=@"fixture-three"; Check([api save],@"same ID on another instance");
    Check(api.savedAccounts.count==3,@"instance-scoped identity");
    [api logout]; Check(api.token==nil && api.savedAccounts.count==2,@"logout removes only current account");
    Check([api restore],@"remaining account is recoverable");
    NSData *previous=[stored copy]; writeFailure=errSecAuthFailed; Check(![api save] && [stored isEqual:previous],@"failed write preserves vault"); writeFailure=errSecSuccess;
    readFailure=errSecDecode; Check(![api save] && [stored isEqual:previous],@"failed read cannot overwrite vault"); readFailure=errSecSuccess;
    writeFailure=errSecInteractionNotAllowed; Check(![api save] && [stored isEqual:previous],@"interaction-denied write preserves vault when fallback unavailable"); writeFailure=errSecSuccess;
    readFailure=errSecInteractionNotAllowed; Check(![api save] && [stored isEqual:previous],@"interaction-denied read preserves vault when fallback unavailable"); readFailure=errSecSuccess;
    NSLog(@"PASS: migration, multiple accounts, instance isolation, logout and failure preservation (mock Keychain)");
} return 0; }
