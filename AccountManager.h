#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@interface AccountManager : NSObject

+ (instancetype)shared;

@property (nonatomic, strong, readonly) NSArray<NSDictionary *> *accounts;
@property (nonatomic, assign) NSInteger currentIndex;  // 已填充数量（0~total-1）

// 浮窗位置（拖拽后自动保存）
@property (nonatomic, assign) CGPoint floatWindowPoint;
// 粘贴前等待时间（秒）
@property (nonatomic, assign) NSTimeInterval pasteDelay;
// 密码粘贴等待时间（秒）
@property (nonatomic, assign) NSTimeInterval passwordDelay;
// 是否锁定图标（禁止拖拽）
@property (nonatomic, assign) BOOL floatLocked;

- (NSDictionary *)nextAccount;
- (void)updateAccountsWithText:(NSString *)text;
- (NSString *)exportAccountsText;
- (void)importFromClipboard;
- (void)exportToClipboard;

// 日志
- (void)recordLogWithIndex:(NSInteger)index total:(NSInteger)total account:(NSString *)account;
- (NSString *)logFilePath;
- (NSString *)readLogContent;
- (void)clearLog;

// 重置进度
- (void)resetProgress;

// 持久化
- (void)saveToFile;

@end