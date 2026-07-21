import QtQuick
import QtQuick.Window
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
    readonly property real   _dpr:   Math.max(1, Screen.devicePixelRatio)
    readonly property real   _px:    1 / _dpr

    // mapToItem gives logical scene coordinates. Track the ancestor geometry
    // explicitly so bindings re-evaluate as animated widget widths move this
    // slot, then snap the mark itself to the output's physical-pixel grid.
    readonly property point _sceneOrigin: {
        let revision = 0
        let item = root
        while (item) {
            revision += Number(item.x) || 0
            revision += Number(item.y) || 0
            revision += (Number(item.width) || 0) * 0
            revision += (Number(item.height) || 0) * 0
            revision += (Number(item.scale) || 0) * 0
            item = item.parent
        }
        const p = root.mapToItem(null, 0, 0)
        return Qt.point(p.x + revision * 0, p.y + revision * 0)
    }

    function _snapX(localX: real): real {
        return Math.round((_sceneOrigin.x + localX) * _dpr) / _dpr
            - _sceneOrigin.x
    }
    function _snapY(localY: real): real {
        return Math.round((_sceneOrigin.y + localY) * _dpr) / _dpr
            - _sceneOrigin.y
    }
    function _physicalSize(logicalSize: real): real {
        return Math.max(_px, Math.round(logicalSize * _dpr) / _dpr)
    }

    property real _animatedW: (show && !_none) ? _slotW : 0

    anchors.verticalCenter: parent.verticalCenter
    implicitWidth:  Math.round(_animatedW)
    implicitHeight: Settings.capHeight
    // only while the slot animates: a settled mark can't overflow, and a clip node breaks scene batching
    clip: width < _slotW - 0.5
    visible: !_none && (show || _mark.opacity > 0)

    Behavior on _animatedW { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }

    Item {
        id: _mark
        anchors.fill: parent
        opacity: root.show ? 1.0 : 0.0
        Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.normal } }

        Rectangle {
            visible: root._style === "·" || root._style === "•" || root._style === "◦"
            readonly property real _rawD: root.compact
                ? (root._style === "◦" ? 4 : 3)
                : (root._style === "•" ? 5 : (root._style === "◦" ? 6 : 3))
            readonly property real d: root._physicalSize(_rawD)
            x: root._snapX((parent.width - width) / 2)
            y: root._snapY((parent.height - height) / 2)
            width: d; height: d; radius: d / 2
            antialiasing: true
            color:        root._style === "◦" ? "transparent" : root._col
            border.width: root._style === "◦" ? root._px : 0
            border.color: root._col
        }

        // One physical pixel, regardless of output scale or the fractional
        // text width of a widget earlier in the row.
        Rectangle {
            visible: root._style === "|"
            x: root._snapX((parent.width - width) / 2)
            y: root._snapY((parent.height - height) / 2)
            width: root._px
            height: root._physicalSize(Settings.capHeight * (root.compact ? 0.50 : 0.62))
            antialiasing: false
            color: root._col
        }

        // solid middle, fades only at the tips (a single centre stop looks like a spindle)
        Rectangle {
            visible: root._style === "line"
            x: root._snapX((parent.width - width) / 2)
            y: root._snapY((parent.height - height) / 2)
            width: root._px
            height: root._physicalSize(Settings.capHeight * (root.compact ? 0.54 : 0.66))
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
            x: root._snapX((parent.width - width) / 2)
            y: root._snapY((parent.height - height) / 2)
            width: root._px
            height: root._physicalSize(Settings.capHeight * (root.compact ? 0.58 : 0.72))
            radius: width / 2
            antialiasing: true
            rotation: 18
            transformOrigin: Item.Center
            color: root._col
        }
    }
}
