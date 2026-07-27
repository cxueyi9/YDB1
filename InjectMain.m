#import <UIKit/UIKit.h>
#import "FloatWindow.h"

// 使用通知确保UI已初始化
__attribute__((constructor))
static void onLoad(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification * _Nonnull note) {
            // 启动悬浮窗
            [FloatWindow shared];
        }];
    });
}