pragma Singleton

import QtQuick
import Quickshell

// whitespace is legal in a unix path; trimming it makes the shell disagree with scripts/lib/xdg.sh
Singleton {
    id: root

    function resolveHome(configured, home, fallback: string): string {
        const explicit = String(configured ?? "")
        if (explicit.startsWith("/")) return explicit
        const base = String(home ?? "")
        return base.startsWith("/") ? base + "/" + fallback : ""
    }

    function resolveAbsolute(configured): string {
        const value = String(configured ?? "")
        return value.startsWith("/") ? value : ""
    }

    readonly property string configHome: root.resolveHome(
        Quickshell.env("XDG_CONFIG_HOME"), Quickshell.env("HOME"), ".config")
    readonly property string cacheHome: root.resolveHome(
        Quickshell.env("XDG_CACHE_HOME"), Quickshell.env("HOME"), ".cache")
    readonly property string stateHome: root.resolveHome(
        Quickshell.env("XDG_STATE_HOME"), Quickshell.env("HOME"), ".local/state")
    readonly property string runtimeDir: root.resolveAbsolute(
        Quickshell.env("XDG_RUNTIME_DIR"))
}
