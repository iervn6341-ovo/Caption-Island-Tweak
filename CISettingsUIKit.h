#import <UIKit/UIKit.h>
@class YTSettingsCell;

// Shared row definitions can be rendered by UIKit or the standalone YouTube entry.
@interface CISettingsItem : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *titleDescription;
@property(nonatomic, copy) NSString *accessibilityIdentifier;
@property(nonatomic, copy) NSString *(^detailTextBlock)(void);
@property(nonatomic, copy) BOOL (^selectBlock)(YTSettingsCell *, NSUInteger);
@property(nonatomic, copy) BOOL (^switchBlock)(YTSettingsCell *, BOOL);
@property(nonatomic) BOOL hasSwitch;
@property(nonatomic) BOOL on;
@property(nonatomic) BOOL enabled;
+ (instancetype)itemWithTitle:(NSString *)title titleDescription:(NSString *)description accessibilityIdentifier:(NSString *)identifier detailTextBlock:(id)detail selectBlock:(BOOL (^)(YTSettingsCell *, NSUInteger))select;
+ (instancetype)checkmarkItemWithTitle:(NSString *)title selectBlock:(BOOL (^)(YTSettingsCell *, NSUInteger))select;
+ (instancetype)switchItemWithTitle:(NSString *)title titleDescription:(NSString *)description accessibilityIdentifier:(NSString *)identifier switchOn:(BOOL)on switchBlock:(BOOL (^)(YTSettingsCell *, BOOL))block settingItemId:(int)itemID;
@end

@interface CISettingsUIKitController : UITableViewController
@property(nonatomic, copy) NSArray<CISettingsItem *> *(^itemsProvider)(void);
@property(nonatomic) NSUInteger selectedItemIndex;
@property(nonatomic) BOOL isChoicePage;
- (void)reloadData;
- (void)pushViewController:(UIViewController *)controller;
@end

// Stable identifiers keep grouping independent from localization and row order.
FOUNDATION_EXPORT NSArray<NSDictionary *> *CISettingsGroups(void);
FOUNDATION_EXPORT NSArray *CISettingsItemsInGroup(NSArray *items, NSString *groupID);
FOUNDATION_EXPORT BOOL CIUsesIntegratedSettings(void);
FOUNDATION_EXPORT void CIPresentSettingsChoices(UIViewController *controller, NSString *title,
                                                 NSArray *rows, NSUInteger selectedIndex);
FOUNDATION_EXPORT __attribute__((visibility("default"))) UIViewController *CIMakeSettingsViewController(void);
