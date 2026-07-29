import QtQuick
import "../../config"
import "../../services"

Item {
    id: root

    // the divider owns the whole span to the next widget; `marked` only adds
    // the visual, so an unmarked one stays a plain gap of the same width
    property bool hasNext: false
    property bool marked: false
    property bool groupBreak: false
    required property bool compact

    readonly property string _style: ShellSettings.dotStyle
    readonly property bool _markWanted: hasNext && marked && _style !== "none"
    // a group boundary keeps the wider span with the mark off, so Groups
    // placement still reads as grouping under the None style
    readonly property bool _wideSpan: hasNext && (_markWanted || groupBreak)
    readonly property int _plainSpan: Metrics.widgetGapFor(compact)
    readonly property int _markedSpan: Metrics.dividerSpanFor(compact)
    // integer slot widths keep this stable; per-divider mapToItem snapping gave
    // repeated siblings a bad local phase and made valid marks vanish
    readonly property real _strokeW: 1

    readonly property bool _isDot: _style === "·" || _style === "•" || _style === "◦"
    readonly property real _strokeScale: _style === "line" ? (compact ? 0.58 : 0.74)
                                       : _style === "slash" ? (compact ? 0.54 : 0.68)
                                       : (compact ? 0.46 : 0.58)
    readonly property color _strokeEnd: _style === "line" ? "transparent" : Theme.barSeparator

    function _roundedSize(logicalSize: real): real {
        return Math.max(1, Math.round(logicalSize))
    }

    property real _animatedSpan: hasNext
        ? (_wideSpan ? _markedSpan : _plainSpan)
        : 0

    anchors.verticalCenter: parent.verticalCenter
    implicitWidth: Math.round(_animatedSpan)
    implicitHeight: Settings.capHeight
    visible: _animatedSpan > 0.01
    // only needed while a visible mark collapses; a clip node at rest is waste
    clip: mark.opacity > 0.001 && width < _markedSpan - 0.5

    Behavior on _animatedSpan {
        enabled: !ShellSettings.reduceMotion
        NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic }
    }

    Item {
        id: mark
        anchors.fill: parent
        opacity: root._markWanted ? 1 : 0
        visible: opacity > 0.001

        Behavior on opacity {
            enabled: !ShellSettings.reduceMotion
            NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
        }

        Rectangle {
            visible: root._isDot
            readonly property real diameter: root._roundedSize(
                root._style === "•" ? (root.compact ? 3 : 4)
                : root._style === "◦" ? (root.compact ? 4 : 5)
                : 3)
            anchors.centerIn: parent
            width: diameter
            height: diameter
            radius: diameter / 2
            antialiasing: true
            color: root._style === "◦" ? "transparent" : Theme.barSeparator
            border.width: root._style === "◦" ? 1 : 0
            border.color: Theme.barSeparator
        }

        Rectangle {
            visible: !root._isDot
            anchors.centerIn: parent
            width: root._strokeW
            height: root._roundedSize(Settings.capHeight * root._strokeScale)
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0;    color: root._strokeEnd }
                GradientStop { position: 0.24; color: Theme.barSeparator }
                GradientStop { position: 0.76; color: Theme.barSeparator }
                GradientStop { position: 1;    color: root._strokeEnd }
            }
            rotation: root._style === "slash" ? 18 : 0
            radius: root._style === "slash" ? width / 2 : 0
            antialiasing: root._style === "slash"
            transformOrigin: Item.Center
        }
    }
}
