#!/bin/bash
set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd -P)"
project_dir="$(cd "$script_dir/../.." && pwd -P)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
for module in ActivityKit UIKit; do
  xcrun swiftc -swift-version 5 -emit-library -emit-module -module-name "$module" \
    "$project_dir/Tests/ActivityLifecycle/$module.swift" \
    -emit-module-path "$test_dir/$module.swiftmodule" -o "$test_dir/lib$module.dylib" \
    -module-cache-path "$test_dir/cache"
done
# Keep the manager private in production; appending tests to the same source
# file exercises the actual implementation without exposing test-only APIs.
python3 - "$project_dir" "$test_dir/Smoke.swift" <<'PY'
import pathlib, sys
root, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
source = (root / 'CIActivityBridge.swift').read_text().replace('UserDefaults.standard', 'testDefaults')
out.write_text(source + '\n' + (root / 'Tests/ActivityLifecycle/Smoke.swift').read_text())
PY
xcrun swiftc -swift-version 5 -parse-as-library -I "$test_dir" -L "$test_dir" \
  -lActivityKit -lUIKit -Xlinker -rpath -Xlinker "$test_dir" \
  -module-cache-path "$test_dir/cache" \
  "$project_dir/Shared/CICaptionActivityAttributes.swift" "$test_dir/Smoke.swift" \
  -o "$test_dir/activity-lifecycle-smoke"
"$test_dir/activity-lifecycle-smoke"
