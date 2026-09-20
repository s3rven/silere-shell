import glob, re, sys

# A settings card pairs a toggle with the value it governs by giving both rows the
# same glyph, so a repeat on adjacent rows is deliberate. A repeat with other rows
# between them is two unrelated settings wearing one icon.
# Sorting these is locale-dependent - private-use codepoints do not compare equal
# under every collation - so compare the characters directly, never via sort/uniq.
bad = []
for f in sorted(glob.glob('modules/menu/settings/Settings*Section.qml')):
    text = open(f, encoding='utf-8').read()
    rows = re.findall(r'glyph:\s*"([^"]+)"(?:\s*;\s*label:\s*"([^"]+)")?', text)
    seen = {}
    for i, (g, label) in enumerate(rows):
        if g in seen and i - seen[g][0] > 1:
            prev = seen[g][1] or "?"
            bad.append(f"{f}: U+{ord(g[0]):05X} on '{prev}' and '{label or '?'}'")
        seen[g] = (i, label)
for b in bad:
    print("  " + b)
sys.exit(1 if bad else 0)
