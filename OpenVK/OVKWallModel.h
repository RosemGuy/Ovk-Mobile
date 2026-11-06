#import <Foundation/Foundation.h>
NSDictionary *OVKPostReference(NSDictionary *post);
NSDictionary *OVKWallWriteParameters(NSString *kind,id owner,id post,id reply,NSString *message,NSNumber *randomID,NSError **error);
BOOL OVKPostAllowsAction(NSDictionary *post,NSString *action,NSNumber *currentUser);
NSDictionary *OVKPostActionParameters(NSDictionary *post,NSString *action,NSNumber *currentUser);
