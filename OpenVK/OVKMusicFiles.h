#import <Foundation/Foundation.h>
NSString *OVKLocalMusicDirectory(void);
NSArray *OVKLocalMusicItems(void);
BOOL OVKImportAudioURL(NSURL *source,NSError **error);

NSArray *OVKLocalMusicItemsInDocuments(NSString *documents);
BOOL OVKImportAudioURLIntoDirectory(NSURL *source,NSString *directory,NSError **error);
