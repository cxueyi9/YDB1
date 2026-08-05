#import "LocationFaker.h"
#import "AccountManager.h"
#import "FloatWindow.h"
#import <objc/runtime.h>

// 前向声明
@interface LocationFavoritesVC : UITableViewController
@property (nonatomic, strong) NSMutableArray *dataSource;
@end

// 用于持有窗口的静态变量
static UIWindow *favoritesWindow = nil;

// ========== 静态变量 ==========
static BOOL enabled = NO;
static CLLocationCoordinate2D fakedCoord = {37.3349, -122.0093};
static NSMutableArray *favorites = nil;

static void loadFavorites() {
    if (!favorites) {
        NSArray *saved = [[NSUserDefaults standardUserDefaults] objectForKey:@"locationFavorites"];
        favorites = saved ? [saved mutableCopy] : [NSMutableArray array];
    }
}
static void saveFavorites() {
    [[NSUserDefaults standardUserDefaults] setObject:favorites forKey:@"locationFavorites"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// ========== Hook ==========
static CLLocationCoordinate2D (*orig_coordinate)(id self, SEL _cmd);
static CLLocationCoordinate2D replaced_coordinate(id self, SEL _cmd) {
    if (enabled) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [FloatWindow showToast:[NSString stringWithFormat:@"定位已伪装 %.4f, %.4f",
                                    fakedCoord.latitude, fakedCoord.longitude]];
        });
        if ([AccountManager shared].detailedLog) {
            NSString *msg = [NSString stringWithFormat:@"【定位伪装】%.6f, %.6f",
                             fakedCoord.latitude, fakedCoord.longitude];
            [[AccountManager shared] appendLog:msg];
        }
        return fakedCoord;
    }
    return orig_coordinate(self, _cmd);
}

@implementation LocationFaker

+ (void)install {
    Method orig = class_getInstanceMethod([CLLocation class], @selector(coordinate));
    if (orig) {
        orig_coordinate = (CLLocationCoordinate2D (*)(id, SEL))method_getImplementation(orig);
        method_setImplementation(orig, (IMP)replaced_coordinate);
    }
}

+ (BOOL)isEnabled { return enabled; }
+ (void)setEnabled:(BOOL)en { enabled = en; }
+ (CLLocationCoordinate2D)currentCoordinate { return fakedCoord; }
+ (void)setCoordinate:(CLLocationCoordinate2D)coord { fakedCoord = coord; }

+ (UIViewController *)favoritesViewController {
    loadFavorites();
    LocationFavoritesVC *vc = [[LocationFavoritesVC alloc] initWithStyle:UITableViewStyleGrouped];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    return nav;
}

// 显示收藏窗口
+ (void)showFavoritesWindow {
    loadFavorites();
    // 如果已有窗口则先关闭
    if (favoritesWindow) {
        favoritesWindow.hidden = YES;
        favoritesWindow = nil;
    }

    LocationFavoritesVC *vc = [[LocationFavoritesVC alloc] initWithStyle:UITableViewStyleGrouped];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];

    // 创建新的窗口
    UIWindowScene *scene = nil;
    if (@available(iOS 13.0, *)) {
        scene = (UIWindowScene *)[[[UIApplication sharedApplication] connectedScenes] anyObject];
    }

    if (scene) {
        favoritesWindow = [[UIWindow alloc] initWithWindowScene:scene];
    } else {
        favoritesWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    }
    favoritesWindow.frame = [UIScreen mainScreen].bounds;
    favoritesWindow.windowLevel = UIWindowLevelAlert + 2;
    favoritesWindow.backgroundColor = [UIColor clearColor];
    favoritesWindow.rootViewController = nav;
    favoritesWindow.hidden = NO;

    // 设置关闭回调
    vc.dismissBlock = ^{
        favoritesWindow.hidden = YES;
        favoritesWindow = nil;
    };
}

@end

// ========== 收藏列表控制器 ==========
@interface LocationFavoritesVC ()
@property (nonatomic, copy) void (^dismissBlock)(void);
@end

@implementation LocationFavoritesVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"收藏坐标";
    self.dataSource = [NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] objectForKey:@"locationFavorites"] ?: @[]];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addFavorite)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismiss)];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
    self.tableView.rowHeight = 60;
}

- (void)dismiss {
    if (self.dismissBlock) self.dismissBlock();
}

- (void)addFavorite {
    // 使用独立窗口弹出 UIAlertController 也不会消失，因为窗口层级足够高
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"新增收藏" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"名称（可空）"; }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"纬度"; tf.keyboardType = UIKeyboardTypeDecimalPad; }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"经度"; tf.keyboardType = UIKeyboardTypeDecimalPad; }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"备注（可空）"; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = alert.textFields[0].text ?: @"";
        double lat = [alert.textFields[1].text doubleValue];
        double lon = [alert.textFields[2].text doubleValue];
        NSString *note = alert.textFields[3].text ?: @"";
        if (lat != 0 || lon != 0) {
            NSDictionary *item = @{@"name": name.length ? name : [NSString stringWithFormat:@"%.4f,%.4f", lat, lon],
                                   @"lat": @(lat), @"lon": @(lon), @"note": note};
            [self.dataSource addObject:item];
            [[NSUserDefaults standardUserDefaults] setObject:self.dataSource forKey:@"locationFavorites"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            [self.tableView reloadData];
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.dataSource.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Cell"];
        cell.detailTextLabel.textColor = [UIColor grayColor];
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
    [FloatWindow showToast:[NSString stringWithFormat:@"已切换定位到 %@", item[@"name"]]];
    [self dismiss];
}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { return YES; }
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [self.dataSource removeObjectAtIndex:indexPath.row];
        [[NSUserDefaults standardUserDefaults] setObject:self.dataSource forKey:@"locationFavorites"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}
@end