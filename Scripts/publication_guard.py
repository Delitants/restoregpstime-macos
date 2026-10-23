#!/usr/bin/env python3
"""Reject local-only material before source or release publication."""
import argparse,pathlib,re,subprocess,sys,zipfile

CLEAN_BASELINE='2bdc38b9f26ee4da42d9a925941249366bb74e31'
PUBLIC_DOCS={'README.md','CHANGELOG.md','docs/INSTALL.md','docs/RECOVERY.md','docs/KNOWN-LIMITS.md'}
SOURCE_EXTENSIONS={'App':{'.plist','.icns','.png','.entitlements','.rgtimeworkflow'},
                   'Scripts':{'.py','.sh','.swift'},'Sources':{'.swift'},'Tests':{'.swift','.py'}}
DATA_FILES={'Dependencies/dependencies.lock.json','Tests/Fixtures/manifest.json',
            'Sources/RestoreGPSTimeCore/Resources/container-capabilities.json',
            'Sources/RestoreGPSTimeCore/Resources/writable-tags.json'}
UPSTREAM_FILES={'ThirdParty/ExifTool-README.txt','ThirdParty/ExifTool-Upstream-LICENSE.txt',
                'ThirdParty/NOTICES.txt','ThirdParty/Perl-Artistic.txt','ThirdParty/Perl-Copying.txt'}
RUNTIME_JSON={'build-identity.json','runtime-identity.json','container-capabilities.json','writable-tags.json'}
MEDIA_TYPES={'.jpg','.jpeg','.heic','.heif','.tif','.tiff','.png','.mov','.mp4','.webp','.avif',
             '.nef','.nrw','.dng','.cr2','.cr3','.arw','.raf','.orf','.rw2','.m4v','.avi','.webm','.xmp'}
ROOT_FILES={'.gitattributes','.gitignore','LICENSE','Package.swift'}
PRIVATE_PARTS={'acceptance','superpowers','.superpowers','work','outputs','internal','reports',
               'test-reports','evidence','plans','privatefixtures','.codex','.agents'}
PRIVATE_NAMES={'release-info.json','release-evidence.json','format-matrix.json',
               'reference-actions.csv','reference-tools.csv','release.md','reference.md','host-matrix.json',
               'attributes-and-tools.md','automatic-timezones.md','metadata-profiles.md','preview-progress.md',
               'timestamp-precision.md','ui-checks.md','workflows-and-finder.md'}
REPORT_NAME=re.compile(r'(?:^|[-_ .])(?:test[-_ ]?(?:report|results)|planning|implementation[-_ ]?(?:plan|notes)|qualification|evidence)(?:[-_ .]|$)',re.I)
REPORT_TYPES={'.md','.txt','.json','.csv','.log','.pdf','.html','.yaml','.yml'}
INTERNAL_TEXT=re.compile(r'(?im)(?:\b\d+\s+(?:(?:unit|integration|native)\s+)?tests?\s+(?:passed|failed|skipped)\b|/Users/[^\s/]+/|^\s*(?:#+\s*)?(?:implementation plan|test results|test report|verification report|acceptance evidence|qualification results|post-signing checks|source commit|reviewed source|build log)(?:\b|:))')
USER_HELP_NAMES={'INSTALL.md','INSTALL.txt','RECOVERY.md','KNOWN-LIMITS.md'}

def internal_path_error(name):
    path=pathlib.PurePosixPath(name)
    if not name or not path.parts or path.is_absolute() or '..' in path.parts or '\\' in name:
        return 'unsafe path'
    parts=[part.removeprefix('._').casefold() for part in path.parts]
    if any(part in PRIVATE_PARTS for part in parts):return 'local-only directory'
    if parts[-1] in PRIVATE_NAMES:return 'local-only document'
    if path.suffix.casefold()=='.log':return 'local-only log'
    if path.suffix.casefold() in REPORT_TYPES and REPORT_NAME.search(parts[-1]):return 'internal report or planning document'
    return None

def source_path_error(name):
    error=internal_path_error(name)
    if error:return error
    path=pathlib.PurePosixPath(name)
    if name in {'.github/publication/guard.py','.github/publication/install-hooks.py','.github/publication/policy.json'}:return None
    if name in PUBLIC_DOCS or name in ROOT_FILES or name in DATA_FILES or name in UPSTREAM_FILES:return None
    if path.suffix.casefold() in SOURCE_EXTENSIONS.get(path.parts[0],set()):return None
    if path.parts[:2]==('Tests','Fixtures') and path.suffix.casefold() in MEDIA_TYPES:return None
    if path.parts[:2]==('.github','workflows') and path.suffix.casefold() in {'.yml','.yaml'}:return None
    if name in {'.githooks/pre-commit','.githooks/pre-push'}:return None
    if path.parts[:2]==('docs','images') and path.suffix.casefold() in {'.jpg','.jpeg','.png','.gif','.webp','.svg'}:return None
    return 'not an approved public source or help path'

