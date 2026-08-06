#import "FloatWindow.h"
#import "AccountManager.h"
#import "LocationFaker.h"

@interface FloatView : UIView
@property (nonatomic, weak) UILabel *roundLabel;
@property (nonatomic, weak) UILabel *badgeLabel;
@property (nonatomic, assign) BOOL isEditing;
@end

@implementation FloatView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:0.9];
        self.layer.cornerRadius = frame.size.width / 2;
        self.clipsToBounds = YES;
        
        UILabel *rLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 4, frame.size.width, 14)];
        rLabel.textAlignment = NSTextAlignmentCenter;
        rLabel.textColor = [UIColor whiteColor];
        rLabel.font = [UIFont systemFontOfSize:10];
        rLabel.text = @"";
        [self addSubview:rLabel];
        _roundLabel = rLabel;
        
        UILabel *badge = [[UILabel alloc] initWithFrame:CGRectMake(0, 18, frame.size.width, 28)];
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
    if (self.isEditing || [AccountManager shared].floatLocked) return;
    CGPoint translation = [pan translationInView:self.superview];
    CGPoint newCenter = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    CGFloat half = self.bounds.size.width / 2, margin = 10;
    newCenter.x = MAX(half + margin, MIN(newCenter.x, self.superview.bounds.size.width - half - margin));
    newCenter.y = MAX(half + margin + 20, MIN(newCenter.y, self.superview.bounds.size.height - half - margin - 20));
    self.center = newCenter;
    [pan setTranslation:CGPointZero inView:self.superview];
    if (pan.state == UIGestureRecognizerStateEnded) {
        [AccountManager shared].floatWindowPoint = self.frame.origin;
        [[AccountManager shared] saveToFile];
    }
}

