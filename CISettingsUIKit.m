#import "CISettingsUIKit.h"
#import "CIConstants.h"
#import <dlfcn.h>
#import <objc/message.h>

@implementation CISettingsItem
- (instancetype)init {
    if ((self = [super init])) _enabled = YES;
    return self;
}
+ (instancetype)itemWithTitle:(NSString *)title titleDescription:(NSString *)description accessibilityIdentifier:(NSString *)identifier detailTextBlock:(id)detail selectBlock:(BOOL (^)(YTSettingsCell *, NSUInteger))select {
    CISettingsItem *item = [self new];
    item.title = title;
    item.titleDescription = description;
    item.accessibilityIdentifier = identifier;
    item.detailTextBlock = detail;
    item.selectBlock = select;
    return item;
}
+ (instancetype)checkmarkItemWithTitle:(NSString *)title selectBlock:(BOOL (^)(YTSettingsCell *, NSUInteger))select {
    return [self itemWithTitle:title titleDescription:nil accessibilityIdentifier:nil detailTextBlock:nil selectBlock:select];
}
+ (instancetype)switchItemWithTitle:(NSString *)title titleDescription:(NSString *)description accessibilityIdentifier:(NSString *)identifier switchOn:(BOOL)on switchBlock:(BOOL (^)(YTSettingsCell *, BOOL))block settingItemId:(int)itemID {
    (void)itemID;
    CISettingsItem *item = [self itemWithTitle:title titleDescription:description accessibilityIdentifier:identifier detailTextBlock:nil selectBlock:nil];
    item.hasSwitch = YES;
    item.on = on;
    item.switchBlock = block;
    return item;
}
@end

@interface CISettingsUIKitController ()
@property(nonatomic, copy) NSArray<CISettingsItem *> *items;
@end

@implementation CISettingsUIKitController
- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 90.0;
    self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    [self reloadData];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadData];
}
- (void)reloadData {
    self.items = self.itemsProvider ? self.itemsProvider() : @[];
    if (self.isViewLoaded) [self.tableView reloadData];
}
- (void)pushViewController:(UIViewController *)controller {
    if (controller) [self.navigationController pushViewController:controller animated:YES];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section; return self.items.count;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"CaptionIsland.Settings"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"CaptionIsland.Settings"];
    CISettingsItem *item = self.items[indexPath.row];
    cell.textLabel.text = item.title;
    NSString *detail = item.detailTextBlock ? item.detailTextBlock() : nil;
    NSMutableArray *lines = [NSMutableArray array];
    if (item.titleDescription.length) [lines addObject:item.titleDescription];
    if (detail.length) [lines addObject:detail];
    cell.detailTextLabel.text = [lines componentsJoinedByString:@"\n"];
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.accessibilityIdentifier = item.accessibilityIdentifier;
    cell.userInteractionEnabled = item.enabled;
    cell.accessoryView = nil;
    cell.accessoryType = self.isChoicePage
        ? ((NSUInteger)indexPath.row == self.selectedItemIndex ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone)
        : (item.selectBlock ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone);
    if (item.hasSwitch) {
        UISwitch *toggle = [UISwitch new];
        toggle.on = item.on;
        toggle.enabled = item.enabled;
        toggle.tag = indexPath.row;
        toggle.accessibilityLabel = item.title;
        toggle.accessibilityHint = item.titleDescription;
        [toggle addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}
- (void)switchChanged:(UISwitch *)sender {
    if (sender.tag < 0 || (NSUInteger)sender.tag >= self.items.count) return;
    CISettingsItem *item = self.items[sender.tag];
    if (item.switchBlock) item.switchBlock(nil, sender.on);
    [self reloadData];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    CISettingsItem *item = self.items[indexPath.row];
    if (!item.enabled || !item.selectBlock) return;
    item.selectBlock(nil, indexPath.row);
    if (self.isChoicePage) self.selectedItemIndex = indexPath.row;
    [self reloadData];
}
@end

BOOL CIUsesIntegratedSettings(void) {
    typedef BOOL (*Integration)(void);
    Integration integration = (Integration)dlsym(RTLD_DEFAULT, "YTKACEIntegratesCaptionIslandSettings");
    return integration && integration();
}

void CIPresentSettingsChoices(UIViewController *controller, NSString *title, NSArray *rows, NSUInteger selectedIndex) {
    typedef void (*SelectionMenu)(UIViewController *, UIView *, NSString *, NSArray<NSString *> *, NSUInteger, void (^)(NSUInteger));
    SelectionMenu selection = (SelectionMenu)dlsym(RTLD_DEFAULT, "YTKACEPresentSelectionMenu");
    if (selection) {
        NSMutableArray *titles = [NSMutableArray array];
        for (id item in rows) [titles addObject:[item title] ?: @""];
        selection(controller, controller.view, title, titles, selectedIndex, ^(NSUInteger index) {
            if (index >= rows.count) return;
            BOOL (^handler)(YTSettingsCell *, NSUInteger) = [rows[index] selectBlock];
            if (handler) handler(nil, index);
        });
        return;
    }
    if ([controller isKindOfClass:CISettingsUIKitController.class]) {
        CISettingsUIKitController *choices = [CISettingsUIKitController new];
        choices.title = title;
        choices.isChoicePage = YES;
        choices.selectedItemIndex = selectedIndex;
        choices.itemsProvider = ^{ return rows; };
        [((CISettingsUIKitController *)controller) pushViewController:choices];
        return;
    }
    // Preserve the standalone YouTube settings path when YTKACE is absent.
    Class pickerClass = NSClassFromString(@"YTSettingsPickerViewController");
    SEL initializer = NSSelectorFromString(@"initWithNavTitle:pickerSectionTitle:rows:selectedItemIndex:parentResponder:");
    if (![pickerClass instancesRespondToSelector:initializer]) return;
    SEL parentSelector = NSSelectorFromString(@"parentResponder");
    id parent = [controller respondsToSelector:parentSelector]
        ? ((id (*)(id, SEL))objc_msgSend)(controller, parentSelector) : nil;
    id picker = ((id (*)(id, SEL, id, id, id, NSUInteger, id))objc_msgSend)(
        [pickerClass alloc], initializer, title, nil, rows, selectedIndex, parent);
    ((void (*)(id, SEL, id))objc_msgSend)(controller, NSSelectorFromString(@"pushViewController:"), picker);
}
