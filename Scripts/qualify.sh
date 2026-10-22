#!/bin/bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"
app=;evidence=;args=("$@")
while [ "$#" -gt 0 ]; do
 case "$1" in --app) app=$2;shift 2;; --evidence-dir) evidence=$2;shift 2;; --fixture-manifest|--host-label) shift 2;; *) echo "Unknown argument $1" >&2;exit 2;; esac
done
[ -d "$app/Contents" ] && [ -n "$evidence" ] && [ ! -e "$evidence" ]
app=$(cd "$app" && pwd)
# Bind test expectations to the actual thin candidate, never a hardcoded CPU.
app_arch=$(python3 - "$app" <<'PYARCH'
import json,pathlib,subprocess,sys
app=pathlib.Path(sys.argv[1]);identity=json.loads((app/'Contents/Resources/build-identity.json').read_text())
arch=identity.get('architecture');actual=subprocess.check_output(['/usr/bin/lipo','-archs',str(app/'Contents/MacOS/RestoreGPSTime')],text=True).strip()
if arch not in ('arm64','x86_64') or actual!=arch:raise SystemExit('Candidate CPU differs from its build identity')
print(arch)
PYARCH
)
mkdir -p work
run_dir=$(mktemp -d "$repo_root/work/qa-run.XXXXXX")
source=$(git rev-parse HEAD)
# All regression media is generated. Suppress the opt-in system Trash operation.
set +e
env -u RESTOREGPSTIME_TEST_SYSTEM_TRASH RESTOREGPSTIME_TEST_ARCH="$app_arch" RESTOREGPSTIME_TEST_APP="$app" RESTOREGPSTIME_TEST_APP_BUNDLE="$app" Scripts/test.sh > "$run_dir/regression.log" 2>&1
regression_exit=$?
set -e
if [ -n "$(git status --porcelain)" ]; then source=uncommitted; fi
export CLANG_MODULE_CACHE_PATH="$repo_root/work/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$repo_root/work/module-cache"
swift build --disable-sandbox --cache-path "$repo_root/work/swift-cache" --config-path "$repo_root/work/swift-config" --security-path "$repo_root/work/swift-security" --product RestoreGPSTimeQA
bin_path=$(swift build --disable-sandbox --cache-path "$repo_root/work/swift-cache" --config-path "$repo_root/work/swift-config" --security-path "$repo_root/work/swift-security" --show-bin-path)
exec env RESTOREGPSTIME_QA_REGRESSION_LOG="$run_dir/regression.log" RESTOREGPSTIME_QA_REGRESSION_SOURCE="$source" RESTOREGPSTIME_QA_REGRESSION_EXIT="$regression_exit" "$bin_path/RestoreGPSTimeQA" "${args[@]}"
