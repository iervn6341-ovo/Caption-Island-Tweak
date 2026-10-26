// The in-player Caption Island button.
//
// Registration goes through YTVideoOverlay rather than hooking the overlay
// directly: that framework already owns placement (anchored off the fullscreen
// button and walking left), visibility, the fullscreen superview swap, and the
// user-facing visibility/order settings. Caption Island requests one fixed
// bottom slot; the hooks below provide its image, gray background and action,
// with a defensive cleanup of legacy top copies.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <math.h>

#import "../YTVideoOverlay/Header.h"
#import "../YTVideoOverlay/Init.x"

#import "CIConstants.h"
#import "CIPlayerButton.h"
#import "CIPlayerControlPanel.h"

// Must differ from "CaptionIsland". YTVideoOverlay titles its settings rows with
// _LOC(TweakBundle(key), @"ENABLED"), resolving that bundle exactly the way
// CIConstants does, so reusing the tweak's own key would label the button switch
// with CaptionIsland.bundle's existing ENABLED string — "Enable Live Activity" —
// and find no POSITION string at all.
static NSString *const CIButtonTweakKey = @"CaptionIslandLyrics";
// Passed to YTVideoOverlay as ToggleKey, which makes it read this key instead of
// its own "YTVideoOverlay-<name>-Enabled" and suppresses the duplicate switch it
// would otherwise draw in its own settings section.
static NSString *const CIPlayerButtonEnabledKey =
    @"CaptionIsland.PlayerButtonEnabled";
// YTVideoOverlay's own position key. Not mirrored into a Caption Island key: the
// framework reads this one directly during layout, so a copy could disagree.
static NSString *CIPlayerButtonPositionKey(void) {
    return [NSString stringWithFormat:@"YTVideoOverlay-%@-Position",
        CIButtonTweakKey];
}

BOOL CIPlayerButtonEnabled(void) {
    return [NSUserDefaults.standardUserDefaults
        boolForKey:CIPlayerButtonEnabledKey];
}

void CISetPlayerButtonEnabled(BOOL enabled) {
    [NSUserDefaults.standardUserDefaults setBool:enabled
                                          forKey:CIPlayerButtonEnabledKey];
}

CIPlayerButtonPosition CIPlayerButtonPosition_(void) {
    return CIPlayerButtonPositionBottom;
}

void CISetPlayerButtonPosition(CIPlayerButtonPosition position) {
    (void)position;
    [NSUserDefaults.standardUserDefaults setInteger:CIPlayerButtonPositionBottom
        forKey:CIPlayerButtonPositionKey()];
}

@interface YTMainAppControlsOverlayView (CaptionIslandButton)
- (void)didPressCaptionIsland:(id)arg;
@end

@interface YTInlinePlayerBarContainerView (CaptionIslandButton)
- (void)didPressCaptionIsland:(id)arg;
@end

/// The glyph, sized and coloured to match YouTube's own overlay controls.
///
/// An SF Symbol rather than bundled art: it removes a packaging failure mode
/// (art that silently does not reach the .bundle leaves an invisible button),
/// and it already matches the weight of the controls beside it. Rendered
/// non-template because YTVideoOverlay sets the image directly on the button
/// without configuring a tint.
static UIImage *CIButtonImage(void) {
    static UIImage *image;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UIImageSymbolConfiguration *configuration =
            [UIImageSymbolConfiguration
                configurationWithPointSize:28
                                    weight:UIImageSymbolWeightSemibold];
        UIImage *symbol = [UIImage systemImageNamed:@"captions.bubble"
                                  withConfiguration:configuration];
        if (!symbol) {
            symbol = [UIImage systemImageNamed:@"text.bubble"
                             withConfiguration:configuration];
        }
        image = [symbol imageWithTintColor:UIColor.whiteColor
                            renderingMode:UIImageRenderingModeAlwaysOriginal];
    });
    return image;
}

static const void *CIPlayerButtonMaterial = &CIPlayerButtonMaterial;

