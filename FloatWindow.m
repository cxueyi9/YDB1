#import "FloatWindow.h"
#import "AccountManager.h"

@interface FloatView : UIView
@property (nonatomic, weak) UILabel *badgeLabel;
@property (nonatomic, assign) BOOL isEditing;
@end

@implementation FloatView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:0.9];
        self.layer.cornerRadius = frame.size.width / 2;
        self.clipsToBounds = YES;
        
        UILabel *badge = [[UILabel alloc] initWithFrame:self.bounds];
        badge.textAlignment = NSTextAlignmentCenter;
        badge.textColor = [UIColor whiteColor];
        badge.font = [UIFont boldSystemFontOfSize:16];
        badge.text = @"0";
        [self addSubview:badge];
        _badgeLabel = badge;
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
        
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        [self addGestureRecognizer:tap];
        
        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
        [self addGestureRecognizer:longPress];
    }
    return self;
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    if (self.isEditing) return;
    CGPoint translation = [pan translationInView:self.superview];
    CGPoint newCenter = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    
    CGFloat half = self.bounds.size.width / 2;
    CGFloat margin = 10;
    newCenter.x = MAX(half + margin, MIN(newCenter.x, self.superview.bounds.size.width - half - margin));
    newCenter.y = MAX(half + margin + 20, MIN(newCenter.y, self.superview.bounds.size.height - half - margin - 20));
    
    self.center = newCenter;
    [pan setTranslation:CGPointZero inView:self.superview];
}

- (void)handleTap:(UITapGestureRecognizer *)tap {
    if (self.isEditing) return;
    
    AccountManager *mgr = [AccountManager shared];
    if (mgr.accounts.count == 0) return;
    
    NSDictionary *acc = [mgr nextAccount];
    if (acc) {
        [self fillAccount:acc[@"account"] password:acc[@"password"]];
        [[FloatWindow shared] updateBadge];
    }
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)longPress {
    if (longPress.state == UIGestureRecognizerStateBegan) {
        [self showEditPanel];
    }
}

- (void)fillAccount:(NSString *)account password:(NSString *)password {
    UIWindow *mainWindow = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w != [FloatWindow shared] && w.hidden == NO && w.windowLevel == UIWindowLevelNormal) {
            mainWindow = w;
            break;
        }
    }
    if (!mainWindow) return;
    
    NSMutableArray<UITextField *> *textFields = [NSMutableArray array];
    [self findTextFieldsInView:mainWindow result:textFields];
    
    UITextField *accountField = nil;
    UITextField *passwordField = nil;
    
    for (UITextField *tf in textFields) {
        NSString *placeholder = tf.placeholder ?: @"";
        NSString *lower = placeholder.lowercaseString;
        if ([lower containsString:@"手机"] || [lower containsString:@"账号"] ||
            [lower containsString:@"用户名"] || [lower containsString:@"account"] || [lower containsString:@"phone"]) {
            accountField = tf;
        } else if ([lower containsString:@"密码"] || [lower containsString:@"password"]) {
            passwordField = tf;
        }
    }
    
    if (!accountField && !passwordField) {
        for (UITextField *tf in textFields) {
            if (tf.isSecureTextEntry) {
                passwordField = tf;
            } else {
                accountField = tf;
            }
        }
    }
    if (!accountField) {
        for (UITextField *tf in textFields) {
            if (tf != passwordField) {
                accountField = tf;
                break;
            }
        }
    }
    
    if (accountField) {
        accountField.text = account;
        [accountField sendActionsForControlEvents:UIControlEventEditingChanged];
    }
    if (passwordField) {
        passwordField.text = password;
        [passwordField sendActionsForControlEvents:UIControlEventEditingChanged];
    }
}

