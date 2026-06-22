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
        enabled: !ShellSettings.reduceMotion
        NumberAnimation {
            duration:    root.expanded ? Motion.medium : Motion.fast
            easing.type: root.expanded ? Easing.OutQuart : Easing.InCubic
        }
    }

    Column {
        id: _content
        width: parent.width

        property int _animCount: 0
        readonly property bool _animating: _animCount > 0
        y:       root.expanded ? 0 : -10
        opacity: root.expanded ? 1.0 : 0.0
        layer.enabled: _animating && !ShellSettings.reduceMotion

        Behavior on y {
            enabled: !ShellSettings.reduceMotion
            NumberAnimation {
                duration:    root.expanded ? Motion.medium : Motion.fast
                easing.type: root.expanded ? Easing.OutQuart : Easing.InCubic
                onStarted: _content._animCount++
                onStopped: _content._animCount = Math.max(0, _content._animCount - 1)
            }
        }
        Behavior on opacity {
            enabled: !ShellSettings.reduceMotion
            NumberAnimation {
                duration:    root.expanded ? Motion.medium : Motion.fast
                easing.type: root.expanded ? Easing.OutCubic : Easing.InCubic
                onStarted: _content._animCount++
                onStopped: _content._animCount = Math.max(0, _content._animCount - 1)
            }
        }
    }
}
