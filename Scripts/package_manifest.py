#!/usr/bin/env python3
import argparse,json,pathlib,subprocess
from release_gate import COMMON_ASSETS,REQUIRED_GATES,CURRENT_OS_MAJOR_BY_ARCH,inspect_app,release_names,sha256
p=argparse.ArgumentParser();p.add_argument('--directory',required=True);p.add_argument('--arch',required=True);p.add_argument('--source-commit',required=True);p.add_argument('--version',required=True);a=p.parse_args()
root=pathlib.Path(a.directory);app=root/'build/RestoreGPSTime.app'
identity=subprocess.run(['/usr/bin/codesign','--display','--verbose=4',str(app)],text=True,capture_output=True).stderr
team=next((line.split('=',1)[1] for line in identity.splitlines() if line.startswith('TeamIdentifier=')),'unavailable')
notary=root/'signing/notary-result.json';accepted=json.loads(notary.read_text()).get('status') if notary.is_file() else 'missing'
assets=[]
for name in sorted(release_names(a.version,a.arch)|COMMON_ASSETS):
 if not (root/name).is_file():raise SystemExit('Missing packaged document/archive: '+name)
 assets.append({'name':name,'sha256':sha256(root/name)})
m={'schema':1,'application':'RestoreGPSTime','version':a.version,'architecture':a.arch,'minimumOS':'13.0','currentOSMajorByArchitecture':CURRENT_OS_MAJOR_BY_ARCH,'sourceCommit':a.source_commit,'reviewedSourceCommit':None,'peerSourceCommit':None,'tag':f'v{a.version}-{a.arch}','stableReady':False,
 'appHash':sha256(app/'Contents/MacOS/RestoreGPSTime'),'dependencyIdentity':json.loads((root/'dependency-identity.json').read_text()),'signing':{'developerID':'Authority=Developer ID Application:' in identity,'hardenedRuntime':'runtime' in identity,'notarization':accepted,'stapled':False,'teamID':team},
 'privacy':{'audited':False,'privateMaterial':None,'secretFound':None},'gates':{g:'missing' for g in REQUIRED_GATES},'hosts':[],'binaries':inspect_app(app),'assets':assets,
 'note':'Local candidate. Review and bind actual acceptance/signing evidence before stable checks; missing is not pass.'}
with (root/'release-evidence.json').open('x') as f:json.dump(m,f,indent=2,sort_keys=True);f.write('\n')
with (root/'SHA256SUMS.txt').open('x') as f:
 for name in sorted(x['name'] for x in assets):f.write(sha256(root/name)+'  '+name+'\n')