@interface CIPlayerCaptionButton : UIButton
@end
@implementation CIPlayerCaptionButton
- (CGSize)intrinsicContentSize { return CGSizeMake(44, 44); }
- (CGSize)sizeThatFits:(CGSize)size { (void)size; return CGSizeMake(44, 44); }
- (CGRect)imageRectForContentRect:(CGRect)rect {
    return CGRectMake(CGRectGetMidX(rect) - 14, CGRectGetMidY(rect) - 14, 28, 28);
}
- (void)layoutSubviews {
    [super layoutSubviews];
    // Keep the white glyph above the sampled material. The button's parent
    // still controls the normal native fade-in/fade-out of the whole control.
    self.imageView.alpha = 1;
    self.imageView.layer.zPosition = 1;
    self.imageView.layer.shadowColor = UIColor.blackColor.CGColor;
    self.imageView.layer.shadowOpacity = 0.65;
    self.imageView.layer.shadowRadius = 1;
    self.imageView.layer.shadowOffset = CGSizeZero;
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.imageView.alpha = 1;
}
@end

static UIVisualEffectView *CIButtonEffectInView(UIView *view, UIView *excluded, NSUInteger depth) {
    if (!view || view == excluded || view.hidden || view.alpha < 0.05 || depth > 4) return nil;
    if ([view isKindOfClass:UIVisualEffectView.class] && ((UIVisualEffectView *)view).effect) return (UIVisualEffectView *)view;
    for (UIView *child in view.subviews) {
        UIVisualEffectView *effect = CIButtonEffectInView(child, excluded, depth + 1);
        if (effect) return effect;
    }
    return nil;
}

static UIView *CIPlayerFullscreenReference(YTInlinePlayerBarContainerView *bar) {
    UIView *reference = [bar respondsToSelector:@selector(enterFullscreenButton)] ? [bar enterFullscreenButton] : nil;
    if (!reference || reference.hidden || reference.alpha < 0.05)
        reference = [bar respondsToSelector:@selector(exitFullscreenButton)] ? [bar exitFullscreenButton] : nil;
    if ((!reference || reference.hidden || reference.alpha < 0.05) &&
        [bar respondsToSelector:@selector(enterExitFullscreenButton)]) reference = [bar enterExitFullscreenButton];
    if (!reference || reference.hidden) return nil;
    for (NSUInteger depth = 0; depth < 3; ++depth) {
        UIView *parent = reference.superview;
        if (!parent || parent == bar || [NSStringFromClass(parent.class) containsString:@"Overlay"]) break;
        CGSize size = parent.bounds.size;
        CGRect child = [reference convertRect:reference.bounds toView:parent];
        if (size.width < 28 || size.width > 64 || size.height < 28 || size.height > 64 ||
            fabs(size.width - size.height) > 8 || fabs(CGRectGetMidX(child) - CGRectGetMidX(parent.bounds)) > 4 ||
            fabs(CGRectGetMidY(child) - CGRectGetMidY(parent.bounds)) > 4) break;
        reference = parent;
    }
    return reference;
}

