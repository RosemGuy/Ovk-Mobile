#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "OVKVideoSound.h"
static void Check(BOOL ok, NSString *message) { if (!ok) { NSLog(@"FAIL: %@",message); exit(1); } }
static void Wait(BOOL (^done)(void)) { NSDate *end=[NSDate dateWithTimeIntervalSinceNow:60]; while (!done() && [end timeIntervalSinceNow]>0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]]; Check(done(),@"asynchronous operation completed"); }
static void Load(AVAsset *asset) { __block BOOL loaded=NO; [asset loadValuesAsynchronouslyForKeys:@[@"tracks",@"duration"] completionHandler:^{ dispatch_async(dispatch_get_main_queue(), ^{ loaded=YES; }); }]; Wait(^BOOL{ return loaded; }); Check([asset statusOfValueForKey:@"tracks" error:NULL]==AVKeyValueStatusLoaded,@"tracks loaded"); }
int main(int argc, const char **argv) { @autoreleasepool {
    Check(argc==3,@"source MP4 and output MOV supplied");
    AVURLAsset *source=[AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:@(argv[1])] options:nil]; Load(source);
    Check(OVKPreferredVideoAudioTrack(source)!=nil,@"bundled source has audio");
    Check(!OVKVideoAudioNeedsConversion(OVKPreferredVideoAudioTrack(source)),@"AAC plays without conversion");
    NSError *error=nil; AVMutableComposition *pictures=[AVMutableComposition composition];
    AVAssetTrack *original=[source tracksWithMediaType:AVMediaTypeVideo][0];
    AVMutableCompositionTrack *v=[pictures addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    Check([v insertTimeRange:original.timeRange ofTrack:original atTime:kCMTimeZero error:&error],@"create video-only rendition");
    Check(OVKVideoComposition(pictures,pictures,&error)==nil,@"do not manufacture a missing audio track");
    AVMutableComposition *joined=OVKVideoComposition(pictures,source,&error);
    Check(joined!=nil && [joined tracksWithMediaType:AVMediaTypeAudio].count==1,@"separate sound is added to video-only rendition");
    AVAssetTrack *joinedAudio=[joined tracksWithMediaType:AVMediaTypeAudio][0]; Check(joinedAudio.enabled,@"output audio enabled");
    AVAssetExportSession *exporter=[[AVAssetExportSession alloc] initWithAsset:joined presetName:AVAssetExportPresetPassthrough];
    exporter.outputURL=[NSURL fileURLWithPath:@(argv[2])]; exporter.outputFileType=AVFileTypeQuickTimeMovie;
    __block BOOL finished=NO; [exporter exportAsynchronouslyWithCompletionHandler:^{ finished=YES; }]; Wait(^BOOL{ return finished; });
    Check(exporter.status==AVAssetExportSessionStatusCompleted,exporter.error.description ?: @"export completed");
    AVURLAsset *output=[AVURLAsset URLAssetWithURL:exporter.outputURL options:nil]; Load(output);
    AVAssetTrack *audio=OVKPreferredVideoAudioTrack(output); Check(audio!=nil && audio.enabled,@"export retains enabled audio");
    AVAssetReader *reader=[[AVAssetReader alloc] initWithAsset:output error:&error];
    AVAssetReaderTrackOutput *pcm=[[AVAssetReaderTrackOutput alloc] initWithTrack:audio outputSettings:@{AVFormatIDKey:@(kAudioFormatLinearPCM),AVLinearPCMBitDepthKey:@16,AVLinearPCMIsFloatKey:@NO,AVLinearPCMIsBigEndianKey:@NO}];
    [reader addOutput:pcm]; Check([reader startReading],@"decode exported audio");
    CMSampleBufferRef buffer=[pcm copyNextSampleBuffer]; Check(buffer!=NULL && CMSampleBufferGetNumSamples(buffer)>0,@"exported audio produces PCM samples"); if (buffer) CFRelease(buffer); [reader cancelReading];
    puts("PASS: missing track rejected, separate audio merged, exported audio decodes");
} return 0; }
