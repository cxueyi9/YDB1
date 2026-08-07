#import "LocationFaker.h"
#import "AccountManager.h"
#import "FloatWindow.h"
#import <objc/runtime.h>

@interface LocationFavoritesVC : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UISwitch *enableSwitch;
@property (nonatomic, strong) UILabel *currentLocLabel;
@property (nonatomic, strong) UITextField *nameField, *latField, *lonField, *noteField;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *dataSource;
@end

// ========== 静态变量 ==========
static BOOL enabled = NO;
static CLLocationCoordinate2D fakedCoord = {37.3349, -122.0093};
static NSInteger selectedFavoriteIndex = -1;

static NSString * const kEnabledKey = @"LocationFakerEnabled";
static NSString * const kLatitudeKey = @"LocationFakerLatitude";
static NSString * const kLongitudeKey = @"LocationFakerLongitude";
static NSString * const kSelectedIndexKey = @"LocationFakerSelectedIndex";

static void loadState() {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud objectForKey:kEnabledKey]) enabled = [ud boolForKey:kEnabledKey];
    if ([ud objectForKey:kLatitudeKey] && [ud objectForKey:kLongitudeKey]) {
        fakedCoord = CLLocationCoordinate2DMake([ud doubleForKey:kLatitudeKey], [ud doubleForKey:kLongitudeKey]);
    }
    if ([ud objectForKey:kSelectedIndexKey]) {
        selectedFavoriteIndex = [ud integerForKey:kSelectedIndexKey];
        NSArray *favs = [LocationFaker favoriteNames];
        if (selectedFavoriteIndex < 0 || selectedFavoriteIndex >= favs.count) selectedFavoriteIndex = -1;
    }
}

static void saveState() {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:enabled forKey:kEnabledKey];
    [ud setDouble:fakedCoord.latitude forKey:kLatitudeKey];
    [ud setDouble:fakedCoord.longitude forKey:kLongitudeKey];
    [ud setInteger:selectedFavoriteIndex forKey:kSelectedIndexKey];
    [ud synchronize];
}

static void syncIndexWithCurrentCoordinate() {
    NSArray *favList = [[NSUserDefaults standardUserDefaults] objectForKey:@"locationFavorites"] ?: @[];
    selectedFavoriteIndex = -1;
    for (NSInteger i = 0; i < favList.count; i++) {
        NSDictionary *item = favList[i];
        if (fabs([item[@"lat"] doubleValue] - fakedCoord.latitude) < 0.000001 &&
            fabs([item[@"lon"] doubleValue] - fakedCoord.longitude) < 0.000001) {
            selectedFavoriteIndex = i;
            break;
        }
    }
    saveState();
}

// Hook
static CLLocationCoordinate2D (*orig_coordinate)(id self, SEL _cmd);
static CLLocationCoordinate2D replaced_coordinate(id self, SEL _cmd) {
    if (enabled) {
        NSString *name = [LocationFaker currentName];
        dispatch_async(dispatch_get_main_queue(), ^{
            [FloatWindow showToast:[NSString stringWithFormat:@"定位已伪装 %@", name]];
        });
        if ([AccountManager shared].detailedLog) {
            [[AccountManager shared] appendLog:[NSString stringWithFormat:@"【定位伪装】%@", name]];
        }
        return fakedCoord;
    }
    return orig_coordinate(self, _cmd);
}

@implementation LocationFaker

+ (void)install {
    loadState();
    Method orig = class_getInstanceMethod([CLLocation class], @selector(coordinate));
    if (orig) {
        orig_coordinate = (CLLocationCoordinate2D (*)(id, SEL))method_getImplementation(orig);
        method_setImplementation(orig, (IMP)replaced_coordinate);
    }
}

+ (BOOL)isEnabled { return enabled; }
+ (void)setEnabled:(BOOL)en { enabled = en; saveState(); }

+ (CLLocationCoordinate2D)currentCoordinate { return fakedCoord; }
+ (void)setCoordinate:(CLLocationCoordinate2D)coord {
    fakedCoord = coord;
    syncIndexWithCurrentCoordinate();
    saveState();
}

