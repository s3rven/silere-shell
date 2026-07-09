pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Singleton {
    id: root

    readonly property var player: {
        const players = Mpris.players.values ?? []
        let fallback = null

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

    // capability props live here so every consumer shares one tracked binding to the current player
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

    // anchor-extrapolate: MPRIS only reports position on change, so we record it + a timestamp and drift forward
    readonly property real length:      (player && player.lengthSupported) ? Math.max(0, player.length) : 0
    readonly property bool canSeek:     player ? player.canSeek : false
    readonly property bool hasPosition: player !== null && player.positionSupported && length > 0

    property real  _anchorPos:  0
    property real  _anchorMs:   0
    property real  positionNow: 0
    readonly property real positionRatio: length > 0 ? Math.max(0, Math.min(1, positionNow / length)) : 0
    readonly property bool positionVisible: (MenuState.open && MenuState.activeTab === 0)
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
        // Spotify's Linux client reports an open.spotify.com/image link that 404s.
        return (player.trackArtUrl || "")
            .replace("https://open.spotify.com/image/", "https://i.scdn.co/image/")
    }

    property string stableArtUrl: ""
    function _syncStableArt(): void {
        if (root.artUrl.length > 0) root.stableArtUrl = root.artUrl
        else if (!root.available)   root.stableArtUrl = ""
        // else: player active, artUrl transiently empty — hold current art
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
    readonly property string _cavaProfileKey: _cavaBars + ":" + _cavaFps + ":" + _cavaSensitivity + ":" + _cavaNoiseReduction

    function _restartCavaIfProfileChanged(oldProfile: string): void {
        Qt.callLater(function() {
            if (_cavaProc.running && oldProfile !== _cavaProfileKey) root._restartCava()
        })
    }
    function registerVisualizer(lowPower): void {
        const wasRunning = _cavaProc.running
        const oldProfile = _cavaProfileKey
        _visualizerClients++
        _visualizerDemand += lowPower ? 1 : 2
        // Only restart when the output shape changes; adding another same-profile canvas should not flash CAVA to zero.
        if (wasRunning) _restartCavaIfProfileChanged(oldProfile)
    }
    function unregisterVisualizer(lowPower): void {
        const wasRunning = _cavaProc.running
        const oldProfile = _cavaProfileKey
        _visualizerClients = Math.max(0, _visualizerClients - 1)
        _visualizerDemand = Math.max(0, _visualizerDemand - (lowPower ? 1 : 2))
        if (wasRunning) _restartCavaIfProfileChanged(oldProfile)
    }

    readonly property int _cavaBars: {
        const compact = ShellSettings.barCompact
        if (_visualizerLowPowerOnly)
            return ShellSettings.mediaVisualizerPreset === "smooth" ? 10
                 : ShellSettings.mediaVisualizerPreset === "eco"    ? 6
                 :                                                     8
        if (ShellSettings.mediaVisualizerStyle === "pulse")
            return ShellSettings.mediaVisualizerPreset === "smooth" ? (compact ? 12 : 14)
                 : ShellSettings.mediaVisualizerPreset === "eco"    ? (compact ? 6 : 8)
                 :                                                     (compact ? 8 : 10)
        if (ShellSettings.mediaVisualizerStyle === "bars")
            return ShellSettings.mediaVisualizerPreset === "smooth" ? (compact ? 14 : 18)
                 : ShellSettings.mediaVisualizerPreset === "eco"    ? (compact ? 8 : 10)
                 :                                                     (compact ? 11 : 14)
        switch (ShellSettings.mediaVisualizerPreset) {
        case "eco":    return compact ? 8 : 10
        case "smooth": return compact ? 18 : 22
        default:       return compact ? 12 : 16
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
    readonly property real _cavaSensitivity: {
        const base = ShellSettings.mediaVisualizerPreset === "eco" ? 120
                   : ShellSettings.mediaVisualizerPreset === "smooth" ? 165
                   : 145
        return Math.round(base * ShellSettings.mediaVisualizerIntensity)
    }
    readonly property real _cavaNoiseReduction: {
        switch (ShellSettings.mediaVisualizerPreset) {
        case "eco":    return 0.72
        case "smooth": return 0.46
        default:       return 0.58
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
        "sleep_timer = 0\n" +
        "framerate = " + _cavaFps + "\n" +
        "sensitivity = " + _cavaSensitivity + "\n" +
        "\n[input]\n" +
        "method = pipewire\n" +
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
    readonly property string _cavaCommandScript: {
        const cfg = _cavaConfigText.replace(/'/g, "'\\''")
        return "base=\"${XDG_RUNTIME_DIR:-/tmp}\"; uid=\"${UID:-$(id -u 2>/dev/null || echo user)}\"; " +
               "dir=\"$base/silere-shell-$uid\"; umask 077; mkdir -p \"$dir\" || exit 1; " +
               "tmp=$(mktemp \"$dir/cava.XXXXXX.conf\") || exit 1; " +
               "printf '%s' '" + cfg + "' > \"$tmp\" || { rm -f \"$tmp\"; exit 1; }; " +
               "cava -p \"$tmp\"; code=$?; rm -f \"$tmp\"; exit $code"
    }
    property bool _cavaRestarting: false

    function _restartCava(): void {
        if (!_cavaProc.running) return
        _cavaRestarting = true
        _cavaRestart.start()
    }

    Connections {
        target: ShellSettings
        function onMediaVisualizerPresetChanged()    { root._restartCava() }
        function onMediaVisualizerStyleChanged()     { root._restartCava() }
        function onMediaVisualizerIntensityChanged() { root._restartCava() }
        function onBarCompactChanged()               { root._restartCava() }
    }
    Timer {
        id: _cavaRestart
        interval: 80
        onTriggered: root._cavaRestarting = false
    }

    // debounce on the stop side so brief alt-tabs don't restart cava
    property bool _fsBlocked: false
    readonly property bool _fullscreenPauseWanted: ShellSettings.mediaVisualizerPauseFullscreen && ShellSettings.mediaProgress
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

    Process {
        id: _cavaProc
        command: ["bash", "-c", root._cavaCommandScript]
        running: root.cavaReady && root._visualizerClients > 0 && root.available && root.playing && !Idle.isIdle && !root._fsBlocked && !root._cavaRestarting
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
                if (result.length < 1) return
                const prev = root.barHeights
                let changed = prev.length !== result.length
                for (let i = 0; !changed && i < result.length; i++)
                    if (Math.abs(result[i] - prev[i]) > 0.02) changed = true
                if (changed) root.barHeights = result
            }
        }
        onRunningChanged: if (!running) root.barHeights = root._zeroBars
        Component.onDestruction: running = false
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
