#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@interface LocationFaker : NSObject

+ (void)install;
+ (BOOL)isEnabled;
+ (void)setEnabled:(BOOL)enabled;
+ (CLLocationCoordinate2D)currentCoordinate;
+ (void)setCoordinate:(CLLocationCoordinate2D)coord;

// 收藏管理，返回一个可直接 present 的 VC
+ (UIViewController *)favoritesViewController;

@end