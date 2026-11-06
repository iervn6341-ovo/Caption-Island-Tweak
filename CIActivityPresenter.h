#import <Foundation/Foundation.h>
#import "CICaptionPresenting.h"

NS_ASSUME_NONNULL_BEGIN

@interface CIActivityPresenter : NSObject <CICaptionPresenting>
+ (instancetype)sharedPresenter;
- (void)endForProcessTermination;
- (void)endForProcessTerminationReason:(NSString *)reason;
@end

NS_ASSUME_NONNULL_END
