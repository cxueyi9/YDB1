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

- (NSArray<NSDictionary *> *)accounts {
    return [_accounts copy];
}

- (NSString *)currentRoundName {
    return (self.currentRound == 0) ? self.roundAName : self.roundBName;
}

- (void)switchToNextRound {
    self.currentRound = 1 - self.currentRound;
    self.roundStartTime = [NSDate date];
    self.needLogRoundStart = YES;
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
            // 格式：序号:账号:密码
            [_accounts addObject:@{@"account": parts[1], @"password": parts[2]}];
        } else if (parts.count == 2) {
            // 兼容旧格式：账号:密码
            [_accounts addObject:@{@"account": parts[0], @"password": parts[1]}];
        }
    }
    self.currentIndex = 0;
    self.currentRound = 0;
    self.roundStartTime = [NSDate date];
    self.needLogRoundStart = YES;
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
    self.needLogRoundStart = YES;
    [self saveToFile];
}

#pragma mark - 本地日志

- (NSString *)logFilePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [paths.firstObject stringByAppendingPathComponent:@"fill_log.txt"];
}

- (void)recordLogRoundStart {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy/M/d HH:mm";
    NSString *timeStr = [fmt stringFromDate:[NSDate date]];
    NSString *line = [NSString stringWithFormat:@"%@ 开始, %@\n", [self currentRoundName], timeStr];
    
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
    NSString *timeStr = [fmt stringFromDate:[NSDate date]];
    NSString *line = [NSString stringWithFormat:@"%ld/%ld, %@, %@\n", (long)index, (long)total, timeStr, account];
    
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
    NSString *path = [self logFilePath];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

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
            // 上传失败，暂存
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

- (NSString *)deviceIdentifier {
    static NSString *identifier = nil;
    if (identifier) return identifier;
    
    NSString *key = @"com.youdaibao.deviceid";
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    identifier = [ud stringForKey:key];
    if (!identifier) {
        identifier = [[NSUUID UUID] UUIDString];
        [ud setObject:identifier forKey:key];
        [ud synchronize];
    }
    return identifier;
}

#pragma mark - 持久化

- (NSString *)dataFilePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [paths.firstObject stringByAppendingPathComponent:@"com.youdaibao.config.plist"];
}

- (void)saveToFile {
    NSMutableArray *arr = [NSMutableArray array];
    for (NSDictionary *d in _accounts) {
        [arr addObject:d];
    }
    NSDictionary *data = @{
        @"accounts": arr,
        @"currentIndex": @(self.currentIndex),
        @"floatWindowPoint": NSStringFromCGPoint(self.floatWindowPoint),
        @"pasteDelay": @(self.pasteDelay),
        @"passwordDelay": @(self.passwordDelay),
        @"floatLocked": @(self.floatLocked),
        @"currentRound": @(self.currentRound),
        @"roundAName": self.roundAName ?: @"A轮",
        @"roundBName": self.roundBName ?: @"B轮",
        @"roundStartTime": self.roundStartTime ?: [NSDate date],
        @"needLogRoundStart": @(self.needLogRoundStart),
        @"serverURL": self.serverURL ?: @""
    };
    [data writeToFile:[self dataFilePath] atomically:YES];
}

- (void)loadFromFile {
    NSDictionary *data = [NSDictionary dictionaryWithContentsOfFile:[self dataFilePath]];
    if (data) {
        NSArray *arr = data[@"accounts"];
        if (arr) _accounts = [arr mutableCopy];
        NSNumber *idx = data[@"currentIndex"];
        self.currentIndex = idx ? [idx integerValue] : 0;
        NSString *fp = data[@"floatWindowPoint"];
        if (fp) self.floatWindowPoint = CGPointFromString(fp);
        NSNumber *pd = data[@"pasteDelay"];
        if (pd) self.pasteDelay = [pd doubleValue];
        NSNumber *pwd = data[@"passwordDelay"];
        if (pwd) self.passwordDelay = [pwd doubleValue];
        NSNumber *locked = data[@"floatLocked"];
        self.floatLocked = locked ? [locked boolValue] : NO;
        
        NSNumber *round = data[@"currentRound"];
        self.currentRound = round ? [round integerValue] : 0;
        self.roundAName = data[@"roundAName"] ?: @"A轮";
        self.roundBName = data[@"roundBName"] ?: @"B轮";
        self.roundStartTime = data[@"roundStartTime"] ?: [NSDate date];
        NSNumber *needLog = data[@"needLogRoundStart"];
        self.needLogRoundStart = needLog ? [needLog boolValue] : YES;
        
        self.serverURL = data[@"serverURL"] ?: @"http://你的服务器地址:5000/upload";
    }
    self.currentRoundRecords = [NSMutableArray array];
}

@end