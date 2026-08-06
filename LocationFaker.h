#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <UIKit/UIKit.h>

@interface LocationFaker : NSObject

+ (void)install;
+ (BOOL)isEnabled;
+ (void)setEnabled:(BOOL)enabled;
+ (CLLocationCoordinate2D)currentCoordinate;
+ (void)setCoordinate:(CLLocationCoordinate2D)coord;
+ (NSString *)currentName;                     // 当前坐标对应的收藏名称，若无则返回坐标字符串

// 收藏管理
+ (UIViewController *)favoritesViewController;

@end