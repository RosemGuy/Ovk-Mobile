#import "OVKLocalAudio.h"
#import "OVKAudioDuration.h"
#import <math.h>
#import <AudioToolbox/AudioToolbox.h>
static NSError *AudioError(NSInteger code,NSString *text) { return [NSError errorWithDomain:@"OpenVKLocalAudio" code:code userInfo:@{NSLocalizedDescriptionKey:text}]; }
// AVAudioPlayer and its callbacks stay on one permanent thread with a live run loop.
@interface OVKAudioThread : NSObject
@property (strong, nonatomic) NSThread *thread;
+ (OVKAudioThread *)shared;
- (void)run:(id)unused;
- (void)execute:(id)operation;
@end
@implementation OVKAudioThread
+ (OVKAudioThread *)shared {
    static OVKAudioThread *worker; static dispatch_once_t once;
    dispatch_once(&once, ^{ worker=[[OVKAudioThread alloc] init]; worker.thread=[[NSThread alloc] initWithTarget:worker selector:@selector(run:) object:nil]; worker.thread.name=@"Ovk-Mobile local audio"; [worker.thread start]; }); return worker;
}
- (void)run:(id)unused {
    @autoreleasepool {
        NSRunLoop *loop=[NSRunLoop currentRunLoop]; NSPort *port=[NSMachPort port]; [loop addPort:port forMode:NSDefaultRunLoopMode];
        while (![self.thread isCancelled]) { @autoreleasepool { [loop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:30]]; } }
    }
}
- (void)execute:(id)operation { void (^work)(void)=operation; work(); }
@end
static void OVKAudioPerform(void (^work)(void)) {
    OVKAudioThread *worker=[OVKAudioThread shared];
    [worker performSelector:@selector(execute:) onThread:worker.thread withObject:[work copy] waitUntilDone:NO];
}
static NSString *OVKAudioCodec(NSURL *url) {
    AudioFileID file=NULL; OSStatus status=AudioFileOpenURL((__bridge CFURLRef)url,kAudioFileReadPermission,0,&file);
    if (status!=noErr) return [NSString stringWithFormat:@"AudioFileOpen: %ld",(long)status];
    AudioStreamBasicDescription format={0}; UInt32 size=sizeof(format);
    status=AudioFileGetProperty(file,kAudioFilePropertyDataFormat,&size,&format); AudioFileClose(file);
    if (status!=noErr) return [NSString stringWithFormat:@"Audio format: %ld",(long)status];
    UInt32 code=format.mFormatID; char text[5]={(char)(code>>24),(char)(code>>16),(char)(code>>8),(char)code,0};
    NSString *codec=[NSString stringWithCString:text encoding:NSASCIIStringEncoding] ?: @"?";
    return [NSString stringWithFormat:@"%@, %.0f Hz, %u ch",codec,format.mSampleRate,(unsigned int)format.mChannelsPerFrame];
}
@interface OVKLocalAudio ()
@property (assign, nonatomic, readwrite) NSTimeInterval duration;
@property (assign, nonatomic, readwrite) NSTimeInterval currentTime;
@property (assign, nonatomic, readwrite) BOOL playing;
@property (assign, nonatomic, readwrite) BOOL completed;
@property (copy, nonatomic, readwrite) NSString *codecDescription;
@property (assign, atomic) BOOL cancelled;
@property (assign, nonatomic) BOOL refreshPending;
@end
@implementation OVKLocalAudio
- (id)init { self=[super init]; return self; }
- (void)publish:(NSError *)error {
    NSTimeInterval duration=_measuredDuration>0 ? _measuredDuration : _player.duration, time=_finished ? duration : _player.currentTime; if (duration>0) time=MIN(time,duration); BOOL playing=_player.playing, finished=_finished;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.cancelled) return;
        self.duration=isfinite(duration) ? duration : 0; self.currentTime=isfinite(time) ? time : 0; self.playing=playing; self.completed=finished;
        if (self.changed) self.changed(error);
    });
}
- (void)prepareURL:(NSURL *)url completion:(void (^)(NSError *))completion {
    OVKAudioPerform(^{
        NSError *error=nil;
        if (self.cancelled) error=AudioError(NSURLErrorCancelled,@"Подготовка отменена");
        else {
            self->_measuredDuration=0;
            NSData *bytes=[NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:NULL];
            if (bytes) self->_measuredDuration=OVKMP3Duration(bytes.bytes,bytes.length);
            NSString *codec=OVKAudioCodec(url); if (self->_measuredDuration>0) codec=[codec stringByAppendingFormat:@", MP3 frames: %.3f s",self->_measuredDuration]; dispatch_async(dispatch_get_main_queue(), ^{ if (!self.cancelled) self.codecDescription=codec; });
            self->_player=[[AVAudioPlayer alloc] initWithContentsOfURL:url error:&error];
            self->_player.delegate=self;
            if (self->_player && ![self->_player prepareToPlay]) error=AudioError(1,@"Не удалось подготовить локальный аудиофайл");
            if (!self->_player && !error) error=AudioError(2,@"Не удалось открыть локальный аудиофайл");
            if (self.cancelled) error=AudioError(NSURLErrorCancelled,@"Подготовка отменена");
        }
        if (error) { self->_player.delegate=nil; [self->_player stop]; self->_player=nil; }
        [self publish:nil]; dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(self.cancelled ? AudioError(NSURLErrorCancelled,@"Операция отменена") : error); });
    });
}
- (void)playWithCompletion:(void (^)(NSError *))completion {
    OVKAudioPerform(^{
        NSError *error=nil;
        if (self.cancelled) error=AudioError(NSURLErrorCancelled,@"Воспроизведение отменено");
        else {
            if (self->_finished) { self->_player.currentTime=0; self->_finished=NO; }
            if (!self->_player || ![self->_player play]) error=AudioError(3,@"Не удалось запустить аудиовывод");
        }
        [self publish:nil]; dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(self.cancelled ? AudioError(NSURLErrorCancelled,@"Операция отменена") : error); });
    });
}
- (void)pause { [self pauseWithCompletion:nil]; }
- (void)pauseWithCompletion:(void (^)(void))completion { self.playing=NO; OVKAudioPerform(^{ [self->_player pause]; [self publish:nil]; if (completion) dispatch_async(dispatch_get_main_queue(),completion); }); }
- (void)seek:(NSTimeInterval)seconds {
    OVKAudioPerform(^{ if (self.cancelled || !self->_player || !isfinite(seconds)) return; self->_finished=NO; self->_player.currentTime=MAX(0,MIN(self->_measuredDuration>0 ? self->_measuredDuration : self->_player.duration,seconds)); [self publish:nil]; });
}
- (void)refresh {
    if (self.refreshPending || self.cancelled) return; self.refreshPending=YES;
    OVKAudioPerform(^{ [self publish:nil]; dispatch_async(dispatch_get_main_queue(), ^{ self.refreshPending=NO; }); });
}
- (void)stop { [self stopWithCompletion:nil]; }
- (void)stopWithCompletion:(void (^)(void))completion {
    self.cancelled=YES; self.playing=NO; self.changed=nil;
    OVKAudioPerform(^{ self->_player.delegate=nil; [self->_player stop]; self->_player=nil; if (completion) dispatch_async(dispatch_get_main_queue(),completion); });
}
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    OVKAudioPerform(^{ if (player!=self->_player || self.cancelled) return; self->_finished=flag; [self publish:flag ? nil : AudioError(4,@"Аудио завершилось с ошибкой")]; });
}
- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error {
    OVKAudioPerform(^{ if (player!=self->_player || self.cancelled) return; [self publish:error ?: AudioError(5,@"Ошибка декодирования аудио")]; });
}
@end
