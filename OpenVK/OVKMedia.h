#import <UIKit/UIKit.h>
#import "OVKAPI.h"
#import "OVKMediaModel.h"
typedef void (^OVKDownloadCompletion)(NSURL *file, NSError *error);
@interface OVKMedia : NSObject
+ (void)clearImageCache;
+ (void)showBundledVideo:(NSString *)name from:(UIViewController *)controller;
+ (void)showCurrentMusicFrom:(UIViewController *)controller;
+ (void)handleRemoteControl:(UIEvent *)event;
+ (id<OVKCancellable>)download:(NSString *)url limit:(unsigned long long)limit progress:(void (^)(float value))progress completion:(OVKDownloadCompletion)completion;
+ (id<OVKCancellable>)image:(NSString *)url maxPixelSize:(NSUInteger)pixels completion:(void (^)(UIImage *,NSError *))completion;
+ (id<OVKCancellable>)image:(NSString *)url completion:(void (^)(UIImage *,NSError *))completion;
@end
@interface OVKRemoteImageView : UIImageView
@property (copy, nonatomic) NSString *source;
- (void)load:(NSString *)url;
@end
@interface OVKAttachmentsController : UITableViewController
- (id)initWithAttachments:(NSArray *)attachments title:(NSString *)title;
- (void)replaceAttachments:(NSArray *)attachments;
@end
@interface OVKPhotoController : UIViewController
- (id)initWithURL:(NSString *)url title:(NSString *)title;
- (id)initWithPhotos:(NSArray *)photos index:(NSUInteger)index;
@end
@interface OVKLibraryController : OVKAttachmentsController
- (id)initWithKind:(NSString *)kind identifier:(NSNumber *)identifier title:(NSString *)title;
@end
