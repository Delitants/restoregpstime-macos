#!/bin/bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"
mkdir -p work/module-cache work/swift-cache work/swift-config work/swift-security
exec env CLANG_MODULE_CACHE_PATH="$repo_root/work/module-cache" SWIFTPM_MODULECACHE_OVERRIDE="$repo_root/work/module-cache" \
  swift test --disable-sandbox --cache-path "$repo_root/work/swift-cache" --config-path "$repo_root/work/swift-config" --security-path "$repo_root/work/swift-security" "$@"
