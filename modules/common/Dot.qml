import QtQuick
import "../../config"
import "../../services"

// Bar separator drawn as a shape (not a font glyph) so it's crisp regardless of font:
// dot, ring, tick, slash, or gradient hairline. Collapses to zero width when hidden.
Item {
    id: root
    property bool show: true

    readonly property string _style: ShellSettings.dotStyle
    // "none" draws no mark and reserves no slot, so the Row collapses to a single
    // uniform gap between widgets — clean spacing, no group dividers at all.
    readonly property bool   _none:  _style === "none"
    readonly property color  _base:  ShellSettings.neutralTheme ? Theme.subtext : Theme.mix(Theme.subtext, Theme.accent, 0.10)
    readonly property color  _col:   Theme.withAlpha(_base, ShellSettings.dotOpacity)
    readonly property bool   _slash: _style === "slash"
    readonly property int    _slotW: Metrics.dotSlot(_slash)

    // Font-derived reference height so marks scale with the bar's text.
    TextMetrics { id: _tm; font.family: Settings.font; font.pixelSize: Settings.fontSize; text: "M" }

    anchors.verticalCenter: parent.verticalCenter
    implicitWidth:  (show && !_none) ? _slotW : 0
    implicitHeight: _tm.height
    clip: true
    visible: !_none && (show || _mark.opacity > 0)

    Behavior on implicitWidth { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }

    Item {
        id: _mark
        anchors.fill: parent
        opacity: root.show ? 1.0 : 0.0
        Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.normal } }

        Rectangle {
            visible: root._style === "·" || root._style === "•" || root._style === "◦"
            anchors.centerIn: parent
            readonly property real d: ShellSettings.barCompact
                ? (root._style === "◦" ? 4 : 3)
                : (root._style === "•" ? 5 : (root._style === "◦" ? 6 : 3))
            width: d; height: d; radius: d / 2
            antialiasing: true
            color:        root._style === "◦" ? "transparent" : root._col
            border.width: root._style === "◦" ? 1 : 0
            border.color: root._col
        }

        Rectangle {
            visible: root._style === "|"
            anchors.centerIn: parent
            width: 1; height: Math.round(_tm.height * (ShellSettings.barCompact ? 0.50 : 0.62))
            antialiasing: true
            color: root._col
        }

        Rectangle {
            visible: root._slash
            anchors.centerIn: parent
            width: 1
            height: Math.round(_tm.height * (ShellSettings.barCompact ? 0.58 : 0.72))
            radius: 0.5
            antialiasing: true
            rotation: 18
            color: root._col
        }

        // hairline: solid middle, fades only at the tips (a single centre stop looks like a spindle)
        Rectangle {
            visible: root._style === "line"
            anchors.centerIn: parent
            width: 1; height: Math.round(_tm.height * (ShellSettings.barCompact ? 0.54 : 0.66))
            antialiasing: true
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0;  color: "transparent" }
                GradientStop { position: 0.30; color: root._col }
                GradientStop { position: 0.70; color: root._col }
                GradientStop { position: 1.0;  color: "transparent" }
            }
        }
    }
}
