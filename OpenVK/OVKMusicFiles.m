#import "OVKLanguage.h"
#import "OVKMusicFiles.h"
#import "OVKMediaFormat.h"
#import <TargetConditionals.h>
#import <CommonCrypto/CommonDigest.h>
static NSArray *AudioSuffixes(void);
NSString * const OVKMusicCacheChanged = @"OVKMusicCacheChanged";

NSString *OVKMusicCacheScope(NSString *server, NSNumber *user) {
    if (!server.length || user.longLongValue <= 0) return nil;
    NSData *input = [[NSString stringWithFormat:@"%@/%@",server,user] dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(input.bytes,(CC_LONG)input.length,digest);
    NSMutableString *scope = [NSMutableString string];
    for (NSUInteger i=0; i<sizeof(digest); i++) [scope appendFormat:@"%02x",(unsigned int)digest[i]];
    return scope;
}

static NSURL *OVKMusicCacheDirectory(NSString *scope) {
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet];
    if (scope.length!=CC_SHA256_DIGEST_LENGTH*2 || [scope rangeOfCharacterFromSet:invalid].location!=NSNotFound) return nil;
    NSURL *support = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] lastObject];
    NSURL *app = [support URLByAppendingPathComponent:@"Ovk-Mobile" isDirectory:YES];
    return [[app URLByAppendingPathComponent:@"OfflineMusic" isDirectory:YES] URLByAppendingPathComponent:scope isDirectory:YES];
}

static BOOL OVKMusicCacheKeyIsValid(NSString *key) {
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789-_"] invertedSet];
    return key.length && [key rangeOfCharacterFromSet:invalid].location==NSNotFound;
}

static NSDictionary *OVKReadMusicCacheEntry(NSURL *directory) {
    NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfURL:[directory URLByAppendingPathComponent:@"track.plist"]];
    NSString *extension = metadata[@"extension"];
    if (![AudioSuffixes() containsObject:extension ?: @""]) return nil;
    NSURL *file = [directory URLByAppendingPathComponent:[@"audio" stringByAppendingPathExtension:extension]];
    NSNumber *size = nil;
    if (![file getResourceValue:&size forKey:NSURLFileSizeKey error:NULL] || !size.unsignedLongLongValue || !metadata[@"item"]) return nil;
    return @{@"key":directory.lastPathComponent, @"file":file, @"size":size, @"item":metadata[@"item"]};
}

NSArray *OVKMusicCacheEntries(NSString *scope) {
    NSURL *directory = OVKMusicCacheDirectory(scope);
    if (!directory) return @[];
    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray *entries = [manager contentsOfDirectoryAtURL:directory includingPropertiesForKeys:nil options:0 error:NULL];
    NSMutableArray *result = [NSMutableArray array];
    for (NSURL *entry in entries) {
        // A terminated process may leave a staging directory behind.
        if ([entry.lastPathComponent hasPrefix:@".pending-"]) {
            [manager removeItemAtURL:entry error:NULL];
            continue;
        }
        if (!OVKMusicCacheKeyIsValid(entry.lastPathComponent)) continue;
        NSDictionary *track = OVKReadMusicCacheEntry(entry);
        if (track) [result addObject:track];
    }
    return result;
}

NSURL *OVKMusicCacheURL(NSString *scope, NSString *key) {
    if (!OVKMusicCacheKeyIsValid(key) || !scope.length) return nil;
    return OVKReadMusicCacheEntry([OVKMusicCacheDirectory(scope) URLByAppendingPathComponent:key])[@"file"];
}

BOOL OVKStoreMusicCacheFile(NSString *scope, NSString *key, NSURL *file, NSString *extension, NSDictionary *item, NSError **error) {
    NSURL *parent = OVKMusicCacheDirectory(scope);
    if (!parent || !OVKMusicCacheKeyIsValid(key) || !item || ![AudioSuffixes() containsObject:extension ?: @""]) return NO;
    if (OVKMusicCacheURL(scope,key)) return YES;
    NSFileManager *manager = [NSFileManager defaultManager];
    if (![manager createDirectoryAtURL:parent withIntermediateDirectories:YES attributes:nil error:error]) return NO;
#if TARGET_OS_IPHONE
    if (![parent setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:error]) return NO;
#endif
    NSString *stagingName = [@".pending-" stringByAppendingString:[[NSProcessInfo processInfo] globallyUniqueString]];
    NSURL *staging = [parent URLByAppendingPathComponent:stagingName isDirectory:YES];
    if (![manager createDirectoryAtURL:staging withIntermediateDirectories:NO attributes:nil error:error]) return NO;
    NSURL *audio = [staging URLByAppendingPathComponent:[@"audio" stringByAppendingPathExtension:extension]];
    NSURL *destination = [parent URLByAppendingPathComponent:key isDirectory:YES];
    NSDictionary *metadata = @{@"extension":extension, @"item":item};
    BOOL stored = [manager moveItemAtURL:file toURL:audio error:error] &&
                  [metadata writeToURL:[staging URLByAppendingPathComponent:@"track.plist"] atomically:YES];
#if TARGET_OS_IPHONE
    if (stored) stored = [manager setAttributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:audio.path error:error];
#endif
    if (stored && [manager fileExistsAtPath:destination.path]) stored = [manager removeItemAtURL:destination error:error];
    if (stored) stored = [manager moveItemAtURL:staging toURL:destination error:error];
    if (!stored) [manager removeItemAtURL:staging error:NULL];
    return stored;
}

