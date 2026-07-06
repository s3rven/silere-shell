pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"

Item {
    id: root

    property string glyph:       ""
    property string label:       ""
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

    width:  parent ? parent.width : 0
    // Header row height + expanded options height
    height: 44 + _options.height
    implicitHeight: height
    opacity: enabled ? 1.0 : 0.45
    Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.medium } }

    // ── Header row ──────────────────────────────────────────────────────
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

    HoverHandler { id: _hov; cursorShape: Qt.PointingHandCursor }
    TapHandler   { onTapped: root._toggleOpen() }

    RowHoverBg {
        width:  parent.width
        height: 44
        topRadius:    root.topRadius
        bottomRadius: root._open ? 0 : root.bottomRadius
        cardInset:    root.cardInset
        active:       _hov.hovered || root.activeFocus
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
        font.pixelSize: Settings.fontSize + 2
        renderType:     Text.NativeRendering
    }
    Item {
        id: _header
        anchors.top:    parent.top
        anchors.left:   _glyph.right; anchors.leftMargin: root.glyph.length > 0 ? 10 : 0
        anchors.right:  _chevronSlot.left; anchors.rightMargin: 8
        height: 44
        Text {
            anchors.left:           parent.left
            anchors.verticalCenter: parent.verticalCenter
            text:       root.label
            textFormat: Text.PlainText
            elide:      Text.ElideRight
            width:      Math.min(implicitWidth, parent.width)
            color:      Theme.withAlpha(Theme.text, 0.85)
            font.family:    Settings.font
            font.pixelSize: Settings.fontSize
            renderType:     Text.NativeRendering
        }
    }
    // Right slot: current value label + chevron
    Item {
        id: _chevronSlot
        anchors.right:          parent.right; anchors.rightMargin: 12
        anchors.verticalCenter: _header.verticalCenter
        width:  Math.min(_valText.implicitWidth + 18, Math.max(72, root.width * 0.38))
        height: 22

        Text {
            id: _valText
            anchors.left:           parent.left
            anchors.right:          parent.right
            anchors.rightMargin:    18
            anchors.verticalCenter: parent.verticalCenter
            text:           root._activeLabel
            textFormat:     Text.PlainText
            elide:          Text.ElideRight
            color:          Theme.withAlpha(Theme.subtext, 0.70)
            font.family:    Settings.font
            font.pixelSize: Settings.fontSize - 1
            renderType:     Text.NativeRendering
        }
        Text {
            anchors.right:          parent.right
            anchors.verticalCenter: parent.verticalCenter
            text:    "󰅀"
            rotation: root._open ? 180 : 0
            transformOrigin: Item.Center
            color:   Theme.withAlpha(Theme.subtext, 0.55)
            font.family:    Settings.font
            font.pixelSize: Settings.fontSize
            renderType:     Text.NativeRendering
            Behavior on rotation { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
        }
    }

    // ── Option list (expands below header) ──────────────────────────────
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
            y:       root._open ? 0 : -8
            opacity: root._open ? 1.0 : 0.0

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

                    width:  parent.width
                    height: 36

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
                            root._open = false
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

                    RowHoverBg {
                        anchors.fill: parent
                        // Only the last option rounds at the card bottom
                        bottomRadius: _opt.index === root.model.length - 1 ? root.bottomRadius : 0
                        cardInset:    root.cardInset
                        active:       _optHov.hovered || _opt.activeFocus
                        fillOpacity:  _opt.activeFocus ? 0.13 : 0.08
                    }

                    // Indent to align with the header label
                    Text {
                        anchors.left:           parent.left
                        anchors.leftMargin:     (root.glyph.length > 0 ? 42 : 24)
                        anchors.verticalCenter: parent.verticalCenter
                        text:       _opt.modelData.label
                        textFormat: Text.PlainText
                        color:      _opt.active
                            ? Theme.accent
                            : Theme.withAlpha(Theme.text, (_optHov.hovered || _opt.activeFocus) ? 0.90 : 0.70)
                        font.family:    Settings.font
                        font.pixelSize: Settings.fontSize
                        font.weight:    _opt.active ? Font.DemiBold : Font.Normal
                        renderType:     Text.NativeRendering
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }
                    // Left accent bar on active item
                    Rectangle {
                        anchors.left:           parent.left; anchors.leftMargin: root.cardInset + 1
                        anchors.verticalCenter: parent.verticalCenter
                        width:   3
                        height:  _opt.active ? 16 : 0
                        radius:  2
                        color:   Theme.accent
                        opacity: _opt.active ? 0.90 : 0.0
                        Behavior on height  { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
                        Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast } }
                    }
                }
            }
        }
    }
}
