#import "OVKTrust.h"
static BOOL OVKTrustAccepted(SecTrustRef trust) {
    SecTrustResultType result = kSecTrustResultInvalid;
    return SecTrustEvaluate(trust,&result) == errSecSuccess && (result == kSecTrustResultUnspecified || result == kSecTrustResultProceed);
}
BOOL OVKEvaluateServerTrust(SecTrustRef trust, NSString *hostname, NSData *additionalRoot) {
    if (!trust || !hostname.length) return NO;
    SecPolicyRef policy = SecPolicyCreateSSL(YES,(__bridge CFStringRef)hostname);
    if (!policy) return NO;
    OSStatus policyStatus = SecTrustSetPolicies(trust,policy); CFRelease(policy);
    if (policyStatus != errSecSuccess) return NO;
    if (OVKTrustAccepted(trust)) return YES;
    if (!additionalRoot.length) return NO;
    SecCertificateRef root = SecCertificateCreateWithData(NULL,(__bridge CFDataRef)additionalRoot);
    if (!root) return NO;
    NSArray *anchors = @[(__bridge id)root];
    OSStatus anchorStatus = SecTrustSetAnchorCertificates(trust,(__bridge CFArrayRef)anchors); CFRelease(root);
    if (anchorStatus != errSecSuccess) return NO;
    return OVKTrustAccepted(trust);
}
