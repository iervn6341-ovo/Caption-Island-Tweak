#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."

# Exercise the production include with the same command-line overrides the
# aggregate build passes, without needing Theos or a decrypted IPA.
make --no-print-directory -s -f - \
  TARGET=iphone:clang:17.5:17.5 \
  SYSROOT=/invalid/downloaded-iPhoneOS17.5.sdk \
  ISYSROOT=/invalid/downloaded-iPhoneOS17.5.sdk <<'MAKE'
include Build/AppleSDK.mk
.PHONY: check
check:
	@test "$(SYSROOT)" = "$$(xcrun --sdk iphoneos --show-sdk-path)"
	@test "$(ISYSROOT)" = "$(SYSROOT)"
	@test "$(TARGET)" = "iphone:clang:$$(xcrun --sdk iphoneos --show-sdk-version):17.5"
	@test -d "$(SYSROOT)/System/Library/Frameworks/ActivityKit.framework"
	@printf 'CaptionIsland SDK selection passed: %s; deployment target 17.5\n' "$(CI_XCODE_IOS_SDK_VERSION)"
MAKE

host_sources=(Shared/CICaptionActivityAttributes.swift CIActivityBridge.swift)
if [ -f CIActivityCommandPipeline.swift ]; then
  host_sources+=(CIActivityCommandPipeline.swift)
fi
xcrun --sdk iphoneos swiftc -typecheck -parse-as-library -swift-version 5 \
  -target arm64-apple-ios17.5 -sdk "$(xcrun --sdk iphoneos --show-sdk-path)" \
  "${host_sources[@]}"
