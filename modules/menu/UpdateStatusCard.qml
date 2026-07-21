import QtQuick
import "../../config"
import "../../services"
import "../common"

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
    // busy can outlive the card being visible; lets callers park the spinner
    property bool animationActive: true

    property string primaryLabel: ""
    property string primaryGlyph: "󰓦"
    property bool primaryEnabled: true
    property bool primaryEmphasis: false
    property color primaryColor: Theme.accent
    property string secondaryLabel: ""
    property string secondaryGlyph: "󰑐"
    property string secondaryAccessibleName: "Refresh"
    property bool secondaryEnabled: true
    property bool secondaryShown: false

    // Drop the card chrome so this can sit as a row inside a shared SettingsCard.
    property bool flat: false

    signal primaryTriggered()
    signal secondaryTriggered()

    width: parent ? parent.width : 0
    implicitHeight: _col.implicitHeight
    height: implicitHeight
    radius: root.flat ? 0 : Theme.radiusControl
    antialiasing: true
    clip: true
    color: root.flat ? "transparent" : Theme.menuCard
    border.width: root.flat ? 0 : 1
    border.color: Theme.menuCardBorder

    Column {
        id: _col
        width: parent.width
        spacing: 0

        Item {
            id: _main
            width: parent.width
            height: 56

            Text {
                id: _g
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: _txt.verticalCenter
                width: 20
                horizontalAlignment: Text.AlignHCenter
                text: root.glyph
                color: root.statusColor
                font.family: Settings.font
                font.pixelSize: Settings.fontSize + 4
                renderType: Text.NativeRendering
                Behavior on color { ColorAnimation { duration: Motion.medium } }

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
                }
                Connections {
                    target: root
                    function onBusyChanged() { if (!root.busy) _rot.angle = 0 }
                    function onAnimationActiveChanged() { if (!root.animationActive) _rot.angle = 0 }
                }
            }

            Column {
                id: _txt
                anchors.left: _g.right
                anchors.leftMargin: 11
                anchors.right: _actions.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                Text {
                    id: _title
                    width: parent.width
                    text: root.title
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: Theme.text
                    font.family: Settings.font
                    font.pixelSize: Settings.fontSize
                    font.weight: Font.Medium
                    renderType: Text.NativeRendering
                }

                Item {
                    width: parent.width
                    height: Math.max(_status.implicitHeight, _sub.implicitHeight)

                    Text {
                        id: _status
                        anchors.left: parent.left
                        anchors.right: _sub.visible ? _sub.left : parent.right
                        anchors.rightMargin: _sub.visible ? 9 : 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.status
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Theme.withAlpha(root.statusColor, 0.9)
                        font.family: Settings.font
                        font.pixelSize: Settings.fontSize - 2
                        renderType: Text.NativeRendering
                        Behavior on color { ColorAnimation { duration: Motion.medium } }
                    }
                    Text {
                        id: _sub
                        visible: root.meta.length > 0
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, parent.width * 0.46)
                        horizontalAlignment: Text.AlignRight
                        text: "·  " + root.meta
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Theme.withAlpha(Theme.subtext, 0.5)
                        font.family: Settings.font
                        font.pixelSize: Settings.fontSize - 2
                        renderType: Text.NativeRendering
                    }
                }
            }

            Row {
                id: _actions
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                ActionButton {
                    visible: root.secondaryShown
                    width: contentWidth
                    height: 28
                    label: root.secondaryLabel
                    glyph: root.secondaryGlyph
                    accessibleName: root.secondaryAccessibleName
                    enabled: root.secondaryEnabled
                    onTriggered: root.secondaryTriggered()
                }

                ActionButton {
                    width: Math.max(contentWidth, 116)
                    height: 28
                    label: root.primaryLabel
                    glyph: root.primaryGlyph
                    enabled: root.primaryEnabled
                    emphasis: root.primaryEmphasis
                    accentColor: root.primaryColor
                    onTriggered: root.primaryTriggered()
                }
            }
        }

        // Pending summary or error, as an indented sub-note under the row.
        Item {
            id: _detailWrap
            visible: height > 0.5
            width: parent.width
            height: root.detail.length > 0 ? 4 * Math.ceil((_detailText.implicitHeight + 3 + 9) / 4) : 0
            clip: true

            Behavior on height {
                enabled: !ShellSettings.reduceMotion
                NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
            }

            Text {
                id: _detailText
                x: 45
                y: 3
                width: parent.width - 45 - 13
                text: root.detail
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                opacity: root.detail.length > 0 ? 1 : 0
                color: root.detailError
                    ? Theme.withAlpha(Theme.warning, 0.85)
                    : Theme.withAlpha(Theme.subtext, 0.58)
                font.family: Settings.font
                font.pixelSize: Settings.fontSize - 2
                lineHeight: 1.15
                renderType: Text.NativeRendering
                Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.fast } }
            }
        }
    }
}
