#!/usr/bin/env python3
"""The QML and JS that Qt compiles before the bar shows, followed by type name from shell.qml.

Usage: startup-set.py [REV] [--list]   (no REV: the tracked files as they are on disk)
Prints "<bytes> <files>". Surfaces that PopupLoader compiles from a file on first open are reached only through a
string, so they and everything only they name stay out, as they do at start.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
args = [a for a in sys.argv[1:] if not a.startswith("--")]
rev = args[0] if args else None


def git(*cmd):
    return subprocess.run(["git", "-C", ROOT, *cmd], check=True, capture_output=True).stdout


if rev:
    tracked = git("ls-tree", "-r", "--name-only", rev).decode().splitlines()
else:
    tracked = git("ls-files").decode().splitlines()
tracked = {p for p in tracked if p.endswith((".qml", ".js", "qmldir")) and not p.startswith("dev/")}


def text(path):
    if rev:
        return git("show", f"{rev}:{path}").decode("utf-8", "replace")
    with open(os.path.join(ROOT, path), encoding="utf-8", errors="replace") as handle:
        return handle.read()


# comments and string literals name no types; a surfaceFile path is a string
STRIP = re.compile(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\'|`(?:\\.|[^`\\])*`', re.S)
IMPORT_DIR = re.compile(r'^\s*import\s+"([^"]+)"', re.M)
NAME = re.compile(r'\b[A-Z][A-Za-z0-9_]*\b')

types = {}
for path in tracked:
    folder = os.path.dirname(path)
    if path.endswith(".qml"):
        types.setdefault(folder, {})[os.path.basename(path)[:-4]] = path
for path in tracked:
    if os.path.basename(path) != "qmldir":
        continue
    folder = os.path.dirname(path)
    for line in text(path).splitlines():
        parts = line.split()
        if parts and parts[0] == "singleton":
            parts = parts[1:]
        if len(parts) == 3 and parts[2].endswith((".qml", ".js")):
            target = os.path.normpath(os.path.join(folder, parts[2]))
            if target in tracked:
                types.setdefault(folder, {})[parts[0]] = target

seen = set()
queue = ["shell.qml"]
while queue:
    path = queue.pop()
    if path in seen or path not in tracked:
        continue
    seen.add(path)
    source = text(path)
    folder = os.path.dirname(path)
    scopes = [folder]
    for target in IMPORT_DIR.findall(source):
        resolved = os.path.normpath(os.path.join(folder, target))
        if target.endswith(".js"):
            queue.append(resolved)
        else:
            scopes.append(resolved)
    names = set(NAME.findall(STRIP.sub(" ", source)))
    for scope in scopes:
        for name, target in types.get(scope, {}).items():
            if name in names and target != path:
                queue.append(target)

total = 0
for path in sorted(seen):
    size = len(text(path).encode("utf-8"))
    total += size
    if "--list" in sys.argv:
        print(f"{size:8d} {path}")
print(total, len(seen))
