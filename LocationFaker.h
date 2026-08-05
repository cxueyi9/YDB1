#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@interface LocationFaker : NSObject

+ (void)install;
+ (BOOL)isEnabled;
+ (void)setEnabled:(BOOL)enabled;
+ (CLLocationCoordinate2D)currentCoordinate;
+ (void)setCoordinate:(CLLocationCoordinate2D)coord;

// 返回收藏管理视图控制器（UINavigationController）
+ (UIViewController *)favoritesViewController;

@end