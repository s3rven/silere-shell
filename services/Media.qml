pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "../config"

Singleton {
    id: root

    readonly property int maxIdentityChars: 512
    readonly property int maxMetadataChars: 2048
    readonly property int maxArtSourceChars: 4096

    function finiteNonnegative(value): real {
        const number = Number(value)
        return isFinite(number) && number > 0 ? number : 0
    }

    // any process on the bus can set artUrl, and Qt loads a remote one on the pixmap
    // thread, where a QNetworkAccessManager first use has crashed the shell in OpenSSL
    function artSource(raw): string {
        const value = String(raw ?? "").trim()
        if (value.length === 0 || value.length > root.maxArtSourceChars) return ""
        if (/[\u0000-\u001F\u007F]/.test(value)) return ""
        if (/^https:\/\//i.test(value))
            return ShellSettings.mediaRemoteArt ? value : ""
        if (/^http:\/\//i.test(value)) return ""
        return IconResolver.safeLocalSource(value)
    }

    // ephemeral by design: players come and go, so a pinned choice is dropped the moment its player leaves the bus
    property string preferredPlayer: ""

    readonly property var playerList: {
        const out = []
        const players = Mpris.players.values ?? []
        for (let i = 0; i < players.length; i++)
            if (players[i]) out.push(players[i])
        // playerctld only mirrors the real players; keep it solely when nothing else is on the bus
        const real = out.filter(p => (p.dbusName || "").indexOf("playerctld") < 0)
        const pool = real.length > 0 ? real : out
        // browsers leave the MPRIS service registered after the tab goes, stopped and with no
        // metadata: counting those offers a switcher that cycles onto an empty card. Stopped
        // only - a paused player is one the user may well want to come back to
        const live = pool.filter(p => p.playbackState !== MprisPlaybackState.Stopped)
        return live.length > 0 ? live : pool
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
    readonly property real _rawLength:  (player && player.lengthSupported)
        ? root.finiteNonnegative(player.length) : 0
    readonly property bool lengthKnown: _rawLength > 0 && _rawLength <= 86400
    // only the sentinel means endless; a browser reports 0 between videos and through an
    // ad break, and calling that live claims something about the track instead of admitting
    // the length is not known yet
    readonly property bool endless:     _rawLength > 86400
    readonly property real length:      lengthKnown ? _rawLength : 0
    readonly property bool canSeek:     player ? player.canSeek : false
    // position still ticks without a length; only the ratio and the seek bar need one
    readonly property bool hasPosition: player !== null && player.positionSupported

    property real  _anchorPos:  0
    property real  _anchorMs:   0
    property real  positionNow: 0
    readonly property real positionRatio: length > 0 ? Math.max(0, Math.min(1, positionNow / length)) : 0
    function positionDemand(homeActive: bool, barVisible: bool, overview: bool): bool {
        return homeActive || (barVisible && !overview)
    }
    readonly property bool positionVisible: root.positionDemand(
        MenuState.homeActive,
        ShellSettings.barShowMedia && root.shown && ShellSettings.mediaWidgetHelper,
        OverviewState.active)

    function _reanchor(): void {
        root._anchorPos = (player && player.positionSupported)
            ? root.finiteNonnegative(player.position) : 0
        root._anchorMs  = Date.now()
        _recompute()
    }
    function extrapolatedPosition(start: real, elapsedMs: real, isPlaying: bool,
            rate: real, duration: real): real {
        const speed = isFinite(rate) ? rate : 1
        const progress = root.finiteNonnegative(start)
            + (isPlaying ? root.finiteNonnegative(elapsedMs) * speed / 1000 : 0)
        return duration > 0 ? Math.max(0, Math.min(duration, progress)) : Math.max(0, progress)
    }

    function _recompute(): void {
        if (!player) { positionNow = 0; return }
        positionNow = root.extrapolatedPosition(root._anchorPos,
            Date.now() - root._anchorMs, root.playing, player.rate, root.length)
    }
    function seekToRatio(r: real): void {
        if (!player || !canSeek || length <= 0) return
        const ratio = Number(r)
        if (!isFinite(ratio)) return
        const target = Math.max(0, Math.min(1, ratio)) * length
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
        function onRateChanged() { root._reanchor() }
    }
    onPositionVisibleChanged: if (positionVisible) root._reanchor()
    Timer {
        interval: 500; repeat: true
        running: root.playing && root.hasPosition && !Idle.isQuiet
            && root.positionVisible
        onTriggered: root._recompute()
    }

    onPlayerChanged: _reanchor()
    readonly property string artist: SafeText.singleLineText(
        player ? player.trackArtist : "", root.maxMetadataChars)
    readonly property string title: SafeText.singleLineText(
        player ? player.trackTitle : "", root.maxMetadataChars)
    readonly property string identity: SafeText.singleLineText(
        player ? player.identity : "", root.maxIdentityChars)
    readonly property string desktopEntry: SafeText.singleLineText(
        player ? player.desktopEntry : "", root.maxIdentityChars)

    function privacyPlaceholderSource(value): string {
        const clean = SafeText.singleLineText(value, root.maxMetadataChars)
        const match = clean.match(/^(.+?)\s+is playing media$/i)
        return match ? match[1].trim() : ""
    }

    function metadataIsPrivacyProtected(titleValue, artistValue, urlValue,
            identityValue, desktopEntryValue, dbusNameValue): bool {
        const placeholderSource = root.privacyPlaceholderSource(titleValue)
        if (placeholderSource.length === 0
                || String(artistValue || "").trim().length > 0
                || String(urlValue || "").trim().length > 0)
            return false

        const source = [placeholderSource, identityValue, desktopEntryValue, dbusNameValue]
            .join(" ").toLowerCase()
        return /(firefox|zen|librewolf|floorp|waterfox|chrome|chromium|brave|edge|opera|vivaldi|thorium)/.test(source)
    }

    readonly property string trackUrl: {
        const metadata = player ? player.metadata : null
        return SafeText.singleLineText(metadata ? metadata["xesam:url"] : "",
            root.maxArtSourceChars)
    }
    readonly property bool metadataPrivacyProtected: root.metadataIsPrivacyProtected(
        title, artist, trackUrl, identity, desktopEntry, player ? player.dbusName : "")
    readonly property string sourceLabel: {
        const placeholder = root.metadataPrivacyProtected
            ? root.privacyPlaceholderSource(title) : ""
        if (placeholder.length > 0) return placeholder
        if (identity.length > 0) return identity
        if (desktopEntry.length > 0) return desktopEntry
        return ""
    }
    readonly property string displayTitle: root.metadataPrivacyProtected
        ? "Media details hidden" : title
    readonly property string displayArtist: root.metadataPrivacyProtected
        ? (sourceLabel.length > 0 ? "Private tab in " + sourceLabel : "Private tab")
        : artist

    // Spotify's Linux client reports an open.spotify.com/image link that 404s
    function normalizedArtUrl(raw): string {
        return String(raw ?? "")
            .replace("https://open.spotify.com/image/", "https://i.scdn.co/image/")
    }

    // i.scdn.co spells the edge length into the id prefix and publishes all three sizes
    // for every cover; clients that hand over the 64px form leave the tile a blur
    function upscaledArtUrl(raw): string {
        const match = String(raw ?? "").match(
            /^(https:\/\/i\.scdn\.co\/image\/)ab67616d(?:00004851|00001e02)([0-9a-f]{8,})$/i)
        return match ? match[1] + "ab67616d0000b273" + match[2] : ""
    }

    // the directory holding a locally played track, for the covers that sit beside it
    function trackDirectory(raw): string {
        const value = String(raw ?? "")
        if (value.slice(0, 8) !== "file:///") return ""
        let path = ""
        try { path = decodeURIComponent(value.slice(7)) } catch (error) { return "" }
        const cut = path.lastIndexOf("/")
        return cut > 0 && path.indexOf("/../") < 0 ? path.slice(0, cut) : ""
    }

    readonly property var sidecarArtNames: [
        "cover.jpg", "cover.png", "Cover.jpg",
        "folder.jpg", "folder.png", "Folder.jpg",
        "front.jpg", "AlbumArt.jpg"
    ]

    // remote art is allowed on purpose where notification icons are denied: mpris art genuinely is a url
    readonly property var artCandidates: {
        const out = []
        function offer(value) {
            const source = root.artSource(value)
            if (source.length > 0 && out.indexOf(source) < 0) out.push(source)
        }
        const reported = root.normalizedArtUrl(root.player ? root.player.trackArtUrl : "")
        offer(root.upscaledArtUrl(reported))
        offer(reported)
        const directory = root.trackDirectory(root.trackUrl)
        if (directory.length > 0)
            for (let i = 0; i < root.sidecarArtNames.length; i++)
                offer(directory + "/" + root.sidecarArtNames[i])
        return out
    }

    readonly property string artKey: root.artCandidates.join("\u0000")
    property int _artCandidate: 0
    onArtKeyChanged: root._artCandidate = 0

    readonly property string artUrl: {
        const candidates = root.artCandidates
        if (candidates.length === 0) return ""
        return candidates[Math.min(root._artCandidate, candidates.length - 1)]
    }

    // a view reports the load it could not finish; without this a cover url that 404s
    // retries itself forever while a readable cover sits unopened beside the track
    function artFailed(url: string): void {
        if (url !== root.artUrl) return
        if (root._artCandidate + 1 < root.artCandidates.length) root._artCandidate++
    }
    function retryArt(): void { root._artCandidate = 0 }

    property string stableArtUrl: ""
    function _syncStableArt(): void {
        if (root.artUrl.length > 0) {
            _staleArtClear.stop()
            root.stableArtUrl = root.artUrl
        } else if (!root.available) {
            _staleArtClear.stop()
            root.stableArtUrl = ""
        } else if (root.stableArtUrl.length > 0) {
            // MPRIS properties often arrive in separate D-Bus updates. Keep the
            // old cover briefly, but do not show it forever for a track with no art.
            _staleArtClear.restart()
        }
    }
    Timer {
        id: _staleArtClear
        interval: 750
        onTriggered: if (root.artUrl.length === 0) root.stableArtUrl = ""
    }
    onArtUrlChanged: _syncStableArt()
    onTitleChanged: { _reanchor(); _syncStableArt() }

    readonly property string playerName:
        !player              ? "" :
        desktopEntry.length > 0 ? desktopEntry :
        identity.length > 0     ? identity :
        SafeText.singleLineText(player.dbusName, root.maxIdentityChars)

    readonly property string label: {
        if (root.metadataPrivacyProtected)
            return sourceLabel.length > 0 ? sourceLabel + " · private media" : "Private media"
        if (ShellSettings.mediaWidgetFormat === "artist-title" && artist.length > 0 && title.length > 0)
            return SafeText.singleLineText(artist + " - " + title, root.maxMetadataChars)
        if (title.length > 0) return title
        if (artist.length > 0) return artist
        if (identity.length > 0) return identity
        if (desktopEntry.length > 0) return desktopEntry
        return player ? "Media" : ""
    }

    property var barHeights: []
    readonly property bool cavaAvailable: SystemTools.hasCava && _cavaConfigPath.length > 0
    readonly property bool cavaReady: cavaAvailable && ShellSettings.mediaProgress
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

    // denser shapes get fewer bars and a lower frame rate; the derived form never once clamped
    readonly property var _vizProfiles: ({
        wave:     { eco: { bars: 10, fps: 26 }, balanced: { bars: 16, fps: 38 }, smooth: { bars: 22, fps: 50 } },
        bars:     { eco: { bars: 10, fps: 23 }, balanced: { bars: 14, fps: 35 }, smooth: { bars: 18, fps: 47 } },
        pulse:    { eco: { bars:  8, fps: 20 }, balanced: { bars: 10, fps: 32 }, smooth: { bars: 14, fps: 44 } },
        lowPower: { eco: { bars:  6, fps: 18 }, balanced: { bars:  8, fps: 26 }, smooth: { bars: 10, fps: 34 } }
    })

    function vizProfile(style: string, preset: string, lowPower: bool): var {
        const row = root._vizProfiles[lowPower ? "lowPower" : style] ?? root._vizProfiles.wave
        return row[preset] ?? row.balanced
    }

    // the bar's row band caps the underline's height, so density is the only lever on the wave's slope
    readonly property bool _vizWide: ShellSettings.mediaVisualizerPosition === "underline"
    function vizBarCount(base: int, lowPower: bool): int {
        return Math.min(96, Math.round(base * (root._vizWide && !lowPower ? 4 : 1)))
    }

    // what the active bar runs at, so the settings hint does not have to restate the table
    readonly property string visualizerLabel: {
        const p = root.vizProfile(ShellSettings.mediaVisualizerStyle,
            ShellSettings.mediaVisualizerPreset, false)
        return root.vizBarCount(p.bars, false) + " bars at " + p.fps + " fps"
    }

    readonly property var _vizActive: root.vizProfile(
        ShellSettings.mediaVisualizerStyle, ShellSettings.mediaVisualizerPreset,
        root._visualizerLowPowerOnly)
    readonly property int _cavaBars: root.vizBarCount(root._vizActive.bars,
        root._visualizerLowPowerOnly)
    readonly property int _cavaFps:  root._vizActive.fps
    readonly property real _cavaNoiseReduction: {
        switch (ShellSettings.mediaVisualizerPreset) {
        // Cava accepts a float from 0 (fast/noisy) to 1 (slow/smooth).
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
    readonly property string _cavaConfigPath: XdgPaths.runtimeDir.length > 0
        ? XdgPaths.runtimeDir + "/silere-shell-cava-" + Quickshell.processId + ".conf"
        : ""
    property bool _cavaConfigReady: false
    property string _writtenCavaProfileKey: ""
    readonly property int _cavaReloadSignal: 10
    property bool _sweptStaleProfiles: false

    // quickshell exits hard on SIGTERM, so the profile outlives the process that wrote it
    function _sweepStaleCavaProfiles(): void {
        const runtime = XdgPaths.runtimeDir
        if (root._sweptStaleProfiles || runtime.length === 0) return
        root._sweptStaleProfiles = true
        Quickshell.execDetached(["bash", "-c",
            'for f in "$1"/silere-shell-cava-*.conf; do ' +
            '[ -e "$f" ] || continue; p=${f##*-}; p=${p%.conf}; ' +
            'case $p in ""|*[!0-9]*) continue;; esac; ' +
            '[ "$p" = "$2" ] && continue; ' +
            'kill -0 "$p" 2>/dev/null || rm -f -- "$f"; done',
            "bash", runtime, String(Quickshell.processId)])
    }

    // blocking writes let save failure veto readiness before cava starts
    function _writeCavaConfig(): void {
        if (root._cavaConfigPath.length === 0) {
            root._cavaConfigReady = false
            return
        }
        root._sweepStaleCavaProfiles()
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
        target: FullscreenState
        enabled: root._fullscreenPauseWanted
        function onActiveChanged() {
            if (FullscreenState.active) _fsBlockTimer.restart()
            else { _fsBlockTimer.stop(); root._fsBlocked = false }
        }
    }
    Timer { id: _fsBlockTimer; interval: 2000; onTriggered: root._fsBlocked = true }
    on_FullscreenPauseWantedChanged: {
        if (!root._fullscreenPauseWanted) {
            _fsBlockTimer.stop()
            root._fsBlocked = false
        } else if (FullscreenState.active) {
            _fsBlockTimer.restart()
        }
    }

    SupervisedProcess {
        id: _cavaProc
        command: ["cava", "-p", root._cavaConfigPath]
        superviseWhen: root._cavaConfigReady && root.cavaReady
            && (root._visualizerClients > 0 || _visualizerStopGrace.running)
            && root.available && root.playing && !Idle.isQuiet && !root._fsBlocked
        restartDelay: 1000
        maxRestartDelay: 30000
        stableAfter: 20000
        // a clean exit 1 is cava refusing to start - an input method this build lacks,
        // which respawning cannot fix; the playback gate retries when it next cycles
        giveUpCodes: [1]
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
