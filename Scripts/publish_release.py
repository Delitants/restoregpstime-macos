#!/usr/bin/env python3
"""Publish only a fully checked candidate; retain receipts and never clobber."""
import argparse,json,pathlib,subprocess,tempfile
from publication_guard import history_errors
from release_gate import public_asset_hashes,sha256,upload_disposition,validate_pair,verify_assets,validate_publication_target
p=argparse.ArgumentParser();p.add_argument('--repository',required=True,choices=['Delitants/restoregpstime-macos']);p.add_argument('--tag',required=True,choices=['v1.0.0-arm64','v1.0.0-x86_64']);p.add_argument('--manifest',required=True);p.add_argument('--peer-manifest',required=True);a=p.parse_args()
manifest=pathlib.Path(a.manifest).resolve();peer=pathlib.Path(a.peer_manifest).resolve();root=manifest.parent
m=json.loads(manifest.read_text());other=json.loads(peer.read_text())
errors=validate_pair(m,other)+verify_assets(m,root)+verify_assets(other,peer.parent)
if m.get('tag')!=a.tag:errors.append('Tag differs from exact candidate manifest')
if errors:raise SystemExit('Publication blocked: '+'; '.join(errors))
repo_root=pathlib.Path(__file__).resolve().parents[1]
source=subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo_root,text=True).strip()
if source!=m['sourceCommit'] or subprocess.check_output(['git','status','--porcelain'],cwd=repo_root,text=True).strip():raise SystemExit('Publication requires the exact clean reviewed source checkout')
source_errors=history_errors(repo_root,source)
if source_errors:raise SystemExit('Publication blocked: '+'; '.join(source_errors))
expected=public_asset_hashes(m,root)
# Re-run actual archive/signature checks before any API call that mutates state.
subprocess.run([str(repo_root/'Scripts/check-release.sh'),'--directory',str(root),'--arch',m['architecture'],'--source-commit',source,'--peer-manifest',str(peer)],check=True)
subprocess.run([str(repo_root/'Scripts/check-release.sh'),'--directory',str(peer.parent),'--arch',other['architecture'],'--source-commit',source,'--peer-manifest',str(manifest)],check=True)
receipts=pathlib.Path(tempfile.mkdtemp(prefix='publish-',dir=repo_root/'work'))
count=0

def api(path,*extra,optional=False):
 global count
 count+=1;r=subprocess.run(['gh','api',path,*extra],capture_output=True)
 (receipts/f'{count:03d}-response.json').write_bytes(r.stdout);(receipts/f'{count:03d}-stderr.txt').write_bytes(r.stderr)
 if r.returncode:
  if optional and b'HTTP 404' in r.stderr:return None
  raise RuntimeError('GitHub API failed; retained receipts at '+str(receipts))
 return json.loads(r.stdout)

account=api('user');repository=api('repos/'+a.repository)
if repository.get('full_name')!=a.repository or repository.get('private') is not False:raise SystemExit('Repository identity/public visibility differs; no publication performed')
api(f'repos/{a.repository}/commits/{source}')
ref=api(f'repos/{a.repository}/git/ref/tags/{a.tag}',optional=True)
if ref:
 obj=ref['object'];depth=0
 while obj['type']=='tag' and depth<8:obj=api(f'repos/{a.repository}/git/tags/{obj["sha"]}')['object'];depth+=1
 if obj.get('type')!='commit' or obj.get('sha')!=source:raise SystemExit('Existing tag points to different content; never replace it')
release=api(f'repos/{a.repository}/releases/tags/{a.tag}',optional=True)
if release is None:
 release=api(f'repos/{a.repository}/releases','-X','POST','-f','tag_name='+a.tag,'-f','target_commitish='+source,'-f','name=RestoreGPSTime 1.0.0 ('+m['architecture']+')','-f','body=Restore photo and video dates and place names on macOS 13+. See the attached installation and undo help.','-F','draft=true')
target_errors=validate_publication_target(release,obj.get('sha') if ref else None,source)
if target_errors:raise SystemExit('; '.join(target_errors))
allowed=set(expected)
existing={x['name']:x for x in release['assets']}
if not set(existing).issubset(allowed):raise SystemExit('Existing release contains unexpected assets; retain and review it')

def download(asset,destination):
 with destination.open('xb') as f:r=subprocess.run(['gh','api',f'repos/{a.repository}/releases/assets/{asset["id"]}','-H','Accept: application/octet-stream'],stdout=f,stderr=subprocess.PIPE)
 if r.returncode:raise RuntimeError('Asset download failed; retained receipts')
 return sha256(destination)

dispositions={}
for name,digest in expected.items():
 if sha256(root/name)!=digest:raise SystemExit('Local asset changed during publication')
 previous=download(existing[name],receipts/('existing-'+name)) if name in existing else None
 dispositions[name]=upload_disposition(digest,previous)
for name,disposition in dispositions.items():
 if disposition=='upload':
  if sha256(root/name)!=expected[name]:raise SystemExit('Local asset changed after preflight')
  # gh refuses an existing asset; deliberately omit --clobber.
  subprocess.run(['gh','release','upload',a.tag,str(root/name),'--repo',a.repository],check=True)
readback=api(f'repos/{a.repository}/releases/tags/{a.tag}');assets={x['name']:x for x in readback['assets']}
if set(assets)!=set(expected):raise SystemExit('Release asset inventory differs after upload; draft retained')
for name,digest in expected.items():
 if download(assets[name],receipts/('readback-'+name))!=digest:raise SystemExit('Release asset read-back differs; draft retained')
if readback.get('draft'):
 readback=api(f'repos/{a.repository}/releases/{readback["id"]}','-X','PATCH','-F','draft=false')
final_ref=api(f'repos/{a.repository}/git/ref/tags/{a.tag}')
final_object=final_ref['object'];depth=0
while final_object['type']=='tag' and depth<8:final_object=api(f'repos/{a.repository}/git/tags/{final_object["sha"]}')['object'];depth+=1
if final_object.get('type')!='commit' or final_object.get('sha')!=source:raise SystemExit('Published tag read-back does not name the reviewed source; retain partial publication receipts')
(receipts/'publication-result.json').write_text(json.dumps({'repository':a.repository,'tag':a.tag,'sourceCommit':source,'authenticatedLogin':account.get('login'),'url':readback['html_url'],'assetHashes':expected},indent=2)+'\n')
print(readback['html_url']);print('Retained publication receipts: '+str(receipts))
