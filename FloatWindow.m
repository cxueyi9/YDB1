#import "FloatWindow.h"
#import "AccountManager.h"

// 类扩展：声明私有方法
@interface FloatWindow ()
- (void)updateFloatViewPosition;
@end

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
        
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        [self addGestureRecognizer:tap];
        
        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
        [self addGestureRecognizer:longPress];
    }
    return self;
}

- (void)handleTap:(UITapGestureRecognizer *)tap {
    if (self.isEditing) return;
    
    AccountManager *mgr = [AccountManager shared];
    NSInteger total = mgr.accounts.count;
    if (total == 0) return;
    
    NSInteger idx = mgr.currentIndex;
    NSDictionary *acc = mgr.accounts[idx % total];
    NSString *account = acc[@"account"];
    NSString *password = acc[@"password"];
    
    [mgr recordLogWithIndex:idx + 1 total:total account:account];
    
    mgr.currentIndex = (idx + 1) % total;
    [mgr saveToFile];
    [[FloatWindow shared] updateBadge];
    
    NSString *msg = [NSString stringWithFormat:@"%ld/%ld，账号 %@", (long)(idx + 1), (long)total, account];
    [FloatWindow showToast:msg];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(mgr.pasteDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [UIPasteboard generalPasteboard].string = account;
        [[UIApplication sharedApplication] sendAction:@selector(paste:) to:nil from:nil forEvent:nil];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(mgr.passwordDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIPasteboard generalPasteboard].string = password;
            [[UIApplication sharedApplication] sendAction:@selector(paste:) to:nil from:nil forEvent:nil];
        });
    });
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)longPress {
    if (longPress.state == UIGestureRecognizerStateBegan) {
        [self showEditPanel];
    }
}

