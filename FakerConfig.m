#import "FakerConfig.h"
#import <UIKit/UIKit.h>

static BOOL debugMode = YES;

@implementation FakerConfig

+ (BOOL)isDebugMode {
    return debugMode;
}

+ (void)setDebugMode:(BOOL)debug {
    debugMode = NO;
}

+ (void)showDebugMessage:(NSString *)msg {
    // 确保在主线程执行
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showDebugMessage:msg];
        });
        return;
    }
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) return;

    UILabel *toast = [[UILabel alloc] init];
    toast.text = msg;
    toast.textColor = [UIColor whiteColor];
    toast.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.font = [UIFont systemFontOfSize:13];
    toast.layer.cornerRadius = 6;
    toast.clipsToBounds = YES;

    CGSize size = [msg sizeWithAttributes:@{NSFontAttributeName: toast.font}];
    CGFloat w = size.width + 16;
    CGFloat h = size.height + 10;
    toast.frame = CGRectMake((keyWindow.bounds.size.width - w)/2, 80, w, h);
    [keyWindow addSubview:toast];

    [UIView animateWithDuration:0.3 delay:1.5 options:0 animations:^{
        toast.alpha = 0;
    } completion:^(BOOL finished) {
        [toast removeFromSuperview];
    }];
}

@end