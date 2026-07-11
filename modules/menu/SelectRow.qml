pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"

Item {
    id: root

    property string glyph:       ""
    property string label:       ""
    property string badge:       ""
    property string badgeKind:   badge
    property var    model:       []
    property var    currentValue
    property real   topRadius:    0
    property real   bottomRadius: 0
    property real   cardInset:    1

    signal chosen(var value)

    property bool _open: false

    function _focusOption(index: int): void {
        if (!_open || _optRepeater.count <= 0) return
        const i = Math.max(0, Math.min(_optRepeater.count - 1, index))
        const item = _optRepeater.itemAt(i)
        if (item) item.forceActiveFocus()
    }

    function _focusActiveOption(): void {
        _focusOption(Math.max(0, _activeIndex))
    }

    function _setOpen(next: bool): void {
        if (!root.enabled) return
        if (_open === next) {
            if (_open) Qt.callLater(root._focusActiveOption)
            return
        }
        _open = next
        if (_open) Qt.callLater(root._focusActiveOption)
    }

    function _toggleOpen(): void {
        _setOpen(!_open)
    }

    readonly property int _activeIndex: {
        for (let i = 0; i < model.length; i++)
            if (model[i].value === currentValue) return i
        return -1
    }
    readonly property string _activeLabel: _activeIndex >= 0 ? model[_activeIndex].label : ""
    readonly property string _activeFont: {
        if (_activeIndex < 0) return Settings.font
        const f = model[_activeIndex].fontFamily
        return (f !== undefined && f !== null && String(f).length > 0) ? String(f) : Settings.font
    }

    width:  parent ? parent.width : 0
    height: 44 + _options.height
    implicitHeight: height
    opacity: enabled ? 1.0 : 0.45
    Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.medium } }

    activeFocusOnTab: root.enabled
    Accessible.role: Accessible.ComboBox
    Accessible.name: root.label
    Accessible.description: root._activeLabel
    Keys.onSpacePressed: event => { if (!event.isAutoRepeat) root._toggleOpen(); event.accepted = true }
    Keys.onReturnPressed: event => { if (!event.isAutoRepeat) root._toggleOpen(); event.accepted = true }
    Keys.onEnterPressed: event => { if (!event.isAutoRepeat) root._toggleOpen(); event.accepted = true }
    Keys.onEscapePressed: event => { root._setOpen(false); event.accepted = true }
    Keys.onDownPressed: event => { root._setOpen(true); event.accepted = true }
    Keys.onUpPressed: event => { root._setOpen(true); event.accepted = true }

    HoverHandler { id: _hov; enabled: root.enabled; cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler   { enabled: root.enabled; onTapped: root._toggleOpen() }

    RowHoverBg {
        width:  parent.width
        height: 44
        topRadius:    root.topRadius
        bottomRadius: root._open ? 0 : root.bottomRadius
        cardInset:    root.cardInset
        active:       (_hov.hovered || root.activeFocus) && root.enabled
        focusActive:  root.activeFocus && root.enabled
        fillOpacity:  root.activeFocus ? 0.13 : 0.08
    }

    Text {
        id: _glyph
        anchors.left:           parent.left; anchors.leftMargin: 14
        anchors.verticalCenter: _header.verticalCenter
        width: root.glyph.length > 0 ? 18 : 0
        horizontalAlignment: Text.AlignHCenter
        text:           root.glyph
        color:          Theme.withAlpha(Theme.subtext, 0.85)
        font.family:    Settings.font
        font.pixelSize: Settings.iconSize + 2
        renderType:     Text.NativeRendering
    }
    Item {
        id: _header
        anchors.top:    parent.top
        anchors.left:   _glyph.right; anchors.leftMargin: root.glyph.length > 0 ? 10 : 0
        anchors.right:  _chevronSlot.left; anchors.rightMargin: 10
        height: 44
        Text {
            id: _label
            anchors.left:           parent.left
            anchors.verticalCenter: parent.verticalCenter
            text:       root.label
            textFormat: Text.PlainText
            elide:      Text.ElideRight
            width:      Math.min(implicitWidth, Math.max(18, parent.width - (_badge.visible ? _badge.width + 7 : 0)))
            color:      Theme.withAlpha(Theme.text, 0.85)
            font.family:    Settings.font
            font.pixelSize: Settings.fontSize
            renderType:     Text.NativeRendering
        }
        SettingsBadge {
            id: _badge
            anchors.left: _label.right
            anchors.leftMargin: 7
            anchors.verticalCenter: _label.verticalCenter
            text: root.badge
            kind: root.badgeKind
        }
    }
    // Right slot: current value label + chevron
    Item {
        id: _chevronSlot
        anchors.right:          parent.right; anchors.rightMargin: 12
        anchors.verticalCenter: _header.verticalCenter
        width:  Math.min(_valText.implicitWidth + 34, Math.max(78, root.width * 0.40))
        height: 26

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusControl - 2
            antialiasing: true
            color: Theme.mix(Theme.menuControl, root._open ? Theme.accent : Theme.text,
                root._open ? (ShellSettings.neutralTheme ? 0.16 : 0.24) : 0.018)
            border.width: 1
            border.color: root._open
                ? Theme.withAlpha(Theme.accent, ShellSettings.highContrast ? 0.64 : 0.46)
                : (_hov.hovered || root.activeFocus ? Theme.withAlpha(Theme.accent, 0.34) : Theme.menuControlLine)
            Behavior on color { enabled: !ShellSettings.reduceMotion; ColorAnimation { duration: Motion.fast } }
            Behavior on border.color { enabled: !ShellSettings.reduceMotion; ColorAnimation { duration: Motion.fast } }
        }

        Text {
            id: _valText
            anchors.left:           parent.left
            anchors.leftMargin:     9
            anchors.right:          parent.right
            anchors.rightMargin:    21
            anchors.verticalCenter: parent.verticalCenter
            text:           root._activeLabel
            textFormat:     Text.PlainText
            elide:          Text.ElideRight
            color:          root._open ? Theme.text : Theme.withAlpha(Theme.subtext, 0.76)
            font.family:    root._activeFont
            font.pixelSize: Settings.fontSize - 1
            font.weight:    root._open ? Font.DemiBold : Font.Medium
            renderType:     Text.NativeRendering
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }
        Text {
            anchors.right:          parent.right
            anchors.rightMargin:    7
            anchors.verticalCenter: parent.verticalCenter
            text:    "󰅀"
            rotation: root._open ? 180 : 0
            transformOrigin: Item.Center
            color:   root._open ? Theme.accent : Theme.withAlpha(Theme.subtext, 0.58)
            font.family:    Settings.font
            font.pixelSize: Settings.fontSize
            renderType:     Text.NativeRendering
            Behavior on rotation { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.medium; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
            Behavior on color    { ColorAnimation { duration: Motion.fast } }
        }
    }

    Item {
        id: _options
        anchors.top:  parent.top; anchors.topMargin: 44
        anchors.left: parent.left
        anchors.right: parent.right

        height:  root._open ? _optCol.implicitHeight : 0
        clip:    true
        visible: height > 0.5

        Behavior on height {
            enabled: !ShellSettings.reduceMotion
            NumberAnimation {
                duration:    root._open ? Motion.medium : Motion.fast
                easing.type: root._open ? Easing.OutQuart : Easing.InCubic
            }
        }

        Column {
            id: _optCol
            width: parent.width
            y:       root._open ? 0 : -10
            opacity: root._open ? 1.0 : 0.0

            // header/options seam rides the slide so it never floats alone mid-animation; inset matches RowDividers
            Rectangle {
                x: 12
                width: parent.width - 24; height: 1
                color: Theme.menuDivider
            }
            Item { width: parent.width; height: 4 }

            Behavior on y {
                enabled: !ShellSettings.reduceMotion
                NumberAnimation {
                    duration:    root._open ? Motion.medium : Motion.fast
                    easing.type: root._open ? Easing.OutQuart : Easing.InCubic
                }
            }
            Behavior on opacity {
                enabled: !ShellSettings.reduceMotion
                NumberAnimation {
                    duration:    root._open ? Motion.medium : Motion.fast
                    easing.type: root._open ? Easing.OutCubic : Easing.InCubic
                }
            }

            Repeater {
                id: _optRepeater
                model: root.model
                delegate: Item {
                    id: _opt
                    required property var modelData
                    required property int index
                    readonly property bool active: root.currentValue === modelData.value
                    readonly property string optionFont:
                        (modelData.fontFamily !== undefined && modelData.fontFamily !== null
                            && String(modelData.fontFamily).length > 0)
                        ? String(modelData.fontFamily) : Settings.font

                    width:  parent.width
                    height: 38

                    function choose(event: var): void {
                        if (!event.isAutoRepeat) {
                            root.chosen(_opt.modelData.value)
                            root._setOpen(false)
                            root.forceActiveFocus()
                        }
                        event.accepted = true
                    }

                    HoverHandler { id: _optHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            root.chosen(_opt.modelData.value)
                            root._setOpen(false)
                            root.forceActiveFocus()
                        }
                    }
                    activeFocusOnTab: root.enabled && root._open
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: root.label + ": " + String(_opt.modelData.label ?? "")
                    Accessible.checked: _opt.active
                    Keys.onSpacePressed:  event => _opt.choose(event)
                    Keys.onReturnPressed: event => _opt.choose(event)
                    Keys.onEnterPressed:  event => _opt.choose(event)
                    Keys.onEscapePressed: event => { root._setOpen(false); root.forceActiveFocus(); event.accepted = true }
                    Keys.onUpPressed:     event => { root._focusOption(_opt.index - 1); event.accepted = true }
                    Keys.onDownPressed:   event => { root._focusOption(_opt.index + 1); event.accepted = true }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Home) {
                            root._focusOption(0)
                            event.accepted = true
                        } else if (event.key === Qt.Key_End) {
                            root._focusOption(root.model.length - 1)
                            event.accepted = true
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        anchors.topMargin: 3
                        anchors.bottomMargin: 3
                        radius: Theme.radiusControl - 2
                        antialiasing: true
                        // selection keeps its fill, keyboard focus keeps its ring; pointer hover is just the text brightening
                        color: _opt.active
                            ? Theme.mix(Theme.menuControl, Theme.accent, ShellSettings.neutralTheme ? 0.16 : 0.24)
                            : "transparent"
                        border.width: _opt.activeFocus ? 1 : 0
                        border.color: Theme.withAlpha(Theme.accent, 0.58)
                        opacity: _opt.active || _opt.activeFocus ? 1.0 : 0.0
                        Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast } }
                        Behavior on color { enabled: !ShellSettings.reduceMotion; ColorAnimation { duration: Motion.fast } }
                    }

                    // Indent to align with the header label
                    Text {
                        anchors.left:           parent.left
                        anchors.leftMargin:     (root.glyph.length > 0 ? 42 : 24)
                        anchors.right:          _check.left
                        anchors.rightMargin:    8
                        anchors.verticalCenter: parent.verticalCenter
                        text:       _opt.modelData.label
                        textFormat: Text.PlainText
                        elide:      Text.ElideRight
                        color:      _opt.active
                            ? Theme.text
                            : Theme.withAlpha(Theme.text, (_optHov.hovered || _opt.activeFocus) ? 0.92 : 0.72)
                        font.family:    _opt.optionFont
                        font.pixelSize: Settings.fontSize
                        font.weight:    _opt.active ? Font.DemiBold : Font.Normal
                        renderType:     Text.NativeRendering
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }
                    Text {
                        id: _check
                        anchors.right:          parent.right
                        anchors.rightMargin:    17
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        horizontalAlignment: Text.AlignHCenter
                        text: "󰄬"
                        color: Theme.accent
                        font.family: Settings.font
                        font.pixelSize: Settings.fontSize
                        renderType: Text.NativeRendering
                        opacity: _opt.active ? 0.90 : 0.0
                        Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast } }
                    }
                }
            }
            Item { width: parent.width; height: 4 }
        }
    }
}
