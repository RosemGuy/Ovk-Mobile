#import "OVKLocalAudio.h"
#import <math.h>
static NSError *AudioError(NSInteger code,NSString *text) { return [NSError errorWithDomain:@"OpenVKLocalAudio" code:code userInfo:@{NSLocalizedDescriptionKey:text}]; }
@interface OVKLocalAudio ()
@property (assign, nonatomic, readwrite) NSTimeInterval duration;
@property (assign, nonatomic, readwrite) NSTimeInterval currentTime;
@property (assign, nonatomic, readwrite) BOOL playing;
@property (assign, atomic) BOOL cancelled;
@property (assign, nonatomic) BOOL refreshPending;
@end
@implementation OVKLocalAudio
- (id)init { self=[super init]; if (self) _queue=dispatch_queue_create("org.openvk.classic.local-audio",DISPATCH_QUEUE_SERIAL); return self; }
- (void)publish:(NSError *)error {
    NSTimeInterval duration=_player.duration, time=_player.currentTime; BOOL playing=_player.playing;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.cancelled) return;
        self.duration=isfinite(duration) ? duration : 0; self.currentTime=isfinite(time) ? time : 0; self.playing=playing;
        if (self.changed) self.changed(error);
    });
}
- (void)prepareURL:(NSURL *)url completion:(void (^)(NSError *))completion {
    dispatch_async(_queue, ^{
        NSError *error=nil;
        if (self.cancelled) error=AudioError(NSURLErrorCancelled,@"Подготовка отменена");
        else {
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
    dispatch_async(_queue, ^{
        NSError *error=nil;
        if (self.cancelled) error=AudioError(NSURLErrorCancelled,@"Воспроизведение отменено");
        else if (!self->_player || ![self->_player play]) error=AudioError(3,@"Не удалось запустить аудиовывод");
        [self publish:nil]; dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(self.cancelled ? AudioError(NSURLErrorCancelled,@"Операция отменена") : error); });
    });
}
- (void)pause { [self pauseWithCompletion:nil]; }
- (void)pauseWithCompletion:(void (^)(void))completion { self.playing=NO; dispatch_async(_queue, ^{ [self->_player pause]; [self publish:nil]; if (completion) dispatch_async(dispatch_get_main_queue(),completion); }); }
- (void)seek:(NSTimeInterval)seconds {
    dispatch_async(_queue, ^{ if (self.cancelled || !self->_player || !isfinite(seconds)) return; self->_player.currentTime=MAX(0,MIN(self->_player.duration,seconds)); [self publish:nil]; });
}
- (void)refresh {
    if (self.refreshPending || self.cancelled) return; self.refreshPending=YES;
    dispatch_async(_queue, ^{ [self publish:nil]; dispatch_async(dispatch_get_main_queue(), ^{ self.refreshPending=NO; }); });
}
- (void)stop { [self stopWithCompletion:nil]; }
- (void)stopWithCompletion:(void (^)(void))completion {
    self.cancelled=YES; self.playing=NO; self.changed=nil;
    dispatch_async(_queue, ^{ self->_player.delegate=nil; [self->_player stop]; self->_player=nil; if (completion) dispatch_async(dispatch_get_main_queue(),completion); });
}
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    dispatch_async(_queue, ^{ if (player!=self->_player || self.cancelled) return; [self publish:flag ? nil : AudioError(4,@"Аудио завершилось с ошибкой")]; });
}
- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error {
    dispatch_async(_queue, ^{ if (player!=self->_player || self.cancelled) return; [self publish:error ?: AudioError(5,@"Ошибка декодирования аудио")]; });
}
@end
