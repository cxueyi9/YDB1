#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <UIKit/UIKit.h>      // 必须导入

@interface LocationFaker : NSObject

+ (void)install;
+ (BOOL)isEnabled;
+ (void)setEnabled:(BOOL)enabled;
+ (CLLocationCoordinate2D)currentCoordinate;
+ (void)setCoordinate:(CLLocationCoordinate2D)coord;

+ (UIViewController *)favoritesViewController;

@end