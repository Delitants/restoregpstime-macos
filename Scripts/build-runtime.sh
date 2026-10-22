#!/bin/bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
arch=arm64
while [ "$#" -gt 0 ]; do
  case "$1" in --arch) arch=$2; shift 2;; *) echo "Unknown argument: $1" >&2; exit 2;; esac
done
case "$arch" in arm64|x86_64) ;; *) echo 'Architecture must be arm64 or x86_64' >&2; exit 2;; esac
"$repo_root/Scripts/prepare-dependencies.sh"
prefix="$repo_root/work/runtime-install/$arch-macos13"
build="$repo_root/work/runtime-builds/perl-$arch-macos13"
export MACOSX_DEPLOYMENT_TARGET=13.0
mkdir -p "$repo_root/work/runtime-builds"
if [ ! -f "$build/Configure" ]; then cp -R "$repo_root/work/sources/perl-5.44.0" "$build"; fi
if [ ! -x "$prefix/bin/perl" ]; then
  cd "$build"
  if [ ! -f config.sh ]; then
    sh Configure -des "-Dprefix=$prefix" -Duserelocatableinc -Uuseshrplib -Uusethreads -Dcc=/usr/bin/clang \
      "-Dccflags=-O2 -arch $arch -mmacosx-version-min=13.0" "-Dldflags=-arch $arch -mmacosx-version-min=13.0" \
      "-Dlddlflags=-bundle -undefined dynamic_lookup -arch $arch -mmacosx-version-min=13.0" > "$repo_root/work/configure-$arch-macos13.log" 2>&1
  fi
  make -j4 > "$repo_root/work/make-$arch-macos13.log" 2>&1
  make install > "$repo_root/work/install-$arch-macos13.log" 2>&1
fi
"$prefix/bin/perl" -e 'die "Unexpected Perl version" unless $^V eq v5.44.0; print "$^V\n"'
/usr/bin/lipo -archs "$prefix/bin/perl"
python3 - "$repo_root" "$arch" <<'PY'
import json,pathlib,subprocess,sys
root=pathlib.Path(sys.argv[1]); arch=sys.argv[2]
receipt={'architecture':arch,'minimumMacOS':'13.0','compiler':subprocess.check_output(['/usr/bin/clang','--version'],text=True).splitlines()[0],'xcode':subprocess.check_output(['/usr/bin/xcodebuild','-version'],text=True).strip(),'dependencyLock':json.loads((root/'Dependencies/dependencies.lock.json').read_text())}
(root/'work/runtime-install'/(arch+'-macos13')/'build-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
PY
