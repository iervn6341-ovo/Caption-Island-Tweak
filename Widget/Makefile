# The widget uses public ActivityFamily APIs introduced in the iOS 18 SDK.
# Use the newest installed SDK independently of the tweaks' private-header SDK;
# runtime availability checks retain the host's iOS 17.5 deployment target.
CAPTION_ISLAND_WIDGET_SDK_VERSION ?= latest
override TARGET := iphone:clang:$(CAPTION_ISLAND_WIDGET_SDK_VERSION):17.5
ARCHS = arm64
THEOS_OBJ_DIR_NAME = obj/CaptionIslandWidget

include $(THEOS)/makefiles/common.mk

ifneq ($(call __vercmp,$(_THEOS_TARGET_SDK_VERSION),ge,18.0),1)
$(error CaptionIslandWidget requires an iOS 18+ SDK; install Xcode 16 or newer)
endif

APPEX_NAME = CaptionIslandWidget

CaptionIslandWidget_FILES = \
	CaptionIslandWidget.swift \
	CaptionSmallActivityView.swift \
	../Shared/CICaptionActivityAttributes.swift
CaptionIslandWidget_FRAMEWORKS = Foundation SwiftUI WidgetKit ActivityKit
CaptionIslandWidget_SWIFT_VERSION = 5
CaptionIslandWidget_INSTALL = 0
CaptionIslandWidget_APP_EXTENSION_SAFE_API = 1
CaptionIslandWidget_APP_EXTENSION_SAFE = 1

include $(THEOS_MAKE_PATH)/appex.mk
