#import <UIKit/UIKit.h>
BOOL OVKDarkTheme(void);
void OVKSetDarkTheme(BOOL dark);
UIColor *OVKThemeBackground(void);
UIColor *OVKThemeSurface(void);
UIColor *OVKThemeText(void);
UIColor *OVKThemeSecondary(void);
UIColor *OVKThemeAccent(void);
UIImage *OVKThemeChrome(NSString *name);
void OVKThemeTable(UITableView *table);
void OVKThemeCell(UITableViewCell *cell);

void OVKThemeButtons(UIView *view);

UIImage *OVKThemeIcon(NSString *name);

NSArray *OVKThemeColors(void);
NSString *OVKThemeColor(void);
void OVKSetThemeColor(NSString *color);

void OVKThemeSection(UIView *view);

void OVKClearThemeCaches(void);

UIImage *OVKThemeLogo(void);
void OVKRestoreDefaultApplicationIcon(void);

UIImage *OVKThemeStretch(NSString *name);
UIColor *OVKPostHeaderColor(void);
UIColor *OVKPostFooterColor(void);

UIColor *OVKProfilePanelColor(void);
void OVKStyleAssetButton(UIButton *button, NSString *name);

UIImage *OVKLoginLogo(void);
