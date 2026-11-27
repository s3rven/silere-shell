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
    readonly property color _statusInk: Theme.inkFor(root.statusColor)
    property bool busy: false
    property bool animationActive: true

    property string primaryLabel: ""
    property string primaryGlyph: "󰓦"
    property bool primaryEnabled: true
    property bool primaryEmphasis: false
    property color primaryColor: Theme.accent
    property string secondaryGlyph: "󰑐"
    property string secondaryLabel: "Refresh"
    property bool secondaryEnabled: true
    property bool secondaryShown: false
    readonly property bool layoutPresent: visible

    readonly property int _textLeft: 14 + Metrics.glyphSlotWidth + 10
    // leave room for the status to read as a sentence before putting actions beside it
    readonly property bool _stackActions: width - _textLeft - 24 - _actions.preferredWidth
        < Settings.fontSize * 10

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

        Item {
            id: _main
            readonly property real summaryHeight: Math.max(Metrics.rowHeightFor(56),
                Metrics.snap4Up(_txt.implicitHeight + 20))

            width: parent.width
            height: summaryHeight + (root._stackActions ? _actions.height + 8 : 0)

            ShellText {
                id: _g
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: _txt.verticalCenter
                width: Metrics.glyphSlotWidth
                horizontalAlignment: Text.AlignHCenter
                text: root.glyph
                color: root._statusInk
                font.pixelSize: Settings.fontSize + 4
                ColorFade on color { duration: Motion.medium }

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
                x: root._textLeft
                y: (_main.summaryHeight - height) / 2
                width: Math.max(0, (root._stackActions ? _main.width : _actions.x) - x - 12)
                spacing: 3

                Item {
                    id: _heading
                    readonly property bool hasMeta: root.meta.length > 0
                    readonly property bool inlineMeta: hasMeta
                        && _title.implicitWidth + 8 + _sub.implicitWidth <= width

                    width: parent.width
                    height: hasMeta ? Math.max(_title.height, _sub.y + _sub.height) : _title.height

                    ShellText {
                        id: _title
                        width: parent.width
                        text: root.title
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        color: Theme.text
                        font.pixelSize: Settings.fontSize
                        font.weight: Font.Medium
                    }
                    ShellText {
                        id: _sub
                        visible: _heading.hasMeta
                        x: _heading.inlineMeta ? _title.implicitWidth + 8 : 0
                        y: _heading.inlineMeta ? _title.baselineOffset - baselineOffset : _title.height + 2
                        width: Math.max(0, parent.width - x)
                        text: root.meta
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        color: Theme.menuTextQuiet
                        font.pixelSize: Settings.fontCaption
                    }
                }

                ShellText {
                    width: parent.width
                    text: root.status
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    color: Theme.withAlpha(root._statusInk, 0.9)
                    font.pixelSize: Settings.fontCaption
                    ColorFade on color { duration: Motion.medium }
                }
            }

            Flow {
                id: _actions
                readonly property real preferredWidth: _primary.width
                    + (root.secondaryShown ? _refresh.width + spacing : 0)

                anchors.right: parent.right
                anchors.rightMargin: 12
                y: root._stackActions ? _main.summaryHeight : (_main.summaryHeight - height) / 2
                width: Math.max(0, Math.min(preferredWidth, _main.width - 24))
                spacing: 8

                ActionButton {
                    id: _refresh
                    visible: root.secondaryShown
                    height: Metrics.rowHeightFor(28)
                    glyph: root.secondaryGlyph
                    accessibleName: root.secondaryLabel
                    enabled: root.secondaryEnabled
                    onTriggered: root.secondaryTriggered()
                }

                ActionButton {
                    id: _primary
                    height: Metrics.rowHeightFor(28)
                    label: root.primaryLabel
                    accessibleName: root.primaryLabel
                    glyph: root.primaryGlyph
                    enabled: root.primaryEnabled
                    emphasis: root.primaryEmphasis
                    accentColor: root.primaryColor
                    onTriggered: root.primaryTriggered()
                }
            }
        }

        Item {
            visible: height > 0.5
            width: parent.width
            height: root.detail.length > 0 ? 4 * Math.ceil((_detailText.implicitHeight + 3 + 9) / 4) : 0
            clip: true

            MotionBehavior on height {
                NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
            }

            ShellText {
                id: _detailText
                x: root._textLeft
                y: 3
                width: parent.width - x - 12
                text: root.detail
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                opacity: root.detail.length > 0 ? 1 : 0
                color: root.detailError
                    ? Theme.withAlpha(Theme.warning, 0.85)
                    : Theme.menuTextDetail
                font.pixelSize: Settings.fontCaption
                lineHeight: 1.15
                MotionBehavior on opacity {NumberAnimation { duration: Motion.fast } }
            }
        }
    }
}
