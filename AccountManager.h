#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@interface AccountManager : NSObject

+ (instancetype)shared;

@property (nonatomic, strong, readonly) NSArray<NSDictionary *> *accounts;
@property (nonatomic, assign) NSInteger currentIndex;

// 定位配置
@property (nonatomic, assign) CGPoint accountPoint;
@property (nonatomic, assign) CGPoint passwordPoint;
@property (nonatomic, assign) NSTimeInterval delaySeconds;

- (NSDictionary *)nextAccount;
- (void)updateAccountsWithText:(NSString *)text;
- (NSString *)exportAccountsText;
- (void)importFromClipboard;
- (void)exportToClipboard;

// 公开保存方法，供FloatWindow调用
- (void)saveToFile;

@end