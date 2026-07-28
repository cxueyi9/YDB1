#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@interface AccountManager : NSObject

+ (instancetype)shared;

@property (nonatomic, strong, readonly) NSArray<NSDictionary *> *accounts;
@property (nonatomic, assign) NSInteger currentIndex;

// 浮窗固定位置（左上角坐标，默认 (20, 100)）
@property (nonatomic, assign) CGPoint floatWindowPoint;
// 点击后粘贴前等待时间（秒）
@property (nonatomic, assign) NSTimeInterval pasteDelay;
// 粘贴完账号后、粘贴密码前的等待时间（秒）
@property (nonatomic, assign) NSTimeInterval passwordDelay;

- (NSDictionary *)nextAccount;
- (void)updateAccountsWithText:(NSString *)text;
- (NSString *)exportAccountsText;
- (void)importFromClipboard;
- (void)exportToClipboard;

// 日志功能
- (void)recordLogWithIndex:(NSInteger)index total:(NSInteger)total account:(NSString *)account;
- (NSString *)logFilePath;
- (NSString *)readLogContent;

- (void)saveToFile;
@end