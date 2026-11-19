#import "CISongTitleInput.h"
#import "CIConstants.h"

void CIConfigureSongTitleCandidates(UITextField *field, NSArray<CISongQuery *> *readings) {
    NSMutableArray<UIAction *> *actions = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    __weak UITextField *weakField = field;
    for (CISongQuery *reading in readings) {
        NSString *title = CICleanCaptionText(reading.title);
        if (!title.length || [seen containsObject:title]) continue;
        [seen addObject:title];
        UIAction *action = [UIAction actionWithTitle:title image:nil identifier:nil
            handler:^(__unused UIAction *selected) {
                UITextField *input = weakField;
                input.text = title;
                [input sendActionsForControlEvents:UIControlEventEditingChanged];
                [input becomeFirstResponder];
            }];
        [actions addObject:action];
    }
    if (!actions.count) {
        field.rightView = nil;
        field.rightViewMode = UITextFieldViewModeNever;
        return;
    }
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake(0, 0, 44, 32);
    [button setImage:[UIImage systemImageNamed:@"chevron.down"] forState:UIControlStateNormal];
    button.accessibilityLabel = CILocalized(@"SONG_TITLE_CANDIDATES", @"Song title candidates");
    button.accessibilityIdentifier = @"CaptionIsland.SongTitleCandidates";
    button.menu = [UIMenu menuWithChildren:actions];
    button.showsMenuAsPrimaryAction = YES;
    field.rightView = button;
    field.rightViewMode = UITextFieldViewModeAlways;
}
