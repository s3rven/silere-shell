pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // `silere indicator` answers before the bar has drawn one
    readonly property bool armed: true
    readonly property int maxItems: 6
    // a script's own marks, set and cleared by the script: nothing here polls or runs anything
    property var items: []

    function set(name: string, glyph: string, text: string): string {
        const key = String(name ?? "")
        if (!/^[a-z0-9][a-z0-9-]{0,31}$/.test(key)) return "error: a name is up to 32 lowercase letters, digits and dashes"
        const mark = SafeText.singleLineText(glyph, 8)
        if (mark.length === 0) return "error: give a glyph to show"
        const item = { name: key, glyph: mark, label: SafeText.singleLineText(text, 32) }
        const at = root.items.findIndex(i => i.name === key)
        if (at < 0 && root.items.length >= root.maxItems) return "error: " + root.maxItems + " indicators at most; clear one first"
        const next = root.items.slice()
        if (at < 0) next.push(item)
        else next[at] = item
        root.items = next
        return "ok"
    }

    function clear(name: string): string {
        const next = root.items.filter(i => i.name !== String(name ?? ""))
        if (next.length === root.items.length) return "error: no indicator named '" + SafeText.singleLineText(name, 32) + "'"
        root.items = next
        return "ok"
    }

    IpcHandler {
        target: "indicators"
        function set(name: string, glyph: string, text: string): string { return root.set(name, glyph, text) }
        function clear(name: string): string { return root.clear(name) }
        function list(): string { return root.items.map(i => i.name + "\t" + i.glyph + "\t" + i.label).join("\n") }
    }
}
