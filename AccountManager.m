#import "AccountManager.h"
#import <UIKit/UIKit.h>

@interface AccountManager ()
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *currentRoundRecords;
@end

@implementation AccountManager {
    NSMutableArray<NSDictionary *> *_accounts;
}

+ (instancetype)shared {
    static AccountManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
        [instance loadFromFile];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _accounts = [NSMutableArray array];
        self.floatWindowPoint = CGPointMake(20, 100);
        self.pasteDelay = 1.0;
        self.passwordDelay = 0.5;
        self.floatLocked = NO;
        
        self.currentRound = 0;
        self.roundAName = @"A轮";
        self.roundBName = @"B轮";
        self.roundStartTime = [NSDate date];
        self.needLogRoundStart = YES;
        
        self.serverURL = @"http://你的服务器地址:5000/upload";
        self.currentRoundRecords = [NSMutableArray array];
    }
    return self;
}

// 原有账号管理方法...
- (NSArray<NSDictionary *> *)accounts { return [_accounts copy]; }
- (NSString *)currentRoundName { return (self.currentRound == 0) ? self.roundAName : self.roundBName; }
- (void)switchToNextRound { self.currentRound = 1 - self.currentRound; self.roundStartTime = [NSDate date]; self.needLogRoundStart = YES; [self saveToFile]; }
- (NSDictionary *)nextAccount { if (_accounts.count == 0) return nil; NSDictionary *acc = _accounts[self.currentIndex % _accounts.count]; self.currentIndex = (self.currentIndex + 1) % _accounts.count; [self saveToFile]; return acc; }
- (void)updateAccountsWithText:(NSString *)text { /* 原有实现，使用 : 分隔符，省略 */ }
- (NSString *)exportAccountsText { /* 原有实现，省略 */ }
- (void)resetProgress { self.currentIndex = 0; self.currentRound = 0; self.roundStartTime = [NSDate date]; self.needLogRoundStart = YES; [self saveToFile]; }

#pragma mark - 本地日志
- (NSString *)logFilePath { /* 原有，省略 */ }
- (void)recordLogRoundStart { /* 原有，省略 */ }
- (void)recordLogWithIndex:(NSInteger)index total:(NSInteger)total account:(NSString *)account { /* 原有，省略 */ }
- (NSString *)readLogContent { /* 原有，省略 */ }
- (void)clearLog { /* 原有，省略 */ }

#pragma mark - 本轮记录（上传用）
- (void)addRoundRecordWithIndex:(NSInteger)index total:(NSInteger)total account:(NSString *)account {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy/M/d HH:mm";
    NSString *timeStr = [fmt stringFromDate:[NSDate date]];
    NSDictionary *record = @{
        @"index": @(index),
        @"total": @(total),
        @"account": account ?: @"",
        @"time": timeStr,
        @"device": [self deviceIdentifier]
    };
    [self.currentRoundRecords addObject:record];
}

- (void)uploadRoundRecordsWithCompletion:(void(^)(BOOL success, NSString *msg))completion {
    if (self.currentRoundRecords.count == 0) {
        if (completion) completion(NO, @"无本轮记录");
        return;
    }
    [self uploadRecords:[self.currentRoundRecords copy] completion:^(BOOL success, NSString *msg) {
        if (success) {
            [self.currentRoundRecords removeAllObjects];
        } else {
            // 上传失败，暂存记录
            NSMutableArray *staged = [[self loadStagedRecords] mutableCopy] ?: [NSMutableArray array];
            [staged addObjectsFromArray:self.currentRoundRecords];
            [self saveStagedRecords:staged];
            [self.currentRoundRecords removeAllObjects];
        }
        if (completion) completion(success, msg);
    }];
}

- (void)uploadStagedRecordsWithCompletion:(void(^)(BOOL success, NSString *msg))completion {
    NSArray *staged = [self loadStagedRecords];
    if (staged.count == 0) {
        if (completion) completion(NO, @"无暂存记录");
        return;
    }
    [self uploadRecords:staged completion:^(BOOL success, NSString *msg) {
        if (success) {
            [self clearStagedRecords];
        }
        if (completion) completion(success, msg);
    }];
}

// 通用上传
- (void)uploadRecords:(NSArray<NSDictionary *> *)records completion:(void(^)(BOOL, NSString*))completion {
    if (self.serverURL.length == 0) {
        if (completion) completion(NO, @"未设置服务器地址");
        return;
    }
    NSError *err;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:records options:0 error:&err];
    if (err) {
        if (completion) completion(NO, err.localizedDescription);
        return;
    }
    NSURL *url = [NSURL URLWithString:self.serverURL];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = jsonData;
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, error.localizedDescription);
            });
            return;
        }
        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        if (httpResp.statusCode == 200) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(YES, @"上传成功");
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *msg = [NSString stringWithFormat:@"服务器返回状态码: %ld", (long)httpResp.statusCode];
                if (completion) completion(NO, msg);
            });
        }
    }];
    [task resume];
}

#pragma mark - 暂存记录持久化
- (NSString *)stagedFilePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [paths.firstObject stringByAppendingPathComponent:@"staged_records.plist"];
}
- (NSArray<NSDictionary *> *)loadStagedRecords {
    return [NSArray arrayWithContentsOfFile:[self stagedFilePath]] ?: @[];
}
- (void)saveStagedRecords:(NSArray<NSDictionary *> *)records {
    [records writeToFile:[self stagedFilePath] atomically:YES];
}
- (void)clearStagedRecords {
    [[NSFileManager defaultManager] removeItemAtPath:[self stagedFilePath] error:nil];
}

#pragma mark - 设备标识
- (NSString *)deviceIdentifier { /* 原有实现，返回 UUID，省略 */ }

#pragma mark - 持久化（增加 serverURL 的存取）
- (NSString *)dataFilePath { /* 原有实现，省略 */ }
- (void)saveToFile { /* 原有实现，增加 serverURL 存储，省略 */ }
- (void)loadFromFile { /* 原有实现，增加 serverURL 读取，省略 */ }

@end