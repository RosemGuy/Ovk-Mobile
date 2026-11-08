#import <Foundation/Foundation.h>
#import "OVKWallModel.h"
static void Expect(BOOL ok,const char *text) { if (!ok) { fprintf(stderr,"FAIL: %s\n",text); exit(1); } }
int main(void) {
 @autoreleasepool {
  NSDictionary *ref=OVKPostReference(@{@"owner_id":@(-42),@"from_id":@3,@"id":@7});
  Expect([ref[@"owner_id"] isEqual:@(-42)] && [ref[@"post_id"] isEqual:@7],"Wall owner must not be confused with author");
  Expect(!OVKPostReference(@{@"id":@0,@"owner_id":@1}),"Invalid post rejected");
  Expect(!OVKPostReference(@{@"id":@"12bad",@"owner_id":@1}),"Malformed numeric ID is not silently truncated");
  NSError *error=nil;
  NSDictionary *params=OVKWallWriteParameters(@"comment",@(-42),@7,@99,@"  Привет, мир! 🎵  ",nil,&error);
  Expect(!error && [params[@"owner_id"] isEqual:@(-42)] && [params[@"post_id"] isEqual:@7] && [params[@"reply_to_comment"] isEqual:@99],"Reply routes to exact post/comment");
  Expect([params[@"message"] isEqual:@"Привет, мир! 🎵"],"Unicode comment preserved");
  params=OVKWallWriteParameters(@"post",@1,nil,nil,@"Запись",nil,&error);
  Expect(params && !params[@"post_id"] && !params[@"reply_to_comment"],"Post is not sent as comment");
  params=OVKWallWriteParameters(@"message",@2000000001,nil,nil,@"Привет",@123,&error);
  Expect([params[@"peer_id"] isEqual:@2000000001] && [params[@"random_id"] isEqual:@123] && !params[@"owner_id"],"Message route and dedup ID preserved");
  Expect(!OVKWallWriteParameters(@"comment",@1,nil,nil,@"Text",nil,&error),"Missing post ID rejected");
  Expect(!OVKWallWriteParameters(@"post",nil,nil,nil,@"Text",nil,&error),"Missing owner rejected without nil dictionary crash");
  Expect(!OVKWallWriteParameters(@"post",@1,nil,nil,@" \n ",nil,&error),"Empty text rejected");
  Expect(!OVKWallWriteParameters(@"comment",@1,@2,@(-1),@"Text",nil,&error),"Invalid reply rejected");
  NSDictionary *owned=@{@"owner_id":@1,@"id":@2};
  Expect(OVKPostAllowsAction(owned,@"archive",@1),"Own-wall legacy permission fallback");
  Expect(!OVKPostAllowsAction(@{@"owner_id":@1,@"id":@2,@"can_archive":@0},@"archive",@1),"Explicit denied permission overrides own-wall fallback");
  Expect(!OVKPostAllowsAction(owned,@"delete",@3),"Cannot delete another wall without permission");
  Expect(OVKPostAllowsAction(@{@"owner_id":@(-4),@"id":@2,@"can_pin":@1},@"pin",@1),"Server-granted group permission supported");
  NSDictionary *like=OVKPostActionParameters(owned,@"like",@1);
  Expect([like[@"item_id"] isEqual:@2] && !like[@"post_id"],"Likes use item_id while wall mutations use post_id");
  Expect(!OVKPostActionParameters(@{@"owner_id":@1},@"like",@1),"Invalid post cannot be liked");
  NSDictionary *first=@{@"id":@1,@"date":@10};
  NSDictionary *second=@{@"id":@2,@"date":@10};
  NSDictionary *third=@{@"id":@3,@"date":@10};
  NSDictionary *fourth=@{@"id":@4,@"date":@11};
  Expect([OVKMergeChatHistory(@[second,fourth],@[third,second,first],YES) isEqual:@[first,second,third,fourth]],"Older page merges overlap without shifting a missing message out of order");
  Expect([OVKMergeChatHistory(@[first,second,third],@[fourth,third],NO) isEqual:@[first,second,third,fourth]],"Refreshing the latest page keeps previously loaded older history");
  Expect([OVKMergeChatHistory(@[first,second,third,fourth],@[fourth,second],NO) isEqual:@[first,second,fourth]],"Fresh page drops an item deleted within its range");
  Expect(OVKPostAllowsAction(@{@"owner_id":@(-4),@"from_id":@1,@"id":@2},@"edit",@1),"Author can edit their post on another wall");
  Expect(!OVKPostAllowsAction(@{@"owner_id":@1,@"from_id":@3,@"id":@2},@"edit",@1),"Owning a wall does not make someone else's post editable");
  Expect(!OVKPostAllowsAction(@{@"owner_id":@1,@"from_id":@1,@"id":@2,@"can_edit":@0},@"edit",@1),"Explicit edit denial is honored");
  Expect(OVKIsOwnChatMessage(@{@"id":@3,@"from_id":@1},@1),"Own message can be selected");
  Expect(!OVKIsOwnChatMessage(@{@"id":@3,@"from_id":@2,@"out":@YES},@1),"Sender identity overrides an inconsistent outgoing flag");
  Expect(!OVKIsOwnChatMessage(@{@"conversation_message_id":@3,@"out":@YES},@1),"Bulk actions need a global message ID");
  Expect([OVKAttachmentReference(@"photo",@{@"owner_id":@(-4),@"id":@2}) isEqual:@"photo-4_2"],"Attachment retains a signed owner ID");
  Expect(!OVKAttachmentReference(@"photo",@{@"owner_id":@1,@"id":@"2bad"}),"Malformed attachment IDs are rejected");
  Expect([OVKConfirmedMessageDeletions(@{@"3":@1,@"4":@0},@[@"3",@"4"]) isEqual:@[@"3"]],"Partial deletion only removes the acknowledged row");
  Expect([OVKConfirmedMessageDeletions(@[@{@"message_id":@3,@"response":@1}],@[@"3",@"4"]) isEqual:@[@"3"]],"VK list results acknowledge IDs individually");
  Expect([OVKConfirmedMessageDeletions(@1,@[@"3",@"4"]) isEqual:@[@"3",@"4"]],"Legacy broker acknowledges the whole batch with one");
  puts("PASS: post/comment/message addressing, Unicode, invalid IDs, validation");
 } return 0;
}
