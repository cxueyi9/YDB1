#import "LocationFaker.h"
#import "AccountManager.h"
#import "FloatWindow.h"
#import <objc/runtime.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>

@interface LocationFavoritesVC : UIViewController <UITableViewDelegate, UITableViewDataSource, CLLocationManagerDelegate>
@property (nonatomic, strong) UISwitch *enableSwitch;
@property (nonatomic, strong) UILabel *currentLocLabel;
@property (nonatomic, strong) UITextField *nameField, *latField, *lonField;
@property (nonatomic, strong) UITextField *mccField, *mncField, *lacField, *cidField;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *dataSource;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, copy) void (^realInfoCompletion)(CLLocationCoordinate2D coord, FakeBaseStation bs);
- (void)startRealInfoFetch;
@end

// ========== 静态变量 ==========
static BOOL enabled = NO;
static CLLocationCoordinate2D fakedCoord = {37.3349, -122.0093};
static FakeBaseStation fakedBS = {0,0,0,0, NO};
static NSInteger selectedFavoriteIndex = -1;

static NSString * const kEnabledKey = @"LocationFakerEnabled";
static NSString * const kLatitudeKey = @"LocationFakerLatitude";
static NSString * const kLongitudeKey = @"LocationFakerLongitude";
static NSString * const kMCCKey = @"LocationFakerMCC";
static NSString * const kMNCKey = @"LocationFakerMNC";
static NSString * const kLACKey = @"LocationFakerLAC";
static NSString * const kCIDKey = @"LocationFakerCID";
static NSString * const kHasBSKey = @"LocationFakerHasBS";
static NSString * const kSelectedIndexKey = @"LocationFakerSelectedIndex";

