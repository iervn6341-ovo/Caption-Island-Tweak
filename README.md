# CaptionIsland

With a compatible YTKACE build, settings are consolidated under **YTKACE → Caption Island**.
The integrated page uses UIKit and shares its row definitions and preference actions
with the standalone YouTube settings entry. Mode, caption-source and duration choices
use YTKACE's shared system-menu presenter when available. The standalone entry remains
available when the integration interface is absent. Preference keys and existing data
are unchanged.

CaptionIsland is a tweak that displays captions and lyrics for the video
currently playing in YouTube.

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
