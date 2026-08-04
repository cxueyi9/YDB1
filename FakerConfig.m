#import "FakerConfig.h"
#import <UIKit/UIKit.h>

static BOOL debugMode = YES;  // 默认开启调试，方便测试

@implementation FakerConfig

+ (BOOL)isDebugMode {
    return debugMode;
}

+ (void)setDebugMode:(BOOL)debug {
    debugMode = debug;
}

+ (void)showDebugMessage:(NSString *)msg {
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
    toast.frame = CGRectMake((keyWindow.bounds.size.width - w)/2, 60, w, h); // 顶部
    [keyWindow addSubview:toast];

    [UIView animateWithDuration:0.3 delay:1.5 options:0 animations:^{
        toast.alpha = 0;
    } completion:^(BOOL finished) {
        [toast removeFromSuperview];
    }];
}

@end