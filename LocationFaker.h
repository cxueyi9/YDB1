#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <UIKit/UIKit.h>

@interface LocationFaker : NSObject

+ (void)install;
+ (BOOL)isEnabled;
+ (void)setEnabled:(BOOL)enabled;
+ (CLLocationCoordinate2D)currentCoordinate;
+ (void)setCoordinate:(CLLocationCoordinate2D)coord;

// 返回收藏管理页面（UINavigationController）
+ (UIViewController *)favoritesViewController;

@end