- (void)handleTap:(UITapGestureRecognizer *)tap {
    if (self.isEditing) return;
    AccountManager *mgr = [AccountManager shared];
    if (mgr.tapLocked) {
        [FloatWindow showToast:@"点击已锁定"];
        return;
    }

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (mgr.clickCooldown > 0 && (now - mgr.lastClickTime) < mgr.clickCooldown) {
        NSTimeInterval remaining = mgr.clickCooldown - (now - mgr.lastClickTime);
        [FloatWindow showToast:[NSString stringWithFormat:@"请 %.0f 秒后再点", remaining]];
        return;
    }
    mgr.lastClickTime = now;
    [mgr saveToFile];

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
    NSString *account = acc[@"account"], *password = acc[@"password"];
    mgr.currentAccount = account;
    [mgr recordLogWithIndex:displayIndex total:total account:account];
    [mgr addRoundRecordWithIndex:displayIndex total:total account:account];
    
    [FloatWindow showToast:[NSString stringWithFormat:@"%ld/%ld，账号 %@", (long)displayIndex, (long)total, account]];
    
    mgr.currentIndex = (mgr.currentIndex + 1) % total;
    [mgr saveToFile];
    [[FloatWindow shared] updateBadge];
    
    if (mgr.currentIndex == 0) {
        [mgr finishRound];
        mgr.needLogRoundStart = YES;
        if (mgr.autoLock) mgr.tapLocked = YES;
        [mgr saveToFile];
        [[FloatWindow shared] updateBadge];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((mgr.pasteDelay + mgr.passwordDelay + 2.0) * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [mgr uploadRoundRecordsWithCompletion:^(BOOL success, NSString *msg) {
                [FloatWindow showToast: success ? @"本轮记录已上传" : [NSString stringWithFormat:@"上传失败: %@", msg]];
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

// 辅助方法
- (void)addLabel:(NSString *)text frameX:(CGFloat)x y:(CGFloat)y w:(CGFloat)w toPanel:(UIView *)panel {
    UILabel *lb = [[UILabel alloc] initWithFrame:CGRectMake(x, y, w, 20)];
    lb.text = text; lb.font = [UIFont systemFontOfSize:12];
    [panel addSubview:lb];
}
- (void)addTextField:(NSInteger)tag value:(NSString *)value frameX:(CGFloat)x y:(CGFloat)y w:(CGFloat)w toPanel:(UIView *)panel {
    UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(x, y, w, 26)];
    tf.borderStyle = UITextBorderStyleRoundedRect; tf.font = [UIFont systemFontOfSize:13];
    tf.text = value; tf.tag = tag;
    if (tag == 2000 || tag == 2001) tf.keyboardType = UIKeyboardTypeDecimalPad;
    else if (tag == 3002 || tag == 2006) tf.keyboardType = UIKeyboardTypeNumberPad;
    [panel addSubview:tf];
}
- (void)addSwitch:(NSInteger)tag on:(BOOL)on frameX:(CGFloat)x y:(CGFloat)y toPanel:(UIView *)panel {
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(x, y, 51, 31)];
    sw.on = on; sw.tag = tag; [panel addSubview:sw];
}

- (void)showEditPanel {
    if (self.isEditing) return;
    self.isEditing = YES;
    
    UIView *superview = self.superview;
    CGRect screenBounds = superview.bounds;
    UIView *cover = [[UIView alloc] initWithFrame:screenBounds];
    cover.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4]; cover.tag = 1001;
    [superview addSubview:cover];
    
    AccountManager *mgr = [AccountManager shared];
    CGFloat panelW = screenBounds.size.width - 40;
    CGFloat panelH = 580;
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake((screenBounds.size.width - panelW)/2,
                                                              (screenBounds.size.height - panelH)/2 - 20,
                                                              panelW, panelH)];
    panel.backgroundColor = [UIColor whiteColor];
    panel.layer.cornerRadius = 14;
    panel.tag = 1002;
    [superview addSubview:panel];
    
    // 标题
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(15, 8, panelW-30, 18)];
    title.text = @"账号与设置"; title.font = [UIFont boldSystemFontOfSize:15];
    [panel addSubview:title];
    
    // 账号列表
    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(15, 28, panelW-30, 120)];
    tv.layer.borderWidth = 0.5; tv.layer.borderColor = [UIColor colorWithWhite:0.8 alpha:1].CGColor;
    tv.layer.cornerRadius = 6; tv.font = [UIFont systemFontOfSize:13];
    tv.tag = 1003; tv.text = [mgr exportAccountsText];
    [panel addSubview:tv];
    
    CGFloat yPos = 28 + 120 + 8;
    CGFloat leftMargin = 15;
    CGFloat comboWidth = (panelW - 2*leftMargin - 10) / 2;
    CGFloat labelWidth = 60, tfWidth = comboWidth - labelWidth - 5;
    CGFloat secondColX = leftMargin + comboWidth + 10;
    
    // 粘贴延时 / 密码延时
    [self addLabel:@"粘贴延时" frameX:leftMargin y:yPos w:labelWidth toPanel:panel];
    [self addTextField:2000 value:[NSString stringWithFormat:@"%.1f", mgr.pasteDelay] frameX:leftMargin+labelWidth+5 y:yPos-2 w:tfWidth toPanel:panel];
    [self addLabel:@"密码延时" frameX:secondColX y:yPos w:labelWidth toPanel:panel];
    [self addTextField:2001 value:[NSString stringWithFormat:@"%.1f", mgr.passwordDelay] frameX:secondColX+labelWidth+5 y:yPos-2 w:tfWidth toPanel:panel];
    yPos += 32;
    
    // 点击冷却
    [self addLabel:@"点击冷却" frameX:leftMargin y:yPos w:labelWidth toPanel:panel];
    [self addTextField:2006 value:[NSString stringWithFormat:@"%.0f", mgr.clickCooldown] frameX:leftMargin+labelWidth+5 y:yPos-2 w:tfWidth toPanel:panel];
    UILabel *hintLabel = [[UILabel alloc] initWithFrame:CGRectMake(secondColX, yPos, comboWidth, 20)];
    hintLabel.text = @"秒，0为关闭"; hintLabel.font = [UIFont systemFontOfSize:11]; hintLabel.textColor = [UIColor grayColor];
    [panel addSubview:hintLabel];
    yPos += 32;
    
    // A轮名 / B轮名
    [self addLabel:@"A轮名" frameX:leftMargin y:yPos w:labelWidth toPanel:panel];
    [self addTextField:3000 value:mgr.roundAName frameX:leftMargin+labelWidth+5 y:yPos-2 w:tfWidth toPanel:panel];
    [self addLabel:@"B轮名" frameX:secondColX y:yPos w:labelWidth toPanel:panel];
    [self addTextField:3001 value:mgr.roundBName frameX:secondColX+labelWidth+5 y:yPos-2 w:tfWidth toPanel:panel];
    yPos += 34;
    
    // 服务器地址
    [self addLabel:@"服务器地址" frameX:leftMargin y:yPos w:70 toPanel:panel];
    [self addTextField:3003 value:mgr.serverURL frameX:leftMargin+75 y:yPos-2 w:panelW-120 toPanel:panel];
    yPos += 34;
    
    // 锁定图标 / 锁定点击
    [self addLabel:@"锁定图标" frameX:leftMargin y:yPos w:65 toPanel:panel];
    [self addSwitch:2002 on:mgr.floatLocked frameX:leftMargin+70 y:yPos-5 toPanel:panel];
    [self addLabel:@"锁定点击" frameX:secondColX y:yPos w:65 toPanel:panel];
    [self addSwitch:2005 on:mgr.tapLocked frameX:secondColX+70 y:yPos-5 toPanel:panel];
    yPos += 36;
    
    // 自动锁定 / 跳转到
    [self addLabel:@"自动锁定" frameX:leftMargin y:yPos w:80 toPanel:panel];
    [self addSwitch:2004 on:mgr.autoLock frameX:leftMargin+85 y:yPos-5 toPanel:panel];
    UILabel *jumpLabel = [[UILabel alloc] initWithFrame:CGRectMake(secondColX, yPos, 45, 20)];
    jumpLabel.text = @"跳转到"; jumpLabel.font = [UIFont systemFontOfSize:12];
    [panel addSubview:jumpLabel];
    UITextField *jumpTF = [[UITextField alloc] initWithFrame:CGRectMake(secondColX+50, yPos-2, comboWidth-95, 26)];
    jumpTF.borderStyle = UITextBorderStyleRoundedRect; jumpTF.font = [UIFont systemFontOfSize:13];
    jumpTF.keyboardType = UIKeyboardTypeNumberPad; jumpTF.placeholder = @"行号"; jumpTF.tag = 3002;
    [panel addSubview:jumpTF];
    UIButton *goBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    goBtn.frame = CGRectMake(secondColX+comboWidth-45, yPos-2, 45, 26);
    [goBtn setTitle:@"Go" forState:UIControlStateNormal]; goBtn.titleLabel.font = [UIFont systemFontOfSize:13];
    goBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:0.15];
    goBtn.layer.cornerRadius = 6;
    [goBtn addTarget:self action:@selector(jumpAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:goBtn];
    yPos += 36;
    
    // 虚拟定位区域
    UIView *locLine = [[UIView alloc] initWithFrame:CGRectMake(leftMargin, yPos, panelW-30, 0.5)];
    locLine.backgroundColor = [UIColor colorWithWhite:0.85 alpha:1]; [panel addSubview:locLine];
    yPos += 8;
    
    UILabel *locTitle = [[UILabel alloc] initWithFrame:CGRectMake(leftMargin, yPos, 100, 20)];
    locTitle.text = @"虚拟定位"; locTitle.font = [UIFont boldSystemFontOfSize:13];
    [panel addSubview:locTitle];
    yPos += 22;
    
    [self addLabel:@"启用" frameX:leftMargin y:yPos w:50 toPanel:panel];
    UISwitch *locSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(leftMargin+55, yPos-5, 51, 31)];
    locSwitch.on = [LocationFaker isEnabled]; locSwitch.tag = 3004;
    [panel addSubview:locSwitch];
    yPos += 30;
    
    UILabel *currentLocLabel = [[UILabel alloc] initWithFrame:CGRectMake(leftMargin, yPos, panelW-30, 20)];
    CLLocationCoordinate2D curLoc = [LocationFaker currentCoordinate];
    currentLocLabel.text = [NSString stringWithFormat:@"当前: %@", [LocationFaker currentName]];
    currentLocLabel.font = [UIFont systemFontOfSize:11]; currentLocLabel.textColor = [UIColor darkGrayColor];
    [panel addSubview:currentLocLabel];
    yPos += 22;
    
    UIButton *manageLocBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    manageLocBtn.frame = CGRectMake(leftMargin, yPos, 80, 28);
    [manageLocBtn setTitle:@"管理收藏" forState:UIControlStateNormal];
    [manageLocBtn addTarget:self action:@selector(openLocationFavorites) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:manageLocBtn];
    yPos += 32;
    
    // 详细日志
    [self addLabel:@"详细日志" frameX:leftMargin y:yPos w:70 toPanel:panel];
    UISwitch *detailLogSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(leftMargin+75, yPos-5, 51, 31)];
    detailLogSwitch.on = mgr.detailedLog; detailLogSwitch.tag = 3005;
    [panel addSubview:detailLogSwitch];
    yPos += 32;
    
    // 分隔线
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(15, yPos, panelW-30, 0.5)];
    line.backgroundColor = [UIColor colorWithWhite:0.85 alpha:1]; [panel addSubview:line];
    yPos += 8;
    
    // 保存/取消
    UIButton *cancelBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    cancelBtn.frame = CGRectMake(panelW/2-110, yPos, 95, 32);
    [cancelBtn setTitle:@"取消" forState:UIControlStateNormal]; cancelBtn.titleLabel.font = [UIFont systemFontOfSize:14];
    cancelBtn.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1]; cancelBtn.layer.cornerRadius = 8;
    [cancelBtn addTarget:self action:@selector(cancelAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:cancelBtn];
    
    UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    saveBtn.frame = CGRectMake(panelW/2+15, yPos, 95, 32);
    [saveBtn setTitle:@"保存" forState:UIControlStateNormal]; saveBtn.titleLabel.font = [UIFont systemFontOfSize:14];
    saveBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:0.9];
    [saveBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal]; saveBtn.layer.cornerRadius = 8;
    [saveBtn addTarget:self action:@selector(saveAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:saveBtn];
    yPos += 40;
    
    // 轮次信息
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init]; fmt.dateFormat = @"HH:mm";
    BOOL isFinished = (mgr.currentIndex == 0 && mgr.accounts.count > 0 && mgr.roundEndTime != nil);
    NSString *status = isFinished ? @"已完成" : @"进行中";
    NSString *info = [NSString stringWithFormat:@"【%@】%@，启动：%@", [mgr currentRoundName], status, [fmt stringFromDate:mgr.roundStartTime]];
    if (isFinished && mgr.roundEndTime) info = [info stringByAppendingFormat:@"，结束：%@", [fmt stringFromDate:mgr.roundEndTime]];
    UILabel *infoLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, yPos, panelW-30, 18)];
    infoLabel.text = info; infoLabel.font = [UIFont boldSystemFontOfSize:13]; infoLabel.textColor = [UIColor darkGrayColor]; infoLabel.tag = 4000;
    [panel addSubview:infoLabel];
    yPos += 22;
    
    // 底部按钮
    UIButton *copyLogBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyLogBtn.frame = CGRectMake(15, yPos, 80, 28);
    [copyLogBtn setTitle:@"复制日志" forState:UIControlStateNormal]; copyLogBtn.titleLabel.font = [UIFont systemFontOfSize:12];
    [copyLogBtn addTarget:self action:@selector(copyLogAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:copyLogBtn];
    
    UIButton *exportClearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    exportClearBtn.frame = CGRectMake(panelW/2 - 40, yPos, 80, 28);
    [exportClearBtn setTitle:@"导出并清空" forState:UIControlStateNormal]; exportClearBtn.titleLabel.font = [UIFont systemFontOfSize:12];
    [exportClearBtn addTarget:self action:@selector(exportAndClearLogAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:exportClearBtn];
    
    UIButton *uploadBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    uploadBtn.frame = CGRectMake(panelW - 95, yPos, 80, 28);
    [uploadBtn setTitle:@"补上传" forState:UIControlStateNormal]; uploadBtn.titleLabel.font = [UIFont systemFontOfSize:12];
    uploadBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:0.15]; uploadBtn.layer.cornerRadius = 6;
    [uploadBtn addTarget:self action:@selector(uploadStagedAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:uploadBtn];
    
    UITapGestureRecognizer *tapCover = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cancelAction:)];
    [cover addGestureRecognizer:tapCover];
}

