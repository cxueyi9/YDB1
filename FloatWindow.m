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
    // 如果锁定则直接返回，不执行任何操作
    if (mgr.floatLocked) {
        [FloatWindow showToast:@"已锁定，请解除锁定后再操作"];
        return;
    }
    
    NSInteger total = mgr.accounts.count;
    if (total == 0) return;
    
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    
    NSInteger displayIndex = mgr.currentIndex + 1;
    
    if (mgr.needLogRoundStart && displayIndex == 1) {
        [mgr switchToNextRound];
        [mgr recordLogRoundStart];
        mgr.needLogRoundStart = NO;
        [mgr saveToFile];
    }
    
    NSDictionary *acc = mgr.accounts[mgr.currentIndex % total];
    NSString *account = acc[@"account"];
    NSString *password = acc[@"password"];
    
    [mgr recordLogWithIndex:displayIndex total:total account:account];
    [mgr addRoundRecordWithIndex:displayIndex total:total account:account];
    
    NSString *msg = [NSString stringWithFormat:@"%ld/%ld，账号 %@", (long)displayIndex, (long)total, account];
    [FloatWindow showToast:msg];
    
    mgr.currentIndex = (mgr.currentIndex + 1) % total;
    [mgr saveToFile];
    [[FloatWindow shared] updateBadge];
    
    if (mgr.currentIndex == 0) {
        mgr.needLogRoundStart = YES;
        // 自动锁定功能：如果开启了自动锁定，则本轮结束后自动锁定
        if (mgr.autoLock) {
            mgr.floatLocked = YES;
        }
        [mgr saveToFile];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((mgr.pasteDelay + mgr.passwordDelay + 2.0) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [mgr uploadRoundRecordsWithCompletion:^(BOOL success, NSString *errMsg) {
                if (success) {
                    [FloatWindow showToast:@"本轮记录已上传"];
                } else {
                    [FloatWindow showToast:[NSString stringWithFormat:@"上传失败: %@", errMsg]];
                }
            }];
        });
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(mgr.pasteDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [UIPasteboard generalPasteboard].string = account;
        [[UIApplication sharedApplication] sendAction:@selector(paste:) to:nil from:nil forEvent:nil];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(mgr.passwordDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIPasteboard generalPasteboard].string = password;
            [[UIApplication sharedApplication] sendAction:@selector(paste:) to:nil from:nil forEvent:nil];
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
    
    CGFloat panelW = screenBounds.size.width - 40;
    CGFloat panelH = 470;  // 增加高度以容纳新开关
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake((screenBounds.size.width - panelW)/2,
                                                              (screenBounds.size.height - panelH)/2 - 20,
                                                              panelW, panelH)];
    panel.backgroundColor = [UIColor whiteColor];
    panel.layer.cornerRadius = 14;
    panel.tag = 1002;
    [superview addSubview:panel];
    
    // 标题
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 8, panelW-30, 18)];
    titleLabel.text = @"账号与设置";
    titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [panel addSubview:titleLabel];
    
    // 账号列表
    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(15, 28, panelW-30, 55)];
    tv.layer.borderWidth = 0.5;
    tv.layer.borderColor = [UIColor colorWithWhite:0.8 alpha:1].CGColor;
    tv.layer.cornerRadius = 6;
    tv.font = [UIFont systemFontOfSize:12];
    tv.tag = 1003;
    tv.text = [mgr exportAccountsText];
    [panel addSubview:tv];
    
    CGFloat yPos = 90;
    CGFloat leftMargin = 15;
    CGFloat comboWidth = (panelW - 2*leftMargin - 10) / 2;
    CGFloat labelWidth = 60;
    CGFloat tfWidth = comboWidth - labelWidth - 5;
    CGFloat secondColX = leftMargin + comboWidth + 10;
    
    // 第一行：粘贴延时、密码延时
    UILabel *delayLabel = [[UILabel alloc] initWithFrame:CGRectMake(leftMargin, yPos, labelWidth, 20)];
    delayLabel.text = @"粘贴延时";
    delayLabel.font = [UIFont systemFontOfSize:12];
    [panel addSubview:delayLabel];
    UITextField *delayTF = [[UITextField alloc] initWithFrame:CGRectMake(leftMargin + labelWidth + 5, yPos-2, tfWidth, 26)];
    delayTF.borderStyle = UITextBorderStyleRoundedRect;
    delayTF.font = [UIFont systemFontOfSize:13];
    delayTF.keyboardType = UIKeyboardTypeDecimalPad;
    delayTF.text = [NSString stringWithFormat:@"%.1f", mgr.pasteDelay];
    delayTF.tag = 2000;
    [panel addSubview:delayTF];
    
    UILabel *pwdLabel = [[UILabel alloc] initWithFrame:CGRectMake(secondColX, yPos, labelWidth, 20)];
    pwdLabel.text = @"密码延时";
    pwdLabel.font = [UIFont systemFontOfSize:12];
    [panel addSubview:pwdLabel];
    UITextField *pwdDelayTF = [[UITextField alloc] initWithFrame:CGRectMake(secondColX + labelWidth + 5, yPos-2, tfWidth, 26)];
    pwdDelayTF.borderStyle = UITextBorderStyleRoundedRect;
    pwdDelayTF.font = [UIFont systemFontOfSize:13];
    pwdDelayTF.keyboardType = UIKeyboardTypeDecimalPad;
    pwdDelayTF.text = [NSString stringWithFormat:@"%.1f", mgr.passwordDelay];
    pwdDelayTF.tag = 2001;
    [panel addSubview:pwdDelayTF];
    
    yPos += 32;
    
    // 第二行：A轮名、B轮名
    UILabel *roundALabel = [[UILabel alloc] initWithFrame:CGRectMake(leftMargin, yPos, labelWidth, 20)];
    roundALabel.text = @"A轮名";
    roundALabel.font = [UIFont systemFontOfSize:12];
    [panel addSubview:roundALabel];
    UITextField *roundATF = [[UITextField alloc] initWithFrame:CGRectMake(leftMargin + labelWidth + 5, yPos-2, tfWidth, 26)];
    roundATF.borderStyle = UITextBorderStyleRoundedRect;
    roundATF.font = [UIFont systemFontOfSize:13];
    roundATF.text = mgr.roundAName;
    roundATF.tag = 3000;
    [panel addSubview:roundATF];
    
    UILabel *roundBLabel = [[UILabel alloc] initWithFrame:CGRectMake(secondColX, yPos, labelWidth, 20)];
    roundBLabel.text = @"B轮名";
    roundBLabel.font = [UIFont systemFontOfSize:12];
    [panel addSubview:roundBLabel];
    UITextField *roundBTF = [[UITextField alloc] initWithFrame:CGRectMake(secondColX + labelWidth + 5, yPos-2, tfWidth, 26)];
    roundBTF.borderStyle = UITextBorderStyleRoundedRect;
    roundBTF.font = [UIFont systemFontOfSize:13];
    roundBTF.text = mgr.roundBName;
    roundBTF.tag = 3001;
    [panel addSubview:roundBTF];
    
    yPos += 34;
    
    // 第三行：服务器地址
    UILabel *serverLabel = [[UILabel alloc] initWithFrame:CGRectMake(leftMargin, yPos, 70, 20)];
    serverLabel.text = @"服务器地址";
    serverLabel.font = [UIFont systemFontOfSize:12];
    [panel addSubview:serverLabel];
    UITextField *serverTF = [[UITextField alloc] initWithFrame:CGRectMake(leftMargin + 75, yPos-2, panelW - 120, 26)];
    serverTF.borderStyle = UITextBorderStyleRoundedRect;
    serverTF.font = [UIFont systemFontOfSize:12];
    serverTF.text = mgr.serverURL;
    serverTF.tag = 3003;
    [panel addSubview:serverTF];
    
    yPos += 34;
    
    // 第四行：锁定图标 + 跳转到
    UILabel *lockLabel = [[UILabel alloc] initWithFrame:CGRectMake(leftMargin, yPos, 60, 20)];
    lockLabel.text = @"锁定";
    lockLabel.font = [UIFont systemFontOfSize:12];
    [panel addSubview:lockLabel];
    UISwitch *lockSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(leftMargin + 65, yPos-5, 51, 31)];
    lockSwitch.on = mgr.floatLocked;
    lockSwitch.tag = 2002;
    [panel addSubview:lockSwitch];
    
    CGFloat jumpLabelWidth = 45;
    CGFloat jumpBtnWidth = 45;
    CGFloat jumpTfWidth = comboWidth - jumpLabelWidth - jumpBtnWidth - 10;
    UILabel *jumpLabel = [[UILabel alloc] initWithFrame:CGRectMake(secondColX, yPos, jumpLabelWidth, 20)];
    jumpLabel.text = @"跳转到";
    jumpLabel.font = [UIFont systemFontOfSize:12];
    [panel addSubview:jumpLabel];
    UITextField *jumpTF = [[UITextField alloc] initWithFrame:CGRectMake(secondColX + jumpLabelWidth + 5, yPos-2, jumpTfWidth, 26)];
    jumpTF.borderStyle = UITextBorderStyleRoundedRect;
    jumpTF.font = [UIFont systemFontOfSize:13];
    jumpTF.keyboardType = UIKeyboardTypeNumberPad;
    jumpTF.placeholder = @"行号";
    jumpTF.tag = 3002;
    [panel addSubview:jumpTF];
    UIButton *jumpBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    jumpBtn.frame = CGRectMake(secondColX + comboWidth - jumpBtnWidth, yPos-2, jumpBtnWidth, 26);
    [jumpBtn setTitle:@"Go" forState:UIControlStateNormal];
    jumpBtn.titleLabel.font = [UIFont systemFontOfSize:13];
    jumpBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:0.15];
    jumpBtn.layer.cornerRadius = 6;
    [jumpBtn addTarget:self action:@selector(jumpAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:jumpBtn];
    
    yPos += 36;
    
    // 新增行：自动锁定开关
    UILabel *autoLockLabel = [[UILabel alloc] initWithFrame:CGRectMake(leftMargin, yPos, 80, 20)];
    autoLockLabel.text = @"自动锁定";
    autoLockLabel.font = [UIFont systemFontOfSize:12];
    [panel addSubview:autoLockLabel];
    UISwitch *autoLockSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(leftMargin + 85, yPos-5, 51, 31)];
    autoLockSwitch.on = mgr.autoLock;
    autoLockSwitch.tag = 2004;  // 新 tag
    [panel addSubview:autoLockSwitch];
    
    yPos += 36;
    
    // 分隔线
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(15, yPos, panelW-30, 0.5)];
    line.backgroundColor = [UIColor colorWithWhite:0.85 alpha:1];
    [panel addSubview:line];
    yPos += 8;
    
    // 保存 / 取消
    UIButton *cancelBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    cancelBtn.frame = CGRectMake(panelW/2 - 110, yPos, 95, 32);
    [cancelBtn setTitle:@"取消" forState:UIControlStateNormal];
    cancelBtn.titleLabel.font = [UIFont systemFontOfSize:14];
    cancelBtn.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1];
    cancelBtn.layer.cornerRadius = 8;
    [cancelBtn addTarget:self action:@selector(cancelAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:cancelBtn];
    
    UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    saveBtn.frame = CGRectMake(panelW/2 + 15, yPos, 95, 32);
    [saveBtn setTitle:@"保存" forState:UIControlStateNormal];
    saveBtn.titleLabel.font = [UIFont systemFontOfSize:14];
    saveBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:0.9];
    [saveBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    saveBtn.layer.cornerRadius = 8;
    [saveBtn addTarget:self action:@selector(saveAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:saveBtn];
    
    yPos += 40;
    
    // 当前轮次信息
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"HH:mm";
    NSString *startTimeStr = [fmt stringFromDate:mgr.roundStartTime];
    NSString *infoText = [NSString stringWithFormat:@"本次【%@】，启动时间：%@", [mgr currentRoundName], startTimeStr];
    UILabel *infoLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, yPos, panelW-30, 18)];
    infoLabel.text = infoText;
    infoLabel.font = [UIFont boldSystemFontOfSize:13];
    infoLabel.textColor = [UIColor darkGrayColor];
    infoLabel.tag = 4000;
    [panel addSubview:infoLabel];
    yPos += 22;
    
    // 日志按钮 + 补上传
    UIButton *copyLogBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyLogBtn.frame = CGRectMake(15, yPos, 90, 28);
    [copyLogBtn setTitle:@"复制日志" forState:UIControlStateNormal];
    copyLogBtn.titleLabel.font = [UIFont systemFontOfSize:12];
    [copyLogBtn addTarget:self action:@selector(copyLogAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:copyLogBtn];
    
    UIButton *exportClearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    exportClearBtn.frame = CGRectMake(panelW - 285, yPos, 90, 28);
    [exportClearBtn setTitle:@"导出并清空" forState:UIControlStateNormal];
    exportClearBtn.titleLabel.font = [UIFont systemFontOfSize:12];
    [exportClearBtn addTarget:self action:@selector(exportAndClearLogAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:exportClearBtn];
    
    UIButton *uploadStagedBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    uploadStagedBtn.frame = CGRectMake(panelW - 195, yPos, 90, 28);
    [uploadStagedBtn setTitle:@"补上传" forState:UIControlStateNormal];
    uploadStagedBtn.titleLabel.font = [UIFont systemFontOfSize:12];
    uploadStagedBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:0.15];
    uploadStagedBtn.layer.cornerRadius = 6;
    [uploadStagedBtn addTarget:self action:@selector(uploadStagedAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:uploadStagedBtn];
    
    UITapGestureRecognizer *tapOnCover = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cancelAction:)];
    [cover addGestureRecognizer:tapOnCover];
}

