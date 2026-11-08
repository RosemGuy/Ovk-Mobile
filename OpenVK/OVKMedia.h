#import <UIKit/UIKit.h>
#import "OVKAPI.h"
#import "OVKMediaModel.h"
typedef void (^OVKDownloadCompletion)(NSURL *file, NSError *error);
extern NSString * const OVKNowPlayingChanged;
@interface OVKMedia : NSObject
+ (void)clearImageCache;
+ (void)clearStoredImageCache;
+ (void)showBundledVideo:(NSString *)name from:(UIViewController *)controller;
+ (void)showCurrentMusicFrom:(UIViewController *)controller;
+ (NSDictionary *)nowPlaying;
+ (void)toggleNowPlaying;
+ (void)nextNowPlaying;
+ (void)cancelCurrentMusicCacheDownloads;
+ (void)handleRemoteControl:(UIEvent *)event;
+ (id<OVKCancellable>)download:(NSString *)url limit:(unsigned long long)limit progress:(void (^)(float value))progress completion:(OVKDownloadCompletion)completion;
+ (id<OVKCancellable>)image:(NSString *)url maxPixelSize:(NSUInteger)pixels completion:(void (^)(UIImage *,NSError *))completion;
+ (id<OVKCancellable>)image:(NSString *)url completion:(void (^)(UIImage *,NSError *))completion;
@end
@interface OVKRemoteImageView : UIImageView
@property (copy, nonatomic) NSString *source;
@property (strong, nonatomic) UIImage *placeholderImage;
@property (assign, nonatomic) NSUInteger maxPixelSize;
- (void)load:(NSString *)url;
@end
@interface OVKInlineAudioView : UIView
@property (copy, nonatomic) NSArray *tracks;
+ (NSArray *)tracksFromAttachments:(NSArray *)attachments;
+ (CGFloat)heightForTracks:(NSArray *)tracks;
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
@property (copy, nonatomic) void (^selectedAttachment)(NSDictionary *attachment);
- (id)initWithKind:(NSString *)kind identifier:(NSNumber *)identifier title:(NSString *)title;
- (void)enableCollectionSearch;
- (id)initForAudioSearch;
- (id)initForAudioFavorites;
- (id)initForAudioFeed;
- (void)setAudioSearchQuery:(NSString *)query;
- (void)submitAudioSearch;
@end

void OVKPresentPhoto(UIViewController *presenter, OVKPhotoController *photo);
