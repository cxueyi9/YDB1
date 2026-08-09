#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@interface AccountManager : NSObject

+ (instancetype)shared;

@property (nonatomic, strong, readonly) NSArray<NSDictionary *> *accounts;
@property (nonatomic, assign) NSInteger currentIndex;

@property (nonatomic, assign) CGPoint floatWindowPoint;
@property (nonatomic, assign) NSTimeInterval pasteDelay;
@property (nonatomic, assign) NSTimeInterval passwordDelay;
@property (nonatomic, assign) BOOL floatLocked;
@property (nonatomic, assign) BOOL tapLocked;
@property (nonatomic, assign) BOOL autoLock;
@property (nonatomic, assign) NSTimeInterval clickCooldown;
@property (nonatomic, assign) NSTimeInterval lastClickTime;

// 一轮计时
@property (nonatomic, strong) NSDate *roundStartTime;
@property (nonatomic, strong) NSDate *roundEndTime;

@property (nonatomic, copy) NSString *serverURL;
@property (nonatomic, strong, readonly) NSMutableArray<NSDictionary *> *currentRoundRecords;
@property (nonatomic, copy) NSString *currentAccount;
@property (nonatomic, assign) BOOL detailedLog;
@property (nonatomic, assign) BOOL antiDetection;
@property (nonatomic, assign) BOOL locationLoggedThisCycle;

// 异常账号相关
@property (nonatomic, strong) NSMutableSet<NSNumber *> *abnormalSet;       // 异常账号索引（1-based）
@property (nonatomic, strong) NSMutableArray<NSNumber *> *abnormalOrdered; // 有序异常列表
@property (nonatomic, assign) NSInteger abnormalCurrentIndex;              // 当前异常处理到的下标
@property (nonatomic, assign) BOOL abnormalMode;                           // 是否处于异常处理模式

- (NSString *)currentRoundName;
- (void)switchToNextRound;
- (void)finishRound;

- (NSDictionary *)nextAccount;
- (void)updateAccountsWithText:(NSString *)text;
- (NSString *)exportAccountsText;

- (void)recordLogWithIndex:(NSInteger)index total:(NSInteger)total account:(NSString *)account;
- (void)recordLogRoundStart;
- (NSString *)logFilePath;
- (NSString *)readLogContent;
- (void)clearLog;
- (void)appendLog:(NSString *)message;

- (void)addRoundRecordWithIndex:(NSInteger)index total:(NSInteger)total account:(NSString *)account;
- (void)uploadRoundRecordsWithCompletion:(void(^)(BOOL success, NSString *msg))completion;

- (NSArray<NSDictionary *> *)loadStagedRecords;
- (void)saveStagedRecords:(NSArray<NSDictionary *> *)records;
- (void)clearStagedRecords;
- (void)uploadStagedRecordsWithCompletion:(void(^)(BOOL success, NSString *msg))completion;

- (NSString *)currentFakedID;
- (NSString *)currentFakedName;

- (void)resetProgress;
- (void)saveToFile;
- (NSString *)deviceIdentifier;

// 异常处理方法
- (void)recordAbnormalWithIndex:(NSInteger)index;        // 记录异常账号 (1-based)
- (void)clearAbnormal;                                   // 清空所有异常
- (NSString *)abnormalString;                            // 返回逗号分隔的异常编号字符串
- (void)enterAbnormalMode;                               // 进入异常处理模式
- (NSDictionary *)nextAbnormalAccount;                   // 返回当前待处理的异常账号信息，并移动指针
- (void)removeAbnormalAtIndex:(NSInteger)index;           // 处理完一个异常后，若不再异常则移除
- (BOOL)isAbnormalRemaining;                             // 是否还有未处理的异常

@end