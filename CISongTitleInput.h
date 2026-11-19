#import <UIKit/UIKit.h>
#import "CITextUtilities.h"

NS_ASSUME_NONNULL_BEGIN
/// Adds a native candidate menu at the trailing edge. Picking a title only
/// edits the field; the enclosing form retains control of search/save.
FOUNDATION_EXPORT void CIConfigureSongTitleCandidates(
    UITextField *field, NSArray<CISongQuery *> *readings
);
NS_ASSUME_NONNULL_END
