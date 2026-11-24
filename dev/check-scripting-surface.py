#!/usr/bin/env python3
"""Fails when docs promise a `silere` command or an IPC call the shell does not answer."""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

launcher = open("scripts/silere", encoding="utf-8").read()
start = launcher.index('case "$command_name" in')
commands = set()
for label in re.findall(r"^    ([a-z|-]+)\)", launcher[start:], re.M):
    commands.update(label.split("|"))

handlers = {}
for path in glob.glob("services/*.qml") + glob.glob("config/*.qml") + glob.glob("modules/**/*.qml", recursive=True) + ["shell.qml"]:
    text = open(path, encoding="utf-8").read()
    for match in re.finditer(r"IpcHandler\s*\{", text):
        depth, i = 0, match.end() - 1
        while i < len(text):
            depth += {"{": 1, "}": -1}.get(text[i], 0)
            if depth == 0:
                break
            i += 1
        block = text[match.end():i]
        target = re.search(r'target:\s*"([^"]+)"', block)
        if target:
            handlers.setdefault(target.group(1), set()).update(re.findall(r"function\s+([A-Za-z]\w*)\s*\(", block))

problems = []
scripting = open("docs/scripting.md", encoding="utf-8").read()
for row in re.findall(r"^\| (`silere [^|]+)\|", scripting, re.M):
    for word in re.findall(r"`silere ([a-z-]+)", row):
        if word not in commands:
            problems.append(f"docs/scripting.md documents `silere {word}`, which scripts/silere does not answer")
calls = 0
for path in sorted(glob.glob("docs/**/*.md", recursive=True) + ["README.md"]):
    if path.startswith("docs/releases/"):
        continue
    for target, fn in re.findall(r"(?:silere ipc|ipc(?: -p \S+)? call) ([a-zA-Z]+) ([a-zA-Z]+)", open(path, encoding="utf-8").read()):
        calls += 1
        if fn not in handlers.get(target, set()):
            problems.append(f"{path} names `ipc {target} {fn}`, which no IpcHandler answers")
if problems:
    print("\n".join(sorted(set(problems))))
    sys.exit(1)
print(f"{len(commands)} commands, {len(handlers)} IPC targets, {calls} documented calls all answered")
