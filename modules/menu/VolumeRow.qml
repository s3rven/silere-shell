pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"

// volume slider with an inline output-device dropdown: the chevron expands the device list beneath the slider, in the card. option styling mirrors SelectRow
Item {
    id: root

    property bool open: false
    property real topRadius:    0
    property real bottomRadius: 0
    property real cardInset:    1

    width: parent ? parent.width : 0
    implicitHeight: _slider.height + _options.height
    height: implicitHeight

    function _focusCurrentSink(): void {
        if (!root.open) return
        for (let i = 0; i < _sinkRepeater.count; i++) {
            const item = _sinkRepeater.itemAt(i)
            if (item && item.active) {
                item.forceActiveFocus()
                return
            }
        }
        const first = _sinkRepeater.itemAt(0)
        if (first) first.forceActiveFocus()
    }

    function _focusSinkIndex(index: int): void {
        if (!root.open || _sinkRepeater.count <= 0) return
        const i = Math.max(0, Math.min(_sinkRepeater.count - 1, index))
        const item = _sinkRepeater.itemAt(i)
        if (item) item.forceActiveFocus()
    }

    // Fold the dropdown away if the extra devices vanish.
    Connections {
        target: Audio
        function onSinkCountChanged() { if (Audio.sinkCount <= 1) root.open = false }
    }

    QuickSlider {
        id: _slider
        y: 0
        width: parent.width
        topRadius:    root.topRadius
        bottomRadius: root.open ? 0 : root.bottomRadius
        cardInset:    root.cardInset
        glyph: Audio.icon
        wheelKey: "volume"
        accessibleName: "Volume"
        value: Audio.uiVolume
        valueText: Audio.label
        glyphClickable: true
        expandable: Audio.sinkCount > 1
        expanded: root.open
        onGlyphClicked: Audio.toggleMute()
        onExpandToggled: {
            root.open = !root.open
            if (root.open) Qt.callLater(root._focusCurrentSink)
        }
        onMoved: (v) => Audio.setVolume(v)
    }

    Item {
        id: _options
        anchors.top: _slider.bottom
        width: parent.width
        height: root.open ? _optCol.implicitHeight + 4 : 0
        clip: true
        visible: height > 0.5

        Behavior on height {
            enabled: !ShellSettings.reduceMotion
            NumberAnimation {
                duration:    root.open ? Motion.medium : Motion.fast
                easing.type: root.open ? Easing.OutQuart : Easing.InCubic
            }
        }

        Column {
            id: _optCol
            width: parent.width
            y:       root.open ? 0 : -8
            opacity: root.open ? 1.0 : 0.0

            Behavior on y {
                enabled: !ShellSettings.reduceMotion
                NumberAnimation {
                    duration:    root.open ? Motion.medium : Motion.fast
                    easing.type: root.open ? Easing.OutQuart : Easing.InCubic
                }
            }
            Behavior on opacity {
                enabled: !ShellSettings.reduceMotion
                NumberAnimation {
                    duration:    root.open ? Motion.medium : Motion.fast
                    easing.type: root.open ? Easing.OutCubic : Easing.InCubic
                }
            }

            Repeater {
                id: _sinkRepeater
                model: root.open ? Audio.sinkModel : []
                delegate: Item {
                    id: _opt
                    required property var modelData
                    required property int index
                    readonly property bool active: modelData.value === Audio.sink

                    width:  _optCol.width
                    height: 36

                    function _choose(): void {
                        Audio.setSink(_opt.modelData.value)
                        root.open = false
                        _slider.forceActiveFocus()
                    }

                    Accessible.role: Accessible.ListItem
                    Accessible.name: _opt.modelData.label
                    Accessible.description: _opt.active ? "Current output" : "Output device"
                    activeFocusOnTab: root.open
                    Keys.onSpacePressed:  event => { if (!event.isAutoRepeat) _opt._choose(); event.accepted = true }
                    Keys.onReturnPressed: event => { if (!event.isAutoRepeat) _opt._choose(); event.accepted = true }
                    Keys.onEnterPressed:  event => { if (!event.isAutoRepeat) _opt._choose(); event.accepted = true }
                    Keys.onEscapePressed: event => { root.open = false; _slider.forceActiveFocus(); event.accepted = true }
                    Keys.onUpPressed:     event => { root._focusSinkIndex(_opt.index - 1); event.accepted = true }
                    Keys.onDownPressed:   event => { root._focusSinkIndex(_opt.index + 1); event.accepted = true }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Home) {
                            root._focusSinkIndex(0)
                            event.accepted = true
                        } else if (event.key === Qt.Key_End) {
                            root._focusSinkIndex(_sinkRepeater.count - 1)
                            event.accepted = true
                        }
                    }

                    HoverHandler { id: _optHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: _opt._choose() }

                    RowHoverBg {
                        anchors.fill: parent
                        bottomRadius: _opt.index === Audio.sinkModel.length - 1 ? root.bottomRadius : 0
                        cardInset:    root.cardInset
                        active:       _optHov.hovered || _opt.activeFocus
                        focusActive:  _opt.activeFocus
                        fillOpacity:  _opt.activeFocus ? 0.13 : 0.08
                    }

                    Rectangle {
                        anchors.left: parent.left; anchors.leftMargin: 2
                        anchors.verticalCenter: parent.verticalCenter
                        width:   3
                        height:  _opt.active ? 16 : 0
                        radius:  2
                        color:   Theme.accent
                        opacity: _opt.active ? 0.90 : 0.0
                        Behavior on height  { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
                        Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast } }
                    }

                    Text {
                        anchors.left: parent.left;  anchors.leftMargin: 42
                        anchors.right: parent.right; anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text:       _opt.modelData.label
                        textFormat: Text.PlainText
                        elide:      Text.ElideRight
                        color: _opt.active
                            ? Theme.accent
                            : Theme.withAlpha(Theme.text, (_optHov.hovered || _opt.activeFocus) ? 0.90 : 0.70)
                        font.family:    Settings.font
                        font.pixelSize: Settings.fontSize
                        font.weight:    _opt.active ? Font.DemiBold : Font.Normal
                        renderType:     Text.NativeRendering
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }
                }
            }
        }
    }
}
