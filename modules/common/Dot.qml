import QtQuick
import "../../config"
import "../../services"

// Bar separator drawn as a shape (not a font glyph) so it's crisp regardless of font:
// dot, ring, tick, or gradient hairline. Collapses to zero width when hidden.
Item {
    id: root
    property bool show: true

    readonly property string _style: ShellSettings.dotStyle
    readonly property color  _col:   Theme.withAlpha(Theme.subtext, ShellSettings.dotOpacity)

    // Font-derived reference height so marks scale with the bar's text.
    TextMetrics { id: _tm; font.family: Settings.font; font.pixelSize: Settings.fontSize; text: "M" }

    anchors.verticalCenter: parent.verticalCenter
    implicitWidth:  show ? 8 : 0
    implicitHeight: _tm.height
    clip: true
    visible: show || _mark.opacity > 0

    Behavior on implicitWidth { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }

    Item {
        id: _mark
        anchors.fill: parent
        opacity: root.show ? 1.0 : 0.0
        Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.normal } }

        // filled dot (·, •) or ring (◦)
        Rectangle {
            visible: root._style === "·" || root._style === "•" || root._style === "◦"
            anchors.centerIn: parent
            readonly property real d: root._style === "•" ? 5 : (root._style === "◦" ? 6 : 3)
            width: d; height: d; radius: d / 2
            antialiasing: true
            color:        root._style === "◦" ? "transparent" : root._col
            border.width: root._style === "◦" ? 1 : 0
            border.color: root._col
        }

        // solid tick (|)
        Rectangle {
            visible: root._style === "|"
            anchors.centerIn: parent
            width: 1; height: Math.round(_tm.height * 0.62)
            antialiasing: true
            color: root._col
        }

        // hairline: solid middle, fades only at the tips (a single centre stop looks like a spindle)
        Rectangle {
            visible: root._style === "line"
            anchors.centerIn: parent
            width: 1; height: Math.round(_tm.height * 0.66)
            antialiasing: true
            gradient: Gradient {
                GradientStop { position: 0.0;  color: "transparent" }
                GradientStop { position: 0.30; color: root._col }
                GradientStop { position: 0.70; color: root._col }
                GradientStop { position: 1.0;  color: "transparent" }
            }
        }
    }
}
