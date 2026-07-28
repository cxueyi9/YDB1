#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@interface AccountManager : NSObject

+ (instancetype)shared;

@property (nonatomic, strong, readonly) NSArray<NSDictionary *> *accounts;
@property (nonatomic, assign) NSInteger currentIndex;

// 定位配置
@property (nonatomic, assign) CGPoint accountPoint;   // 账号输入框坐标
@property (nonatomic, assign) CGPoint passwordPoint;  // 密码输入框坐标
@property (nonatomic, assign) NSTimeInterval delaySeconds; // 填充密码前的延时

- (NSDictionary *)nextAccount;
- (void)updateAccountsWithText:(NSString *)text;
- (NSString *)exportAccountsText;
- (void)importFromClipboard;
- (void)exportToClipboard;

@end