pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"

Item {
    id: root

    property string glyph:      ""
    property string text:       ""
    property color  glyphColor: Theme.text
    property color  textColor:  Theme.subtext
    property bool   interactive: false
    property string accessibleName: ""
    property string accessibleDescription: ""
    property int    maxTextWidth: 150
    property bool   compact: ShellSettings.barCompact
    property int    horizontalPadding: Metrics.pillPadFor(compact)
    property bool   animateGlyph: true
    // opt-in cross-fade on text change; off by default — Volume/Brightness update every scroll tick and shouldn't fade-through
    property bool   animateText: false
    property bool   animateGlyphColor: true
    property int    glyphPixelSize: Settings.iconSize + 2
    // floor the text box to this string's width so value readouts (volume/brightness) don't resize on every change
    property string reserveText: ""
    readonly property real _reserveW: reserveText.length > 0 ? Math.ceil(_reserveMetrics.advanceWidth) : 0
    property bool   contentScanEnabled: false
    property color  contentScanColor: Theme.text
    property real   contentScanProgress: 0.0
    property real   contentScanWidth: 10.0
    property real   levelValue: -1.0
    property bool   levelVisible: false
    property color  levelColor: Theme.accent

    // delayed hover flag for reveal detail text (battery/network) — true only after the pointer rests hoverRevealDelay ms
    property int    hoverRevealDelay: 80
    property bool   hoverActive: false
    readonly property bool hovered: _pillHover.hovered
    readonly property bool expanded: hoverActive || activeFocus

    // opt-in press feedback: bind to a handler's pressed state, the glyph dips then springs back
    property bool   pressed: false
    property bool   _keyboardPressed: false
    readonly property bool visualPressed: pressed || _keyboardPressed

    signal activated()

    readonly property int  pillH:   24
    readonly property bool hasText: text.length > 0

    // holds recent max width so the pill doesn't jitter while scrolling; resets after `shrinkDelay` ms or immediately when text clears (e.g. network hiding SSID).
    // set shrinkDelay: 0 on hover-only pills so they snap back instead of leaving a gap.
    property int  shrinkDelay: 600
    property real _minW: 0
    // Whole px: fractional text widths put the pill (and every widget after it
    // in the bar row) on fractional pixels, which blurs NativeRendering text.
    readonly property real rowWidth: Math.ceil(row.implicitWidth)
    implicitWidth:  Math.max(rowWidth, _minW) + horizontalPadding * 2

    onRowWidthChanged: {
        if (shrinkDelay <= 0) {
            _shrinkDelay.stop()
            _minW = rowWidth
            return
        }
        if (rowWidth > _minW) _minW = rowWidth
        _shrinkDelay.restart()
    }
    onTextChanged: if (text.length === 0) { _minW = 0; _shrinkDelay.stop() }
    onShrinkDelayChanged: if (shrinkDelay <= 0) { _shrinkDelay.stop(); _minW = rowWidth }
    onVisibleChanged: if (!visible) {
        _hoverRevealTimer.stop()
        _shrinkDelay.stop()
        hoverActive = false
    }

    Timer {
        id: _shrinkDelay
        interval: root.shrinkDelay
        onTriggered: root._minW = root.rowWidth
    }

    TextMetrics {
        id: _reserveMetrics
        font.family:    Settings.font
        font.pixelSize: Settings.fontSize
        text:           root.reserveText
    }

    property bool _ready: false
    property string _shownGlyph: ""
    property string _nextGlyph:  ""

    Component.onCompleted: {
        _shownGlyph = root.glyph
        Qt.callLater(function() { _ready = true })
    }

    onGlyphChanged: {
        if (!_ready) { _shownGlyph = glyph; return }
        if (!animateGlyph || ShellSettings.reduceMotion) {
            _glyphStamp.stop()
            _shownGlyph = glyph
            _nextGlyph = glyph
            _glyphText.scale = 1.0
            return
        }
        _nextGlyph = glyph
        if (!_glyphStamp.running) _glyphStamp.start()
    }

    SequentialAnimation {
        id: _glyphStamp
        NumberAnimation { target: _glyphText; property: "scale"; to: 0.72; duration: Motion.instant; easing.type: Easing.InCubic }
        ScriptAction    { script: root._shownGlyph = root._nextGlyph }
        NumberAnimation { target: _glyphText; property: "scale"; from: 0.72; to: 1.0; duration: Motion.fast; easing.type: Easing.OutQuart }
        onFinished: { if (root._nextGlyph !== root._shownGlyph) _glyphStamp.start() }
    }

    Behavior on implicitWidth {
        enabled: root._ready && !ShellSettings.reduceMotion
        NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic }
    }
    // bar row's full height as the input target, visible capsule stays compact — matters on a tall bar
    implicitHeight: Math.max(pillH, parent ? parent.height : 0)
    // clip only when something actually overflows: the row while the pill eases open into wider text
    // (shrinking can't spill — width lags above the content), and the scan sweep, which starts off-pill.
    // a standing clip node would break scene batching on every bar repaint.
    clip: _contentScan.active || row.width > width
    activeFocusOnTab: interactive

    Accessible.role: interactive ? Accessible.Button : Accessible.StaticText
    Accessible.name: accessibleName
    Accessible.description: accessibleDescription
    Accessible.focusable: interactive
    Accessible.onPressAction: if (root.interactive) root.activated()

    Keys.onPressed: event => {
        if (!root.interactive || (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter))
            return
        root._keyboardPressed = true
        event.accepted = true
    }
    Keys.onReleased: event => {
        if (!root._keyboardPressed || (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter))
            return
        root._keyboardPressed = false
        event.accepted = true
        root.activated()
    }

    // fill on hover, ring on focus; never on press — a press-driven version flashed on every click
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: root.pillH
        radius: height / 2
        // keys off activeFocusOnTab so Tab-reachable non-button pills (e.g. brightness) still ring
        readonly property bool _focus: root.activeFocusOnTab && root.activeFocus
        // hover capsule leans faintly accent to match the glyph/text hover tint
        color: _focus ? Theme.withAlpha(Theme.accent, 0.14)
                      : Theme.withAlpha(Theme.mix(Theme.text, Theme.accent, 0.30), 0.07)
        opacity: ((_pillHover.hovered && ShellSettings.barHoverHighlight) || _focus) ? 1.0 : 0.0
        visible: opacity > 0.001
        border.width: _focus ? 1 : 0
        border.color: Theme.withAlpha(Theme.accent, 0.72)
        Behavior on opacity {
            enabled: !ShellSettings.reduceMotion
            NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
        }
        Behavior on color {
            enabled: !ShellSettings.reduceMotion
            ColorAnimation { duration: Motion.fast }
        }
    }

    Item {
        id: _levelTrack
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round((parent.height + root.pillH) / 2) - 3
        width: Math.max(10, parent.width - root.horizontalPadding * 2 - 2)
        height: 2
        opacity: root.levelVisible && root.levelValue >= 0 ? 1 : 0
        visible: opacity > 0.001

        Behavior on opacity {
            enabled: !ShellSettings.reduceMotion
            NumberAnimation { duration: Motion.fast }
        }

        Rectangle {
            anchors.fill: parent
            radius: 1
            color: Theme.withAlpha(Theme.subtext, 0.16)
        }

        Rectangle {
            width: Math.round(parent.width * Math.max(0, Math.min(1, root.levelValue)))
            height: parent.height
            radius: 1
            color: root.levelColor
            opacity: 0.78

            Behavior on width {
                enabled: !ShellSettings.reduceMotion
                NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
            }
            Behavior on color {
                enabled: !ShellSettings.reduceMotion
                ColorAnimation { duration: Motion.color }
            }
        }
    }

    readonly property color _hoverGlyphColor: ((_pillHover.hovered && ShellSettings.barHoverHighlight) || activeFocus)
        ? Theme.mix(glyphColor, Theme.accent, 0.20) : glyphColor
    readonly property color _hoverTextColor: ((_pillHover.hovered && ShellSettings.barHoverHighlight) || activeFocus)
        ? Theme.mix(textColor, Theme.accent, 0.16) : textColor

    Row {
        id: row
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        spacing: Metrics.pillGapFor(root.compact)

        Item {
            id: _glyphBox
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth:  root._shownGlyph.length > 0 ? Metrics.iconCellFor(root.glyphPixelSize) : 0
            implicitHeight: _glyphText.implicitHeight
            scale: root.visualPressed ? 0.84 : 1.0
            transformOrigin: Item.Center
            Behavior on scale { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

            Text {
                id: _glyphText
                anchors.centerIn: parent
                text:            root._shownGlyph
                color:           root._hoverGlyphColor
                transformOrigin: Item.Center
                font.family:     Settings.font
                font.pixelSize:  root.glyphPixelSize
                renderType:      Text.NativeRendering
                Behavior on color {
                    enabled: root.animateGlyphColor && !ShellSettings.reduceMotion
                    ColorAnimation { duration: Motion.color }
                }
            }
        }

        Item {
            id: _textBox
            readonly property bool _hasShownText: _textEl._hasShownText
            anchors.verticalCenter: parent.verticalCenter
            visible: _hasShownText
            width:   _hasShownText ? Math.ceil(Math.min(Math.max(implicitWidth, root._reserveW), root.maxTextWidth)) : 0
            height: _textEl.implicitHeight
            implicitWidth: _textEl.implicitWidth

            Text {
                id: _textEl
                property string _shown: ""
                readonly property bool _hasShownText: root.animateText ? _shown.length > 0 : root.hasText
                width: parent.width
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: root.reserveText.length > 0 ? Text.AlignHCenter : Text.AlignLeft
                elide:   Text.ElideRight
                text:    root.animateText ? _shown : root.text
                textFormat: Text.PlainText
                color:   root._hoverTextColor
                font.family:    Settings.font
                font.pixelSize: Settings.fontSize
                renderType: Text.NativeRendering
                Behavior on color {
                    enabled: !ShellSettings.reduceMotion
                    ColorAnimation { duration: Motion.color }
                }
            }

            Component.onCompleted: if (root.animateText) _textEl._shown = root.text

            Connections {
                target: root
                enabled: root.animateText
                function onTextChanged() {
                    if (!root._ready) { _textEl._shown = root.text; return }
                    if (ShellSettings.reduceMotion) {
                        _textSwap.stop()
                        _textEl.opacity = 1.0
                        _textEl._shown = root.text
                        return
                    }
                    _textSwap.restart()
                }
            }

            SequentialAnimation {
                id: _textSwap
                NumberAnimation { target: _textEl; property: "opacity"; to: 0;   duration: Motion.instant; easing.type: Easing.InCubic  }
                ScriptAction    { script: _textEl._shown = root.text }
                NumberAnimation { target: _textEl; property: "opacity"; to: 1.0; duration: Motion.fast;    easing.type: Easing.OutCubic }
            }
        }
    }

    Loader {
        id: _contentScan
        // glyph-only status pills (initial update checks) still need a visible sweep before detail text arrives
        active: root.contentScanEnabled && !ShellSettings.reduceMotion
        width: Math.max(1, root.contentScanWidth)
        height: row.height
        x: row.x - width + (row.width + width) * Math.max(0, Math.min(1, root.contentScanProgress))
        y: row.y

        sourceComponent: Item {
            clip: true
            width: _contentScan.width
            height: _contentScan.height

            Row {
                x: row.x - _contentScan.x
                y: 0
                spacing: row.spacing

                Item {
                    width: _glyphBox.width
                    height: row.height

                    Text {
                        anchors.centerIn: parent
                        text:           root._shownGlyph
                        color:          root.contentScanColor
                        font.family:    Settings.font
                        font.pixelSize: root.glyphPixelSize
                        renderType:     Text.NativeRendering
                    }
                }

                Item {
                    visible: _textBox._hasShownText
                    width: _textBox.width
                    height: row.height

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        // must match the real text's alignment (centers when a reserveText floor is set) or the swept copy lands offset and looks doubled/garbled
                        horizontalAlignment: root.reserveText.length > 0 ? Text.AlignHCenter : Text.AlignLeft
                        elide: Text.ElideRight
                        text: root.animateText ? _textEl._shown : root.text
                        textFormat: Text.PlainText
                        color: root.contentScanColor
                        font.family: Settings.font
                        font.pixelSize: Settings.fontSize
                        renderType: Text.NativeRendering
                    }
                }
            }
        }
    }

    HoverHandler {
        id: _pillHover
        // horizontal padding gives hover/click/wheel/focus one non-overlapping target, not extending hover into neighbours
        margin: 0
        onHoveredChanged: {
            if (hovered) _hoverRevealTimer.restart()
            else { _hoverRevealTimer.stop(); root.hoverActive = false }
        }
    }

    Timer {
        id: _hoverRevealTimer
        interval: root.hoverRevealDelay
        onTriggered: root.hoverActive = true
    }

    onActiveFocusChanged: {
        if (!activeFocus && !hovered) {
            _keyboardPressed = false
            hoverActive = false
        }
    }
}
