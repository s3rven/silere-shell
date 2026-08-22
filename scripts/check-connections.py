import glob, re, sys

QML = sorted(
    glob.glob('shell.qml')
    + glob.glob('config/*.qml')
    + glob.glob('services/*.qml')
    + glob.glob('modules/**/*.qml', recursive=True)
)
SOURCE = {f: open(f).read() for f in QML}

DECL = re.compile(
    r'^\s*(?:readonly\s+)?property\s+(?:alias\s+)?[\w.<>]+\s+(\w+)', re.M)
SIGNAL = re.compile(r'^\s*signal\s+(\w+)', re.M)
FUNCTION = re.compile(r'^\s*function\s+(\w+)', re.M)
ROOT_TYPE = re.compile(r'^\s*([A-Z]\w*)\s*\{', re.M)

own, base, singleton = {}, {}, set()
for f, text in SOURCE.items():
    name = f.rsplit('/', 1)[-1][:-4]
    body = re.sub(r'//[^\n]*', '', text)
    own[name] = (set(DECL.findall(text)) | set(SIGNAL.findall(text))
                 | set(FUNCTION.findall(text)))
    root = ROOT_TYPE.search(body)
    base[name] = root.group(1) if root else None
    if 'pragma Singleton' in text:
        singleton.add(name)


def members(name, seen=None):
    seen = seen or set()
    if name in seen or name not in own:
        return set()
    seen.add(name)
    return own[name] | members(base.get(name), seen)


def rooted_in_singleton(name, seen=None):
    """True when the whole inheritance chain is local files ending at Singleton.

    A chain reaching any other external type (Item, PanelWindow, ...) inherits
    members this scan cannot see, so those targets are left alone.
    """
    seen = seen or set()
    if name in seen:
        return False
    seen.add(name)
    parent = base.get(name)
    if parent == 'Singleton':
        return True
    if parent not in own:
        return False
    return rooted_in_singleton(parent, seen)


def block(text, start):
    depth = 0
    i = text.index('{', start)
    while i < len(text):
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
        i += 1
    return text[start:]


def candidates(handler):
    """Names a `function on<Handler>` can be serving.

    Qt strips a leading underscore before capitalising, so property `_foo` is
    reached by on_FooChanged, not on_fooChanged.
    """
    if handler.endswith('Changed'):
        stem = handler[:-len('Changed')]
    else:
        stem = handler
    names = {stem, stem[0].lower() + stem[1:]}
    if stem.startswith('_') and len(stem) > 1:
        names.add('_' + stem[1].lower() + stem[2:])
    return names


bad = []
for f, text in SOURCE.items():
    for found in re.finditer(r'\bConnections\s*\{', text):
        body = block(text, found.start())
        line = text[:found.start()].count('\n') + 1
        target = re.search(r'target\s*:\s*([\w.]+)', body)
        if not target:
            continue
        name = target.group(1)
        if name not in singleton or not rooted_in_singleton(name):
            continue
        exposed = members(name)
        for handler in re.finditer(r'function\s+on(\w+)\s*\(', body):
            if not candidates(handler.group(1)) & exposed:
                bad.append(f"{f}:{line}: {name} has no "
                           f"on{handler.group(1)} to serve")

for b in sorted(bad):
    print("  " + b)
sys.exit(1 if bad else 0)
