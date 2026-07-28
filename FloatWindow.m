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
        badge.font = [UIFont boldSystemFontOfSize:13]; // 缩小字体以适应进度格式
        badge.adjustsFontSizeToFitWidth = YES;
        badge.minimumScaleFactor = 0.5;
        badge.text = @"0/0";
        [self addSubview:badge];
        _badgeLabel = badge;
        
        // 拖拽手势（根据锁定状态决定是否生效）
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
    if ([AccountManager shared].floatLocked) return; // 锁定则禁止拖拽
    
    CGPoint translation = [pan translationInView:self.superview];
    CGPoint newCenter = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    
    CGFloat half = self.bounds.size.width / 2;
    CGFloat margin = 10;
    newCenter.x = MAX(half + margin, MIN(newCenter.x, self.superview.bounds.size.width - half - margin));
    newCenter.y = MAX(half + margin + 20, MIN(newCenter.y, self.superview.bounds.size.height - half - margin - 20));
    
    self.center = newCenter;
    [pan setTranslation:CGPointZero inView:self.superview];
    
    // 拖拽结束时保存当前位置
    if (pan.state == UIGestureRecognizerStateEnded) {
        AccountManager *mgr = [AccountManager shared];
        mgr.floatWindowPoint = self.frame.origin;
        [mgr saveToFile];
    }
}