- (void)findTextFieldsInView:(UIView *)view result:(NSMutableArray<UITextField *> *)result {
    if ([view isKindOfClass:[UITextField class]]) {
        UITextField *tf = (UITextField *)view;
        // 收集所有输入框信息，用弹窗显示
        NSString *info = [NSString stringWithFormat:
                          @"placeholder: %@\n"
                          @"secure: %d\n"
                          @"text: %@\n"
                          @"accessibilityId: %@\n"
                          @"class: %@\n"
                          @"tag: %ld",
                          tf.placeholder ?: @"(nil)",
                          tf.isSecureTextEntry,
                          tf.text ?: @"(nil)",
                          tf.accessibilityIdentifier ?: @"(nil)",
                          NSStringFromClass([tf class]),
                          (long)tf.tag];
        
        // 弹出信息（注意：这会在每次点击填充时弹窗，显示所有输入框的信息）
        [self showDebugAlert:info];
        
        [result addObject:tf];
    }
    for (UIView *sub in view.subviews) {
        [self findTextFieldsInView:sub result:result];
    }
}

// 临时辅助方法：显示调试信息
- (void)showDebugAlert:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"输入框信息" message:message preferredStyle:UIAlertControllerStyleAlert];
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    [rootVC presentViewController:alert animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [alert dismissViewControllerAnimated:YES completion:nil];
    });
}

// 弹出配置面板（新增导入/导出按钮）
- (void)showEditPanel {
    if (self.isEditing) return;
    self.isEditing = YES;
    
    UIView *superview = self.superview;
    CGRect screenBounds = superview.bounds;
    
    // 半透明背景
    UIView *cover = [[UIView alloc] initWithFrame:screenBounds];
    cover.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];
    cover.tag = 1001;
    [superview addSubview:cover];
    
    CGFloat panelW = screenBounds.size.width - 60;
    CGFloat panelH = 340;  // 稍微加高以容纳按钮
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake((screenBounds.size.width - panelW)/2,
                                                              (screenBounds.size.height - panelH)/2 - 50,
                                                              panelW, panelH)];
    panel.backgroundColor = [UIColor whiteColor];
    panel.layer.cornerRadius = 12;
    panel.tag = 1002;
    [superview addSubview:panel];
    
    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(15, 10, panelW-30, 20)];
    hint.text = @"每行输入：账号|密码";
    hint.font = [UIFont systemFontOfSize:13];
    hint.textColor = [UIColor grayColor];
    [panel addSubview:hint];
    
    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(15, 35, panelW-30, 190)];
    tv.layer.borderWidth = 0.5;
    tv.layer.borderColor = [UIColor lightGrayColor].CGColor;
    tv.font = [UIFont systemFontOfSize:15];
    tv.tag = 1003;
    
    AccountManager *mgr = [AccountManager shared];
    tv.text = [mgr exportAccountsText];
    [panel addSubview:tv];
    
    // 第一行按钮：保存 / 取消
    UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    saveBtn.frame = CGRectMake(panelW/2 + 20, 240, 80, 35);
    [saveBtn setTitle:@"保存" forState:UIControlStateNormal];
    [saveBtn addTarget:self action:@selector(saveAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:saveBtn];
    
    UIButton *cancelBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    cancelBtn.frame = CGRectMake(panelW/2 - 100, 240, 80, 35);
    [cancelBtn setTitle:@"取消" forState:UIControlStateNormal];
    [cancelBtn addTarget:self action:@selector(cancelAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:cancelBtn];
    
    // 第二行按钮：导入 / 导出
    UIButton *importBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    importBtn.frame = CGRectMake(15, 285, 100, 35);
    [importBtn setTitle:@"从剪贴板导入" forState:UIControlStateNormal];
    importBtn.titleLabel.font = [UIFont systemFontOfSize:14];
    [importBtn addTarget:self action:@selector(importAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:importBtn];
    
    UIButton *exportBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    exportBtn.frame = CGRectMake(panelW - 115, 285, 100, 35);
    [exportBtn setTitle:@"导出到剪贴板" forState:UIControlStateNormal];
    exportBtn.titleLabel.font = [UIFont systemFontOfSize:14];
    [exportBtn addTarget:self action:@selector(exportAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:exportBtn];
    
    UITapGestureRecognizer *tapOnCover = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cancelAction:)];
    [cover addGestureRecognizer:tapOnCover];
}

- (void)saveAction:(id)sender {
    UIView *superview = self.superview;
    UIView *panel = [superview viewWithTag:1002];
    UITextView *tv = (UITextView *)[panel viewWithTag:1003];
    
    [[AccountManager shared] updateAccountsWithText:tv.text];
    [[FloatWindow shared] updateBadge];
    [self dismissPanel];
    [self showAlert:@"保存成功"];
}

- (void)cancelAction:(id)sender {
    [self dismissPanel];
}

- (void)importAction:(id)sender {
    [[AccountManager shared] importFromClipboard];
    // 刷新文本框内容
    UIView *superview = self.superview;
    UIView *panel = [superview viewWithTag:1002];
    UITextView *tv = (UITextView *)[panel viewWithTag:1003];
    tv.text = [[AccountManager shared] exportAccountsText];
    [[FloatWindow shared] updateBadge];
    [self showAlert:@"已从剪贴板导入"];
}

- (void)exportAction:(id)sender {
    [[AccountManager shared] exportToClipboard];
    [self showAlert:@"已复制到剪贴板"];
}

- (void)dismissPanel {
    UIView *superview = self.superview;
    [[superview viewWithTag:1001] removeFromSuperview];
    [[superview viewWithTag:1002] removeFromSuperview];
    self.isEditing = NO;
}

- (void)showAlert:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    [rootVC presentViewController:alert animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [alert dismissViewControllerAnimated:YES completion:nil];
    });
}

