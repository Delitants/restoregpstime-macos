#!/usr/bin/env python3
"""Fail-closed stable release contract. Never uploads or changes GitHub state."""
import argparse,hashlib,json,pathlib,re,subprocess,sys
CURRENT_OS_MAJOR_BY_ARCH={'arm64':27,'x86_64':26}
REQUIRED_GATES=('baseline-regression','genuine-formats','large-video','volumes','native-ui','finder-services-droplets','finder-isolated-login','instruments-10000','relocated-offline','source-review')
COMMON_ASSETS={'INSTALL.md','RECOVERY.md','KNOWN-LIMITS.md','THIRD-PARTY-NOTICES.txt','DEPENDENCY-LICENSES.zip','LICENSE.txt'}
def sha256(path):
    h=hashlib.sha256()
    with pathlib.Path(path).open('rb') as f:
        for b in iter(lambda:f.read(1048576),b''):h.update(b)
    return h.hexdigest()
def release_names(version,arch):
    label={'arm64':'AppleSilicon','x86_64':'Intel'}.get(arch,'INVALID')
    return {f'RestoreGPSTime-{version}-{label}.{ext}' for ext in ('zip','dmg')}
def valid_hash(value,length):return isinstance(value,str) and re.fullmatch('[0-9a-f]{'+str(length)+'}',value) is not None
def min_os(value):
    if not isinstance(value,str) or not re.fullmatch(r'\d+\.\d+(?:\.\d+)?',value):return False
    return tuple(map(int,value.split('.')))<=(13,0,0)
def valid_dependency(value):
    return isinstance(value,dict) and set(value)=={'engineHash','databaseHash','capabilityHash'} and all(valid_hash(v,64) for v in value.values())
def validate_manifest(m):
    errors=[]
    if not isinstance(m,dict):return ['Manifest is not an object']
    arch=m.get('architecture');version=m.get('version');source=m.get('sourceCommit')
    if m.get('schema')!=1 or m.get('application')!='RestoreGPSTime':errors.append('Unsupported release identity')
    if arch not in ('arm64','x86_64') or version!='1.0.0' or m.get('tag')!=f'v{version}-{arch}' or m.get('minimumOS')!='13.0':errors.append('Wrong release version, architecture, tag or minimum OS')
    if not valid_hash(source,40) or m.get('reviewedSourceCommit')!=source or m.get('peerSourceCommit')!=source:errors.append('Both releases must share one reviewed source commit')
    signing=m.get('signing',{})
    if not isinstance(signing,dict) or any(signing.get(k) is not True for k in ('developerID','hardenedRuntime','stapled')) or signing.get('notarization')!='Accepted' or not re.fullmatch('[A-Z0-9]{10}',str(signing.get('teamID',''))):errors.append('Developer ID, hardened runtime, accepted notarization and stapling are required')
    privacy=m.get('privacy',{})
    if not isinstance(privacy,dict) or privacy.get('audited') is not True or privacy.get('privateMaterial') is not False or privacy.get('secretFound') is not False:errors.append('Public source and artifact privacy audit is incomplete')
    gates=m.get('gates',{})
    if not isinstance(gates,dict):gates={}
    for gate in REQUIRED_GATES:
        if gates.get(gate)!='pass':errors.append('Missing/failing gate: '+gate)
    current=m.get('currentOSMajorByArchitecture')
    if current!=CURRENT_OS_MAJOR_BY_ARCH:errors.append('Current supported OS matrix must match each architecture')
    if not isinstance(current,dict):current={}
    if not valid_hash(m.get('appHash'),64) or not valid_dependency(m.get('dependencyIdentity')):errors.append('Missing exact candidate application/dependency identity')
    hosts=m.get('hosts',[])
    if not isinstance(hosts,list):hosts=[]
    for cpu in ('arm64','x86_64'):
        for oldest in (True,False):
            found=[h for h in hosts if isinstance(h,dict) and h.get('architecture')==cpu and h.get('hardwareARM') is (cpu=='arm64') and h.get('translated') is False and h.get('status')=='pass' and h.get('sourceCommit')==source and valid_hash(h.get('appHash'),64) and valid_dependency(h.get('dependencyIdentity')) and (h.get('architecture')!=arch or h.get('appHash')==m.get('appHash') and h.get('dependencyIdentity')==m.get('dependencyIdentity')) and (h.get('osMajor')==13 if oldest else h.get('current') is True and isinstance(h.get('osMajor'),int) and h['osMajor']==current.get(cpu))]
            if len(found)!=1:errors.append(f'Missing or ambiguous native {cpu} '+('macOS 13' if oldest else 'current OS')+' acceptance')
    binaries=m.get('binaries',[])
    if not isinstance(binaries,list) or not binaries:errors.append('No Mach-O inventory');binaries=[]
    for binary in binaries:
        if not isinstance(binary,dict) or binary.get('architectures')!=[arch] or not min_os(binary.get('minimumOS')) or binary.get('platform')!='macOS':errors.append('Wrong Mach-O architecture or OS minimum');continue
        path=binary.get('path','')
        if not isinstance(path,str) or not path.startswith('Contents/') or '..' in pathlib.PurePosixPath(path).parts:errors.append('Unsafe binary path')
        for dep in binary.get('dependencies',[]):
            if not isinstance(dep,str) or not dep.startswith(('/System/Library/','/usr/lib/','@executable_path/../Frameworks/','@loader_path/')):errors.append('External or unresolved binary dependency')
    assets=m.get('assets',[])
    if not isinstance(assets,list):assets=[]
    names=[];allowed=release_names(version,arch)|COMMON_ASSETS
    for asset in assets:
        if not isinstance(asset,dict):errors.append('Invalid asset');continue
        name=asset.get('name');names.append(name)
        if name not in allowed or not valid_hash(asset.get('sha256'),64):errors.append('Unexpected asset name or checksum')
    if len(names)!=len(set(str(n) for n in names)) or not (release_names(version,arch)|COMMON_ASSETS).issubset(set(str(n) for n in names)):errors.append('Missing or duplicated architecture archives')
    return errors

