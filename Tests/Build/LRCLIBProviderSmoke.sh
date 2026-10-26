#!/bin/bash
set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd -P)"
project_dir="$(cd "$script_dir/../.." && pwd -P)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror -framework Foundation \
  "$project_dir/Tests/ObjC/LRCLIBProviderSmoke.m" \
  "$project_dir/CILRCLIBProvider.m" "$project_dir/CICaptionParser.m" \
  "$project_dir/CITextUtilities.m" "$project_dir/CIConstants.m" \
  "$project_dir/CIModels.m" "$project_dir/CILogStore.m" \
  -o "$test_dir/lrclib-provider-smoke"
TMPDIR="$test_dir/" "$test_dir/lrclib-provider-smoke"