// 使用独立窗口展示收藏页面，避免 present 限制
static UIWindow *locationWindow = nil;
- (void)openLocationFavorites {
    UIViewController *vc = [LocationFaker favoritesViewController];
    if (!vc) return;
    
    // 创建新窗口
    UIWindow *window;
    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = (UIWindowScene *)[[[UIApplication sharedApplication] connectedScenes] anyObject];
        if (scene) {
            window = [[UIWindow alloc] initWithWindowScene:scene];
        } else {
            window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        }
    } else {
        window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    }
    window.windowLevel = UIWindowLevelAlert + 2;
    window.backgroundColor = [UIColor clearColor];
    window.rootViewController = vc;
    window.hidden = NO;
    locationWindow = window;
    
    // 监听关闭通知或手动关闭（在收藏 VC 的 dismiss 方法中处理）
    // 这里简单处理：在 favoritesViewController 内部关闭时设置一个回调，我们通过 NSNotification 或者直接设置一个 dismissBlock
    // 因为 LocationFavoritesVC 已经是 UINavigationController，其 leftBarButtonItem 是 Done，
    // 我们在 Done 按钮的 dismiss 方法中已调用 dismissViewControllerAnimated，但现在是独立窗口，
    // 我们需要在 dismiss 时隐藏并销毁窗口。
    // 修改 LocationFaker 中的 favoritesViewController 返回的 VC，添加一个关闭回调。
    // 为简化，我们在 FloatWindow 中监听该窗口隐藏？更好的做法是修改 LocationFaker 的 favoritesViewController 提供一个 dismissBlock。
    // 此处我们给 navigationController 的 rootViewController 设置一个 dismissBlock，但 LocationFaker 返回的是 UINavigationController，
    // 无法直接设，我们可以在 FloatWindow 中使用 associated object 或 KVO。
    // 为快速解决，我们直接在 openLocationFavorites 中给 navigationController 的 rootViewController 设置 dismissBlock。
    // 假设 vc 是 UINavigationController，其 rootViewController 是 LocationFavoritesVC，我们强制类型转换并设置 block。
    if ([vc isKindOfClass:[UINavigationController class]]) {
        UINavigationController *nav = (UINavigationController *)vc;
        UIViewController *rootVC = nav.viewControllers.firstObject;
        if ([rootVC respondsToSelector:@selector(setDismissBlock:)]) {
            // LocationFavoritesVC 需要添加 dismissBlock 属性，为简化，我们使用通知或直接修改 LocationFavoritesVC 的 dismiss 方法。
            // 我们可以用 runtime 添加一个 block 属性，但更简单的是，在 LocationFavoritesVC 中，当点击 Done 时，除了 dismiss 自身，还发送一个通知。
            // 我们修改 LocationFaker.m 中的 LocationFavoritesVC 的 dismiss 方法，增加发送通知。
            // 这里先假定我们已经修改了 LocationFavoritesVC，在 dismiss 时发送 @"LocationFavoritesDismissed" 通知。
            // 然后在此处监听该通知，收到后隐藏并置空 locationWindow。
            [[NSNotificationCenter defaultCenter] addObserverForName:@"LocationFavoritesDismissed"
                                                              object:nil
                                                               queue:[NSOperationQueue mainQueue]
                                                          usingBlock:^(NSNotification *note) {
                locationWindow.hidden = YES;
                locationWindow = nil;
                [[NSNotificationCenter defaultCenter] removeObserver:self name:@"LocationFavoritesDismissed" object:nil];
            }];
        } else {
            // 如果没有 dismissBlock，我们无法可靠地关闭窗口，但可以设置一个延时检测？或者强制在 LocationFavoritesVC 中处理。
            // 我们马上修改 LocationFaker.m，让 LocationFavoritesVC 的 dismiss 方法发送通知，并确保窗口关闭。
        }
    }
}

