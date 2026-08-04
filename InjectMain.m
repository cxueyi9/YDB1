#import <UIKit/UIKit.h>
#import "FloatWindow.h"
#import "AccountManager.h"
#import "DeviceFaker.h"

__attribute__((constructor))
static void onLoad(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 等待应用完全激活后再安装设备标识拦截，避免启动早期调用不安全
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                [DeviceFaker install];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [FloatWindow shared];
                });
            });
        }];

        // 应用即将非活跃时强制保存
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            [[AccountManager shared] saveToFile];
        }];
    });
}