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
    return [[AccountManager shared] currentFakedID] ?: @"00000000-0000-0000-0000-000000000001";
}

static NSString* currentFakedName(void) {
    return [[AccountManager shared] currentFakedName] ?: @"iPhone";
}

static NSUUID* fakedUUID(void) {
    NSString *fakedStr = currentFakedID();
    NSString *clean = [fakedStr stringByReplacingOccurrencesOfString:@"-" withString:@""];
    if (clean.length > 32) clean = [clean substringToIndex:32];
    while (clean.length < 32) clean = [clean stringByAppendingString:@"0"];
    NSMutableString *formatted = [NSMutableString string];
    for (NSInteger i = 0; i < clean.length; i++) {
        if (i == 8 || i == 12 || i == 16 || i == 20) [formatted appendString:@"-"];
        [formatted appendFormat:@"%c", [clean characterAtIndex:i]];
    }
    return [[NSUUID alloc] initWithUUIDString:formatted];
}

static void logFake(NSString *type, NSString *value) {
    if ([AccountManager shared].detailedLog) {
        NSString *account = [AccountManager shared].currentAccount ?: @"无账号";
        NSString *msg = [NSString stringWithFormat:@"【伪装】-【%@】-【%@】-【%@】", account, type, value];
        [[AccountManager shared] appendLog:msg];
    }
}

#pragma mark - UIDevice Hook

@interface UIDevice (Faker)
@end

@implementation UIDevice (Faker)

- (NSUUID *)faker_identifierForVendor {
    @try {
        NSUUID *uuid = fakedUUID();
        logFake(@"IDFV", uuid.UUIDString);
        if ([FakerConfig isDebugMode]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [FakerConfig showDebugMessage:@"IDFV 已伪装"];
            });
        }
        return uuid;
    } @catch (NSException *exception) {
        return [[NSUUID alloc] initWithUUIDString:@"00000000-0000-0000-0000-000000000001"];
    }
}

- (NSString *)faker_name {
    @try {
        NSString *name = currentFakedName();
        logFake(@"设备名", name);
        if ([FakerConfig isDebugMode]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [FakerConfig showDebugMessage:@"设备名称已伪装"];
            });
        }
        return name;
    } @catch (NSException *exception) {
        return @"iPhone";
    }
}

- (NSString *)faker_model { return @"iPhone"; }
- (NSString *)faker_systemVersion { return @"16.0"; }

@end

#pragma mark - ASIdentifierManager Hook

@interface ASIdentifierManager (Faker)
@end

@implementation ASIdentifierManager (Faker)

- (NSUUID *)faker_advertisingIdentifier {
    @try {
        NSUUID *uuid = fakedUUID();
        logFake(@"IDFA", uuid.UUIDString);
        if ([FakerConfig isDebugMode]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [FakerConfig showDebugMessage:@"IDFA 已伪装"];
            });
        }
        return uuid;
    } @catch (NSException *exception) {
        return [[NSUUID alloc] initWithUUIDString:@"00000000-0000-0000-0000-000000000001"];
    }
}

- (BOOL)faker_isAdvertisingTrackingEnabled { return YES; }

@end

@implementation DeviceFaker

+ (void)install {
    swizzleInstanceMethod([UIDevice class], @selector(identifierForVendor), @selector(faker_identifierForVendor));
    swizzleInstanceMethod([UIDevice class], @selector(name), @selector(faker_name));
    swizzleInstanceMethod([UIDevice class], @selector(model), @selector(faker_model));
    swizzleInstanceMethod([UIDevice class], @selector(systemVersion), @selector(faker_systemVersion));

    Class asIdManager = NSClassFromString(@"ASIdentifierManager");
    if (asIdManager) {
        swizzleInstanceMethod(asIdManager, @selector(advertisingIdentifier), @selector(faker_advertisingIdentifier));
        swizzleInstanceMethod(asIdManager, @selector(isAdvertisingTrackingEnabled), @selector(faker_isAdvertisingTrackingEnabled));
    }
}

@end