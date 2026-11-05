#import <Foundation/Foundation.h>
#import "OVKMediaModel.h"
#import "OVKAPI.h"
static void Expect(BOOL passed,const char *message) { if (!passed) { fprintf(stderr,"FAIL: %s\n",message); exit(1); } }
int main(void) {
    @autoreleasepool {
        [OVKAPI shared].siteServer = @"https://example.invalid";
        Expect([OVKMediaURL(@"/photo.jpg") isEqual:@"https://example.invalid/photo.jpg"],"Relative media URL resolved");
        Expect([OVKMediaURL(@"//cdn.example.invalid/photo.jpg") isEqual:@"https://cdn.example.invalid/photo.jpg"],"Protocol-relative CDN URL resolved");
        Expect(!OVKMediaURL(@"javascript:alert(1)").length,"Non-media scheme rejected");
        Expect(!OVKMediaURL(@"https://user:password@example.invalid/a").length,"Embedded credentials rejected");
        NSDictionary *sized = @{@"sizes":@[@{@"width":@800,@"height":@600,@"url":@"/large.jpg"},@{@"width":@100,@"height":@100,@"url":@"/small.jpg"}]};
        Expect([OVKPhotoSource(sized) hasSuffix:@"/large.jpg"],"Largest photo chosen independently of response order");
        Expect([OVKPhotoSource(@{@"photo_604":@"/preview.jpg",@"sizes":@[@{@"width":@2048,@"height":@1536,@"url":@"/full.jpg"}]}) hasSuffix:@"/full.jpg"],"Large photo sizes preferred over legacy preview");
        Expect([OVKPhotoSource(@{@"photo_max_orig":@"/original.jpg",@"photo_1280":@"/preview.jpg"}) hasSuffix:@"/original.jpg"],"Explicit photo original preferred");
        NSDictionary *photo = @{@"type":@"photo",@"photo":@{@"photo_604":@"/a.jpg"}};
        NSDictionary *audio = @{@"type":@"audio",@"audio":@{@"artist":@"Artist",@"title":@"Song",@"url":@"/song.mp3"}};
        NSDictionary *video = @{@"type":@"video",@"video":@{@"title":@"Clip",@"files":@{@"mp4_720":@"/720.mp4",@"mp4_360":@"/360.mp4"}}};
        NSArray *media = OVKPlayableAttachments(@{@"attachments":@[photo,photo,audio,video]});
        Expect(media.count == 4,"All attachments preserved, including multiple photos");
        Expect([media[2][@"title"] isEqual:@"Artist — Song"],"Audio title includes artist");
        Expect([media[3][@"url"] hasSuffix:@"/360.mp4"],"Legacy-friendly MP4 rendition preferred");
        Expect(OVKPlayableAttachments(@{@"explicit":@1,@"attachments":@[photo]}).count == 0,"Hidden post has no media");
        NSArray *voice = OVKPlayableAttachments(@{@"attachments":@[@{@"type":@"audio_message",@"audio_message":@{@"link_mp3":@"/voice.mp3",@"link_ogg":@"/voice.ogg"}}]});
        Expect([voice[0][@"url"] hasSuffix:@"/voice.mp3"],"Voice selects MP3");
        NSDictionary *external = @{@"player":@"https://player.example.invalid/embed/1",@"files":@{@"external":@"https://player.example.invalid/watch/1"}};
        Expect(!OVKDirectVideoURL(external).length,"Web player is not treated as a direct video file");
        Expect(OVKPlayableAttachments(@{@"attachments":@[[NSNull null],@{@"type":@"photo",@"photo":[NSNull null]}]}).count == 1,"Malformed attachments do not crash model");
        NSArray *copies = OVKPlayableAttachments(@{@"copy_history":@[@{@"explicit":@1,@"attachments":@[photo]},@{@"attachments":@[audio]}]});
        Expect(copies.count == 1 && [copies[0][@"type"] isEqual:@"audio"],"Repost media respects explicit flag");
        NSDictionary *variants=@{@"files":@{@"mp4_360":@"/360.mp4",@"mp4_720":@"/720.mp4",@"original":@"/original.mp4",@"external":@"/watch"},@"url":@"/original.mp4"};
        NSArray *urls=OVKVideoURLs(variants);
        Expect(urls.count==3 && [urls[0] hasSuffix:@"/360.mp4"] && [urls[2] hasSuffix:@"/original.mp4"],"Fallback candidates include original without duplicate or web player");
        Expect([OVKVideoAudioURL(@{@"files":@{@"audio":@"/sound.m4a"}}) hasSuffix:@"/sound.m4a"],"Explicit separate audio URL retained");
        Expect(!OVKVideoAudioURL(@{@"files":@{@"audio":[NSNull null]}}).length,"Malformed separate audio does not crash");
        Expect(!OVKVideoURLs(@{@"files":@{@"mp4_360":@"javascript:alert(1)"}}).count,"Invalid candidate schemes rejected");
        puts("PASS: media URLs, photo sizes, multiple attachments, audio/video, voice, explicit/reposts, malformed data");
    }
    return 0;
}
