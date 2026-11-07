#import <UIKit/UIKit.h>
@interface OVKSetupController : UITableViewController
@property (copy, nonatomic) void (^completed)(void);
@end