def artifact_path_error(name):
    error=internal_path_error(name)
    if error:return error
    path=pathlib.PurePosixPath(name)
    if path.suffix.casefold()=='.json' and path.name.removeprefix('._').casefold() not in RUNTIME_JSON:
        return 'unapproved JSON resource; keep reports local'
    return None

def public_text_errors(name,text):
    return [name+': internal planning, test details or local path in user help'] if INTERNAL_TEXT.search(text) else []

def zip_errors(archive):
    errors=[]
    try:
        with zipfile.ZipFile(archive) as z:
            for item in z.infolist():
                error=artifact_path_error(item.filename)
                if error:errors.append(item.filename+': '+error)
                elif pathlib.PurePosixPath(item.filename).name in USER_HELP_NAMES and not item.is_dir():
                    if item.file_size>1048576:errors.append(item.filename+': help file is too large')
                    else:errors+=public_text_errors(item.filename,z.read(item).decode('utf-8'))
    except (OSError,ValueError,UnicodeError,zipfile.BadZipFile) as error:errors.append(str(archive)+': '+str(error))
    return errors

def release_file_errors(root,names):
    root=pathlib.Path(root);errors=[]
    for name in names:
        error=artifact_path_error(name)
        if error:errors.append(name+': '+error);continue
        path=root/name
        if path.is_symlink() or not path.is_file():errors.append(name+': missing file or symlink');continue
        if path.suffix.casefold()=='.zip':errors+=zip_errors(path)
        elif path.name in USER_HELP_NAMES:
            try:errors+=public_text_errors(name,path.read_text(encoding='utf-8'))
            except (OSError,UnicodeError) as error:errors.append(name+': '+str(error))
    return errors

def directory_errors(root):
    root=pathlib.Path(root)
    return release_file_errors(root,[p.relative_to(root).as_posix() for p in root.rglob('*') if not p.is_dir()])

def git(repo,*args):
    return subprocess.check_output(['git','-C',str(repo),*args],stderr=subprocess.PIPE)

def tree_errors(repo,revision='HEAD',index=False):
    command=('ls-files','-z') if index else ('ls-tree','-r','--name-only','-z',revision)
    errors=[]
    for raw in git(repo,*command).split(b'\0'):
        if not raw:continue
        name=raw.decode('utf-8')
        error=source_path_error(name)
        if error:errors.append(name+': '+error)
        elif name in PUBLIC_DOCS:
            text=git(repo,'show',(':' if index else revision+':')+name).decode('utf-8')
            errors+=public_text_errors(name,text)
    return errors

def history_errors(repo,revision,baseline=CLEAN_BASELINE):
    try:
        ancestor=subprocess.run(['git','-C',str(repo),'merge-base','--is-ancestor',baseline,revision],capture_output=True)
        if ancestor.returncode:return ['Source must descend from the public cleanup commit; older tags remain unchanged.']
        revisions=git(repo,'rev-list',revision,'^'+baseline).decode().splitlines() or [revision]
        errors=[]
        for commit in revisions:errors += [commit[:12]+' '+e for e in tree_errors(repo,commit)]
        return errors
    except (subprocess.CalledProcessError,OSError,UnicodeError) as error:return ['Cannot verify source history: '+str(error)]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository',default=str(pathlib.Path(__file__).resolve().parents[1]))
    mode=parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--index',action='store_true');mode.add_argument('--history');mode.add_argument('--pre-push',action='store_true')
    args=parser.parse_args()
    try:
        if args.index:errors=tree_errors(args.repository,index=True)
        elif args.history:errors=history_errors(args.repository,args.history)
        else:
            errors=[]
            for line in sys.stdin:
                fields=line.split()
                if len(fields)!=4:errors.append('Invalid pre-push input');continue
                local=fields[1]
                if set(local)=={'0'}:continue
                if not re.fullmatch('[0-9a-f]{40}',local):errors.append('Invalid pushed object');continue
                errors+=history_errors(args.repository,local)
    except (OSError,UnicodeError,subprocess.CalledProcessError) as error:errors=['Cannot verify publication: '+str(error)]
    for error in errors:print('Publication blocked: '+error,file=sys.stderr)
    return 1 if errors else 0

if __name__=='__main__':sys.exit(main())
