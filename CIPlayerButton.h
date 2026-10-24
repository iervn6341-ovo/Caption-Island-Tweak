#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CIPlayerButtonPosition) {
    /// With autoplay, captions and the overflow menu.
    CIPlayerButtonPositionTop = 0,
    /// Beside the fullscreen button, next to the copy-timestamp button.
    CIPlayerButtonPositionBottom = 1,
};

/// Registers the in-player button with YTVideoOverlay and installs the two overlay
/// hooks that supply its image and tap handler.
///
/// Safe to call when YTVideoOverlay is absent: registration is a message to a class
/// looked up by name, and each hook group is gated on its class existing.
FOUNDATION_EXPORT void CIInstallPlayerButton(void);

/// Whether the button is shown. Backed by a Caption Island preference rather than
/// YTVideoOverlay's own key, which is what lets the switch live on this tweak's
/// settings screen instead of under "Player buttons".
FOUNDATION_EXPORT BOOL CIPlayerButtonEnabled(void);
FOUNDATION_EXPORT void CISetPlayerButtonEnabled(BOOL enabled);

/// The button uses the bottom-right slot beside fullscreen. The setter retains
/// source compatibility and migrates any legacy top placement to the bottom.
FOUNDATION_EXPORT CIPlayerButtonPosition CIPlayerButtonPosition_(void);
FOUNDATION_EXPORT void CISetPlayerButtonPosition(
    CIPlayerButtonPosition position
);

NS_ASSUME_NONNULL_END
