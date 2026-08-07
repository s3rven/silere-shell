pragma ComponentBehavior: Bound

import QtQuick
import "../../../config"

Item {
    id: root

    required property real headX
    required property real tailX
    required property real centerY
    required property real weight
    required property color tint
    required property bool running

    readonly property real _gap: Math.abs(headX - tailX)
    readonly property bool _rightward: headX >= tailX
    readonly property real _strength: running ? Math.min(1, _gap / 13) : 0
    readonly property real _left: Math.min(headX, tailX)

    readonly property color _tintClear: Theme.withAlpha(tint, 0)
    readonly property color _core: Theme.withAlpha(Theme.text, 0.95)
    readonly property color _coreClear: Theme.withAlpha(Theme.text, 0)

    Rectangle {
        id: band
        height: (4 + root._strength * 4) * root.weight
        radius: height / 2
        antialiasing: true
        y: root.centerY - height / 2
        x: root._left - height / 2
        width: root._gap + height
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: root._rightward ? root._tintClear : root.tint }
            GradientStop { position: 1.0; color: root._rightward ? root.tint : root._tintClear }
        }
        opacity: root._strength * 0.93
        visible: opacity > 0.01
    }

    Rectangle {
        height: (10 + root._strength * 4) * root.weight
        radius: height / 2
        antialiasing: true
        y: root.centerY - height / 2
        x: band.x
        width: band.width
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: root._rightward ? root._tintClear : root.tint }
            GradientStop { position: 1.0; color: root._rightward ? root.tint : root._tintClear }
        }
        opacity: root._strength * 0.20
        visible: opacity > 0.01
    }

    Rectangle {
        height: Math.max(1, (1.5 + root._strength * 1.5) * root.weight)
        radius: height / 2
        antialiasing: true
        y: root.centerY - height / 2
        x: band.x
        width: band.width
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: root._rightward ? root._coreClear : root._core }
            GradientStop { position: 1.0; color: root._rightward ? root._core : root._coreClear }
        }
        opacity: root._strength * 0.88
        visible: opacity > 0.01
    }
}