def validate_pair(first,second):
    errors=validate_manifest(first)+validate_manifest(second)
    if {first.get('architecture'),second.get('architecture')}!={'arm64','x86_64'} or first.get('sourceCommit')!=second.get('sourceCommit'):errors.append('Architecture pair does not share its reviewed source')
    expected={m.get('architecture'):(m.get('appHash'),m.get('dependencyIdentity')) for m in [first,second]}
    for manifest in [first,second]:
        for host in manifest.get('hosts',[]):
            if isinstance(host,dict) and (host.get('appHash'),host.get('dependencyIdentity'))!=expected.get(host.get('architecture')):errors.append('Native host receipt does not bind the exact architecture candidate/dependencies')
    a,b=first.get('dependencyIdentity',{}),second.get('dependencyIdentity',{})
    if isinstance(a,dict) and isinstance(b,dict) and any(a.get(k)!=b.get(k) for k in ['databaseHash','capabilityHash']):errors.append('Candidate database/capability identities differ')
    return errors

def gatekeeper_accepted(output):
    lines=[line.strip() for line in output.splitlines()]
    return not any(line.lower().startswith('override=') for line in lines) and 'source=Notarized Developer ID' in lines and any(re.fullmatch(r'(?:.*: )?accepted',line) for line in lines)

def validate_publication_target(release,tag_commit,source):
    if tag_commit is not None:return [] if tag_commit==source else ['Existing tag does not name the reviewed commit']
    if release.get('draft') is not True or release.get('target_commitish')!=source:return ['An untagged draft must name the exact reviewed commit, without a moving branch alias']
    return []

def upload_disposition(expected_hash,existing_hash):
    if not valid_hash(expected_hash,64):raise ValueError('Invalid expected asset hash')
    if existing_hash is None:return 'upload'
    if existing_hash==expected_hash:return 'skip'
    raise ValueError('Existing asset has different content; no overwrite or deletion is allowed')

