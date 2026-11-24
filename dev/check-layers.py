#!/usr/bin/env python3
"""Fails when a base service reads a singleton above it: one upward read ties the two layers into one cycle, where
building either builds every service in it. What both need goes in a .pragma library file or is wired from above."""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = ["XdgPaths", "ConfigStore", "SafeText", "ShellSettings", "SystemTools", "DateTime", "Idle"]

singletons = {}
for folder in ("services", "config"):
    for line in open(os.path.join(ROOT, folder, "qmldir"), encoding="utf-8"):
        parts = line.split()
        if len(parts) == 4 and parts[0] == "singleton":
            singletons[parts[1]] = os.path.join(folder, parts[3])
strip = re.compile(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\'', re.S)
problems = []
for name in BASE:
    source = strip.sub(" ", open(os.path.join(ROOT, singletons[name]), encoding="utf-8").read())
    above = sorted(other for other in singletons
                   if other not in BASE and re.search(r"\b" + other + r"\.", source))
    if above:
        problems.append(f"{singletons[name]} reads {', '.join(above)}")
if problems:
    print("\n".join(problems))
    sys.exit(1)
print(f"{len(BASE)} base services read only each other")
