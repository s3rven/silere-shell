import QtQuick
import "../../config"
import "../../services"

Item {
    id: root

    property bool expanded: true
    default property alias data: _content.data

    width:   parent ? parent.width : 0
    height:  expanded ? _content.implicitHeight : 0
    clip:    true
    enabled: expanded
    visible: height > 0.5

    Behavior on height {
        NumberAnimation {
            duration:    root.expanded ? Motion.medium : Motion.fast
            easing.type: root.expanded ? Easing.OutQuart : Easing.InCubic
        }
    }

    Column {
        id: _content
        width: parent.width

        property bool _animating: false
        y:       root.expanded ? 0 : -10
        opacity: root.expanded ? 1.0 : 0.0
        layer.enabled: _animating && !ShellSettings.reduceMotion

        onYChanged:       if (!ShellSettings.reduceMotion) _animating = true
        onOpacityChanged: if (!ShellSettings.reduceMotion) _animating = true

        Connections {
            target: ShellSettings
            function onReduceMotionChanged() {
                if (ShellSettings.reduceMotion) _content._animating = false
            }
        }

        Behavior on y {
            NumberAnimation {
                duration:    root.expanded ? Motion.medium : Motion.fast
                easing.type: root.expanded ? Easing.OutQuart : Easing.InCubic
            }
        }
        Behavior on opacity {
            SequentialAnimation {
                NumberAnimation {
                    duration:    root.expanded ? Motion.medium : Motion.fast
                    easing.type: root.expanded ? Easing.OutCubic : Easing.InCubic
                }
                ScriptAction { script: _content._animating = false }
            }
        }
    }
}
