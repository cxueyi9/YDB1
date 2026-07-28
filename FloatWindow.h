#import <UIKit/UIKit.h>

@interface FloatWindow : UIWindow

+ (instancetype)shared;
- (void)updateBadge;

// 类方法展示toast
+ (void)showToast:(NSString *)message;

@end