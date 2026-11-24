#!/usr/bin/env python3
"""Fails when shipped QML reads a singleton's underscore member from another file: what another file needs is public."""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
listed = subprocess.run(["git", "-C", ROOT, "ls-files"], capture_output=True, text=True, check=True).stdout.split()
singletons = {}
for path in listed:
    if os.path.basename(path) != "qmldir" or path.startswith("dev/"):
        continue
    for line in open(os.path.join(ROOT, path), encoding="utf-8"):
        parts = line.split()
        if len(parts) == 4 and parts[0] == "singleton":
            singletons[parts[1]] = os.path.normpath(os.path.join(os.path.dirname(path), parts[3]))
reads = re.compile(r"\b(" + "|".join(sorted(singletons, key=len, reverse=True)) + r")\.(_[A-Za-z0-9_]+)")
found = []
for path in listed:
    if not path.endswith((".qml", ".js")) or path.startswith("dev/"):
        continue
    text = open(os.path.join(ROOT, path), encoding="utf-8").read()
    for match in reads.finditer(text):
        if singletons[match.group(1)] != path:
            line = text.count("\n", 0, match.start()) + 1
            found.append(f"{path}:{line}: {match.group(0)}")
if found:
    print("\n".join(found))
    sys.exit(1)
print(f"{len(singletons)} singletons, no private member read from another file")
