pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../../config"
import "../../../services"
import "../../common"

Item {
    id: root

    required property ShellScreen screen

    property bool compact: false
    property bool barActive: true
    readonly property int _horizontalPadding: Metrics.pillPadFor(compact)
    readonly property string _zone: ShellSettings.barWidgetLocate("windowTitle").zone
    readonly property bool _titleVisible: ShellSettings.showWindowTitle && root.hasClient
        && (root.currentTitle.length > 0
            || (ShellSettings.showWindowTitleApp && root.currentApp.length > 0))

    readonly property bool layoutVisible: root._titleVisible || root._op > 0.001
        || root.implicitWidth > 0.5 || _debounce.running || _seq.running
    // the width lags the fade both ways, so a divider keyed off it marks an empty slot;
    // a crossfade between titles holds this up, or each focus change blinks the divider
    readonly property bool contentVisible: root._displayText.length > 0
        && (root._op > 0.001 || (_seq.running && root._pendVisible))

    Accessible.role: Accessible.StaticText
    Accessible.name: root._spokenText.length > 0
        ? "Active window, " + root._spokenText : ""

    // a zone widget displaces its neighbours, so the cap tightens with the rest of the bar
    property real widthBudget: -1
    readonly property real   _widthCap: {
        const span = root.widthBudget > 0 ? root.widthBudget
            : (root.screen ? root.screen.width : 0)
        if (span <= 0) return Infinity
        return Math.min(Metrics.windowTitleWidthFor(root.compact),
            Math.round(span * (root.compact ? 0.18 : 0.25)))
    }

    readonly property string monitorName: Compositor.monitorName(root.screen)
    readonly property int    monitorWsId: Compositor.activeWorkspaceId(root.monitorName)
    property int             _lastWsId:      1
    property bool            _wsJustChanged: false

    onMonitorWsIdChanged: {
        if (monitorWsId > 0) {
            _wsJustChanged = true
            root._queueTransition()
        }
    }

    readonly property var    toplevel:     Compositor.activeToplevel
    readonly property string clientOutput: toplevel ? String(toplevel.output || "") : ""
    readonly property bool   hasClient:    toplevel !== null && toplevel !== undefined
                                           && (clientOutput === monitorName
                                               || (clientOutput.length === 0
                                                   && Compositor.focusedMonitor === monitorName))
    readonly property string currentRef:   hasClient ? String(toplevel?.ref ?? "") : ""
    readonly property string rawTitle:     hasClient ? (toplevel?.title ?? "") : ""
    readonly property string currentApp:   hasClient
        ? String(toplevel?.appId || toplevel?.cls || toplevel?.initialClass || "") : ""

    function _matchKey(s: string): string {
        return String(s || "").toLowerCase()
            .replace(/[‐‑‒–—―]/g, "-").replace(/\s+/g, " ").trim()
    }

    readonly property bool _mediaSharesZone: {
        const media = ShellSettings.barWidgetLocate("media")
        return root._zone.length > 0 && media.zone === root._zone
    }
    readonly property bool _mediaCandidate: root._mediaSharesZone
        && ShellSettings.barShowMedia && Media.shown
    readonly property bool _mediaTitleMatch: {
        if (!root._mediaCandidate) return false
        const windowTitle = root._matchKey(root.rawTitle)
        const mediaTitle = root._matchKey(Media.title)
        return mediaTitle.length >= 12 && windowTitle.indexOf(mediaTitle) !== -1
    }
    property bool _mediaMatchHeld: false
    property string _mediaMatchRef: ""
    readonly property bool _mediaOwnsTitle: root._mediaTitleMatch
        || (root._mediaCandidate && root._mediaMatchHeld
            && root._mediaMatchRef === root.currentRef)
    readonly property string currentTitle: root._mediaOwnsTitle ? "" : root.rawTitle

    function _syncMediaOwnership(): void {
        if (root._mediaTitleMatch) {
            _mediaRelease.stop()
            root._mediaMatchHeld = true
            root._mediaMatchRef = root.currentRef
            return
        }
        if (!root._mediaCandidate || root._mediaMatchRef !== root.currentRef) {
            _mediaRelease.stop()
            root._mediaMatchHeld = false
            return
        }
        if (root._mediaMatchHeld) _mediaRelease.restart()
    }

    on_MediaTitleMatchChanged: root._syncMediaOwnership()
    on_MediaCandidateChanged: root._syncMediaOwnership()

    Timer {
        id: _mediaRelease
        interval: 500
        onTriggered: root._mediaMatchHeld = false
    }

    function _clean(s: string): string {
        const raw = String(s || "").trim()
        if (!raw) return ""
        const parts = raw.split(".").filter(x => x.length > 0)
        let leaf = parts.length > 0 ? parts[parts.length - 1] : raw
        leaf = leaf.replace(/[-_]+/g, " ").replace(/\s+/g, " ").trim()
        if (!leaf) return ""

        if (leaf === leaf.toLowerCase() || leaf === leaf.toUpperCase()) {
            return leaf.split(" ").map(function(part) {
                return part.length <= 2
                    ? part.toUpperCase()
                    : part.charAt(0).toUpperCase() + part.slice(1).toLowerCase()
            }).join(" ")
        }
        return leaf
    }

    // the desktop entry names the app: an id's last segment can be a word like "desktop"
    function _appName(app: string): string {
        if (!ShellSettings.showWindowTitleApp || app.length === 0) return root._clean(app)
        const entry = DesktopEntries.heuristicLookup(app)
        // "Spotify (Launcher)": a packaging note, not part of the app's name
        const name = entry ? SafeText.singleLineText(entry.name || "", 64)
            .replace(/\s*\([^()]*\)$/, "") : ""
        return name.length > 0 ? name : root._clean(app)
    }

    // visible labels, not reverse-domain ids: _clean() would leave "notes.md" as "MD"
    function _labelKey(s: string): string {
        return String(s || "").toLowerCase()
            .replace(/[‐‑‒–—―]/g, "-")
            .replace(/[._-]+/g, " ").replace(/\s+/g, " ").trim()
    }

    function _looksLikeAppLabel(label: string, app: string): bool {
        const labelKey = root._labelKey(label)
        const appKey = root._labelKey(app)
        if (labelKey.length === 0 || appKey.length === 0) return false
        if (labelKey === appKey) return true
        if (appKey.length < 5 || !labelKey.endsWith(" " + appKey)) return false
        return labelKey.split(" ").length <= appKey.split(" ").length + 1
    }

    function _withoutAppSuffix(title: string, app: string): string {
        const raw = String(title || "").trim()
        const appKey = root._labelKey(app)
        if (raw.length === 0 || appKey.length === 0) return raw

        // "document — App" is the common shape; the app half is already drawn
        const separators = [" — ", " – ", " - ", " | ", " · "]
        let cut = -1
        let separatorLength = 0
        for (let i = 0; i < separators.length; i++) {
            const at = raw.lastIndexOf(separators[i])
            if (at > cut) {
                cut = at
                separatorLength = separators[i].length
            }
        }
        if (cut <= 0) return raw

        const suffix = raw.slice(cut + separatorLength)
        if (!root._looksLikeAppLabel(suffix, app)) return raw
        const useful = raw.slice(0, cut).trim()
        return useful.length > 0 ? useful : raw
    }

    property bool _ready: false
    property int  _dir:   1

    property string _shownApp:   ""
    property string _shownTitle: ""
    property string _shownRef:   ""
    property bool   _shownVisible: false
    property real   _op:         0
    property real   _y:          0
    property string _pendApp:    ""
    property string _pendTitle:  ""
    property string _pendRef:    ""
    property bool   _pendVisible: false
    property bool   _shownShowApp: true
    property bool   _pendShowApp:  true
    property real   _slideD:     0
    property real   _opTarget:   1.0
    property int    _outMs:      0
    property int    _inMs:       0
    property bool   _queued:     false

    function _settleCurrent(): void {
        _debounce.stop()
        _seq.stop()
        _wsJustChanged = false
        if (monitorWsId > 0) _lastWsId = monitorWsId
        _shownApp = _appName(currentApp)
        _shownTitle = currentTitle
        _shownRef = currentRef
        _shownVisible = _titleVisible
        _shownShowApp = ShellSettings.showWindowTitleApp
        _op = _titleVisible ? 1.0 : 0.0
        _y = 0
        _queued = false
    }

    function _matchesCurrent(): bool {
        return root._shownApp === root._appName(root.currentApp)
            && root._shownTitle === root.currentTitle
            && root._shownRef === root.currentRef
            && root._shownVisible === root._titleVisible
            && root._shownShowApp === ShellSettings.showWindowTitleApp
            && Math.abs(root._op - (root._titleVisible ? 1.0 : 0.0)) < 0.001
    }

    function _capturePending(): void {
        root._pendApp = root._appName(root.currentApp)
        root._pendTitle = root.currentTitle
        root._pendRef = root.currentRef
        root._pendVisible = root._titleVisible
        root._pendShowApp = ShellSettings.showWindowTitleApp
    }

    function _queueTransition(): void {
        if (!root._ready) return
        if (!root.barActive || Idle.isIdle) {
            root._settleCurrent()
            return
        }
        if (ShellSettings.reduceMotion) {
            root._settleCurrent()
            return
        }
        if (!root._wsJustChanged && root._matchesCurrent()) return
        if (_seq.running) {
            root._capturePending()
            root._queued = true
            return
        }
        if (!root._titleVisible && root._op <= 0.001 && root.implicitWidth <= 0.5) {
            root._settleCurrent()
            return
        }
        _debounce.restart()
    }

    readonly property bool _titleMatchesApp: {
        return root._looksLikeAppLabel(root._displayTitle, root._shownApp)
    }

    // HTML-escape dynamic text before StyledText markup; titles routinely contain &, <, >
    function _esc(s: string): string {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }
    // color -> #AARRGGBB, the form Qt's StyledText font-color parser accepts
    function _h2(n: real): string {
        const v = Math.max(0, Math.min(255, Math.round(n)))
        return (v < 16 ? "0" : "") + v.toString(16)
    }
    function _hex(c: color, a: real): string {
        return "#" + _h2(a * 255) + _h2(c.r * 255) + _h2(c.g * 255) + _h2(c.b * 255)
    }

    readonly property string _displayTitle: root._shownShowApp
        ? root._withoutAppSuffix(root._shownTitle, root._shownApp)
        : root._shownTitle
    readonly property bool _showAppAndTitle: root._shownShowApp
        && root._shownApp.length > 0 && root._displayTitle.length > 0
        && !root._titleMatchesApp
    readonly property string _displayText: !root._shownVisible ? ""
        : root._showAppAndTitle
            ? root._shownApp + " " + ShellSettings.dotTextGlyph + " " + root._displayTitle
            : root._displayTitle.length > 0 ? root._displayTitle
            : root._shownShowApp ? root._shownApp : ""
    readonly property string _spokenText: !root._shownVisible ? ""
        : root._showAppAndTitle
            ? root._shownApp + ", " + root._displayTitle
            : root._displayTitle.length > 0 ? root._displayTitle
            : root._shownShowApp ? root._shownApp : ""
    readonly property string _formatted: {
        if (root._displayText.length === 0) return ""
        const appCol   = _hex(Theme.subtext, 1.0)
        const titleCol = _hex(Theme.text, 1.0)
        if (root._showAppAndTitle) {
            const dotCol = _hex(Theme.barSeparator, Theme.barSeparator.a)
            return '<font color="' + appCol   + '">' + _esc(_shownApp) + '</font> '
                 + '<font color="' + dotCol   + '">' + _esc(ShellSettings.dotTextGlyph) + '</font> '
                 + '<font color="' + titleCol + '">' + _esc(_displayTitle) + '</font>'
        }
        if (_displayTitle.length > 0)
            return '<font color="' + titleCol + '">' + _esc(_displayTitle) + '</font>'
        if (_shownApp.length > 0)
            return '<font color="' + appCol + '">' + _esc(_shownApp) + '</font>'
        return ""
    }

    Component.onCompleted: {
        root._syncMediaOwnership()
        _wsJustChanged = false
        _shownApp   = _appName(currentApp)
        _shownTitle = currentTitle
        _shownRef   = currentRef
        _shownVisible = _titleVisible
        _shownShowApp = ShellSettings.showWindowTitleApp
        _op         = _titleVisible ? 1.0 : 0.0
        _ready      = true
        Qt.callLater(function() {
            if (!root) return
            if (root.monitorWsId > 0) root._lastWsId = root.monitorWsId
        })
    }

    onHasClientChanged:  root._queueTransition()
    onCurrentRefChanged: {
        root._syncMediaOwnership()
        root._queueTransition()
    }
    onCurrentAppChanged: root._queueTransition()
    onCurrentTitleChanged: root._queueTransition()
    // the handlers above run before this binding is recomputed, so a queue driven only by
    // them settles on a stale invisible state and never hears that a title arrived
    on_TitleVisibleChanged: root._queueTransition()
    onBarActiveChanged: {
        if (!root._ready) return
        if (root.barActive) root._queueTransition()
        else root._settleCurrent()
    }
    Connections {
        target: ShellSettings
        function onShowWindowTitleChanged() { root._queueTransition() }
        function onShowWindowTitleAppChanged() { root._queueTransition() }
        function onReduceMotionChanged() {
            if (ShellSettings.reduceMotion) root._settleCurrent()
        }
    }

    // entries land after startup, so a title shown before then carries the id's name
    Connections {
        target: ShellSettings.showWindowTitleApp ? DesktopEntries : null
        function onApplicationsChanged() { root._queueTransition() }
    }

    Connections {
        target: Idle
        function onIsIdleChanged() {
            if (Idle.isIdle) {
                root._settleCurrent()
            } else {
                root._queueTransition()
            }
        }
    }

    Timer {
        id: _debounce
        interval: 20
        onTriggered: {
            const isWsSwitch = root._wsJustChanged && root.monitorWsId !== root._lastWsId
            root._wsJustChanged = false
            root._capturePending()

            const identityChanged = root._shownRef !== root._pendRef
                || root._shownApp !== root._pendApp
                || root._shownVisible !== root._pendVisible
                || root._shownShowApp !== root._pendShowApp
            const fullTransition = isWsSwitch || identityChanged

            root._dir = isWsSwitch ? (root.monitorWsId > root._lastWsId ? 1 : -1) : 1
            if (root.monitorWsId > 0) root._lastWsId = root.monitorWsId

            if (!fullTransition) {
                root._shownTitle = root._pendTitle
                root._op = root._pendVisible ? 1.0 : 0.0
                return
            }

            root._slideD     = isWsSwitch ? 5 : 0
            root._opTarget   = root._pendVisible ? 1.0 : 0.0
            root._outMs      = root._op <= 0.001 ? 0 : 80
            root._inMs       = !root._pendVisible ? 0 : 135

            _yOut.to     = -root._slideD * root._dir
            _opIn.to     = root._opTarget

            _seq.restart()
        }
    }

    SequentialAnimation {
        id: _seq

        ParallelAnimation {
            NumberAnimation {                 target: root; property: "_op";    to: 0; duration: Motion.ms(root._outMs); easing.type: Easing.InCubic }
            NumberAnimation { id: _yOut;      target: root; property: "_y";            duration: Motion.ms(root._outMs); easing.type: Easing.InCubic }
        }
        ScriptAction {
            script: {
                root._shownApp   = root._pendApp
                root._shownTitle = root._pendTitle
                root._shownRef   = root._pendRef
                root._shownVisible = root._pendVisible
                root._shownShowApp = root._pendShowApp
                root._y     = root._slideD * root._dir
            }
        }
        ParallelAnimation {
            NumberAnimation { id: _opIn; target: root; property: "_op";              duration: Motion.ms(root._inMs); easing.type: Easing.OutCubic }
            NumberAnimation {            target: root; property: "_y";     to: 0;     duration: Motion.ms(root._inMs); easing.type: Easing.OutQuart }
        }
        onFinished: {
            const again = root._queued || root._wsJustChanged || !root._matchesCurrent()
            root._queued = false
            if (again) Qt.callLater(root._queueTransition)
        }
    }

    readonly property real _contentCap: Math.max(0,
        root._widthCap - root._horizontalPadding * 2)
    TextMetrics {
        id: _textMetrics
        font.family: Settings.font
        font.pixelSize: Settings.fontSize
        text: root._displayText
    }
    readonly property real _measuredContentWidth: root._displayText.length > 0
        ? Math.ceil(Math.min(_textMetrics.advanceWidth, root._contentCap)) : 0
    readonly property real _naturalWidth: root._displayText.length > 0
        ? root._measuredContentWidth + root._horizontalPadding * 2
        : 0


    implicitWidth: root._naturalWidth
    // a zone widget shoves its neighbours when it resizes, and titles change on every
    // navigation; ease the box so the rest of the bar does not twitch with the text
    MotionBehavior on implicitWidth {
        NumberAnimation { duration: Motion.ms(110); easing.type: Easing.OutCubic }
    }
    // not parent.height: the zone's Loader takes its height from this item, so reading it back
    // collapses to zero and the clip below erases the text
    implicitHeight: ShellSettings.barHeight

    Item {
        anchors.fill: parent
        clip: true

        ShellText {
            id: content
            x: root._zone === "left" ? root._horizontalPadding
                : root._zone === "right"
                    ? Math.round(parent.width - width - root._horizontalPadding)
                    : Math.round((parent.width - width) / 2)
            anchors.verticalCenter:       parent.verticalCenter
            anchors.verticalCenterOffset: root._y
            opacity:         root._op
            visible:         root._op > 0

            text:           root._formatted
            textFormat:     Text.StyledText
            font.pixelSize: Settings.fontSize
            elide:          Text.ElideRight
            width:          Math.max(0, Math.min(
                root.width - root._horizontalPadding * 2,
                root._measuredContentWidth))
        }
    }

}
