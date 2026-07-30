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
        self.tapLocked = NO;
        self.autoLock = NO;

        self.currentRound = 0;
        self.roundAName = @"A轮";
        self.roundBName = @"B轮";
        self.roundStartTime = [NSDate date];
        self.roundEndTime = nil;
        self.needLogRoundStart = YES;

        self.serverURL = @"http://你的服务器地址:5000/upload";
        self.currentRoundRecords = [NSMutableArray array];
    }
    return self;
}

- (NSArray<NSDictionary *> *)accounts { return [_accounts copy]; }

- (NSString *)currentRoundName { return (self.currentRound == 0) ? self.roundAName : self.roundBName; }

- (void)switchToNextRound {
    self.currentRound = 1 - self.currentRound;
    self.roundStartTime = [NSDate date];
    self.roundEndTime = nil;
    self.needLogRoundStart = YES;
    [self saveToFile];
}

- (void)finishRound {
    self.roundEndTime = [NSDate date];
    [self saveToFile];
}

- (NSDictionary *)nextAccount {
    if (_accounts.count == 0) return nil;
    NSDictionary *acc = _accounts[self.currentIndex % _accounts.count];
    self.currentIndex = (self.currentIndex + 1) % _accounts.count;
    [self saveToFile];
    return acc;
}

- (void)updateAccountsWithText:(NSString *)text {
    [_accounts removeAllObjects];
    NSArray *lines = [text componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) continue;
        NSArray *parts = [trimmed componentsSeparatedByString:@":"];
        if (parts.count == 3) {
            [_accounts addObject:@{@"account": parts[1], @"password": parts[2]}];
        } else if (parts.count == 2) {
            [_accounts addObject:@{@"account": parts[0], @"password": parts[1]}];
        }
    }
    self.currentIndex = 0;
    self.currentRound = 0;
    self.roundStartTime = [NSDate date];
    self.roundEndTime = nil;
    self.needLogRoundStart = YES;
    self.tapLocked = NO;
    [self saveToFile];
}

- (NSString *)exportAccountsText {
    NSMutableString *text = [NSMutableString string];
    for (NSInteger i = 0; i < _accounts.count; i++) {
        NSDictionary *acc = _accounts[i];
        [text appendFormat:@"%ld:%@:%@\n", (long)(i+1), acc[@"account"], acc[@"password"]];
    }
    return text;
}

- (void)resetProgress {
    self.currentIndex = 0;
    self.currentRound = 0;
    self.roundStartTime = [NSDate date];
    self.roundEndTime = nil;
    self.needLogRoundStart = YES;
    self.tapLocked = NO;
    [self saveToFile];
}

#pragma mark - 本地日志（保持不变）
- (NSString *)logFilePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [paths.firstObject stringByAppendingPathComponent:@"fill_log.txt"];
}

- (void)recordLogRoundStart {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy/M/d HH:mm";
    NSString *line = [NSString stringWithFormat:@"%@ 开始, %@\n", [self currentRoundName], [fmt stringFromDate:[NSDate date]]];
    NSString *path = [self logFilePath];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
        [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
}

- (void)recordLogWithIndex:(NSInteger)index total:(NSInteger)total account:(NSString *)account {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy/M/d HH:mm";
    NSString *line = [NSString stringWithFormat:@"%ld/%ld, %@, %@\n", (long)index, (long)total, [fmt stringFromDate:[NSDate date]], account];
    NSString *path = [self logFilePath];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
        [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
}

- (NSString *)readLogContent {
    return [NSString stringWithContentsOfFile:[self logFilePath] encoding:NSUTF8StringEncoding error:nil] ?: @"";
}

- (void)clearLog {
    [[NSFileManager defaultManager] removeItemAtPath:[self logFilePath] error:nil];
}

#pragma mark - 本轮记录/上传（不变）
- (void)addRoundRecordWithIndex:(NSInteger)index total:(NSInteger)total account:(NSString *)account {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy/M/d HH:mm";
    [self.currentRoundRecords addObject:@{
        @"index": @(index),
        @"total": @(total),
        @"account": account ?: @"",
        @"time": [fmt stringFromDate:[NSDate date]],
        @"device": [self deviceIdentifier]
    }];
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
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                if (completion) completion(NO, error.localizedDescription);
                return;
            }
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            if (httpResp.statusCode == 200) {
                if (completion) completion(YES, @"上传成功");
            } else {
                if (completion) completion(NO, [NSString stringWithFormat:@"服务器状态码 %ld", (long)httpResp.statusCode]);
            }
        });
    }];
    [task resume];
}

#pragma mark - 暂存记录（不变）
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

- (NSString *)deviceIdentifier {
    static NSString *identifier = nil;
    if (identifier) return identifier;
    NSString *key = @"com.youdaibao.deviceid";
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    identifier = [ud stringForKey:key];
    if (!identifier) {
        identifier = [[NSUUID UUID] UUIDString];
        [ud setObject:identifier forKey:key];
    }
    return identifier;
}

#pragma mark - 持久化（改造：核心状态使用 NSUserDefaults）

- (NSString *)dataFilePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [paths.firstObject stringByAppendingPathComponent:@"com.youdaibao.config.plist"];
}