- (void)jumpAction:(UIButton *)sender {
    UIView *panel = [self.superview viewWithTag:1002];
    UITextField *jumpTF = (UITextField *)[panel viewWithTag:3002];
    NSInteger targetLine = [jumpTF.text integerValue];
    AccountManager *mgr = [AccountManager shared];
    NSInteger total = mgr.accounts.count;
    if (total == 0) { [FloatWindow showToast:@"暂无账号"]; return; }
    
    if (targetLine < 1) targetLine = 1;
    if (targetLine > total) targetLine = total;
    
    if (targetLine == total) {
        mgr.currentIndex = 0;
        mgr.roundEndTime = [NSDate date];
        mgr.needLogRoundStart = YES;
    } else {
        mgr.currentIndex = targetLine;
        mgr.roundEndTime = nil;
        mgr.needLogRoundStart = NO;
    }
    [mgr saveToFile];
    [[FloatWindow shared] updateBadge];
    [FloatWindow showToast:[NSString stringWithFormat:@"已跳转到第 %ld 行", (long)targetLine]];
}

- (void)saveAction:(id)sender {
    UIView *panel = [self.superview viewWithTag:1002];
    UITextView *tv = (UITextView *)[panel viewWithTag:1003];
    AccountManager *mgr = [AccountManager shared];
    NSString *newText = tv.text;
    if (![newText isEqualToString:[mgr exportAccountsText]]) [mgr updateAccountsWithText:newText];
    
    mgr.pasteDelay = [[(UITextField *)[panel viewWithTag:2000] text] doubleValue];
    mgr.passwordDelay = [[(UITextField *)[panel viewWithTag:2001] text] doubleValue];
    mgr.clickCooldown = [[(UITextField *)[panel viewWithTag:2006] text] doubleValue];
    if (mgr.pasteDelay < 0.1) mgr.pasteDelay = 1.0;
    if (mgr.passwordDelay < 0.1) mgr.passwordDelay = 0.5;
    if (mgr.clickCooldown < 0) mgr.clickCooldown = 0;
    mgr.lastClickTime = 0;
    
    mgr.floatLocked = ((UISwitch *)[panel viewWithTag:2002]).on;
    mgr.tapLocked = ((UISwitch *)[panel viewWithTag:2005]).on;
    mgr.autoLock = ((UISwitch *)[panel viewWithTag:2004]).on;
    mgr.detailedLog = ((UISwitch *)[panel viewWithTag:3005]).on;
    
    BOOL locEnabled = ((UISwitch *)[panel viewWithTag:3004]).on;
    [LocationFaker setEnabled:locEnabled];
    
    UITextField *rATF = (UITextField *)[panel viewWithTag:3000];
    if (rATF.text.length > 0) mgr.roundAName = rATF.text;
    UITextField *rBTF = (UITextField *)[panel viewWithTag:3001];
    if (rBTF.text.length > 0) mgr.roundBName = rBTF.text;
    mgr.serverURL = [(UITextField *)[panel viewWithTag:3003] text] ?: mgr.serverURL;
    [mgr saveToFile];
    [[FloatWindow shared] updateBadge];
    [self dismissPanel];
    [FloatWindow showToast:@"设置已保存"];
}

