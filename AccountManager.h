#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@interface AccountManager : NSObject

+ (instancetype)shared;

@property (nonatomic, strong, readonly) NSArray<NSDictionary *> *accounts;
@property (nonatomic, assign) NSInteger currentIndex;

@property (nonatomic, assign) CGPoint floatWindowPoint;
@property (nonatomic, assign) NSTimeInterval pasteDelay;
@property (nonatomic, assign) NSTimeInterval passwordDelay;
@property (nonatomic, assign) BOOL floatLocked;      // 锁定图标拖拽
@property (nonatomic, assign) BOOL tapLocked;        // 锁定点击填充
@property (nonatomic, assign) BOOL autoLock;         // 自动锁定点击

@property (nonatomic, assign) NSInteger currentRound;
@property (nonatomic, copy) NSString *roundAName;
@property (nonatomic, copy) NSString *roundBName;
@property (nonatomic, strong) NSDate *roundStartTime;
@property (nonatomic, strong) NSDate *roundEndTime;  // 新增
@property (nonatomic, assign) BOOL needLogRoundStart;

@property (nonatomic, copy) NSString *serverURL;
@property (nonatomic, strong, readonly) NSMutableArray<NSDictionary *> *currentRoundRecords;

// 当前登录账号（由点击填充时自动记录）
@property (nonatomic, copy) NSString *currentAccount;

- (NSString *)currentRoundName;
- (void)switchToNextRound;
- (void)finishRound;                                 // 新增：记录结束时间

- (NSDictionary *)nextAccount;
- (void)updateAccountsWithText:(NSString *)text;
- (NSString *)exportAccountsText;

// 本地日志
- (void)recordLogWithIndex:(NSInteger)index total:(NSInteger)total account:(NSString *)account;
- (void)recordLogRoundStart;
- (NSString *)logFilePath;
- (NSString *)readLogContent;
- (void)clearLog;

// 本轮记录/上传
- (void)addRoundRecordWithIndex:(NSInteger)index total:(NSInteger)total account:(NSString *)account;
- (void)uploadRoundRecordsWithCompletion:(void(^)(BOOL success, NSString *msg))completion;

// 暂存管理
- (NSArray<NSDictionary *> *)loadStagedRecords;
- (void)saveStagedRecords:(NSArray<NSDictionary *> *)records;
- (void)clearStagedRecords;
- (void)uploadStagedRecordsWithCompletion:(void(^)(BOOL success, NSString *msg))completion;

- (void)resetProgress;
- (void)saveToFile;
- (NSString *)deviceIdentifier;

// 根据账号生成唯一伪装标识
- (NSString *)fakedDeviceIdentifierForAccount:(NSString *)account;

// 追加自定义消息到本地日志文件
- (void)appendLog:(NSString *)message;

@end