- (void)showEditPanel {
    if (self.isEditing) return;
    self.isEditing = YES;
    
    UIView *superview = self.superview;
    CGRect screenBounds = superview.bounds;
    
    UIView *cover = [[UIView alloc] initWithFrame:screenBounds];
    cover.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];
    cover.tag = 1001;
    [superview addSubview:cover];
    
    CGFloat panelW = screenBounds.size.width - 40;
    CGFloat panelH = 480;
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake((screenBounds.size.width - panelW)/2,
                                                              (screenBounds.size.height - panelH)/2 - 50,
                                                              panelW, panelH)];
    panel.backgroundColor = [UIColor whiteColor];
    panel.layer.cornerRadius = 12;
    panel.tag = 1002;
    [superview addSubview:panel];
    
    AccountManager *mgr = [AccountManager shared];
    int yPos = 10;
    
    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(15, yPos, panelW-30, 20)];
    hint.text = @"账号列表（每行：账号|密码）";
    hint.font = [UIFont systemFontOfSize:13];
    hint.textColor = [UIColor grayColor];
    [panel addSubview:hint];
    yPos += 22;
    
    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(15, yPos, panelW-30, 80)];
    tv.layer.borderWidth = 0.5;
    tv.layer.borderColor = [UIColor lightGrayColor].CGColor;
    tv.font = [UIFont systemFontOfSize:14];
    tv.tag = 1003;
    tv.text = [mgr exportAccountsText];
    [panel addSubview:tv];
    yPos += 90;
    
    NSArray *labels = @[@"浮窗 X:", @"浮窗 Y:", @"粘贴延时(秒):", @"密码延时(秒):"];
    NSArray *values = @[[NSString stringWithFormat:@"%.0f", mgr.floatWindowPoint.x],
                        [NSString stringWithFormat:@"%.0f", mgr.floatWindowPoint.y],
                        [NSString stringWithFormat:@"%.1f", mgr.pasteDelay],
                        [NSString stringWithFormat:@"%.1f", mgr.passwordDelay]];
    
    for (int i = 0; i < labels.count; i++) {
        UILabel *lb = [[UILabel alloc] initWithFrame:CGRectMake(15, yPos, 100, 25)];
        lb.text = labels[i];
        lb.font = [UIFont systemFontOfSize:13];
        [panel addSubview:lb];
        
        UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(120, yPos, panelW-150, 25)];
        tf.borderStyle = UITextBorderStyleRoundedRect;
        tf.font = [UIFont systemFontOfSize:13];
        tf.keyboardType = (i >= 2) ? UIKeyboardTypeDecimalPad : UIKeyboardTypeNumberPad;
        tf.text = values[i];
        tf.tag = 2000 + i;
        [panel addSubview:tf];
        yPos += 30;
    }
    yPos += 10;
    
    UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    saveBtn.frame = CGRectMake(panelW/2 + 20, yPos, 80, 35);
    [saveBtn setTitle:@"保存" forState:UIControlStateNormal];
    [saveBtn addTarget:self action:@selector(saveAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:saveBtn];
    
    UIButton *cancelBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    cancelBtn.frame = CGRectMake(panelW/2 - 100, yPos, 80, 35);
    [cancelBtn setTitle:@"取消" forState:UIControlStateNormal];
    [cancelBtn addTarget:self action:@selector(cancelAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:cancelBtn];
    yPos += 40;
    
    UIButton *importBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    importBtn.frame = CGRectMake(15, yPos, 100, 35);
    [importBtn setTitle:@"从剪贴板导入" forState:UIControlStateNormal];
    importBtn.titleLabel.font = [UIFont systemFontOfSize:12];
    [importBtn addTarget:self action:@selector(importAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:importBtn];
    
    UIButton *exportBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    exportBtn.frame = CGRectMake(panelW - 215, yPos, 100, 35);
    [exportBtn setTitle:@"导出账号" forState:UIControlStateNormal];
    exportBtn.titleLabel.font = [UIFont systemFontOfSize:12];
    [exportBtn addTarget:self action:@selector(exportAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:exportBtn];
    
    UIButton *logBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    logBtn.frame = CGRectMake(panelW - 115, yPos, 100, 35);
    [logBtn setTitle:@"复制日志" forState:UIControlStateNormal];
    logBtn.titleLabel.font = [UIFont systemFontOfSize:12];
    [logBtn addTarget:self action:@selector(copyLogAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:logBtn];
    
    UITapGestureRecognizer *tapOnCover = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cancelAction:)];
    [cover addGestureRecognizer:tapOnCover];
}

- (void)saveAction:(id)sender {
    UIView *superview = self.superview;
    UIView *panel = [superview viewWithTag:1002];
    UITextView *tv = (UITextView *)[panel viewWithTag:1003];
    
    AccountManager *mgr = [AccountManager shared];
    [mgr updateAccountsWithText:tv.text];
    
    NSArray *tags = @[@2000, @2001, @2002, @2003];
    NSMutableArray *vals = [NSMutableArray array];
    for (NSNumber *tag in tags) {
        UITextField *tf = (UITextField *)[panel viewWithTag:tag.integerValue];
        [vals addObject:tf.text ?: @""];
    }
    mgr.floatWindowPoint = CGPointMake([vals[0] floatValue], [vals[1] floatValue]);
    mgr.pasteDelay = [vals[2] doubleValue];
    mgr.passwordDelay = [vals[3] doubleValue];
    if (mgr.pasteDelay < 0.1) mgr.pasteDelay = 1.0;
    if (mgr.passwordDelay < 0.1) mgr.passwordDelay = 0.5;
    [mgr saveToFile];
    
    FloatWindow *fw = [FloatWindow shared];
    [fw updateFloatViewPosition];
    [fw updateBadge];
    
    [self dismissPanel];
    [FloatWindow showToast:@"配置已保存"];
}

- (void)cancelAction:(id)sender {
    [self dismissPanel];
}

- (void)importAction:(id)sender {
    [[AccountManager shared] importFromClipboard];
    UIView *superview = self.superview;
    UIView *panel = [superview viewWithTag:1002];
    UITextView *tv = (UITextView *)[panel viewWithTag:1003];
    tv.text = [[AccountManager shared] exportAccountsText];
    [[FloatWindow shared] updateBadge];
    [FloatWindow showToast:@"已导入"];
}

- (void)exportAction:(id)sender {
    [[AccountManager shared] exportToClipboard];
    [FloatWindow showToast:@"账号已复制到剪贴板"];
}

- (void)copyLogAction:(id)sender {
    NSString *log = [[AccountManager shared] readLogContent];
    if (log.length == 0) {
        [FloatWindow showToast:@"暂无日志"];
    } else {
        [UIPasteboard generalPasteboard].string = log;
        [FloatWindow showToast:@"日志已复制到剪贴板"];
    }
}

- (void)dismissPanel {
    UIView *superview = self.superview;
    [[superview viewWithTag:1001] removeFromSuperview];
    [[superview viewWithTag:1002] removeFromSuperview];
    self.isEditing = NO;
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
        AccountManager *mgr = [AccountManager shared];
        _floatView = [[FloatView alloc] initWithFrame:CGRectMake(mgr.floatWindowPoint.x,
                                                                 mgr.floatWindowPoint.y,
                                                                 size, size)];
        [self.rootViewController.view addSubview:_floatView];
        [self updateBadge];
    }
    return self;
}

- (void)updateFloatViewPosition {
    AccountManager *mgr = [AccountManager shared];
    CGRect f = _floatView.frame;
    f.origin = mgr.floatWindowPoint;
    _floatView.frame = f;
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

+ (void)showToast:(NSString *)message {
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) return;
    
    UILabel *toast = [[UILabel alloc] init];
    toast.text = message;
    toast.textColor = [UIColor whiteColor];
    toast.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.font = [UIFont systemFontOfSize:15];
    toast.layer.cornerRadius = 8;
    toast.clipsToBounds = YES;
    
    CGSize size = [message sizeWithAttributes:@{NSFontAttributeName: toast.font}];
    CGFloat w = size.width + 20;
    CGFloat h = size.height + 12;
    toast.frame = CGRectMake((keyWindow.bounds.size.width - w)/2, keyWindow.bounds.size.height - 120, w, h);
    [keyWindow addSubview:toast];
    
    [UIView animateWithDuration:0.3 delay:1.5 options:0 animations:^{
        toast.alpha = 0;
    } completion:^(BOOL finished) {
        [toast removeFromSuperview];
    }];
}

@end