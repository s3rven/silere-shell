import QtQuick
import "../../config"
import "../../services"

Rectangle {
    id: root

    property string glyph: "󰚰"
    property string title: ""
    property string status: ""
    property string meta: ""
    property string checkedText: ""
    property string detail: ""
    property bool   detailError: false
    property color statusColor: Theme.subtext
    property bool busy: false

    property string primaryLabel: ""
    property string primaryGlyph: "󰓦"
    property bool primaryEnabled: true
    property bool primaryEmphasis: false
    property color primaryColor: Theme.accent
    property string secondaryLabel: ""
    property string secondaryGlyph: "󰑐"
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
            height: 40

            Text {
                id: _g
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                horizontalAlignment: Text.AlignHCenter
                text: root.glyph
                color: root.statusColor
                font.family: Settings.font
                font.pixelSize: Settings.fontSize + 3
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
                    running: root.busy && !ShellSettings.reduceMotion
                    loops: Animation.Infinite
                    from: 0; to: 360
                    duration: Motion.ms(1100)
                }
                Connections {
                    target: root
                    function onBusyChanged() { if (!root.busy) _rot.angle = 0 }
                }
            }

            Column {
                id: _txt
                anchors.left: _g.right
                anchors.leftMargin: 9
                anchors.right: _actions.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Item {
                    width: parent.width
                    height: _title.implicitHeight

                    Text {
                        id: _title
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, parent.width - (_meta.visible ? _meta.width + 7 : 0))
                        text: root.title
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Theme.text
                        font.family: Settings.font
                        font.pixelSize: Settings.fontSize
                        font.weight: Font.Medium
                        renderType: Text.NativeRendering
                    }
                    Text {
                        id: _meta
                        visible: root.meta.length > 0
                        anchors.left: _title.right
                        anchors.leftMargin: 7
                        anchors.baseline: _title.baseline
                        width: Math.min(implicitWidth, parent.width * 0.45)
                        text: root.meta
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Theme.withAlpha(Theme.subtext, 0.55)
                        font.family: Settings.font
                        font.pixelSize: Settings.fontSize - 3
                        renderType: Text.NativeRendering
                    }
                }

                Item {
                    width: parent.width
                    height: _status.implicitHeight

                    Text {
                        id: _status
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, parent.width - (_checked.visible ? _checked.width + 8 : 0))
                        text: root.status
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Theme.withAlpha(root.statusColor, 0.85)
                        font.family: Settings.font
                        font.pixelSize: Settings.fontSize - 2
                        renderType: Text.NativeRendering
                        Behavior on color { ColorAnimation { duration: Motion.medium } }
                    }
                    Text {
                        id: _checked
                        visible: root.checkedText.length > 0
                        anchors.right: parent.right
                        anchors.baseline: _status.baseline
                        width: Math.min(implicitWidth, parent.width * 0.5)
                        text: root.checkedText
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Theme.withAlpha(Theme.subtext, 0.42)
                        font.family: Settings.font
                        font.pixelSize: Settings.fontSize - 3
                        renderType: Text.NativeRendering
                    }
                }
            }

            Row {
                id: _actions
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                SettingsActionButton {
                    visible: root.secondaryShown
                    width: contentWidth
                    height: 28
                    label: root.secondaryLabel
                    glyph: root.secondaryGlyph
                    enabled: root.secondaryEnabled
                    onTriggered: root.secondaryTriggered()
                }

                SettingsActionButton {
                    width: contentWidth
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
            visible: root.detail.length > 0
            width: parent.width
            height: visible ? 4 * Math.ceil((_detailText.implicitHeight + 3 + 9) / 4) : 0

            Text {
                id: _detailText
                x: 41
                y: 3
                width: parent.width - 41 - 13
                text: root.detail
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: root.detailError
                    ? Theme.withAlpha(Theme.warning, 0.85)
                    : Theme.withAlpha(Theme.subtext, 0.58)
                font.family: Settings.font
                font.pixelSize: Settings.fontSize - 2
                lineHeight: 1.15
                renderType: Text.NativeRendering
            }
        }
    }
}
