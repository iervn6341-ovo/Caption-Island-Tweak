#import <UIKit/UIKit.h>
#import "../../CISongTitleInput.h"

static NSString *ResultPath(void) {
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject
        stringByAppendingPathComponent:@"result.txt"];
}
static void Check(BOOL condition, NSString *message) {
    if (condition) return;
    [[@"FAIL: " stringByAppendingString:message] writeToFile:ResultPath()
        atomically:YES encoding:NSUTF8StringEncoding error:nil];
    abort();
}
@interface SongTitleInputSmoke : UIResponder <UIApplicationDelegate, UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic) NSUInteger edits, searches;
@end
@implementation SongTitleInputSmoke
- (void)changed:(UITextField *)field { (void)field; self.edits++; }
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application; (void)options; return YES;
}
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)session; (void)options;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    UIViewController *root = [UIViewController new]; root.view.backgroundColor = UIColor.systemBackgroundColor;
    self.window.rootViewController = root; [self.window makeKeyAndVisible];
    NSArray<CISongQuery *> *readings = @[
        [CISongQuery queryWithTitle:@"Precious Star Dreamer" artist:@"Azumi Waki" origin:@"parsed"],
        [CISongQuery queryWithTitle:@"Never Looking Back" artist:@"Uma Musume" origin:@"parsed"],
        [CISongQuery queryWithTitle:@"Precious Star Dreamer" artist:@"Duplicate" origin:@"parsed"],
        [CISongQuery queryWithTitle:@"" artist:@"" origin:@"parsed"],
    ];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Enter a song title…"
        message:@"Enter the track name LRCLIB should search." preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = readings.firstObject.title;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.returnKeyType = UIReturnKeySearch;
        CIConfigureSongTitleCandidates(field, readings);
        [field addTarget:self action:@selector(changed:) forControlEvents:UIControlEventEditingChanged];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Search" style:UIAlertActionStyleDefault
        handler:^(__unused UIAlertAction *action) { self.searches++; }]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500 * NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        [root presentViewController:alert animated:NO completion:^{
            UITextField *field = alert.textFields.firstObject;
            UIButton *dropdown = (id)field.rightView;
            Check([dropdown isKindOfClass:UIButton.class] && dropdown.showsMenuAsPrimaryAction &&
                field.rightViewMode == UITextFieldViewModeAlways, @"a native menu arrow must be attached to the field's trailing edge");
            Check(dropdown.menu.children.count == 2, @"blank and duplicate candidate titles must be omitted");
            Check([dropdown.menu.children.firstObject.title isEqual:@"Precious Star Dreamer"] &&
                [dropdown.menu.children.lastObject.title isEqual:@"Never Looking Back"], @"candidate order must match the current video readings");
            field.text = @"An editable draft";
            [dropdown sendAction:(UIAction *)dropdown.menu.children.lastObject];
            Check([field.text isEqual:@"Never Looking Back"] && self.edits == 1 && self.searches == 0 &&
                root.presentedViewController == alert && field.isFirstResponder,
                @"choosing a candidate must replace the editable draft without submitting or dismissing the prompt");
            field.text = @"Never Looking Back (live)";
            Check(self.searches == 0, @"a filled title must remain editable before Search");
            UITextField *empty = [UITextField new]; CIConfigureSongTitleCandidates(empty, @[]);
            Check(!empty.rightView && empty.rightViewMode == UITextFieldViewModeNever, @"no candidates must leave ordinary text entry usable");
            __weak UITextField *released;
            UIAction *retainedAction;
            @autoreleasepool {
                UITextField *temporary = [UITextField new]; CIConfigureSongTitleCandidates(temporary, readings);
                released = temporary; retainedAction = (UIAction *)((UIButton *)temporary.rightView).menu.children.firstObject;
            }
            Check(!released, @"a candidate action must not retain a dismissed text field");
            [dropdown sendAction:retainedAction];
            [@"PASS: native candidate menu, title filling, editing notification, no automatic search, duplicate/empty handling and field release\n"
                writeToFile:ResultPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
            if ([NSProcessInfo.processInfo.arguments containsObject:@"--preview-menu"])
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500 * NSEC_PER_MSEC),dispatch_get_main_queue(),^{ [dropdown performPrimaryAction]; });
        }];
    });
}
@end
int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(SongTitleInputSmoke.class)); }
}
