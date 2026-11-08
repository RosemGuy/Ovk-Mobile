#import <Foundation/Foundation.h>
NSString *OVKLocalMusicDirectory(void);
NSArray *OVKLocalMusicItems(void);
BOOL OVKImportAudioURL(NSURL *source,NSError **error);
BOOL OVKLocalMusicIsFavorite(NSString *path);
void OVKSetLocalMusicFavorite(NSString *path, BOOL favorite);
extern NSString * const OVKMusicCacheChanged;
NSString *OVKMusicCacheScope(NSString *server, NSNumber *user);
NSArray *OVKMusicCacheEntries(NSString *scope);
NSURL *OVKMusicCacheURL(NSString *scope, NSString *key);
BOOL OVKStoreMusicCacheFile(NSString *scope, NSString *key, NSURL *file, NSString *extension, NSDictionary *item, NSError **error);
BOOL OVKRemoveMusicCacheEntry(NSString *scope, NSString *key, NSError **error);

NSArray *OVKLocalMusicItemsInDocuments(NSString *documents);
BOOL OVKImportAudioURLIntoDirectory(NSURL *source,NSString *directory,NSError **error);
