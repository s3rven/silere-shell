pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../common"

Item {
    id: root

    property string glyph:       ""
    property string label:       ""
    property string description: ""
    property var    model:       []
    property var    currentValue
    property real   topRadius:    0
    property real   bottomRadius: 0
    property real   cardInset:    1
    property real   cardLeftBleed: 0
    readonly property int _optionsCapH: 224
    readonly property bool _hasDesc: description.length > 0
    readonly property int _headerH: _hasDesc
        ? Math.max(56, 4 * Math.ceil((20 + _headerText.implicitHeight) / 4))
        : 44

    signal chosen(var value)

    property bool _open: false

    function _focusOption(index: int): void {
        if (!_open || _optRepeater.count <= 0) return
        const i = Math.max(0, Math.min(_optRepeater.count - 1, index))
        const item = _optRepeater.itemAt(i)
        if (item) {
            item.forceActiveFocus()
            const viewportH = Math.min(_optCol.implicitHeight, root._optionsCapH)
            if (item.y < _options.contentY + 4)
                _options.contentY = Math.max(0, item.y - 4)
            else if (item.y + item.height > _options.contentY + viewportH - 4)
                _options.contentY = Math.min(
                    Math.max(0, _options.contentHeight - viewportH),
                    item.y + item.height - viewportH + 4)
        }
    }

    function _focusActiveOption(): void {
        _focusOption(Math.max(0, _activeIndex))
    }

    function _setOpen(next: bool): void {
        if (next && !root.enabled) return
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

    onEnabledChanged: if (!enabled) _setOpen(false)

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
    height: _headerH + _options.height
    implicitHeight: height
    opacity: enabled ? 1.0 : 0.45
    MotionBehavior on opacity {NumberAnimation { duration: Motion.medium } }

    activeFocusOnTab: root.enabled
    Accessible.role: Accessible.ComboBox
    Accessible.name: root.label
    Accessible.description: root.description.length > 0
        ? root.description + ". " + root._activeLabel : root._activeLabel
    Accessible.onPressAction: root._toggleOpen()
    Keys.onSpacePressed: event => { if (!event.isAutoRepeat) root._toggleOpen(); event.accepted = true }
    Keys.onReturnPressed: event => { if (!event.isAutoRepeat) root._toggleOpen(); event.accepted = true }
    Keys.onEnterPressed: event => { if (!event.isAutoRepeat) root._toggleOpen(); event.accepted = true }
    Keys.onEscapePressed: event => {
        if (root._open) {
            root._setOpen(false)
            event.accepted = true
        } else {
            event.accepted = false
        }
    }
    Keys.onDownPressed: event => { root._setOpen(true); event.accepted = true }
    Keys.onUpPressed: event => { root._setOpen(true); event.accepted = true }

    Item {
        id: _headerHitArea
        width: parent.width
        height: root._headerH

        HoverHandler {
            id: _hov
            enabled: root.enabled
            cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        }
        TapHandler {
            enabled: root.enabled
            onTapped: root._toggleOpen()
        }
    }

    RowHoverBg {
        width:  parent.width
        height: root._headerH
        topRadius:    root.topRadius
        bottomRadius: root._open ? 0 : root.bottomRadius
        cardInset:    root.cardInset
        leftBleed:    root.cardLeftBleed
        active:       (_hov.hovered || root.activeFocus) && root.enabled
        focusActive:  root.activeFocus && root.enabled
        fillOpacity:  root.activeFocus ? 0.13 : 0.08
    }

    ShellText {
        id: _glyph
        anchors.left:           parent.left; anchors.leftMargin: 14
        anchors.verticalCenter: _header.verticalCenter
        width: root.glyph.length > 0 ? 18 : 0
        horizontalAlignment: Text.AlignHCenter
        text:           root.glyph
        color:          Theme.withAlpha(Theme.subtext, 0.85)
        font.pixelSize: Settings.iconSize + 2
    }
    Item {
        id: _header
        anchors.top:    parent.top
        anchors.left:   _glyph.right; anchors.leftMargin: root.glyph.length > 0 ? 10 : 0
        anchors.right:  _chevronSlot.left; anchors.rightMargin: 10
        height: root._headerH
        Column {
            id: _headerText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            ShellText {
                id: _label
                width: parent.width
                text: root.label
                elide: Text.ElideRight
                color: Theme.withAlpha(Theme.text, 0.85)
                font.pixelSize: Settings.fontSize
            }
            ShellText {
                visible: root._hasDesc
                width: parent.width
                text: root.description
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: Theme.withAlpha(Theme.subtext, 0.52)
                font.pixelSize: Math.max(8, Settings.fontSize - 2)
                lineHeight: 1.1
            }
        }
    }
    Item {
        id: _chevronSlot
        anchors.right:          parent.right; anchors.rightMargin: 12
        anchors.verticalCenter: _header.verticalCenter
        width:  Math.min(_valText.implicitWidth + 34, Math.max(78, root.width * 0.40))
        height: 26

        Rectangle {
            id: _chevronFill
            anchors.fill: parent
            radius: Theme.radiusControl - 2
            antialiasing: true
            color: Theme.mix(Theme.menuControl, root._open ? Theme.accent : Theme.text,
                root._open ? (ShellSettings.neutralTheme ? 0.16 : 0.24) : 0.018)
            MotionBehavior on color {ColorAnimation { duration: Motion.fast } }

            readonly property color _outlineColor: root._open
                ? Theme.withAlpha(Theme.accent, ShellSettings.highContrast ? 0.64 : 0.46)
                : (_hov.hovered || root.activeFocus ? Theme.withAlpha(Theme.accent, 0.34) : Theme.menuControlLine)

            OutlineBorder {
                radius: _chevronFill.radius
                outlineColor: _chevronFill._outlineColor
                MotionBehavior on outlineColor {ColorAnimation { duration: Motion.fast } }
            }
        }

        ShellText {
            id: _valText
            anchors.left:           parent.left
            anchors.leftMargin:     9
            anchors.right:          parent.right
            anchors.rightMargin:    21
            anchors.verticalCenter: parent.verticalCenter
            text:           root._activeLabel
            elide:          Text.ElideRight
            color:          root._open ? Theme.text : Theme.withAlpha(Theme.subtext, 0.76)
            font.family:    root._activeFont
            font.pixelSize: Settings.fontSize - 1
            font.weight:    root._open ? Font.DemiBold : Font.Medium
            MotionBehavior on color {
                ColorAnimation { duration: Motion.fast }
            }
        }
        ShellText {
            anchors.right:          parent.right
            anchors.rightMargin:    7
            anchors.verticalCenter: parent.verticalCenter
            text:    "󰅀"
            rotation: root._open ? 180 : 0
            transformOrigin: Item.Center
            color:   root._open ? Theme.accent : Theme.withAlpha(Theme.subtext, 0.58)
            font.pixelSize: Settings.fontSize
            MotionBehavior on rotation {NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }
            MotionBehavior on color {
                ColorAnimation { duration: Motion.fast }
            }
        }
    }

    Flickable {
        id: _options
        anchors.top:  parent.top; anchors.topMargin: root._headerH
        anchors.left: parent.left
        anchors.right: parent.right

        height: root._open
            ? Math.min(_optCol.implicitHeight, root._optionsCapH)
            : 0
        contentWidth: width
        contentHeight: _optCol.implicitHeight
        boundsMovement: Flickable.StopAtBounds
        flickDeceleration: 1800
        maximumFlickVelocity: 1800
        interactive: contentHeight > height + 1
        clip:    true
        visible: height > 0.5

        MotionBehavior on height {
            NumberAnimation {
                duration: root._open ? Motion.medium : Motion.fast
                easing.type: root._open ? Easing.OutQuart : Easing.InCubic
            }
        }

        Column {
            id: _optCol
            width: parent.width
            y: 0
            opacity: root._open ? 1.0 : 0.0

            Hairline {
                x: 12
                width: parent.width - 24
                color: Theme.menuDivider
            }
            Item { width: parent.width; height: 3 }

            MotionBehavior on opacity {
                NumberAnimation {
                    duration: Motion.fast
                    easing.type: root._open ? Easing.OutCubic : Easing.InCubic
                }
            }

            Repeater {
                id: _optRepeater
                // The font picker can contain dozens of entries. Keep closed
                // dropdown delegates out of the scene, including while a
                // close animation is no longer visible.
                model: root._open || _options.height > 0.5 ? root.model : []
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
                            root._setOpen(false)
                            root.forceActiveFocus()
                        }
                    }
                    activeFocusOnTab: root.enabled && root._open
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: root.label + ": " + String(_opt.modelData.label ?? "")
                    Accessible.checked: _opt.active
                    Accessible.onPressAction: {
                        root.chosen(_opt.modelData.value)
                        root._setOpen(false)
                        root.forceActiveFocus()
                    }
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
                        id: _optFill
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        anchors.topMargin: 3
                        anchors.bottomMargin: 3
                        radius: Theme.radiusControl - 2
                        antialiasing: true
                        color: _opt.active
                            ? Theme.mix(Theme.menuControl, Theme.accent, ShellSettings.neutralTheme ? 0.16 : 0.24)
                            : _optHov.hovered || _opt.activeFocus
                                ? Theme.withAlpha(Theme.text, 0.035)
                                : "transparent"
                        opacity: _opt.active || _opt.activeFocus || _optHov.hovered ? 1.0 : 0.0
                        MotionBehavior on opacity {NumberAnimation { duration: Motion.fast } }
                        MotionBehavior on color {ColorAnimation { duration: Motion.fast } }

                        OutlineBorder {
                            radius: _optFill.radius
                            outlineColor: _opt.activeFocus ? Theme.withAlpha(Theme.accent, 0.58) : "transparent"
                        }
                    }

                    ShellText {
                        anchors.left:           parent.left
                        anchors.leftMargin:     (root.glyph.length > 0 ? 42 : 24)
                        anchors.right:          _check.left
                        anchors.rightMargin:    8
                        anchors.verticalCenter: parent.verticalCenter
                        text:       _opt.modelData.label
                        elide:      Text.ElideRight
                        color:      _opt.active
                            ? Theme.text
                            : Theme.withAlpha(Theme.text, (_optHov.hovered || _opt.activeFocus) ? 0.92 : 0.72)
                        font.family:    _opt.optionFont
                        font.pixelSize: Settings.fontSize
                        font.weight:    _opt.active ? Font.DemiBold : Font.Normal
                        MotionBehavior on color {
                            ColorAnimation { duration: Motion.fast }
                        }
                    }
                    ShellText {
                        id: _check
                        anchors.right:          parent.right
                        anchors.rightMargin:    17
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        horizontalAlignment: Text.AlignHCenter
                        text: "󰄬"
                        color: Theme.accent
                        font.pixelSize: Settings.fontSize
                        opacity: _opt.active ? 0.90 : 0.0
                        MotionBehavior on opacity {NumberAnimation { duration: Motion.fast } }
                    }
                }
            }
            Item { width: parent.width; height: 4 }
        }
    }

    MenuScrollThumb {
        list: _options
        shown: root._open
        trackInset: 4
        rightInset: 3
        minimumLength: 18
        color: Theme.subtext
        idleOpacity: 0.34
        movingOpacity: 0.56
    }
}
