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

@property (nonatomic, assign) NSInteger currentRound;
@property (nonatomic, copy) NSString *roundAName;
@property (nonatomic, copy) NSString *roundBName;
@property (nonatomic, strong) NSDate *roundStartTime;
@property (nonatomic, strong) NSDate *roundEndTime;
@property (nonatomic, assign) BOOL needLogRoundStart;

@property (nonatomic, copy) NSString *serverURL;
@property (nonatomic, strong, readonly) NSMutableArray<NSDictionary *> *currentRoundRecords;

// 在原有属性后追加
@property (nonatomic, assign) NSTimeInterval lastClickTime;   // 上次点击时间戳
@property (nonatomic, assign) NSTimeInterval clickCooldown;   // 点击冷却秒数，默认30

// 虚拟定位
@property (nonatomic, assign) BOOL fakeLocationEnabled;       // 是否启用虚拟定位
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *locationFavorites; // 收藏地址列表
@property (nonatomic, assign) NSInteger selectedLocationIndex; // 当前选中的地址索引，-1表示未选
// 每个地址字典包含：name, latMin, latMax, lonMin, lonMax

// 当前登录账号（填充时自动设置）
@property (nonatomic, copy) NSString *currentAccount;

- (NSString *)currentRoundName;
- (void)switchToNextRound;
- (void)finishRound;

- (NSDictionary *)nextAccount;
- (void)updateAccountsWithText:(NSString *)text;
- (NSString *)exportAccountsText;

// 本地日志
- (void)recordLogWithIndex:(NSInteger)index total:(NSInteger)total account:(NSString *)account;
- (void)recordLogRoundStart;
- (NSString *)logFilePath;
- (NSString *)readLogContent;
- (void)clearLog;
- (void)appendLog:(NSString *)message;   // 追加自定义日志

// 本轮记录/上传
- (void)addRoundRecordWithIndex:(NSInteger)index total:(NSInteger)total account:(NSString *)account;
- (void)uploadRoundRecordsWithCompletion:(void(^)(BOOL success, NSString *msg))completion;

// 暂存管理
- (NSArray<NSDictionary *> *)loadStagedRecords;
- (void)saveStagedRecords:(NSArray<NSDictionary *> *)records;
- (void)clearStagedRecords;
- (void)uploadStagedRecordsWithCompletion:(void(^)(BOOL success, NSString *msg))completion;

// 伪装信息
- (NSString *)fakedDeviceIdentifierForAccount:(NSString *)account; // 已废弃，保留兼容
- (NSString *)currentFakedID;   // 当前账号的伪装 UUID
- (NSString *)currentFakedName; // 当前账号的伪装设备名

- (void)resetProgress;
- (void)saveToFile;
- (NSString *)deviceIdentifier;



@end