static void CIStylePlayerButton(UIView *button, UIView *reference) {
    UIVisualEffectView *owned = objc_getAssociatedObject(button, CIPlayerButtonMaterial);
    UIVisualEffectView *native = CIButtonEffectInView(reference, nil, 0);
    UIVisualEffectView *existing = CIButtonEffectInView(button, owned, 0);
    if (!owned) {
        owned = [[UIVisualEffectView alloc] initWithEffect:nil];
        owned.userInteractionEnabled = NO;
        objc_setAssociatedObject(button, CIPlayerButtonMaterial, owned, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    existing.hidden = YES; // Do not paint the plugin's larger hit area as a second circle.
    if (owned.superview != button) [button insertSubview:owned atIndex:0];
    CGFloat visualExtent = native ? MIN(native.bounds.size.width, native.bounds.size.height) :
        (reference.layer.cornerRadius > 0 ? reference.layer.cornerRadius * 2 : 36);
    visualExtent = MIN(40, MAX(28, visualExtent));
    CGRect materialFrame = CGRectMake(CGRectGetMidX(button.bounds) - visualExtent / 2,
        CGRectGetMidY(button.bounds) - visualExtent / 2, visualExtent, visualExtent);
    if (!CGRectEqualToRect(owned.frame, materialFrame)) owned.frame = materialFrame;
    if (owned.layer.cornerRadius != visualExtent / 2) owned.layer.cornerRadius = visualExtent / 2;
    owned.layer.cornerCurve = kCACornerCurveContinuous;
    owned.clipsToBounds = YES;
    owned.layer.zPosition = -1;
    if (native && !UIAccessibilityIsReduceTransparencyEnabled()) {
        if (owned.effect != native.effect) owned.effect = native.effect;
        owned.backgroundColor = UIColor.clearColor;
    } else {
        if (owned.effect) owned.effect = nil;
        UIColor *background = reference.backgroundColor;
        if ((!background || CGColorGetAlpha(background.CGColor) < 0.05) && reference.layer.backgroundColor)
            background = [UIColor colorWithCGColor:reference.layer.backgroundColor];
        if (!background || CGColorGetAlpha(background.CGColor) < 0.05)
            background = [UIColor colorWithWhite:0.20 alpha:UIAccessibilityIsReduceTransparencyEnabled() ? 1.0 : 0.65];
        owned.backgroundColor = background;
    }
    button.backgroundColor = UIColor.clearColor;
    button.layer.borderWidth = 0;
    button.layer.cornerRadius = 0;
    button.clipsToBounds = NO;
}

%group CaptionIslandButtonTop

%hook YTMainAppControlsOverlayView

- (void)layoutSubviews {
    %orig;
    // Remove any legacy top copy, including when YouTube makes all native
    // controls visible again. The patched helper no longer creates this copy.
    UIView *button = self.overlayButtons[CIButtonTweakKey];
    button.hidden = YES;
    button.alpha = 0;
    [button removeFromSuperview];
}

- (UIImage *)buttonImage:(NSString *)tweakId {
    return [tweakId isEqualToString:CIButtonTweakKey]
        ? CIButtonImage() : %orig;
}

%new(v@:@)
- (void)didPressCaptionIsland:(id)arg {
    // The panel resolves its own presenter by walking the presented-controller
    // chain, so the overlay's own controller is not needed and nil is expected.
    CIPresentPlayerControlPanel(nil);
}

%end

%end

%group CaptionIslandButtonBottom

%hook YTInlinePlayerBarContainerView

- (void)layoutSubviews {
    %orig;
    UIView *button = self.overlayButtons[CIButtonTweakKey];
    if (button == nil) return;
    CIStylePlayerButton(button, CIPlayerFullscreenReference(self));
}

- (UIImage *)buttonImage:(NSString *)tweakId {
    return [tweakId isEqualToString:CIButtonTweakKey]
        ? CIButtonImage() : %orig;
}

%new(v@:@)
- (void)didPressCaptionIsland:(id)arg {
    CIPresentPlayerControlPanel(nil);
}

%end

%end

void CIInstallPlayerButton(void) {
    // Migrate existing top-placement preferences to the single bottom button.
    CISetPlayerButtonPosition(CIPlayerButtonPositionBottom);
    // YTVideoOverlay defaults a newly registered tweak to disabled and to the
    // top-right slot. Seed both so the button appears beside the fullscreen
    // control without the user having to find the setting first;
    // registerDefaults never overwrites a value the user has already chosen.
    [NSUserDefaults.standardUserDefaults registerDefaults:@{
        CIPlayerButtonEnabledKey: @YES,
        CIPlayerButtonPositionKey(): @(CIPlayerButtonPositionBottom),
    }];
    initYTVideoOverlay(CIButtonTweakKey, @{
        @"providesBackground": @YES,
        @"buttonFactory": [^UIButton *(UIView *host, BOOL top) {
            (void)top;
            UIButton *button = [CIPlayerCaptionButton buttonWithType:UIButtonTypeCustom];
            button.frame = CGRectMake(0, 0, 44, 44);
            button.tintColor = UIColor.whiteColor;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            button.adjustsImageWhenHighlighted = NO;
            button.adjustsImageWhenDisabled = NO;
#pragma clang diagnostic pop
            [button setImage:CIButtonImage() forState:UIControlStateNormal];
            button.accessibilityIdentifier = @"YTVideoOverlay-CaptionIslandLyrics";
            [button addTarget:host action:NSSelectorFromString(@"didPressCaptionIsland:")
                forControlEvents:UIControlEventTouchUpInside];
            return button;
        } copy],
        AccessibilityLabelKey: CILocalized(@"PANEL_TITLE", @"Caption Island"),
        SelectorKey: @"didPressCaptionIsland:",
        @"fixedPosition": @(CIPlayerButtonPositionBottom),
        // Our key, so the switch lives on the Caption Island settings screen and
        // YTVideoOverlay does not draw a second one of its own.
        ToggleKey: CIPlayerButtonEnabledKey,
    });
    if (NSClassFromString(@"YTMainAppControlsOverlayView")) {
        %init(CaptionIslandButtonTop);
    }
    if (NSClassFromString(@"YTInlinePlayerBarContainerView")) {
        %init(CaptionIslandButtonBottom);
    }
}
