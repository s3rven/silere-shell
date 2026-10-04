"""Check recycled delegate animations without gating their view's own chrome."""

from pathlib import Path
import re
import sys


def code_only(text):
    # Keep offsets and line numbers while masking strings and comments. A brace
    # in a label, URL or JavaScript string must not end a delegate's scope.
    pattern = r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|`(?:\\.|[^`\\])*`|//[^\n]*|/\*[\s\S]*?\*/'
    return re.sub(pattern, lambda m: re.sub(r'[^\n]', ' ', m[0]), text)


def closing_brace(code, start):
    depth = 0
    for i in range(start, len(code)):
        depth += (code[i] == '{') - (code[i] == '}')
        if depth == 0:
            return i + 1
    raise ValueError('unclosed QML block')


def check(root):
    paths = sorted(root.glob('modules/**/*.qml'))
    paths += sorted(root.glob('config/*.qml')) + sorted(root.glob('services/*.qml'))
    if (root / 'shell.qml').exists():
        paths.append(root / 'shell.qml')
    sources = {p: code_only(p.read_text()) for p in paths}
    components = {p.stem: p for p in paths}
    scopes = set()
    for path, code in sources.items():
        if re.search(r'ListView\.on(?:Pooled|Reused)\s*:', code):
            scopes.add((path, 0, len(code)))
        for pooling in re.finditer(r'\breuseItems\s*:\s*true\b', code):
            stack = []
            for i, char in enumerate(code[:pooling.start()]):
                if char == '{':
                    stack.append(i)
                elif char == '}':
                    stack.pop()
            if not stack:
                continue
            view_start = stack[-1]
            view_end = closing_brace(code, view_start)
            for delegate in re.finditer(r'\bdelegate\s*:\s*([A-Z]\w*)\s*\{',
                                        code[view_start:view_end]):
                start = view_start + delegate.start()
                brace = view_start + delegate.end() - 1
                scopes.add((path, start, closing_brace(code, brace)))
                component = components.get(delegate[1])
                if component:
                    scopes.add((component, 0, len(sources[component])))

    errors = set()
    count = 0
    for path, start, end in sorted(scopes):
        code = sources[path]
        body = code[start:end]
        animations = list(re.finditer(
            r'\b(?:ColorFade|MotionBehavior|Disclosure)\s+on\s+[\w.]+\s*\{', body))
        count += len(animations)
        if not animations:
            continue
        label = path.relative_to(root)
        for animation in animations:
            brace = animation.end() - 1
            block = body[brace:closing_brace(body, brace)]
            if not re.search(r'\bgate\s*:', block):
                line = code.count('\n', 0, start + animation.start()) + 1
                errors.add(f'{label}:{line}: recycled delegate animation needs a gate')
        if not all(re.search(r'ListView\.on' + event + r'\s*:', body)
                   for event in ('Pooled', 'Reused')):
            errors.add(f'{label}: animated delegate needs both pool and reuse handlers')
    if count == 0:
        errors.add('pooling scan inspected no delegate animations')
    return sorted(errors)


if __name__ == '__main__':
    root = Path(sys.argv[1] if len(sys.argv) > 1 else '.').resolve()
    errors = check(root)
    for error in errors:
        print('  ' + error)
    sys.exit(bool(errors))
