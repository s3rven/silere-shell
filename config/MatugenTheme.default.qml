pragma Singleton

import QtQuick
import Quickshell

// bundled fallback palette, copied to MatugenTheme.qml on first install so the shell themes before matugen runs.
// matugen overwrites MatugenTheme.qml (gitignored), leaving this default untouched.
Singleton {
    readonly property color background: "#101116"
    readonly property color surface:    "#1d1f26"
    readonly property color text:       "#e9eaf0"
    readonly property color subtext:    "#a0a4b0"
    readonly property color accent:     "#b8bdd8"
    readonly property color error:      "#dd92a2"
    readonly property color warning:    "#d4ad77"
    readonly property color success:    "#94bd8b"
}
