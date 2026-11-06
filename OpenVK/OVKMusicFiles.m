#import "OVKLanguage.h"
#import "OVKMusicFiles.h"
#import "OVKMediaFormat.h"
#import <TargetConditionals.h>
static NSArray *AudioSuffixes(void) { return @[@"mp3",@"m4a",@"aac",@"wav",@"caf",@"aif",@"aiff",@"mp4"]; }
NSString *OVKLocalMusicDirectory(void) {
    NSString *documents=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES) objectAtIndex:0];
    NSString *path=[documents stringByAppendingPathComponent:@"Music"];
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL]; return path;
}
NSArray *OVKLocalMusicItems(void) { return OVKLocalMusicItemsInDocuments([OVKLocalMusicDirectory() stringByDeletingLastPathComponent]); }
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
