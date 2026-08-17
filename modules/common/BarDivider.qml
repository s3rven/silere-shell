import QtQuick
import "../../config"
import "../../services"

Item {
    id: root

    // the divider owns the whole span to the next widget; unmarked stays a plain gap of the same width
    property bool hasNext: false
    property bool marked: false
    property bool groupBreak: false
    required property bool compact

    // preview surfaces draw a style the setting is not on yet; empty means follow the setting
    property string styleOverride: ""
    readonly property string _style: styleOverride.length > 0
        ? styleOverride : ShellSettings.dotStyle
    readonly property bool _markWanted: hasNext && marked && _style !== "none"
    // a group boundary keeps the wider span with the mark off, so Groups placement still reads under the None style
    readonly property bool _wideSpan: hasNext && (_markWanted || groupBreak)
    readonly property int _plainSpan: Metrics.widgetGapFor(compact)
    readonly property int _markedSpan: Metrics.dividerSpanFor(compact)
    readonly property bool _isDot: _style === "·" || _style === "•" || _style === "◦"
    readonly property real _strokeScale: _style === "line" ? (compact ? 0.54 : 0.64)
                                       : _style === "slash" ? (compact ? 0.50 : 0.58)
                                       : (compact ? 0.40 : 0.48)

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

    MotionBehavior on _animatedSpan {
        NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic }
    }

    Item {
        id: mark
        anchors.fill: parent
        opacity: root._markWanted ? 1 : 0
        visible: opacity > 0.001

        MotionBehavior on opacity {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
        }

        Rectangle {
            visible: root._isDot
            // each dot style steps down by one when compact, or · and • land on the same size
            readonly property real diameter: root._roundedSize(
                root._style === "•" ? (root.compact ? 3 : 4)
                : root._style === "◦" ? (root.compact ? 4 : 5)
                : (root.compact ? 2 : 3))
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
            width: root.compact ? 1.5 : 2
            height: root._roundedSize(Settings.capHeight * root._strokeScale)
            color: Theme.barSeparator
            rotation: root._style === "slash" ? 18 : 0
            radius: width / 2
            antialiasing: true
            transformOrigin: Item.Center
        }
    }
}
