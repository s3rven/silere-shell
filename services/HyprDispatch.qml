pragma Singleton

import QtQuick
import Quickshell

// The mechanism for talking to Hyprland, with no opinion about compositor state.
// HyprActions owns the state-aware behaviour and sets useLua; keeping the two
// apart is what stops Compositor and HyprActions depending on each other.
Singleton {
    id: root

    property bool useLua: false

    function _quote(value): string {
        return "\"" + String(value).replace(/\\/g, "\\\\").replace(/"/g, "\\\"") + "\""
    }

    function _value(value): string {
        const text = String(value)
        return /^-?\d+$/.test(text) ? text : root._quote(text)
    }

    function _luaCall(dispatcher, args): string {
        if (dispatcher === "focusmonitor")
            return "hl.dsp.focus({ monitor = " + root._quote(args) + " })"
        if (dispatcher === "workspace")
            return "hl.dsp.focus({ workspace = " + root._value(args) + " })"
        if (dispatcher === "movetoworkspacesilent")
            return "hl.dsp.window.move({ workspace = " + root._value(args) + ", follow = false })"
        if (dispatcher === "focuswindow")
            return "hl.dsp.focus({ window = " + root._quote(args) + " })"
        return ""
    }

    function _text(dispatcher, args): string {
        if (root.useLua) {
            const call = root._luaCall(dispatcher, args)
            if (call.length > 0) return call
        }
        return (args !== undefined && args !== null && String(args).length > 0)
            ? dispatcher + " " + String(args) : dispatcher
    }

    function dispatch(dispatcher, args): void {
        if (!SystemTools.ready || !SystemTools.hasHyprctl) return
        if (root.useLua && (dispatcher === "focusmonitor" || dispatcher === "workspace"
            || dispatcher === "movetoworkspacesilent" || dispatcher === "focuswindow")) {
            const call = root._luaCall(dispatcher, args)
            if (call.length === 0) return
            Quickshell.execDetached(["hyprctl", "dispatch", call])
            return
        }
        const cmd = ["hyprctl", "dispatch", dispatcher]
        if (args !== undefined && args !== null && String(args).length > 0)
            cmd.push(String(args))
        Quickshell.execDetached(cmd)
    }

    // chain in one sh: detached hyprctl processes land out of order, and --batch mangles the quoted lua-framework calls
    function dispatchPair(d1, a1, d2, a2): void {
        if (!SystemTools.ready || !SystemTools.hasHyprctl) return
        Quickshell.execDetached(["sh", "-c",
            "hyprctl dispatch \"$1\" >/dev/null && hyprctl dispatch \"$2\"",
            "sh", root._text(d1, a1), root._text(d2, a2)])
    }
}
