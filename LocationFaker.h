#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@interface LocationFaker : NSObject

+ (void)install;
+ (BOOL)isEnabled;
+ (void)setEnabled:(BOOL)enabled;
+ (CLLocationCoordinate2D)currentCoordinate;
+ (void)setCoordinate:(CLLocationCoordinate2D)coord;

// 直接显示收藏管理窗口
+ (void)showFavoritesWindow;

@end