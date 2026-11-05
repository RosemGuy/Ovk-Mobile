#import <Foundation/Foundation.h>
#import <Security/Security.h>
// Preserves SSL hostname and validity checks. Tries system trust before an additional CA.
BOOL OVKEvaluateServerTrust(SecTrustRef trust, NSString *hostname, NSData *additionalRoot);
