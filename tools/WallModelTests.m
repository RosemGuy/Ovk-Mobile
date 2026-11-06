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
  puts("PASS: post/comment/message addressing, Unicode, invalid IDs, validation");
 } return 0;
}