- (void)jumpAction:(UIButton *)sender {
    UIView *panel = [self.superview viewWithTag:1002];
    UITextField *jumpTF = (UITextField *)[panel viewWithTag:3002];
    NSInteger targetLine = [jumpTF.text integerValue];
    
    AccountManager *mgr = [AccountManager shared];
    NSInteger total = mgr.accounts.count;
    if (total == 0) {
        [FloatWindow showToast:@"暂无账号"];
        return;
    }
    
    if (targetLine < 1) targetLine = 1;
    if (targetLine > total) targetLine = total;
    
    mgr.currentIndex = targetLine - 1;
    [mgr saveToFile];
    [[FloatWindow shared] updateBadge];
    [FloatWindow showToast:[NSString stringWithFormat:@"已跳转到第 %ld 行", (long)targetLine]];
}

- (void)saveAction:(id)sender {
    UIView *panel = [self.superview viewWithTag:1002];
    UITextView *tv = (UITextView *)[panel viewWithTag:1003];
    
    AccountManager *mgr = [AccountManager shared];
    NSString *newText = tv.text;
    NSString *originalText = [mgr exportAccountsText];
    
    if (![newText isEqualToString:originalText]) {
        [mgr updateAccountsWithText:newText];
    }
    
    UITextField *delayTF = (UITextField *)[panel viewWithTag:2000];
    UITextField *pwdDelayTF = (UITextField *)[panel viewWithTag:2001];
    mgr.pasteDelay = [delayTF.text doubleValue];
    mgr.passwordDelay = [pwdDelayTF.text doubleValue];
    if (mgr.pasteDelay < 0.1) mgr.pasteDelay = 1.0;
    if (mgr.passwordDelay < 0.1) mgr.passwordDelay = 0.5;
    
    UISwitch *lockSwitch = (UISwitch *)[panel viewWithTag:2002];
    mgr.floatLocked = lockSwitch.on;
    
    UISwitch *autoLockSwitch = (UISwitch *)[panel viewWithTag:2004];
    mgr.autoLock = autoLockSwitch.on;
    
    UITextField *roundATF = (UITextField *)[panel viewWithTag:3000];
    UITextField *roundBTF = (UITextField *)[panel viewWithTag:3001];
    if (roundATF.text.length > 0) mgr.roundAName = roundATF.text;
    if (roundBTF.text.length > 0) mgr.roundBName = roundBTF.text;
    
    UITextField *serverTF = (UITextField *)[panel viewWithTag:3003];
    if (serverTF.text.length > 0) mgr.serverURL = serverTF.text;
    
    [mgr saveToFile];
    [[FloatWindow shared] updateBadge];
    [self dismissPanel];
    [FloatWindow showToast:@"设置已保存"];
}

- (void)cancelAction:(id)sender {
    [self dismissPanel];
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

- (void)uploadStagedAction:(id)sender {
    [[AccountManager shared] uploadStagedRecordsWithCompletion:^(BOOL success, NSString *msg) {
        if (success) {
            [FloatWindow showToast:@"补上传成功"];
        } else {
            [FloatWindow showToast:[NSString stringWithFormat:@"补上传失败: %@", msg]];
        }
    }];
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
    NSInteger progress = mgr.currentIndex;
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