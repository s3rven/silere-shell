import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Rectangle {
    id: root

    property string glyph: "󰚰"
    property string title: ""
    property string status: ""
    property string meta: ""
    property string detail: ""
    property bool   detailError: false
    property color statusColor: Theme.subtext
    property bool busy: false
    property bool animationActive: true

    property string primaryLabel: ""
    property string primaryGlyph: "󰓦"
    property bool primaryEnabled: true
    property bool primaryEmphasis: false
    property color primaryColor: Theme.accent
    property string secondaryGlyph: "󰑐"
    property string secondaryAccessibleName: "Refresh"
    property bool secondaryEnabled: true
    property bool secondaryShown: false

    readonly property bool _compactActions: width < 300

    signal primaryTriggered()
    signal secondaryTriggered()

    width: parent ? parent.width : 0
    implicitHeight: _col.implicitHeight
    height: implicitHeight
    radius: 0
    antialiasing: true
    clip: true
    color: "transparent"

    Column {
        id: _col
        width: parent.width
        spacing: 0

        Item {
            id: _main
            width: parent.width
            height: 56

            ShellText {
                id: _g
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: _txt.verticalCenter
                width: 18
                horizontalAlignment: Text.AlignHCenter
                text: root.glyph
                color: root.statusColor
                font.pixelSize: Settings.fontSize + 4
                MotionBehavior on color {
                    ColorAnimation { duration: Motion.medium }
                }

                transform: Rotation {
                    id: _rot
                    origin.x: _g.width / 2
                    origin.y: _g.height / 2
                    angle: 0
                }
                NumberAnimation {
                    target: _rot; property: "angle"
                    running: root.busy && root.animationActive && !ShellSettings.reduceMotion
                    loops: Animation.Infinite
                    from: 0; to: 360
                    duration: Motion.ms(1100)
                    onRunningChanged: if (!running) _rot.angle = 0
                }
            }

            Column {
                id: _txt
                anchors.left: _g.right
                anchors.leftMargin: 10
                anchors.right: _actions.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                ShellText {
                    id: _title
                    width: parent.width
                    text: root.title
                    elide: Text.ElideRight
                    color: Theme.text
                    font.pixelSize: Settings.fontSize
                    font.weight: Font.Medium
                }

                Item {
                    width: parent.width
                    height: Math.max(_status.implicitHeight, _sub.implicitHeight)

                    ShellText {
                        id: _status
                        anchors.left: parent.left
                        anchors.right: _sub.visible ? _sub.left : parent.right
                        anchors.rightMargin: _sub.visible ? 9 : 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.status
                        elide: Text.ElideRight
                        color: Theme.withAlpha(root.statusColor, 0.9)
                        font.pixelSize: Settings.fontSize - 2
                        MotionBehavior on color {
                            ColorAnimation { duration: Motion.medium }
                        }
                    }
                    ShellText {
                        id: _sub
                        visible: root.meta.length > 0
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, parent.width * 0.46)
                        horizontalAlignment: Text.AlignRight
                        text: "·  " + root.meta
                        elide: Text.ElideRight
                        color: Theme.withAlpha(Theme.subtext, 0.5)
                        font.pixelSize: Settings.fontSize - 2
                    }
                }
            }

            Row {
                id: _actions
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                ActionButton {
                    visible: root.secondaryShown
                    height: 28
                    glyph: root.secondaryGlyph
                    accessibleName: root.secondaryAccessibleName
                    enabled: root.secondaryEnabled
                    onTriggered: root.secondaryTriggered()
                }

                ActionButton {
                    height: 28
                    label: root._compactActions ? "" : root.primaryLabel
                    glyph: root.primaryGlyph
                    accessibleName: root.primaryLabel
                    enabled: root.primaryEnabled
                    emphasis: root.primaryEmphasis
                    accentColor: root.primaryColor
                    onTriggered: root.primaryTriggered()
                }
            }
        }

        Item {
            id: _detailWrap
            visible: height > 0.5
            width: parent.width
            height: root.detail.length > 0 ? 4 * Math.ceil((_detailText.implicitHeight + 3 + 9) / 4) : 0
            clip: true

            MotionBehavior on height {
                NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
            }

            ShellText {
                id: _detailText
                x: 42
                y: 3
                width: parent.width - 42 - 12
                text: root.detail
                wrapMode: Text.WordWrap
                opacity: root.detail.length > 0 ? 1 : 0
                color: root.detailError
                    ? Theme.withAlpha(Theme.warning, 0.85)
                    : Theme.withAlpha(Theme.subtext, 0.58)
                font.pixelSize: Settings.fontSize - 2
                lineHeight: 1.15
                MotionBehavior on opacity {NumberAnimation { duration: Motion.fast } }
            }
        }
    }
}
