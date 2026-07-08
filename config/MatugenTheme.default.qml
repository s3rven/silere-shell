pragma Singleton

import QtQuick
import Quickshell

// bundled fallback palette, copied to MatugenTheme.qml on first install so the shell themes before matugen runs.
// matugen overwrites MatugenTheme.qml (gitignored), leaving this default untouched.
Singleton {
    readonly property color background: "#131318"
    readonly property color surface:    "#201f25"
    readonly property color text:       "#e5e1e9"
    readonly property color subtext:    "#c8c5d0"
    readonly property color accent:     "#c4c0ff"
    readonly property color error:      "#ffb4ab"
    readonly property color warning:    "#ebb9d1"
    readonly property color success:    "#c7c4dc"
}
