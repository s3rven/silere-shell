import glob, re, sys
bad = []
for f in sorted(glob.glob('modules/**/*.qml', recursive=True)):
    lines = open(f).read().split('\n')
    for i, l in enumerate(lines):
        m = re.match(r"^(\s*)scale:\s*(.+)$", l)
        if not m:
            continue
        indent = len(m.group(1))
        sub = []
        for nxt in lines[i + 1:]:
            if nxt.strip() and (len(nxt) - len(nxt.lstrip())) <= indent - 4:
                break
            sub.append(nxt)
        if not any(re.search(r"\b(ShellText|RollingText|Text\s*\{)", s) for s in sub):
            continue
        # a state that is transparent or hidden at that scale can never look soft
        ctx = '\n'.join(lines[max(0, i - 10):i + 3])
        hidden = re.search(r"(opacity|visible):[^\n]*(\?|&&)", ctx) and re.search(r"0\.0|false", ctx)
        if not hidden:
            bad.append(f"{f}:{i + 1}: {m.group(2).strip()[:48]}")
for b in bad:
    print("  " + b)
sys.exit(1 if bad else 0)
