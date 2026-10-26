include Build/AppleSDK.mk
ARCHS = arm64
INSTALL_TARGET_PROCESSES = YouTube

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CaptionIsland

CaptionIsland_FILES = \
	Tweak.xm \
	CISettings.xm \
	CISettingsUIKit.m \
	CIPlayerButton.xm \
	CIGearMenuItem.xm \
	CIBackgroundPlaybackMonitor.m \
	CIPlaybackState.m \
	CIConstants.m \
	CILanguagePriorityViewController.m \
	CITitleKeywordViewController.m \
	CIModels.m \
	CICaptionTiming.m \
	CIVideoEligibility.m \
	CIVideoOverrides.m \
	CITextUtilities.m \
	CICaptionParser.m \
	CILyricsAligner.m \
	CIYouTubeInspector.m \
	CILRCLIBProvider.m \
	CILogStore.m \
	CIProcessDiagnostics.m \
	CILRCLIBCacheViewController.m \
	CILogViewController.m \
	CIActivityPresenter.m \
	CICaptionCoordinator.m \
	CIPlayerControlPanel.m \
	CIActivityBridge.swift \
	Shared/CICaptionActivityAttributes.swift
CaptionIsland_CFLAGS = -fobjc-arc
CaptionIsland_FRAMEWORKS = UIKit Foundation QuartzCore ActivityKit MediaPlayer AVKit BackgroundTasks UniformTypeIdentifiers
CaptionIsland_SWIFT_VERSION = 5

include $(THEOS_MAKE_PATH)/tweak.mk
