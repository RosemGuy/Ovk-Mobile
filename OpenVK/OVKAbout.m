#import "OVKUI.h"
#import "OVKMedia.h"
@interface OVKAboutController ()
@property (strong, nonatomic) UIImageView *themeLogo;
@end
@implementation OVKAboutController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=OVKL(@"Об приложении"); OVKConfigureEdges(self); self.view.backgroundColor=OVKThemeBackground();
    UIScrollView *scroll=[[UIScrollView alloc] initWithFrame:self.view.bounds]; scroll.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; scroll.contentSize=CGSizeMake(self.view.bounds.size.width,470); [self.view addSubview:scroll];
    CGFloat width=MIN(420,self.view.bounds.size.width); UIView *panel=[[UIView alloc] initWithFrame:CGRectMake((self.view.bounds.size.width-width)/2,0,width,470)]; panel.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin; [scroll addSubview:panel];
    UIImageView *logo=[[UIImageView alloc] initWithImage:OVKThemeLogo()]; self.themeLogo=logo; logo.frame=CGRectMake((width-144)/2,30,144,144); logo.contentMode=UIViewContentModeScaleAspectFit; logo.userInteractionEnabled=YES; logo.accessibilityLabel=@"Ovk-Mobile"; [logo addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(logoHeld:)]]; [panel addSubview:logo];
    NSArray *lines=@[@"Ovk-Mobile alpha",OVKL(@"Версия 1.0"),OVKL(@"Авторы"),@"RosemaryDude  ·  bagmay904"];
    for (NSUInteger i=0;i<lines.count;i++) { UILabel *label=[[UILabel alloc] initWithFrame:CGRectMake(16,194+i*34,width-32,30)]; label.backgroundColor=[UIColor clearColor]; label.text=lines[i]; label.textAlignment=NSTextAlignmentCenter; label.textColor=i==2 ? OVKThemeSecondary() : OVKThemeText(); label.font=i==0 ? [UIFont boldSystemFontOfSize:24] : [UIFont systemFontOfSize:16]; [panel addSubview:label]; }
    UIButton *github=[UIButton buttonWithType:UIButtonTypeCustom]; github.frame=CGRectMake((width-260)/2,354,260,33); [github setTitle:OVKL(@"Проект на GitHub") forState:UIControlStateNormal]; github.titleLabel.font=[UIFont boldSystemFontOfSize:14]; [github setTitleColor:OVKThemeAccent() forState:UIControlStateNormal]; [github setBackgroundImage:[OVKThemeChrome(@"FooterButton") resizableImageWithCapInsets:UIEdgeInsetsMake(15,7,15,7)] forState:UIControlStateNormal]; [github addTarget:self action:@selector(openGitHub) forControlEvents:UIControlEventTouchUpInside]; [panel addSubview:github];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; self.themeLogo.image=OVKThemeLogo(); }
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; for (UIView *view in self.view.subviews) if ([view isKindOfClass:[UIScrollView class]]) ((UIScrollView *)view).contentSize=CGSizeMake(self.view.bounds.size.width,470); }
- (void)openGitHub { [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/RosemGuy/Ovk-Mobile/tree/main"]]; }
- (void)logoHeld:(UILongPressGestureRecognizer *)press { if (press.state==UIGestureRecognizerStateBegan) [OVKMedia showBundledVideo:@"AboutSecret" from:self]; }
@end
