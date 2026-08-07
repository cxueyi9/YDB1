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
+ (NSArray *)favoriteNames;                   // 所有收藏名称（用于选择框）
+ (NSInteger)selectedFavoriteIndex;           // 当前选中的收藏索引（-1 表示无匹配）
+ (UIViewController *)favoritesViewController; // 收藏管理页面（独立窗口）

@end