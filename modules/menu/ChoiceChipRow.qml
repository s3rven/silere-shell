pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../common"

Item {
    id: root

    property string glyph: ""
    property string label: ""
    property var    model: []
    property var    currentValue
    property color  accentColor: Theme.accent
    // Card-edge rounding for the hover fill — set on the first/last row of a card
    // so the fill rounds only where the card itself does (see RowHoverBg).
    property real   topRadius:    0
    property real   bottomRadius: 0
    property real   cardInset:    1
    signal chosen(var value)

    readonly property real _compactControlW:
        Math.min(172, Math.max(1, width - 26))
    readonly property real _inlineLabelW:
        Math.max(0, width - 12 - _compactControlW - 14 - 10)
    readonly property bool _stacked: width > 0
        && _labelRow.neededW > _inlineLabelW

    // 4px multiples: keep card dividers on whole physical px under fractional scaling
    width:  parent ? parent.width : 0
    height: _stacked ? 76 : 44
    opacity: enabled ? 1.0 : 0.45
    Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.medium } }

    readonly property int _activeIndex: {
        for (let i = 0; i < model.length; i++) {
            if (model[i].value === currentValue) return i
        }
        return -1
    }

    // one tab stop for the row: entering lands on the active chip, ←/→ move, Space/Enter pick (Item not FocusScope, so it only fires when the row gets Tab focus)
    activeFocusOnTab: enabled
    onActiveFocusChanged: {
        if (activeFocus && _segRepeater.count > 0) {
            const it = _segRepeater.itemAt(Math.max(0, _activeIndex))
            if (it) it.forceActiveFocus()
        }
    }

    Item {
        id: _labelRow
        x: 14
        y: root._stacked ? 12 : (root.height - height) / 2
        width: root._stacked
            ? root.width - 26
            : Math.max(0, _segContainer.x - x - 10)
        implicitHeight: Math.max(_glyph.implicitHeight, _label.implicitHeight)
        height: Math.max(_glyph.implicitHeight, _label.implicitHeight)
        readonly property real neededW: (root.glyph.length > 0 ? 28 : 0)
            + Math.ceil(_label.implicitWidth)

        Text {
            id: _glyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            visible: root.glyph.length > 0
            width: visible ? 18 : 0
            horizontalAlignment: Text.AlignHCenter
            text:           root.glyph
            color:          Theme.withAlpha(Theme.subtext, 0.85)
            font.family:    Settings.font
            font.pixelSize: Settings.iconSize + 2
            renderType:     Text.NativeRendering
        }
        Text {
            id: _label
            anchors.left:           _glyph.right
            anchors.leftMargin:     root.glyph.length > 0 ? 10 : 0
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Math.max(18, parent.width - anchors.leftMargin - _glyph.width))
            text:           root.label
            textFormat:     Text.PlainText
            elide:          Text.ElideRight
            color:          Theme.withAlpha(Theme.text, 0.85)
            font.family:    Settings.font
            font.pixelSize: Settings.fontSize
            renderType:     Text.NativeRendering
        }
    }

    Rectangle {
        id: _segContainer
        x: root.width - 12 - width
        y: root._stacked ? root.height - 12 - height : (root.height - height) / 2
        width: Math.min(root._stacked ? 240 : 172,
            Math.max(1, root.width - 26))
        height: 28
        radius:       Theme.radiusControl
        antialiasing: true
        color: Theme.mix(Theme.menuControl, Theme.text, 0.012)

        OutlineBorder {
            radius: _segContainer.radius
            outlineColor: Theme.menuControlLine
        }

        // bumped when delegates are (re)created: itemAt() returns null while the Repeater populates;
        // without this the binding caches that null and the indicator stays hidden until the first click re-evals
        property int _rev: 0
        readonly property Item _activeSeg: {
            _segContainer._rev
            if (root._activeIndex < 0 || _segRepeater.count <= root._activeIndex) return null
            return _segRepeater.itemAt(root._activeIndex)
        }
        property int _hoverIndex: -1
        readonly property Item _hoverSeg: {
            _segContainer._rev
            if (_hoverIndex < 0 || _segRepeater.count <= _hoverIndex) return null
            return _segRepeater.itemAt(_hoverIndex)
        }

        property bool _animReady: false
        Component.onCompleted: Qt.callLater(function() {
            _segContainer._animReady = true
        })

        readonly property real _cellW: Math.max(1,
            Math.floor((_segContainer.width - 8) / Math.max(1, root.model.length)))

        Rectangle {
            readonly property bool shown: _segContainer._hoverSeg
                && _segContainer._hoverIndex !== root._activeIndex
            x: _segContainer._hoverSeg
                ? _segContainer._hoverSeg.x + _segRow.x + 2
                : 4
            y: 2
            width: _segContainer._hoverSeg
                ? Math.max(1, _segContainer._hoverSeg.width - 4) : 1
            height: 24
            radius: Theme.radiusControl - 3
            antialiasing: true
            color: Theme.withAlpha(Theme.text, 0.045)
            opacity: shown ? 1 : 0
            visible: opacity > 0.001
            Behavior on x {
                enabled: _segContainer._animReady && !ShellSettings.reduceMotion
                NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
            }
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }

        Rectangle {
            id: _indicator
            x: _segContainer._activeSeg
                ? _segContainer._activeSeg.x + _segRow.x + 2
                : 4
            y: 2
            width: _segContainer._activeSeg
                ? Math.max(1, _segContainer._activeSeg.width - 4) : 1
            height: 24
            radius: Theme.radiusControl - 3
            antialiasing: true
            opacity:      _segContainer._activeSeg ? 1.0 : 0.0
            visible:      opacity > 0.001
            color: Theme.mix(Theme.menuControl, root.accentColor,
                ShellSettings.neutralTheme ? 0.16 : 0.24)
            border.width: 1
            border.color: Theme.withAlpha(root.accentColor,
                ShellSettings.highContrast ? 0.62 : 0.34)

            Behavior on x        { enabled: _segContainer._animReady && !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.width; easing.type: Easing.OutQuart } }
            Behavior on width    { enabled: _segContainer._animReady && !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.width; easing.type: Easing.OutQuart } }
        }

        Row {
            id: _segRow
            x: 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Repeater {
                id: _segRepeater
                model: root.model
                onItemAdded:   _segContainer._rev++
                onItemRemoved: _segContainer._rev++

                delegate: Item {
                    id: _seg
                    required property var modelData
                    required property int index

                    readonly property bool   active:   index === root._activeIndex
                    readonly property string segGlyph: (modelData.glyph !== undefined && modelData.glyph !== null)
                        ? String(modelData.glyph) : ""

                    width:  _segContainer._cellW
                    height: 26
                    clip: true

                    Accessible.role: Accessible.RadioButton
                    Accessible.name: root.label + ": " + String(_seg.modelData.label ?? "")
                    Accessible.checked: _seg.active
                    Accessible.onPressAction: {
                        if (root.enabled) root.chosen(_seg.modelData.value)
                    }
                    Keys.onSpacePressed: event => { if (!event.isAutoRepeat && root.enabled) root.chosen(_seg.modelData.value); event.accepted = true }
                    Keys.onReturnPressed: event => { if (!event.isAutoRepeat && root.enabled) root.chosen(_seg.modelData.value); event.accepted = true }
                    Keys.onEnterPressed: event => { if (!event.isAutoRepeat && root.enabled) root.chosen(_seg.modelData.value); event.accepted = true }
                    Keys.onLeftPressed: event => {
                        const it = _segRepeater.itemAt(_seg.index - 1)
                        if (it) it.forceActiveFocus()
                        event.accepted = true
                    }
                    Keys.onRightPressed: event => {
                        const it = _segRepeater.itemAt(_seg.index + 1)
                        if (it) it.forceActiveFocus()
                        event.accepted = true
                    }

                    HoverHandler {
                        id: _hover
                        enabled: root.enabled
                        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onHoveredChanged: {
                            if (hovered) _segContainer._hoverIndex = _seg.index
                            else if (_segContainer._hoverIndex === _seg.index)
                                _segContainer._hoverIndex = -1
                        }
                    }
                    TapHandler {
                        enabled: root.enabled
                        onTapped: root.chosen(_seg.modelData.value)
                    }

                    // Keyboard focus stays explicit without adding pointer-hover fills.
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: Theme.radiusControl - 3
                        antialiasing: true
                        color: "transparent"
                        border.width: 1
                        border.color: Theme.withAlpha(root.accentColor, 0.58)
                        opacity: _seg.activeFocus ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                    }

                    Row {
                        id: _content
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible:        _seg.segGlyph.length > 0
                            text:           _seg.segGlyph
                            color:          _seg.active
                                ? Theme.mix(Theme.text, root.accentColor, ShellSettings.highContrast ? 0.0 : 0.10)
                                : (_hover.hovered ? Theme.withAlpha(Theme.text, 0.88) : Theme.withAlpha(Theme.subtext, 0.68))
                            font.family:    Settings.font
                            font.pixelSize: Math.max(9, Settings.fontSize - 1)
                            font.weight:    Font.Medium
                            renderType:     Text.NativeRendering
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible:        _seg.modelData.label.length > 0
                            text:           _seg.modelData.label
                            textFormat:     Text.PlainText
                            width: Math.min(implicitWidth, Math.max(14, _segContainer._cellW - 8
                                - (_seg.segGlyph.length > 0 ? 18 : 0)))
                            height: 18
                            verticalAlignment: Text.AlignVCenter
                            elide:          Text.ElideRight
                            color:          _seg.active
                                ? Theme.mix(Theme.text, root.accentColor, ShellSettings.highContrast ? 0.0 : 0.10)
                                : (_hover.hovered ? Theme.withAlpha(Theme.text, 0.88) : Theme.withAlpha(Theme.subtext, 0.68))
                            font.family:    Settings.font
                            font.pixelSize: Math.max(9, Settings.fontSize - 1)
                            fontSizeMode: Text.HorizontalFit
                            minimumPixelSize: Math.max(8, Settings.fontSize - 3)
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
