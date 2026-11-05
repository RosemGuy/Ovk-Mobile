#import <Foundation/Foundation.h>
NSString *OVKMediaURL(NSString *value);
NSString *OVKPhotoSource(NSDictionary *photo);
NSArray *OVKPlayableAttachments(NSDictionary *post);
NSString *OVKDirectVideoURL(NSDictionary *video);

NSArray *OVKVideoURLs(NSDictionary *video);
NSString *OVKVideoAudioURL(NSDictionary *video);
