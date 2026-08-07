#import <Foundation/Foundation.h>

@interface LicenseManager : NSObject

// 检查注册状态，若无效则展示注册页面
+ (void)validateAndShowIfNeeded;

// 获取当前有效期字符串，无注册返回 nil
+ (NSString *)expireDateString;

@end