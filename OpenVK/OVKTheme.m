#import "OVKTheme.h"
NSArray *OVKThemeColors(void) { return @[@"blue",@"purple",@"red",@"green",@"orange",@"pink"]; }
NSString *OVKThemeColor(void) { NSString *value=[[NSUserDefaults standardUserDefaults] stringForKey:@"OVKThemeColor"]; return [OVKThemeColors() containsObject:value ?: @""] ? value : @"blue"; }
void OVKSetThemeColor(NSString *color) { if (![OVKThemeColors() containsObject:color]) return; [[NSUserDefaults standardUserDefaults] setObject:color forKey:@"OVKThemeColor"]; [[NSNotificationCenter defaultCenter] postNotificationName:@"OVKThemeChanged" object:nil]; }
static UIColor *OVKBaseAccent(void) {
    NSDictionary *colors=@{@"blue":@[@.31,@.45,@.60],@"purple":@[@.47,@.30,@.67],@"red":@[@.70,@.24,@.25],@"green":@[@.23,@.50,@.36],@"orange":@[@.73,@.39,@.15],@"pink":@[@.68,@.29,@.50]}; NSArray *rgb=colors[OVKThemeColor()]; return [UIColor colorWithRed:[rgb[0] doubleValue] green:[rgb[1] doubleValue] blue:[rgb[2] doubleValue] alpha:1];
}
BOOL OVKDarkTheme(void) { return [[NSUserDefaults standardUserDefaults] boolForKey:@"OVKDarkTheme"]; }
void OVKSetDarkTheme(BOOL dark) { [[NSUserDefaults standardUserDefaults] setBool:dark forKey:@"OVKDarkTheme"]; [[NSNotificationCenter defaultCenter] postNotificationName:@"OVKThemeChanged" object:nil]; }
UIColor *OVKThemeBackground(void) { return OVKDarkTheme() ? [UIColor colorWithRed:.09 green:.105 blue:.125 alpha:1] : [UIColor colorWithPatternImage:[UIImage imageNamed:@"Linen"]]; }
UIColor *OVKThemeSurface(void) { return OVKDarkTheme() ? [UIColor colorWithRed:.15 green:.17 blue:.20 alpha:1] : [UIColor whiteColor]; }
UIColor *OVKThemeText(void) { return OVKDarkTheme() ? [UIColor colorWithWhite:.92 alpha:1] : [UIColor colorWithWhite:.12 alpha:1]; }
UIColor *OVKThemeSecondary(void) { return OVKDarkTheme() ? [UIColor colorWithWhite:.66 alpha:1] : [UIColor grayColor]; }
UIColor *OVKThemeAccent(void) { UIColor *color=OVKBaseAccent(); if (!OVKDarkTheme()) return color; CGFloat red=0,green=0,blue=0,alpha=0; [color getRed:&red green:&green blue:&blue alpha:&alpha]; return [UIColor colorWithRed:red*.55+.45 green:green*.55+.45 blue:blue*.55+.45 alpha:1]; }
UIImage *OVKThemeChrome(NSString *name) {
    UIImage *original=[UIImage imageNamed:name]; if (!original || (!OVKDarkTheme() && [OVKThemeColor() isEqualToString:@"blue"])) return original;
    static NSCache *images=nil; static dispatch_once_t once; dispatch_once(&once, ^{ images=[[NSCache alloc] init]; }); NSString *cacheKey=[NSString stringWithFormat:@"%@:%d:%@",name,OVKDarkTheme(),OVKThemeColor()]; UIImage *saved=[images objectForKey:cacheKey]; if (saved) return saved;
    UIGraphicsBeginImageContextWithOptions(original.size,NO,original.scale); [original drawAtPoint:CGPointZero];
    if (![name hasPrefix:@"Music"] && ![OVKThemeColor() isEqualToString:@"blue"]) { [OVKBaseAccent() setFill]; UIRectFillUsingBlendMode((CGRect){CGPointZero,original.size},kCGBlendModeColor); [original drawAtPoint:CGPointZero blendMode:kCGBlendModeDestinationIn alpha:1]; }
    if (OVKDarkTheme()) { CGFloat shade=([name hasPrefix:@"Bubble"] || [name hasPrefix:@"Message"] || [name hasPrefix:@"Footer"] || [name isEqualToString:@"SectionBar"]) ? .78 : .55; [[UIColor colorWithWhite:0 alpha:shade] setFill]; UIRectFillUsingBlendMode((CGRect){CGPointZero,original.size},kCGBlendModeSourceAtop); } UIImage *result=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); if (result) [images setObject:result forKey:cacheKey]; return result;
}
void OVKThemeTable(UITableView *table) { table.backgroundView=nil; table.backgroundColor=OVKThemeBackground(); table.separatorColor=OVKDarkTheme() ? [UIColor colorWithWhite:.26 alpha:1] : [UIColor colorWithWhite:.87 alpha:1]; }
void OVKThemeCell(UITableViewCell *cell) { UIView *background=[[UIView alloc] initWithFrame:cell.bounds]; background.backgroundColor=OVKThemeSurface(); cell.backgroundView=background; cell.backgroundColor=OVKThemeSurface(); cell.textLabel.backgroundColor=[UIColor clearColor]; cell.detailTextLabel.backgroundColor=[UIColor clearColor]; cell.textLabel.textColor=OVKThemeText(); cell.detailTextLabel.textColor=OVKThemeSecondary(); if (cell.accessoryType==UITableViewCellAccessoryCheckmark) { UILabel *mark=[[UILabel alloc] initWithFrame:CGRectMake(0,0,24,24)]; mark.text=@"✓"; mark.textAlignment=NSTextAlignmentCenter; mark.font=[UIFont boldSystemFontOfSize:19]; mark.textColor=OVKThemeAccent(); mark.backgroundColor=[UIColor clearColor]; cell.accessoryView=mark; cell.accessibilityTraits|=UIAccessibilityTraitSelected; } }

