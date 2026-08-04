#import "DeviceFaker.h"
#import "FakerConfig.h"
#import "AccountManager.h"
#import <UIKit/UIKit.h>
#import <AdSupport/AdSupport.h>
#import <objc/runtime.h>

static void swizzleInstanceMethod(Class cls, SEL original, SEL fake) {
    Method origM = class_getInstanceMethod(cls, original);
    Method fakeM = class_getInstanceMethod(cls, fake);
    if (class_addMethod(cls, original, method_getImplementation(fakeM), method_getTypeEncoding(fakeM))) {
        class_replaceMethod(cls, fake, method_getImplementation(origM), method_getTypeEncoding(origM));
    } else {
        method_exchangeImplementations(origM, fakeM);
    }
}

static NSString* currentFakedID(void) {
    NSString *account = [AccountManager shared].currentAccount;
    if (account.length == 0) {
        // 默认返回一个固定的占位 UUID，保证格式正确
        return @"00000000-0000-0000-0000-000000000001";
    }
    return [[AccountManager shared] fakedDeviceIdentifierForAccount:account];
}

#pragma mark - UIDevice Hook

@interface UIDevice (Faker)
@end

@implementation UIDevice (Faker)

- (NSString *)faker_identifierForVendor {
    @try {
        NSString *faked = currentFakedID();
        if ([FakerConfig isDebugMode]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [FakerConfig showDebugMessage:@"IDFV 已伪装"];
            });
        }
        return faked;
    } @catch (NSException *exception) {
        return @"00000000-0000-0000-0000-000000000001";
    }
}

- (NSString *)faker_name {
    @try {
        if ([FakerConfig isDebugMode]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [FakerConfig showDebugMessage:@"设备名称已伪装"];
            });
        }
        return @"iPhone";
    } @catch (NSException *exception) {
        return @"iPhone";
    }
}

- (NSString *)faker_model {
    return @"iPhone";
}

- (NSString *)faker_systemVersion {
    return @"16.0";
}

@end

#pragma mark - ASIdentifierManager Hook (IDFA)

@interface ASIdentifierManager (Faker)
@end

@implementation ASIdentifierManager (Faker)

- (NSUUID *)faker_advertisingIdentifier {
    @try {
        NSString *faked = currentFakedID();
        if ([FakerConfig isDebugMode]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [FakerConfig showDebugMessage:@"IDFA 已伪装"];
            });
        }
        // 确保长度至少为 36，不足则用0填充
        NSString *uuidStr = [faked stringByReplacingOccurrencesOfString:@"-" withString:@""];
        if (uuidStr.length > 32) uuidStr = [uuidStr substringToIndex:32];
        while (uuidStr.length < 32) uuidStr = [uuidStr stringByAppendingString:@"0"];
        // 格式化为 8-4-4-4-12
        NSMutableString *formatted = [NSMutableString string];
        for (int i = 0; i < uuidStr.length; i++) {
            if (i == 8 || i == 12 || i == 16 || i == 20) [formatted appendString:@"-"];
            [formatted appendFormat:@"%C", [uuidStr characterAtIndex:i]];
        }
        return [[NSUUID alloc] initWithUUIDString:formatted];
    } @catch (NSException *exception) {
        return [[NSUUID alloc] initWithUUIDString:@"00000000-0000-0000-0000-000000000001"];
    }
}

- (BOOL)faker_isAdvertisingTrackingEnabled {
    return YES;
}

@end

#pragma mark - 安装入口

@implementation DeviceFaker

+ (void)install {
    // UIDevice
    swizzleInstanceMethod([UIDevice class], @selector(identifierForVendor), @selector(faker_identifierForVendor));
    swizzleInstanceMethod([UIDevice class], @selector(name), @selector(faker_name));
    swizzleInstanceMethod([UIDevice class], @selector(model), @selector(faker_model));
    swizzleInstanceMethod([UIDevice class], @selector(systemVersion), @selector(faker_systemVersion));

    // ASIdentifierManager (IDFA)
    Class asIdManager = NSClassFromString(@"ASIdentifierManager");
    if (asIdManager) {
        swizzleInstanceMethod(asIdManager, @selector(advertisingIdentifier), @selector(faker_advertisingIdentifier));
        swizzleInstanceMethod(asIdManager, @selector(isAdvertisingTrackingEnabled), @selector(faker_isAdvertisingTrackingEnabled));
    }
}

@end