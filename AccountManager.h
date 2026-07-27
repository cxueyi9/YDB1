#import <Foundation/Foundation.h>

@interface AccountManager : NSObject

+ (instancetype)shared;

@property (nonatomic, strong, readonly) NSArray<NSDictionary *> *accounts;
@property (nonatomic, assign) NSInteger currentIndex;

- (NSDictionary *)nextAccount;
- (void)updateAccountsWithText:(NSString *)text;
- (NSString *)exportAccountsText;                     // 导出格式化文本
- (void)importFromClipboard;                          // 从剪贴板导入
- (void)exportToClipboard;                            // 导出到剪贴板

@end