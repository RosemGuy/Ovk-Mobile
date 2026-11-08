#import "OVKLanguage.h"
#import "OVKWallModel.h"
#import "OVKAPI.h"
static long long WallID(id value) { NSString *text=OVKString(value); NSScanner *scanner=[NSScanner scannerWithString:text]; long long result=0; return text.length && [scanner scanLongLong:&result] && [scanner isAtEnd] ? result : 0; }
NSString *OVKChatMessageKey(NSDictionary *message) {
    NSString *key=OVKString(message[@"id"]);
    return key.length && ![key isEqualToString:@"0"] ? key : OVKString(message[@"conversation_message_id"]);
}
NSString *OVKAttachmentReference(NSString *type, NSDictionary *object) {
    if (![@[@"photo",@"audio",@"video",@"doc",@"note",@"poll",@"wall"] containsObject:type ?: @""]) return nil;
    long long owner=WallID(object[@"owner_id"] ?: object[@"oid"] ?: object[@"to_id"] ?: object[@"user_id"] ?: object[@"author_id"] ?: object[@"from_id"]);
    long long identifier=WallID(object[@"id"] ?: object[@"aid"] ?: object[@"pid"] ?: object[@"vid"] ?: object[@"post_id"]);
    return owner && identifier>0 ? [NSString stringWithFormat:@"%@%lld_%lld",type,owner,identifier] : nil;
}
BOOL OVKIsOwnChatMessage(NSDictionary *message, NSNumber *user) {
    long long me=WallID(user), sender=WallID(message[@"from_id"]);
    return me>0 && WallID(message[@"id"])>0 && (sender ? sender==me : [OVKString(message[@"out"]) boolValue]);
}
NSArray *OVKConfirmedMessageDeletions(id response, NSArray *requested) {
    // VK-compatible servers return either an ID-to-status map or a list of status records.
    if ([OVKString(response) isEqualToString:@"1"]) return requested;
    NSMutableDictionary *statuses=[OVKDictionary(response) mutableCopy];
    NSArray *records=[response isKindOfClass:[NSArray class]] ? response : OVKArray(statuses[@"items"]);
    for (id value in records) {
        NSDictionary *record=OVKDictionary(value);
        NSString *key=OVKString(record[@"message_id"] ?: record[@"id"]);
        id status=record[@"response"] ?: record[@"result"] ?: record[@"deleted"];
        if (key.length && status) statuses[key]=status;
    }
    NSMutableArray *confirmed=[NSMutableArray array];
    for (NSString *key in requested) if ([OVKString(statuses[key]) isEqualToString:@"1"]) [confirmed addObject:key];
    return confirmed;
}
static NSComparisonResult OVKChatMessageOrder(NSDictionary *a, NSDictionary *b) {
    double firstDate=[OVKString(a[@"date"]) doubleValue], secondDate=[OVKString(b[@"date"]) doubleValue];
    if (firstDate<secondDate) return NSOrderedAscending;
    if (firstDate>secondDate) return NSOrderedDescending;
    long long firstID=[OVKChatMessageKey(a) longLongValue], secondID=[OVKChatMessageKey(b) longLongValue];
    return firstID<secondID ? NSOrderedAscending : (firstID>secondID ? NSOrderedDescending : NSOrderedSame);
}
NSArray *OVKMergeChatHistory(NSArray *current, NSArray *newestFirst, BOOL olderPage) {
    NSMutableArray *incoming=[NSMutableArray array];
    NSMutableSet *keys=[NSMutableSet set];
    for (id value in [newestFirst reverseObjectEnumerator]) {
        if (![value isKindOfClass:[NSDictionary class]]) continue;
        NSString *key=OVKChatMessageKey(value);
        if (key.length && [keys containsObject:key]) continue;
        if (key.length) [keys addObject:key];
        [incoming addObject:value];
    }
    NSDictionary *first=incoming.count ? incoming[0] : nil;
    NSMutableArray *merged=[NSMutableArray arrayWithCapacity:current.count+incoming.count];
    // The fresh page owns its time range. Keep only messages that predate it on a latest-page refresh.
    for (NSDictionary *message in current) {
        if ([keys containsObject:OVKChatMessageKey(message)]) continue;
        if (olderPage || (first && OVKChatMessageOrder(message,first)==NSOrderedAscending)) [merged addObject:message];
    }
    [merged addObjectsFromArray:incoming];
    [merged sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) {
        return OVKChatMessageOrder(a,b);
    }];
    return merged;
}
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
    if ([action isEqual:@"edit"]) {
        long long me=WallID(currentUser), author=WallID(post[@"from_id"] ?: post[@"source_id"] ?: reference[@"owner_id"]);
        return me>0 && author==me && (!post[@"can_edit"] || [OVKString(post[@"can_edit"]) boolValue]);
    }
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
