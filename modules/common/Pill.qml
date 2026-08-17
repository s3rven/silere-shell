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
    property int    maxTextWidth: 150
    property bool   compact: ShellSettings.barCompact
    readonly property int horizontalPadding: Metrics.pillPadFor(compact)
    property bool   animateGlyph: true
    property bool   animateText: false
    property int    glyphPixelSize: Settings.iconSize + 2
    property string reserveText: ""
    readonly property real _reserveW: reserveText.length > 0 ? Math.ceil(_reserveMetrics.advanceWidth) : 0
    property bool   contentScanEnabled: false
    property color  contentScanColor: Theme.text
    property real   contentScanProgress: 0.0
    property real   contentScanWidth: 10.0
    property real   levelValue: -1.0
    property bool   levelVisible: false
    property color  levelColor: Theme.accent

    property bool   hoverActive: false
    readonly property bool hovered: _pillHover.hovered
    readonly property bool expanded: hoverActive

    property bool   pressed: false
    readonly property bool visualPressed: pressed

    signal activated()

    readonly property int  pillH:   Metrics.barRowHeight
    readonly property bool hasText: text.length > 0

    property bool collapsed: false
    property int  shrinkDelay: 600
    property real _minW: 0
    // whole px: a fractional text width puts the pill and every widget after it off-pixel and blurs NativeRendering text
    readonly property real rowWidth: Math.ceil(row.implicitWidth)
    implicitWidth:  collapsed ? 0 : Math.max(rowWidth, _minW) + horizontalPadding * 2

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
        if (_ready) _settleAnimatedContent()
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
        _nextGlyph = root.glyph
        Qt.callLater(function() { if (root) root._ready = true })
    }

    function _settleAnimatedContent(): void {
        _glyphStamp.stop()
        _textSwap.stop()
        _shownGlyph = root.glyph
        _nextGlyph = root.glyph
        _glyphText.scale = 1.0
        _textEl.opacity = 1.0
        if (root.animateText) _textEl._shown = root.text
    }

    onGlyphChanged: {
        if (!_ready) { _shownGlyph = glyph; return }
        if (!root.visible || !animateGlyph || ShellSettings.reduceMotion) {
            _settleAnimatedContent()
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
        onFinished: {
            if (root.visible && !ShellSettings.reduceMotion
                    && root._nextGlyph !== root._shownGlyph)
                _glyphStamp.start()
        }
    }

    MotionBehavior on implicitWidth {
        // not visible: it reads through the parent, so a collapsing pill turns its own
        // gate off partway and the signal means "my zone is showing", not "I am open"
        gate: root._ready
        NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic }
    }
    implicitHeight: Math.max(pillH, parent ? parent.height : 0)
    // only while it eases open into wider text, or the scan sweeps in from off-pill; a standing clip node breaks batching
    clip: _contentScan.active || row.width > width

    Rectangle {
        id: _hoverCap
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: root.pillH
        radius: Metrics.hoverRadiusFor(height)
        readonly property bool _hover: _pillHover.hovered
            && ShellSettings.barHoverHighlight
        color: root.visualPressed ? Theme.withAlpha(Theme.accent, 0.18)
             : Theme.withAlpha(Theme.mix(Theme.text, Theme.accent, 0.30), 0.07)
        opacity: (_hover || root.visualPressed) ? 1.0 : 0.0
        scale: root.visualPressed ? 0.985
             : _hover ? 1.0 : 0.96
        transformOrigin: Item.Center
        visible: opacity > 0.001
        MotionBehavior on opacity {
            NumberAnimation {
                duration: (_hoverCap._hover || root.visualPressed)
                    ? Motion.hoverIn : Motion.hoverOut
                easing.type: Easing.OutCubic
            }
        }
        MotionBehavior on scale {
            NumberAnimation {
                duration: root.visualPressed ? Motion.press
                    : _hoverCap._hover
                        ? Motion.hoverIn : Motion.hoverOut
                easing.type: Easing.OutCubic
            }
        }
        ColorFade on color {}
    }

    Item {
        id: _levelTrack
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round((parent.height + root.pillH) / 2) - 3
        width: Math.max(10, parent.width - root.horizontalPadding * 2 - 2)
        height: 2
        opacity: root.levelVisible && root.levelValue >= 0 ? 1 : 0
        visible: opacity > 0.001

        MotionBehavior on opacity {
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

            MotionBehavior on width {
                NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
            }
            ColorFade on color {}
        }
    }

    readonly property bool _contentHot: (_pillHover.hovered
        && ShellSettings.barHoverHighlight)
        || root.visualPressed
    readonly property color _hoverGlyphColor: _contentHot
        ? Theme.mix(glyphColor, Theme.accent, 0.20) : glyphColor
    readonly property color _hoverTextColor: _contentHot
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

            ShellText {
                id: _glyphText
                anchors.centerIn: parent
                text:            root._shownGlyph
                color:           root._hoverGlyphColor
                transformOrigin: Item.Center
                font.pixelSize:  root.glyphPixelSize
                ColorFade on color {}
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

            ShellText {
                id: _textEl
                property string _shown: ""
                readonly property bool _hasShownText: root.animateText ? _shown.length > 0 : root.hasText
                width: parent.width
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: root.reserveText.length > 0 ? Text.AlignHCenter : Text.AlignLeft
                elide:   Text.ElideRight
                text:    root.animateText ? _shown : root.text
                color:   root._hoverTextColor
                font.pixelSize: Settings.fontSize
                ColorFade on color {}
            }

            Component.onCompleted: if (root.animateText) _textEl._shown = root.text

            Connections {
                target: root
                enabled: root.animateText
                function onTextChanged() {
                    if (!root._ready) { _textEl._shown = root.text; return }
                    if (!root.visible || ShellSettings.reduceMotion) {
                        root._settleAnimatedContent()
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
        active: root.visible && root.contentScanEnabled
            && !ShellSettings.reduceMotion
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

                    ShellText {
                        anchors.centerIn: parent
                        text:           root._shownGlyph
                        color:          root.contentScanColor
                        font.pixelSize: root.glyphPixelSize
                    }
                }

                Item {
                    visible: _textBox._hasShownText
                    width: _textBox.width
                    height: row.height

                    ShellText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        // must match the real text's alignment (centers when a reserveText floor is set) or the swept copy lands offset and looks doubled/garbled
                        horizontalAlignment: root.reserveText.length > 0 ? Text.AlignHCenter : Text.AlignLeft
                        elide: Text.ElideRight
                        text: root.animateText ? _textEl._shown : root.text
                        color: root.contentScanColor
                        font.pixelSize: Settings.fontSize
                    }
                }
            }
        }
    }

    HoverHandler {
        id: _pillHover
        enabled: root.enabled && root.visible
        margin: 0
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onHoveredChanged: {
            if (hovered) _hoverRevealTimer.restart()
            else { _hoverRevealTimer.stop(); root.hoverActive = false }
        }
    }

    Timer {
        id: _hoverRevealTimer
        interval: 80
        onTriggered: root.hoverActive = true
    }

    Connections {
        target: ShellSettings
        function onReduceMotionChanged() {
            if (ShellSettings.reduceMotion && root._ready)
                root._settleAnimatedContent()
        }
    }

}
