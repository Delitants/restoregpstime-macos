#!/usr/bin/env python3
"""Optional test-fixture authoring; Pillow/libwebp and FFmpeg/SVT-AV1 are not app dependencies."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from PIL import Image, features

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--ffmpeg", default="ffmpeg")
parser.add_argument("--output", type=Path, required=True, help="A fresh output directory; never overwritten")
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
args.output.mkdir(parents=True, exist_ok=False)
image = Image.open(root / "Tests/Fixtures/paris.png")
image.save(args.output / "geometric-baseline.webp", format="WEBP", lossless=True)
commands = [
    ["-i", str(root / "Tests/Fixtures/paris.png"), "-vf", "scale=128:128", "-frames:v", "1",
     "-c:v", "libsvtav1", "-preset", "12", "-crf", "20", "-pix_fmt", "yuv420p",
     "-svtav1-params", "lp=2", "-f", "avif", str(args.output / "geometric-baseline.avif")],
    ["-i", str(root / "Tests/Fixtures/paris.mov"), "-map", "0:v:0", "-c", "copy",
     "-map_metadata", "-1", "-f", "mp4", str(args.output / "geometric-baseline.mp4")],
]
for index, command in enumerate(commands):
    with (args.output / f"ffmpeg-{index}.log").open("xb") as log:
        subprocess.run([args.ffmpeg, "-hide_banner", "-nostdin", "-n"] + command,
                       check=True, stdout=log, stderr=subprocess.STDOUT)
record = {"origin": "Generated geometric Paris fixtures; no personal media",
          "pillow": Image.__version__, "libwebp": features.version("webp"),
          "ffmpeg": subprocess.check_output([args.ffmpeg, "-version"], text=True).splitlines()[0],
          "files": {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in sorted(args.output.glob("geometric-baseline.*"))}}
(args.output / "provenance.json").write_text(json.dumps(record, indent=2) + "\n")
