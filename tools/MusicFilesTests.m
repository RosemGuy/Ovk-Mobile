#import <Foundation/Foundation.h>
#import "OVKMusicFiles.h"
static void Expect(BOOL value,const char *message) { if (!value) { fprintf(stderr,"FAIL: %s\n",message); exit(1); } }
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        Expect(argc==2,"Pass demo WAV");
        NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
        NSString *documents=[root stringByAppendingPathComponent:@"Documents"],*music=[documents stringByAppendingPathComponent:@"Music"];
        NSURL *source=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]]; NSError *error=nil;
        Expect(OVKImportAudioURLIntoDirectory(source,music,&error),"Import local WAV");
        Expect(OVKImportAudioURLIntoDirectory(source,music,&error),"Duplicate import does not overwrite");
        NSArray *items=OVKLocalMusicItemsInDocuments(documents); Expect(items.count==2,"Both imports listed");
        Expect(![items[0][@"local_path"] isEqual:items[1][@"local_path"]],"Unique duplicate names");
        for (NSDictionary *item in items) Expect([[NSFileManager defaultManager] fileExistsAtPath:item[@"local_path"]],"Imported file exists");
        [@"ignored" writeToFile:[documents stringByAppendingPathComponent:@"notes.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [@"partial" writeToFile:[music stringByAppendingPathComponent:@".import-test.tmp"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        Expect(OVKLocalMusicItemsInDocuments(documents).count==2,"Non-audio and partial files excluded");
        Expect(!OVKImportAudioURLIntoDirectory([NSURL URLWithString:@"https://example.invalid/test.mp3"],music,&error),"Remote URL is not imported as local");
        Expect(!OVKImportAudioURLIntoDirectory([NSURL fileURLWithPath:music],music,&error),"Directory is not an audio file");
        Expect([[NSFileManager defaultManager] fileExistsAtPath:source.path],"Original file is preserved");
        NSString *favoriteName = [root.lastPathComponent stringByAppendingPathExtension:@"wav"];
        NSString *favoritePath = [music stringByAppendingPathComponent:favoriteName];
        NSString *sameNameInDocuments = [documents stringByAppendingPathComponent:favoriteName];
        Expect(!OVKLocalMusicIsFavorite(favoritePath),"New local track is not a favorite");
        OVKSetLocalMusicFavorite(favoritePath,YES);
        OVKSetLocalMusicFavorite(favoritePath,YES);
        Expect(OVKLocalMusicIsFavorite(favoritePath),"Local favorite can be read after saving");
        Expect(!OVKLocalMusicIsFavorite(sameNameInDocuments),"Same file names in different folders are independent");
        OVKSetLocalMusicFavorite(favoritePath,NO);
        Expect(!OVKLocalMusicIsFavorite(favoritePath),"Removing a local favorite clears it");

        NSString *server = [NSString stringWithFormat:@"https://cache-test.invalid/%@",root.lastPathComponent];
        NSString *scope = OVKMusicCacheScope(server,@1);
        NSString *otherScope = OVKMusicCacheScope(server,@2);
        Expect(scope.length==64 && ![scope isEqualToString:otherScope],"Cache scope distinguishes accounts");
        NSURL *download = [NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"download"]];
        Expect([[NSFileManager defaultManager] copyItemAtURL:source toURL:download error:&error],"Stage an audio download");
        NSDictionary *track = @{@"type":@"audio",@"title":@"Offline test",@"object":@{@"id":@2,@"owner_id":@(-1)}};
        Expect(OVKStoreMusicCacheFile(scope,@"-1_2",download,@"wav",track,&error),"Store a completed track");
        NSURL *cached = OVKMusicCacheURL(scope,@"-1_2");
        Expect(cached!=nil && OVKMusicCacheURL(otherScope,@"-1_2")==nil,"Only the owning account sees a cached file");
        NSArray *cacheEntries = OVKMusicCacheEntries(scope);
        Expect(cacheEntries.count==1 && [cacheEntries[0][@"size"] unsignedLongLongValue]>0,"Cache entry contributes to the size");
        Expect(OVKRemoveMusicCacheEntry(scope,@"-1_2",&error),"Remove one cached track");
        Expect(OVKMusicCacheEntries(scope).count==0 && OVKMusicCacheURL(scope,@"-1_2")==nil,"Removal clears the track and its metadata");
        NSURL *scopeDirectory = [[cached URLByDeletingLastPathComponent] URLByDeletingLastPathComponent];
        [[NSFileManager defaultManager] removeItemAtURL:scopeDirectory error:NULL];
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
        puts("PASS: local imports, catalog, favorites and isolated offline cache");
    } return 0;
}
