# CaptionIsland

With a compatible YTKACE build, settings are consolidated under **YTKACE → Caption Island**.
The integrated page uses UIKit and shares its row definitions and preference actions
with the standalone YouTube settings entry. Mode, caption-source and duration choices
use YTKACE's shared system-menu presenter when available. The standalone entry remains
available when the integration interface is absent. Preference keys and existing data
are unchanged.

CaptionIsland is a tweak that displays captions and lyrics for the video
currently playing in YouTube.

## Player button

The KACE-Youtube YTVideoOverlay adapter uses a public UIKit button with a 44pt
touch target and a centered 28pt semibold white caption glyph. Its material circle is separate
from the touch area: it follows the fullscreen control within 28–40pt, with a
36pt fallback. This avoids YouTube's private icon padding and the previous
oversized background. The image sits above the sampled material at full local
opacity with a subtle contrast shadow; native whole-control fading remains intact.
The button remains fixed at the bottom; visibility lives
in CaptionIsland settings. Older YTVideoOverlay builds retain the legacy factory.

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

Both CaptionIsland.dylib and the widget compile and link against the iPhoneOS SDK
shipped with the selected Xcode. Build/AppleSDK.mk overrides inherited TARGET,
SYSROOT and ISYSROOT so the host's Swift bridge cannot accidentally import Swift
overlays from a downloaded Theos SDK. The widget requires an iOS 18+ SDK (Xcode
16+). Deployment remains iOS 17.5, which uses the original Activity configuration.

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
