import glob, os, re, sys

# a page renamed or moved left docs and messages naming one that no longer exists (11-18: three, 11-21: two)
src = open("services/SettingsTree.js", encoding="utf-8").read()
start = src.index("var tree = [")
tree = src[start:src.index("\n]\n", start)]
groups = {}
group = None
for m in re.finditer(r'label: "([^"]+)"(, children)?', tree):
    if m.group(2):
        group = m.group(1)
        groups[group] = []
    elif group:
        groups[group].append(m.group(1))
if not groups:
    sys.exit("could not read SettingsTree.tree")

def starts_with_label(text, labels):
    for label in sorted(labels, key=len, reverse=True):
        if text.startswith(label) and not text[len(label):len(label) + 1].isalnum():
            return label
    return None

# release notes describe their own version; everything else is read against today's pages
files = ["README.md", "CHANGELOG.md", "dev/check.sh"]
files += [f for f in glob.glob("docs/**/*.md", recursive=True) if not f.startswith("docs/releases/")]
files += glob.glob("packaging/**/*.install", recursive=True)
files += [f for f in glob.glob("scripts/**/*", recursive=True) if os.path.isfile(f) and f.endswith((".sh", "silere"))]
files += glob.glob("services/*.qml") + glob.glob("modules/**/*.qml", recursive=True) + glob.glob("config/*.qml")

bad = []
for f in sorted(set(files)):
    for n, line in enumerate(open(f, encoding="utf-8", errors="replace"), 1):
        for m in re.finditer(r"Settings (›|>) ", line):
            sep = " " + m.group(1) + " "
            rest = line[m.end():]
            g = starts_with_label(rest, groups)
            if not g:
                bad.append(f"{f}:{n}: no Settings group starts '{rest.strip()[:40]}' (groups: {', '.join(groups)})")
                continue
            after = rest[len(g):]
            if after.startswith(sep) and not starts_with_label(after[len(sep):], groups[g]):
                bad.append(f"{f}:{n}: {g} has no page starting '{after[len(sep):].strip()[:40]}' (pages: {', '.join(groups[g])})")
if bad:
    print("\n".join(bad))
    sys.exit(1)
