import QtQuick
import "../../config"

Item {
    id: root

    property alias text: _label.text
    property color color: Theme.text
    property bool  expanded: true
    // fixed-width floor: ticking digits re-hint per pair under fractional scaling and the +-1px wobble walks the whole bar once a second
    property string reserveText: ""
    property bool _ready: false

    Component.onCompleted: Qt.callLater(function() {
        if (root) root._ready = true
    })

    TextMetrics {
        id: _reserve
        font.family:    Settings.font
        font.pixelSize: Settings.fontSize
        text:           root.reserveText
    }

    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    height: _label.implicitHeight
    width:  !expanded ? 0
          : reserveText.length > 0 ? Math.ceil(_reserve.advanceWidth)
          : Math.ceil(_label.implicitWidth)
    clip: width + 0.5 < Math.ceil(_label.implicitWidth)

    MotionBehavior on width {
        gate: root._ready
        NumberAnimation { duration: Motion.width; easing.type: Easing.OutCubic }
    }

    ShellText {
        id: _label
        anchors.left:           parent.left
        anchors.verticalCenter: parent.verticalCenter
        color:          root.color
        font.pixelSize: Settings.fontSize
        ColorFade on color {}
        opacity:        root.expanded ? 1.0 : 0.0
        MotionBehavior on opacity {
            gate: root._ready
            NumberAnimation { duration: Motion.width; easing.type: Easing.OutCubic }
        }
    }
}
