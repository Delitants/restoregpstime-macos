#!/bin/bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
arch=arm64; configuration=debug; output="$repo_root/work/test-bundles/arm64"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --arch) arch=$2; shift 2;; --configuration) configuration=$2; shift 2;; --output) output=$2; shift 2;;
    *) echo "Unknown argument: $1" >&2; exit 2;;
  esac
done
case "$arch" in arm64|x86_64) ;; *) exit 2;; esac
case "$configuration" in debug|release) ;; *) exit 2;; esac
cd "$repo_root"
"$repo_root/Scripts/build-runtime.sh" --arch "$arch"
export CLANG_MODULE_CACHE_PATH="$repo_root/work/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$repo_root/work/module-cache"
export MACOSX_DEPLOYMENT_TARGET=13.0
swift_flags=(--disable-sandbox --cache-path "$repo_root/work/swift-cache" --config-path "$repo_root/work/swift-config" --security-path "$repo_root/work/swift-security" --arch "$arch" --configuration "$configuration")
swift build "${swift_flags[@]}" --product RestoreGPSTime
bin_path=$(swift build "${swift_flags[@]}" --show-bin-path)
mkdir -p "$output"
output=$(cd "$output" && pwd)
app="$output/RestoreGPSTime.app"
if [ -e "$app" ]; then echo "Output exists: $app. Choose a new output directory; builds do not overwrite evidence." >&2; exit 1; fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/PlugIns/PerlModules" "$app/Contents/Resources/PerlRuntime" "$app/Contents/Resources/ExifTool" "$app/Contents/Resources/Notices"
cp "$bin_path/RestoreGPSTime" "$app/Contents/MacOS/RestoreGPSTime"
cp "$repo_root/App/Info.plist" "$app/Contents/Info.plist"
cp "$repo_root/App/Resources/AppIcon.icns" "$app/Contents/Resources/"
cp "$repo_root/work/runtime-install/$arch-macos13/bin/perl" "$app/Contents/Helpers/perl"
cp -R "$repo_root/work/runtime-install/$arch-macos13/lib" "$app/Contents/Resources/PerlRuntime/"
python3 - "$app" <<'PY'
import pathlib,shutil,sys
app=pathlib.Path(sys.argv[1]); archroot=app/'Contents/Resources/PerlRuntime/lib/perl5/5.44.0/darwin-2level'
native=app/'Contents/PlugIns/PerlModules'
for path in archroot.rglob('*.bundle'):
    target=native/path.relative_to(archroot);target.parent.mkdir(parents=True,exist_ok=True)
    shutil.move(str(path),str(target))
PY
cp "$repo_root/work/runtime-install/$arch-macos13/build-receipt.json" "$app/Contents/Resources/runtime-identity.json"
cp "$repo_root/work/sources/exiftool-13.59/exiftool" "$app/Contents/Resources/ExifTool/"
cp -R "$repo_root/work/sources/exiftool-13.59/lib" "$app/Contents/Resources/ExifTool/"
cp -R "$repo_root/ThirdParty/" "$app/Contents/Resources/Notices/"
if [ -d "$repo_root/Sources/RestoreGPSTimeCore/Resources" ]; then
  cp "$repo_root/Sources/RestoreGPSTimeCore/Resources/"*.json "$app/Contents/Resources/"
fi
# Local test signing only. Developer ID/notarization is a separate release gate.
python3 - "$app" <<'PY'
import pathlib,subprocess,sys
app=pathlib.Path(sys.argv[1]);magic={b'\xcf\xfa\xed\xfe',b'\xca\xfe\xba\xbe'}
for path in sorted(app.rglob('*'),key=lambda p:len(p.parts),reverse=True):
    if not path.is_file() or path.is_symlink():continue
    if path == app/'Contents/MacOS/RestoreGPSTime':continue
    with path.open('rb') as f:head=f.read(4)
    if head in magic:subprocess.run(['/usr/bin/codesign','--force','--sign','-',str(path)],check=True)
PY
/usr/bin/codesign --force --sign - "$app"
/usr/bin/codesign --verify --deep --strict "$app"
printf '%s\n' "$app"
