#!/bin/bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
python3 "$repo_root/Scripts/check_release.py" "$@"
