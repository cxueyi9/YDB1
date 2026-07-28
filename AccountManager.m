#import "AccountManager.h"
#import <UIKit/UIKit.h>

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
    }
    return self;
}

- (NSArray<NSDictionary *> *)accounts {
    return [_accounts copy];
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
        NSArray *parts = [trimmed componentsSeparatedByString:@"|"];
        if (parts.count == 2) {
            [_accounts addObject:@{@"account": parts[0], @"password": parts[1]}];
        }
    }
    self.currentIndex = 0;
    [self saveToFile];
}

- (NSString *)exportAccountsText {
    NSMutableString *text = [NSMutableString string];
    for (NSDictionary *acc in _accounts) {
        [text appendFormat:@"%@|%@\n", acc[@"account"], acc[@"password"]];
    }
    return text;
}

- (void)importFromClipboard {
    NSString *pasteText = [UIPasteboard generalPasteboard].string;
    if (pasteText.length > 0) {
        [self updateAccountsWithText:pasteText];
    }
}

- (void)exportToClipboard {
    [UIPasteboard generalPasteboard].string = [self exportAccountsText];
}

#pragma mark - 日志

- (NSString *)logFilePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [paths.firstObject stringByAppendingPathComponent:@"fill_log.txt"];
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
        @"passwordDelay": @(self.passwordDelay)
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
    }
}

@end