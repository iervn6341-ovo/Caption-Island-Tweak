# CaptionIsland

With a compatible YTKACE build, settings are consolidated under **YTKACE → Caption Island**.
The integrated page uses UIKit and shares its row definitions and preference actions
with the standalone YouTube settings entry. Mode, caption-source and duration choices
use YTKACE's shared system-menu presenter when available. The standalone entry remains
available when the integration interface is absent. Preference keys and existing data
are unchanged.

CaptionIsland is a tweak that displays captions and lyrics for the video
currently playing in YouTube.

## Caption-Fix AOD experiment

This branch adds **AOD update test fixes** to settings (default on here). It
coalesces adjacent unsent lyric/presentation commands and skips redundant
presentation refreshes within five seconds of a submission. Lifecycle controls
remain ordered; disabling the switch provides a FIFO comparison in the same
instrumented build. Restart YouTube before each A/B run.

With Detailed logging enabled, `[AODDiag]` records lifecycle/clock/cue stages,
queue waits, ActivityKit call duration and local content revisions. These entries
exclude lyric text and credentials. Content observations and `update` returns
are not AOD render acknowledgements. The existing LaunchPrefetch retention
strategy is unchanged; hook counters cannot prove system execution eligibility.
Expensive RunningBoard diagnostic sampling is limited to every 30 seconds.
Real repeated-lock/AOD tests are required to determine whether this helps.

## CarPlay and small Live Activities

On iOS 18 and later, the extension opts into the small Activity family used by
CarPlay (iOS 26+) and Apple Watch. The small layout uses the full content width
for the current cue, with the next cue underneath at lower contrast. It omits
the large caption icon, video title and source badge. Lyrics are not shortened
to the Dynamic Island compact presentation's 12-character preview.

The layout chooses up to three current-cue rows and two next-cue rows according
to the available height, falling back to fewer rows on short cards. At extreme
sizes only the current cue is shown. Long content uses tail ellipsis within the
card rather than drawing outside it. The system controls card size, placement
and update scheduling; this does not guarantee that arbitrary lyric lengths fit
or that every cue appears immediately on every head unit. The phone Lock Screen
and expanded Dynamic Island keep their existing layouts.

The widget builds with the newest installed iOS SDK (18+ required), independently
of the private-header SDK selected for the tweaks. Its deployment target remains
iOS 17.5, which uses the original Activity configuration. Xcode 16+ is required.

## Lyric sources

- **YouTube captions:** the video's available CC and ASR caption tracks.
- **LRCLIB:** synchronized LRC lyrics or plain-text lyrics returned by the
  [LRCLIB API](https://lrclib.net/).

## LRCLIB notice

CaptionIsland is independent from LRCLIB and is not affiliated with, endorsed
by, or sponsored by LRCLIB. CaptionIsland does not claim ownership of lyric
text, timestamps, metadata, or other data returned by LRCLIB; those rights
remain with their respective owners. Please comply with LRCLIB's terms and all
applicable rights when using its data.
