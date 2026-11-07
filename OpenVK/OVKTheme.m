#import "OVKTheme.h"
static NSCache *OVKChromeImages=nil,*OVKIconImages=nil,*OVKStretchedImages=nil;
void OVKClearThemeCaches(void) { [OVKChromeImages removeAllObjects]; [OVKIconImages removeAllObjects]; [OVKStretchedImages removeAllObjects]; }
static BOOL OVKDark;
static NSString *OVKColor;
NSArray *OVKThemeColors(void) { static NSArray *colors; static dispatch_once_t once; dispatch_once(&once, ^{ colors=@[@"blue",@"purple",@"red",@"green",@"orange",@"pink"]; }); return colors; }
static void OVKLoadTheme(void) { static dispatch_once_t once; dispatch_once(&once, ^{ NSUserDefaults *settings=[NSUserDefaults standardUserDefaults]; NSString *color=[settings stringForKey:@"OVKThemeColor"]; OVKColor=[OVKThemeColors() containsObject:color ?: @""] ? [color copy] : @"blue"; OVKDark=[settings boolForKey:@"OVKDarkTheme"]; }); }
NSString *OVKThemeColor(void) { OVKLoadTheme(); return OVKColor; }
BOOL OVKDarkTheme(void) { OVKLoadTheme(); return OVKDark; }
void OVKSetThemeColor(NSString *color) { if (![OVKThemeColors() containsObject:color]) return; OVKLoadTheme(); OVKColor=[color copy]; [[NSUserDefaults standardUserDefaults] setObject:color forKey:@"OVKThemeColor"]; OVKClearThemeCaches(); [[NSNotificationCenter defaultCenter] postNotificationName:@"OVKThemeChanged" object:nil]; }
void OVKSetDarkTheme(BOOL dark) { OVKLoadTheme(); OVKDark=dark; [[NSUserDefaults standardUserDefaults] setBool:dark forKey:@"OVKDarkTheme"]; OVKClearThemeCaches(); [[NSNotificationCenter defaultCenter] postNotificationName:@"OVKThemeChanged" object:nil]; }
static NSDictionary *OVKAccentPalette(BOOL dark) {
    static NSDictionary *palettes[2]; static dispatch_once_t once; dispatch_once(&once, ^{
        NSArray *rgb=@[@[@.31,@.45,@.60],@[@.47,@.30,@.67],@[@.70,@.24,@.25],@[@.23,@.50,@.36],@[@.73,@.39,@.15],@[@.68,@.29,@.50]];
        for (NSUInteger mode=0;mode<2;mode++) { NSMutableDictionary *values=[NSMutableDictionary dictionary]; for (NSUInteger index=0;index<rgb.count;index++) { NSArray *value=rgb[index]; double r=[value[0] doubleValue],g=[value[1] doubleValue],b=[value[2] doubleValue]; if (mode) { r=r*.55+.45; g=g*.55+.45; b=b*.55+.45; } values[OVKThemeColors()[index]]=[UIColor colorWithRed:r green:g blue:b alpha:1]; } palettes[mode]=[values copy]; }
    }); return palettes[dark ? 1 : 0];
}
static UIColor *OVKBaseAccent(void) { return OVKAccentPalette(NO)[OVKThemeColor()]; }
UIColor *OVKThemeAccent(void) { return OVKAccentPalette(OVKDarkTheme())[OVKThemeColor()]; }
UIColor *OVKThemeBackground(void) { static UIColor *light,*dark; static dispatch_once_t once; dispatch_once(&once, ^{ light=[UIColor colorWithPatternImage:[UIImage imageNamed:@"Linen"]]; dark=[UIColor colorWithRed:.09 green:.105 blue:.125 alpha:1]; }); return OVKDarkTheme() ? dark : light; }
UIColor *OVKThemeSurface(void) { static UIColor *dark; static dispatch_once_t once; dispatch_once(&once, ^{ dark=[UIColor colorWithRed:.15 green:.17 blue:.20 alpha:1]; }); return OVKDarkTheme() ? dark : [UIColor whiteColor]; }
UIColor *OVKThemeText(void) { static UIColor *light,*dark; static dispatch_once_t once; dispatch_once(&once, ^{ light=[UIColor colorWithWhite:.12 alpha:1]; dark=[UIColor colorWithWhite:.92 alpha:1]; }); return OVKDarkTheme() ? dark : light; }
UIColor *OVKThemeSecondary(void) { static UIColor *dark; static dispatch_once_t once; dispatch_once(&once, ^{ dark=[UIColor colorWithWhite:.66 alpha:1]; }); return OVKDarkTheme() ? dark : [UIColor grayColor]; }
UIImage *OVKThemeChrome(NSString *name) {
    UIImage *original=[UIImage imageNamed:name]; if (!original || (!OVKDarkTheme() && [OVKThemeColor() isEqualToString:@"blue"])) return original;
    static dispatch_once_t once; dispatch_once(&once, ^{ OVKChromeImages=[[NSCache alloc] init]; OVKChromeImages.totalCostLimit=2*1024*1024; }); NSCache *images=OVKChromeImages; NSString *cacheKey=name; UIImage *saved=[images objectForKey:cacheKey]; if (saved) return saved;
    UIGraphicsBeginImageContextWithOptions(original.size,NO,original.scale); [original drawAtPoint:CGPointZero];
    if (![name hasPrefix:@"Music"] && ![OVKThemeColor() isEqualToString:@"blue"]) { [OVKBaseAccent() setFill]; UIRectFillUsingBlendMode((CGRect){CGPointZero,original.size},kCGBlendModeColor); [original drawAtPoint:CGPointZero blendMode:kCGBlendModeDestinationIn alpha:1]; }
    if (OVKDarkTheme()) { CGFloat shade=([name hasPrefix:@"Bubble"] || [name hasPrefix:@"Message"] || [name hasPrefix:@"Footer"] || [name isEqualToString:@"SectionBar"]) ? .78 : .55; [[UIColor colorWithWhite:0 alpha:shade] setFill]; UIRectFillUsingBlendMode((CGRect){CGPointZero,original.size},kCGBlendModeSourceAtop); } UIImage *result=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); if (result) [images setObject:result forKey:cacheKey cost:CGImageGetWidth(result.CGImage)*CGImageGetHeight(result.CGImage)*4]; return result;
}
void OVKThemeTable(UITableView *table) { table.backgroundView=nil; table.backgroundColor=OVKThemeBackground(); table.separatorColor=OVKDarkTheme() ? [UIColor colorWithWhite:.26 alpha:1] : [UIColor colorWithWhite:.87 alpha:1]; }
void OVKThemeCell(UITableViewCell *cell) {
    UIView *background=cell.backgroundView;
    if (!background || [background isKindOfClass:[UIImageView class]]) { background=[[UIView alloc] initWithFrame:cell.bounds]; cell.backgroundView=background; }
    background.backgroundColor=OVKThemeSurface(); cell.backgroundColor=OVKThemeSurface();
    cell.textLabel.backgroundColor=[UIColor clearColor]; cell.detailTextLabel.backgroundColor=[UIColor clearColor]; cell.textLabel.textColor=OVKThemeText(); cell.detailTextLabel.textColor=OVKThemeSecondary();
    if (cell.accessoryType==UITableViewCellAccessoryCheckmark) {
        UILabel *mark=cell.accessoryView.tag==7749 ? (UILabel *)cell.accessoryView : nil;
        if (!mark) { mark=[[UILabel alloc] initWithFrame:CGRectMake(0,0,24,24)]; mark.tag=7749; mark.text=@"✓"; mark.textAlignment=NSTextAlignmentCenter; mark.font=[UIFont boldSystemFontOfSize:19]; mark.backgroundColor=[UIColor clearColor]; cell.accessoryView=mark; }
        mark.textColor=OVKThemeAccent(); cell.accessibilityTraits|=UIAccessibilityTraitSelected;
    } else if (cell.accessoryView.tag==7749) { cell.accessoryView=nil; cell.accessibilityTraits&=~UIAccessibilityTraitSelected; }
}

