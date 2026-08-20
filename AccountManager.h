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
@property (nonatomic, copy) NSString *roundEndLocName;   // 一轮结束时的定位收藏名称
// 异常账号
@property (nonatomic, strong) NSMutableSet<NSNumber *> *abnormalSet;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *abnormalOrdered;
@property (nonatomic, assign) NSInteger abnormalCurrentIndex;
@property (nonatomic, assign) BOOL abnormalMode;

// 新增 Bark 推送
@property (nonatomic, copy) NSString *barkKey;
@property (nonatomic, assign) BOOL barkEnabled;
// 锁定模式（区别于点击锁定）
@property (nonatomic, assign) BOOL lockedMode;

- (void)sendBarkPush:(NSString *)content;

- (NSDictionary *)nextAccount;
- (void)updateAccountsWithText:(NSString *)text;
- (NSString *)exportAccountsText;

- (void)recordLogWithIndex:(NSInteger)index total:(NSInteger)total account:(NSString *)account;
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

// 异常处理
- (void)recordAbnormalWithIndex:(NSInteger)index;
- (void)clearAbnormal;
- (NSString *)abnormalString;
- (void)setAbnormalFromString:(NSString *)str;
- (void)enterAbnormalMode;
- (NSDictionary *)nextAbnormalAccount;
- (void)removeLastHandledAbnormal;
- (BOOL)isAbnormalRemaining;
- (void)loadFromFile;   // 公开加载方法，用于界面刷新



@end