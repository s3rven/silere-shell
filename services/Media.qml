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
    Connections {
        target: MenuState
        function onOpenChanged() { if (MenuState.open) root._reanchor() }
    }
    Timer {
        interval: 500; repeat: true
        running: root.playing && MenuState.open
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

    readonly property string label:
        (ShellSettings.mediaWidgetFormat === "artist-title" && artist.length > 0 && title.length > 0)
            ? artist + " - " + title
            : (title.length > 0 ? title : artist)

    property var barHeights: [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
    readonly property bool cavaReady: SystemTools.hasCava && SystemTools.hasCavaConfig
                                && ShellSettings.mediaProgress

    Process {
        id: _cavaProc
        command: ["bash", "-c",
            "config=${XDG_CONFIG_HOME:-$HOME/.config}; exec cava -p \"$config/cava/silere-shell.conf\""]
        running: root.cavaReady && root.available && root.playing && !Idle.isIdle
        stdout: SplitParser {
            onRead: line => {
                const parts = line.split(";")
                const result = []
                for (let i = 0; i < parts.length; i++) {
                    if (parts[i].length === 0) continue
                    const value = Number(parts[i])
                    if (isNaN(value)) continue
                    // Store normalized 0-1; canvas scales to actual px at paint time.
                    // Divide by ascii_max_range (12); works gracefully at any bar count.
                    result.push(Math.pow(value / 12, 1.3))
                }
                if (result.length < 1) return
                const prev = root.barHeights
                let changed = prev.length !== result.length
                for (let i = 0; !changed && i < result.length; i++)
                    if (Math.abs(result[i] - prev[i]) > 0.02) changed = true
                if (changed) root.barHeights = result
            }
        }
        onRunningChanged: if (!running) root.barHeights = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
        Component.onDestruction: running = false
    }

    function togglePlay(): void {
        if (!player || !player.canTogglePlaying) return
        player.togglePlaying()
    }

    function next(): void {
        if (!player || !player.canGoNext) return
        player.next()
    }

    function previous(): void {
        if (!player || !player.canGoPrevious) return
        player.previous()
    }
}
