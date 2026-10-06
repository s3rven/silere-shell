import glob, re, sys

# anchors.centerIn rounds to a whole logical pixel before PixelSnap rounds to a device
# pixel. At 1.25 the two roundings can land a centred item one device pixel off true
# centre, and off a ring snapped around it: a selected swatch sat 3 px from its ring on
# one side and 1 px on the other. With alignWhenCentered off, PixelSnap alone decides.
# A Math.round on the item's own x or y is the same double rounding, written by hand.
def own_text(body):
    depth, own = 0, []
    for ch in body[1:]:
        if ch == '{':
            depth += 1
            own.append(' ')
        elif ch == '}':
            depth -= 1
        elif depth == 0:
            own.append(ch)
    return "".join(own)

bad = []
for f in sorted(glob.glob('modules/**/*.qml', recursive=True) + glob.glob('config/*.qml')):
    src = open(f, encoding='utf-8').read()
    stack = []
    for i, ch in enumerate(src):
        if ch == '{':
            stack.append(i)
        elif ch == '}' and stack:
            s = stack.pop()
            own = own_text(src[s:i])
            snapped = re.search(r'transform:[^\n]*PixelSnap|transform:\s*\[[^\]]*PixelSnap', own, re.S)
            if not snapped:
                continue
            line = f"{f}:{src[:s].count(chr(10)) + 1}"
            if 'anchors.centerIn' in own and not re.search(r'alignWhenCentered:\s*false', own):
                bad.append(line + " centres with anchors.centerIn; set anchors.alignWhenCentered: false")
            if re.search(r'^\s*[xy]:\s*Math\.round', own, re.M):
                bad.append(line + " rounds its own x or y; leave it unrounded for PixelSnap")
for b in bad:
    print("  " + b)
sys.exit(1 if bad else 0)
