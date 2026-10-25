#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT void CILogProcessBackgroundEligibility(NSString *reason);
/// Local hook counters only; this does not prove system execution eligibility.
FOUNDATION_EXPORT NSString *CILaunchPrefetchRetentionSummary(void);

FOUNDATION_EXPORT void CIInstallLaunchPrefetchRetentionProbe(void);

FOUNDATION_EXPORT void CIReloadLaunchPrefetchRetentionProbe(void);

FOUNDATION_EXPORT void CIReleaseRetainedLaunchPrefetchAssertions(
    NSString *reason
);

NS_ASSUME_NONNULL_END
