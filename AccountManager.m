#import "AccountManager.h"
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>

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
        self.clickCooldown = 30.0;
        self.lastClickTime = 0;
        self.detailedLog = NO;
        self.antiDetection = NO;
        self.locationLoggedThisCycle = NO;
        self.serverURL = @"";
        self.currentRoundRecords = [NSMutableArray array];
        self.currentAccount = @"";
        self.abnormalSet = [NSMutableSet set];
        self.abnormalOrdered = [NSMutableArray array];
        self.abnormalCurrentIndex = 0;
        self.abnormalMode = NO;
        self.barkKey = @"";
        self.barkEnabled = NO;
        self.lockedMode = NO;
    }
    return self;
}

- (NSArray<NSDictionary *> *)accounts { return [_accounts copy]; }

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
        if (parts.count >= 3) {
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
        } else if (parts.count == 2) {
            NSString *account = parts[0];
            NSString *password = parts[1];
            NSString *fakedID = [self generateFakedIDForAccount:account];
            [_accounts addObject:@{
                @"account": account,
                @"password": password,
                @"fakedID": fakedID,
                @"fakedName": @"iPhone"
            }];
        }
    }
    self.currentIndex = 0;
    self.roundStartTime = nil;
    self.roundEndTime = nil;
    self.tapLocked = NO;
    self.currentAccount = @"";
    [self saveToFile];
}

- (NSString *)exportAccountsText {
    NSMutableString *text = [NSMutableString string];
    for (NSInteger i = 0; i < _accounts.count; i++) {
        NSDictionary *acc = _accounts[i];
        [text appendFormat:@"%ld:%@:%@:%@:%@\n", (long)(i+1),
         acc[@"account"], acc[@"password"], acc[@"fakedID"] ?: @"", acc[@"fakedName"] ?: @"iPhone"];
    }
    return text;
}

- (void)resetProgress {
    self.currentIndex = 0;
    self.roundStartTime = nil;
    self.roundEndTime = nil;
    self.tapLocked = NO;
    self.currentAccount = @"";
    [self saveToFile];
}

#pragma mark - 伪装标识

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
    if (self.serverURL.length == 0) {
        if (completion) completion(NO, @"未设置服务器地址");
        return;
    }
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
    if (self.serverURL.length == 0) {
        if (completion) completion(NO, @"未设置服务器地址");
        return;
    }
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

#pragma mark - 清除设备标识缓存

- (void)clearDeviceIdentifierCache {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSArray *possibleKeys = @[@"deviceId", @"IDFV", @"IDFA", @"deviceIdentifier",
                              @"com.apple.deviceid", @"com.apple.identifier",
                              @"com.yourapp.deviceid", @"udid", @"uuid"];
    for (NSString *key in possibleKeys) {
        [ud removeObjectForKey:key];
    }
    [ud synchronize];

    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
    NSArray *services = @[bundleID,
                          [bundleID stringByAppendingString:@".deviceid"],
                          [bundleID stringByAppendingString:@".identifier"],
                          @"com.apple.deviceid",
                          @"com.apple.identifier"];
    for (NSString *service in services) {
        [self deleteKeychainItemForService:service];
    }
}

- (void)deleteKeychainItemForService:(NSString *)service {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: service,
    };
    SecItemDelete((__bridge CFDictionaryRef)query);
}

#pragma mark - 异常处理

- (void)recordAbnormalWithIndex:(NSInteger)index {
    if (index < 1 || index > self.accounts.count) return;
    NSNumber *idx = @(index);
    [self.abnormalSet addObject:idx];
    if (![self.abnormalOrdered containsObject:idx]) {
        [self.abnormalOrdered addObject:idx];
    }
    [self saveToFile];
}

- (void)clearAbnormal {
    [self.abnormalSet removeAllObjects];
    [self.abnormalOrdered removeAllObjects];
    self.abnormalCurrentIndex = 0;
    self.abnormalMode = NO;
    [self saveToFile];
}

- (NSString *)abnormalString {
    return [self.abnormalOrdered componentsJoinedByString:@","];
}

- (void)setAbnormalFromString:(NSString *)str {
    [self.abnormalSet removeAllObjects];
    [self.abnormalOrdered removeAllObjects];
    for (NSString *part in [str componentsSeparatedByString:@","]) {
        NSString *trimmed = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length == 0) continue;
        NSInteger num = [trimmed integerValue];
        if (num > 0 && num <= self.accounts.count) {
            NSNumber *n = @(num);
            [self.abnormalSet addObject:n];
            if (![self.abnormalOrdered containsObject:n]) {
                [self.abnormalOrdered addObject:n];
            }
        }
    }
    self.abnormalCurrentIndex = 0;
    [self saveToFile];
}

