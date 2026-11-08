#import <UIKit/UIKit.h>
@interface OVKComposeController : UIViewController
@property (strong, nonatomic) NSNumber *identifier;
@property (assign, nonatomic) BOOL message;
@property (strong, nonatomic) NSNumber *postID;
@property (strong, nonatomic) NSNumber *replyID;
@property (copy, nonatomic) NSString *replyName;
@property (copy, nonatomic) NSString *initialText;
@property (copy, nonatomic) NSDictionary *editingPost;
@property (copy, nonatomic) NSDictionary *editingMessage;
@property (assign, nonatomic) BOOL showAttachmentPickerOnOpen;
@property (copy, nonatomic) void (^savedMessage)(NSDictionary *message);
@property (copy, nonatomic) void (^sent)(void);
@end
@interface OVKCommentsController : UITableViewController <UIActionSheetDelegate>
- (id)initWithPost:(NSDictionary *)post;
@end
