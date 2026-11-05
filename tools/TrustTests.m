#import <Foundation/Foundation.h>
#import "OVKTrust.h"
static void Expect(BOOL value,const char *message) { if (!value) { fprintf(stderr,"FAIL: %s\n",message); exit(1); } }
static SecTrustRef NewTrust(NSData *leafData,NSData *rootData) {
    SecCertificateRef leaf = SecCertificateCreateWithData(NULL,(__bridge CFDataRef)leafData);
    SecCertificateRef root = SecCertificateCreateWithData(NULL,(__bridge CFDataRef)rootData);
    Expect(leaf && root,"Test certificates load");
    SecPolicyRef policy = SecPolicyCreateSSL(YES,CFSTR("api.example.invalid"));
    NSArray *chain = @[(__bridge id)leaf,(__bridge id)root]; SecTrustRef trust = NULL;
    OSStatus status = SecTrustCreateWithCertificates((__bridge CFArrayRef)chain,policy,&trust);
    CFRelease(leaf); CFRelease(root); CFRelease(policy); Expect(status == errSecSuccess && trust,"Test trust created"); return trust;
}
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        Expect(argc == 3,"Supply test leaf and root DER paths");
        NSData *leaf = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
        NSData *root = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[2]]];
        SecTrustRef valid = NewTrust(leaf,root); Expect(OVKEvaluateServerTrust(valid,@"api.example.invalid",root),"Additional CA accepts valid matching server"); CFRelease(valid);
        SecTrustRef wrongHost = NewTrust(leaf,root); Expect(!OVKEvaluateServerTrust(wrongHost,@"wrong.example.invalid",root),"Wrong hostname rejected"); CFRelease(wrongHost);
        SecTrustRef unknown = NewTrust(leaf,root); Expect(!OVKEvaluateServerTrust(unknown,@"api.example.invalid",nil),"Unknown CA rejected without anchor"); CFRelease(unknown);
        SecTrustRef malformed = NewTrust(leaf,root); Expect(!OVKEvaluateServerTrust(malformed,@"api.example.invalid",[@"bad certificate" dataUsingEncoding:NSUTF8StringEncoding]),"Malformed anchor rejected"); CFRelease(malformed);
        SecTrustRef expired = NewTrust(leaf,root); NSDate *future = [NSDate dateWithTimeIntervalSinceNow:60*60*24*30]; SecTrustSetVerifyDate(expired,(__bridge CFDateRef)future);
        Expect(!OVKEvaluateServerTrust(expired,@"api.example.invalid",root),"Expired server certificate rejected"); CFRelease(expired);
        puts("PASS: additional CA, hostname mismatch, unknown CA, malformed anchor, certificate expiry");
    }
    return 0;
}
