#import "LocationFaker.h"
#import "AccountManager.h"
#import "FloatWindow.h"
#import <objc/runtime.h>

@interface LocationFavoritesVC : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITextField *nameField, *latField, *lonField, *noteField;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *dataSource;
@end

// ========== 静态变量 ==========
static BOOL enabled = NO;
static CLLocationCoordinate2D fakedCoord = {37.3349, -122.0093};
static NSInteger selectedFavoriteIndex = -1; // -1 表示无匹配

// 持久化键
static NSString * const kEnabledKey = @"LocationFakerEnabled";
static NSString * const kLatitudeKey = @"LocationFakerLatitude";
static NSString * const kLongitudeKey = @"LocationFakerLongitude";
static NSString * const kSelectedIndexKey = @"LocationFakerSelectedIndex";

static void loadState() {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud objectForKey:kEnabledKey]) {
        enabled = [ud boolForKey:kEnabledKey];
    }
    if ([ud objectForKey:kLatitudeKey] && [ud objectForKey:kLongitudeKey]) {
        fakedCoord = CLLocationCoordinate2DMake([ud doubleForKey:kLatitudeKey], [ud doubleForKey:kLongitudeKey]);
    }
    if ([ud objectForKey:kSelectedIndexKey]) {
        selectedFavoriteIndex = [ud integerForKey:kSelectedIndexKey];
        // 校验索引有效性：如果索引超出当前收藏数量或坐标不匹配，则设为 -1
        NSArray *favs = [LocationFaker favoriteNames];
        if (selectedFavoriteIndex >= 0 && selectedFavoriteIndex < favs.count) {
            // 进一步验证坐标是否匹配
            NSArray *favList = [[NSUserDefaults standardUserDefaults] objectForKey:@"locationFavorites"] ?: @[];
            NSDictionary *item = favList[selectedFavoriteIndex];
            double lat = [item[@"lat"] doubleValue];
            double lon = [item[@"lon"] doubleValue];
            if (fabs(lat - fakedCoord.latitude) > 0.000001 || fabs(lon - fakedCoord.longitude) > 0.000001) {
                selectedFavoriteIndex = -1; // 坐标已变，清除选择
            }
        } else {
            selectedFavoriteIndex = -1;
        }
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

// 同步索引：根据当前坐标在收藏列表中查找匹配项，更新 selectedFavoriteIndex
static void syncIndexWithCurrentCoordinate() {
    NSArray *favList = [[NSUserDefaults standardUserDefaults] objectForKey:@"locationFavorites"] ?: @[];
    selectedFavoriteIndex = -1;
    for (NSInteger i = 0; i < favList.count; i++) {
        NSDictionary *item = favList[i];
        double lat = [item[@"lat"] doubleValue];
        double lon = [item[@"lon"] doubleValue];
        if (fabs(lat - fakedCoord.latitude) < 0.000001 && fabs(lon - fakedCoord.longitude) < 0.000001) {
            selectedFavoriteIndex = i;
            break;
        }
    }
    saveState();
}

// ========== Hook ==========
static CLLocationCoordinate2D (*orig_coordinate)(id self, SEL _cmd);
static CLLocationCoordinate2D replaced_coordinate(id self, SEL _cmd) {
    if (enabled) {
        NSString *name = [LocationFaker currentName];
        dispatch_async(dispatch_get_main_queue(), ^{
            [FloatWindow showToast:[NSString stringWithFormat:@"定位已伪装 %@", name]];
        });
        if ([AccountManager shared].detailedLog) {
            NSString *msg = [NSString stringWithFormat:@"【定位伪装】%@", name];
            [[AccountManager shared] appendLog:msg];
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
+ (void)setEnabled:(BOOL)en {
    enabled = en;
    saveState();
}

+ (CLLocationCoordinate2D)currentCoordinate { return fakedCoord; }
+ (void)setCoordinate:(CLLocationCoordinate2D)coord {
    fakedCoord = coord;
    syncIndexWithCurrentCoordinate(); // 更新选中索引
    saveState();
}

+ (NSString *)currentName {
    if (selectedFavoriteIndex >= 0) {
        NSArray *favList = [[NSUserDefaults standardUserDefaults] objectForKey:@"locationFavorites"] ?: @[];
        if (selectedFavoriteIndex < favList.count) {
            NSDictionary *item = favList[selectedFavoriteIndex];
            double lat = [item[@"lat"] doubleValue];
            double lon = [item[@"lon"] doubleValue];
            if (fabs(lat - fakedCoord.latitude) < 0.000001 && fabs(lon - fakedCoord.longitude) < 0.000001) {
                return item[@"name"] ?: @"未知";
            }
        }
        selectedFavoriteIndex = -1; // 数据不一致，重置
        saveState();
    }
    return [NSString stringWithFormat:@"%.6f, %.6f", fakedCoord.latitude, fakedCoord.longitude];
}

+ (NSArray *)favoriteNames {
    NSArray *favList = [[NSUserDefaults standardUserDefaults] objectForKey:@"locationFavorites"] ?: @[];
    NSMutableArray *names = [NSMutableArray array];
    for (NSDictionary *item in favList) {
        [names addObject: item[@"name"] ?: @"未命名"];
    }
    return names;
}

+ (NSInteger)selectedFavoriteIndex { return selectedFavoriteIndex; }

+ (UIViewController *)favoritesViewController {
    LocationFavoritesVC *vc = [[LocationFavoritesVC alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    return nav;
}

@end

// ========== 收藏管理控制器（已删除“应用坐标”按钮） ==========
@implementation LocationFavoritesVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"收藏坐标";
    self.view.backgroundColor = [UIColor whiteColor];
    self.dataSource = [NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] objectForKey:@"locationFavorites"] ?: @[]];
    
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                          target:self
                                                                                          action:@selector(doneAction)];
    
    CGFloat margin = 15;
    CGFloat y = 100;
    CGFloat fieldH = 36;
    CGFloat labelW = 60;
    
    // 名称
    UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, y, labelW, fieldH)];
    nameLabel.text = @"名称"; nameLabel.textColor = [UIColor blackColor];
    [self.view addSubview:nameLabel];
    _nameField = [[UITextField alloc] initWithFrame:CGRectMake(margin + labelW, y, self.view.bounds.size.width - margin*2 - labelW, fieldH)];
    _nameField.placeholder = @"可选"; _nameField.borderStyle = UITextBorderStyleRoundedRect; _nameField.textColor = [UIColor blackColor];
    [self.view addSubview:_nameField];
    y += fieldH + 8;
    
    // 纬度/经度
    UILabel *latLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, y, labelW, fieldH)];
    latLabel.text = @"纬度"; latLabel.textColor = [UIColor blackColor];
    [self.view addSubview:latLabel];
    _latField = [[UITextField alloc] initWithFrame:CGRectMake(margin + labelW, y, (self.view.bounds.size.width - margin*2 - labelW - 10)/2, fieldH)];
    _latField.placeholder = @"纬度"; _latField.borderStyle = UITextBorderStyleRoundedRect; _latField.keyboardType = UIKeyboardTypeDecimalPad; _latField.textColor = [UIColor blackColor];
    [self.view addSubview:_latField];
    
    _lonField = [[UITextField alloc] initWithFrame:CGRectMake(margin + labelW + (self.view.bounds.size.width - margin*2 - labelW - 10)/2 + 10, y, (self.view.bounds.size.width - margin*2 - labelW - 10)/2, fieldH)];
    _lonField.placeholder = @"经度"; _lonField.borderStyle = UITextBorderStyleRoundedRect; _lonField.keyboardType = UIKeyboardTypeDecimalPad; _lonField.textColor = [UIColor blackColor];
    [self.view addSubview:_lonField];
    y += fieldH + 8;
    
    // 备注
    UILabel *noteLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, y, labelW, fieldH)];
    noteLabel.text = @"备注"; noteLabel.textColor = [UIColor blackColor];
    [self.view addSubview:noteLabel];
    _noteField = [[UITextField alloc] initWithFrame:CGRectMake(margin + labelW, y, self.view.bounds.size.width - margin*2 - labelW, fieldH)];
    _noteField.placeholder = @"可选"; _noteField.borderStyle = UITextBorderStyleRoundedRect; _noteField.textColor = [UIColor blackColor];
    [self.view addSubview:_noteField];
    y += fieldH + 12;
    
    // 只保留“收藏当前”按钮
    UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    saveBtn.frame = CGRectMake(margin, y, self.view.bounds.size.width - margin*2, 36);
    [saveBtn setTitle:@"收藏当前" forState:UIControlStateNormal];
    [saveBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    saveBtn.backgroundColor = [UIColor systemGreenColor]; saveBtn.layer.cornerRadius = 6;
    [saveBtn addTarget:self action:@selector(saveFavorite) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:saveBtn];
    y += 44;
    
    // 收藏列表（选择后直接应用坐标并关闭页面）
    _tableView = [[UITableView alloc] initWithFrame:CGRectMake(margin, y, self.view.bounds.size.width - margin*2, self.view.bounds.size.height - y - 20) style:UITableViewStylePlain];
    _tableView.backgroundColor = [UIColor whiteColor]; _tableView.separatorColor = [UIColor lightGrayColor];
    _tableView.delegate = self; _tableView.dataSource = self; _tableView.rowHeight = 50;
    [self.view addSubview:_tableView];
}

