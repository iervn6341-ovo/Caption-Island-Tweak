#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT void CILogProcessBackgroundEligibility(NSString *reason);

FOUNDATION_EXPORT void CIInstallLaunchPrefetchRetentionProbe(void);

FOUNDATION_EXPORT void CIReloadLaunchPrefetchRetentionProbe(void);

FOUNDATION_EXPORT void CIReleaseRetainedLaunchPrefetchAssertions(
    NSString *reason
);

NS_ASSUME_NONNULL_END
