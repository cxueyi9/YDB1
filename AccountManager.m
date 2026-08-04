#import "AccountManager.h"
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>

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
        self.currentAccount = @"";
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
        if (parts.count < 3) continue; // 至少需要 序号:账号:密码
        
        NSString *account = parts[1];
        NSString *password = parts[2];
        if (account.length == 0) continue;
        
        NSString *fakedID = nil;
        if (parts.count >= 4 && [parts[3] length] > 0) {
            fakedID = parts[3];
        } else {
            fakedID = [self generateFakedIDForAccount:account];
        }
        
        NSString *fakedName = @"iPhone";
        if (parts.count >= 5 && [parts[4] length] > 0) {
            fakedName = parts[4];
        }
        
        [_accounts addObject:@{
            @"account": account,
            @"password": password,
            @"fakedID": fakedID,
            @"fakedName": fakedName
        }];
    }
    self.currentIndex = 0;
    self.currentRound = 0;
    self.roundStartTime = [NSDate date];
    self.roundEndTime = nil;
    self.needLogRoundStart = YES;
    self.tapLocked = NO;
    self.currentAccount = @"";
    [self saveToFile];
}

- (NSString *)exportAccountsText {
    NSMutableString *text = [NSMutableString string];
    for (NSInteger i = 0; i < _accounts.count; i++) {
        NSDictionary *acc = _accounts[i];
        NSString *fakedID = acc[@"fakedID"] ?: @"";
        NSString *fakedName = acc[@"fakedName"] ?: @"iPhone";
        [text appendFormat:@"%ld:%@:%@:%@:%@\n", (long)(i+1),
         acc[@"account"], acc[@"password"], fakedID, fakedName];
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
    self.currentAccount = @"";
    [self saveToFile];
}

#pragma mark - 伪装标识生成

- (NSString *)generateFakedIDForAccount:(NSString *)account {
    if (!account || account.length == 0) return @"00000000-0000-0000-0000-000000000000";
    NSData *data = [account dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *output = [NSMutableString stringWithCapacity:36];
    for (int i = 0; i < 16; i++) {
        if (i == 4 || i == 6 || i == 8 || i == 10) [output appendString:@"-"];
        [output appendFormat:@"%02x", digest[i]];
    }
    return [output uppercaseString];
}

- (NSString *)fakedDeviceIdentifierForAccount:(NSString *)account {
    // 直接遍历查找
    for (NSDictionary *acc in _accounts) {
        if ([acc[@"account"] isEqualToString:account]) {
            return acc[@"fakedID"] ?: [self generateFakedIDForAccount:account];
        }
    }
    return [self generateFakedIDForAccount:account];
}

- (NSString *)currentFakedID {
    for (NSDictionary *acc in _accounts) {
        if ([acc[@"account"] isEqualToString:self.currentAccount]) {
            return acc[@"fakedID"] ?: @"00000000-0000-0000-0000-000000000001";
        }
    }
    return @"00000000-0000-0000-0000-000000000001";
}

- (NSString *)currentFakedName {
    for (NSDictionary *acc in _accounts) {
        if ([acc[@"account"] isEqualToString:self.currentAccount]) {
            return acc[@"fakedName"] ?: @"iPhone";
        }
    }
    return @"iPhone";
}

#pragma mark - 本地日志

- (NSString *)logFilePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [paths.firstObject stringByAppendingPathComponent:@"fill_log.txt"];
}

- (void)recordLogRoundStart {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy/M/d HH:mm";
    NSString *line = [NSString stringWithFormat:@"%@ 开始, %@\n", [self currentRoundName], [fmt stringFromDate:[NSDate date]]];
    [self appendLine:line];
}

- (void)recordLogWithIndex:(NSInteger)index total:(NSInteger)total account:(NSString *)account {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy/M/d HH:mm";
    NSString *line = [NSString stringWithFormat:@"%ld/%ld, %@, %@\n", (long)index, (long)total, [fmt stringFromDate:[NSDate date]], account];
    [self appendLine:line];
}

- (void)appendLog:(NSString *)message {
    if (!message || message.length == 0) return;
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy/M/d HH:mm:ss";
    NSString *timeStr = [fmt stringFromDate:[NSDate date]];
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", timeStr, message];
    [self appendLine:line];
}

- (void)appendLine:(NSString *)line {
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

#pragma mark - 本轮记录/上传

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

#pragma mark - 暂存记录

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

#pragma mark - 持久化

- (NSString *)dataFilePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [paths.firstObject stringByAppendingPathComponent:@"com.youdaibao.config.plist"];
}

- (void)saveToFile {
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
    [ud setObject:self.currentAccount ?: @"" forKey:@"currentAccount"];
    if (self.roundStartTime) [ud setObject:self.roundStartTime forKey:@"roundStartTime"];
    else [ud removeObjectForKey:@"roundStartTime"];
    if (self.roundEndTime) [ud setObject:self.roundEndTime forKey:@"roundEndTime"];
    else [ud removeObjectForKey:@"roundEndTime"];
    [ud setObject:NSStringFromCGPoint(self.floatWindowPoint) forKey:@"floatWindowPoint"];
    [ud synchronize];

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
        @"serverURL": self.serverURL ?: @"",
        @"currentAccount": self.currentAccount ?: @""
    };
    [data writeToFile:[self dataFilePath] atomically:YES];
}

- (void)loadFromFile {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
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
        self.currentAccount = [ud stringForKey:@"currentAccount"] ?: @"";
        if ([ud objectForKey:@"roundStartTime"]) self.roundStartTime = [ud objectForKey:@"roundStartTime"];
        else self.roundStartTime = [NSDate date];
        if ([ud objectForKey:@"roundEndTime"]) self.roundEndTime = [ud objectForKey:@"roundEndTime"];
        else self.roundEndTime = nil;
        NSString *fpStr = [ud stringForKey:@"floatWindowPoint"];
        if (fpStr) self.floatWindowPoint = CGPointFromString(fpStr);
    } else {
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
            self.currentAccount = data[@"currentAccount"] ?: @"";
            if ([data[@"roundStartTime"] isKindOfClass:[NSDate class]]) self.roundStartTime = data[@"roundStartTime"];
            else self.roundStartTime = [NSDate date];
            if ([data[@"roundEndTime"] isKindOfClass:[NSDate class]]) self.roundEndTime = data[@"roundEndTime"];
            else self.roundEndTime = nil;
            NSString *fp = data[@"floatWindowPoint"];
            if (fp) self.floatWindowPoint = CGPointFromString(fp);
        }
    }
    
    NSDictionary *data = [NSDictionary dictionaryWithContentsOfFile:[self dataFilePath]];
    NSArray *arr = data[@"accounts"];
    if (arr) {
        _accounts = [arr mutableCopy];
        // 兼容旧数据：若缺失 fakedID/fakedName，自动生成并保存
        BOOL modified = NO;
        for (NSMutableDictionary *acc in _accounts) {
            if (!acc[@"fakedID"]) {
                NSString *genID = [self generateFakedIDForAccount:acc[@"account"]];
                acc[@"fakedID"] = genID;
                modified = YES;
            }
            if (!acc[@"fakedName"]) {
                acc[@"fakedName"] = @"iPhone";
                modified = YES;
            }
        }
        if (modified) {
            [self saveToFile];
        }
    } else {
        _accounts = [NSMutableArray array];
    }
    self.currentRoundRecords = [NSMutableArray array];
}

@end