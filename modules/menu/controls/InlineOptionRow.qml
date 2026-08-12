import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Item {
    id: root

    property string glyph: ""
    property string label: ""
    property string status: ""
    property color accentColor: Theme.accent
    property bool selected: false
    property bool highlighted: false
    property bool warning: false
    // Dropdown choices use the same outlined, transparent-at-rest language as
    // ghost buttons. Other list consumers keep their edge-to-edge row surface.
    property bool ghost: false
    property bool interactive: true
    property string labelFontFamily: Settings.font
    property Component preview: null
    property var previewValue

    signal triggered()

    readonly property int rowHeight: Metrics.rowHeightFor(32)
    readonly property bool _hot: _hover.hovered || _tap.pressed
    readonly property int _surfaceInset: root.ghost ? 5 : 0

    function trigger(): void {
        if (root.enabled && root.interactive) root.triggered()
    }

    width: parent ? parent.width : 0
    implicitHeight: rowHeight
    height: implicitHeight
    opacity: root.enabled && root.interactive ? 1.0 : 0.48
    MotionBehavior on opacity {NumberAnimation { duration: Motion.medium } }

    HoverHandler {
        id: _hover
        enabled: root.enabled && root.interactive
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        id: _tap
        enabled: root.enabled && root.interactive
        onTapped: {
            root.trigger()
        }
    }

    Rectangle {
        id: _fill
        x: root._surfaceInset
        y: root.ghost ? 2 : 0
        width: Math.max(0, parent.width - root._surfaceInset * 2)
        height: Math.max(0, parent.height - (root.ghost ? 3 : 0))
        radius: root.ghost ? Theme.radiusField : 0
        antialiasing: root.ghost
        color: root.warning
            ? Theme.withAlpha(Theme.warning,
                root._hot ? 0.10 : root.selected ? 0.085 : 0.055)
            : root.selected
                ? root.ghost
                    ? (_tap.pressed
                        ? Theme.withAlpha(root.accentColor, 0.10)
                        : _hover.hovered
                            ? Theme.withAlpha(root.accentColor, 0.065)
                            : "transparent")
                    : Theme.withAlpha(root.accentColor,
                        ShellSettings.highContrast ? 0.14
                            : root._hot ? 0.105
                            : ShellSettings.neutralTheme ? 0.065 : 0.085)
                : root.highlighted
                    ? Theme.withAlpha(root.accentColor, root._hot ? 0.075 : 0.050)
                    : _tap.pressed ? Theme.withAlpha(Theme.text, 0.055)
                        : _hover.hovered ? Theme.withAlpha(Theme.text, 0.030)
                            : "transparent"
        ColorFade on color {}

        OutlineBorder {
            radius: _fill.radius
            outlineWidth: 1
            outlineColor: !root.ghost ? "transparent"
                    : root.selected
                        ? Theme.controlLineActive(root.accentColor)
                        : _hover.hovered
                            ? Theme.menuControlLineHot
                            : Theme.menuControlLine
            ColorFade on outlineColor {}
        }
    }

    ShellText {
        id: _glyph
        anchors.left: parent.left
        anchors.leftMargin: 14 + root._surfaceInset
        anchors.verticalCenter: parent.verticalCenter
        width: 18
        visible: root.preview === null
        horizontalAlignment: Text.AlignHCenter
        text: root.glyph
        color: root.warning ? Theme.warning
            : root.selected || root.highlighted ? root.accentColor
            : Theme.withAlpha(Theme.subtext, 0.78)
        font.pixelSize: Settings.iconSize + 1
        ColorFade on color {}
    }

    Loader {
        anchors.left: _glyph.left
        anchors.verticalCenter: parent.verticalCenter
        width: _glyph.width
        height: parent.height
        active: root.preview !== null
        sourceComponent: root.preview
        // the component is shared by every row, so it reads its subject off the Loader it lands in
        readonly property var optionValue: root.previewValue
    }

    ShellText {
        anchors.left: _glyph.right
        anchors.leftMargin: 10
        anchors.right: _status.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        elide: Text.ElideRight
        color: root.selected || root.highlighted ? Theme.text
            : Theme.withAlpha(Theme.text, root._hot ? 0.92 : 0.76)
        font.family: root.labelFontFamily
        font.pixelSize: Settings.fontSize
        font.weight: root.selected ? Font.DemiBold : Font.Normal
        ColorFade on color {}
    }

    ShellText {
        id: _status
        anchors.right: _check.left
        anchors.rightMargin: root.selected ? 6 : 0
        MotionBehavior on anchors.rightMargin { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, Math.max(0, root.width * 0.34))
        horizontalAlignment: Text.AlignRight
        text: root.status
        elide: Text.ElideRight
        color: root.warning ? Theme.warning
            : root.selected ? Theme.mix(root.accentColor, Theme.text, 0.14)
            : Theme.withAlpha(Theme.subtext, root._hot ? 0.70 : 0.54)
        font.pixelSize: Settings.fontCaption
        font.weight: root.warning || root.selected ? Font.Medium : Font.Normal
        ColorFade on color {}
    }

    ShellText {
        id: _check
        anchors.right: parent.right
        anchors.rightMargin: 12 + root._surfaceInset
        anchors.verticalCenter: parent.verticalCenter
        width: root.selected ? 18 : 0
        horizontalAlignment: Text.AlignHCenter
        text: "󰄬"
        color: root.warning ? Theme.warning : root.accentColor
        font.pixelSize: Settings.fontSize
        opacity: root.selected ? 0.90 : 0.0
        MotionBehavior on width { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
        MotionBehavior on opacity { NumberAnimation { duration: Motion.fast } }
    }
}