- (void)doneAction {
    self.view.window.hidden = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"LocationFavoritesDismissed" object:nil];
}

- (void)saveFavorite {
    double lat = [_latField.text doubleValue];
    double lon = [_lonField.text doubleValue];
    if (lat == 0 && lon == 0) return;
    NSString *name = _nameField.text.length ? _nameField.text : [NSString stringWithFormat:@"%.4f,%.4f", lat, lon];
    NSString *note = _noteField.text ?: @"";
    NSDictionary *item = @{@"name": name, @"lat": @(lat), @"lon": @(lon), @"note": note};
    [self.dataSource addObject:item];
    [[NSUserDefaults standardUserDefaults] setObject:self.dataSource forKey:@"locationFavorites"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [_tableView reloadData];
    _nameField.text = @""; _latField.text = @""; _lonField.text = @""; _noteField.text = @"";
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
    // 关闭页面
    [self doneAction];
}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { return YES; }
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [self.dataSource removeObjectAtIndex:indexPath.row];
        [[NSUserDefaults standardUserDefaults] setObject:self.dataSource forKey:@"locationFavorites"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        // 如果删除的是当前选中的定位，需要更新状态
        if (indexPath.row == [LocationFaker selectedFavoriteIndex]) {
            [LocationFaker setCoordinate:CLLocationCoordinate2DMake(0, 0)]; // 无效坐标，将导致索引重置
        }
    }
}
@end