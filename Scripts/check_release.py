#!/usr/bin/env python3
import argparse,json,pathlib,plistlib,subprocess,tempfile,zipfile
from release_gate import COMMON_ASSETS,inspect_app,release_names,sha256,validate_manifest,validate_pair,verify_assets,gatekeeper_accepted
def tree_hashes(app):
 result={}
 for path in sorted(app.rglob('*')):
  if path.is_symlink():raise ValueError('Unexpected installed app symlink')
  if path.is_file():result[str(path.relative_to(app))]=sha256(path)
 return result
p=argparse.ArgumentParser();p.add_argument('--directory',required=True);p.add_argument('--arch',required=True,choices=['arm64','x86_64']);p.add_argument('--source-commit',required=True);p.add_argument('--peer-manifest');a=p.parse_args()
root=pathlib.Path(a.directory).resolve();work=pathlib.Path(tempfile.mkdtemp(prefix='release-check-',dir=root));errors=[]
def run(args,name):
 r=subprocess.run(args,text=True,capture_output=True);(work/(name+'.txt')).write_text(r.stdout+r.stderr)
 if r.returncode:errors.append(name+' failed; retained local receipt')
 return r
try:
 m=json.loads((root/'release-evidence.json').read_text());errors+=validate_manifest(m)+verify_assets(m,root)
 if m.get('architecture')!=a.arch or m.get('sourceCommit')!=a.source_commit:errors.append('Requested architecture/source differs from manifest')
 if a.peer_manifest:errors+=validate_pair(m,json.loads(pathlib.Path(a.peer_manifest).read_text()))
 else:errors.append('Matching peer manifest is required for stable publication')
 expected=release_names(m.get('version'),a.arch)|COMMON_ASSETS|{'release-evidence.json'}
 lines=(root/'SHA256SUMS.txt').read_text().splitlines();seen=set()
 for line in lines:
  digest,name=line.split('  ',1)
  if name not in expected or name in seen or (root/name).is_symlink() or sha256(root/name)!=digest:raise ValueError('Invalid checksum inventory or changed asset')
  seen.add(name)
 if seen!=expected:errors.append('Checksum inventory is incomplete')
 zipname=next(name for name in release_names(m.get('version'),a.arch) if name.endswith('.zip'))
 with zipfile.ZipFile(root/zipname) as archive:
  total=0
  for info in archive.infolist():
   parts=pathlib.PurePosixPath(info.filename).parts
   if info.filename.startswith('/') or '..' in parts or not parts or parts[0] not in ('RestoreGPSTime.app','__MACOSX'):raise ValueError('Unsafe ZIP entry')
   total+=info.file_size
  if total>2_147_483_648:raise ValueError('App ZIP exceeds its two GiB extraction bound')
 run(['/usr/bin/ditto','-x','-k',str(root/zipname),str(work/'extracted')],'extract-zip')
 app=work/'extracted/RestoreGPSTime.app'
 inventory=inspect_app(app)
 if inventory!=m.get('binaries'):errors.append('Extracted app Mach-O inventory differs from manifest')
 if sha256(app/'Contents/MacOS/RestoreGPSTime')!=m.get('appHash'):errors.append('Extracted executable differs from acceptance identity')
 observer=pathlib.Path(__file__).resolve().parent/'observe-dependencies.sh'
 observed_path=work/'observed-dependencies.json'
 observed=run([str(observer),'--app',str(app),'--output',str(observed_path)],'dependency-observation')
 if observed.returncode==0 and json.loads(observed_path.read_text())!=m.get('dependencyIdentity'):errors.append('Extracted runtime/database/capability hashes differ from the exact acceptance identity')
 build=json.loads((app/'Contents/Resources/build-identity.json').read_text())
 if build.get('sourceCommit')!=a.source_commit or build.get('sourceDirty') is not False or build.get('architecture')!=a.arch or build.get('configuration')!='release':errors.append('App build identity is not the exact clean release source')
 info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
 if info.get('CFBundleShortVersionString')!=m.get('version') or info.get('LSMinimumSystemVersion')!='13.0':errors.append('App version/minimum OS differs from release')
 run(['/usr/bin/codesign','--verify','--deep','--strict',str(app)],'codesign-verify')
 identity=run(['/usr/bin/codesign','--display','--verbose=4',str(app)],'codesign-identity').stderr
 if 'Authority=Developer ID Application:' not in identity or 'runtime' not in identity or 'TeamIdentifier='+m.get('signing',{}).get('teamID','') not in identity:errors.append('Actual signing identity or hardened runtime did not qualify')
 run(['/usr/bin/xcrun','stapler','validate',str(app)],'staple-validate')
 assessment=run(['/usr/sbin/spctl','--assess','--type','execute','--verbose=4',str(app)],'gatekeeper-app')
 if not gatekeeper_accepted(assessment.stdout+assessment.stderr):errors.append('Normal notarized Gatekeeper acceptance is missing or overridden')
 # Both archives must install the same signed app. Mounting/install and quarantine
 # qualification are separately recorded native gates; never infer them from ZIP.
 dmg=next(name for name in release_names(m.get('version'),a.arch) if name.endswith('.dmg'))
 run(['/usr/bin/hdiutil','verify',str(root/dmg)],'dmg-verify')
 mount=work/'mounted';mount.mkdir()
 attached=run(['/usr/bin/hdiutil','attach','-readonly','-nobrowse','-mountpoint',str(mount),str(root/dmg)],'dmg-attach')
 if attached.returncode==0:
  try:
   if tree_hashes(mount/'RestoreGPSTime.app')!=tree_hashes(app):errors.append('DMG and ZIP apps differ')
   link=mount/'Applications'
   if not link.is_symlink() or str(link.readlink())!='/Applications':errors.append('DMG Applications link differs')
  finally:run(['/usr/bin/hdiutil','detach',str(mount)],'dmg-detach')
 run(['/usr/bin/xcrun','stapler','validate',str(root/dmg)],'dmg-staple-validate')
except (OSError,ValueError,TypeError,KeyError,StopIteration,zipfile.BadZipFile,subprocess.SubprocessError) as e:errors.append(str(e))
(work/'check-result.json').write_text(json.dumps({'schema':1,'stableReady':not errors,'errors':errors},indent=2)+'\n')
for error in errors:print('BLOCKED: '+error)
print('Local checker receipt: '+str(work/'check-result.json'))
raise SystemExit(2 if errors else 0)
