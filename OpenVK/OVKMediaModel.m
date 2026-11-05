#import "OVKMediaModel.h"
#import "OVKAPI.h"
NSString *OVKMediaURL(NSString *value) {
    if (!value.length) return @"";
    NSString *baseURL = [OVKAPI shared].siteServer ?: [OVKAPI shared].server;
    NSURL *base = [NSURL URLWithString:[baseURL stringByAppendingString:@"/"]];
    NSURL *url = [[NSURL URLWithString:value relativeToURL:base] absoluteURL];
    NSString *scheme = url.scheme.lowercaseString;
    if (([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) && !url.host.length) return @"";
    return [@[@"https",@"http",@"demo"] containsObject:scheme ?: @""] && !url.user && !url.password ? url.absoluteString : @"";
}
NSString *OVKPhotoSource(NSDictionary *photo) {
    NSString *original=OVKMediaURL(OVKString(photo[@"photo_max_orig"])); if (original.length) return original;
    NSString *chosen=@""; double best=0;
    NSArray *sizes=OVKArray(photo[@"sizes"]); if (!sizes.count) sizes=OVKArray(photo[@"images"]);
    for (id value in sizes) {
        NSDictionary *size=OVKDictionary(value); NSString *url=OVKMediaURL(OVKString(size[@"url"] ?: size[@"src"]));
        double area=[OVKString(size[@"width"]) doubleValue]*[OVKString(size[@"height"]) doubleValue];
        if (url.length && (!chosen.length || area>=best)) { chosen=url; best=area; }
    }
    if (chosen.length) return chosen;
    for (NSString *key in @[@"photo_2560",@"photo_1280",@"photo_807",@"photo_604",@"photo_200",@"photo_130",@"url",@"src"]) {
        NSString *url=OVKMediaURL(OVKString(photo[key])); if (url.length) return url;
    } return @"";
}
NSArray *OVKVideoURLs(NSDictionary *video) {
    NSDictionary *files=OVKDictionary(video[@"files"]); NSMutableArray *urls=[NSMutableArray array];
    for (NSString *key in @[@"mp4_360",@"mp4_240",@"mp4_480",@"mp4_720",@"mp4_1080",@"original",@"url",@"external"]) {
        NSString *raw=OVKString(files[key]); NSURL *candidateURL=[NSURL URLWithString:raw]; NSString *ext=candidateURL.pathExtension.lowercaseString;
        if (![key hasPrefix:@"mp4_"] && ![@[@"mp4",@"mov",@"m4v"] containsObject:ext ?: @""]) continue;
        NSString *url=OVKMediaURL(raw); if (url.length && ![urls containsObject:url]) [urls addObject:url];
    }
    for (NSString *key in @[@"url",@"original",@"original_url"]) {
        NSString *raw=OVKString(video[key]); NSURL *candidateURL=[NSURL URLWithString:raw]; NSString *ext=candidateURL.pathExtension.lowercaseString;
        NSString *url=OVKMediaURL(raw); if ([@[@"mp4",@"mov",@"m4v"] containsObject:ext ?: @""] && url.length && ![urls containsObject:url]) [urls addObject:url];
    }
    return urls;
}
NSString *OVKVideoAudioURL(NSDictionary *video) {
    NSDictionary *files=OVKDictionary(video[@"files"]);
    for (id raw in @[files[@"audio"] ?: @"",files[@"mp3"] ?: @"",files[@"m4a"] ?: @"",video[@"audio_url"] ?: @""]) {
        NSString *value=OVKString(raw); if (!value.length) value=OVKString(OVKDictionary(raw)[@"url"]);
        NSString *url=OVKMediaURL(value); if (url.length) return url;
    } return @"";
}
NSString *OVKDirectVideoURL(NSDictionary *video) { NSArray *urls=OVKVideoURLs(video); return urls.count ? urls[0] : @""; }
NSArray *OVKPlayableAttachments(NSDictionary *post) {
    if ([OVKString(post[@"explicit"]) boolValue]) return @[];
    NSMutableArray *result = [NSMutableArray array];
    for (id value in OVKArray(post[@"attachments"])) {
        NSDictionary *a = OVKDictionary(value); NSString *type = OVKString(a[@"type"]); NSDictionary *object = OVKDictionary(a[type]);
        NSString *title = OVKString(object[@"title"]), *url = @"", *preview = @"";
        if ([type isEqualToString:@"photo"]) { url = OVKPhotoSource(object); preview = url; if (!title.length) title = @"Фотография"; }
        else if ([type isEqualToString:@"audio"]) { url = OVKMediaURL(OVKString(object[@"url"])); NSString *artist = OVKString(object[@"artist"]); if (artist.length) title = [NSString stringWithFormat:@"%@ — %@",artist,title]; }
        else if ([type isEqualToString:@"video"]) { url = OVKDirectVideoURL(object); preview = OVKMediaURL(OVKString(object[@"photo_800"] ?: object[@"photo_320"] ?: object[@"photo_130"])); if (!preview.length) preview = OVKPhotoSource(@{@"sizes":OVKArray(object[@"image"] ?: object[@"images"])}); }
        else if ([type isEqualToString:@"audio_message"] || [type isEqualToString:@"voice"] || [type isEqualToString:@"doc"]) {
            NSDictionary *voice = [type isEqualToString:@"doc"] ? OVKDictionary(OVKDictionary(object[@"preview"])[@"audio_msg"]) : object;
            if (!voice.count) continue; type = @"audio"; url = OVKMediaURL(OVKString(voice[@"link_mp3"])); title = @"Голосовое сообщение";
        } else continue;
        if (!title.length) title = [type isEqualToString:@"audio"] ? @"Аудиозапись" : @"Видеозапись";
        [result addObject:@{@"type":type,@"title":title,@"url":url,@"preview":preview,@"object":object}];
    }
    // Reposts remain separate records, respecting the nested explicit flag.
    for (id value in OVKArray(post[@"copy_history"])) {
        NSDictionary *copy = OVKDictionary(value); if (![OVKString(copy[@"explicit"]) boolValue]) {
            NSMutableDictionary *shallow = [copy mutableCopy]; [shallow removeObjectForKey:@"copy_history"]; [result addObjectsFromArray:OVKPlayableAttachments(shallow)];
        }
    }
    return result;
}
