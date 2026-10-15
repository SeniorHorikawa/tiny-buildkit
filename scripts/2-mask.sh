#!/usr/bin/env bash
set -euo pipefail

root="${1:?usage: 2-mask.sh <dir>}"

python3 - "$root" <<'PY'
import os
import re
import sys

root = sys.argv[1]
exts = (".sh", ".py", ".properties", ".txt", ".json", ".yml", ".yaml", ".kts", ".gradle", ".xml", ".toml")
skip_dirs = {".git", "build", ".gradle", ".kotlin", ".idea", "tmp"}

pat_long = re.compile(rb"[A-Za-z0-9+/=]{20,}")
pat_alnum = re.compile(rb"\b[0-9A-Z][0-9A-Za-z]{11,}\b")
pat_ident = re.compile(rb"\b[A-Za-z0-9_-]{16,}\b")
pat_host = re.compile(rb"\b[a-z0-9][a-z0-9.-]{6,}[a-z0-9]\b")
pat_kv = re.compile(rb"=\s*([^\s=]{6,})")
pat_here = re.compile(rb"<<\s*'?([A-Za-z_][A-Za-z0-9_]*)'?\s*\n(.*?)\n\1", re.S)

found = set()
limit = 400
emitted = 0

def emit(value):
    global emitted
    value = value.strip()
    if emitted >= limit or not (2 <= len(value) <= 200) or value in found:
        return
    try:
        text = value.decode("utf-8")
    except UnicodeDecodeError:
        return
    if any(c in text for c in "%\r\n"):
        return
    found.add(value)
    emitted += 1
    sys.stdout.write("::add-mask::" + text + "\n")

for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = [d for d in dirnames if d not in skip_dirs]
    for name in filenames:
        if emitted >= limit:
            break
        if not name.endswith(exts):
            continue
        try:
            with open(os.path.join(dirpath, name), "rb") as fh:
                data = fh.read(400000)
        except OSError:
            continue
        for pat in (pat_long, pat_alnum, pat_ident, pat_host, pat_kv):
            for m in set(pat.findall(data)):
                emit(m)
        for m in pat_here.finditer(data):
            for line in m.group(2).split(b"\n"):
                emit(line)

sys.stderr.write("masked %d values\n" % emitted)
PY

echo "mask ok"
