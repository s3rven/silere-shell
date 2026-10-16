import os, re, subprocess, sys

# comments are lowercase single lines without a closing period: the house style every
# cleanup restored, and the drift that came back each time nothing checked it
files = [f for f in subprocess.check_output(["git", "ls-files", "*.qml", "*.js"], text=True).split()
         if not f.startswith("dev/")]
components = {os.path.basename(f)[:-4] for f in files if f.endswith(".qml")}
keep = components | {
    "Qt", "Hyprland", "Spotify", "Cava", "Quickshell", "Maintenance", "Nerd", "Connections", "Repeater",
    "Rectangle", "Canvas", "Timer", "Loader", "Column", "Row", "Text", "Image", "Shape", "Behavior",
    "Process", "Singleton", "Item", "Window", "Flickable", "ListView", "Region", "Variants", "Discord",
    "Firefox", "Electron", "Chromium", "Linux", "Matugen", "Lua", "Wayland", "Mesa", "Escape", "Enter",
    "Ctrl", "Super", "Shift", "Monday", "Sunday", "Niri", "KWin", "Kitty", "Steam", "Zen", "Google",
    "Windows", "Arch", "Lenovo", "ThinkPad", "Legion", "Bluetooth", "Wi-Fi", "Ethernet", "Night", "Do", "I"}
bad = []
for f in files:
    lines = open(f, encoding="utf-8").read().split("\n")
    i = 0
    while i < len(lines):
        m = re.match(r"^(\s*)//(?!@)\s?(.*)$", lines[i])
        if not m:
            i += 1
            continue
        start, indent = i, m.group(1)
        while i + 1 < len(lines) and re.match(r"^" + indent + r"//(?!@)", lines[i + 1]):
            i += 1
        first = re.match(r"^\s*//\s?(.*)$", lines[start]).group(1).rstrip()
        last = re.match(r"^\s*//\s?(.*)$", lines[i]).group(1).rstrip()
        word = re.match(r"^([A-Za-z][A-Za-z\-]*)", first)
        if word and re.fullmatch(r"[A-Z][a-z]*(-[a-z]+)*", word.group(1)) \
                and word.group(1) not in keep and word.group(1).split("-")[0] not in keep \
                and not first[len(word.group(1)):].startswith(("(", "_", ".")):
            bad.append(f"{f}:{start + 1}: starts with '{word.group(1)}'")
        if last.endswith(".") and not last.endswith("...") \
                and not re.search(r"\b(e\.g|i\.e|etc|vs)\.$", last) and len(last) > 1 \
                and (last[-2].isalnum() or last[-2] in ")\"'`"):
            bad.append(f"{f}:{i + 1}: ends with a period")
        i += 1
for b in bad:
    print("  " + b)
sys.exit(1 if bad else 0)
