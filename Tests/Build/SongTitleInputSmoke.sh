#!/bin/bash
set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd -P)"
project_dir="$(cd "$script_dir/../.." && pwd -P)"
app_dir="${1:?Pass an output .app directory}"
mkdir -p "$app_dir"
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror \
  -target "$(uname -m)-apple-ios17.5-simulator" \
  -isysroot "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -framework UIKit -framework Foundation \
  "$project_dir/Tests/UIKit/SongTitleInputSmoke.m" "$project_dir/CISongTitleInput.m" \
  "$project_dir/CITextUtilities.m" "$project_dir/CIConstants.m" "$project_dir/CILogStore.m" \
  -o "$app_dir/SongTitleInputSmoke"
cp "$project_dir/Tests/UIKit/SongTitleInputSmoke-Info.plist" "$app_dir/Info.plist"
codesign --force --sign - "$app_dir"
