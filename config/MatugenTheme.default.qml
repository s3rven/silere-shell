pragma Singleton

import QtQuick
import Quickshell

// bundled fallback palette copied to MatugenTheme.qml (gitignored) on first install; matugen overwrites that, never this
Singleton {
    readonly property color background: "#101116"
    readonly property color surface:    "#1d1f26"
    readonly property color text:       "#e9eaf0"
    readonly property color subtext:    "#a0a4b0"
    readonly property color accent:     "#ffffff"
    readonly property color error:      "#dd92a2"
    readonly property color warning:    "#d4ad77"
    readonly property color success:    "#94bd8b"
}
