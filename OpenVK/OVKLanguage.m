#import "OVKLanguage.h"
BOOL OVKLanguageIsEnglish(void) { return [[[NSUserDefaults standardUserDefaults] stringForKey:@"OVKLanguage"] isEqualToString:@"en"]; }
NSString *OVKL(NSString *russian) {
    if (!OVKLanguageIsEnglish()) return russian;
    static NSDictionary *strings=nil; static dispatch_once_t once;
    dispatch_once(&once, ^{ NSString *path=[[NSBundle mainBundle] pathForResource:@"Languages" ofType:@"json"]; NSData *data=[NSData dataWithContentsOfFile:path]; if (data) strings=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]; });
    return [strings[russian] isKindOfClass:[NSString class]] ? strings[russian] : russian;
}
void OVKSetLanguage(NSString *language) {
    if (![@[@"ru",@"en"] containsObject:language]) return;
    [[NSUserDefaults standardUserDefaults] setObject:language forKey:@"OVKLanguage"];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"OVKLanguageChanged" object:nil];
}
