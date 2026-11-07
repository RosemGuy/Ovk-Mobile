#import "OVKSocialModel.h"
#import "OVKAPI.h"
#import "OVKLanguage.h"
#import <limits.h>
static long long SocialID(id value) { NSString *text=OVKString(value); NSScanner *scanner=[NSScanner scannerWithString:text]; long long result=0; return text.length && [scanner scanLongLong:&result] && scanner.isAtEnd && result!=LLONG_MIN ? result : 0; }
NSArray *OVKSocialItems(id response) {
    NSArray *items=[response isKindOfClass:[NSArray class]] ? response : OVKArray(OVKDictionary(response)[@"items"]);
    NSMutableArray *valid=[NSMutableArray array]; for (id item in items) if ([item isKindOfClass:[NSDictionary class]]) [valid addObject:item]; return valid;
}
NSNumber *OVKNotificationActor(NSDictionary *item) {
    NSDictionary *feedback=OVKDictionary(item[@"feedback"]); NSArray *items=OVKArray(feedback[@"items"]);
    id value=feedback[@"from_id"] ?: OVKDictionary(items.count ? items[0] : nil)[@"from_id"] ?: item[@"from_id"];
    long long actor=SocialID(value); return actor ? @(actor) : nil;
}
NSDictionary *OVKNotificationPost(NSDictionary *item) {
    NSDictionary *parent=OVKDictionary(item[@"parent"]); NSString *type=OVKString(item[@"type"]), *parentType=OVKString(parent[@"type"]);
    // Comment IDs and photo IDs must never be mistaken for post IDs.
    if (!parent[@"post_id"] && !OVKDictionary(parent[@"post"]).count && ![@[@"like_post",@"copy_post",@"comment_post",@"wall"] containsObject:type] && ![parentType isEqualToString:@"post"]) return nil;
    NSDictionary *post=OVKDictionary(parent[@"post"]); if (!post.count) post=parent;
    long long owner=SocialID(post[@"owner_id"] ?: post[@"to_id"]), identifier=SocialID(post[@"post_id"] ?: post[@"id"]);
    return owner && identifier>0 ? @{@"owner_id":@(owner),@"id":@(identifier)} : nil;
}
NSString *OVKNotificationSummary(NSDictionary *item) {
    NSString *type=OVKString(item[@"type"]);
    NSDictionary *labels=@{@"like_post":OVKL(@"Нравится ваша запись"),@"like_comment":OVKL(@"Нравится ваш комментарий"),@"like_photo":OVKL(@"Нравится ваша фотография"),@"comment_post":OVKL(@"Комментарий к записи"),@"comment_photo":OVKL(@"Комментарий к фотографии"),@"reply_comment":OVKL(@"Ответ на комментарий"),@"reply_comment_photo":OVKL(@"Ответ на комментарий"),@"copy_post":OVKL(@"Поделились вашей записью"),@"follow":OVKL(@"Новый подписчик"),@"friend_accepted":OVKL(@"Заявка в друзья принята"),@"mention":OVKL(@"Вас упомянули"),@"wall":OVKL(@"Новая запись на стене")};
    return labels[type] ?: OVKL(@"Новое уведомление");
}
