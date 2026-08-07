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

// ========== 收藏管理控制器 ==========
@implementation LocationFavoritesVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"虚拟定位";
    self.view.backgroundColor = [UIColor whiteColor];
    self.dataSource = [NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] objectForKey:@"locationFavorites"] ?: @[]];
    
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                          target:self
                                                                                          action:@selector(doneAction)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                           target:self
                                                                                           action:@selector(addNewFavorite)];
    
    CGFloat margin = 15;
    CGFloat y = 100;
    CGFloat fieldH = 30;
    CGFloat labelW = 60;
    
    // 启用开关
    UILabel *enableLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, y, 50, fieldH)];
    enableLabel.text = @"启用"; enableLabel.textColor = [UIColor blackColor];
    [self.view addSubview:enableLabel];
    _enableSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(margin + 55, y-2, 51, 31)];
    _enableSwitch.on = [LocationFaker isEnabled];
    [self.view addSubview:_enableSwitch];
    
    _currentLocLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin + 120, y, self.view.bounds.size.width - margin - 120 - margin, fieldH)];
    _currentLocLabel.text = [NSString stringWithFormat:@"当前: %@", [LocationFaker currentName]];
    _currentLocLabel.font = [UIFont systemFontOfSize:13];
    _currentLocLabel.textColor = [UIColor darkGrayColor];
    [self.view addSubview:_currentLocLabel];
    y += fieldH + 15;
    
    // 名称
    UILabel *nameLb = [[UILabel alloc] initWithFrame:CGRectMake(margin, y, labelW, fieldH)];
    nameLb.text = @"名称"; nameLb.textColor = [UIColor blackColor];
    [self.view addSubview:nameLb];
    _nameField = [[UITextField alloc] initWithFrame:CGRectMake(margin+labelW, y, self.view.bounds.size.width - margin*2 - labelW, fieldH)];
    _nameField.placeholder = @"可选"; _nameField.borderStyle = UITextBorderStyleRoundedRect; _nameField.textColor = [UIColor blackColor];
    [self.view addSubview:_nameField];
    y += fieldH + 8;
    
    // 纬度 / 经度
    UILabel *latLb = [[UILabel alloc] initWithFrame:CGRectMake(margin, y, labelW, fieldH)];
    latLb.text = @"纬度"; latLb.textColor = [UIColor blackColor];
    [self.view addSubview:latLb];
    _latField = [[UITextField alloc] initWithFrame:CGRectMake(margin+labelW, y, (self.view.bounds.size.width - margin*2 - labelW - 10)/2, fieldH)];
    _latField.placeholder = @"纬度"; _latField.borderStyle = UITextBorderStyleRoundedRect; _latField.keyboardType = UIKeyboardTypeDecimalPad; _latField.textColor = [UIColor blackColor];
    [self.view addSubview:_latField];
    _lonField = [[UITextField alloc] initWithFrame:CGRectMake(margin+labelW + (self.view.bounds.size.width - margin*2 - labelW - 10)/2 + 10, y, (self.view.bounds.size.width - margin*2 - labelW - 10)/2, fieldH)];
    _lonField.placeholder = @"经度"; _lonField.borderStyle = UITextBorderStyleRoundedRect; _lonField.keyboardType = UIKeyboardTypeDecimalPad; _lonField.textColor = [UIColor blackColor];
    [self.view addSubview:_lonField];
    y += fieldH + 8;
    
    // 备注
    UILabel *noteLb = [[UILabel alloc] initWithFrame:CGRectMake(margin, y, labelW, fieldH)];
    noteLb.text = @"备注"; noteLb.textColor = [UIColor blackColor];
    [self.view addSubview:noteLb];
    _noteField = [[UITextField alloc] initWithFrame:CGRectMake(margin+labelW, y, self.view.bounds.size.width - margin*2 - labelW, fieldH)];
    _noteField.placeholder = @"可选"; _noteField.borderStyle = UITextBorderStyleRoundedRect; _noteField.textColor = [UIColor blackColor];
    [self.view addSubview:_noteField];
    y += fieldH + 12;
    
    // 操作按钮：保存当前（新增/更新）、清空输入框
    UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    saveBtn.frame = CGRectMake(margin, y, (self.view.bounds.size.width - margin*2 - 10)/2, 36);
    [saveBtn setTitle:@"保存到列表" forState:UIControlStateNormal];
    [saveBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    saveBtn.backgroundColor = [UIColor systemGreenColor]; saveBtn.layer.cornerRadius = 6;
    [saveBtn addTarget:self action:@selector(saveFavorite) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:saveBtn];
    
    UIButton *clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    clearBtn.frame = CGRectMake(margin + (self.view.bounds.size.width - margin*2 - 10)/2 + 10, y, (self.view.bounds.size.width - margin*2 - 10)/2, 36);
    [clearBtn setTitle:@"清空输入" forState:UIControlStateNormal];
    [clearBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    clearBtn.backgroundColor = [UIColor systemGrayColor]; clearBtn.layer.cornerRadius = 6;
    [clearBtn addTarget:self action:@selector(clearFields) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:clearBtn];
    y += 44;
    
    // 列表
    _tableView = [[UITableView alloc] initWithFrame:CGRectMake(margin, y, self.view.bounds.size.width - margin*2, self.view.bounds.size.height - y - 20) style:UITableViewStylePlain];
    _tableView.backgroundColor = [UIColor whiteColor];
    _tableView.separatorColor = [UIColor lightGrayColor];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.rowHeight = 50;
    [self.view addSubview:_tableView];
}

- (void)doneAction {
    // 如果输入框中有有效坐标，则应用
    double lat = [_latField.text doubleValue];
    double lon = [_lonField.text doubleValue];
    if (lat != 0 || lon != 0) {
        [LocationFaker setCoordinate:CLLocationCoordinate2DMake(lat, lon)];
    }
    // 启用状态根据开关
    [LocationFaker setEnabled:_enableSwitch.on];
    
    self.view.window.hidden = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"LocationFavoritesDismissed" object:nil];
}

