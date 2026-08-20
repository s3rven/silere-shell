import QtQuick
import "../../../config"
import "../../common"

Item {
    id: root

    property color  chipColor: Theme.accent
    property bool   active:    false
    property bool   outlined:  false
    property bool   spectrum:  false
    property string name:      ""
    default property alias content: _chip.data

    signal picked()
    signal hoverChanged(string name, bool hovered)

    function _activate(): void { if (root.enabled) root.picked() }

    implicitWidth: 26
    implicitHeight: 32
    width: implicitWidth
    height: implicitHeight

    HoverHandler {
        id: _h
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: root.hoverChanged(root.name, hovered)
    }
    TapHandler {
        id: _t
        enabled: root.enabled
        onTapped: {
            root._activate()
        }
    }

    Rectangle {
        id: _chip
        anchors.centerIn: parent; width: 22; height: 22; radius: 11
        antialiasing: true
        color: root.spectrum ? "transparent" : root.chipColor
        scale: _t.pressed ? 0.90 : _h.hovered ? 1.04 : 1.0
        transformOrigin: Item.Center
        MotionBehavior on scale {NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

        // only the custom chip pays for a canvas; the presets stay a flat fill
        Loader {
            anchors.fill: parent
            active: root.spectrum
            sourceComponent: Canvas {
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const r = width / 2
                    const g = ctx.createConicalGradient(r, r, -Math.PI / 2)
                    for (let i = 0; i <= 12; i++)
                        g.addColorStop(i / 12, Theme.lchColor(70.8, 38, i * 30))
                    ctx.fillStyle = g
                    ctx.beginPath()
                    ctx.arc(r, r, r, 0, Math.PI * 2)
                    ctx.fill()
                }
            }
        }

        // a circle is all corner, so Rectangle.border over-weights its whole perimeter
        OutlineBorder {
            radius: width / 2
            outlineWidth: 1
            outlineColor: root.outlined ? Theme.swatchEdge : "transparent"
        }
    }
}
