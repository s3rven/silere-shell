pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../../../config"
import "../../../services"

Item {
    id: root

    required property ShellScreen screen

    // Width the bar can actually give us (BarContent sets this = titleAvailableWidth).
    // Caps the inner text so a crowded bar elides from the right instead of cropping
    // the centered text on both ends. Deliberately separate from the animated box
    // width, so the text size snaps to the new title rather than revealing as the box
    // resizes on every change. -1 = unset (no cap beyond the 25% screen ceiling).
    property real availableWidth: -1

    readonly property var    monitor:     Hyprland.monitorFor(root.screen)
    readonly property int    monitorWsId: monitor?.activeWorkspace?.id ?? 0
    property int             _lastWsId:      1
    property bool            _wsJustChanged: false

    onMonitorWsIdChanged: {
        if (monitorWsId > 0) {
            _wsJustChanged = true
            if (_ready) _debounce.restart()
        }
    }

    readonly property var    toplevel:     Hyprland.activeToplevel
    readonly property bool   hasClient:    toplevel !== null && toplevel !== undefined
                                           && (toplevel.workspace?.id ?? 0) === monitorWsId
    readonly property string currentTitle: toplevel?.title             ?? ""
    readonly property string currentApp:   (toplevel?.wayland?.appId
                                            || toplevel?.lastIpcObject?.class
                                            || toplevel?.lastIpcObject?.initialClass
                                            || "")

    function _clean(s: string): string {
        const raw = String(s || "").trim()
        if (!raw) return ""
        const parts = raw.split(".").filter(x => x.length > 0)
        let leaf = parts.length > 0 ? parts[parts.length - 1] : raw
        leaf = leaf.replace(/[-_]+/g, " ").replace(/\s+/g, " ").trim()
        if (!leaf) return ""

        // App ids/classes are often lower-case slugs. Keep mixed-case names as
        // provided, but make plain ids read like labels in the bar.
        if (leaf === leaf.toLowerCase() || leaf === leaf.toUpperCase()) {
            return leaf.split(" ").map(function(part) {
                return part.length <= 2
                    ? part.toUpperCase()
                    : part.charAt(0).toUpperCase() + part.slice(1).toLowerCase()
            }).join(" ")
        }
        return leaf
    }

    function _norm(s: string): string {
        return root._clean(s).toLowerCase().replace(/\s+/g, " ").trim()
    }

    property bool _ready: false
    property int  _dir:   1

    property string _shownApp:   ""
    property string _shownTitle: ""
    property real   _op:         0
    property real   _y:          0
    property real   _scale:      1.0
    property string _pendApp:    ""
    property string _pendTitle:  ""
    property bool   _shownShowApp: true
    property bool   _pendShowApp:  true
    property real   _slideD:     0
    property real   _scaleStart: 1.0
    property real   _opTarget:   1.0

    readonly property bool _titleMatchesApp: {
        const title = root._norm(_shownTitle)
        const app = root._norm(_shownApp)
        return title.length > 0 && title === app
    }

    // HTML-escape dynamic text before embedding it in the StyledText markup
    // below, window titles routinely contain &, <, >.
    function _esc(s: string): string {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }
    // color -> #AARRGGBB, the form Qt's StyledText font-color parser accepts.
    function _h2(n: real): string {
        const v = Math.max(0, Math.min(255, Math.round(n)))
        return (v < 16 ? "0" : "") + v.toString(16)
    }
    function _hex(c: color, a: real): string {
        return "#" + _h2(a * 255) + _h2(c.r * 255) + _h2(c.g * 255) + _h2(c.b * 255)
    }

    // "app · title" as one styled line: dimmed app, separator at the user's
    // dot opacity, full-strength title. Collapses to whichever single part is
    // present when the title is empty or just echoes the app; overflow is
    // elided by the Text below.
    readonly property string _formatted: {
        const appCol   = _hex(Theme.subtext, ShellSettings.windowTitleOpacity)
        const titleCol = _hex(Theme.text, ShellSettings.windowTitleOpacity)
        if (_shownShowApp && _shownApp.length > 0 && _shownTitle.length > 0 && !_titleMatchesApp) {
            const dotCol = _hex(Theme.subtext, ShellSettings.dotOpacity)
            // Drawn separator styles in Dot.qml need a text equivalent here.
            // │ (U+2502) renders as a thinner stroke than ASCII | in most fonts.
            const sep = (ShellSettings.dotStyle === "line" || ShellSettings.dotStyle === "|") ? "│"
                      : ShellSettings.dotStyle === "slash" ? "/"
                      : ShellSettings.dotStyle
            return '<font color="' + appCol   + '">' + _esc(_shownApp) + '</font> '
                 + '<font color="' + dotCol   + '">' + _esc(sep) + '</font> '
                 + '<font color="' + titleCol + '">' + _esc(_shownTitle) + '</font>'
        }
        if (_shownTitle.length > 0)
            return '<font color="' + titleCol + '">' + _esc(_shownTitle) + '</font>'
        if (_shownApp.length > 0)
            return '<font color="' + appCol + '">' + _esc(_shownApp) + '</font>'
        return ""
    }

    Component.onCompleted: {
        _wsJustChanged = false
        _shownApp   = _clean(currentApp)
        _shownTitle = currentTitle
        _shownShowApp = ShellSettings.showWindowTitleApp
        _op         = hasClient ? 1.0 : 0.0
        _ready      = true
        Qt.callLater(function() { if (monitorWsId > 0) _lastWsId = monitorWsId })
    }

    onHasClientChanged:  if (_ready) _debounce.restart()
    onCurrentAppChanged: if (_ready) _debounce.restart()
    Connections {
        target: ShellSettings
        function onShowWindowTitleAppChanged() { if (root._ready) _debounce.restart() }
    }

    onCurrentTitleChanged: {
        if (!_ready || _debounce.running || _seq.running) return
        root._shownTitle = currentTitle
    }

    Timer {
        id: _debounce
        interval: 20
        onTriggered: {
            const isWsSwitch = root._wsJustChanged && root.monitorWsId !== root._lastWsId
            root._wsJustChanged = false

            root._dir = isWsSwitch ? (root.monitorWsId > root._lastWsId ? 1 : -1) : 1
            if (root.monitorWsId > 0) root._lastWsId = root.monitorWsId

            root._slideD     = isWsSwitch ? 5 : 0
            root._scaleStart = isWsSwitch ? 1.0 : 0.985
            root._opTarget   = root.hasClient ? 1.0 : 0.0
            root._pendApp    = root._clean(root.currentApp)
            root._pendTitle  = root.currentTitle
            root._pendShowApp = ShellSettings.showWindowTitleApp

            _yOut.to     = -root._slideD * root._dir
            _scaleOut.to = root._scaleStart
            _opIn.to     = root._opTarget

            _seq.restart()
        }
    }

    SequentialAnimation {
        id: _seq

        ParallelAnimation {
            NumberAnimation {                 target: root; property: "_op";    to: 0; duration: Motion.ms(90);  easing.type: Easing.InCubic  }
            NumberAnimation { id: _yOut;      target: root; property: "_y";            duration: Motion.ms(115); easing.type: Easing.OutCubic }
            NumberAnimation { id: _scaleOut;  target: root; property: "_scale";        duration: Motion.ms(105); easing.type: Easing.OutCubic }
        }
        ScriptAction {
            script: {
                root._shownApp   = root._pendApp
                root._shownTitle = root._pendTitle
                root._shownShowApp = root._pendShowApp
                root._y     = root._slideD * root._dir
                root._scale = root._scaleStart
            }
        }
        ParallelAnimation {
            NumberAnimation { id: _opIn; target: root; property: "_op";              duration: Motion.ms(145); easing.type: Easing.OutCubic }
            NumberAnimation {            target: root; property: "_y";     to: 0;     duration: Motion.ms(170); easing.type: Easing.OutQuart }
            NumberAnimation {            target: root; property: "_scale"; to: 1.0;   duration: Motion.ms(160); easing.type: Easing.OutCubic }
        }
        // Title-only changes that land mid-swap are dropped by the guard in
        // onCurrentTitleChanged (apps often set the real title a beat after
        // mapping); sync silently like the live-retitle path so the bar never
        // sits on a stale title after a fast switch.
        ScriptAction {
            script: if (!_debounce.running && root._shownTitle !== root.currentTitle)
                root._shownTitle = root.currentTitle
        }
    }

    // No Behavior here: the text content snaps, so the box must snap with it
    // in the same frame. Animating the box after the text changed left the new
    // title clipped at both ends (no ellipsis) while the box caught up; in the
    // animated swap path the snap happens while the text is faded out anyway.
    implicitWidth:  Math.ceil(content.implicitWidth)
    implicitHeight: parent ? parent.height : ShellSettings.barHeight

    Item {
        anchors.fill: parent
        clip: true

        Text {
            id: content
            x: Math.round((parent.width - width) / 2)
            anchors.verticalCenter:       parent.verticalCenter
            anchors.verticalCenterOffset: root._y
            opacity:         root._op
            visible:         root._op > 0
            scale:           root._scale
            transformOrigin: Item.Center

            text:           root._formatted
            textFormat:     Text.StyledText
            font.family:    Settings.font
            font.pixelSize: Settings.fontSize
            renderType:     Text.NativeRendering
            elide:          Text.ElideRight
            // Cap at 25% of the screen, and at the width the bar actually gave us, so a
            // crowded bar elides from the right instead of cropping the centered text on
            // both ends. Uses availableWidth (which doesn't animate during a title swap)
            // rather than the animated box width, so the text snaps to the new title.
            width:          Math.ceil(Math.min(implicitWidth,
                                     root.availableWidth >= 0 ? root.availableWidth : implicitWidth,
                                     Math.round(root.screen.width * 0.25)))
        }
    }
}
