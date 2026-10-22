#!/bin/bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
downloads=${RESTOREGPSTIME_DOWNLOADS:-"$repo_root/work/downloads"}
mkdir -p "$downloads" "$repo_root/work/sources"
python3 - "$repo_root" "$downloads" <<'PY'
import hashlib,json,pathlib,subprocess,sys,tarfile
root=pathlib.Path(sys.argv[1]); cache=pathlib.Path(sys.argv[2])
for dep in json.loads((root/'Dependencies/dependencies.lock.json').read_text())['dependencies']:
    path=cache/(dep['sourceDirectory']+'.tar.gz')
    if not path.exists():
        subprocess.run(['/usr/bin/curl','--fail','--location','--retry','0','--output',str(path),dep['url']],check=True)
    actual=hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != dep['sha256']:raise SystemExit(f"Source checksum mismatch: {path}. Retain it and investigate; no extraction performed.")
    target=root/'work/sources'/dep['sourceDirectory']
    if not target.exists():
        with tarfile.open(path) as archive:archive.extractall(root/'work/sources',filter='data')
    print(f"Verified {dep['name']} {dep['version']}: {actual}")
PY