void OVKThemeButtons(UIView *view) {
    if ([view isKindOfClass:[UISegmentedControl class]]) ((UISegmentedControl *)view).tintColor=OVKThemeAccent();
    if ([view isKindOfClass:[UIButton class]]) { UIButton *button=(UIButton *)view;
        if (button.buttonType==UIButtonTypeRoundedRect) { [button setBackgroundImage:[OVKThemeChrome(@"FooterButton") resizableImageWithCapInsets:UIEdgeInsetsMake(5,7,5,7)] forState:UIControlStateNormal]; [button setTitleColor:OVKThemeAccent() forState:UIControlStateNormal]; }
    }
    for (UIView *child in view.subviews) OVKThemeButtons(child);
}

UIImage *OVKThemeIcon(NSString *name) {
    BOOL activeLike=[name isEqualToString:@"PostLikeActive"]; UIImage *image=[UIImage imageNamed:activeLike ? @"PostLike" : name]; if (!image || (!activeLike && !OVKDarkTheme() && [OVKThemeColor() isEqualToString:@"blue"])) return image;
    static NSCache *icons=nil; static dispatch_once_t once; dispatch_once(&once, ^{ icons=[[NSCache alloc] init]; }); NSString *cacheKey=[NSString stringWithFormat:@"%@:%d:%@",name,OVKDarkTheme(),OVKThemeColor()]; UIImage *cached=[icons objectForKey:cacheKey]; if (cached) return cached;
    UIGraphicsBeginImageContextWithOptions(image.size,NO,image.scale); [image drawAtPoint:CGPointZero]; [OVKThemeAccent() setFill]; UIRectFillUsingBlendMode((CGRect){CGPointZero,image.size},kCGBlendModeSourceIn); UIImage *result=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); if (result) [icons setObject:result forKey:cacheKey]; return result;
}

void OVKThemeSection(UIView *view) {
    if ([view isKindOfClass:[UILabel class]]) { UILabel *label=(UILabel *)view; label.textColor=OVKThemeSecondary(); label.shadowColor=nil; label.backgroundColor=[UIColor clearColor]; }
    for (UIView *child in view.subviews) OVKThemeSection(child);
}
