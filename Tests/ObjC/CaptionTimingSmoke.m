#import <Foundation/Foundation.h>
#import <math.h>
#import "../../CICaptionTiming.h"
#import "../../CIModels.h"

static void CIAssert(BOOL condition, NSString *message) {
    if (condition) return;
    NSLog(@"Caption timing smoke failed: %@", message);
    exit(1);
}

int main(void) {
    @autoreleasepool {
        CIAssert(
            fabs(CIAdjustedCaptionLookupTime(5.0, 2.0) - 7.0) < 0.001,
            @"a positive advance should look ahead"
        );
        CIAssert(
            fabs(CIAdjustedCaptionBoundary(6.0, 2.0) - 4.0) < 0.001,
            @"a positive advance should move an ActivityKit boundary earlier"
        );
        CIAssert(
            fabs(CIAdjustedCaptionLookupTime(0.0, -2.0) + 2.0) < 0.001,
            @"a negative advance must preserve pre-roll before a zero-time cue"
        );
        CIAssert(
            fabs(CIAdjustedCaptionBoundary(0.0, -2.0) - 2.0) < 0.001,
            @"a negative advance should delay a zero-time ActivityKit boundary"
        );
        NSArray<CICaptionCue *> *cues = @[
            [[CICaptionCue alloc] initWithStartTime:1.0 endTime:2.0 text:@"a"],
            [[CICaptionCue alloc] initWithStartTime:2.2 endTime:3.0 text:@"b"],
            [[CICaptionCue alloc] initWithStartTime:6.0 endTime:7.0 text:@"c"],
            [[CICaptionCue alloc] initWithStartTime:6.5 endTime:8.0 text:@"d"],
        ];
        NSArray<CICaptionCue *> *bridged =
            CIBridgeShortCaptionGaps(cues, CICaptionShortGapBridgeSeconds);
        CIAssert(bridged.count == cues.count, @"bridging must keep every cue");
        CIAssert(fabs(bridged[0].endTime - 2.2) < 0.001,
            @"a 0.2s silence should keep the previous line until the next start");
        CIAssert(fabs(bridged[1].endTime - 3.0) < 0.001,
            @"a 3s instrumental gap should still show the gap state");
        CIAssert(fabs(bridged[2].endTime - 7.0) < 0.001,
            @"overlapping cues must not be modified");
        CIAssert([bridged[0].text isEqualToString:@"a"] &&
            fabs(bridged[0].startTime - 1.0) < 0.001,
            @"bridging must keep the cue text and start");
        NSArray<CICaptionCue *> *bridgedTwice =
            CIBridgeShortCaptionGaps(bridged, CICaptionShortGapBridgeSeconds);
        CIAssert(fabs(bridgedTwice[0].endTime - 2.2) < 0.001 &&
            fabs(bridgedTwice[1].endTime - 3.0) < 0.001,
            @"bridging must be idempotent for cached cue sets");

        CIAssert(fabs(CISanitizedPlaybackRate(1.5) - 1.5) < 0.001,
            @"a normal speed should pass through");
        CIAssert(fabs(CISanitizedPlaybackRate(0) - 1.0) < 0.001 &&
            fabs(CISanitizedPlaybackRate(NAN) - 1.0) < 0.001,
            @"a missing or paused rate should fall back to 1x");
        CIAssert(fabs(CISanitizedPlaybackRate(16) - 4.0) < 0.001,
            @"an absurd rate should be clamped");
        CIAssert(fabs(CIExtrapolatedPlaybackTime(10, 100, 102, 2.0) - 14.0) < 0.001,
            @"two wall seconds at 2x should advance four media seconds");
        CIAssert(fabs(CIExtrapolatedPlaybackTime(10, 100, 99, 1.0) - 10.0) < 0.001,
            @"an uptime before the anchor must not rewind the estimate");

        CIAssert(CIIsBackwardPlaybackJitter(9.85, 10.015,
            CIPlaybackJitterToleranceSeconds),
            @"a sample slightly behind the timer estimate is jitter");
        CIAssert(!CIIsBackwardPlaybackJitter(8.0, 10.0,
            CIPlaybackJitterToleranceSeconds),
            @"a two-second backward move is a seek");
        CIAssert(!CIIsBackwardPlaybackJitter(10.2, 10.0,
            CIPlaybackJitterToleranceSeconds),
            @"a forward sample is never jitter");
        CIAssert(!CIIsBackwardPlaybackJitter(5.0, -DBL_MAX,
            CIPlaybackJitterToleranceSeconds),
            @"an unset reference must not suppress samples");
        NSLog(@"Caption timing smoke passed");
    }
    return 0;
}
