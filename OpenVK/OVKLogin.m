#import <math.h>
#import "OVKLanguage.h"
#import "OVKUI.h"
#import "OVKAPI.h"
#import "OVKMusic.h"
@interface OVKOAuthController : UIViewController <UIWebViewDelegate>
@property (strong, nonatomic) UIWebView *web;
@property (strong, nonatomic) UILabel *webStatus;
@property (strong, nonatomic) UIActivityIndicatorView *webSpinner;
@property (strong, nonatomic) NSTimer *watchdog;
@property (copy, nonatomic) NSString *server;
@property (copy, nonatomic) void (^received)(NSString *token);
@end
@implementation OVKOAuthController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = OVKL(@"Вход OpenVK");
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:OVKL(@"Отмена") style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
    OVKConfigureEdges(self);
    self.webStatus = [[UILabel alloc] initWithFrame:CGRectMake(35,0,self.view.bounds.size.width-45,44)]; self.webStatus.autoresizingMask = UIViewAutoresizingFlexibleWidth; self.webStatus.font = [UIFont systemFontOfSize:11]; self.webStatus.numberOfLines = 2; self.webStatus.text = @"Загрузка страницы входа…"; [self.view addSubview:self.webStatus];
    self.webSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray]; self.webSpinner.frame = CGRectMake(8,12,20,20); self.webSpinner.hidesWhenStopped = YES; [self.webSpinner startAnimating]; [self.view addSubview:self.webSpinner];
    self.web = [[UIWebView alloc] initWithFrame:CGRectMake(0,44,self.view.bounds.size.width,MAX(0,self.view.bounds.size.height-44))]; self.web.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; self.web.delegate = self; [self.view addSubview:self.web];
    NSString *redirect = [self.server stringByAppendingString:@"/blank.html"];
    NSString *authServer = [self.server isEqualToString:@"https://api.openvk.org"] ? @"https://openvk.org" : self.server;
    NSString *url = [NSString stringWithFormat:@"%@/authorize?client_name=%@&redirect_uri=%@&display=page&response_type=token&revoke=0", authServer, OVKEncode(@"OpenVK Classic for iOS 6"), OVKEncode(redirect)];
    [self.web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:25]];
    self.watchdog = [NSTimer scheduledTimerWithTimeInterval:30 target:self selector:@selector(loadTimeout) userInfo:nil repeats:NO];
}
- (void)cancel { [self.watchdog invalidate]; self.watchdog = nil; self.web.delegate = nil; [self.web stopLoading]; [self dismissViewControllerAnimated:YES completion:nil]; }
- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)type {
    NSURL *url = request.URL; NSURL *origin = [NSURL URLWithString:self.server];
    if ([url.scheme isEqualToString:@"https"] && [url.host isEqualToString:origin.host] && [(url.port ?: @443) isEqual:(origin.port ?: @443)] && [url.path isEqualToString:@"/blank.html"]) {
        NSDictionary *params = OVKQuery(url.fragment ?: url.query ?: @""); NSString *token = OVKString(params[@"access_token"]);
        if (token.length) {
            void (^callback)(NSString *) = self.received; self.received = nil; [self.watchdog invalidate]; self.watchdog = nil; [self.webSpinner stopAnimating];
            [self dismissViewControllerAnimated:YES completion:^{ if (callback) callback(token); }];
        } else OVKAlert(OVKL(@"Вход не завершён"), OVKString(params[@"error_description"]).length ? params[@"error_description"] : OVKL(@"Сервер не вернул токен. Повторите вход."));
        return NO;
    }
    if ([url.scheme isEqualToString:@"about"]) return YES;
    if (![url.scheme isEqualToString:@"https"]) return NO;
    // Keep login credentials on the selected instance, including 2FA pages.
    BOOL officialLogin = [self.server isEqualToString:@"https://api.openvk.org"] && [url.host isEqualToString:@"openvk.org"] && (!url.port || [url.port isEqual:@443]);
    if (!officialLogin && (![url.host isEqualToString:origin.host] || ![(url.port ?: @443) isEqual:(origin.port ?: @443)])) {
        OVKAlert(OVKL(@"Другой домен входа"),@"Этот сервер перенаправляет авторизацию на другой домен. Укажите его на экране входа или используйте токен API."); return NO;
    }
    return YES;
}
- (void)loadTimeout {
    self.watchdog = nil; self.web.delegate = nil; [self.web stopLoading]; [self.webSpinner stopAnimating];
    self.webStatus.text = @"Сервер не загрузил вход за 30 секунд. Нажмите «Отмена» и используйте вход по паролю.";
    OVKAlert(OVKL(@"Вход не загрузился"),@"Сервер не ответил или страница несовместима со старым WebKit. Вернитесь назад и используйте нативный вход по логину и паролю.");
}
- (void)webViewDidFinishLoad:(UIWebView *)webView {
    if (webView.loading) return;
    [self.watchdog invalidate]; self.watchdog = nil; [self.webSpinner stopAnimating];
    NSString *content = [webView stringByEvaluatingJavaScriptFromString:@"document.body ? document.body.innerHTML : ''"];
    self.webStatus.text = content.length ? @"Если страница не работает, вернитесь и используйте вход по паролю." : @"Сервер вернул пустую страницу. Используйте нативный вход по паролю.";
}
- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
    if (error.code == NSURLErrorCancelled || error.code == 102) return;
    [self.watchdog invalidate]; self.watchdog = nil; [self.webSpinner stopAnimating];
    self.webStatus.text = [NSString stringWithFormat:@"%@ (%@ %ld)",error.localizedDescription,error.domain,(long)error.code]; OVKAlert(@"Не удалось открыть вход",self.webStatus.text);
}
- (void)dealloc { [_watchdog invalidate]; _web.delegate = nil; [_web stopLoading]; }
@end
// A visible browser for the user's own server challenge. No automated CAPTCHA solving.
@interface OVKVerificationController : UIViewController <UIWebViewDelegate>
@property (strong, nonatomic) UIWebView *web;
@property (strong, nonatomic) UILabel *status;
@property (strong, nonatomic) UIActivityIndicatorView *spinner;
@property (copy, nonatomic) NSString *server;
@property (strong, nonatomic) id<OVKCancellable> task;
@property (assign, nonatomic) BOOL cancelled;
@end
@implementation OVKVerificationController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = OVKL(@"Проверка сервера");
    OVKConfigureEdges(self);
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:OVKL(@"Отмена") style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:OVKL(@"Готово") style:UIBarButtonItemStyleDone target:self action:@selector(verify)];
    self.status = [[UILabel alloc] initWithFrame:CGRectMake(30,0,self.view.bounds.size.width-38,62)]; self.status.autoresizingMask = UIViewAutoresizingFlexibleWidth; self.status.font = [UIFont systemFontOfSize:11]; self.status.textAlignment = NSTextAlignmentCenter; self.status.numberOfLines = 3; self.status.text = OVKL(@"Пройдите проверку сайта, затем нажмите «Готово». Пароль здесь вводить не нужно."); [self.view addSubview:self.status];
    self.web = [[UIWebView alloc] initWithFrame:CGRectMake(0,62,self.view.bounds.size.width,MAX(0,self.view.bounds.size.height-62))]; self.web.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; self.web.delegate = self; self.web.scalesPageToFit = YES; [self.view addSubview:self.web];
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray]; self.spinner.frame = CGRectMake(5,20,20,20); self.spinner.hidesWhenStopped = YES; [self.view addSubview:self.spinner]; [self.spinner startAnimating];
    // Browser verification no longer changes the native API User-Agent (curl).
    NSURL *url = [NSURL URLWithString:[self.server stringByAppendingString:@"/method/ovk.test?v=5.131"]];
    [self.web loadRequest:[NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30]];
}
- (void)cancel {
    self.cancelled = YES; self.web.delegate = nil; [self.web stopLoading]; [self.task cancel]; self.task = nil; [self dismissViewControllerAnimated:YES completion:nil];
}
- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)type {
    NSString *scheme = request.URL.scheme.lowercaseString;
    if ([scheme isEqualToString:@"about"]) return YES;
    if (![scheme isEqualToString:@"https"]) { self.status.text = OVKL(@"Страница попыталась перейти без HTTPS. Переход остановлен."); return NO; }
    // Third-party HTTPS frames may be part of the provider's visible challenge.
    if ([request.URL isEqual:request.mainDocumentURL]) self.status.text = [NSString stringWithFormat:@"%@\nПройдите проверку сайта и нажмите «Готово».",request.URL.host];
    return YES;
}
- (void)webViewDidFinishLoad:(UIWebView *)webView { if (!webView.loading) [self.spinner stopAnimating]; }
- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
    if (error.code == NSURLErrorCancelled || error.code == 102) return;
    [self.spinner stopAnimating]; self.status.text = error.localizedDescription;
}
- (void)verify {
    if (self.task) return;
    if (![[OVKAPI shared].server isEqualToString:self.server]) { OVKAlert(OVKL(@"Изменён инстанс"),OVKL(@"Закройте проверку и выберите сервер заново.")); return; }
    self.navigationItem.rightBarButtonItem.enabled = NO; [self.spinner startAnimating]; self.status.text = OVKL(@"Проверяем API: User-Agent curl…");
    self.task = [[OVKAPI shared] checkConnection:^(id response,NSError *error) {
        self.task = nil; if (self.cancelled) return;
        self.navigationItem.rightBarButtonItem.enabled = YES; [self.spinner stopAnimating];
        if (error) {
            self.status.text = @"API всё ещё недоступен. Проверка могла не завершиться или не поддерживаться в iOS 6.";
            OVKAlert(OVKL(@"Проверка не помогла"),[NSString stringWithFormat:@"%@\n\nЕсли страница защиты пуста или сообщает об устаревшем браузере, нужен совместимый адрес API от администратора сервера.",error.localizedDescription]); return;
        }
        [self dismissViewControllerAnimated:YES completion:^{ OVKAlert(OVKL(@"API доступен"),@"Проверочный запрос прошёл. Теперь можно выполнить вход. Если сервер снова потребует проверку, её понадобится повторить."); }];
    }];
}
- (void)dealloc { _web.delegate = nil; [_web stopLoading]; }
@end
@interface OVKPasswordController : UIViewController <UIAlertViewDelegate>
@property (assign, nonatomic) BOOL embedded;
@property (copy, nonatomic) BOOL (^prepareLogin)(void);
@property (copy, nonatomic) void (^busyChanged)(BOOL busy);
@property (strong, nonatomic) UITextField *username;
@property (strong, nonatomic) UITextField *password;
@property (strong, nonatomic) UITextField *code;
@property (strong, nonatomic) UIButton *login;
@property (strong, nonatomic) UILabel *status;
@property (strong, nonatomic) UIScrollView *scroll;
@property (strong, nonatomic) UIActivityIndicatorView *spinner;
@property (strong, nonatomic) id<OVKCancellable> task;
@property (assign, nonatomic) BOOL cancelled;
@property (copy, nonatomic) NSString *server;
@property (copy, nonatomic) void (^received)(NSString *token);
@end
@implementation OVKPasswordController
- (UITextField *)field:(NSString *)placeholder y:(CGFloat)y secure:(BOOL)secure panel:(UIView *)panel {
    UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(20,y,280,44)]; field.borderStyle = UITextBorderStyleRoundedRect; field.placeholder = placeholder; field.secureTextEntry = secure; field.autocorrectionType = UITextAutocorrectionTypeNo; field.autocapitalizationType = UITextAutocapitalizationTypeNone; field.font = [UIFont systemFontOfSize:15]; [panel addSubview:field]; return field;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = OVKL(@"Вход в аккаунт");
    OVKConfigureEdges(self);
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:OVKL(@"Отмена") style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
    self.scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds]; self.scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; self.scroll.backgroundColor = [UIColor clearColor]; UIImageView *backdrop = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"LoginBackdrop"]]; backdrop.frame = self.view.bounds; backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; [self.view addSubview:backdrop]; self.scroll.contentSize = CGSizeMake(320,415); [self.view addSubview:self.scroll];
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(MAX(0,(self.view.bounds.size.width-320)/2),0,320,415)]; panel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin; [self.scroll addSubview:panel];
    UILabel *server = [[UILabel alloc] initWithFrame:CGRectMake(20,12,280,24)]; server.text = self.server; server.textAlignment = NSTextAlignmentCenter; server.font = [UIFont systemFontOfSize:12]; server.backgroundColor = [UIColor clearColor]; server.textColor = [UIColor colorWithWhite:.9 alpha:1]; [panel addSubview:server];
    self.username = [self field:OVKL(@"Логин или e-mail") y:48 secure:NO panel:panel]; self.username.keyboardType = UIKeyboardTypeEmailAddress;
    self.password = [self field:OVKL(@"Пароль") y:98 secure:YES panel:panel];
    self.code = [self field:OVKL(@"Код 2FA, если включён") y:148 secure:YES panel:panel]; self.code.keyboardType = UIKeyboardTypeNumberPad; self.code.hidden = YES;
    self.login = [UIButton buttonWithType:UIButtonTypeCustom]; self.login.frame = CGRectMake(20,154,280,46); OVKStyleAssetButton(self.login,@"LoginButton"); [self.login setTitle:OVKL(@"Войти") forState:UIControlStateNormal]; self.login.titleLabel.font = [UIFont boldSystemFontOfSize:16]; [self.login addTarget:self action:@selector(submit) forControlEvents:UIControlEventTouchUpInside]; [panel addSubview:self.login];
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray]; self.spinner.frame = CGRectMake(150,210,20,20); self.spinner.hidesWhenStopped = YES; [panel addSubview:self.spinner];
    self.status = [[UILabel alloc] initWithFrame:CGRectMake(20,242,280,100)]; self.status.numberOfLines = 0; self.status.textAlignment = NSTextAlignmentCenter; self.status.font = [UIFont systemFontOfSize:12]; self.status.textColor = [UIColor colorWithWhite:.85 alpha:1]; self.status.backgroundColor = [UIColor clearColor]; self.status.text = OVKL(@"Данные будут отправлены выбранному инстансу по HTTPS. Пароль на устройстве не сохраняется."); [panel addSubview:self.status];
    [self.login setBackgroundImage:OVKThemeStretch(@"LoginButtonPressed") forState:UIControlStateHighlighted];
    for (UITextField *field in @[self.username,self.password,self.code]) { field.borderStyle=UITextBorderStyleNone; field.background=OVKThemeStretch(@"LoginField"); UIView *padding=[[UIView alloc] initWithFrame:CGRectMake(0,0,14,1)]; field.leftView=padding; field.leftViewMode=UITextFieldViewModeAlways; field.contentVerticalAlignment=UIControlContentVerticalAlignmentCenter; }
    // Keep the native form and its working authentication, with the old blue login layout.
    for (UIView *element in panel.subviews) { CGRect frame=element.frame; frame.origin.y+=90; element.frame=frame; }
    UIImageView *wordmark=[[UIImageView alloc] initWithImage:[UIImage imageNamed:@"LoginWordmark"]]; wordmark.frame=CGRectMake(65,30,190,50); wordmark.contentMode=UIViewContentModeScaleAspectFit; [panel addSubview:wordmark];
    CGRect panelFrame=panel.frame; panelFrame.size.height=505; panel.frame=panelFrame; self.scroll.contentSize=CGSizeMake(320,505);
    if (self.embedded) {
        self.scroll.scrollEnabled=NO; self.scroll.backgroundColor=[UIColor clearColor]; backdrop.hidden=YES; server.hidden=YES;
        wordmark.image=OVKLoginLogo(); wordmark.frame=CGRectMake(112,18,96,96);
        self.username.frame=CGRectMake(20,130,280,44); self.password.frame=CGRectMake(20,182,280,44); self.login.frame=CGRectMake(20,236,280,46);
        self.status.frame=CGRectMake(20,284,280,28); self.status.font=[UIFont systemFontOfSize:10]; self.status.numberOfLines=2; self.status.text=@""; self.spinner.frame=CGRectMake(150,288,20,20);
        panel.frame=CGRectMake(0,0,320,316); self.scroll.contentSize=CGSizeMake(320,316);
    } else [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboard:) name:UIKeyboardWillChangeFrameNotification object:nil];
}
- (void)keyboard:(NSNotification *)note {
    CGRect frame = [self.view convertRect:[note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil]; CGFloat bottom = MAX(0,CGRectGetMaxY(self.view.bounds)-CGRectGetMinY(frame)); self.scroll.contentInset = UIEdgeInsetsMake(0,0,bottom,0); self.scroll.scrollIndicatorInsets = self.scroll.contentInset;
}
- (void)cancel {
    self.cancelled = YES; [self.task cancel]; self.task = nil; self.password.text = @""; self.code.text = @""; [self dismissViewControllerAnimated:YES completion:nil];
}
- (void)submit {
    if (self.task) return;
    if (self.prepareLogin && !self.prepareLogin()) return;
    NSString *username = [self.username.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!username.length || !self.password.text.length) { OVKAlert(OVKL(@"Заполните поля"),OVKL(@"Введите логин и пароль аккаунта выбранного инстанса.")); return; }
    [self.view endEditing:YES]; self.login.enabled = NO; self.username.enabled = NO; self.password.enabled = NO; self.code.enabled = NO; [self.spinner startAnimating]; self.status.text = OVKL(@"Подключение к серверу…");
    if (self.busyChanged) self.busyChanged(YES);
    // No password is written to defaults, Keychain, URL, or logs.
    self.task = [[OVKAPI shared] authenticateUsername:username password:self.password.text code:self.code.text completion:^(id response,NSError *error) {
        self.task = nil; if (self.cancelled) return;
        if (self.busyChanged) self.busyChanged(NO);
        self.login.enabled = YES; self.username.enabled = YES; self.password.enabled = YES; self.code.enabled = YES; [self.spinner stopAnimating];
        if (error) {
            if ([OVKString(error.userInfo[@"OVKAuthReason"]) isEqualToString:@"need_validation"]) { self.status.text = OVKL(@"Нужен код двухфакторной авторизации"); [self askForCode]; return; }
            NSString *text = error.localizedDescription;
            if ([error.domain isEqualToString:NSURLErrorDomain] && error.code <= -1200 && error.code >= -1206 && [error.localizedDescription rangeOfString:@"ISRG Root X1"].location == NSNotFound) text = @"Не удалось установить защищённое соединение. Проверьте дату в виртуалке, сеть и сертификаты iOS 6. Ошибки TLS не обходятся.";
            self.status.text = [NSString stringWithFormat:@"%@\nКод: %@ %ld",text,error.domain,(long)error.code];
            OVKAlert(OVKL(@"Не удалось войти"),self.status.text); return;
        }
        NSString *token = OVKString(OVKDictionary(response)[@"access_token"]);
        self.password.text = @""; self.code.text = @"";
        void (^callback)(NSString *) = self.received;
        if (self.embedded) { if (callback) callback(token); }
        else { self.received=nil; [self dismissViewControllerAnimated:YES completion:^{ if (callback) callback(token); }]; }
    }];
}
- (void)askForCode {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:OVKL(@"Двухфакторная авторизация") message:OVKL(@"Введите одноразовый код двухфакторной авторизации для этого аккаунта.") delegate:self cancelButtonTitle:OVKL(@"Отмена") otherButtonTitles:OVKL(@"Продолжить"),nil];
    alert.alertViewStyle = UIAlertViewStylePlainTextInput; alert.tag = 206;
    UITextField *field = [alert textFieldAtIndex:0]; field.keyboardType = UIKeyboardTypeNumberPad; field.secureTextEntry = YES; [alert show];
}
- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index {
    if (alert.tag != 206 || self.cancelled) return;
    if (index == alert.cancelButtonIndex) { self.code.text = @""; return; }
    NSString *code = [[alert textFieldAtIndex:0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!code.length) { self.status.text = OVKL(@"Код не введён. Нажмите «Войти», чтобы повторить."); return; }
    self.code.text = code; [self submit];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end
@interface OVKLoginController () <UIAlertViewDelegate>
@property (strong, nonatomic) OVKPasswordController *loginForm;
@property (strong, nonatomic) UIView *advancedPanel;
@property (strong, nonatomic) UIScrollView *loginScroll;
@property (strong, nonatomic) UILabel *instanceLabel;
@property (strong, nonatomic) UIButton *advancedButton;
@property (assign, nonatomic) BOOL advancedShown;
@property (strong, nonatomic) UITextField *serverField;
@property (strong, nonatomic) UITextField *apiField;
@property (copy, nonatomic) NSString *customAPI;
@property (strong, nonatomic) UIButton *checkButton;
@property (strong, nonatomic) UITextField *tokenField;
@property (strong, nonatomic) UIButton *oauthButton;
@property (strong, nonatomic) UIButton *tokenButton;
@property (strong, nonatomic) UILabel *status;
@property (strong, nonatomic) UISegmentedControl *instancePicker;
@property (copy, nonatomic) NSString *customServer;
@end
@implementation OVKLoginController
- (UIButton *)button:(NSString *)title y:(CGFloat)y action:(SEL)action inView:(UIView *)container {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeRoundedRect]; button.frame = CGRectMake(20,y,280,42); button.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [button setTitle:title forState:UIControlStateNormal]; [button setTitleColor:OVKBlue() forState:UIControlStateNormal]; button.titleLabel.font = [UIFont boldSystemFontOfSize:15]; [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside]; [container addSubview:button]; return button;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"Ovk-Mobile"; self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:OVKL(@"Музыка") style:UIBarButtonItemStylePlain target:self action:@selector(localMusic)];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:OVKL(@"Аккаунты") style:UIBarButtonItemStylePlain target:self action:@selector(openSavedAccounts)];
    OVKConfigureEdges(self);
    UIImageView *backdrop=[[UIImageView alloc] initWithImage:[UIImage imageNamed:@"LoginBackdrop"]]; backdrop.frame=self.view.bounds; backdrop.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; [self.view addSubview:backdrop];
    UIScrollView *scroll=[[UIScrollView alloc] initWithFrame:self.view.bounds]; self.loginScroll=scroll; scroll.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; scroll.alwaysBounceVertical=YES; [self.view addSubview:scroll];
    UIView *panel=[[UIView alloc] initWithFrame:CGRectMake(MAX(0,(self.view.bounds.size.width-320)/2),0,320,420)]; panel.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin; [scroll addSubview:panel]; scroll.contentSize=CGSizeMake(self.view.bounds.size.width,420);
    self.loginForm=[[OVKPasswordController alloc] init]; self.loginForm.embedded=YES;
    __weak OVKLoginController *weakSelf=self;
    self.loginForm.prepareLogin=^BOOL { return [weakSelf prepare]; };
    self.loginForm.busyChanged=^(BOOL busy) { weakSelf.view.userInteractionEnabled=!busy; weakSelf.navigationItem.rightBarButtonItem.enabled=!busy; weakSelf.navigationItem.leftBarButtonItem.enabled=!busy; };
    self.loginForm.received=^(NSString *token) { [weakSelf validate:token]; };
    [self addChildViewController:self.loginForm]; self.loginForm.view.frame=CGRectMake(0,0,320,316); self.loginForm.view.backgroundColor=[UIColor clearColor]; [panel addSubview:self.loginForm.view]; [self.loginForm didMoveToParentViewController:self];
    UIButton *instances=[UIButton buttonWithType:UIButtonTypeCustom]; instances.frame=CGRectMake(20,318,280,32); instances.titleLabel.font=[UIFont boldSystemFontOfSize:13]; [instances setTitle:OVKL(@"Выбрать инстанс") forState:UIControlStateNormal]; [instances setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal]; [instances addTarget:self action:@selector(showInstances) forControlEvents:UIControlEventTouchUpInside]; [panel addSubview:instances];
    self.instanceLabel=[[UILabel alloc] initWithFrame:CGRectMake(20,348,280,18)]; self.instanceLabel.backgroundColor=[UIColor clearColor]; self.instanceLabel.font=[UIFont systemFontOfSize:11]; self.instanceLabel.textColor=[UIColor colorWithWhite:.85 alpha:1]; self.instanceLabel.textAlignment=NSTextAlignmentCenter; [panel addSubview:self.instanceLabel];
    self.advancedButton=[UIButton buttonWithType:UIButtonTypeCustom]; self.advancedButton.frame=CGRectMake(20,376,280,30); [self.advancedButton setTitle:OVKL(@"Дополнительно ▾") forState:UIControlStateNormal]; self.advancedButton.titleLabel.font=[UIFont systemFontOfSize:12]; [self.advancedButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal]; [self.advancedButton addTarget:self action:@selector(toggleAdvanced) forControlEvents:UIControlEventTouchUpInside]; [panel addSubview:self.advancedButton];
    self.advancedPanel=[[UIView alloc] initWithFrame:CGRectMake(0,416,320,526)]; self.advancedPanel.hidden=YES; [panel addSubview:self.advancedPanel];
    UIView *advanced=self.advancedPanel;
    self.instancePicker=[[UISegmentedControl alloc] initWithItems:@[@"openvk.org",OVKL(@"Другой")]]; self.instancePicker.frame=CGRectMake(20,0,280,32); self.instancePicker.tintColor=OVKBlue(); [self.instancePicker addTarget:self action:@selector(selectInstance) forControlEvents:UIControlEventValueChanged]; [advanced addSubview:self.instancePicker];
    self.serverField=[[UITextField alloc] initWithFrame:CGRectMake(20,44,280,38)]; self.apiField=[[UITextField alloc] initWithFrame:CGRectMake(20,92,280,38)];
    for (UITextField *field in @[self.serverField,self.apiField]) { field.borderStyle=UITextBorderStyleRoundedRect; field.keyboardType=UIKeyboardTypeURL; field.autocapitalizationType=UITextAutocapitalizationTypeNone; field.autocorrectionType=UITextAutocorrectionTypeNo; field.font=[UIFont systemFontOfSize:12]; [advanced addSubview:field]; }
    self.serverField.placeholder=@"https://example.org"; self.apiField.placeholder=OVKL(@"API-домен (пусто = домен сайта)");
    self.checkButton=[self button:OVKL(@"Проверить API") y:142 action:@selector(checkAPI) inView:advanced]; self.checkButton.frame=CGRectMake(20,142,135,38); self.checkButton.titleLabel.font=[UIFont boldSystemFontOfSize:11];
    UIButton *verification=[self button:OVKL(@"Проверка защиты") y:142 action:@selector(verifyProtection) inView:advanced]; verification.frame=CGRectMake(165,142,135,38); verification.titleLabel.font=[UIFont boldSystemFontOfSize:11];
    // Existing validation code uses this button as the login busy-state control.
    self.oauthButton=self.loginForm.login;
    [self button:OVKL(@"Демонстрация без аккаунта") y:194 action:@selector(demo) inView:advanced];
    [self button:OVKL(@"Альтернативный веб-вход") y:246 action:@selector(oauth) inView:advanced];
    self.tokenField=[[UITextField alloc] initWithFrame:CGRectMake(20,300,280,38)]; self.tokenField.borderStyle=UITextBorderStyleRoundedRect; self.tokenField.placeholder=OVKL(@"Access token выбранного инстанса"); self.tokenField.secureTextEntry=YES; self.tokenField.autocapitalizationType=UITextAutocapitalizationTypeNone; self.tokenField.autocorrectionType=UITextAutocorrectionTypeNo; [advanced addSubview:self.tokenField];
    self.tokenButton=[self button:OVKL(@"Войти по токену") y:350 action:@selector(tokenLogin) inView:advanced];
    self.status=[[UILabel alloc] initWithFrame:CGRectMake(20,404,280,100)]; self.status.backgroundColor=[UIColor clearColor]; self.status.textColor=[UIColor colorWithWhite:.9 alpha:1]; self.status.font=[UIFont systemFontOfSize:11]; self.status.numberOfLines=0; self.status.textAlignment=NSTextAlignmentCenter; self.status.text=OVKL(@"Ovk-Mobile alpha • iOS 6\nНеофициальный клиент"); [advanced addSubview:self.status];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loginKeyboard:) name:UIKeyboardWillChangeFrameNotification object:nil];
    NSString *site = [OVKAPI shared].siteServer ?: [OVKAPI shared].server;
    if ([site isEqualToString:@"https://openvk.xyz"]) site=@"https://openvk.org";
    self.instancePicker.selectedSegmentIndex = [site isEqualToString:@"https://openvk.org"] ? 0 : 1;
    self.customServer = self.instancePicker.selectedSegmentIndex == 1 ? site : @"";
    self.customAPI = self.instancePicker.selectedSegmentIndex == 1 ? [OVKAPI shared].server : @"";
    self.serverField.enabled = NO; [self selectInstance];
}
- (void)toggleAdvanced {
    self.advancedShown=!self.advancedShown; self.advancedPanel.hidden=!self.advancedShown;
    UIView *panel=self.advancedPanel.superview; CGRect frame=panel.frame; frame.size.height=self.advancedShown ? 950 : 420; panel.frame=frame;
    self.loginScroll.contentSize=CGSizeMake(self.view.bounds.size.width,frame.size.height);
    [self.advancedButton setTitle:self.advancedShown ? OVKL(@"Дополнительно ▴") : OVKL(@"Дополнительно ▾") forState:UIControlStateNormal];
    if (self.advancedShown) [self.loginScroll scrollRectToVisible:CGRectMake(0,416,320,180) animated:YES];
}
- (void)loginKeyboard:(NSNotification *)note {
    CGRect keyboard=[self.view convertRect:[note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil]; CGFloat overlap=CGRectGetHeight(CGRectIntersection(self.view.bounds,keyboard)); if (!isfinite(overlap)) overlap=0;
    self.loginScroll.contentInset=UIEdgeInsetsMake(0,0,overlap,0); self.loginScroll.scrollIndicatorInsets=self.loginScroll.contentInset;
    UIView *field=self.loginForm.username.isFirstResponder ? self.loginForm.username : (self.loginForm.password.isFirstResponder ? self.loginForm.password : nil);
    if (field) [self.loginScroll scrollRectToVisible:[field convertRect:field.bounds toView:self.loginScroll] animated:YES];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)openSavedAccounts { [self.navigationController pushViewController:[[OVKAccountsController alloc] initWithStyle:UITableViewStyleGrouped] animated:YES]; }
- (void)localMusic { [self.navigationController pushViewController:[[OVKMusicController alloc] init] animated:YES]; }
- (void)selectInstance {
    [self.view endEditing:YES];
    if (self.serverField.enabled) { self.customServer = self.serverField.text; self.customAPI = self.apiField.text; }
    BOOL custom = self.instancePicker.selectedSegmentIndex == 1;
    self.serverField.enabled = custom;
    if (custom) { self.serverField.text = self.customServer ?: @""; self.apiField.text = self.customAPI ?: @""; }
    else {
        self.serverField.text = @"https://openvk.org";
        self.apiField.text = @"https://api.openvk.org";
    }
    [self.oauthButton setTitle:OVKL(@"Войти") forState:UIControlStateNormal]; self.instanceLabel.text=self.serverField.text; self.loginForm.password.text=@""; self.loginForm.code.text=@"";
    self.tokenField.text = @"";
}
- (BOOL)prepare {
    [self.view endEditing:YES]; NSString *site = [OVKAPI validatedServer:self.serverField.text];
    NSString *apiInput = [self.apiField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *server = apiInput.length ? [OVKAPI validatedServer:apiInput] : site;
    if (!site || !server) { OVKAlert(OVKL(@"Адрес сервера"),@"Укажите HTTPS-домены сайта и API без /method, пути и параметров. API-домен можно оставить пустым, если он совпадает с сайтом."); return NO; }
    self.instanceLabel.text=site;
    [OVKAPI shared].server = server; [OVKAPI shared].siteServer = site; [OVKAPI shared].demo = NO;
    [OVKInstancesController rememberSite:site api:server]; [[NSUserDefaults standardUserDefaults] setObject:site forKey:@"OVKSelectedSite"]; [[NSUserDefaults standardUserDefaults] setObject:server forKey:@"OVKSelectedAPI"]; return YES;
}
- (void)checkAPI {
    if (![self prepare]) return;
    self.checkButton.enabled = NO; self.oauthButton.enabled = NO; self.tokenButton.enabled = NO; self.instancePicker.enabled = NO; self.serverField.enabled = NO; self.apiField.enabled = NO; self.status.text = OVKL(@"Проверка API без пароля…");
    NSString *server = [[OVKAPI shared].server copy];
    [[OVKAPI shared] checkConnection:^(id response,NSError *error) {
        self.checkButton.enabled = YES; self.oauthButton.enabled = YES; self.tokenButton.enabled = YES; self.instancePicker.enabled = YES; self.serverField.enabled = self.instancePicker.selectedSegmentIndex == 1; self.apiField.enabled = YES;
        self.status.text = error ? [NSString stringWithFormat:@"%@\n%@",server,error.localizedDescription] : OVKL(@"API отвечает. Вход проверяется отдельно.");
        if ([error.domain isEqualToString:@"OpenVK"] && error.code == 403) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:OVKL(@"HTTP 403 — доступ запрещён") message:self.status.text delegate:self cancelButtonTitle:OVKL(@"Закрыть") otherButtonTitles:OVKL(@"Открыть проверку"),nil]; alert.tag = 403; [alert show];
        } else OVKAlert(error ? OVKL(@"API недоступен") : OVKL(@"API отвечает"),error ? self.status.text : @"Публичный метод вернул JSON. Теперь можно попробовать вход на этом инстансе.");
    }];
}
- (void)showInstances {
    if (!self.checkButton.enabled) return;
    __weak OVKLoginController *weakSelf = self;
    OVKInstancesController *list = [[OVKInstancesController alloc] initWithSelection:^(NSString *site,NSString *api) {
        OVKLoginController *page = weakSelf; if (!page) return;
        page.customServer = site; page.customAPI = api; page.serverField.enabled = NO; page.instancePicker.selectedSegmentIndex = 1; [page selectInstance]; [page prepare];
    }];
    UINavigationController *nav = [[OVKNavigationController alloc] initWithRootViewController:list]; OVKStyleNavigation(nav); [self presentViewController:nav animated:YES completion:nil];
}
- (void)verifyProtection {
    if (!self.checkButton.enabled || ![self prepare]) return;
    OVKVerificationController *page = [[OVKVerificationController alloc] init]; page.server = [OVKAPI shared].server;
    UINavigationController *nav = [[OVKNavigationController alloc] initWithRootViewController:page]; OVKStyleNavigation(nav); [self presentViewController:nav animated:YES completion:nil];
}
- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index { if (alert.tag == 403 && index == 1) [self verifyProtection]; }
- (void)passwordLogin {
    if (![self prepare]) return;
    OVKPasswordController *login = [[OVKPasswordController alloc] init]; login.server = [OVKAPI shared].server;
    __weak OVKLoginController *weakSelf = self; login.received = ^(NSString *token){ [weakSelf validate:token]; };
    UINavigationController *nav = [[OVKNavigationController alloc] initWithRootViewController:login]; OVKStyleNavigation(nav); [self presentViewController:nav animated:YES completion:nil];
}
- (void)oauth {
    if (![self prepare]) return;
    OVKOAuthController *oauth = [[OVKOAuthController alloc] init]; oauth.server = [OVKAPI shared].siteServer;
    __weak OVKLoginController *weakSelf = self;
    oauth.received = ^(NSString *token){ [weakSelf validate:token]; };
    UINavigationController *nav = [[OVKNavigationController alloc] initWithRootViewController:oauth]; OVKStyleNavigation(nav); [self presentViewController:nav animated:YES completion:nil];
}
- (void)tokenLogin { if ([self prepare]) [self validate:[self.tokenField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]]; }
- (void)validate:(NSString *)token {
    if (!token.length) { OVKAlert(OVKL(@"Нет токена"),OVKL(@"Вставьте токен вашего аккаунта OpenVK.")); return; }
    OVKAPI *api = [OVKAPI shared]; api.token = token;
    self.view.userInteractionEnabled=NO; self.navigationItem.rightBarButtonItem.enabled=NO; self.navigationItem.leftBarButtonItem.enabled=NO;
    self.oauthButton.enabled = NO; self.tokenButton.enabled = NO; self.instancePicker.enabled = NO; self.serverField.enabled = NO; self.apiField.enabled = NO; self.checkButton.enabled = NO; self.status.text = OVKL(@"Проверяем аккаунт…");
    [api call:@"users.get" parameters:@{@"fields":@"photo_100,status"} completion:^(id result, NSError *error) {
        self.view.userInteractionEnabled=YES; self.navigationItem.rightBarButtonItem.enabled=YES; self.navigationItem.leftBarButtonItem.enabled=YES;
        self.oauthButton.enabled = YES; self.tokenButton.enabled = YES; self.instancePicker.enabled = YES; self.serverField.enabled = self.instancePicker.selectedSegmentIndex == 1; self.apiField.enabled = YES; self.checkButton.enabled = YES;
        NSDictionary *user = OVKDictionary([OVKArray(result) count] ? result[0] : nil);
        if (error || [user[@"id"] integerValue] <= 0) { api.token = nil; self.status.text = OVKL(@"Вход не выполнен"); OVKAlert(OVKL(@"Ошибка входа"),error.localizedDescription ?: OVKL(@"Сервер не вернул профиль аккаунта")); return; }
        api.userID = user[@"id"]; api.accountName=[[NSString stringWithFormat:@"%@ %@",OVKString(user[@"first_name"]),OVKString(user[@"last_name"])] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (![api save]) OVKAlert(OVKL(@"Сеанс не сохранён"),[api keychainErrorDescription]);
        self.tokenField.text = @"";
        [(OVKAppDelegate *)[UIApplication sharedApplication].delegate showClient];
    }];
}
- (void)demo { [self.view endEditing:YES]; if (!self.oauthButton.enabled) return; OVKAPI *api = [OVKAPI shared]; api.demo = YES; api.token = nil; api.userID = @1; [(OVKAppDelegate *)[UIApplication sharedApplication].delegate showClient]; }
@end
