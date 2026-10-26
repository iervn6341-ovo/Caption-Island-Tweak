# CaptionIsland contains Swift as well as Objective-C. Compile and link both
# against the SDK shipped with the selected Xcode, not a downloaded Theos SDK's
# Swift overlays. Parent TARGET/SYSROOT command-line settings must not leak in.
CI_XCODE_IOS_SDK_PATH := $(shell xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)
CI_XCODE_IOS_SDK_VERSION := $(shell xcrun --sdk iphoneos --show-sdk-version 2>/dev/null)
ifeq ($(strip $(CI_XCODE_IOS_SDK_PATH)),)
$(error CaptionIsland requires a selected Xcode with an iPhoneOS SDK; check DEVELOPER_DIR)
endif
ifeq ($(strip $(CI_XCODE_IOS_SDK_VERSION)),)
$(error Could not determine the selected Xcode iPhoneOS SDK version)
endif

HOST_DEPLOYMENT_VERSION ?= 17.5
override TARGET := iphone:clang:$(CI_XCODE_IOS_SDK_VERSION):$(HOST_DEPLOYMENT_VERSION)
override SYSROOT := $(CI_XCODE_IOS_SDK_PATH)
override ISYSROOT := $(CI_XCODE_IOS_SDK_PATH)
