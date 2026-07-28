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
// 是否锁定图标（禁止点击填充）
@property (nonatomic, assign) BOOL floatLocked;
// 是否开启自动锁定（每轮结束后自动锁定）
@property (nonatomic, assign) BOOL autoLock;

// 轮次管理
@property (nonatomic, assign) NSInteger currentRound;          // 0 或 1
@property (nonatomic, copy) NSString *roundAName;
@property (nonatomic, copy) NSString *roundBName;
@property (nonatomic, strong) NSDate *roundStartTime;
@property (nonatomic, assign) BOOL needLogRoundStart;          // 是否需要在下次填充时记录轮次开始

// 服务器上传
@property (nonatomic, copy) NSString *serverURL;
@property (nonatomic, strong, readonly) NSMutableArray<NSDictionary *> *currentRoundRecords;

- (NSString *)currentRoundName;
- (void)switchToNextRound;

- (NSDictionary *)nextAccount;
- (void)updateAccountsWithText:(NSString *)text;
- (NSString *)exportAccountsText;

// 本地日志文件
- (void)recordLogWithIndex:(NSInteger)index total:(NSInteger)total account:(NSString *)account;
- (void)recordLogRoundStart;
- (NSString *)logFilePath;
- (NSString *)readLogContent;
- (void)clearLog;

// 本轮记录（用于上传）
- (void)addRoundRecordWithIndex:(NSInteger)index total:(NSInteger)total account:(NSString *)account;
- (void)uploadRoundRecordsWithCompletion:(void(^)(BOOL success, NSString *msg))completion;

// 暂存记录管理
- (NSArray<NSDictionary *> *)loadStagedRecords;
- (void)saveStagedRecords:(NSArray<NSDictionary *> *)records;
- (void)clearStagedRecords;
- (void)uploadStagedRecordsWithCompletion:(void(^)(BOOL success, NSString *msg))completion;

- (void)resetProgress;
- (void)saveToFile;
- (NSString *)deviceIdentifier;

@end