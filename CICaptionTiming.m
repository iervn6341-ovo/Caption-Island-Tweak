#import "CICaptionTiming.h"
#import "CIModels.h"
#import <math.h>

NSTimeInterval CIAdjustedCaptionLookupTime(
    NSTimeInterval playbackTime,
    NSTimeInterval advance
) {
    if (!isfinite(playbackTime)) return 0;
    if (!isfinite(advance)) advance = 0;
    // A negative result is intentional: it keeps a cue that begins at media
    // time zero hidden until a negative advance (delay) has elapsed.
    return playbackTime + advance;
}

NSTimeInterval CIAdjustedCaptionBoundary(
    NSTimeInterval mediaBoundary,
    NSTimeInterval advance
) {
    if (!isfinite(mediaBoundary)) return 0;
    if (!isfinite(advance)) advance = 0;
    return MAX(0, mediaBoundary - advance);
}

const NSTimeInterval CICaptionShortGapBridgeSeconds = 1.2;
const NSTimeInterval CIPlaybackJitterToleranceSeconds = 0.5;

NSArray<CICaptionCue *> *CIBridgeShortCaptionGaps(
    NSArray<CICaptionCue *> *cues,
    NSTimeInterval maximumGap
) {
    if (cues.count < 2 || !isfinite(maximumGap) || maximumGap <= 0) {
        return [cues copy] ?: @[];
    }
    NSMutableArray<CICaptionCue *> *result =
        [NSMutableArray arrayWithCapacity:cues.count];
    for (NSUInteger index = 0; index < cues.count; index++) {
        CICaptionCue *cue = cues[index];
        if (index + 1 < cues.count) {
            NSTimeInterval nextStart = cues[index + 1].startTime;
            NSTimeInterval gap = nextStart - cue.endTime;
            if (isfinite(gap) && gap > 0 && gap < maximumGap &&
                nextStart > cue.startTime) {
                cue = [[CICaptionCue alloc] initWithStartTime:cue.startTime
                                                      endTime:nextStart
                                                         text:cue.text];
            }
        }
        [result addObject:cue];
    }
    return [result copy];
}

double CISanitizedPlaybackRate(double rate) {
    if (!isfinite(rate) || rate <= 0.001) return 1.0;
    return MIN(4.0, MAX(0.25, rate));
}

NSTimeInterval CIExtrapolatedPlaybackTime(
    NSTimeInterval anchorTime,
    NSTimeInterval anchorUptime,
    NSTimeInterval uptime,
    double rate
) {
    if (!isfinite(anchorTime)) return 0;
    if (!isfinite(anchorUptime) || !isfinite(uptime)) return anchorTime;
    NSTimeInterval estimate = anchorTime +
        MAX(0, uptime - anchorUptime) * CISanitizedPlaybackRate(rate);
    return isfinite(estimate) ? estimate : anchorTime;
}

BOOL CIIsBackwardPlaybackJitter(
    NSTimeInterval sample,
    NSTimeInterval reference,
    NSTimeInterval tolerance
) {
    if (!isfinite(sample) || !isfinite(reference) ||
        !isfinite(tolerance) || tolerance <= 0) return NO;
    NSTimeInterval lag = reference - sample;
    return lag > 0 && lag <= tolerance;
}

const NSTimeInterval CIPlaybackSeekThresholdSeconds = 1.0;

BOOL CIIsPlaybackSeek(
    NSTimeInterval previousRawTime,
    NSTimeInterval rawTime,
    NSTimeInterval elapsed,
    double rate,
    NSTimeInterval threshold
) {
    if (!isfinite(previousRawTime) || !isfinite(rawTime) ||
        !isfinite(elapsed) || elapsed < 0 ||
        !isfinite(threshold) || threshold <= 0) return NO;
    if (fabs(rawTime - previousRawTime) < 0.04) return NO;
    NSTimeInterval expected = previousRawTime +
        elapsed * CISanitizedPlaybackRate(rate);
    return fabs(rawTime - expected) > threshold;
}
