#import "OVKLanguage.h"
#import "OVKWallModel.h"
#import "OVKAPI.h"
static long long WallID(id value) { NSString *text=OVKString(value); NSScanner *scanner=[NSScanner scannerWithString:text]; long long result=0; return text.length && [scanner scanLongLong:&result] && [scanner isAtEnd] ? result : 0; }
NSDictionary *OVKPostReference(NSDictionary *post) {
    long long owner=WallID(post[@"owner_id"] ?: post[@"to_id"] ?: post[@"source_id"] ?: post[@"from_id"]);
    long long identifier=WallID(post[@"id"] ?: post[@"post_id"]);
    return owner!=0 && identifier>0 ? @{@"owner_id":@(owner),@"post_id":@(identifier)} : nil;
}
NSDictionary *OVKWallWriteParameters(NSString *kind,id owner,id post,id reply,NSString *message,NSNumber *randomID,NSError **error) {
    NSString *text=[OVKString(message) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    long long ownerID=WallID(owner),postID=WallID(post),replyID=WallID(reply);
    if (!text.length || !ownerID || (![@[@"post",@"comment",@"message"] containsObject:kind ?: @""]) || ([kind isEqualToString:@"comment"] && postID<=0) || (reply && replyID<=0)) {
        if (error) *error=[NSError errorWithDomain:@"OvkWall" code:1 userInfo:@{NSLocalizedDescriptionKey:!text.length ? OVKL(@"Введите текст") : @"Не удалось определить адрес записи или получателя"}]; return nil;
    }
    NSMutableDictionary *params=[@{@"message":text} mutableCopy];
    if ([kind isEqualToString:@"message"]) { params[@"peer_id"]=@(ownerID); if (randomID) params[@"random_id"]=randomID; }
    else { params[@"owner_id"]=@(ownerID); if ([kind isEqualToString:@"comment"]) { params[@"post_id"]=@(postID); if (replyID>0) params[@"reply_to_comment"]=@(replyID); } }
    return params;
}
BOOL OVKPostAllowsAction(NSDictionary *post,NSString *action,NSNumber *currentUser) {
    NSDictionary *reference=OVKPostReference(post); if (!reference) return NO;
    if ([action isEqual:@"like"]) { NSDictionary *likes=OVKDictionary(post[@"likes"]); return [OVKString(likes[@"user_likes"]) boolValue] || !likes[@"can_like"] || [OVKString(likes[@"can_like"]) boolValue]; }
    NSString *key=@{@"archive":@"can_archive",@"reveal":@"can_archive",@"delete":@"can_delete",@"pin":@"can_pin",@"unpin":@"can_pin"}[action]; if (!key) return NO;
    if (post[key]) return [OVKString(post[key]) boolValue];
    return WallID(currentUser)>0 && WallID(reference[@"owner_id"])==WallID(currentUser);
}
NSDictionary *OVKPostActionParameters(NSDictionary *post,NSString *action,NSNumber *currentUser) {
    if (!OVKPostAllowsAction(post,action,currentUser)) return nil;
    NSDictionary *reference=OVKPostReference(post);
    if ([action isEqual:@"like"]) return @{@"type":@"post",@"owner_id":reference[@"owner_id"],@"item_id":reference[@"post_id"]};
    return reference;
}