void OVKThemeButtons(UIView *view) {
    if ([view isKindOfClass:[UISegmentedControl class]]) ((UISegmentedControl *)view).tintColor=OVKThemeAccent();
    if ([view isKindOfClass:[UIButton class]]) { UIButton *button=(UIButton *)view;
        if (button.buttonType==UIButtonTypeRoundedRect) { OVKStyleAssetButton(button,@"FooterButton"); [button setTitleColor:OVKThemeAccent() forState:UIControlStateNormal]; }
    }
    for (UIView *child in view.subviews) OVKThemeButtons(child);
}

UIImage *OVKThemeIcon(NSString *name) {
    BOOL activeLike=[name isEqualToString:@"PostLikeActive"]; UIImage *image=[UIImage imageNamed:activeLike ? @"PostLike" : name]; if (!image || (!activeLike && !OVKDarkTheme() && [OVKThemeColor() isEqualToString:@"blue"])) return image;
    static dispatch_once_t once; dispatch_once(&once, ^{ OVKIconImages=[[NSCache alloc] init]; OVKIconImages.countLimit=48; }); NSCache *icons=OVKIconImages; NSString *cacheKey=name; UIImage *cached=[icons objectForKey:cacheKey]; if (cached) return cached;
    UIGraphicsBeginImageContextWithOptions(image.size,NO,image.scale); [image drawAtPoint:CGPointZero]; [OVKThemeAccent() setFill]; UIRectFillUsingBlendMode((CGRect){CGPointZero,image.size},kCGBlendModeSourceIn); UIImage *result=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); if (result) [icons setObject:result forKey:cacheKey]; return result;
}

