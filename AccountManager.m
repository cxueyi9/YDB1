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
    NSString *text = [self exportAccountsText];
    [UIPasteboard generalPasteboard].string = text;
}

#pragma mark - 文件持久化

- (NSString *)dataFilePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docDir = paths.firstObject;
    return [docDir stringByAppendingPathComponent:@"com.youdaibao.accounts.plist"];
}

- (void)saveToFile {
    NSMutableArray *arr = [NSMutableArray array];
    for (NSDictionary *d in _accounts) {
        [arr addObject:d];
    }
    NSDictionary *data = @{
        @"accounts": arr,
        @"currentIndex": @(self.currentIndex)
    };
    [data writeToFile:[self dataFilePath] atomically:YES];
}

- (void)loadFromFile {
    NSDictionary *data = [NSDictionary dictionaryWithContentsOfFile:[self dataFilePath]];
    if (data) {
        NSArray *arr = data[@"accounts"];
        if (arr) {
            _accounts = [arr mutableCopy];
        }
        NSNumber *idx = data[@"currentIndex"];
        self.currentIndex = idx ? [idx integerValue] : 0;
    }
}

@end