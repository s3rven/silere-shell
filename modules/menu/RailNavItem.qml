import QtQuick
import "../../config"
import "../common"

Item {
    id: root

    property string glyph: ""
    property string label: ""
    property string accessibleDescription: ""
    property bool active: false
    property color accentColor: Theme.accent
    property int railW: 44
    // Expanded drawers already provide their own labels. Keeping this tooltip
    // open there paints it over the drawer's controls.
    property bool labelPillEnabled: true
    property RailLabelGroup labels: null
    property bool _hoverReady: false

    FocusVisual { id: _focusVisual; target: root }

    readonly property bool _hot: _hover.hovered || _focusVisual.active

    signal tapped()

    width: railW
    height: Metrics.rowHeightFor(34)
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: root.label
    Accessible.description: root.accessibleDescription.length > 0
        ? root.accessibleDescription
        : (root.active ? "Current page" : "Open " + root.label)
    Accessible.selectable: true
    Accessible.selected: root.active
    Accessible.pressed: _tap.pressed
    Accessible.onPressAction: root.tapped()

    Timer {
        id: _labelDelay
        interval: 80
        onTriggered: root._hoverReady = _hover.hovered
    }

    HoverHandler {
        id: _hover
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: {
            if (hovered) {
                // one shared delay: a per-item one makes a sweep down the rail look like it drops labels at random
                if (root.labels && root.labels.warm) root._hoverReady = true
                else _labelDelay.restart()
            } else {
                _labelDelay.stop()
                root._hoverReady = false
                if (root.labels) root.labels.release()
            }
        }
    }
    TapHandler {
        id: _tap
        onTapped: {
            _focusVisual.takePointerFocus()
            root.tapped()
        }
    }
    Keys.onPressed: _focusVisual.noteKeyboardInput()
    Keys.onSpacePressed: event => { if (!event.isAutoRepeat) root.tapped(); event.accepted = true }
    Keys.onReturnPressed: event => { if (!event.isAutoRepeat) root.tapped(); event.accepted = true }
    Keys.onEnterPressed: event => { if (!event.isAutoRepeat) root.tapped(); event.accepted = true }

    // Nerd Font glyphs have uneven bearings; measure ink to centre the icon in the pill
    TextMetrics {
        id: _ink
        font.family: Settings.font
        font.pixelSize: Settings.iconSize + 2
        text: root.glyph
    }

    Rectangle {
        id: _activeBg
        anchors.centerIn: parent
        width: 30; height: 30; radius: 9
        antialiasing: true
        color: _tap.pressed
            ? Theme.mix(Theme.menuControl, root.accentColor, 0.10)
            : root.active ? Theme.menuControl
            : root._hot ? Theme.withAlpha(Theme.text, 0.050) : "transparent"
        scale: _tap.pressed ? 0.94 : (root.active || root._hot ? 1.0 : 0.90)
        transformOrigin: Item.Center
        ColorFade on color {}
        MotionBehavior on scale {NumberAnimation { duration: Motion.ms(135); easing.type: Easing.OutCubic } }

        OutlineBorder {
            radius: _activeBg.radius
            outlineColor: (root.active || _hover.hovered || _focusVisual.active)
                ? (root.active ? Theme.menuControlLine : Theme.menuControlLineHot)
                : "transparent"
            ColorFade on outlineColor {}
        }
    }

    ShellText {
        id: _iconText
        // NativeRendering blurs on a fractional origin, so solve for the ink centre and snap
        // the result: centreIn plus a float offset lands the glyph on a sub-pixel x every time
        x: Math.round(parent.width / 2
            - (_ink.tightBoundingRect.x + _ink.tightBoundingRect.width / 2))
        y: Math.round((parent.height - _iconText.height) / 2)
        text: root.glyph
        color: root.active
            ? Theme.mix(root.accentColor, Theme.text, 0.10)
            : Theme.withAlpha(Theme.mix(Theme.subtext, root.accentColor, _hover.hovered || _focusVisual.active ? 0.24 : 0),
                               _hover.hovered || _focusVisual.active ? 0.78 : 0.50)
        font.pixelSize: Settings.iconSize + 2
        scale: _tap.pressed ? 0.92 : (root.active ? 1.015 : 1.0)
        transformOrigin: Item.Center
        ColorFade on color {}
        MotionBehavior on scale {NumberAnimation { duration: Motion.ms(115); easing.type: Easing.OutCubic } }
    }

    Rectangle {
        id: _pill
        // not focus alone: tapping Power force-focuses it and would pin the label open while the rail stays open
        readonly property bool _show: root.labelPillEnabled
            && ((_hover.hovered && root._hoverReady)
                || (_focusVisual.active && !root.active))
        on_ShowChanged: if (_show && root.labels) root.labels.engage()

        x: root.railW + 7
        anchors.verticalCenter: parent.verticalCenter
        width: _pillLabel.implicitWidth + 18
        height: 22; radius: Theme.radiusInline
        color: Theme.menuCard
        antialiasing: true
        opacity: _show ? 1.0 : 0.0
        scale:   _show ? 1.0 : 0.96
        property real _slide: _show ? 0 : -3
        transform: Translate { x: _pill._slide }

        OutlineBorder {
            radius: _pill.radius
            outlineColor: Theme.menuCardBorder
        }
        visible: opacity > 0.01
        transformOrigin: Item.Left
        z: 10
        MotionBehavior on opacity {
            NumberAnimation { duration: _pill._show ? Motion.fast : Motion.instant; easing.type: Easing.OutCubic }
        }
        MotionBehavior on scale {
            NumberAnimation { duration: _pill._show ? Motion.fast : Motion.instant; easing.type: Easing.OutCubic }
        }
        MotionBehavior on _slide {
            NumberAnimation { duration: _pill._show ? Motion.fast : Motion.instant; easing.type: Easing.OutCubic }
        }
        ShellText {
            id: _pillLabel
            anchors.centerIn: parent
            text: root.label
            color: Theme.withAlpha(Theme.text, 0.78)
            font.family: Settings.font; font.pixelSize: Settings.fontLabel
        }
    }
}
