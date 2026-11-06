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
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
        puts("PASS: local imports, duplicates, catalog, partial-file exclusion, source preservation");
    } return 0;
}