void OVKThemeSection(UIView *view) {
    if ([view isKindOfClass:[UILabel class]]) { UILabel *label=(UILabel *)view; label.textColor=OVKThemeSecondary(); label.shadowColor=nil; label.backgroundColor=[UIColor clearColor]; }
    for (UIView *child in view.subviews) OVKThemeSection(child);
}

UIImage *OVKThemeLogo(void) {
    UIImage *source=[UIImage imageNamed:@"Avatar"]; if (!source) return nil;
    UIGraphicsBeginImageContextWithOptions(source.size,NO,source.scale);
    [source drawAtPoint:CGPointZero]; [OVKBaseAccent() setFill];
    UIRectFillUsingBlendMode((CGRect){CGPointZero,source.size},kCGBlendModeSourceIn);
    UIImage *result=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return result;
}
// Restore the primary icon for installations that previously selected a theme icon.
#if __IPHONE_OS_VERSION_MAX_ALLOWED < 100300
@interface UIApplication (OVKPrimaryIconAPI)
@property (nonatomic, readonly) NSString *alternateIconName;
- (void)setAlternateIconName:(NSString *)name completionHandler:(void (^)(NSError *error))completion;
@end
#endif
void OVKRestoreDefaultApplicationIcon(void) {
    UIApplication *app=[UIApplication sharedApplication];
    if (![app respondsToSelector:@selector(alternateIconName)] || ![app respondsToSelector:@selector(setAlternateIconName:completionHandler:)] || !app.alternateIconName || app.applicationState!=UIApplicationStateActive) return;
    [app setAlternateIconName:nil completionHandler:^(NSError *error) { if (error) NSLog(@"Ovk-Mobile primary icon: %@",error.localizedDescription); }];
}

UIImage *OVKThemeStretch(NSString *name) {
    static NSDictionary *caps; static dispatch_once_t once;
    dispatch_once(&once, ^{ NSString *path=[[NSBundle mainBundle] pathForResource:@"ChromeCaps" ofType:@"json"]; NSData *data=path ? [NSData dataWithContentsOfFile:path] : nil; if (data) caps=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]; OVKStretchedImages=[[NSCache alloc] init]; OVKStretchedImages.countLimit=64; });
    UIImage *cached=[OVKStretchedImages objectForKey:name]; if (cached) return cached;
    UIImage *image=OVKThemeChrome(name); if (!image) return nil;
    NSArray *values=caps[name]; if (values.count!=4) return image;
    UIEdgeInsets insets=UIEdgeInsetsMake([values[0] doubleValue],[values[1] doubleValue],[values[2] doubleValue],[values[3] doubleValue]);
    if (insets.left+insets.right>=image.size.width || insets.top+insets.bottom>=image.size.height) return image;
    UIImage *result=[image resizableImageWithCapInsets:insets]; [OVKStretchedImages setObject:result forKey:name]; return result;
}
UIColor *OVKPostHeaderColor(void) {
    static UIColor *light,*dark; static dispatch_once_t once; dispatch_once(&once, ^{ light=[UIColor colorWithPatternImage:[UIImage imageNamed:@"PostHeader"]]; dark=[UIColor colorWithRed:.18 green:.21 blue:.25 alpha:1]; }); return OVKDarkTheme() ? dark : light;
}
UIColor *OVKPostFooterColor(void) {
    static UIColor *light,*dark; static dispatch_once_t once; dispatch_once(&once, ^{ light=[UIColor colorWithRed:.96 green:.97 blue:.98 alpha:1]; dark=[UIColor colorWithRed:.13 green:.15 blue:.18 alpha:1]; }); return OVKDarkTheme() ? dark : light;
}

UIColor *OVKProfilePanelColor(void) {
    static UIColor *panel; static dispatch_once_t once; dispatch_once(&once, ^{ panel=[UIColor colorWithPatternImage:[UIImage imageNamed:@"ProfilePanel"]]; }); return panel;
}
void OVKStyleAssetButton(UIButton *button, NSString *name) {
    [button setBackgroundImage:OVKThemeStretch(name) forState:UIControlStateNormal];
    NSString *pressed=[name stringByAppendingString:@"Pressed"];
    if ([UIImage imageNamed:pressed]) [button setBackgroundImage:OVKThemeStretch(pressed) forState:UIControlStateHighlighted];
}
