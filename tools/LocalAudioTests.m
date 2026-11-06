#import <Foundation/Foundation.h>
#import "OVKLocalAudio.h"
static void Expect(BOOL ok,const char *message) { if (!ok) { fprintf(stderr,"FAIL: %s\n",message); exit(1); } }
static void Wait(BOOL (^done)(void),const char *message) {
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:6];
    while (!done() && deadline.timeIntervalSinceNow>0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
    Expect(done(),message);
}
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        Expect(argc==2,"Pass demo WAV path"); NSURL *file=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        __block BOOL done=NO;
        OVKLocalAudio *invalid=[[OVKLocalAudio alloc] init];
        [invalid prepareURL:[NSURL fileURLWithPath:@"/does-not-exist/ovk-missing.mp3"] completion:^(NSError *error) { Expect([NSThread isMainThread] && error!=nil,"Missing file reports error on main thread"); done=YES; }];
        Wait(^BOOL { return done; },"Missing-file callback"); [invalid stop];
        done=NO; OVKLocalAudio *cancelled=[[OVKLocalAudio alloc] init];
        [cancelled prepareURL:file completion:^(NSError *error) { Expect(error.code==NSURLErrorCancelled,"Cancelled preparation never becomes ready"); done=YES; }]; [cancelled stop];
        Wait(^BOOL { return done; },"Cancel callback");
        done=NO; OVKLocalAudio *audio=[[OVKLocalAudio alloc] init];
        [audio prepareURL:file completion:^(NSError *error) { Expect(!error,"Prepare WAV"); Expect(audio.codecDescription.length>0 && [audio.codecDescription rangeOfString:@"lpcm"].location!=NSNotFound,"WAV codec is inspected"); Expect(audio.duration>1.9 && audio.duration<2.1,"Correct duration"); done=YES; }];
        Wait(^BOOL { return done; },"Prepare callback");
        done=NO; [audio playWithCompletion:^(NSError *error) { Expect(!error && audio.playing,"Play returns actual success"); done=YES; }];
        Wait(^BOOL { return done; },"Play callback");
        Wait(^BOOL { [audio refresh]; return audio.currentTime>1.2; },"Playback progresses beyond first second");
        done=NO; [audio pauseWithCompletion:^{ Expect(!audio.playing,"Pause state"); done=YES; }]; Wait(^BOOL { return done; },"Pause callback");
        [audio seek:.5]; Wait(^BOOL { [audio refresh]; return audio.currentTime>.4 && audio.currentTime<.6; },"Seek uses cached snapshot");
        done=NO; [audio stopWithCompletion:^{ Expect(!audio.playing,"Stop state"); done=YES; }]; Wait(^BOOL { return done; },"Stop callback");
        puts("PASS: local WAV, errors, cancellation, first-second progress, pause, seek, stop");
    } return 0;
}