@end

@implementation FloatWindow {
    FloatView *_floatView;
}

+ (instancetype)shared {
    static FloatWindow *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[FloatWindow alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = (UIWindowScene *)[[[UIApplication sharedApplication] connectedScenes] anyObject];
        if (scene) {
            self = [super initWithWindowScene:scene];
        } else {
            self = [super initWithFrame:[UIScreen mainScreen].bounds];
        }
    } else {
        self = [super initWithFrame:[UIScreen mainScreen].bounds];
    }
    if (self) {
        self.frame = [UIScreen mainScreen].bounds;
        self.windowLevel = UIWindowLevelAlert + 1;
        self.backgroundColor = [UIColor clearColor];
        self.rootViewController = [UIViewController new];
        self.rootViewController.view.backgroundColor = [UIColor clearColor];
        self.hidden = NO;
        
        CGFloat size = 50;
        _floatView = [[FloatView alloc] initWithFrame:CGRectMake(self.bounds.size.width - size - 20,
                                                                 self.bounds.size.height * 0.3,
                                                                 size, size)];
        [self.rootViewController.view addSubview:_floatView];
        [self updateBadge];
    }
    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *view = [super hitTest:point withEvent:event];
    if (view == self.rootViewController.view || view == self) {
        if (CGRectContainsPoint(_floatView.frame, point)) {
            return _floatView;
        }
        UIView *cover = [self.rootViewController.view viewWithTag:1001];
        if (cover && CGRectContainsPoint(cover.frame, point)) {
            return cover;
        }
        UIView *panel = [self.rootViewController.view viewWithTag:1002];
        if (panel) {
            CGPoint panelPoint = [self.rootViewController.view convertPoint:point toView:panel];
            if ([panel pointInside:panelPoint withEvent:event]) {
                return [panel hitTest:panelPoint withEvent:event];
            }
        }
        return nil;
    }
    return view;
}

- (void)updateBadge {
    AccountManager *mgr = [AccountManager shared];
    NSInteger total = mgr.accounts.count;
    if (total > 0) {
        NSInteger nextIndex = mgr.currentIndex % total + 1;
        _floatView.badgeLabel.text = [NSString stringWithFormat:@"%ld", (long)nextIndex];
    } else {
        _floatView.badgeLabel.text = @"0";
    }
}

@end