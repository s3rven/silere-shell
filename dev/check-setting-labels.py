import glob, re, sys

# Settings search indexes each schema entry's `l` without building any page, so the
# label it searches must be the one the row shows. Only literal row labels are checked.


def row_labels():
    found = {}
    for f in sorted(glob.glob('modules/menu/settings/*.qml')):
        text = open(f, encoding='utf-8').read()
        for m in re.finditer(r'\bkey:\s*"(\w+)"', text):
            depth, start = 0, m.start()
            while start > 0:
                start -= 1
                if text[start] == '}':
                    depth += 1
                elif text[start] == '{':
                    if depth == 0:
                        break
                    depth -= 1
            depth, end = 0, start + 1
            while end < len(text):
                if text[end] == '{':
                    depth += 1
                elif text[end] == '}':
                    if depth == 0:
                        break
                    depth -= 1
                end += 1
            body, depth, flat = text[start + 1:end], 0, []
            for ch in body:
                if ch == '{':
                    depth += 1
                elif ch == '}':
                    depth -= 1
                flat.append(ch if depth == 0 else ' ')
            label = re.search(r'(?:^|[\s;])label:\s*"([^"]+)"\s*(?:$|[\n;])', ''.join(flat), re.M)
            if label:
                found.setdefault(m.group(1), set()).add(label.group(1))
    return found


schema = {}
for m in re.finditer(r'\{ k: "(\w+)",[^\n]*', open('services/ShellSettings.qml', encoding='utf-8').read()):
    lab = re.search(r'\bl: "([^"]*)"', m.group(0))
    schema[m.group(1)] = lab.group(1) if lab else None

bad = []
for key, labels in sorted(row_labels().items()):
    if key not in schema:
        continue
    if schema[key] is None:
        bad.append(f"{key}: row shows {sorted(labels)} but its schema entry has no l:")
    elif schema[key] not in labels:
        bad.append(f"{key}: schema l: \"{schema[key]}\" but the row shows {sorted(labels)}")
if '--list' in sys.argv:
    for key, labels in sorted(row_labels().items()):
        print(key, sorted(labels))
    sys.exit(0)
for b in bad:
    print("  " + b)
sys.exit(1 if bad else 0)