- (void)addNewFavorite {
    [self clearFields];
}

- (void)saveFavorite {
    double lat = [_latField.text doubleValue];
    double lon = [_lonField.text doubleValue];
    if (lat == 0 && lon == 0) return;
    NSString *name = _nameField.text.length ? _nameField.text : [NSString stringWithFormat:@"%.4f,%.4f", lat, lon];
    NSString *note = _noteField.text ?: @"";
    NSDictionary *item = @{@"name": name, @"lat": @(lat), @"lon": @(lon), @"note": note};
    
    // 检查是否编辑已有项：若名称和经纬度与列表中某项相同，则更新该项
    NSInteger existingIndex = -1;
    for (NSInteger i = 0; i < self.dataSource.count; i++) {
        NSDictionary *d = self.dataSource[i];
        if ([d[@"name"] isEqualToString:name] || (fabs([d[@"lat"] doubleValue]-lat)<0.000001 && fabs([d[@"lon"] doubleValue]-lon)<0.000001)) {
            existingIndex = i;
            break;
        }
    }
    if (existingIndex >= 0) {
        self.dataSource[existingIndex] = item;
    } else {
        [self.dataSource addObject:item];
    }
    [[NSUserDefaults standardUserDefaults] setObject:self.dataSource forKey:@"locationFavorites"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [_tableView reloadData];
    [self clearFields];
}

- (void)clearFields {
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
    _nameField.text = item[@"name"];
    _latField.text = [item[@"lat"] stringValue];
    _lonField.text = [item[@"lon"] stringValue];
    _noteField.text = item[@"note"];
    // 不自动应用，等待用户点击完成
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { return YES; }
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [self.dataSource removeObjectAtIndex:indexPath.row];
        [[NSUserDefaults standardUserDefaults] setObject:self.dataSource forKey:@"locationFavorites"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        // 如果删除的是当前选中，清空坐标
        if (indexPath.row == [LocationFaker selectedFavoriteIndex]) {
            [LocationFaker setCoordinate:CLLocationCoordinate2DMake(0, 0)];
        }
    }
}
@end