BOOL OVKRemoveMusicCacheEntry(NSString *scope, NSString *key, NSError **error) {
    if (!OVKMusicCacheKeyIsValid(key)) return NO;
    NSURL *entry = [OVKMusicCacheDirectory(scope) URLByAppendingPathComponent:key isDirectory:YES];
    if (!entry) return NO;
    NSFileManager *manager = [NSFileManager defaultManager];
    return ![manager fileExistsAtPath:entry.path] || [manager removeItemAtURL:entry error:error];
}
static NSArray *AudioSuffixes(void) { return @[@"mp3",@"m4a",@"aac",@"wav",@"caf",@"aif",@"aiff",@"mp4"]; }
NSString *OVKLocalMusicDirectory(void) {
    NSString *documents=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES) objectAtIndex:0];
    NSString *path=[documents stringByAppendingPathComponent:@"Music"];
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL]; return path;
}
NSArray *OVKLocalMusicItems(void) { return OVKLocalMusicItemsInDocuments([OVKLocalMusicDirectory() stringByDeletingLastPathComponent]); }
static NSString * const OVKLocalFavoritesKey = @"OVKLocalMusicFavorites";

static NSString *OVKLocalFavoriteID(NSString *path) {
    NSString *directory = [[path stringByDeletingLastPathComponent] lastPathComponent];
    return [directory stringByAppendingPathComponent:path.lastPathComponent];
}

BOOL OVKLocalMusicIsFavorite(NSString *path) {
    return path.length && [[[NSUserDefaults standardUserDefaults] arrayForKey:OVKLocalFavoritesKey]
                          containsObject:OVKLocalFavoriteID(path)];
}

void OVKSetLocalMusicFavorite(NSString *path, BOOL favorite) {
    if (!path.length) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *favorites = [[defaults arrayForKey:OVKLocalFavoritesKey] mutableCopy] ?: [NSMutableArray array];
    NSString *identifier = OVKLocalFavoriteID(path);
    if (favorite && ![favorites containsObject:identifier]) [favorites addObject:identifier];
    if (!favorite) [favorites removeObject:identifier];
    [defaults setObject:favorites forKey:OVKLocalFavoritesKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"OVKLocalMusicFavoritesChanged" object:nil];
}

NSArray *OVKLocalMusicItemsInDocuments(NSString *documents) {
    NSMutableArray *items=[NSMutableArray array]; NSString *path=[documents stringByAppendingPathComponent:@"Music"];
    for (NSString *directory in @[path,documents]) {
        NSArray *names=[[[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:NULL] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        for (NSString *name in names) {
            if (![AudioSuffixes() containsObject:name.pathExtension.lowercaseString]) continue;
            NSString *file=[directory stringByAppendingPathComponent:name]; BOOL folder=NO;
            if (![[NSFileManager defaultManager] fileExistsAtPath:file isDirectory:&folder] || folder) continue;
            [items addObject:@{@"type":@"audio",@"title":[name stringByDeletingPathExtension],@"local_path":file,@"url":@"",@"preview":@"",@"object":@{}}];
        }
    } return items;
}
BOOL OVKImportAudioURL(NSURL *source,NSError **error) { return OVKImportAudioURLIntoDirectory(source,OVKLocalMusicDirectory(),error); }
BOOL OVKImportAudioURLIntoDirectory(NSURL *source,NSString *directory,NSError **error) {
    if (!source.isFileURL) { if (error) *error=[NSError errorWithDomain:@"OvkMusicImport" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Ожидается локальный аудиофайл"}]; return NO; }
    BOOL isDirectory=NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:source.path isDirectory:&isDirectory] || isDirectory) { if (error) *error=[NSError errorWithDomain:@"OvkMusicImport" code:3 userInfo:@{NSLocalizedDescriptionKey:@"Аудиофайл не найден"}]; return NO; }
    NSFileHandle *handle=[NSFileHandle fileHandleForReadingAtPath:source.path]; NSData *header=[handle readDataOfLength:64]; [handle closeFile];
    const char *type=OVKMediaContainer(header.bytes,header.length);
    NSString *suffix=type ? [NSString stringWithUTF8String:type] : source.pathExtension.lowercaseString;
    if ([suffix isEqualToString:@"mp4"]) suffix=@"m4a";
    if (![AudioSuffixes() containsObject:suffix ?: @""]) { if (error) *error=[NSError errorWithDomain:@"OvkMusicImport" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Поддерживаются MP3, M4A, AAC, WAV, AIFF и CAF"}]; return NO; }
    NSString *stem=[[source.path lastPathComponent] stringByDeletingPathExtension]; if (!stem.length) stem=OVKL(@"Аудиозапись");
    NSString *folder=directory; if (![[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:error]) return NO; NSString *name=[stem stringByAppendingPathExtension:suffix]; NSString *target=[folder stringByAppendingPathComponent:name]; NSUInteger index=2;
    while ([[NSFileManager defaultManager] fileExistsAtPath:target]) { name=[[NSString stringWithFormat:@"%@ (%lu)",stem,(unsigned long)index++] stringByAppendingPathExtension:suffix]; target=[folder stringByAppendingPathComponent:name]; }
    NSString *temporary=[folder stringByAppendingPathComponent:[NSString stringWithFormat:@".import-%@.tmp",[[NSProcessInfo processInfo] globallyUniqueString]]];
    if (![[NSFileManager defaultManager] copyItemAtURL:source toURL:[NSURL fileURLWithPath:temporary] error:error]) { [[NSFileManager defaultManager] removeItemAtPath:temporary error:NULL]; return NO; }
    BOOL moved=[[NSFileManager defaultManager] moveItemAtPath:temporary toPath:target error:error];
    if (!moved) [[NSFileManager defaultManager] removeItemAtPath:temporary error:NULL];
#if TARGET_OS_IPHONE
    if (moved) [[NSFileManager defaultManager] setAttributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:target error:NULL];
#endif
    return moved;
}
