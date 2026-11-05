#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <dispatch/dispatch.h>
// A single downloaded file. All decoder/output operations run on one worker queue.
@interface OVKLocalAudio : NSObject <AVAudioPlayerDelegate> {
    dispatch_queue_t _queue;
    AVAudioPlayer *_player;
}
@property (assign, nonatomic, readonly) NSTimeInterval duration;
@property (assign, nonatomic, readonly) NSTimeInterval currentTime;
@property (assign, nonatomic, readonly) BOOL playing;
@property (copy, nonatomic) void (^changed)(NSError *error);
- (void)prepareURL:(NSURL *)url completion:(void (^)(NSError *error))completion;
- (void)playWithCompletion:(void (^)(NSError *error))completion;
- (void)pause;
- (void)pauseWithCompletion:(void (^)(void))completion;
- (void)seek:(NSTimeInterval)seconds;
- (void)refresh;
- (void)stop;
- (void)stopWithCompletion:(void (^)(void))completion;
@end
