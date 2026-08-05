#import "FloatWindow.h"
#import "AccountManager.h"
#import "LocationFaker.h"

@interface FloatView : UIView
@property (nonatomic, weak) UILabel *roundLabel;
@property (nonatomic, weak) UILabel *badgeLabel;
@property (nonatomic, assign) BOOL isEditing;
@end

@implementation FloatView
// ... 与上一版相同，省略
@end

#pragma mark - FloatWindow

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

        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            [self updateBadge];
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            [[AccountManager shared] saveToFile];
        }];
    }
    return self;
}

// showEditPanel 完整实现，包含虚拟定位区域
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
    CGFloat panelH = 580; // 增加高度容纳虚拟定位
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake((screenBounds.size.width-panelW)/2, (screenBounds.size.height-panelH)/2-20, panelW, panelH)];
    panel.backgroundColor = [UIColor whiteColor]; panel.layer.cornerRadius = 14; panel.tag = 1002;
    [superview addSubview:panel];

    // 标题
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(15, 8, panelW-30, 18)];
    title.text = @"账号与设置"; title.font = [UIFont boldSystemFontOfSize:15]; [panel addSubview:title];

    // 账号列表
    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(15, 28, panelW-30, 120)];
    tv.layer.borderWidth = 0.5; tv.layer.borderColor = [UIColor colorWithWhite:0.8 alpha:1].CGColor;
    tv.layer.cornerRadius = 6; tv.font = [UIFont systemFontOfSize:13]; tv.tag = 1003; tv.text = [mgr exportAccountsText];
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
    goBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:0.15]; goBtn.layer.cornerRadius = 6;
    [goBtn addTarget:self action:@selector(jumpAction:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:goBtn];
    yPos += 36;

    // ------ 虚拟定位区域 ------
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
    currentLocLabel.text = [NSString stringWithFormat:@"当前: %.6f, %.6f", curLoc.latitude, curLoc.longitude];
    currentLocLabel.font = [UIFont systemFontOfSize:11]; currentLocLabel.textColor = [UIColor darkGrayColor];
    [panel addSubview:currentLocLabel];
    yPos += 22;

    UIButton *manageLocBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    manageLocBtn.frame = CGRectMake(leftMargin, yPos, 80, 28);
    [manageLocBtn setTitle:@"管理收藏" forState:UIControlStateNormal];
    [manageLocBtn addTarget:self action:@selector(openLocationFavorites) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:manageLocBtn];
    yPos += 32;

    // 详细日志开关
    [self addLabel:@"详细日志" frameX:leftMargin y:yPos w:70 toPanel:panel];
    UISwitch *detailLogSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(leftMargin+75, yPos-5, 51, 31)];
    detailLogSwitch.on = mgr.detailedLog; detailLogSwitch.tag = 3005;
    [panel addSubview:detailLogSwitch];
    yPos += 32;
    // ------ 虚拟定位区域结束 ------

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

// 新增方法：打开虚拟定位收藏管理界面
- (void)openLocationFavorites {
    // 弹出 LocationFaker 提供的收藏管理 VC
    UIViewController *vc = [LocationFaker favoritesViewController];
    if (vc) {
        UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
        while (root.presentedViewController) root = root.presentedViewController;
        [root presentViewController:vc animated:YES completion:nil];
    }
}

// saveAction 中增加保存定位开关和详细日志
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

    // 虚拟定位开关
    BOOL locEnabled = ((UISwitch *)[panel viewWithTag:3004]).on;
    [LocationFaker setEnabled:locEnabled];

    UITextField *rATF = (UITextField *)[panel viewWithTag:3000]; if (rATF.text.length) mgr.roundAName = rATF.text;
    UITextField *rBTF = (UITextField *)[panel viewWithTag:3001]; if (rBTF.text.length) mgr.roundBName = rBTF.text;
    mgr.serverURL = [(UITextField *)[panel viewWithTag:3003] text] ?: mgr.serverURL;
    [mgr saveToFile];
    [[FloatWindow shared] updateBadge];
    [self dismissPanel];
    [FloatWindow showToast:@"设置已保存"];
}

// 其他方法（jump, cancel, copyLog等）保持不变...
@end