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
runtime_prefix=$("$repo_root/Scripts/build-runtime.sh" --arch "$arch" --print-prefix)
export CLANG_MODULE_CACHE_PATH="$repo_root/work/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$repo_root/work/module-cache"
export MACOSX_DEPLOYMENT_TARGET=13.0
swift_flags=(--disable-sandbox --cache-path "$repo_root/work/swift-cache" --config-path "$repo_root/work/swift-config" --security-path "$repo_root/work/swift-security" --arch "$arch" --configuration "$configuration")
swift build "${swift_flags[@]}" --product RestoreGPSTime
swift build "${swift_flags[@]}" --product RestoreGPSTimeDroplet
bin_path=$(swift build "${swift_flags[@]}" --show-bin-path)
mkdir -p "$output"
output=$(cd "$output" && pwd)
app="$output/RestoreGPSTime.app"
if [ -e "$app" ]; then echo "Output exists: $app. Choose a new output directory; builds do not overwrite evidence." >&2; exit 1; fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/PlugIns/PerlModules" "$app/Contents/Resources/PerlRuntime" "$app/Contents/Resources/ExifTool" "$app/Contents/Resources/Notices"
cp "$bin_path/RestoreGPSTime" "$app/Contents/MacOS/RestoreGPSTime"
cp "$repo_root/App/Info.plist" "$app/Contents/Info.plist"
python3 - "$app" "$arch" "$configuration" <<'PYBUILD'
import datetime,json,pathlib,subprocess,sys
app=pathlib.Path(sys.argv[1]);source=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
dirty=bool(subprocess.check_output(['git','status','--porcelain'],text=True).strip())
(app/'Contents/Resources/build-identity.json').write_text(json.dumps({'schema':1,'sourceCommit':source,'sourceDirty':dirty,'architecture':sys.argv[2],'configuration':sys.argv[3],'minimumOS':'13.0'},sort_keys=True)+'\n')
PYBUILD
cp "$repo_root/App/Resources/AppIcon.icns" "$app/Contents/Resources/"
cp "$runtime_prefix/bin/perl" "$app/Contents/Helpers/perl"
cp -R "$runtime_prefix/lib" "$app/Contents/Resources/PerlRuntime/"
python3 - "$app" "$runtime_prefix" <<'PY'
import pathlib,shutil,stat,sys
app=pathlib.Path(sys.argv[1]); archroot=app/'Contents/Resources/PerlRuntime/lib/perl5/5.44.0/darwin-2level'
native=app/'Contents/PlugIns/PerlModules'
# Installation receipts are retained in the developer cache, not distributed.
for path in archroot.rglob('.packlist'):
    if path.is_file() and not path.is_symlink():path.unlink()
# These are developer installation descriptions, not runtime search paths.
for relative in ['Config_heavy.pl','CORE/config.h']:
    path=archroot/relative
    if path.is_file() and not path.is_symlink():
        note=b'RestoreGPSTime packaging 2026-10-22: local installation prefix neutralized; bundled runtime search paths unchanged.'
        comment=b'# '+note+b'\n' if relative.endswith('.pl') else b'/* '+note+b' */\n'
        data=comment+path.read_bytes().replace(sys.argv[2].encode(),b'/RestoreGPSTimeRuntime')
        mode=path.stat().st_mode & 0o777
        path.chmod(mode | stat.S_IWUSR);path.write_bytes(data);path.chmod(mode)
for path in archroot.rglob('*.bundle'):
    target=native/path.relative_to(archroot);target.parent.mkdir(parents=True,exist_ok=True)
    shutil.move(str(path),str(target))
PY
cp "$runtime_prefix/build-receipt.json" "$app/Contents/Resources/runtime-identity.json"
cp "$repo_root/work/sources/exiftool-13.59/exiftool" "$app/Contents/Resources/ExifTool/"
cp -R "$repo_root/work/sources/exiftool-13.59/lib" "$app/Contents/Resources/ExifTool/"
cp -R "$repo_root/ThirdParty/" "$app/Contents/Resources/Notices/"
if [ -d "$repo_root/Sources/RestoreGPSTimeCore/Resources" ]; then
  cp "$repo_root/Sources/RestoreGPSTimeCore/Resources/"*.json "$app/Contents/Resources/"
fi
droplet="$app/Contents/Resources/DropletTemplate.app"
mkdir -p "$droplet/Contents/MacOS" "$droplet/Contents/Resources"
cp "$bin_path/RestoreGPSTimeDroplet" "$droplet/Contents/MacOS/RestoreGPSTimeDroplet"
cp "$repo_root/App/DropletInfo.plist" "$droplet/Contents/Info.plist"
cp "$repo_root/App/Resources/AppIcon.icns" "$droplet/Contents/Resources/"
cp "$repo_root/App/Resources/DropletWorkflow.rgtimeworkflow" "$droplet/Contents/Resources/Workflow.rgtimeworkflow"
cp "$repo_root/Sources/RestoreGPSTimeCore/Resources/writable-tags.json" "$droplet/Contents/Resources/"
# Local test signing only. Developer ID/notarization is a separate release gate.
python3 - "$app" "$configuration" <<'PY'
import pathlib,subprocess,sys
app=pathlib.Path(sys.argv[1]);magic={b'\xcf\xfa\xed\xfe',b'\xca\xfe\xba\xbe'}
for path in sorted(app.rglob('*'),key=lambda p:len(p.parts),reverse=True):
    if not path.is_file() or path.is_symlink():continue
    with path.open('rb') as f:head=f.read(4)
    if head in magic:
        if sys.argv[2]=='release':
            mode=path.stat().st_mode & 0o777
            path.chmod(mode | 0o200)
            try:subprocess.run(['/usr/bin/strip','-S',str(path)],check=True)
            finally:path.chmod(mode)
        if path != app/'Contents/MacOS/RestoreGPSTime':subprocess.run(['/usr/bin/codesign','--force','--sign','-',str(path)],check=True)
PY
/usr/bin/codesign --force --sign - "$droplet"
/usr/bin/codesign --force --sign - "$app"
/usr/bin/codesign --verify --deep --strict "$app"
if [ "$configuration" = release ]; then "$repo_root/Scripts/audit-bundle-paths.py" --app "$app" --repository "$repo_root";fi
printf '%s\n' "$app"