- (void)cancelAction:(id)sender { [self dismissPanel]; }

- (void)copyLogAction:(id)sender {
    NSString *log = [[AccountManager shared] readLogContent];
    if (log.length == 0) [FloatWindow showToast:@"暂无日志"];
    else {
        [UIPasteboard generalPasteboard].string = log;
        [FloatWindow showToast:@"日志已复制"];
    }
}

- (void)exportAndClearLogAction:(id)sender {
    AccountManager *mgr = [AccountManager shared];
    NSString *log = [mgr readLogContent];
    if (log.length == 0) { [FloatWindow showToast:@"暂无日志"]; return; }
    [UIPasteboard generalPasteboard].string = log;
    [mgr clearLog];
    [FloatWindow showToast:@"日志已导出并清空"];
}

- (void)uploadStagedAction:(UIButton *)sender {
    sender.enabled = NO;
    [sender setTitle:@"上传中…" forState:UIControlStateNormal];
    [[AccountManager shared] uploadStagedRecordsWithCompletion:^(BOOL success, NSString *msg) {
        sender.enabled = YES;
        [sender setTitle:@"补上传" forState:UIControlStateNormal];
        [FloatWindow showToast: success ? @"补上传成功" : [NSString stringWithFormat:@"失败: %@", msg]];
    }];
}