- (void)enterAbnormalMode {
    if (self.abnormalOrdered.count == 0) return;
    self.abnormalMode = YES;
    self.abnormalCurrentIndex = 0;
    [self saveToFile];
}

- (NSDictionary *)nextAbnormalAccount {
    if (!self.abnormalMode || self.abnormalOrdered.count == 0) return nil;
    if (self.abnormalCurrentIndex >= self.abnormalOrdered.count) {
        self.abnormalCurrentIndex = 0;
    }
    NSNumber *indexNum = self.abnormalOrdered[self.abnormalCurrentIndex];
    NSInteger lineNumber = [indexNum integerValue];
    self.currentIndex = lineNumber - 1;
    self.abnormalCurrentIndex++;
    [self saveToFile];
    return self.accounts[lineNumber - 1];
}

- (void)removeLastHandledAbnormal {
    if (self.abnormalCurrentIndex == 0 || self.abnormalOrdered.count == 0) return;
    NSInteger idx = self.abnormalCurrentIndex - 1;
    if (idx < self.abnormalOrdered.count) {
        NSNumber *removed = self.abnormalOrdered[idx];
        [self.abnormalSet removeObject:removed];
        [self.abnormalOrdered removeObjectAtIndex:idx];
        self.abnormalCurrentIndex = idx;
    }
    if (self.abnormalOrdered.count == 0) {
        self.abnormalMode = NO;
        self.abnormalCurrentIndex = 0;
    }
    [self saveToFile];
}

- (BOOL)isAbnormalRemaining {
    return self.abnormalOrdered.count > 0;
}

#pragma mark - Bark 推送

- (void)sendBarkPush:(NSString *)content {
    if (!self.barkEnabled || self.barkKey.length == 0 || content.length == 0) return;
    
    NSString *title = @"易达宝司机";   // 标题固定
    NSString *group = @"易达宝司机";   // 分组固定
    NSString *encodedTitle = [self URLEncodedString:title];
    NSString *encodedContent = [self URLEncodedString:content];
    NSString *encodedGroup = [self URLEncodedString:group];
    
    NSString *urlStr = [NSString stringWithFormat:@"https://api.day.app/%@/%@/%@?group=%@",
                        self.barkKey,
                        encodedTitle,
                        encodedContent,
                        encodedGroup];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return;
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"GET";
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:nil];
    [task resume];
}

// 辅助：更严格的URL编码
- (NSString *)URLEncodedString:(NSString *)str {
    NSCharacterSet *allowed = [NSCharacterSet URLQueryAllowedCharacterSet];
    NSMutableCharacterSet *customAllowed = [allowed mutableCopy];
    [customAllowed removeCharactersInString:@"&?=/+"];
    return [str stringByAddingPercentEncodingWithAllowedCharacters:customAllowed];
}

#pragma mark - 持久化（强化版）

- (NSString *)dataFilePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [paths.firstObject stringByAppendingPathComponent:@"com.youdaibao.config.plist"];
}

- (void)saveToFile {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setInteger:self.currentIndex forKey:@"currentIndex"];
    [ud setBool:self.tapLocked forKey:@"tapLocked"];
    [ud setBool:self.autoLock forKey:@"autoLock"];
    [ud setBool:self.floatLocked forKey:@"floatLocked"];
    [ud setDouble:self.pasteDelay forKey:@"pasteDelay"];
    [ud setDouble:self.passwordDelay forKey:@"passwordDelay"];
    [ud setDouble:self.clickCooldown forKey:@"clickCooldown"];
    [ud setDouble:self.lastClickTime forKey:@"lastClickTime"];
    [ud setBool:self.detailedLog forKey:@"detailedLog"];
    [ud setBool:self.antiDetection forKey:@"antiDetection"];
    [ud setBool:self.lockedMode forKey:@"lockedMode"];
    [ud setObject:self.serverURL ?: @"" forKey:@"serverURL"];
    [ud setObject:self.currentAccount ?: @"" forKey:@"currentAccount"];
    [ud setObject:self.barkKey ?: @"" forKey:@"barkKey"];
    [ud setBool:self.barkEnabled forKey:@"barkEnabled"];
    if (self.roundStartTime) [ud setObject:self.roundStartTime forKey:@"roundStartTime"];
    else [ud removeObjectForKey:@"roundStartTime"];
    if (self.roundEndTime) [ud setObject:self.roundEndTime forKey:@"roundEndTime"];
    else [ud removeObjectForKey:@"roundEndTime"];
    [ud setObject:NSStringFromCGPoint(self.floatWindowPoint) forKey:@"floatWindowPoint"];

    // 异常列表存储为字符串
    [ud setObject:[self abnormalString] forKey:@"abnormalString"];
    [ud setBool:self.abnormalMode forKey:@"abnormalMode"];

    // 账号列表：仅当有数据时才更新 JSON
    if (_accounts.count > 0) {
        NSError *error;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:_accounts options:0 error:&error];
        if (jsonData) {
            NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            [ud setObject:jsonString forKey:@"accountsJSON"];
        }
    }
    [ud synchronize];

    // 同时写入 plist 备份
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
        @"clickCooldown": @(self.clickCooldown),
        @"lastClickTime": @(self.lastClickTime),
        @"detailedLog": @(self.detailedLog),
        @"antiDetection": @(self.antiDetection),
        @"lockedMode": @(self.lockedMode),
        @"serverURL": self.serverURL ?: @"",
        @"currentAccount": self.currentAccount ?: @"",
        @"barkKey": self.barkKey ?: @"",
        @"barkEnabled": @(self.barkEnabled)
    };
    [data writeToFile:[self dataFilePath] atomically:YES];
}

