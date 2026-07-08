import QtQuick
import "../../config"

// text segment that collapses width to 0 (clipped) + fades when not expanded; clock day-name/seconds/AM-PM.
Item {
    id: root

    property alias text: _label.text
    property color color: Theme.text
    property bool  expanded: true
    // Fixed-width floor measured from this string: ticking values (clock
    // seconds) re-hint per digit pair under fractional scaling, and the ±1px
    // implicitWidth wobble walks the whole bar once a second otherwise.
    property string reserveText: ""

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
    clip:   true

    Behavior on width { NumberAnimation { duration: Motion.width; easing.type: Easing.OutCubic } }

    Text {
        id: _label
        anchors.left:           parent.left
        anchors.verticalCenter: parent.verticalCenter
        color:          root.color
        font.family:    Settings.font
        font.pixelSize: Settings.fontSize
        renderType:     Text.NativeRendering
        Behavior on color { ColorAnimation { duration: Motion.color } }
        opacity:        root.expanded ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: Motion.width; easing.type: Easing.OutCubic } }
    }
}
