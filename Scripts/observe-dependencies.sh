#!/bin/bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
app=;output=
while [ "$#" -gt 0 ]; do
 case "$1" in --app) app=$2;shift 2;; --output) output=$2;shift 2;; *) exit 2;; esac
done
[ -d "$app/Contents" ] && [ -n "$output" ] && [ ! -e "$output" ]
cd "$repo_root"
export CLANG_MODULE_CACHE_PATH="$repo_root/work/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$repo_root/work/module-cache"
flags=(--disable-sandbox --cache-path "$repo_root/work/swift-cache" --config-path "$repo_root/work/swift-config" --security-path "$repo_root/work/swift-security" --arch "$(uname -m)")
swift build "${flags[@]}" --product RestoreGPSTimeQA
bin_path=$(swift build "${flags[@]}" --show-bin-path)
exec "$bin_path/RestoreGPSTimeQA" --dependency-app "$app" --dependency-output "$output"