static void loadState() {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud objectForKey:kEnabledKey]) enabled = [ud boolForKey:kEnabledKey];
    if ([ud objectForKey:kLatitudeKey] && [ud objectForKey:kLongitudeKey]) {
        fakedCoord = CLLocationCoordinate2DMake([ud doubleForKey:kLatitudeKey], [ud doubleForKey:kLongitudeKey]);
    }
    if ([ud objectForKey:kHasBSKey]) {
        fakedBS.hasBaseStation = [ud boolForKey:kHasBSKey];
        fakedBS.mcc = [ud integerForKey:kMCCKey];
        fakedBS.mnc = [ud integerForKey:kMNCKey];
        fakedBS.lac = [ud integerForKey:kLACKey];
        fakedBS.cid = [ud integerForKey:kCIDKey];
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
    [ud setBool:fakedBS.hasBaseStation forKey:kHasBSKey];
    [ud setInteger:fakedBS.mcc forKey:kMCCKey];
    [ud setInteger:fakedBS.mnc forKey:kMNCKey];
    [ud setInteger:fakedBS.lac forKey:kLACKey];
    [ud setInteger:fakedBS.cid forKey:kCIDKey];
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

// ========== Hook CLLocation coordinate ==========
static CLLocationCoordinate2D (*orig_coordinate)(id self, SEL _cmd);
static CLLocationCoordinate2D replaced_coordinate(id self, SEL _cmd) {
    if (enabled) {
        NSString *name = [LocationFaker currentName];
        NSString *hint = fakedBS.hasBaseStation ? @"基站信息已伪装" : @"GPS定位已伪装";
        dispatch_async(dispatch_get_main_queue(), ^{
            [FloatWindow showToast:[NSString stringWithFormat:@"%@ %@", hint, name]];
        });
        if ([AccountManager shared].detailedLog) {
            [[AccountManager shared] appendLog:[NSString stringWithFormat:@"【定位伪装】%@", name]];
        }
        return fakedCoord;
    }
    return orig_coordinate(self, _cmd);
}

// ========== Hook CoreTelephony 基站信息 ==========
static NSString* (*orig_mobileNetworkCode)(id self, SEL _cmd);
static NSString* replaced_mobileNetworkCode(id self, SEL _cmd) {
    if (enabled && fakedBS.hasBaseStation) {
        return [NSString stringWithFormat:@"%02ld", (long)fakedBS.mnc];
    }
    return orig_mobileNetworkCode(self, _cmd);
}

static NSString* (*orig_mobileCountryCode)(id self, SEL _cmd);
static NSString* replaced_mobileCountryCode(id self, SEL _cmd) {
    if (enabled && fakedBS.hasBaseStation) {
        return [NSString stringWithFormat:@"%03ld", (long)fakedBS.mcc];
    }
    return orig_mobileCountryCode(self, _cmd);
}

static NSString* (*orig_isoCountryCode)(id self, SEL _cmd);
static NSString* replaced_isoCountryCode(id self, SEL _cmd) {
    if (enabled && fakedBS.hasBaseStation) {
        return @"cn";
    }
    return orig_isoCountryCode(self, _cmd);
}

@implementation LocationFaker

+ (void)install {
    loadState();
    Method coordMethod = class_getInstanceMethod([CLLocation class], @selector(coordinate));
    if (coordMethod) {
        orig_coordinate = (CLLocationCoordinate2D (*)(id, SEL))method_getImplementation(coordMethod);
        method_setImplementation(coordMethod, (IMP)replaced_coordinate);
    }
    Class ctc = NSClassFromString(@"CTCarrier");
    if (ctc) {
        Method mnc = class_getInstanceMethod(ctc, @selector(mobileNetworkCode));
        if (mnc) {
            orig_mobileNetworkCode = (NSString* (*)(id, SEL))method_getImplementation(mnc);
            method_setImplementation(mnc, (IMP)replaced_mobileNetworkCode);
        }
        Method mcc = class_getInstanceMethod(ctc, @selector(mobileCountryCode));
        if (mcc) {
            orig_mobileCountryCode = (NSString* (*)(id, SEL))method_getImplementation(mcc);
            method_setImplementation(mcc, (IMP)replaced_mobileCountryCode);
        }
        Method iso = class_getInstanceMethod(ctc, @selector(isoCountryCode));
        if (iso) {
            orig_isoCountryCode = (NSString* (*)(id, SEL))method_getImplementation(iso);
            method_setImplementation(iso, (IMP)replaced_isoCountryCode);
        }
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

+ (void)setBaseStation:(FakeBaseStation)bs { fakedBS = bs; saveState(); }
+ (FakeBaseStation)currentBaseStation { return fakedBS; }
+ (BOOL)hasBaseStation { return fakedBS.hasBaseStation; }

+ (NSString *)currentName {
    NSArray *favs = [[NSUserDefaults standardUserDefaults] objectForKey:@"locationFavorites"] ?: @[];
    if (selectedFavoriteIndex >= 0 && selectedFavoriteIndex < favs.count) {
        NSDictionary *item = favs[selectedFavoriteIndex];
        if (fabs([item[@"lat"] doubleValue] - fakedCoord.latitude) < 0.000001 &&
            fabs([item[@"lon"] doubleValue] - fakedCoord.longitude) < 0.000001) {
            return item[@"name"];
        }
    }
    return [NSString stringWithFormat:@"%.6f, %.6f", fakedCoord.latitude, fakedCoord.longitude];
}

+ (NSArray *)favoriteNames {
    NSArray *favs = [[NSUserDefaults standardUserDefaults] objectForKey:@"locationFavorites"] ?: @[];
    NSMutableArray *names = [NSMutableArray array];
    for (NSDictionary *item in favs) [names addObject:item[@"name"] ?: @"未命名"];
    return names;
}

+ (NSInteger)selectedFavoriteIndex { return selectedFavoriteIndex; }

+ (UIViewController *)favoritesViewController {
    LocationFavoritesVC *vc = [[LocationFavoritesVC alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    return nav;
}

+ (void)requestRealLocationAndBaseStationWithCompletion:(void(^)(CLLocationCoordinate2D coord, FakeBaseStation bs))completion {
    LocationFavoritesVC *vc = [[LocationFavoritesVC alloc] init];
    vc.realInfoCompletion = completion;
    [vc startRealInfoFetch];
    objc_setAssociatedObject([NSNull null], "RealInfoVC", vc, OBJC_ASSOCIATION_RETAIN);
}

@end

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
    CGFloat y = 100, fieldH = 30, labelW = 50;
    
    // 启用开关
    UILabel *enLb = [[UILabel alloc] initWithFrame:CGRectMake(margin, y, labelW, fieldH)];
    enLb.text = @"启用"; enLb.textColor = [UIColor blackColor];
    [self.view addSubview:enLb];
    _enableSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(margin+labelW+5, y-2, 51, 31)];
    _enableSwitch.on = [LocationFaker isEnabled];
    [self.view addSubview:_enableSwitch];
    
    _currentLocLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin+labelW+70, y, self.view.bounds.size.width - margin*2 - labelW - 70, fieldH)];
    _currentLocLabel.text = [NSString stringWithFormat:@"当前: %@", [LocationFaker currentName]];
    _currentLocLabel.font = [UIFont systemFontOfSize:13];
    _currentLocLabel.textColor = [UIColor darkGrayColor];
    [self.view addSubview:_currentLocLabel];
    y += fieldH + 15;
    
    // 名称（必填）
    UILabel *nameLb = [[UILabel alloc] initWithFrame:CGRectMake(margin, y, labelW, fieldH)];
    nameLb.text = @"名称*"; nameLb.textColor = [UIColor redColor];
    [self.view addSubview:nameLb];
    _nameField = [[UITextField alloc] initWithFrame:CGRectMake(margin+labelW, y, self.view.bounds.size.width - margin*2 - labelW, fieldH)];
    _nameField.placeholder = @"必填"; _nameField.borderStyle = UITextBorderStyleRoundedRect; _nameField.textColor = [UIColor blackColor];
    [self.view addSubview:_nameField];
    y += fieldH + 8;
    
    // 纬度/经度
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
    
    // 基站信息
    NSArray *bsLabels = @[@"MCC", @"MNC", @"LAC", @"CID"];
    _mccField = [self createBSField]; _mncField = [self createBSField]; _lacField = [self createBSField]; _cidField = [self createBSField];
    NSArray *bsFields = @[_mccField, _mncField, _lacField, _cidField];
    CGFloat smallW = (self.view.bounds.size.width - margin*2 - labelW - 3*10) / 4;
    for (int i = 0; i < 4; i++) {
        UILabel *lb = [[UILabel alloc] initWithFrame:CGRectMake(margin + (smallW+10)*i, y, 30, fieldH)];
        lb.text = bsLabels[i]; lb.font = [UIFont systemFontOfSize:12]; lb.textColor = [UIColor blackColor];
        [self.view addSubview:lb];
        UITextField *tf = bsFields[i];
        tf.frame = CGRectMake(margin + 30 + (smallW+10)*i, y, smallW - 30, fieldH);
        tf.placeholder = bsLabels[i];
        tf.keyboardType = UIKeyboardTypeNumberPad;
        [self.view addSubview:tf];
    }
    y += fieldH + 12;
    
    // 一键获取按钮
    UIButton *fetchBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    fetchBtn.frame = CGRectMake(margin, y, self.view.bounds.size.width - margin*2, 36);
    [fetchBtn setTitle:@"一键获取真实位置和基站" forState:UIControlStateNormal];
    [fetchBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    fetchBtn.backgroundColor = [UIColor systemBlueColor]; fetchBtn.layer.cornerRadius = 6;
    [fetchBtn addTarget:self action:@selector(fetchRealInfo) forControlEvents:UIControlEventTouchUpInside];
    fetchBtn.tag = 100; // 用于获取时修改标题
    [self.view addSubview:fetchBtn];
    y += 44;
    
    // 保存到列表按钮
    UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    saveBtn.frame = CGRectMake(margin, y, self.view.bounds.size.width - margin*2, 36);
    [saveBtn setTitle:@"保存到列表" forState:UIControlStateNormal];
    [saveBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    saveBtn.backgroundColor = [UIColor systemGreenColor]; saveBtn.layer.cornerRadius = 6;
    [saveBtn addTarget:self action:@selector(saveFavorite) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:saveBtn];
    y += 44;
    
    _tableView = [[UITableView alloc] initWithFrame:CGRectMake(margin, y, self.view.bounds.size.width - margin*2, self.view.bounds.size.height - y - 20) style:UITableViewStylePlain];
    _tableView.backgroundColor = [UIColor whiteColor]; _tableView.separatorColor = [UIColor lightGrayColor];
    _tableView.delegate = self; _tableView.dataSource = self; _tableView.rowHeight = 50;
    [self.view addSubview:_tableView];
}

- (UITextField *)createBSField {
    UITextField *tf = [[UITextField alloc] init];
    tf.borderStyle = UITextBorderStyleRoundedRect;
    tf.font = [UIFont systemFontOfSize:13];
    tf.textColor = [UIColor blackColor];
    return tf;
}

- (void)startRealInfoFetch {
    if (!_locationManager) {
        _locationManager = [[CLLocationManager alloc] init];
        _locationManager.delegate = self;
        [_locationManager requestWhenInUseAuthorization];
    }
    [_locationManager requestLocation];
}

- (void)fetchRealInfo {
    UIButton *btn = (UIButton *)[self.view viewWithTag:100];
    btn.enabled = NO;
    [btn setTitle:@"获取中…" forState:UIControlStateNormal];
    __weak typeof(self) weakSelf = self;
    self.realInfoCompletion = ^(CLLocationCoordinate2D coord, FakeBaseStation bs) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.latField.text = [NSString stringWithFormat:@"%.6f", coord.latitude];
        strongSelf.lonField.text = [NSString stringWithFormat:@"%.6f", coord.longitude];
        if (bs.hasBaseStation) {
            strongSelf.mccField.text = [NSString stringWithFormat:@"%ld", (long)bs.mcc];
            strongSelf.mncField.text = [NSString stringWithFormat:@"%ld", (long)bs.mnc];
            strongSelf.lacField.text = [NSString stringWithFormat:@"%ld", (long)bs.lac];
            strongSelf.cidField.text = [NSString stringWithFormat:@"%ld", (long)bs.cid];
        }
        UIButton *b = (UIButton *)[strongSelf.view viewWithTag:100];
        b.enabled = YES;
        [b setTitle:@"一键获取真实位置和基站" forState:UIControlStateNormal];
    };
    [self startRealInfoFetch];
}

#pragma mark - CLLocationManagerDelegate
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *loc = locations.lastObject;
    if (loc && self.realInfoCompletion) {
        CTTelephonyNetworkInfo *info = [[CTTelephonyNetworkInfo alloc] init];
        CTCarrier *carrier = nil;
        if (@available(iOS 12.0, *)) {
            NSString *service = nil;
if (@available(iOS 13.0, *)) {
    service = info.dataServiceIdentifier ?: [info.serviceSubscriberCellularProviders.allKeys firstObject];
} else {
    // iOS 12 以下可能没有 serviceSubscriberCellularProviders，使用 subscriberCellularProvider
}
            if (service) {
                carrier = info.serviceSubscriberCellularProviders[service];
            }
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            carrier = info.subscriberCellularProvider;
#pragma clang diagnostic pop
        }
        FakeBaseStation bs;
        bs.mcc = carrier ? [carrier.mobileCountryCode integerValue] : 0;
        bs.mnc = carrier ? [carrier.mobileNetworkCode integerValue] : 0;
        bs.lac = 0; bs.cid = 0;
        bs.hasBaseStation = (carrier != nil);
        self.realInfoCompletion(loc.coordinate, bs);
        self.realInfoCompletion = nil;
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    if (self.realInfoCompletion) {
        FakeBaseStation bs = {0,0,0,0, NO};
        self.realInfoCompletion(CLLocationCoordinate2DMake(0, 0), bs);
        self.realInfoCompletion = nil;
    }
}

- (void)doneAction {
    [self applyCoords];
    self.view.window.hidden = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"LocationFavoritesDismissed" object:nil];
}

- (void)applyCoords {
    double lat = [_latField.text doubleValue];
    double lon = [_lonField.text doubleValue];
    if (lat != 0 || lon != 0) {
        [LocationFaker setCoordinate:CLLocationCoordinate2DMake(lat, lon)];
    }
    if (_mccField.text.length > 0 || _mncField.text.length > 0) {
        FakeBaseStation bs;
        bs.mcc = [_mccField.text integerValue];
        bs.mnc = [_mncField.text integerValue];
        bs.lac = [_lacField.text integerValue];
        bs.cid = [_cidField.text integerValue];
        bs.hasBaseStation = YES;
        [LocationFaker setBaseStation:bs];
    } else {
        FakeBaseStation bs = fakedBS;
        bs.hasBaseStation = NO;
        [LocationFaker setBaseStation:bs];
    }
    // 强制打开定位
    [LocationFaker setEnabled:YES];
    _enableSwitch.on = YES;
}

- (void)addNewFavorite {
    _nameField.text = @"";
    _latField.text = @"";
    _lonField.text = @"";
    _mccField.text = @"";
    _mncField.text = @"";
    _lacField.text = @"";
    _cidField.text = @"";
}

- (void)saveFavorite {
    double lat = [_latField.text doubleValue];
    double lon = [_lonField.text doubleValue];
    NSString *name = _nameField.text;
    if (name.length == 0) {
        [self showAlert:@"名称必填"];
        return;
    }
    if (lat == 0 && lon == 0) return;
    
    NSMutableDictionary *item = [NSMutableDictionary dictionaryWithDictionary:@{
        @"name": name,
        @"lat": @(lat),
        @"lon": @(lon)
    }];
    if (_mccField.text.length > 0) {
        item[@"mcc"] = @([_mccField.text integerValue]);
        item[@"mnc"] = @([_mncField.text integerValue]);
        item[@"lac"] = @([_lacField.text integerValue]);
        item[@"cid"] = @([_cidField.text integerValue]);
    }
    
    NSInteger idx = -1;
    for (NSInteger i = 0; i < self.dataSource.count; i++) {
        NSDictionary *d = self.dataSource[i];
        if ([d[@"name"] isEqualToString:name] || (fabs([d[@"lat"] doubleValue]-lat)<0.000001 && fabs([d[@"lon"] doubleValue]-lon)<0.000001)) {
            idx = i;
            break;
        }
    }
    if (idx >= 0) self.dataSource[idx] = item;
    else [self.dataSource addObject:item];
    
    [[NSUserDefaults standardUserDefaults] setObject:self.dataSource forKey:@"locationFavorites"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self.tableView reloadData];
    [self addNewFavorite];
}

- (void)showAlert:(NSString *)msg {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
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
    NSString *detail = [NSString stringWithFormat:@"%.4f,%.4f", [item[@"lat"] doubleValue], [item[@"lon"] doubleValue]];
    if (item[@"mcc"]) detail = [detail stringByAppendingFormat:@" 基站%@", item[@"mcc"]];
    cell.detailTextLabel.text = detail;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = self.dataSource[indexPath.row];
    _nameField.text = item[@"name"];
    _latField.text = [item[@"lat"] stringValue];
    _lonField.text = [item[@"lon"] stringValue];
    _mccField.text = item[@"mcc"] ? [item[@"mcc"] stringValue] : @"";
    _mncField.text = item[@"mnc"] ? [item[@"mnc"] stringValue] : @"";
    _lacField.text = item[@"lac"] ? [item[@"lac"] stringValue] : @"";
    _cidField.text = item[@"cid"] ? [item[@"cid"] stringValue] : @"";
    [self applyCoords];
    [self doneAction];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { return YES; }
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSInteger deletedIndex = indexPath.row;
        BOOL isSelected = (deletedIndex == [LocationFaker selectedFavoriteIndex]);
        [self.dataSource removeObjectAtIndex:deletedIndex];
        [[NSUserDefaults standardUserDefaults] setObject:self.dataSource forKey:@"locationFavorites"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];

        if (isSelected) {
            [LocationFaker setCoordinate:CLLocationCoordinate2DMake(0, 0)];
            [LocationFaker setBaseStation:(FakeBaseStation){0,0,0,0, NO}];
            [LocationFaker setEnabled:NO];
        }
        // 重新同步索引，确保 selectedFavoriteIndex 正确
        [LocationFaker setCoordinate:[LocationFaker currentCoordinate]];
    }
}
@end