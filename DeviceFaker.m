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

// 生成一个合法的 NSUUID 对象，基于账号哈希
static NSUUID* currentFakedUUID(void) {
    NSString *account = [AccountManager shared].currentAccount;
    NSString *uuidStr;
    if (account.length == 0) {
        uuidStr = @"00000000-0000-0000-0000-000000000001";
    } else {
        uuidStr = [[AccountManager shared] fakedDeviceIdentifierForAccount:account];
    }
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:uuidStr];
    if (!uuid) {
        // 降级：使用固定 UUID
        uuid = [[NSUUID alloc] initWithUUIDString:@"00000000-0000-0000-0000-000000000001"];
    }
    return uuid;
}

#pragma mark - UIDevice Hook

@interface UIDevice (Faker)
@end

@implementation UIDevice (Faker)

// 关键修复：必须返回 NSUUID 对象，而不是 NSString
- (NSUUID *)faker_identifierForVendor {
    @try {
        NSUUID *faked = currentFakedUUID();
        if ([FakerConfig isDebugMode]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [FakerConfig showDebugMessage:@"IDFV 已伪装"];
            });
        }
        return faked;
    } @catch (NSException *exception) {
        return [[NSUUID alloc] initWithUUIDString:@"00000000-0000-0000-0000-000000000001"];
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
        NSUUID *faked = currentFakedUUID();
        if ([FakerConfig isDebugMode]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [FakerConfig showDebugMessage:@"IDFA 已伪装"];
            });
        }
        return faked;
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