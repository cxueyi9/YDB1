#import <Foundation/Foundation.h>

@interface FakerConfig : NSObject

/// 是否启用调试模式（弹出提示）
+ (BOOL)isDebugMode;
+ (void)setDebugMode:(BOOL)debug;

/// 在屏幕顶部显示调试信息
+ (void)showDebugMessage:(NSString *)msg;

@end