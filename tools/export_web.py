"""Exports the web build: the engine export plus assets.pck with the extracted game data.

    python tools/export_web.py --redot path/to/redot [--out build/web]

--redot defaults to the REDOT environment variable. The output folder is created if needed.
"""
import argparse
import os
import subprocess
import sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
parser = argparse.ArgumentParser()
parser.add_argument("--redot", default=os.environ.get("REDOT"))
parser.add_argument("--out", default=os.path.join(root, "build", "web"))
args = parser.parse_args()
if not args.redot:
    sys.exit("pass --redot or set REDOT")
out = os.path.abspath(args.out)
os.makedirs(out, exist_ok=True)
base = [args.redot, "--headless", "--path", root]
subprocess.run(base + ["--script", "tools/build_web_pack.gd", "--", os.path.join(out, "assets.pck")], check=True)
subprocess.run(base + ["--export-release", "Web", os.path.join(out, "index.html")], check=True)
print("exported to", out)
