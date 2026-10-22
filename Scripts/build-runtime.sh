#!/bin/bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
arch=arm64;print_prefix=false
while [ "$#" -gt 0 ]; do
 case "$1" in --arch) arch=$2;shift 2;; --print-prefix) print_prefix=true;shift;; *) echo "Unknown argument: $1" >&2;exit 2;; esac
done
case "$arch" in arm64|x86_64) ;; *) exit 2;; esac
# A new namespace deliberately invalidates the host-autodetected v1 runtimes.
# Existing builds and failed candidates remain available for diagnosis.
namespace="$arch-macos13-isolated-v2"
prefix="$repo_root/work/runtime-install/$namespace"
build="$repo_root/work/runtime-builds/perl-$namespace"
if $print_prefix; then printf '%s\n' "$prefix";exit 0;fi
"$repo_root/Scripts/prepare-dependencies.sh"
export MACOSX_DEPLOYMENT_TARGET=13.0
mkdir -p "$repo_root/work/runtime-builds"
if [ ! -f "$build/Configure" ]; then cp -R "$repo_root/work/sources/perl-5.44.0" "$build";fi
if [ ! -x "$prefix/bin/perl" ]; then
 cd "$build"
 if [ ! -f config.sh ]; then
  sh Configure -des "-Dprefix=$prefix" -Duserelocatableinc -Uuseshrplib -Uusethreads -Dcc=/usr/bin/clang \
   '-Dnoextensions=DB_File GDBM_File NDBM_File ODBM_File' \
   "-Dccflags=-O2 -arch $arch -mmacosx-version-min=13.0" "-Dldflags=-arch $arch -mmacosx-version-min=13.0" \
   "-Dlddlflags=-bundle -undefined dynamic_lookup -arch $arch -mmacosx-version-min=13.0" > "$repo_root/work/configure-$namespace.log" 2>&1
 fi
 make -j4 > "$repo_root/work/make-$namespace.log" 2>&1
 make install > "$repo_root/work/install-$namespace.log" 2>&1
fi
"$prefix/bin/perl" -e 'die "Unexpected Perl version" unless $^V eq v5.44.0; print "$^V\n"'
python3 - "$repo_root" "$arch" "$prefix" <<'PY'
import json,pathlib,subprocess,sys
root=pathlib.Path(sys.argv[1]);arch=sys.argv[2];prefix=pathlib.Path(sys.argv[3]);excluded=['DB_File','GDBM_File','NDBM_File','ODBM_File']
for module in excluded:
 if list((prefix/'lib').rglob(module+'.bundle')):raise SystemExit('Excluded optional module remains: '+module)
for path in [prefix/'bin/perl']+sorted((prefix/'lib').rglob('*.bundle')):
 actual=subprocess.check_output(['/usr/bin/lipo','-archs',str(path)],text=True).strip()
 if actual!=arch:raise SystemExit('Runtime architecture differs: '+str(path))
 lines=subprocess.check_output(['/usr/bin/otool','-L',str(path)],text=True).splitlines()[1:]
 for line in lines:
  dependency=line.strip().split(' (compatibility version',1)[0]
  if not dependency.startswith(('/usr/lib/','/System/Library/')):raise SystemExit('External runtime dependency: '+dependency)
receipt={'schema':2,'buildProfile':'isolated-v2','excludedExtensions':excluded,'architecture':arch,'minimumMacOS':'13.0','compiler':subprocess.check_output(['/usr/bin/clang','--version'],text=True).splitlines()[0],'xcode':subprocess.check_output(['/usr/bin/xcodebuild','-version'],text=True).strip(),'dependencyLock':json.loads((root/'Dependencies/dependencies.lock.json').read_text())}
path=prefix/'build-receipt.json'
if path.exists() and json.loads(path.read_text())!=receipt:raise SystemExit('Runtime cache receipt differs; retain it and use a new profile namespace')
path.write_text(json.dumps(receipt,indent=2)+'\n')
print('Verified isolated native runtime: '+arch)
PY