def verify_assets(m,root):
    errors=[];root=pathlib.Path(root)
    for asset in m.get('assets',[]):
        name=asset.get('name','')
        if name not in release_names(m.get('version'),m.get('architecture'))|COMMON_ASSETS:errors.append('Unsafe asset name');continue
        p=root/name
        if p.is_symlink() or not p.is_file() or sha256(p)!=asset.get('sha256'):errors.append('Missing/changed asset: '+name)
    return errors

def public_asset_hashes(m,root):
    root=pathlib.Path(root)
    required=release_names(m.get('version'),m.get('architecture'))|COMMON_ASSETS
    assets=m.get('assets',[])
    names=[a.get('name') for a in assets]
    if len(names)!=len(required) or set(names)!=required:
        raise ValueError('Public asset inventory differs from user downloads and documents')
    errors=verify_assets(m,root)
    checksums=root/'SHA256SUMS.txt'
    if errors or checksums.is_symlink() or not checksums.is_file():
        raise ValueError('; '.join(errors) or 'Missing public checksum file')
    return {**{a['name']:a['sha256'] for a in assets},'SHA256SUMS.txt':sha256(checksums)}

def inspect_app(app):
    app=pathlib.Path(app);result=[]
    for path in sorted(app.rglob('*')):
        if path.is_symlink():raise ValueError('Unexpected symlink inside app: '+str(path.relative_to(app)))
        if not path.is_file():continue
        with path.open('rb') as f:magic=f.read(4)
        if magic not in (b'\xcf\xfa\xed\xfe',b'\xfe\xed\xfa\xcf',b'\xca\xfe\xba\xbe',b'\xbe\xba\xfe\xca'):continue
        arch=subprocess.check_output(['/usr/bin/lipo','-archs',str(path)],text=True).strip().split()
        load=subprocess.check_output(['/usr/bin/otool','-l',str(path)],text=True)
        minimum=re.search(r'^\s*(?:minos|version) (\d+\.\d+(?:\.\d+)?)\s*$',load,re.M)
        # LC_ID_DYLIB compatibility versions are not OS deployment targets.
        build=re.search(r'cmd LC_BUILD_VERSION\n(?:(?!\n\s*Load command).)*?\n\s*minos (\S+)',load,re.S)
        legacy=re.search(r'cmd LC_VERSION_MIN_MACOSX\n(?:(?!\n\s*Load command).)*?\n\s*version (\S+)',load,re.S)
        target=build or legacy
        deps=subprocess.check_output(['/usr/bin/otool','-L',str(path)],text=True).splitlines()[1:]
        deps=[line.strip().split(' (compatibility version',1)[0] for line in deps]
        platform=re.search(r'cmd LC_BUILD_VERSION\n(?:(?!\n\s*Load command).)*?\n\s*platform (\S+)',load,re.S)
        platform_name='macOS' if (legacy or platform and platform.group(1) in ('1','MACOS','macos')) else 'unknown'
        result.append({'path':str(path.relative_to(app)),'architectures':arch,'minimumOS':target.group(1) if target else 'unknown','platform':platform_name,'dependencies':deps})
    return result

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--directory',required=True);parser.add_argument('--arch',required=True,choices=['arm64','x86_64']);parser.add_argument('--source-commit',required=True);parser.add_argument('--peer-manifest');args=parser.parse_args()
    root=pathlib.Path(args.directory)
    try:
        m=json.loads((root/'release-evidence.json').read_text());errors=validate_manifest(m)+verify_assets(m,root)
        if m.get('architecture')!=args.arch or m.get('sourceCommit')!=args.source_commit:errors.append('Requested candidate identity differs from manifest')
        if args.peer_manifest:errors+=validate_pair(m,json.loads(pathlib.Path(args.peer_manifest).read_text()))
        else:errors.append('Matching peer manifest is required before stable publication')
        for error in errors:print('BLOCKED: '+error)
        return 2 if errors else 0
    except (OSError,ValueError,TypeError,KeyError) as error:print('BLOCKED: '+str(error));return 2
if __name__=='__main__':sys.exit(main())
