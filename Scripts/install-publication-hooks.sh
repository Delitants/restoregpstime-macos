#!/bin/bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"
configured=$(git config --get core.hooksPath || true)
if [ -n "$configured" ] && [ "$configured" != .githooks ]; then
 echo 'Existing custom hooks configuration retained; integrate publication checks before publishing.' >&2
 exit 2
fi
if [ -z "$configured" ]; then
 for hook in pre-commit pre-push; do
  existing=$(git rev-parse --git-path "hooks/$hook")
  if [ -e "$existing" ]; then
   echo 'Existing custom hook retained; integrate publication checks before publishing.' >&2
   exit 2
  fi
 done
fi
for hook in pre-commit pre-push; do test -x ".githooks/$hook"; done
git config --local core.hooksPath .githooks
printf '%s\n' 'Publication hooks enabled for this checkout.'
