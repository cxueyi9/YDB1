#import "LicenseManager.h"
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonHMAC.h>
#import <objc/runtime.h>

static NSString * const kServerSecret = @"YourSecretKey123!";
static NSString * const kLicenseKey = @"com.license.key";

// 注册视图控制器
@interface LicenseVC : UIViewController
@property (nonatomic, copy) NSString *localIdentifier;
@end

@implementation LicenseManager

+ (void)validateAndShowIfNeeded {
    NSString *license = [[NSUserDefaults standardUserDefaults] stringForKey:kLicenseKey];
    if (license && [self verifyLicense:license]) {
        return; // 有效
    }
    // 强制显示注册页
    dispatch_async(dispatch_get_main_queue(), ^{
        [self showRegistrationWindow];
    });
}

+ (BOOL)verifyLicense:(NSString *)license {
    NSData *data = [[NSData alloc] initWithBase64EncodedString:license options:0];
    if (!data) return NO;
    NSString *decoded = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!decoded) return NO;
    NSArray *parts = [decoded componentsSeparatedByString:@"|"];
    if (parts.count != 3) return NO;
    NSString *identifier = parts[0];
    NSString *expireStr = parts[1];
    NSString *hmac = parts[2];

    if (![identifier isEqualToString:[self generateLocalIdentifier]]) return NO;

    long long expire = [expireStr longLongValue];
    if ([[NSDate date] timeIntervalSince1970] > expire) return NO;

    NSString *computed = [self hmacForIdentifier:identifier expire:expire];
    return [computed isEqualToString:hmac];
}

+ (NSString *)expireDateString {
    NSString *license = [[NSUserDefaults standardUserDefaults] stringForKey:kLicenseKey];
    if (!license) return nil;
    NSData *data = [[NSData alloc] initWithBase64EncodedString:license options:0];
    if (!data) return nil;
    NSString *decoded = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!decoded) return nil;
    NSArray *parts = [decoded componentsSeparatedByString:@"|"];
    if (parts.count != 3) return nil;
    long long expire = [parts[1] longLongValue];
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:expire];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd";
    return [fmt stringFromDate:date];
}

+ (NSString *)generateLocalIdentifier {
    NSString *key = @"com.license.deviceid";
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *deviceID = [ud stringForKey:key];
    if (!deviceID) {
        deviceID = [[NSUUID UUID] UUIDString];
        [ud setObject:deviceID forKey:key];
        [ud synchronize];
    }
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyyMMddHH";
    NSString *timeStr = [fmt stringFromDate:[NSDate date]];
    return [NSString stringWithFormat:@"%@|%@|%@", deviceID, bundleID, timeStr];
}

+ (NSString *)hmacForIdentifier:(NSString *)identifier expire:(long long)expire {
    NSString *msg = [NSString stringWithFormat:@"%@|%lld", identifier, expire];
    const char *cKey = [kServerSecret cStringUsingEncoding:NSUTF8StringEncoding];
    const char *cData = [msg cStringUsingEncoding:NSUTF8StringEncoding];
    unsigned char cHMAC[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, cKey, strlen(cKey), cData, strlen(cData), cHMAC);
    NSMutableString *output = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [output appendFormat:@"%02x", cHMAC[i]];
    }
    return output;
}

+ (void)showRegistrationWindow {
    UIWindow *window;
    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = (UIWindowScene *)[[[UIApplication sharedApplication] connectedScenes] anyObject];
        window = scene ? [[UIWindow alloc] initWithWindowScene:scene] : [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    } else {
        window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    }
    window.windowLevel = UIWindowLevelAlert + 100;
    window.backgroundColor = [UIColor whiteColor];
    window.rootViewController = [[LicenseVC alloc] init];
    window.hidden = NO;
    [window makeKeyAndVisible];  // 确保可接收触摸事件

    // 保持窗口不被释放
    objc_setAssociatedObject([UIApplication sharedApplication], "LicenseWindow", window, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end

@implementation LicenseVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    self.localIdentifier = [LicenseManager generateLocalIdentifier];

    CGFloat w = self.view.bounds.size.width;
    CGFloat y = 80;
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, y, w-40, 30)];
    title.text = @"软件未注册";
    title.font = [UIFont boldSystemFontOfSize:22];
    title.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:title];
    y += 50;

    UITextView *idView = [[UITextView alloc] initWithFrame:CGRectMake(20, y, w-40, 80)];
    idView.text = self.localIdentifier;
    idView.font = [UIFont systemFontOfSize:14];
    idView.layer.borderWidth = 1;
    idView.layer.borderColor = [UIColor lightGrayColor].CGColor;
    idView.editable = NO;
    [self.view addSubview:idView];
    y += 90;

    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(20, y, 100, 30);
    [copyBtn setTitle:@"复制标识" forState:UIControlStateNormal];
    [copyBtn addTarget:self action:@selector(copyID) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:copyBtn];
    y += 40;

    UITextField *codeField = [[UITextField alloc] initWithFrame:CGRectMake(20, y, w-40, 40)];
    codeField.placeholder = @"请输入注册码";
    codeField.borderStyle = UITextBorderStyleRoundedRect;
    codeField.tag = 200;
    [self.view addSubview:codeField];
    y += 50;

    UIButton *regBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    regBtn.frame = CGRectMake(20, y, w-40, 44);
    [regBtn setTitle:@"注册" forState:UIControlStateNormal];
    [regBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    regBtn.backgroundColor = [UIColor systemBlueColor];
    regBtn.layer.cornerRadius = 8;
    [regBtn addTarget:self action:@selector(registerAction) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:regBtn];
    y += 60;

    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(20, y, w-40, 40)];
    hint.text = @"请将标识码发送给管理员获取注册码";
    hint.textColor = [UIColor grayColor];
    hint.font = [UIFont systemFontOfSize:13];
    hint.textAlignment = NSTextAlignmentCenter;
    hint.numberOfLines = 0;
    [self.view addSubview:hint];
}

- (void)copyID {
    UIPasteboard.generalPasteboard.string = self.localIdentifier;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:@"已复制" preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:alert animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:nil];
        });
    }];
}

- (void)registerAction {
    UITextField *field = [self.view viewWithTag:200];
    NSString *code = field.text;
    if (code.length == 0) return;

    if ([LicenseManager verifyLicense:code]) {
        [[NSUserDefaults standardUserDefaults] setObject:code forKey:@"com.license.key"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        // 显示成功提示后退出
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"注册成功" message:@"请重新打开应用" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            exit(0);
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    } else {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"错误" message:@"注册码无效或已过期" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}
@end