#import "OVKVideoSound.h"
static NSError *OVKVideoSoundError(NSString *message) {
    return [NSError errorWithDomain:@"OVKVideoSound" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
BOOL OVKVideoAudioNeedsConversion(AVAssetTrack *track) {
    if (!track.formatDescriptions.count) return YES;
    for (id description in track.formatDescriptions) {
        FourCharCode codec=CMFormatDescriptionGetMediaSubType((__bridge CMFormatDescriptionRef)description);
        // MP3/PCM/ALAC may play as music while failing inside a movie on old iOS.
        // Keep AAC movie tracks; other formats go through the system AAC exporter.
        if (codec!='aac ' && codec!='aach' && codec!='aacp' && codec!='mp4a') return YES;
    }
    return NO;
}
AVAssetTrack *OVKPreferredVideoAudioTrack(AVAsset *asset) {
    NSArray *tracks=[asset tracksWithMediaType:AVMediaTypeAudio];
    for (AVAssetTrack *track in tracks) if (track.enabled && !OVKVideoAudioNeedsConversion(track)) return track;
    for (AVAssetTrack *track in tracks) if (!OVKVideoAudioNeedsConversion(track)) return track;
    return tracks.count ? tracks[0] : nil;
}
AVMutableComposition *OVKVideoComposition(AVAsset *video, AVAsset *sound, NSError **error) {
    NSArray *pictures=[video tracksWithMediaType:AVMediaTypeVideo];
    AVAssetTrack *audio=OVKPreferredVideoAudioTrack(sound);
    if (!pictures.count || !audio || !CMTIME_IS_NUMERIC(video.duration) || CMTimeCompare(video.duration,kCMTimeZero)<=0) {
        if (error) *error=OVKVideoSoundError(@"Не удалось прочитать видео и звуковую дорожку"); return nil;
    }
    AVAssetTrack *picture=pictures[0];
    CMTimeRange bounds=CMTimeRangeMake(kCMTimeZero,video.duration);
    CMTimeRange vr=CMTimeRangeGetIntersection(picture.timeRange,bounds);
    CMTimeRange ar=CMTimeRangeGetIntersection(audio.timeRange,sound==video ? bounds : CMTimeRangeMake(kCMTimeZero,sound.duration));
    if (!CMTIMERANGE_IS_VALID(vr) || !CMTIMERANGE_IS_VALID(ar) || !CMTIME_IS_NUMERIC(vr.duration) || !CMTIME_IS_NUMERIC(ar.duration) || CMTimeCompare(vr.duration,kCMTimeZero)<=0 || CMTimeCompare(ar.duration,kCMTimeZero)<=0) {
        if (error) *error=OVKVideoSoundError(@"Некорректная длительность дорожек"); return nil;
    }
    AVMutableComposition *result=[AVMutableComposition composition];
    AVMutableCompositionTrack *v=[result addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    AVMutableCompositionTrack *a=[result addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
    // Preserve embedded audio timestamps; separate files start with the video.
    CMTime destination=sound==video ? ar.start : kCMTimeZero;
    ar.duration=CMTimeMinimum(ar.duration,CMTimeSubtract(video.duration,destination));
    if (CMTimeCompare(ar.duration,kCMTimeZero)<=0 || ![v insertTimeRange:vr ofTrack:picture atTime:vr.start error:error] || ![a insertTimeRange:ar ofTrack:audio atTime:destination error:error]) return nil;
    // Fresh composition tracks are enabled and use the default volume.
    // Older SDKs expose these properties as read-only.
    v.preferredTransform=picture.preferredTransform;
    return result;
}
