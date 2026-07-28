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
        badge.font = [UIFont boldSystemFontOfSize:13];
        badge.adjustsFontSizeToFitWidth = YES;
        badge.minimumScaleFactor = 0.5;
        badge.text = @"0/0";
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
    if ([AccountManager shared].floatLocked) return;
    
    CGPoint translation = [pan translationInView:self.superview];
    CGPoint newCenter = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    
    CGFloat half = self.bounds.size.width / 2;
    CGFloat margin = 10;
    newCenter.x = MAX(half + margin, MIN(newCenter.x, self.superview.bounds.size.width - half - margin));
    newCenter.y = MAX(half + margin + 20, MIN(newCenter.y, self.superview.bounds.size.height - half - margin - 20));
    
    self.center = newCenter;
    [pan setTranslation:CGPointZero inView:self.superview];
    
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
    
    // 防止屏幕休眠：开始操作
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    
    NSInteger displayIndex = mgr.currentIndex + 1;  // 1-based
    NSDictionary *acc = mgr.accounts[mgr.currentIndex % total];
    NSString *account = acc[@"account"];
    NSString *password = acc[@"password"];
    
    // 如果需要记录轮次开始（新一轮的第一条）
    if (mgr.needLogRoundStart && displayIndex == 1) {
        [mgr recordLogRoundStart];
        mgr.needLogRoundStart = NO;
        [mgr saveToFile];
    }
    
    // 记录填充日志
    [mgr recordLogWithIndex:displayIndex total:total account:account];
    
    NSString *msg = [NSString stringWithFormat:@"%ld/%ld，账号 %@", (long)displayIndex, (long)total, account];
    [FloatWindow showToast:msg];
    
    // 索引递增
    mgr.currentIndex = (mgr.currentIndex + 1) % total;
    [mgr saveToFile];
    [[FloatWindow shared] updateBadge];
    
    // 检查是否完成一轮（currentIndex == 0 表示刚填充完最后一个，下一轮将从0开始）
    if (mgr.currentIndex == 0) {
        [mgr switchToNextRound];   // 切换轮次，设置 needLogRoundStart = YES
    }
    
    // 延时粘贴账号
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(mgr.pasteDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [UIPasteboard generalPasteboard].string = account;
        [[UIApplication sharedApplication] sendAction:@selector(paste:) to:nil from:nil forEvent:nil];
        
        // 延时粘贴密码
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(mgr.passwordDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIPasteboard generalPasteboard].string = password;
            [[UIApplication sharedApplication] sendAction:@selector(paste:) to:nil from:nil forEvent:nil];
            
            // 操作完成，恢复屏幕休眠
            [UIApplication sharedApplication].idleTimerDisabled = NO;
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
    
    AccountManager *mgr = [AccountManager shared];
    
    // 面板尺寸（根据内容自适应高度）
    CGFloat panelW = screenBounds.size.width - 40;
    CGFloat panelH = 420;   // 增加高度以容纳轮次名称和底部信息
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake((screenBounds.size.width - panelW)/2,
                                                              (screenBounds.size.height - panelH)/2 - 30,
                                                              panelW, panelH)];
    panel.backgroundColor = [UIColor whiteColor];
    panel.layer.cornerRadius = 14;
    panel.tag = 1002;
    [superview addSubview:panel];
    
    // 标题
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 12, panelW-30, 20)];
    titleLabel.text = @"账号与设置";
    titleLabel.font = [UIFont boldSystemFontOfSize:15];
    titleLabel.textColor = [UIColor blackColor];
    [panel addSubview:titleLabel];
    
    // 账号输入框
    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(15, 35, panelW-30, 75)];
    tv.layer.borderWidth = 0.5;
    tv.layer.borderColor = [UIColor colorWithWhite:0.8 alpha:1].CGColor;
    tv.layer.cornerRadius = 6;
    tv.font = [UIFont systemFontOfSize:12];
    tv.tag = 1003;
    tv.text = [mgr exportAccountsText];
    [panel addSubview:tv];
    
    CGFloat yPos = 120;
    CGFloat fieldW = (panelW - 50) / 2;   // 两个并排输入框宽度
    
    // 粘贴延时 / 密码延时（一行）
    UILabel *delayLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, yPos, 60, 20)];
    delayLabel.text = @"粘贴延时";
    delayLabel.font = [UIFont systemFontOfSize:12];
    [panel addSubview:delayLabel];
    UITextField *delayTF = [[UITextField alloc] initWithFrame:CGRectMake(75, yPos-2, fieldW-30, 26)];
    delayTF.borderStyle = UITextBorderStyleRoundedRect;
    delayTF.font = [UIFont systemFontOfSize:13];
    delayTF.keyboardType = UIKeyboardTypeDecimalPad;
    delayTF.text = [NSString stringWithFormat:@"%.1f", mgr.pasteDelay];
    delayTF.tag = 2000;
    [panel addSubview:delayTF];
    
    UILabel *pwdLabel = [[UILabel alloc] initWithFrame:CGRectMake(15 + fieldW + 10, yPos, 60, 20)];
    pwdLabel.text = @"密码延时";
    pwdLabel.font = [UIFont systemFontOfSize:12];
    [panel addSubview:pwdLabel];
    UITextField *pwdDelayTF = [[UITextField alloc] initWithFrame:CGRectMake(75 + fieldW + 10, yPos-2, fieldW-30, 26)];
    pwdDelayTF.borderStyle = UITextBorderStyleRoundedRect;
    pwdDelayTF.font = [UIFont systemFontOfSize:13];
    pwdDelayTF.keyboardType = UIKeyboardTypeDecimalPad;
    pwdDelayTF.text = [NSString stringWithFormat:@"%.1f", mgr.passwordDelay];
    pwdDelayTF.tag = 2001;
    [panel addSubview:pwdDelayTF];
    
    yPos += 36;
    
    // 轮次名称（一行两个）
    UILabel *roundALabel = [[UILabel alloc] initWithFrame:CGRectMake(15, yPos, 50, 20)];
    roundALabel.text = @"A轮名";
    roundALabel.font = [UIFont systemFontOfSize:12];
    [panel addSubview:roundALabel];
    UITextField *roundATF = [[UITextField alloc] initWithFrame:CGRectMake(65, yPos-2, fieldW-10, 26)];
    roundATF.borderStyle = UITextBorderStyleRoundedRect;
    roundATF.font = [UIFont systemFontOfSize:13];
    roundATF.text = mgr.roundAName;
    roundATF.tag = 3000;
    [panel addSubview:roundATF];
    
    UILabel *roundBLabel = [[UILabel alloc] initWithFrame:CGRectMake(15 + fieldW + 10, yPos, 50, 20)];
    roundBLabel.text = @"B轮名";
    roundBLabel.font = [UIFont systemFontOfSize:12];
    [panel addSubview:roundBLabel];
    UITextField *roundBTF = [[UITextField alloc] initWithFrame:CGRectMake(65 + fieldW + 10, yPos-2, fieldW-10, 26)];
    roundBTF.borderStyle = UITextBorderStyleRoundedRect;
    roundBTF.font = [UIFont systemFontOfSize:13];
    roundBTF.text = mgr.roundBName;
    roundBTF.tag = 3001;
    [panel addSubview:roundBTF];
    
    yPos += 38;
    
    // 锁定开关 + 重置进度按钮
    UILabel *lockLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, yPos, 60, 20)];
    lockLabel.text = @"锁定图标";
    lockLabel.font = [UIFont systemFontOfSize:12];
    [panel addSubview:lockLabel];
    UISwitch *lockSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(80, yPos-5, 51, 31)];
    lockSwitch.on = mgr.floatLocked;
    lockSwitch.tag = 2002;
    [panel addSubview:lockSwitch];
    
    UIButton *resetBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    resetBtn.frame = CGRectMake(panelW - 100, yPos-2, 85, 28);
    [resetBtn setTitle:@"重置进度" forState:UIControlStateNormal];
    resetBtn.titleLabel.font = [UIFont systemFontOfSize:12];
    resetBtn.backgroundColor = [UIColor colorWithRed:0.9 green:0.3 blue:0.3 alpha:0.1];
    resetBtn.layer.cornerRadius = 6;
    [resetBtn addTarget:self action:@selector(resetProgressAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:resetBtn];
    
    yPos += 36;
    
    // 分隔线
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(15, yPos, panelW-30, 0.5)];
    line.backgroundColor = [UIColor colorWithWhite:0.85 alpha:1];
    [panel addSubview:line];
    yPos += 10;
    
    // 底部按钮：取消 / 保存
    UIButton *cancelBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    cancelBtn.frame = CGRectMake(panelW/2 - 120, yPos, 100, 36);
    [cancelBtn setTitle:@"取消" forState:UIControlStateNormal];
    cancelBtn.titleLabel.font = [UIFont systemFontOfSize:14];
    cancelBtn.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1];
    cancelBtn.layer.cornerRadius = 8;
    [cancelBtn addTarget:self action:@selector(cancelAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:cancelBtn];
    
    UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    saveBtn.frame = CGRectMake(panelW/2 + 20, yPos, 100, 36);
    [saveBtn setTitle:@"保存" forState:UIControlStateNormal];
    saveBtn.titleLabel.font = [UIFont systemFontOfSize:14];
    saveBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:0.9];
    [saveBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    saveBtn.layer.cornerRadius = 8;
    [saveBtn addTarget:self action:@selector(saveAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:saveBtn];
    
    yPos += 44;
    
    // 当前轮次信息（底部标签）
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"HH:mm";
    NSString *startTimeStr = [fmt stringFromDate:mgr.roundStartTime];
    NSString *infoText = [NSString stringWithFormat:@"本次【%@】，启动时间：%@", [mgr currentRoundName], startTimeStr];
    UILabel *infoLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, yPos, panelW-30, 20)];
    infoLabel.text = infoText;
    infoLabel.font = [UIFont systemFontOfSize:11];
    infoLabel.textColor = [UIColor grayColor];
    infoLabel.tag = 4000;   // 方便后续更新
    [panel addSubview:infoLabel];
    yPos += 26;
    
    // 日志按钮（最底部）
    UIButton *copyLogBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyLogBtn.frame = CGRectMake(15, yPos, 90, 30);
    [copyLogBtn setTitle:@"复制日志" forState:UIControlStateNormal];
    copyLogBtn.titleLabel.font = [UIFont systemFontOfSize:12];
    [copyLogBtn addTarget:self action:@selector(copyLogAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:copyLogBtn];
    
    UIButton *exportClearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    exportClearBtn.frame = CGRectMake(panelW - 105, yPos, 90, 30);
    [exportClearBtn setTitle:@"导出并清空" forState:UIControlStateNormal];
    exportClearBtn.titleLabel.font = [UIFont systemFontOfSize:12];
    [exportClearBtn addTarget:self action:@selector(exportAndClearLogAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:exportClearBtn];
    
    UITapGestureRecognizer *tapOnCover = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cancelAction:)];
    [cover addGestureRecognizer:tapOnCover];
}

