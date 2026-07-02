pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"

// Volume slider with the output-device dropdown built in: the chevron on the
// row expands the device list inline, directly beneath the slider, within the
// card. Option styling mirrors SelectRow.
Item {
    id: root

    property bool open: false
    property real topRadius:    0
    property real bottomRadius: 0
    property real cardInset:    1

    width: parent ? parent.width : 0
    implicitHeight: _slider.height + _options.height
    height: implicitHeight

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
        onExpandToggled: root.open = !root.open
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
                model: Audio.sinkModel
                delegate: Item {
                    id: _opt
                    required property var modelData
                    required property int index
                    readonly property bool active: modelData.value === Audio.sink

                    width:  _optCol.width
                    height: 36

                    Accessible.role: Accessible.ListItem
                    Accessible.name: _opt.modelData.label
                    Accessible.description: _opt.active ? "Current output" : "Output device"

                    HoverHandler { id: _optHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { Audio.setSink(_opt.modelData.value); root.open = false } }

                    RowHoverBg {
                        anchors.fill: parent
                        bottomRadius: _opt.index === Audio.sinkModel.length - 1 ? root.bottomRadius : 0
                        cardInset:    root.cardInset
                        active:       _optHov.hovered
                        fillOpacity:  0.08
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
                            : Theme.withAlpha(Theme.text, _optHov.hovered ? 0.90 : 0.70)
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
