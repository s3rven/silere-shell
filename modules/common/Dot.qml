import QtQuick
import "../../config"
import "../../services"

// bar separator drawn as a shape (not a font glyph) so it's crisp regardless of font: dot/ring/tick/slash/hairline; zero width when hidden.
Item {
    id: root
    property bool show: true
    property bool compact: ShellSettings.barCompact

    readonly property string _style: ShellSettings.dotStyle
    // "none" draws no mark and reserves no slot — Row collapses to a uniform gap, no dividers
    readonly property bool   _none:  _style === "none"
    readonly property color  _col:   Theme.barSeparator
    readonly property bool   _slash: _style === "slash"
    readonly property int    _slotW: Metrics.dotSlotFor(_slash, compact)

    anchors.verticalCenter: parent.verticalCenter
    implicitWidth:  (show && !_none) ? _slotW : 0
    implicitHeight: Settings.capHeight
    // only while the slot animates: a settled mark can't overflow, and a clip node breaks scene batching
    clip: width < _slotW - 0.5
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
            readonly property real d: root.compact
                ? (root._style === "◦" ? 4 : 3)
                : (root._style === "•" ? 5 : (root._style === "◦" ? 6 : 3))
            width: d; height: d; radius: d / 2
            antialiasing: true
            color:        root._style === "◦" ? "transparent" : root._col
            border.width: root._style === "◦" ? 1 : 0
            border.color: root._col
        }

        // axis-aligned 1px: antialiasing smears it (as in RowDividers), whole-px x/y keeps it off a sub-pixel column
        Rectangle {
            visible: root._style === "|"
            x: Math.round((parent.width - width) / 2)
            y: Math.round((parent.height - height) / 2)
            width: 1; height: Math.round(Settings.capHeight * (root.compact ? 0.50 : 0.62))
            antialiasing: false
            color: root._col
        }

        // solid middle, fades only at the tips (a single centre stop looks like a spindle)
        Rectangle {
            visible: root._style === "line"
            x: Math.round((parent.width - width) / 2)
            y: Math.round((parent.height - height) / 2)
            width: 1; height: Math.round(Settings.capHeight * (root.compact ? 0.54 : 0.66))
            antialiasing: false
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0;  color: "transparent" }
                GradientStop { position: 0.30; color: root._col }
                GradientStop { position: 0.70; color: root._col }
                GradientStop { position: 1.0;  color: "transparent" }
            }
        }

        // rotated, so it keeps antialiasing — a hard-edged diagonal stairsteps
        Rectangle {
            visible: root._slash
            anchors.centerIn: parent
            width: 1
            height: Math.round(Settings.capHeight * (root.compact ? 0.58 : 0.72))
            radius: 0.5
            antialiasing: true
            rotation: 18
            color: root._col
        }
    }
}
