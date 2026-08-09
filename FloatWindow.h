#import <UIKit/UIKit.h>

@interface FloatWindow : UIWindow

+ (instancetype)shared;
- (void)updateBadge;

// 普通 Toast（账号、伪装等）
+ (void)showToast:(NSString *)message;
// 虚拟定位专用 Toast（位置稍下移，避免与普通 Toast 重叠）
+ (void)showLocationToast:(NSString *)message;

@end