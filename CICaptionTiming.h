#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Positive advance values make a caption appear earlier.
FOUNDATION_EXPORT NSTimeInterval CIAdjustedCaptionLookupTime(
    NSTimeInterval playbackTime,
    NSTimeInterval advance
);

FOUNDATION_EXPORT NSTimeInterval CIAdjustedCaptionBoundary(
    NSTimeInterval mediaBoundary,
    NSTimeInterval advance
);

@class CICaptionCue;

/// Silences shorter than this keep the previous line on screen instead of
/// submitting a separate "♪" gap update to ActivityKit.
FOUNDATION_EXPORT const NSTimeInterval CICaptionShortGapBridgeSeconds;

/// A playback sample this far behind the caption clock is reporting latency,
/// not a seek. Larger backward moves are still honoured as seeks.
FOUNDATION_EXPORT const NSTimeInterval CIPlaybackJitterToleranceSeconds;

/// Extends each cue to the following cue's start when the silence between them
/// is positive but shorter than `maximumGap`. Overlaps and longer gaps are left
/// untouched. The operation is idempotent.
FOUNDATION_EXPORT NSArray<CICaptionCue *> *CIBridgeShortCaptionGaps(
    NSArray<CICaptionCue *> *cues,
    NSTimeInterval maximumGap
);

/// Returns a usable media-seconds-per-wall-second rate. Non-finite, zero and
/// out-of-range values fall back to 1.0; the result is clamped to 0.25...4.
FOUNDATION_EXPORT double CISanitizedPlaybackRate(double rate);

/// anchorTime + elapsed wall time × rate. Elapsed time never goes negative.
FOUNDATION_EXPORT NSTimeInterval CIExtrapolatedPlaybackTime(
    NSTimeInterval anchorTime,
    NSTimeInterval anchorUptime,
    NSTimeInterval uptime,
    double rate
);

/// YES when `sample` is behind `reference` by no more than `tolerance`.
FOUNDATION_EXPORT BOOL CIIsBackwardPlaybackJitter(
    NSTimeInterval sample,
    NSTimeInterval reference,
    NSTimeInterval tolerance
);

/// A raw clock that lands further than this from where continuous playback
/// would have put it was moved by a seek (Lock Screen scrubber, skip buttons).
FOUNDATION_EXPORT const NSTimeInterval CIPlaybackSeekThresholdSeconds;

/// YES when the raw media clock moved since the previous sample, but not by
/// roughly `elapsed × rate`: the player jumped rather than played. A clock that
/// stood still is not a seek, so a frozen getter keeps its existing handling.
FOUNDATION_EXPORT BOOL CIIsPlaybackSeek(
    NSTimeInterval previousRawTime,
    NSTimeInterval rawTime,
    NSTimeInterval elapsed,
    double rate,
    NSTimeInterval threshold
);

NS_ASSUME_NONNULL_END
