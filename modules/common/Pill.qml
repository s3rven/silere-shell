import QtQuick
import "../../config"
import "../../services"

Item {
    id: root

    property string glyph:      ""
    property string text:       ""
    property color  glyphColor: Theme.text
    property color  textColor:  Theme.subtext
    property int    cursorShape: Qt.ArrowCursor
    property int    maxTextWidth: 150
    property bool   animateGlyph: true
    // Opt-in cross-fade when `text` changes. Off by default since widgets
    // like Volume/Brightness update text on every scroll tick and don't
    // want fade-through on rapid changes.
    property bool   animateText: false
    property bool   animateGlyphColor: true
    property int    glyphPixelSize: Settings.fontSize + 2
    // Floor the text box to this string's width so value readouts (volume,
    // brightness) keep a constant size instead of resizing on every change.
    property string reserveText: ""
    readonly property real _reserveW: reserveText.length > 0 ? Math.ceil(_reserveMetrics.advanceWidth) : 0
    property bool   contentScanEnabled: false
    property color  contentScanColor: Theme.text
    property real   contentScanProgress: 0.0
    property real   contentScanWidth: 10.0

    // Delayed hover flag for hover-reveal detail text (battery/network use it):
    // true only after the pointer rests on the pill for hoverRevealDelay ms.
    property int    hoverRevealDelay: 80
    property bool   hoverActive: false

    // Opt-in press feedback: a clickable widget binds this to its own
    // handler's pressed state and the glyph dips, then springs back.
    property bool   pressed: false

    readonly property int  pillH:   24
    readonly property bool hasText: text.length > 0

    // Holds the maximum width seen recently so the pill doesn't jitter while
    // scrolling. Resets automatically after `shrinkDelay` ms, or immediately
    // when text clears (e.g. network widget hiding its SSID).
    // Set shrinkDelay: 0 on pills that only change on hover (not rapid scroll)
    // so they snap back immediately instead of leaving a gap.
    property int  shrinkDelay: 600
    property real _minW: 0
    // Whole px: fractional text widths put the pill (and every widget after it
    // in the bar row) on fractional pixels, which blurs NativeRendering text.
    readonly property real rowWidth: Math.ceil(row.implicitWidth)
    implicitWidth:  Math.max(rowWidth, _minW)

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
        NumberAnimation { target: _glyphText; property: "scale"; to: 0.0; duration: Motion.instant; easing.type: Easing.InBack;  easing.overshoot: 1.2 }
        ScriptAction    { script: root._shownGlyph = root._nextGlyph }
        NumberAnimation { target: _glyphText; property: "scale"; from: 0.0; to: 1.0; duration: Motion.width; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
        onFinished: { if (root._nextGlyph !== root._shownGlyph) _glyphStamp.start() }
    }

    Behavior on implicitWidth {
        enabled: root._ready && !ShellSettings.reduceMotion
        NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic }
    }
    implicitHeight: pillH

    // Default hover affordance: glyph and text lean toward the accent — the
    // widget acknowledges the pointer without geometry or chrome. Status
    // colours (battery warning…) stay dominant under the 1/3 mix.
    readonly property color _hoverGlyphColor: _pillHover.hovered
        ? Theme.mix(glyphColor, Theme.accent, 0.35) : glyphColor
    readonly property color _hoverTextColor: _pillHover.hovered
        ? Theme.mix(textColor, Theme.accent, 0.30) : textColor

    Row {
        id: row
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        spacing: 5

        Item {
            id: _glyphBox
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth:  Math.ceil(_glyphText.implicitWidth)
            implicitHeight: _glyphText.implicitHeight
            scale: root.pressed ? 0.84 : 1.0
            transformOrigin: Item.Center
            Behavior on scale { enabled: !ShellSettings.reduceMotion; SpringAnimation { spring: 18; damping: 0.5; epsilon: 0.005 } }

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
        active: root.contentScanEnabled && root.hasText && !ShellSettings.reduceMotion
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
                        // Must match the real text's alignment (it centers when a
                        // reserveText floor is set) or the swept copy lands offset
                        // and looks like doubled/garbled characters.
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
        // Extend the hover target past the tight text bounds so hover-reveal
        // isn't pixel-precise. Compact mode tightens the gaps, so the margin
        // shrinks with them — overlapping targets make neighbours fight.
        margin: ShellSettings.barCompact ? 3 : 7
        cursorShape: root.cursorShape
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
}