+ (NSString *)currentName {
    NSArray *favList = [[NSUserDefaults standardUserDefaults] objectForKey:@"locationFavorites"] ?: @[];
    if (selectedFavoriteIndex >= 0 && selectedFavoriteIndex < favList.count) {
        NSDictionary *item = favList[selectedFavoriteIndex];
        if (fabs([item[@"lat"] doubleValue] - fakedCoord.latitude) < 0.000001 &&
            fabs([item[@"lon"] doubleValue] - fakedCoord.longitude) < 0.000001) {
            return item[@"name"];
        }
    }
    return [NSString stringWithFormat:@"%.6f, %.6f", fakedCoord.latitude, fakedCoord.longitude];
}

+ (NSArray *)favoriteNames {
    NSArray *favList = [[NSUserDefaults standardUserDefaults] objectForKey:@"locationFavorites"] ?: @[];
    NSMutableArray *names = [NSMutableArray array];
    for (NSDictionary *item in favList) [names addObject:item[@"name"] ?: @"未命名"];
    return names;
}

+ (NSInteger)selectedFavoriteIndex { return selectedFavoriteIndex; }

+ (UIViewController *)favoritesViewController {
    LocationFavoritesVC *vc = [[LocationFavoritesVC alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    return nav;
}

@end

// ========== 收藏管理控制器（增加开关和标签） ==========
@implementation LocationFavoritesVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"虚拟定位";
    self.view.backgroundColor = [UIColor whiteColor];
    self.dataSource = [NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] objectForKey:@"locationFavorites"] ?: @[]];
    
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                          target:self
                                                                                          action:@selector(doneAction)];
    CGFloat margin = 15;
    CGFloat y = 100;
    CGFloat fieldH = 30;
    
    // 启用开关
    UILabel *enableLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, y, 50, fieldH)];
    enableLabel.text = @"启用"; enableLabel.textColor = [UIColor blackColor];
    [self.view addSubview:enableLabel];
    _enableSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(margin + 55, y-2, 51, 31)];
    _enableSwitch.on = [LocationFaker isEnabled];
    [_enableSwitch addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_enableSwitch];
    
    // 当前定位标签
    _currentLocLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin + 120, y, self.view.bounds.size.width - margin - 120 - margin, fieldH)];
    _currentLocLabel.text = [NSString stringWithFormat:@"当前: %@", [LocationFaker currentName]];
    _currentLocLabel.font = [UIFont systemFontOfSize:13];
    _currentLocLabel.textColor = [UIColor darkGrayColor];
    [self.view addSubview:_currentLocLabel];
    y += fieldH + 15;
    
    // 收藏列表（占据下方空间）
    _tableView = [[UITableView alloc] initWithFrame:CGRectMake(margin, y, self.view.bounds.size.width - margin*2, self.view.bounds.size.height - y - 20) style:UITableViewStylePlain];
    _tableView.backgroundColor = [UIColor whiteColor];
    _tableView.separatorColor = [UIColor lightGrayColor];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.rowHeight = 50;
    [self.view addSubview:_tableView];
    
    // 不再需要输入框和按钮，列表选择即可
}

- (void)switchChanged:(UISwitch *)sender {
    [LocationFaker setEnabled:sender.on];
}

- (void)doneAction {
    self.view.window.hidden = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"LocationFavoritesDismissed" object:nil];
}

#pragma mark - TableView
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.dataSource.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Cell"];
        cell.textLabel.textColor = [UIColor blackColor];
        cell.detailTextLabel.textColor = [UIColor darkGrayColor];
        cell.backgroundColor = [UIColor whiteColor];
    }
    NSDictionary *item = self.dataSource[indexPath.row];
    cell.textLabel.text = item[@"name"];
    cell.detailTextLabel.text = item[@"note"] ?: @"";
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = self.dataSource[indexPath.row];
    double lat = [item[@"lat"] doubleValue], lon = [item[@"lon"] doubleValue];
    [LocationFaker setCoordinate:CLLocationCoordinate2DMake(lat, lon)];
    [LocationFaker setEnabled:YES];
    // 更新界面
    _enableSwitch.on = YES;
    _currentLocLabel.text = [NSString stringWithFormat:@"当前: %@", item[@"name"]];
    // 自动关闭
    [self doneAction];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { return YES; }
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [self.dataSource removeObjectAtIndex:indexPath.row];
        [[NSUserDefaults standardUserDefaults] setObject:self.dataSource forKey:@"locationFavorites"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        if (indexPath.row == [LocationFaker selectedFavoriteIndex]) {
            [LocationFaker setCoordinate:CLLocationCoordinate2DMake(0, 0)];
        }
    }
}
@end