- (void)handleTap:(UITapGestureRecognizer *)tap {
    if (self.isEditing) return;
    
    AccountManager *mgr = [AccountManager shared];
    NSInteger total = mgr.accounts.count;
    if (total == 0) return;
    
    // currentIndex 表示已填充数量，所以本次填充的是第 currentIndex 条（0-based），显示序号为 currentIndex+1
    NSInteger displayIndex = mgr.currentIndex + 1; // 1-based
    NSDictionary *acc = mgr.accounts[mgr.currentIndex % total];
    NSString *account = acc[@"account"];
    NSString *password = acc[@"password"];
    
    // 记录日志
    [mgr recordLogWithIndex:displayIndex total:total account:account];
    
    // 进度提示（显示当前填充的序号）
    NSString *msg = [NSString stringWithFormat:@"%ld/%ld，账号 %@", (long)displayIndex, (long)total, account];
    [FloatWindow showToast:msg];
    
    // 移动索引（已填充数+1）
    mgr.currentIndex = (mgr.currentIndex + 1) % total;
    [mgr saveToFile];
    [[FloatWindow shared] updateBadge];
    
    // 延时粘贴
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
    CGFloat panelH = 440; // 高度调整
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake((screenBounds.size.width - panelW)/2,
                                                              (screenBounds.size.height - panelH)/2 - 50,
                                                              panelW, panelH)];
    panel.backgroundColor = [UIColor whiteColor];
    panel.layer.cornerRadius = 12;
    panel.tag = 1002;
    [superview addSubview:panel];
    
    AccountManager *mgr = [AccountManager shared];
    int yPos = 10;
    
    // 账号列表编辑
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
    
    // 配置项：粘贴延时，密码延时，锁定图标
    NSArray *labels = @[@"粘贴延时(秒):", @"密码延时(秒):", @"锁定图标:"];
    NSArray *values = @[[NSString stringWithFormat:@"%.1f", mgr.pasteDelay],
                        [NSString stringWithFormat:@"%.1f", mgr.passwordDelay]];
    
    for (int i = 0; i < 2; i++) {
        UILabel *lb = [[UILabel alloc] initWithFrame:CGRectMake(15, yPos, 100, 25)];
        lb.text = labels[i];
        lb.font = [UIFont systemFontOfSize:13];
        [panel addSubview:lb];
        
        UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(120, yPos, panelW-150, 25)];
        tf.borderStyle = UITextBorderStyleRoundedRect;
        tf.font = [UIFont systemFontOfSize:13];
        tf.keyboardType = UIKeyboardTypeDecimalPad;
        tf.text = values[i];
        tf.tag = 2000 + i;
        [panel addSubview:tf];
        yPos += 30;
    }
    
    // 锁定图标开关
    UILabel *lockLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, yPos, 100, 25)];
    lockLabel.text = @"锁定图标:";
    lockLabel.font = [UIFont systemFontOfSize:13];
    [panel addSubview:lockLabel];
    
    UISwitch *lockSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(120, yPos, 51, 31)];
    lockSwitch.on = mgr.floatLocked;
    lockSwitch.tag = 2002;
    [panel addSubview:lockSwitch];
    yPos += 35;
    
    yPos += 5;
    
    // 按钮：保存 / 取消
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
    
    // 功能按钮行1：导入 / 导出账号 / 重置进度
    UIButton *importBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    importBtn.frame = CGRectMake(15, yPos, 90, 35);
    [importBtn setTitle:@"从剪贴板导入" forState:UIControlStateNormal];
    importBtn.titleLabel.font = [UIFont systemFontOfSize:11];
    [importBtn addTarget:self action:@selector(importAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:importBtn];
    
    UIButton *exportBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    exportBtn.frame = CGRectMake(panelW/2 - 45, yPos, 90, 35);
    [exportBtn setTitle:@"导出账号" forState:UIControlStateNormal];
    exportBtn.titleLabel.font = [UIFont systemFontOfSize:11];
    [exportBtn addTarget:self action:@selector(exportAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:exportBtn];
    
    UIButton *resetBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    resetBtn.frame = CGRectMake(panelW - 105, yPos, 90, 35);
    [resetBtn setTitle:@"重置进度" forState:UIControlStateNormal];
    resetBtn.titleLabel.font = [UIFont systemFontOfSize:11];
    [resetBtn addTarget:self action:@selector(resetProgressAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:resetBtn];
    yPos += 40;
    
    // 功能按钮行2：复制日志 / 导出日志并清空
    UIButton *copyLogBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyLogBtn.frame = CGRectMake(15, yPos, 90, 35);
    [copyLogBtn setTitle:@"复制日志" forState:UIControlStateNormal];
    copyLogBtn.titleLabel.font = [UIFont systemFontOfSize:11];
    [copyLogBtn addTarget:self action:@selector(copyLogAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:copyLogBtn];
    
    UIButton *exportClearLogBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    exportClearLogBtn.frame = CGRectMake(panelW - 105, yPos, 90, 35);
    [exportClearLogBtn setTitle:@"导出并清空" forState:UIControlStateNormal];
    exportClearLogBtn.titleLabel.font = [UIFont systemFontOfSize:11];
    [exportClearLogBtn addTarget:self action:@selector(exportAndClearLogAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:exportClearLogBtn];
    
    UITapGestureRecognizer *tapOnCover = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cancelAction:)];
    [cover addGestureRecognizer:tapOnCover];
}

- (void)saveAction:(id)sender {
    UIView *superview = self.superview;
    UIView *panel = [superview viewWithTag:1002];
    UITextView *tv = (UITextView *)[panel viewWithTag:1003];
    
    AccountManager *mgr = [AccountManager shared];
    [mgr updateAccountsWithText:tv.text];
    
    // 读取延时配置
    UITextField *delayTF = (UITextField *)[panel viewWithTag:2000];
    UITextField *pwdDelayTF = (UITextField *)[panel viewWithTag:2001];
    mgr.pasteDelay = [delayTF.text doubleValue];
    mgr.passwordDelay = [pwdDelayTF.text doubleValue];
    if (mgr.pasteDelay < 0.1) mgr.pasteDelay = 1.0;
    if (mgr.passwordDelay < 0.1) mgr.passwordDelay = 0.5;
    
    // 锁定状态
    UISwitch *lockSwitch = (UISwitch *)[panel viewWithTag:2002];
    mgr.floatLocked = lockSwitch.on;
    
    [mgr saveToFile];
    [[FloatWindow shared] updateBadge];
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

- (void)resetProgressAction:(id)sender {
    [[AccountManager shared] resetProgress];
    [[FloatWindow shared] updateBadge];
    [FloatWindow showToast:@"进度已重置"];
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

- (void)exportAndClearLogAction:(id)sender {
    AccountManager *mgr = [AccountManager shared];
    NSString *log = [mgr readLogContent];
    if (log.length == 0) {
        [FloatWindow showToast:@"暂无日志"];
        return;
    }
    [UIPasteboard generalPasteboard].string = log;
    [mgr clearLog];
    [FloatWindow showToast:@"日志已导出并清空"];
}

- (void)dismissPanel {
    UIView *superview = self.superview;
    [[superview viewWithTag:1001] removeFromSuperview];
    [[superview viewWithTag:1002] removeFromSuperview];
    self.isEditing = NO;
}

@end

#pragma mark - FloatWindow 实现

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
    NSInteger progress = mgr.currentIndex; // 已填充数量
    if (total > 0) {
        _floatView.badgeLabel.text = [NSString stringWithFormat:@"%ld/%ld", (long)progress, (long)total];
    } else {
        _floatView.badgeLabel.text = @"0/0";
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