import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Item {
    id: root

    property string glyph: ""
    property string label: ""
    property string accessiblePrefix: ""
    property string status: ""
    property color accentColor: Theme.accent
    property bool selected: false
    property bool highlighted: false
    property bool warning: false
    // an arm-to-confirm prompt and a refused connection are both "attention", but one is
    // asking and the other is reporting; they must not share a colour
    property bool failed: false
    property bool interactive: true
    // same contract as MenuRow: the container says which end of the card this row is at,
    // and the highlight takes that corner instead of inventing one of its own
    property real topRadius: 0
    property real bottomRadius: 0
    property real cardInset: 1
    property string labelFontFamily: Settings.font
    property Component preview: null
    property var previewValue

    signal triggered()

    readonly property int rowHeight: Metrics.rowHeightFor(32)
    // a pooled row rebinds holding the previous row's values: gate every animation below
    property bool motionReady: true
    // the gate must already be shut when the row rebinds, which happens before onReused;
    // stop the pending settle too, or it reopens the gate while the row sits in the pool
    ListView.onPooled: { _settle.stop(); root.motionReady = false }
    ListView.onReused: { root.motionReady = false; _settle.restart() }
    Timer { id: _settle; interval: 0; onTriggered: root.motionReady = true }
    Component.onDestruction: _settle.stop()
    readonly property bool _hot: _hover.hovered || _tap.pressed
    readonly property bool  _attentive: root.warning || root.failed
    readonly property color _attention: root.failed ? Theme.error : Theme.warning

    function trigger(): void {
        if (root.enabled && root.interactive) root.triggered()
    }

    width: parent ? parent.width : 0
    implicitHeight: rowHeight
    height: implicitHeight
    opacity: root.enabled && root.interactive ? 1.0 : Theme.disabledOpacity
    MotionBehavior on opacity { gate: root.motionReady; NumberAnimation { duration: Motion.medium } }

    Accessible.role: root.accessiblePrefix.length > 0
        ? Accessible.RadioButton : Accessible.Button
    Accessible.name: root.accessiblePrefix.length > 0
        ? root.accessiblePrefix + ": " + root.label : root.label
    Accessible.description: root.status
    Accessible.focusable: root.enabled && root.interactive
    Accessible.checkable: root.accessiblePrefix.length > 0
    Accessible.checked: root.accessiblePrefix.length > 0 && root.selected
    Accessible.selected: root.selected
    Accessible.onPressAction: root.trigger()

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
        readonly property real _topR: Math.max(0, root.topRadius - root.cardInset)
        readonly property real _botR: Math.max(0, root.bottomRadius - root.cardInset)

        x: root.cardInset
        y: root.topRadius > 0 ? root.cardInset : 0
        width:  Math.max(0, root.width - root.cardInset * 2)
        height: Math.max(0, root.height
            - (root.topRadius > 0 ? root.cardInset : 0)
            - (root.bottomRadius > 0 ? root.cardInset : 0))

        topLeftRadius:     _topR
        topRightRadius:    _topR
        bottomLeftRadius:  _botR
        bottomRightRadius: _botR
        antialiasing: _topR > 0 || _botR > 0

        color: root._attentive
            ? Theme.withAlpha(root._attention,
                root._hot ? 0.10 : root.selected ? 0.085 : 0.055)
            : root.selected
                ? Theme.withAlpha(root.accentColor,
                    ShellSettings.highContrast ? 0.14
                        : root._hot ? 0.105
                        : ShellSettings.neutralTheme ? 0.065 : 0.085)
                : root.highlighted
                    ? Theme.withAlpha(root.accentColor, root._hot ? 0.075 : 0.050)
                    : _tap.pressed ? Theme.withAlpha(Theme.text, 0.055)
                        : _hover.hovered ? Theme.withAlpha(Theme.text, 0.030)
                            : "transparent"
        ColorFade on color { gate: root.motionReady }
    }

    ShellText {
        id: _glyph
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        width: 18
        visible: root.preview === null
        horizontalAlignment: Text.AlignHCenter
        text: root.glyph
        color: root._attentive ? root._attention
            : root.selected || root.highlighted ? root.accentColor
            : Theme.withAlpha(Theme.subtext, 0.78)
        font.pixelSize: Settings.iconSize + 1
        ColorFade on color { gate: root.motionReady }
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
        ColorFade on color { gate: root.motionReady }
    }

    ShellText {
        id: _status
        anchors.right: _check.left
        anchors.rightMargin: root.selected ? 6 : 0
        MotionBehavior on anchors.rightMargin { gate: root.motionReady; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, Math.max(0, root.width * 0.34))
        horizontalAlignment: Text.AlignRight
        text: root.status
        elide: Text.ElideRight
        color: root._attentive ? root._attention
            : root.selected ? Theme.mix(root.accentColor, Theme.text, 0.14)
            : Theme.withAlpha(Theme.subtext, root._hot ? 0.70 : 0.54)
        font.pixelSize: Settings.fontCaption
        font.weight: root._attentive || root.selected ? Font.Medium : Font.Normal
        ColorFade on color { gate: root.motionReady }
    }

    ShellText {
        id: _check
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: root.selected ? 18 : 0
        horizontalAlignment: Text.AlignHCenter
        text: "󰄬"
        color: root._attentive ? root._attention : root.accentColor
        font.pixelSize: Settings.fontSize
        opacity: root.selected ? 0.90 : 0.0
        MotionBehavior on width { gate: root.motionReady; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
        MotionBehavior on opacity { gate: root.motionReady; NumberAnimation { duration: Motion.fast } }
    }
}