- (void)dismissPanel {
    UIView *superview = self.superview;
    [[superview viewWithTag:1001] removeFromSuperview];
    [[superview viewWithTag:1002] removeFromSuperview];
    self.isEditing = NO;
}

@end

#pragma mark - FloatWindow 主实现

@implementation FloatWindow {
    FloatView *_floatView;
}

+ (instancetype)shared {
    static FloatWindow *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [[FloatWindow alloc] init]; });
    return instance;
}

- (instancetype)init {
    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = (UIWindowScene *)[[[UIApplication sharedApplication] connectedScenes] anyObject];
        self = scene ? [super initWithWindowScene:scene] : [super initWithFrame:[UIScreen mainScreen].bounds];
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
        AccountManager *mgr = [AccountManager shared];
        _floatView = [[FloatView alloc] initWithFrame:CGRectMake(mgr.floatWindowPoint.x, mgr.floatWindowPoint.y, 50, 50)];
        [self.rootViewController.view addSubview:_floatView];
        [self updateBadge];

        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            [self updateBadge];
        }];

        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            [[AccountManager shared] saveToFile];
        }];
    }
    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *view = [super hitTest:point withEvent:event];
    if (view == self.rootViewController.view || view == self) {
        if (CGRectContainsPoint(_floatView.frame, point)) return _floatView;
        UIView *cover = [self.rootViewController.view viewWithTag:1001];
        if (cover && CGRectContainsPoint(cover.frame, point)) return cover;
        UIView *panel = [self.rootViewController.view viewWithTag:1002];
        if (panel) {
            CGPoint panelPoint = [self.rootViewController.view convertPoint:point toView:panel];
            if ([panel pointInside:panelPoint withEvent:event]) return [panel hitTest:panelPoint withEvent:event];
        }
        return nil;
    }
    return view;
}

- (void)updateBadge {
    AccountManager *mgr = [AccountManager shared];
    NSInteger total = mgr.accounts.count;
    if (total > 0) {
        NSString *progressText;
        if (mgr.currentIndex == 0 && mgr.roundEndTime != nil) {
            progressText = [NSString stringWithFormat:@"%ld/%ld", (long)total, (long)total];
        } else {
            progressText = [NSString stringWithFormat:@"%ld/%ld", (long)mgr.currentIndex, (long)total];
        }
        _floatView.badgeLabel.text = progressText;
    } else {
        _floatView.badgeLabel.text = @"0/0";
    }
    _floatView.roundLabel.text = [mgr currentRoundName];
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
    toast.frame = CGRectMake((keyWindow.bounds.size.width - w)/2, 80, w, h);
    [keyWindow addSubview:toast];
    
    [UIView animateWithDuration:0.3 delay:1.5 options:0 animations:^{
        toast.alpha = 0;
    } completion:^(BOOL finished) {
        [toast removeFromSuperview];
    }];
}

@end