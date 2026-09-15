pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "../config"

Singleton {
    id: root

    readonly property real stepPct: 0.05

    readonly property PwNode      sink:  Pipewire.defaultAudioSink
    readonly property PwNode      source: Pipewire.defaultAudioSource

    readonly property PwVolumeControl _out: PwVolumeControl {
        node: root.sink
        enabled: Pipewire.ready
    }
    readonly property PwVolumeControl _in: PwVolumeControl {
        node: root.source
        enabled: Pipewire.ready
    }

    readonly property bool ready: _out.ready
    readonly property real targetVolume: _out.targetVolume
    readonly property bool pendingApply: _out.pendingApply
    readonly property real effectiveVolume: _out.effectiveVolume
    readonly property bool muted: _out.muted
    readonly property real uiVolume: _out.uiVolume

    readonly property bool micReady: _in.ready
    readonly property bool micMuted: _in.muted
    readonly property real micVolume: _in.uiVolume

    // icon name and form factor live on the device, not the node, and a bluez sink carries
    // neither: the node name and its description are all there is to go on. Any Bluetooth
    // audio sink reads as a headset, since nothing on the node separates one from a speaker
    function deviceClass(node): string {
        if (!node) return ""
        const props = node.properties || ({})
        const stated = (String(props["device.form-factor"] || "") + " "
            + String(props["device.icon-name"] || "")).toLowerCase()
        if (stated.indexOf("headset") >= 0 || stated.indexOf("headphone") >= 0) return "headset"
        if (stated.indexOf("speaker") >= 0) return "speaker"
        const name = String(node.name || "")
        // a bluez sink states neither, so the name alone would call every speaker a headset
        if (name.toLowerCase().indexOf("bluez") >= 0) {
            const btIcon = Bluetooth.iconForNodeName(name).toLowerCase()
            if (btIcon.indexOf("speaker") >= 0 || btIcon.indexOf("audio-card") >= 0)
                return "speaker"
            return "headset"
        }
        const hay = (name + " " + String(node.description || "")).toLowerCase()
        if (hay.indexOf("bluetooth") >= 0 || hay.indexOf("headset") >= 0
                || hay.indexOf("headphone") >= 0) return "headset"
        return "speaker"
    }
    readonly property string sinkClass: root.deviceClass(sink)

    // the level glyphs give way only for a headset, which is the routing worth seeing at a
    // glance; the percentage and the hover level bar still carry the level
    readonly property string icon:
        !ready                   ? "󰝟" :
        muted || uiVolume === 0  ? "󰖁" :
        sinkClass === "headset"  ? "󰋋" :
        uiVolume < 0.33          ? "󰕿" :
        uiVolume < 0.66          ? "󰖀" : "󰕾"
    readonly property string label: ready ? `${Math.round(uiVolume * 100)}%` : "--%"
    readonly property string sinkName: root.sinkLabel(sink)

    readonly property string micIcon: !micReady || micMuted ? "󰍭" : "󰍬"
    readonly property string micLabel: micReady ? `${Math.round(micVolume * 100)}%` : "--%"
    readonly property string sourceName: root.sinkLabel(source)

    readonly property var _nodes: Pipewire.nodes ? (Pipewire.nodes.values || []) : []

    function _isType(node, flag): bool {
        return node !== null && (node.type & flag) === flag
    }

    readonly property var sinks: {
        const out = []
        // PipeWire briefly detaches its node model while reconnecting.
        const all = root._nodes
        for (let i = 0; i < all.length; i++) {
            const n = all[i]
            if (n && n.isSink && !n.isStream) out.push(n)
        }
        return out
    }
    readonly property int sinkCount: sinks.length
    readonly property var sinkModel: sinks.map(n => ({ value: n, label: root.sinkLabel(n) }))

    readonly property var sources: {
        const out = []
        const all = root._nodes
        for (let i = 0; i < all.length; i++) {
            const n = all[i]
            if (n && !n.isStream && root._isType(n, PwNodeType.AudioSource)) out.push(n)
        }
        return out
    }
    readonly property int sourceCount: sources.length
    readonly property var sourceModel: sources.map(n => ({ value: n, label: root.sinkLabel(n) }))

    // type only, like _inputStreams below: this is what gets tracked, and filtering the
    // tracked set on a property is a binding loop through PwObjectTracker
    readonly property var _outputStreams: {
        const out = []
        const all = root._nodes
        for (let i = 0; i < all.length; i++)
            if (root._isType(all[i], PwNodeType.AudioOutStream)) out.push(all[i])
        return out
    }

    // a stream with no application behind it is PipeWire routing of its own — a loopback,
    // a combine sink — and has no place in a list of apps
    function isAppStream(props): bool {
        const p = props || ({})
        return String(p["application.name"] || "").length > 0
            || String(p["application.process.binary"] || "").length > 0
    }

    readonly property var playbackStreams: {
        const out = []
        const streams = root._outputStreams
        for (let i = 0; i < streams.length; i++) {
            const n = streams[i]
            if (root.isAppStream(n ? n.properties : null)) out.push(n)
        }
        return out
    }
    // an app recording system output is an input stream too, and counting it lights the
    // microphone indicator for the visualiser and every screen recorder. cava flags
    // stream.capture.sink; a monitor named as the target says the same thing on its own
    function capturesOutput(props): bool {
        const p = props || ({})
        const flag = p["stream.capture.sink"]
        if (flag === true || String(flag).toLowerCase() === "true") return true
        const target = String(p["target.object"] || p["node.target"] || "")
        return target.endsWith(".monitor")
    }

    // tracking is what fills in `properties`, so the tracked set is chosen on node type
    // alone; filtering it on a property here is a binding loop through PwObjectTracker
    readonly property var _inputStreams: {
        const out = []
        const all = root._nodes
        for (let i = 0; i < all.length; i++)
            if (root._isType(all[i], PwNodeType.AudioInStream)) out.push(all[i])
        return out
    }

    readonly property var captureStreams: {
        const out = []
        const streams = root._inputStreams
        for (let i = 0; i < streams.length; i++) {
            const n = streams[i]
            const props = n ? n.properties : null
            if (root.isAppStream(props) && !root.capturesOutput(props)) out.push(n)
        }
        return out
    }
    readonly property int playbackCount: playbackStreams.length
    readonly property int captureCount: captureStreams.length
    readonly property bool micActive: captureCount > 0
    readonly property string captureSummary: {
        const c = root.captureStreams
        if (c.length === 0) return ""
        if (c.length === 1) return root.streamLabel(c[0])
        return c.length + " apps listening"
    }

    readonly property var playbackModel:
        playbackStreams.map(n => ({ value: n, label: root.streamLabel(n) }))
    readonly property var captureModel:
        captureStreams.map(n => ({ value: n, label: root.streamLabel(n) }))

    // the streams are tracked too: without it a per-app row has no audio interface to move
    readonly property var _tracked: {
        const out = []
        if (root.sink) out.push(root.sink)
        if (root.source) out.push(root.source)
        const play = root._outputStreams
        for (let i = 0; i < play.length; i++) out.push(play[i])
        const cap = root._inputStreams
        for (let i = 0; i < cap.length; i++) out.push(cap[i])
        return out
    }

    PwObjectTracker { objects: root._tracked }

    function setSink(node): void {
        if (node) Pipewire.preferredDefaultAudioSink = node
    }

    function setSource(node): void {
        if (node) Pipewire.preferredDefaultAudioSource = node
    }

    function cycleSink(): void {
        const list = root.sinks
        if (list.length < 2) return
        const i = list.indexOf(root.sink)
        root.setSink(list[(i + 1) % list.length])
    }

    function cycleSource(): void {
        const list = root.sources
        if (list.length < 2) return
        const i = list.indexOf(root.source)
        root.setSource(list[(i + 1) % list.length])
    }

    function openSoundSettings(): bool {
        const argv = Settings.soundSettingsCommand
        if (argv.length === 0) return false
        Quickshell.execDetached(argv)
        return true
    }
    readonly property bool hasSoundSettings: Settings.soundSettingsCommand.length > 0
    readonly property string soundSettingsName: root.hasSoundSettings
        ? String(Settings.soundSettingsCommand[0]) : ""

    function sinkLabel(node): string {
        if (!node) return ""
        return SafeText.singleLineText(
            node.description || node.nickname || node.name || "Output", 256)
    }

    // a stream is named for the app behind it; its own description is the track or pipeline
    function streamLabel(node): string {
        if (!node) return ""
        const props = node.properties || ({})
        const app = props["application.name"] || props["media.name"] || ""
        return SafeText.singleLineText(
            app || node.description || node.nickname || node.name || "App", 256)
    }

    function bumpBy(delta: real): void { root._out.bumpBy(delta) }
    function setVolume(v: real): void  { root._out.setVolume(v) }
    function toggleMute(): void        { root._out.toggleMute() }

    function micBumpBy(delta: real): void { root._in.bumpBy(delta) }
    function setMicVolume(v: real): void  { root._in.setVolume(v) }
    function toggleMicMute(): void        { root._in.toggleMute() }
}
