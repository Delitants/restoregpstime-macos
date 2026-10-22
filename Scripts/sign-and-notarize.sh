#!/bin/bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
app=; identity=; profile=; evidence=
while [ "$#" -gt 0 ]; do
 case "$1" in --app) app=$2;shift 2;; --identity) identity=$2;shift 2;; --keychain-profile) profile=$2;shift 2;; --evidence-dir) evidence=$2;shift 2;; *) exit 2;; esac
done
case "$identity" in 'Developer ID Application: '*) ;; *) echo 'An existing Developer ID Application identity is required.' >&2;exit 2;; esac
[ -d "$app/Contents" ] && [ -n "$profile" ] && [ -n "$evidence" ]
[ ! -e "$evidence" ] || { echo 'Evidence exists; choose a new directory.' >&2;exit 2; }
mkdir -m 700 -p "$evidence"
python3 - "$app" "$identity" "$repo_root/App/RestoreGPSTime.entitlements" <<'PY'
import pathlib,subprocess,sys
app=pathlib.Path(sys.argv[1]);identity=sys.argv[2];entitlements=sys.argv[3]
for p in sorted(app.rglob('*'),key=lambda p:len(p.parts),reverse=True):
 if p.is_symlink():raise SystemExit('Unexpected app symlink')
 if not p.is_file():continue
 with p.open('rb') as f:magic=f.read(4)
 if magic in (b'\xcf\xfa\xed\xfe',b'\xca\xfe\xba\xbe'):
  subprocess.run(['/usr/bin/codesign','--force','--sign',identity,'--options','runtime','--timestamp','--entitlements',entitlements,str(p)],check=True)
for nested in sorted(app.rglob('*.app'),key=lambda p:len(p.parts),reverse=True):
 subprocess.run(['/usr/bin/codesign','--force','--sign',identity,'--options','runtime','--timestamp','--entitlements',entitlements,str(nested)],check=True)
subprocess.run(['/usr/bin/codesign','--force','--sign',identity,'--options','runtime','--timestamp','--entitlements',entitlements,str(app)],check=True)
PY
/usr/bin/codesign --verify --deep --strict "$app" > "$evidence/codesign-verify.txt" 2>&1
/usr/bin/codesign --display --verbose=4 "$app" > "$evidence/codesign-identity.txt" 2>&1
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$evidence/notary-submission.zip"
xcrun notarytool submit "$evidence/notary-submission.zip" --keychain-profile "$profile" --wait --output-format json > "$evidence/notary-result.json"
python3 - "$evidence/notary-result.json" <<'PY'
import json,sys
if json.load(open(sys.argv[1])).get('status')!='Accepted':raise SystemExit('Notarization did not return Accepted; retained result blocks release')
PY
xcrun stapler staple "$app" > "$evidence/staple.txt" 2>&1
xcrun stapler validate "$app" > "$evidence/staple-validate.txt" 2>&1
/usr/sbin/spctl --assess --type execute --verbose=4 "$app" > "$evidence/gatekeeper.txt" 2>&1

python3 - "$repo_root/Scripts" "$evidence/gatekeeper.txt" <<'PYGATE'
import pathlib,sys
sys.path.insert(0,sys.argv[1])
from release_gate import gatekeeper_accepted
if not gatekeeper_accepted(pathlib.Path(sys.argv[2]).read_text()):raise SystemExit('Gatekeeper assessment was overridden or did not confirm notarized Developer ID; evidence retained, qualification blocked')
PYGATE
