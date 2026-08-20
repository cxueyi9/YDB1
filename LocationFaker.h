#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <UIKit/UIKit.h>

// 基站信息结构
typedef struct {
    NSInteger mcc;
    NSInteger mnc;
    NSInteger lac;
    NSInteger cid;
    BOOL hasBaseStation; // 是否包含有效基站数据
} FakeBaseStation;

@interface LocationFaker : NSObject

+ (void)install;
+ (BOOL)isEnabled;
+ (void)setEnabled:(BOOL)enabled;
+ (CLLocationCoordinate2D)currentCoordinate;
+ (void)setCoordinate:(CLLocationCoordinate2D)coord;
+ (void)setBaseStation:(FakeBaseStation)bs;
+ (FakeBaseStation)currentBaseStation;
+ (BOOL)hasBaseStation;

+ (NSString *)currentName;
+ (NSArray *)favoriteNames;
+ (NSInteger)selectedFavoriteIndex;
+ (UIViewController *)favoritesViewController;

// 获取真实位置和基站（用于一键获取）
+ (void)requestRealLocationAndBaseStationWithCompletion:(void(^)(CLLocationCoordinate2D coord, FakeBaseStation bs))completion;

+ (NSArray *)favoriteList;          // 返回完整收藏数组
+ (void)switchToNextFavorite;       // 切换到下一个收藏定位

@end