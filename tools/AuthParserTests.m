#import <Foundation/Foundation.h>
#import "OVKAPI.h"
@interface NSObject (OVKParserTestEntry)
- (void)connectionDidFinishLoading:(NSURLConnection *)connection;
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error;
@end
static void Expect(BOOL passed, NSString *message) {
    if (!passed) { fprintf(stderr,"FAIL: %s\n",[message UTF8String]); exit(1); }
}
static NSDictionary *Parse(NSInteger status, BOOL token, id body, BOOL cancelled401) {
    Class requestClass = NSClassFromString(@"OVKRequest"); Expect(requestClass != Nil,@"Request class linked");
    NSObject *request = [[requestClass alloc] init];
    NSData *data = [body isKindOfClass:[NSData class]] ? body : [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
    [request setValue:[data mutableCopy] forKey:@"data"];
    [request setValue:@(status) forKey:@"status"]; [request setValue:@(token) forKey:@"tokenResponse"];
    [request setValue:[NSURL URLWithString:@"https://example.invalid/token"] forKey:@"origin"];
    [request setValue:@"application/json" forKey:@"mimeType"];
    __block id observedResult = nil; __block NSError *observedError = nil; __block NSUInteger calls = 0;
    OVKCompletion completion = ^(id result,NSError *error){ observedResult = result; observedError = error; calls++; };
    [request setValue:completion forKey:@"completion"];
    if (cancelled401) [request connection:nil didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorUserCancelledAuthentication userInfo:nil]];
    else [request connectionDidFinishLoading:nil];
    Expect(calls == 1,@"Exactly one completion");
    return @{@"result":observedResult ?: [NSNull null],@"error":observedError ?: [NSNull null]};
}
static void AuthError(NSDictionary *parsed, NSString *reason) {
    NSError *error = parsed[@"error"];
    Expect([error isKindOfClass:[NSError class]],@"Authentication failure returned");
    Expect([error.userInfo[@"OVKAuthReason"] isEqual:reason],@"Authentication reason preserved");
    Expect(parsed[@"result"] == [NSNull null],@"No successful result on auth failure");
}
int main(void) {
    @autoreleasepool {
        NSDictionary *ok = Parse(200,YES,@{@"access_token":@"fake-test-token",@"user_id":@7},NO);
        Expect([ok[@"result"][@"access_token"] isEqual:@"fake-test-token"],@"Top-level token response");
        NSDictionary *validation = @{@"error":@"need_validation",@"validation_type":@"2fa_app",@"validation_sid":@"fake-test-sid"};
        AuthError(Parse(401,YES,validation,NO),@"need_validation");
        AuthError(Parse(401,YES,validation,YES),@"need_validation");
        AuthError(Parse(400,YES,@{@"error":@{@"error_code":@28,@"error_msg":@"Invalid username or password"}},NO),@"invalid_password");
        AuthError(Parse(400,YES,@{@"error_code":@28,@"error_msg":@"Invalid username or password"},NO),@"invalid_password");
        AuthError(Parse(400,YES,@{@"error_code":@28,@"error_msg":@"Invalid 2FA code"},NO),@"need_validation");
        AuthError(Parse(401,YES,@{@"error":@"invalid_password"},NO),@"invalid_password");
        NSDictionary *apiError = Parse(400,NO,@{@"error":@{@"error_code":@5,@"error_msg":@"User authorization failed"}},NO);
        Expect([apiError[@"error"] code] == 5,@"JSON error survives HTTP 400");
        NSData *html = [@"<html>Forbidden</html>" dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *blocked = Parse(403,YES,html,NO);
        Expect([blocked[@"error"] code] == 403,@"HTML 403 remains server error");
        Expect(![[blocked[@"error"] userInfo][@"OVKAuthReason"] isEqual:@"invalid_password"],@"HTML 403 is not a password error");
        NSDictionary *users = Parse(200,NO,@{@"response":@[@{@"id":@7}]},NO);
        Expect([users[@"result"] isKindOfClass:[NSArray class]],@"Standard API array response");
        NSString *sample = @"pass &+?=пароль";
        NSDictionary *decoded = OVKQuery([@"password=" stringByAppendingString:OVKEncode(sample)]);
        Expect([decoded[@"password"] isEqual:sample],@"Form encoding preserves symbols and Unicode");
        puts("PASS: auth response, 2FA, cancelled 401, wrapped/flat errors, API HTTP 400, HTML 403, form encoding");
    }
    return 0;
}
