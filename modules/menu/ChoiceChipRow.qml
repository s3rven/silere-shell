pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"

Item {
    id: root

    property string glyph: ""
    property string label: ""
    property var    model: []
    property var    currentValue
    property color  accentColor: Theme.accent
    property bool   rowEnabled: true
    property bool   stacked:    false
    // Card-edge rounding for the hover fill — set on the first/last row of a card
    // so the fill rounds only where the card itself does (see RowHoverBg).
    property real   topRadius:    0
    property real   bottomRadius: 0
    property real   cardInset:    1
    // auto-stack when the inline form wouldn't fit; positioned via x/y (not flipped
    // anchors) so the layout switch is glitch-free. Gauged off the control's
    // *natural* inline width, not its live width — segment widths depend on
    // _stacked, so reading the live width here would close a binding loop.
    readonly property bool _stacked: stacked
        || (width > 0 && _segContainer._maxNatW > 0
            && _labelRow.implicitWidth + _segContainer._naturalW + 40 > width)

    signal chosen(var value)

    // 4px multiples: keep card dividers on whole physical px under
    // fractional scaling.
    width:  parent ? parent.width : 0
    height: _stacked ? 72 : 44
    opacity: rowEnabled ? 1.0 : 0.45
    Behavior on opacity { NumberAnimation { duration: Motion.medium } }

    readonly property int _activeIndex: {
        for (let i = 0; i < model.length; i++) {
            if (model[i].value === currentValue) return i
        }
        return -1
    }

    // Hover fill, matching the toggle/slider rows.
    HoverHandler { id: _rowHover; enabled: root.rowEnabled }
    RowHoverBg {
        anchors.fill: parent
        topRadius:    root.topRadius
        bottomRadius: root.bottomRadius
        cardInset:    root.cardInset
        active:       _rowHover.hovered && root.rowEnabled
        fillOpacity:  0.08
    }

    Row {
        id: _labelRow
        x: 12
        y: root._stacked ? 11 : (root.height - height) / 2
        spacing: 8

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.glyph.length > 0
            width: Math.ceil(implicitWidth)   // whole px so the label lands on the pixel grid
            text:           root.glyph
            color:          Theme.withAlpha(Theme.subtext, 0.85)
            font.family:    Settings.font
            font.pixelSize: Settings.fontSize + 1
            renderType:     Text.NativeRendering
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text:           root.label
            textFormat:     Text.PlainText
            color:          Theme.withAlpha(Theme.text, 0.85)
            font.family:    Settings.font
            font.pixelSize: Settings.fontSize
            renderType:     Text.NativeRendering
        }
    }

    Rectangle {
        id: _segContainer
        x: root._stacked ? 12 : (root.width - 12 - width)
        y: root._stacked ? (_labelRow.y + _labelRow.height + 8) : (root.height - height) / 2
        height:       26
        width:        _segRow.implicitWidth + 4
        radius:       8
        antialiasing: true
        color:        Theme.menuControl
        border.width: 1
        border.color: Theme.menuControlLine

        // Bumped when delegates are (re)created. itemAt() returns null while the
        // Repeater is still populating; without this the binding caches that null
        // and the indicator stays hidden until the first click forces a re-eval.
        property int _rev: 0
        readonly property Item _activeSeg: {
            _segContainer._rev
            if (root._activeIndex < 0 || _segRepeater.count <= root._activeIndex) return null
            return _segRepeater.itemAt(root._activeIndex)
        }

        property bool _animReady: false
        Component.onCompleted: Qt.callLater(function() {
            _segContainer._animReady = true
            _segContainer._recalcNat()
        })

        // Equal-width segments: every segment takes the widest segment's natural
        // width, so a control reads as one tidy switch instead of ragged chips
        // (3s vs 10s, Off vs Center). Recomputed imperatively rather than as a
        // binding over itemAt() so a segment whose text settles late can't strand
        // a stale max.
        property real _maxNatW: 0
        function _recalcNat() {
            let m = 0
            for (let i = 0; i < _segRepeater.count; i++) {
                const it = _segRepeater.itemAt(i)
                if (it) m = Math.max(m, it.natW)
            }
            _maxNatW = m
        }
        // Natural inline width of the whole control (drives the stack decision).
        readonly property real _naturalW: _maxNatW * root.model.length + 4
        // Stacked: segments divide the full row width evenly (12px gutter each side,
        // 4px for the segRow inset), floored so they stay on the pixel grid.
        readonly property real _fullCellW: Math.floor((root.width - 28) / Math.max(1, root.model.length))
        readonly property real _cellW: root._stacked ? _fullCellW : _maxNatW

        Rectangle {
            id: _indicator
            x:      _segContainer._activeSeg ? _segContainer._activeSeg.x + _segRow.x : 2
            y:      2
            width:  _segContainer._activeSeg ? _segContainer._activeSeg.width : 0
            height: parent.height - 4
            radius:       6
            antialiasing: true
            opacity:      _segContainer._activeSeg ? 1.0 : 0.0
            visible:      opacity > 0.001

            color:        Theme.mix(Theme.menuCard, root.accentColor, 0.38)
            border.width: 1
            border.color: Theme.mix(Theme.menuCard, root.accentColor, 0.68)

            Behavior on x        { enabled: _segContainer._animReady && !ShellSettings.reduceMotion; SpringAnimation { spring: 7; damping: 0.7; epsilon: 0.5 } }
            Behavior on width    { enabled: _segContainer._animReady && !ShellSettings.reduceMotion; SpringAnimation { spring: 7; damping: 0.7; epsilon: 0.5 } }
            Behavior on opacity  { NumberAnimation { duration: Motion.fast } }
            Behavior on color        { ColorAnimation { duration: Motion.fast } }
            Behavior on border.color { ColorAnimation { duration: Motion.fast } }
        }

        Row {
            id: _segRow
            x: 2
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Repeater {
                id: _segRepeater
                model: root.model
                onItemAdded:   { _segContainer._rev++; _segContainer._recalcNat() }
                onItemRemoved: { _segContainer._rev++; _segContainer._recalcNat() }

                delegate: Item {
                    id: _seg
                    required property var modelData
                    required property int index

                    readonly property bool   active:   index === root._activeIndex
                    readonly property string segGlyph: (modelData.glyph !== undefined && modelData.glyph !== null)
                        ? String(modelData.glyph) : ""

                    // Natural (content) width; the container maxes these to size
                    // every segment equally. Never shrink below it so text can't clip.
                    readonly property real natW: Math.ceil(_content.implicitWidth) + 20
                    onNatWChanged: _segContainer._recalcNat()

                    width:  Math.max(natW, _segContainer._cellW)
                    height: 24

                    HoverHandler {
                        id: _hover
                        enabled: root.rowEnabled
                        cursorShape: root.rowEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }
                    TapHandler {
                        id: _tap
                        enabled: root.rowEnabled
                        onTapped: root.chosen(_seg.modelData.value)
                    }

                    scale: _tap.pressed ? 0.92 : 1.0
                    transformOrigin: Item.Center
                    Behavior on scale { enabled: !ShellSettings.reduceMotion; SpringAnimation { spring: 14; damping: 0.5; epsilon: 0.005 } }

                    Row {
                        id: _content
                        anchors.centerIn: parent
                        spacing: _seg.segGlyph.length > 0 && _seg.modelData.label.length > 0 ? 4 : 0

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible:        _seg.segGlyph.length > 0
                            text:           _seg.segGlyph
                            color:          _seg.active
                                ? root.accentColor
                                : Theme.withAlpha(Theme.subtext, _hover.hovered ? 0.95 : 0.70)
                            font.family:    Settings.font
                            font.pixelSize: Settings.fontSize
                            font.weight:    Font.Medium
                            renderType:     Text.NativeRendering
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible:        _seg.modelData.label.length > 0
                            text:           _seg.modelData.label
                            textFormat:     Text.PlainText
                            color:          _seg.active
                                ? root.accentColor
                                : Theme.withAlpha(Theme.subtext, _hover.hovered ? 0.95 : 0.70)
                            font.family:    Settings.font
                            font.pixelSize: Settings.fontSize
                            font.weight:    _seg.active ? Font.DemiBold : Font.Medium
                            renderType:     Text.NativeRendering
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                        }
                    }
                }
            }
        }
    }
}
