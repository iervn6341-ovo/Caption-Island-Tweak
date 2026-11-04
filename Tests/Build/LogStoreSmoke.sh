#!/bin/bash
set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd -P)"
project_dir="$(cd "$script_dir/../.." && pwd -P)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror -framework Foundation \
  "$project_dir/Tests/ObjC/LogStoreSmoke.m" "$project_dir/CILogStore.m" \
  -o "$test_dir/log-store-smoke"
TMPDIR="$test_dir/" "$test_dir/log-store-smoke"
