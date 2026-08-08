#import "LicenseManager.h"
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonHMAC.h>
#import <CommonCrypto/CommonCryptor.h>
#import <objc/runtime.h>

static NSString * const kServerSecret = @"Com.Wanlianyida.Driver.app.123!";
static NSString * const kLicenseKey = @"com.license.key";

// 注册视图控制器
@interface LicenseVC : UIViewController
@property (nonatomic, copy) NSString *localIdentifier; // 明文
@property (nonatomic, copy) NSString *encryptedID;      // 密文
@end

@implementation LicenseManager

+ (void)validateAndShowIfNeeded {
    NSString *license = [[NSUserDefaults standardUserDefaults] stringForKey:kLicenseKey];
    if (license && [self verifyLicense:license]) {
        return;
    }
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
    NSString *encryptedID = parts[0];
    NSString *expireStr = parts[1];
    NSString *hmac = parts[2];

    // 解密标识
    NSString *identifier = [self decryptIdentifier:encryptedID];
    if (!identifier) return NO;
    if (![identifier isEqualToString:[self generateLocalIdentifier]]) return NO;

    long long expire = [expireStr longLongValue];
    if ([[NSDate date] timeIntervalSince1970] > expire) return NO;

    // 计算 HMAC 时，使用原始注册码中的密文标识和过期时间
    NSString *computed = [self hmacForEncryptedID:encryptedID expire:expire];
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

#pragma mark - 加密/解密

+ (NSData *)AESKey {
    // 用 kServerSecret 的 SHA256 作为 AES-256 密钥
    const char *s = [kServerSecret UTF8String];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(s, (CC_LONG)strlen(s), digest);
    return [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
}

+ (NSString *)encryptIdentifier:(NSString *)plain {
    NSData *plainData = [plain dataUsingEncoding:NSUTF8StringEncoding];
    NSData *key = [self AESKey];
    // IV 固定为 16 字节零（生产环境建议随机，但必须两边一致）
    char ivBytes[kCCBlockSizeAES128] = {0};
    NSData *iv = [NSData dataWithBytes:ivBytes length:kCCBlockSizeAES128];
    
    size_t bufferSize = [plainData length] + kCCBlockSizeAES128;
    void *buffer = malloc(bufferSize);
    size_t numBytesEncrypted = 0;
    CCCryptorStatus status = CCCrypt(kCCEncrypt,
                                     kCCAlgorithmAES,
                                     kCCOptionPKCS7Padding,
                                     [key bytes], kCCKeySizeAES256,
                                     [iv bytes],
                                     [plainData bytes], [plainData length],
                                     buffer, bufferSize,
                                     &numBytesEncrypted);
    if (status == kCCSuccess) {
        NSData *encrypted = [NSData dataWithBytes:buffer length:numBytesEncrypted];
        free(buffer);
        return [encrypted base64EncodedStringWithOptions:0];
    }
    free(buffer);
    return nil;
}

+ (NSString *)decryptIdentifier:(NSString *)cipher {
    NSData *cipherData = [[NSData alloc] initWithBase64EncodedString:cipher options:0];
    if (!cipherData) return nil;
    NSData *key = [self AESKey];
    char ivBytes[kCCBlockSizeAES128] = {0};
    NSData *iv = [NSData dataWithBytes:ivBytes length:kCCBlockSizeAES128];
    
    size_t bufferSize = [cipherData length] + kCCBlockSizeAES128;
    void *buffer = malloc(bufferSize);
    size_t numBytesDecrypted = 0;
    CCCryptorStatus status = CCCrypt(kCCDecrypt,
                                     kCCAlgorithmAES,
                                     kCCOptionPKCS7Padding,
                                     [key bytes], kCCKeySizeAES256,
                                     [iv bytes],
                                     [cipherData bytes], [cipherData length],
                                     buffer, bufferSize,
                                     &numBytesDecrypted);
    if (status == kCCSuccess) {
        NSData *plainData = [NSData dataWithBytes:buffer length:numBytesDecrypted];
        free(buffer);
        return [[NSString alloc] initWithData:plainData encoding:NSUTF8StringEncoding];
    }
    free(buffer);
    return nil;
}

+ (NSString *)hmacForEncryptedID:(NSString *)encryptedID expire:(long long)expire {
    NSString *msg = [NSString stringWithFormat:@"%@|%lld", encryptedID, expire];
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
    [window makeKeyAndVisible];
    objc_setAssociatedObject([UIApplication sharedApplication], "LicenseWindow", window, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end

@implementation LicenseVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    self.localIdentifier = [LicenseManager generateLocalIdentifier];
    self.encryptedID = [LicenseManager encryptIdentifier:self.localIdentifier];

    CGFloat w = self.view.bounds.size.width;
    CGFloat y = 80;
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, y, w-40, 30)];
    title.text = @"软件未注册";
    title.font = [UIFont boldSystemFontOfSize:22];
    title.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:title];
    y += 50;

    // 显示密文标识
    UITextView *idView = [[UITextView alloc] initWithFrame:CGRectMake(20, y, w-40, 100)];
    idView.text = self.encryptedID;
    idView.font = [UIFont systemFontOfSize:14];
    idView.layer.borderWidth = 1;
    idView.layer.borderColor = [UIColor lightGrayColor].CGColor;
    idView.editable = NO;
    [self.view addSubview:idView];
    y += 110;

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
    UIPasteboard.generalPasteboard.string = self.encryptedID;
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