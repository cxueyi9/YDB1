#import <UIKit/UIKit.h>
#import "FloatWindow.h"
#import "AccountManager.h"

__attribute__((constructor))
static void onLoad(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 应用完全启动后创建浮窗
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [FloatWindow shared];
                });
            });
        }];

        // 进入后台时强制保存当前状态，防止被杀后丢失
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            [[AccountManager shared] saveToFile];
        }];
    });
}