#!/usr/bin/env python3
"""Reject the current builder's home/repository paths in a distribution bundle."""
import argparse,json,pathlib
p=argparse.ArgumentParser();p.add_argument('--app',required=True);p.add_argument('--repository',required=True);a=p.parse_args()
root=pathlib.Path(a.app);needles={str(pathlib.Path(a.repository).resolve()).encode(),str(pathlib.Path.home()).encode()};hits=[]
for path in sorted(root.rglob('*')):
 if path.is_file() and not path.is_symlink():
  tail=b''
  with path.open('rb') as stream:
   while block:=stream.read(1048576):
    data=tail+block
    if any(needle in data for needle in needles):hits.append(str(path.relative_to(root)));break
    tail=data[-max(map(len,needles)):]

print(json.dumps({'schema':1,'personalBuildPaths':hits},indent=2))
raise SystemExit(2 if hits else 0)
