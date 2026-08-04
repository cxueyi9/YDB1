#import "DeviceFaker.h"
#import "FakerConfig.h"
#import "AccountManager.h"
#import <UIKit/UIKit.h>
#import <AdSupport/AdSupport.h>
#import <objc/runtime.h>

#pragma mark - 辅助函数：交换实例方法

static void swizzleInstanceMethod(Class cls, SEL original, SEL fake) {
    Method origM = class_getInstanceMethod(cls, original);
    Method fakeM = class_getInstanceMethod(cls, fake);
    if (class_addMethod(cls, original, method_getImplementation(fakeM), method_getTypeEncoding(fakeM))) {
        class_replaceMethod(cls, fake, method_getImplementation(origM), method_getTypeEncoding(origM));
    } else {
        method_exchangeImplementations(origM, fakeM);
    }
}

#pragma mark - 获取当前伪装标识

static NSString* currentFakedID(void) {
    // 从 AccountManager 获取当前登录账号对应的伪装标识
    NSString *account = [AccountManager shared].currentAccount;
    if (!account) return @"00000000-0000-0000-0000-000000000000"; // 默认占位
    return [[AccountManager shared] fakedDeviceIdentifierForAccount:account];
}

#pragma mark - UIDevice Hook

@interface UIDevice (Faker)
@end

@implementation UIDevice (Faker)

- (NSString *)faker_identifierForVendor {
    NSString *faked = currentFakedID();
    if ([FakerConfig isDebugMode]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [FakerConfig showDebugMessage:@"IDFV 已伪装"];
        });
    }
    return faked;
}

- (NSString *)faker_name {
    if ([FakerConfig isDebugMode]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [FakerConfig showDebugMessage:@"设备名称已伪装"];
        });
    }
    return @"iPhone";
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
    NSString *faked = currentFakedID();
    if ([FakerConfig isDebugMode]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [FakerConfig showDebugMessage:@"IDFA 已伪装"];
        });
    }
    return [[NSUUID alloc] initWithUUIDString:[faked substringToIndex:36]]; // 取前36位作为标准UUID
}

- (BOOL)faker_isAdvertisingTrackingEnabled {
    return YES;
}

@end

#pragma mark - NSProcessInfo Hook (设备名等)

@interface NSProcessInfo (Faker)
@end

@implementation NSProcessInfo (Faker)

- (NSString *)faker_hostName {
    return @"iPhone";
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

    // NSProcessInfo (设备名)
    swizzleInstanceMethod([NSProcessInfo class], @selector(hostName), @selector(faker_hostName));
}

@end