- (void)saveAction:(id)sender {
    UIView *superview = self.superview;
    UIView *panel = [superview viewWithTag:1002];
    UITextView *tv = (UITextView *)[panel viewWithTag:1003];
    
    AccountManager *mgr = [AccountManager shared];
    NSString *newText = tv.text;
    NSString *originalText = [mgr exportAccountsText];
    
    // 只有账号列表内容变化时才更新列表（内部重置进度和轮次）
    if (![newText isEqualToString:originalText]) {
        [mgr updateAccountsWithText:newText];
    }
    
    // 读取延时
    UITextField *delayTF = (UITextField *)[panel viewWithTag:2000];
    UITextField *pwdDelayTF = (UITextField *)[panel viewWithTag:2001];
    mgr.pasteDelay = [delayTF.text doubleValue];
    mgr.passwordDelay = [pwdDelayTF.text doubleValue];
    if (mgr.pasteDelay < 0.1) mgr.pasteDelay = 1.0;
    if (mgr.passwordDelay < 0.1) mgr.passwordDelay = 0.5;
    
    // 锁定状态
    UISwitch *lockSwitch = (UISwitch *)[panel viewWithTag:2002];
    mgr.floatLocked = lockSwitch.on;
    
    // 轮次名称
    UITextField *roundATF = (UITextField *)[panel viewWithTag:3000];
    UITextField *roundBTF = (UITextField *)[panel viewWithTag:3001];
    if (roundATF.text.length > 0) mgr.roundAName = roundATF.text;
    if (roundBTF.text.length > 0) mgr.roundBName = roundBTF.text;
    
    [mgr saveToFile];
    [[FloatWindow shared] updateBadge];
    [self dismissPanel];
    [FloatWindow showToast:@"设置已保存"];
}

- (void)cancelAction:(id)sender {
    [self dismissPanel];
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