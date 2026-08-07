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

// 一轮计时（用于信息标签）
@property (nonatomic, strong) NSDate *roundStartTime;
@property (nonatomic, strong) NSDate *roundEndTime;

@property (nonatomic, copy) NSString *serverURL;
@property (nonatomic, strong, readonly) NSMutableArray<NSDictionary *> *currentRoundRecords;
@property (nonatomic, copy) NSString *currentAccount;
@property (nonatomic, assign) BOOL detailedLog;
@property (nonatomic, assign) BOOL antiDetection; // 防封检查

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

@end