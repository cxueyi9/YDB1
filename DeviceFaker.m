#import "DeviceFaker.h"
#import "FakerConfig.h"
#import "AccountManager.h"
#import "FloatWindow.h"
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
    NSString *account = [AccountManager shared].currentAccount ?: @"无账号";
    NSString *msg = [NSString stringWithFormat:@"【伪装】-【%@】-【%@】-【%@】", account, type, value];
    [[AccountManager shared] appendLog:msg];
    if ([FakerConfig isDebugMode]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [FloatWindow showToast:[NSString stringWithFormat:@"%@ 已伪装", type]];
        });
    }
}

#pragma mark - NSUserDefaults Hook（拦截常见标识键）
static id (*orig_NSUserDefaults_objectForKey)(id self, SEL _cmd, NSString *key);
static id replaced_NSUserDefaults_objectForKey(id self, SEL _cmd, NSString *key) {
    if ([key isEqualToString:@"deviceId"] ||
        [key isEqualToString:@"IDFV"] ||
        [key isEqualToString:@"IDFA"] ||
        [key isEqualToString:@"deviceIdentifier"] ||
        [key hasPrefix:@"com.apple."]) {
        return currentFakedID();
    }
    return orig_NSUserDefaults_objectForKey(self, _cmd, key);
}

static NSString* (*orig_NSUserDefaults_stringForKey)(id self, SEL _cmd, NSString *key);
static NSString* replaced_NSUserDefaults_stringForKey(id self, SEL _cmd, NSString *key) {
    if ([key isEqualToString:@"deviceId"] ||
        [key isEqualToString:@"IDFV"] ||
        [key isEqualToString:@"IDFA"] ||
        [key isEqualToString:@"deviceIdentifier"] ||
        [key hasPrefix:@"com.apple."]) {
        return currentFakedID();
    }
    return orig_NSUserDefaults_stringForKey(self, _cmd, key);
}

#pragma mark - UIDevice Hook
@interface UIDevice (Faker)
@end

@implementation UIDevice (Faker)

- (NSUUID *)faker_identifierForVendor {
    @try {
        NSUUID *uuid = fakedUUID();
        logFake(@"IDFV", uuid.UUIDString);
        return uuid;
    } @catch (NSException *exception) {
        return [[NSUUID alloc] initWithUUIDString:@"00000000-0000-0000-0000-000000000001"];
    }
}

- (NSString *)faker_name {
    @try {
        NSString *name = [AccountManager shared].currentFakedName ?: @"iPhone";
        logFake(@"设备名", name);
        return name;
    } @catch (NSException *exception) {
        return @"iPhone";
    }
}

- (NSString *)faker_model { return @"iPhone"; }
- (NSString *)faker_systemVersion { return @"16.0"; }

@end

#pragma mark - ASIdentifierManager Hook (IDFA)
@interface ASIdentifierManager (Faker)
@end

@implementation ASIdentifierManager (Faker)

- (NSUUID *)faker_advertisingIdentifier {
    @try {
        NSUUID *uuid = fakedUUID();
        logFake(@"IDFA", uuid.UUIDString);
        return uuid;
    } @catch (NSException *exception) {
        return [[NSUUID alloc] initWithUUIDString:@"00000000-0000-0000-0000-000000000001"];
    }
}

- (BOOL)faker_isAdvertisingTrackingEnabled { return YES; }

@end

@implementation DeviceFaker

+ (void)install {
    // UIDevice
    swizzleInstanceMethod([UIDevice class], @selector(identifierForVendor), @selector(faker_identifierForVendor));
    swizzleInstanceMethod([UIDevice class], @selector(name), @selector(faker_name));
    swizzleInstanceMethod([UIDevice class], @selector(model), @selector(faker_model));
    swizzleInstanceMethod([UIDevice class], @selector(systemVersion), @selector(faker_systemVersion));

    // ASIdentifierManager
    Class asIdManager = NSClassFromString(@"ASIdentifierManager");
    if (asIdManager) {
        swizzleInstanceMethod(asIdManager, @selector(advertisingIdentifier), @selector(faker_advertisingIdentifier));
        swizzleInstanceMethod(asIdManager, @selector(isAdvertisingTrackingEnabled), @selector(faker_isAdvertisingTrackingEnabled));
    }

    // NSUserDefaults 拦截
    Class udClass = [NSUserDefaults class];
    Method m1 = class_getInstanceMethod(udClass, @selector(objectForKey:));
    if (m1) {
        orig_NSUserDefaults_objectForKey = (id(*)(id, SEL, NSString*))method_getImplementation(m1);
        method_setImplementation(m1, (IMP)replaced_NSUserDefaults_objectForKey);
    }
    Method m2 = class_getInstanceMethod(udClass, @selector(stringForKey:));
    if (m2) {
        orig_NSUserDefaults_stringForKey = (NSString* (*)(id, SEL, NSString*))method_getImplementation(m2);
        method_setImplementation(m2, (IMP)replaced_NSUserDefaults_stringForKey);
    }
}

@end