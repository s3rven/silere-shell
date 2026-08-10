pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "../config"

Singleton {
    id: root

    // ephemeral by design: players come and go, so a pinned choice is dropped the moment its player leaves the bus
    property string preferredPlayer: ""

    readonly property var playerList: {
        const out = []
        const players = Mpris.players.values ?? []
        for (let i = 0; i < players.length; i++)
            if (players[i]) out.push(players[i])
        // playerctld only mirrors the real players; keep it solely when nothing else is on the bus
        const real = out.filter(p => (p.dbusName || "").indexOf("playerctld") < 0)
        return real.length > 0 ? real : out
    }
    readonly property int playerCount: playerList.length

    onPlayerListChanged: {
        if (root.preferredPlayer.length === 0) return
        for (let i = 0; i < root.playerList.length; i++)
            if (root.playerList[i].dbusName === root.preferredPlayer) return
        root.preferredPlayer = ""
    }

    function cyclePlayer(): void {
        const players = root.playerList
        if (players.length < 2) return
        let idx = -1
        for (let i = 0; i < players.length; i++)
            if (players[i] === root.player) { idx = i; break }
        root.preferredPlayer = players[(idx + 1) % players.length].dbusName
    }

    readonly property var player: {
        const players = root.playerList
        let fallback = null

        if (root.preferredPlayer.length > 0) {
            for (let i = 0; i < players.length; i++)
                if (players[i].dbusName === root.preferredPlayer) return players[i]
        }

        for (let i = 0; i < players.length; i++) {
            const p = players[i]
            if (!p) continue
            if (p.isPlaying) return p
            if (p.playbackState !== MprisPlaybackState.Stopped) {
                if (!fallback || fallback.playbackState === MprisPlaybackState.Stopped) fallback = p
            } else if (!fallback) {
                fallback = p
            }
        }

        return fallback
    }

    readonly property bool available: player !== null
        && (player.playbackState !== MprisPlaybackState.Stopped || title.length > 0)
    readonly property bool playing: player ? player.isPlaying : false

    readonly property bool canTogglePlaying: player ? player.canTogglePlaying : false
    readonly property bool canGoNext:        player ? player.canGoNext : false
    readonly property bool canGoPrevious:    player ? player.canGoPrevious : false

    property bool shown: false

    function _syncShown(): void {
        if (!available)  { _pauseTimer.stop(); _hideTimer.stop(); if (shown) shown = false; return }
        if (playing)     { _pauseTimer.stop(); _hideTimer.stop(); if (!shown) shown = true; return }
        if (shown && !_pauseTimer.running && !_hideTimer.running) _pauseTimer.start()
    }

    onAvailableChanged: { _syncShown(); _syncStableArt() }
    onPlayingChanged:   { _syncShown(); _reanchor() }
    Component.onCompleted: { _syncShown(); _reanchor(); if (artUrl.length > 0) stableArtUrl = artUrl }

    Timer { id: _pauseTimer; interval: 5000;  onTriggered: _hideTimer.start() }
    Timer { id: _hideTimer;  interval: 10000; onTriggered: root.shown = false  }

    // MPRIS reports 2^63-1 microseconds for anything with no end, which every live
    // stream is; a real track is never a day long, so past the cap it means unknown
    readonly property real _rawLength:  (player && player.lengthSupported) ? Math.max(0, player.length) : 0
    readonly property bool lengthKnown: _rawLength > 0 && _rawLength <= 86400
    readonly property real length:      lengthKnown ? _rawLength : 0
    readonly property bool canSeek:     player ? player.canSeek : false
    // position still ticks without a length; only the ratio and the seek bar need one
    readonly property bool hasPosition: player !== null && player.positionSupported

    property real  _anchorPos:  0
    property real  _anchorMs:   0
    property real  positionNow: 0
    readonly property real positionRatio: length > 0 ? Math.max(0, Math.min(1, positionNow / length)) : 0
    readonly property bool positionVisible: MenuState.homeActive
        || (ShellSettings.barShowMedia && root.shown && ShellSettings.mediaWidgetHelper)

    function _reanchor(): void {
        root._anchorPos = (player && player.positionSupported) ? Math.max(0, player.position) : 0
        root._anchorMs  = Date.now()
        _recompute()
    }
    function _recompute(): void {
        if (!player) { positionNow = 0; return }
        let p = root._anchorPos
        if (playing) p += (Date.now() - root._anchorMs) / 1000
        positionNow = root.length > 0 ? Math.max(0, Math.min(root.length, p)) : Math.max(0, p)
    }
    function seekToRatio(r: real): void {
        if (!player || !canSeek || length <= 0) return
        const target = Math.max(0, Math.min(1, r)) * length
        player.position = target
        root._anchorPos = target
        root._anchorMs  = Date.now()
        _recompute()
    }
    function formatTime(secs: real): string {
        const s  = (isFinite(secs) && secs > 0) ? Math.floor(secs) : 0
        const h  = Math.floor(s / 3600)
        const m  = Math.floor((s % 3600) / 60)
        const ss = String(s % 60).padStart(2, "0")
        return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${ss}` : `${m}:${ss}`
    }

    Connections {
        target: root.player
        enabled: root.player !== null
        function onPositionChanged() { root._reanchor() }
    }
    onPositionVisibleChanged: if (positionVisible) root._reanchor()
    Timer {
        interval: 500; repeat: true
        running: root.playing && root.hasPosition && !Idle.isIdle
            && root.positionVisible
        onTriggered: root._recompute()
    }

    onPlayerChanged: _reanchor()
    readonly property string artist: player ? player.trackArtist : ""
    readonly property string title: player ? player.trackTitle : ""
    readonly property string identity: player ? player.identity : ""
    readonly property string desktopEntry: player ? player.desktopEntry : ""

    readonly property string artUrl: {
        if (!player) return ""
        // remote art is allowed on purpose where notification icons are denied: mpris art genuinely is a url
        // Spotify's Linux client reports an open.spotify.com/image link that 404s
        return (player.trackArtUrl || "")
            .replace("https://open.spotify.com/image/", "https://i.scdn.co/image/")
    }

    property string stableArtUrl: ""
    function _syncStableArt(): void {
        if (root.artUrl.length > 0) root.stableArtUrl = root.artUrl
        else if (!root.available)   root.stableArtUrl = ""
    }
    onArtUrlChanged: _syncStableArt()
    onTitleChanged: { _reanchor(); _syncStableArt() }

    readonly property string playerName:
        !player              ? "" :
        desktopEntry.length > 0 ? desktopEntry :
        identity.length > 0     ? identity :
        player.dbusName || ""

    readonly property string label: {
        if (ShellSettings.mediaWidgetFormat === "artist-title" && artist.length > 0 && title.length > 0)
            return artist + " - " + title
        if (title.length > 0) return title
        if (artist.length > 0) return artist
        if (identity.length > 0) return identity
        if (desktopEntry.length > 0) return desktopEntry
        return player ? "Media" : ""
    }

    property var barHeights: []
    readonly property bool cavaReady: SystemTools.hasCava && ShellSettings.mediaProgress
    property int _visualizerClients: 0
    property int _visualizerDemand: 0
    readonly property bool _visualizerLowPowerOnly: _visualizerClients > 0 && _visualizerDemand <= _visualizerClients
    readonly property string _cavaProfileKey: [
        _cavaBars,
        _cavaFps,
        _cavaNoiseReduction
    ].join(":")

    function registerVisualizer(lowPower: bool): void {
        const warmHandoff = _visualizerStopGrace.running
        if (_visualizerClients === 0 && !warmHandoff) _cavaConfigReady = false
        _visualizerDemand += lowPower ? 1 : 2
        _visualizerClients++
        if (!_cavaConfigReady || _writtenCavaProfileKey !== _cavaProfileKey)
            _writeCavaConfig()
        _visualizerStopGrace.stop()
    }
    function unregisterVisualizer(lowPower: bool): void {
        if (_visualizerClients <= 0) return
        if (_visualizerClients === 1) _visualizerStopGrace.restart()
        _visualizerClients = Math.max(0, _visualizerClients - 1)
        _visualizerDemand = Math.max(0, _visualizerDemand - (lowPower ? 1 : 2))
    }
    function updateVisualizerPower(previousLowPower: bool, nextLowPower: bool): void {
        if (previousLowPower === nextLowPower || _visualizerClients <= 0) return
        _visualizerDemand = Math.max(0, _visualizerDemand
            - (previousLowPower ? 1 : 2) + (nextLowPower ? 1 : 2))
    }

    Timer { id: _visualizerStopGrace; interval: 150 }

    readonly property int _cavaBars: {
        if (_visualizerLowPowerOnly)
            return ShellSettings.mediaVisualizerPreset === "smooth" ? 10
                 : ShellSettings.mediaVisualizerPreset === "eco"    ? 6
                 :                                                     8
        if (ShellSettings.mediaVisualizerStyle === "pulse")
            return ShellSettings.mediaVisualizerPreset === "smooth" ? 14
                 : ShellSettings.mediaVisualizerPreset === "eco"    ? 8
                 :                                                     10
        if (ShellSettings.mediaVisualizerStyle === "bars")
            return ShellSettings.mediaVisualizerPreset === "smooth" ? 18
                 : ShellSettings.mediaVisualizerPreset === "eco"    ? 10
                 :                                                     14
        switch (ShellSettings.mediaVisualizerPreset) {
        case "eco":    return 10
        case "smooth": return 22
        default:       return 16
        }
    }
    readonly property int _cavaFps: {
        if (_visualizerLowPowerOnly)
            return ShellSettings.mediaVisualizerPreset === "smooth" ? 34
                 : ShellSettings.mediaVisualizerPreset === "eco"    ? 18
                 :                                                     26
        const shapeTrim = ShellSettings.mediaVisualizerStyle === "pulse" ? 6
                        : ShellSettings.mediaVisualizerStyle === "bars"  ? 3
                        : 0
        switch (ShellSettings.mediaVisualizerPreset) {
        case "eco":    return Math.max(20, 26 - shapeTrim)
        case "smooth": return Math.max(36, 50 - shapeTrim)
        default:       return Math.max(28, 38 - shapeTrim)
        }
    }
    readonly property real _cavaNoiseReduction: {
        switch (ShellSettings.mediaVisualizerPreset) {
        // cava expects this on a 0-100 scale, not a normalized 0-1 scale
        case "eco":    return 72
        case "smooth": return 46
        default:       return 58
        }
    }
    readonly property var _zeroBars: {
        const out = []
        for (let i = 0; i < _cavaBars; i++) out.push(0)
        return out
    }
    readonly property string _cavaConfigText:
        "[general]\n" +
        "bars = " + _cavaBars + "\n" +
        "sleep_timer = 2\n" +
        "framerate = " + _cavaFps + "\n" +
        "autosens = 1\n" +
        "lower_cutoff_freq = 45\n" +
        "higher_cutoff_freq = 10000\n" +
        "\n[input]\n" +
        "method = pipewire\n" +
        "source = auto\n" +
        "\n[output]\n" +
        "method = raw\n" +
        "raw_target = /dev/stdout\n" +
        "data_format = ascii\n" +
        "ascii_max_range = 12\n" +
        "bar_delimiter = 59\n" +
        "frame_delimiter = 10\n" +
        "channels = mono\n" +
        "\n[smoothing]\n" +
        "noise_reduction = " + _cavaNoiseReduction + "\n"
    // runtime-owned path avoids symlink attacks through /tmp
    readonly property string _cavaConfigPath: {
        const runtime = String(Quickshell.env("XDG_RUNTIME_DIR") || "").trim()
        return runtime.startsWith("/")
            ? runtime + "/silere-shell-cava-" + Quickshell.processId + ".conf"
            : ""
    }
    property bool _cavaConfigReady: false
    property string _writtenCavaProfileKey: ""
    readonly property int _cavaReloadSignal: 10

    // blocking writes let save failure veto readiness before cava starts
    function _writeCavaConfig(): void {
        if (root._cavaConfigPath.length === 0) return
        _cavaConfigSync.stop()
        const nextProfile = root._cavaProfileKey
        const reloadRunning = _cavaProc.running
            && root._writtenCavaProfileKey.length > 0
            && root._writtenCavaProfileKey !== nextProfile
        root._cavaConfigReady = true
        _cavaConfig.setText(root._cavaConfigText)
        if (!root._cavaConfigReady) return
        root._writtenCavaProfileKey = nextProfile
        if (reloadRunning) _cavaProc.signal(root._cavaReloadSignal)
    }

    on_CavaProfileKeyChanged: if (root._visualizerClients > 0) _cavaConfigSync.restart()

    Timer {
        id: _cavaConfigSync
        interval: 0
        onTriggered: root._writeCavaConfig()
    }

    FileView {
        id: _cavaConfig
        path: root._cavaConfigPath
        atomicWrites: true
        blockWrites: true
        printErrors: false
        onSaveFailed: {
            root._cavaConfigReady = false
            root._writtenCavaProfileKey = ""
        }
    }

    property bool _fsBlocked: false
    readonly property bool _fullscreenPauseWanted: ShellSettings.mediaProgress
    Connections {
        target: Notifications
        enabled: root._fullscreenPauseWanted
        function onFullscreenActiveChanged() {
            if (Notifications.fullscreenActive) _fsBlockTimer.restart()
            else { _fsBlockTimer.stop(); root._fsBlocked = false }
        }
    }
    Timer { id: _fsBlockTimer; interval: 2000; onTriggered: root._fsBlocked = true }
    on_FullscreenPauseWantedChanged: {
        if (!root._fullscreenPauseWanted) {
            _fsBlockTimer.stop()
            root._fsBlocked = false
        } else if (Notifications.fullscreenActive) {
            _fsBlockTimer.restart()
        }
    }

    SupervisedProcess {
        id: _cavaProc
        command: ["cava", "-p", root._cavaConfigPath]
        superviseWhen: root._cavaConfigReady && root.cavaReady
            && (root._visualizerClients > 0 || _visualizerStopGrace.running)
            && root.available && root.playing && !Idle.isIdle && !root._fsBlocked
        restartDelay: 1000
        maxRestartDelay: 30000
        stableAfter: 20000
        stdout: SplitParser {
            onRead: line => {
                const parts = line.split(";")
                const result = []
                for (let i = 0; i < parts.length; i++) {
                    if (parts[i].length === 0) continue
                    const value = Number(parts[i])
                    if (isNaN(value)) continue
                    const normalized = Math.max(0, Math.min(1, value / 12))
                    result.push(Math.pow(normalized, 1.3))
                }
                if (result.length !== root._cavaBars) return
                const prev = root.barHeights
                let changed = prev.length !== result.length
                for (let i = 0; !changed && i < result.length; i++)
                    if (Math.abs(result[i] - prev[i]) > 0.02) changed = true
                if (changed) root.barHeights = result
            }
        }
        onRunningChanged: if (!running) root.barHeights = root._zeroBars
    }

    function togglePlay(): void {
        if (!canTogglePlaying) return
        player.togglePlaying()
    }

    function next(): void {
        if (!canGoNext) return
        player.next()
    }

    function previous(): void {
        if (!canGoPrevious) return
        player.previous()
    }
}
