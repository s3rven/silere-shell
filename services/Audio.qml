pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "../config"

Singleton {
    id: root

    readonly property bool armed: true
    readonly property real stepPct: 0.05

    readonly property PwNode      sink:  Pipewire.defaultAudioSink
    readonly property PwNode      source: Pipewire.defaultAudioSource

    readonly property PwVolumeControl _out: PwVolumeControl {
        node: root.sink
        enabled: Pipewire.ready
    }
    signal micMutedExternally()

    readonly property PwVolumeControl _in: PwVolumeControl {
        node: root.source
        enabled: Pipewire.ready
        onMutedExternally: root.micMutedExternally()
    }

    readonly property bool ready: _out.ready
    readonly property real targetVolume: _out.targetVolume
    readonly property bool pendingApply: _out.pendingApply
    readonly property bool muted: _out.muted
    readonly property real uiVolume: _out.uiVolume

    readonly property bool micReady: _in.ready
    readonly property bool micMuted: _in.muted
    readonly property real micVolume: _in.uiVolume

    // icon name and form factor live on the device, not the node, and a bluez sink carries
    // neither: the node name and its description are all there is to go on. Any Bluetooth
    // audio sink reads as a headset, since nothing on the node separates one from a speaker
    readonly property var _linkGroups: Pipewire.linkGroups ? (Pipewire.linkGroups.values || []) : []

    function _isVirtual(props): bool {
        const v = props["node.virtual"]
        return v === true || String(v) === "true"
    }

    // a combine sink, loopback or filter chain feeds devices through its own streams, which share its node.group
    function _fedDevices(node, links): var {
        const props = node.properties || ({})
        const group = String(props["node.group"] || props["node.link-group"] || "")
        const out = []
        if (group.length === 0) return out
        for (let i = 0; i < links.length; i++) {
            const src = links[i] ? links[i].source : null
            const dst = links[i] ? links[i].target : null
            if (!src || !dst || src === node || dst === node || dst.isStream) continue
            const p = src.properties || ({})
            if (String(p["node.group"] || p["node.link-group"] || "") === group) out.push(dst)
        }
        return out
    }

    // only routing visible here (a node.group shared with its streams) can be said to reach no device;
    // a sink fed by another process, like an equalizer app, is never flagged
    function feedsNothing(node, links): bool {
        if (!node) return false
        const props = node.properties || ({})
        if (!root._isVirtual(props)) return false
        if (String(props["node.group"] || props["node.link-group"] || "").length === 0) return false
        return root._fedDevices(node, links || root._linkGroups).length === 0
    }

    function deviceClass(node, links, depth): string {
        if (!node) return ""
        const props = node.properties || ({})
        // a virtual sink is named by its config ("Combined Headphones"), not by what is plugged in
        if (root._isVirtual(props)) {
            const level = depth || 0
            if (level > 3) return "speaker"
            const fed = root._fedDevices(node, links || root._linkGroups)
            for (let i = 0; i < fed.length; i++)
                if (root.deviceClass(fed[i], links, level + 1) === "headset") return "headset"
            return "speaker"
        }
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
        // PipeWire briefly detaches its node model while reconnecting
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

    // type only, like _inputStreams below: this is what gets tracked, and filtering the tracked set on a property is a binding loop through PwObjectTracker
    readonly property var _outputStreams: {
        const out = []
        const all = root._nodes
        for (let i = 0; i < all.length; i++)
            if (root._isType(all[i], PwNodeType.AudioOutStream)) out.push(all[i])
        return out
    }

    // a stream with no application behind it is PipeWire routing of its own — a loopback, a combine sink — and has no place in a list of apps
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

    function trackedNodes(defaultSink, defaultSource, sinks, sources, playback, capture): var {
        const out = []
        function add(node) {
            if (node && out.indexOf(node) < 0) out.push(node)
        }
        add(defaultSink)
        add(defaultSource)
        for (const group of [sinks, sources, playback, capture])
            for (const node of group) add(node)
        return out
    }

    // both device pickers read node properties before a device becomes the default;
    // streams also need binding so their per-app controls can change audio
    readonly property var _tracked: root.trackedNodes(root.sink, root.source,
        root.sinks, root.sources, root._outputStreams, root._inputStreams)

    PwObjectTracker { objects: root._tracked }

    function setSink(node): void {
        if (node) Pipewire.preferredDefaultAudioSink = node
    }

    function setSource(node): void {
        if (node) Pipewire.preferredDefaultAudioSource = node
    }

    function cycleSink(): string {
        const list = root.sinks
        if (list.length < 2) return ""
        const i = list.indexOf(root.sink)
        const next = list[(i + 1) % list.length]
        root.setSink(next)
        return root.sinkLabel(next)
    }

    function cycleSource(): string {
        const list = root.sources
        if (list.length < 2) return ""
        const i = list.indexOf(root.source)
        const next = list[(i + 1) % list.length]
        root.setSource(next)
        return root.sinkLabel(next)
    }

    function openSoundSettings(): bool {
        const argv = Settings.soundSettingsCommand
        if (argv.length === 0) return false
        Compositor.launch(argv)
        return true
    }
    readonly property bool hasSoundSettings: Settings.soundSettingsCommand.length > 0
    readonly property string soundSettingsName: root.hasSoundSettings
        ? String(Settings.soundSettingsCommand[0]) : ""

    // a headset an app's microphone moved onto hands-free keeps its name and drops to call quality; the suffix is what makes the osd say so
    function sinkLabel(node, peers): string {
        if (!node) return ""
        const name = SafeText.singleLineText(root._cardLabel(node, peers ?? (node.isSink ? root.sinks : root.sources))
            || node.nickname || node.name || (node.isSink ? "Output" : "Input"), 256)
        const profile = String((node.properties || {})["api.bluez5.profile"] || "")
        return node.isSink && profile.indexOf("headset") === 0 ? name + " · Call mode" : name
    }

    // ALSA names a node card + profile ("… Analog Stereo"), which truncates in the menu; the card
    // alone is enough unless another node of the same card is in the list beside it
    function _cardLabel(node, peers): string {
        const desc = String(node.description || "")
        const profile = String((node.properties || {})["device.profile.description"] || "")
        if (profile.length === 0 || desc.length <= profile.length + 1 || !desc.endsWith(" " + profile)) return desc
        const card = desc.slice(0, desc.length - profile.length - 1)
        for (const p of peers || [])
            if (p && p !== node && String(p.description || "").startsWith(card)) return desc
        return card
    }

    // a stream is named for the app behind it; its own description is the track or pipeline
    function streamLabel(node): string {
        if (!node) return ""
        const props = node.properties || ({})
        const app = props["application.name"] || props["media.name"] || ""
        return SafeText.singleLineText(
            app || node.description || node.nickname || node.name || "App", 256)
    }

    // DesktopEntries answers null until its first scan lands; reading this reruns a lookup then
    property int _entriesRevision: 0
    Connections {
        target: DesktopEntries
        function onApplicationsChanged() { root._entriesRevision++ }
    }

    // the app's own icon: its icon name if it sends one, else the name it plays under, else its binary
    function streamIcon(node): string {
        void root._entriesRevision
        if (!node) return ""
        const props = node.properties || ({})
        for (const key of ["application.icon-name", "application.name", "application.process.binary"]) {
            const id = String(props[key] || "")
            const icon = id.length > 0 ? (IconResolver.appMeta(id)?.icon ?? "") : ""
            if (icon.length > 0) return icon
        }
        return ""
    }

    function bumpBy(delta: real): void { root._out.bumpBy(delta) }
    function setVolume(v: real): void  { root._out.setVolume(v) }
    function toggleMute(): void        { root._out.toggleMute() }

    function micBumpBy(delta: real): void { root._in.bumpBy(delta) }
    function setMicVolume(v: real): void  { root._in.setVolume(v) }
    function toggleMicMute(): void        { root._in.toggleMute() }

    function _ipcSetVolume(percent: int, microphone: bool): string {
        if (percent < 0 || percent > 100) return "error: volume must be between 0 and 100"
        const control = microphone ? root._in : root._out
        if (!control.ready) return microphone ? "error: no audio input available" : "error: no audio output available"
        control.setVolume(percent / 100)
        if (microphone) root._ipcMicFeedback()
        return Math.round(control.effectiveVolume * 100) + "%"
    }

    function _ipcStepVolume(direction: int, microphone: bool): string {
        const control = microphone ? root._in : root._out
        if (!control.ready) return microphone ? "error: no audio input available" : "error: no audio output available"
        control.bumpBy(direction * root.stepPct)
        if (microphone) root._ipcMicFeedback()
        return Math.round(control.effectiveVolume * 100) + "%"
    }

    function _ipcToggleMute(microphone: bool): string {
        const control = microphone ? root._in : root._out
        if (!control.ready) return microphone ? "error: no audio input available" : "error: no audio output available"
        control.toggleMute()
        if (microphone) root._ipcMicFeedback()
        return control.muted ? "muted" : "unmuted"
    }

    function _ipcCycleDevice(microphone: bool): string {
        const devices = microphone ? root.sources : root.sinks
        if (devices.length === 0) return microphone ? "error: no audio input available" : "error: no audio output available"
        if (devices.length < 2) return microphone ? "error: only one audio input available" : "error: only one audio output available"
        // defaults change asynchronously; return the device requested by this call
        return microphone ? root.cycleSource() : root.cycleSink()
    }

    function _ipcMicFeedback(): void {
        OsdBarState.show("microphone", root.micIcon, root.micVolume,
            root.micMuted ? "Microphone muted" : "Microphone · " + root.micLabel, root.micMuted)
    }

    readonly property IpcHandler _ipc: IpcHandler {
        target: "audio"

        function setVolume(percent: int): string { return root._ipcSetVolume(percent, false) }
        function volumeUp(): string { return root._ipcStepVolume(1, false) }
        function volumeDown(): string { return root._ipcStepVolume(-1, false) }
        function toggleMute(): string { return root._ipcToggleMute(false) }
        function cycleOutput(): string { return root._ipcCycleDevice(false) }

        function setMicVolume(percent: int): string { return root._ipcSetVolume(percent, true) }
        function micUp(): string { return root._ipcStepVolume(1, true) }
        function micDown(): string { return root._ipcStepVolume(-1, true) }
        function toggleMicMute(): string { return root._ipcToggleMute(true) }
        function cycleInput(): string { return root._ipcCycleDevice(true) }

        function status(): string {
            return JSON.stringify({
                output: { ready: root.ready, name: root.sinkName,
                    volume: Math.round(root._out.effectiveVolume * 100), muted: root.muted },
                input: { ready: root.micReady, name: root.sourceName,
                    volume: Math.round(root._in.effectiveVolume * 100), muted: root.micMuted }
            })
        }
    }
}
