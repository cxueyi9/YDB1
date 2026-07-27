#import <UIKit/UIKit.h>

@interface FloatWindow : UIWindow

+ (instancetype)shared;

// 刷新浮标上的索引显示
- (void)updateBadge;

@end