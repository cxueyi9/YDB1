#import <Foundation/Foundation.h>

@interface DeviceFaker : NSObject

/// 安装所有 Hook（应在 dylib 加载时调用一次）
+ (void)install;

@end