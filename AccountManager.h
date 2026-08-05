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

@property (nonatomic, assign) NSInteger currentRound;
@property (nonatomic, copy) NSString *roundAName;
@property (nonatomic, copy) NSString *roundBName;
@property (nonatomic, strong) NSDate *roundStartTime;
@property (nonatomic, strong) NSDate *roundEndTime;
@property (nonatomic, assign) BOOL needLogRoundStart;

@property (nonatomic, copy) NSString *serverURL;
@property (nonatomic, strong, readonly) NSMutableArray<NSDictionary *> *currentRoundRecords;
@property (nonatomic, copy) NSString *currentAccount;

// 详细日志开关
@property (nonatomic, assign) BOOL detailedLog;

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
- (void)appendLog:(NSString *)message;        // 追加自定义日志，会判断detailedLog

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

@end