- (void)loadFromFile {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    self.currentIndex = [ud integerForKey:@"currentIndex"];
    self.tapLocked = [ud boolForKey:@"tapLocked"];
    self.autoLock = [ud boolForKey:@"autoLock"];
    self.floatLocked = [ud boolForKey:@"floatLocked"];
    self.pasteDelay = [ud doubleForKey:@"pasteDelay"];
    self.passwordDelay = [ud doubleForKey:@"passwordDelay"];
    self.clickCooldown = [ud doubleForKey:@"clickCooldown"];
    self.lastClickTime = [ud doubleForKey:@"lastClickTime"];
    self.detailedLog = [ud boolForKey:@"detailedLog"];
    self.antiDetection = [ud boolForKey:@"antiDetection"];
    self.lockedMode = [ud boolForKey:@"lockedMode"];
    self.serverURL = [ud stringForKey:@"serverURL"] ?: @"";
    self.currentAccount = [ud stringForKey:@"currentAccount"] ?: @"";
    self.barkKey = [ud stringForKey:@"barkKey"] ?: @"";
    self.barkEnabled = [ud boolForKey:@"barkEnabled"];
    if ([ud objectForKey:@"roundStartTime"]) self.roundStartTime = [ud objectForKey:@"roundStartTime"];
    else self.roundStartTime = nil;
    if ([ud objectForKey:@"roundEndTime"]) self.roundEndTime = [ud objectForKey:@"roundEndTime"];
    else self.roundEndTime = nil;
    NSString *fpStr = [ud stringForKey:@"floatWindowPoint"];
    if (fpStr) self.floatWindowPoint = CGPointFromString(fpStr);

    // 恢复异常列表
    NSString *abStr = [ud stringForKey:@"abnormalString"];
    if (abStr.length > 0) [self setAbnormalFromString:abStr];
    self.abnormalMode = [ud boolForKey:@"abnormalMode"];

    // 恢复账号列表：优先从 JSON，空则忽略
    BOOL loaded = NO;
    NSString *jsonString = [ud stringForKey:@"accountsJSON"];
    if (jsonString.length > 0) {
        NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
        NSError *error;
        NSArray *jsonArray = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
        if (jsonArray && [jsonArray isKindOfClass:[NSArray class]] && jsonArray.count > 0) {
            _accounts = [jsonArray mutableCopy];
            loaded = YES;
        }
    }

    if (!loaded) {
        NSDictionary *data = [NSDictionary dictionaryWithContentsOfFile:[self dataFilePath]];
        NSArray *arr = data[@"accounts"];
        if (arr && arr.count > 0) {
            _accounts = [arr mutableCopy];
            loaded = YES;
        }
    }

    if (!loaded) {
        _accounts = [NSMutableArray array];
    }

    // 兼容旧数据（补全 fakedID/fakedName）
    BOOL modified = NO;
    for (NSMutableDictionary *acc in _accounts) {
        if (!acc[@"fakedID"]) {
            acc[@"fakedID"] = [self generateFakedIDForAccount:acc[@"account"]];
            modified = YES;
        }
        if (!acc[@"fakedName"]) {
            acc[@"fakedName"] = @"iPhone";
            modified = YES;
        }
    }
    if (modified) [self saveToFile];
    self.currentRoundRecords = [NSMutableArray array];
}

@end