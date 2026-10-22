#!/bin/bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
arch=;version=;source=;output=;identity=;profile=
while [ "$#" -gt 0 ]; do
 case "$1" in --arch) arch=$2;shift 2;; --version) version=$2;shift 2;; --source-commit) source=$2;shift 2;; --output) output=$2;shift 2;; --identity) identity=$2;shift 2;; --keychain-profile) profile=$2;shift 2;; *) echo "Unknown argument $1" >&2;exit 2;; esac
done
case "$arch" in arm64) label=AppleSilicon;; x86_64) label=Intel;; *) exit 2;; esac
[ "$version" = 1.0.0 ] && [ -n "$output" ]
cd "$repo_root"
[ "$(git rev-parse HEAD)" = "$source" ] && [ -z "$(git status --porcelain)" ] || { echo 'Package the exact clean source commit only.' >&2;exit 2; }
[ ! -e "$output" ] || { echo 'Output exists; failed evidence is never overwritten.' >&2;exit 2; }
mkdir -p "$output";output=$(cd "$output" && pwd)
Scripts/build-app.sh --arch "$arch" --configuration release --output "$output/build" > "$output/build.log" 2>&1
app="$output/build/RestoreGPSTime.app"
python3 - "$app" "$version" <<'PY'
import pathlib,plistlib,sys
for p in [pathlib.Path(sys.argv[1])/'Contents/Info.plist',pathlib.Path(sys.argv[1])/'Contents/Resources/DropletTemplate.app/Contents/Info.plist']:
 data=plistlib.loads(p.read_bytes());data['CFBundleShortVersionString']=sys.argv[2];data['CFBundleVersion']='1';p.write_bytes(plistlib.dumps(data))
PY
# Plist updates invalidate ad-hoc signatures; re-sign nested app before parent.
/usr/bin/codesign --force --sign - "$app/Contents/Resources/DropletTemplate.app" >> "$output/build.log" 2>&1
/usr/bin/codesign --force --sign - "$app" >> "$output/build.log" 2>&1
if [ -n "$identity" ] || [ -n "$profile" ]; then
 Scripts/sign-and-notarize.sh --app "$app" --identity "$identity" --keychain-profile "$profile" --evidence-dir "$output/signing"
fi
# Observe identities with the same implementation used by frozen plans/QA,
# after final signing. This mode does not execute the foreign-CPU helper.
Scripts/observe-dependencies.sh --app "$app" --output "$output/dependency-identity.json" > "$output/dependency-build.log" 2>&1
stage="$output/dmg-root";mkdir "$stage"
/usr/bin/ditto "$app" "$stage/RestoreGPSTime.app"
ln -s /Applications "$stage/Applications"
cp docs/INSTALL.md "$stage/INSTALL.md"
name="RestoreGPSTime-$version-$label"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$output/$name.zip"
/usr/bin/hdiutil create -volname "RestoreGPSTime $version ($label)" -srcfolder "$stage" -format UDZO "$output/$name.dmg" > "$output/dmg.log" 2>&1
if [ -n "$identity" ]; then
 /usr/bin/codesign --sign "$identity" --timestamp "$output/$name.dmg"
 xcrun notarytool submit "$output/$name.dmg" --keychain-profile "$profile" --wait --output-format json > "$output/signing/dmg-notary-result.json"
 python3 - "$output/signing/dmg-notary-result.json" <<'PY'
import json,sys
if json.load(open(sys.argv[1])).get('status')!='Accepted':raise SystemExit('DMG notarization did not return Accepted')
PY
 xcrun stapler staple "$output/$name.dmg" >> "$output/signing/staple.txt" 2>&1
fi
cp docs/{INSTALL,RECOVERY,KNOWN-LIMITS}.md "$output/"
cp docs/acceptance/{format-matrix.json,reference-actions.csv,reference-tools.csv} "$output/"
cp ThirdParty/NOTICES.txt "$output/THIRD-PARTY-NOTICES.txt"
cp LICENSE "$output/LICENSE.txt"
/usr/bin/ditto -c -k --keepParent ThirdParty "$output/DEPENDENCY-LICENSES.zip"
python3 "$repo_root/Scripts/package_manifest.py" --directory "$output" --arch "$arch" --source-commit "$source" --version "$version"
echo "Local candidate: $output (stable publication requires check-release.sh and native acceptance)."
