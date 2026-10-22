#!/bin/bash
set -euo pipefail
# Produce a shareable summary from a local QA result. Raw logs, fixture paths and
# media are deliberately not copied. This does not promote missing gates.
if [ "$#" -ne 2 ]; then echo 'Usage: collect-evidence.sh LOCAL_QA_DIRECTORY NEW_SUMMARY.json' >&2; exit 2; fi
python3 - "$1" "$2" <<'PY'
import json,pathlib,sys
root=pathlib.Path(sys.argv[1]);out=pathlib.Path(sys.argv[2])
if out.exists():raise SystemExit('Refusing to overwrite retained evidence')
result=json.loads((root/'qualification-result.json').read_text())
if result.get('schema')!=1:raise SystemExit('Unsupported QA schema')
summary={k:result[k] for k in ['schema','sourceCommit','appHash','hostLabel','host','gates']}
# Error details may contain local paths. Export only explicit status identifiers;
# reviewers retain raw local records and attach separately audited proof.
summary['hostLabel']='local-qualification'
summary['gates']=[{'id':g['id'],'status':g['status']} for g in result['gates']]
summary['stableReady']=False
summary['note']='Sanitized status summary; raw local evidence requires separate review.'
with out.open('x') as f:json.dump(summary,f,indent=2);f.write('\n')
PY