- (void)saveToFile {
    // 1. 保存核心进度到 NSUserDefaults（强制写入，不怕被杀）
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setInteger:self.currentIndex forKey:@"currentIndex"];
    [ud setInteger:self.currentRound forKey:@"currentRound"];
    [ud setBool:self.needLogRoundStart forKey:@"needLogRoundStart"];
    [ud setBool:self.tapLocked forKey:@"tapLocked"];
    [ud setBool:self.autoLock forKey:@"autoLock"];
    [ud setBool:self.floatLocked forKey:@"floatLocked"];
    [ud setDouble:self.pasteDelay forKey:@"pasteDelay"];
    [ud setDouble:self.passwordDelay forKey:@"passwordDelay"];
    [ud setObject:self.roundAName ?: @"A轮" forKey:@"roundAName"];
    [ud setObject:self.roundBName ?: @"B轮" forKey:@"roundBName"];
    [ud setObject:self.serverURL ?: @"" forKey:@"serverURL"];
    if (self.roundStartTime) [ud setObject:self.roundStartTime forKey:@"roundStartTime"];
    else [ud removeObjectForKey:@"roundStartTime"];
    if (self.roundEndTime) [ud setObject:self.roundEndTime forKey:@"roundEndTime"];
    else [ud removeObjectForKey:@"roundEndTime"];
    [ud setObject:NSStringFromCGPoint(self.floatWindowPoint) forKey:@"floatWindowPoint"];
    [ud synchronize];  // 立即同步

    // 2. 同时保存账号列表到 plist（以便完整备份）
    NSMutableArray *arr = [NSMutableArray array];
    for (NSDictionary *d in _accounts) [arr addObject:d];
    NSDictionary *data = @{
        @"accounts": arr,
        @"currentIndex": @(self.currentIndex),
        @"floatWindowPoint": NSStringFromCGPoint(self.floatWindowPoint),
        @"pasteDelay": @(self.pasteDelay),
        @"passwordDelay": @(self.passwordDelay),
        @"floatLocked": @(self.floatLocked),
        @"tapLocked": @(self.tapLocked),
        @"autoLock": @(self.autoLock),
        @"currentRound": @(self.currentRound),
        @"roundAName": self.roundAName ?: @"A轮",
        @"roundBName": self.roundBName ?: @"B轮",
        @"roundStartTime": self.roundStartTime ?: [NSDate date],
        @"roundEndTime": self.roundEndTime ?: [NSNull null],
        @"needLogRoundStart": @(self.needLogRoundStart),
        @"serverURL": self.serverURL ?: @""
    };
    [data writeToFile:[self dataFilePath] atomically:YES];
}

- (void)loadFromFile {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    // 优先从 NSUserDefaults 恢复核心状态（即使应用被杀死也能保证最新）
    if ([ud objectForKey:@"currentIndex"] != nil) {
        self.currentIndex = [ud integerForKey:@"currentIndex"];
        self.currentRound = [ud integerForKey:@"currentRound"];
        self.needLogRoundStart = [ud boolForKey:@"needLogRoundStart"];
        self.tapLocked = [ud boolForKey:@"tapLocked"];
        self.autoLock = [ud boolForKey:@"autoLock"];
        self.floatLocked = [ud boolForKey:@"floatLocked"];
        self.pasteDelay = [ud doubleForKey:@"pasteDelay"];
        self.passwordDelay = [ud doubleForKey:@"passwordDelay"];
        self.roundAName = [ud stringForKey:@"roundAName"] ?: @"A轮";
        self.roundBName = [ud stringForKey:@"roundBName"] ?: @"B轮";
        self.serverURL = [ud stringForKey:@"serverURL"] ?: @"http://你的服务器地址:5000/upload";
        if ([ud objectForKey:@"roundStartTime"]) self.roundStartTime = [ud objectForKey:@"roundStartTime"];
        else self.roundStartTime = [NSDate date];
        if ([ud objectForKey:@"roundEndTime"]) self.roundEndTime = [ud objectForKey:@"roundEndTime"];
        else self.roundEndTime = nil;
        NSString *fpStr = [ud stringForKey:@"floatWindowPoint"];
        if (fpStr) self.floatWindowPoint = CGPointFromString(fpStr);
    } else {
        // 若 NSUserDefaults 中没有，从 plist 读取（兼容旧版数据）
        NSDictionary *data = [NSDictionary dictionaryWithContentsOfFile:[self dataFilePath]];
        if (data) {
            self.currentIndex = [data[@"currentIndex"] integerValue];
            self.currentRound = [data[@"currentRound"] integerValue];
            self.needLogRoundStart = [data[@"needLogRoundStart"] boolValue];
            self.tapLocked = [data[@"tapLocked"] boolValue];
            self.autoLock = [data[@"autoLock"] boolValue];
            self.floatLocked = [data[@"floatLocked"] boolValue];
            self.pasteDelay = [data[@"pasteDelay"] doubleValue];
            self.passwordDelay = [data[@"passwordDelay"] doubleValue];
            self.roundAName = data[@"roundAName"] ?: @"A轮";
            self.roundBName = data[@"roundBName"] ?: @"B轮";
            self.serverURL = data[@"serverURL"] ?: @"http://你的服务器地址:5000/upload";
            if ([data[@"roundStartTime"] isKindOfClass:[NSDate class]]) self.roundStartTime = data[@"roundStartTime"];
            else self.roundStartTime = [NSDate date];
            if ([data[@"roundEndTime"] isKindOfClass:[NSDate class]]) self.roundEndTime = data[@"roundEndTime"];
            else self.roundEndTime = nil;
            NSString *fp = data[@"floatWindowPoint"];
            if (fp) self.floatWindowPoint = CGPointFromString(fp);
        }
    }
    
    // 继续从 plist 中读取账号列表（文件方式存储可避免 NSUserDefaults 容量限制）
    NSDictionary *data = [NSDictionary dictionaryWithContentsOfFile:[self dataFilePath]];
    NSArray *arr = data[@"accounts"];
    if (arr) {
        _accounts = [arr mutableCopy];
    }
    
    // 初始化内存中的记录数组
    self.currentRoundRecords = [NSMutableArray array];
}

@end