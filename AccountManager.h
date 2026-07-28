#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@interface AccountManager : NSObject

+ (instancetype)shared;

@property (nonatomic, strong, readonly) NSArray<NSDictionary *> *accounts;
@property (nonatomic, assign) NSInteger currentIndex;          // 已填充数量

// 浮窗位置
@property (nonatomic, assign) CGPoint floatWindowPoint;
// 粘贴前等待时间（秒）
@property (nonatomic, assign) NSTimeInterval pasteDelay;
// 密码粘贴等待时间（秒）
@property (nonatomic, assign) NSTimeInterval passwordDelay;
// 是否锁定图标
@property (nonatomic, assign) BOOL floatLocked;

// 轮次管理
@property (nonatomic, assign) NSInteger currentRound;         // 0 或 1
@property (nonatomic, copy) NSString *roundAName;
@property (nonatomic, copy) NSString *roundBName;
@property (nonatomic, strong) NSDate *roundStartTime;
@property (nonatomic, assign) BOOL needLogRoundStart;         // 是否需要在下次填充时记录轮次开始

- (NSString *)currentRoundName;
- (void)switchToNextRound;

- (NSDictionary *)nextAccount;
- (void)updateAccountsWithText:(NSString *)text;
- (NSString *)exportAccountsText;
- (void)importFromClipboard;
- (void)exportToClipboard;

// 日志
- (void)recordLogWithIndex:(NSInteger)index total:(NSInteger)total account:(NSString *)account;
- (void)recordLogRoundStart;                                  // 新增
- (NSString *)logFilePath;
- (NSString *)readLogContent;
- (void)clearLog;

- (void)resetProgress;
- (void)saveToFile;

@end