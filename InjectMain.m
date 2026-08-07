#import <UIKit/UIKit.h>
#import "FloatWindow.h"
#import "AccountManager.h"
#import "DeviceFaker.h"
#import "LocationFaker.h"
#import "LicenseManager.h"

__attribute__((constructor))
static void onLoad(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 等待应用完全激活后再执行初始化和注册检查
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                // 1. 注册检查（若未注册则显示注册页面，阻止后续执行）
                [LicenseManager validateAndShowIfNeeded];

                // 2. 安装设备标识拦截和虚拟定位
                [DeviceFaker install];
                [LocationFaker install];

                // 3. 延迟创建悬浮窗（确保界面加载完毕）
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [FloatWindow shared];
                });
            });
        }];

        // 应用即将非活跃时强制保存配置
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            [[AccountManager shared] saveToFile];
        }];
    });
}