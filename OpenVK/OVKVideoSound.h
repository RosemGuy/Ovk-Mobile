#import <AVFoundation/AVFoundation.h>
// Caller loads tracks/duration first. No network or audio-session changes here.
AVAssetTrack *OVKPreferredVideoAudioTrack(AVAsset *asset);
BOOL OVKVideoAudioNeedsConversion(AVAssetTrack *track);
AVMutableComposition *OVKVideoComposition(AVAsset *video, AVAsset *sound, NSError **error);
