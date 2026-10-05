import collections, glob, os, re, sys

QML = sorted(
    glob.glob('shell.qml')
    + glob.glob('config/*.qml')
    + glob.glob('services/*.qml')
    + glob.glob('modules/**/*.qml', recursive=True)
)
SOURCE = {f: re.sub(r'//[^\n]*', '', open(f).read()) for f in QML}
COMPONENT = {os.path.basename(f)[:-4]: f for f in QML
             if os.path.basename(f)[0].isupper()}

SETTING = re.compile(r'ShellSettings\.(\w+)')
# a gate spanning several lines keeps its continuations indented past the property
ACTIVE = re.compile(r'\n\s*active:\s*((?:[^\n]*\n\s{16,}[^\n]*)|[^\n]*)')
SELF_GATE = re.compile(
    r'property\s+bool\s+\w*(?:wanted|shown|showing)\w*\s*:\s*'
    r'((?:[^\n]*\n\s{8,}[^\n]*){0,4})', re.I)


def blocks(text, head):
    """(body, line) for every `head { ... }` block, matched on braces."""
    lines = text.split('\n')
    for i, line in enumerate(lines):
        if not re.search(head, line):
            continue
        depth = 0
        body = []
        for k in range(i, len(lines)):
            depth += lines[k].count('{') - lines[k].count('}')
            body.append(lines[k])
            if depth == 0 and k > i:
                break
        yield '\n'.join(body), i + 1


def instantiated(body):
    return {n for n in COMPONENT
            if re.search(r'(?<![A-Za-z0-9_.])' + n + r'\s*\{', body)}


inherited = collections.defaultdict(set)
site = collections.defaultdict(set)
for f, text in SOURCE.items():
    for body, line in blocks(text, r'\bLoader\s*\{'):
        found = ACTIVE.search(body)
        if not found:
            continue
        keys = set(SETTING.findall(found.group(1)))
        if not keys:
            continue
        for name in instantiated(body):
            inherited[name] |= keys
            site[name].add(f'{f}:{line}')

# a component drawn inside a gated one is behind that gate too
for _ in range(4):
    for host, keys in list(inherited.items()):
        for name in instantiated(SOURCE.get(COMPONENT.get(host, ''), '')):
            if name != host and not inherited[name] >= keys:
                inherited[name] |= keys
                site[name].add(f'(nested in {host})')

bad = []
for name, keys in sorted(inherited.items()):
    own = set()
    for gate in SELF_GATE.findall(SOURCE.get(COMPONENT[name], '')):
        own |= set(SETTING.findall(gate))
    if not own:
        continue
    stolen = keys - own
    if stolen:
        bad.append(
            f"{COMPONENT[name]}: {name} decides itself on "
            f"{'/'.join(sorted(own))} but only ever builds behind "
            f"{'/'.join(sorted(stolen))} [{', '.join(sorted(site[name]))}]")

for b in bad:
    print('  ' + b)
sys.exit(1 if bad else 0)
