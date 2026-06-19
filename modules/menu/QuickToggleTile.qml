import QtQuick
import "../../config"
import "../../services"

// Quick-toggle tile: a state-bearing button in the control-center grid.
// Reads as icon → title → status; "active" is signalled by a left accent rail
// plus tinted fill so the on/off state lands even without relying on hue alone.
Rectangle {
    id: root

    property bool active: false
    property bool available: true
    property string activeGlyph: ""
    property string inactiveGlyph: ""
    property string title: ""
    // Subtitle line; empty hides it (SSID, device name, temperature…).
    property string status: ""
    property color accentColor: Theme.accent
    property int badgeCount: 0
    // Shows a chevron that opens an inline list (Wi-Fi networks, BT devices).
    property bool expandable: false
    property bool expanded:   false
    readonly property string glyphText: active ? activeGlyph : inactiveGlyph

    signal toggled()
    signal badgeActivated()
    signal expandToggled()

    // Gate the glyph-swap stamp so it doesn't fire on the initial binding.
    property bool _ready: false
    Component.onCompleted: _ready = true
    onGlyphTextChanged: if (_ready) _stamp.restart()

    height: 56
    radius: Theme.radiusCard
    antialiasing: true
    clip: true
    opacity: available ? 1.0 : 0.38
    scale: _tap.active ? 0.96 : 1.0
    transformOrigin: Item.Center
    layer.enabled: scale < 0.999 && !ShellSettings.reduceMotion

    // Inactive is a deliberate flat control surface, not a faded accent; active
    // lifts to a quiet accent tint. Hover nudges both a notch brighter.
    color: active
        ? Theme.mix(Theme.menuControl, accentColor,   _hover.hovered ? 0.22 : 0.16)
        : Theme.mix(Theme.menuControl, Theme.subtext, _hover.hovered ? 0.06 : 0.0)
    border.width: 1
    border.color: active
        ? Theme.mix(Theme.surface, accentColor,   0.34)
        : Theme.menuControlLine

    Behavior on color        { ColorAnimation  { duration: Motion.medium } }
    Behavior on border.color { ColorAnimation  { duration: Motion.medium } }
    Behavior on opacity      { NumberAnimation { duration: Motion.normal } }
    Behavior on scale        { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

    HoverHandler {
        id: _hover
        cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    TapHandler {
        id: _tap
        enabled: root.available
        onTapped: root.toggled()
    }

    // Left accent rail — the non-colour cue for "on". Grows in from zero width so
    // the state change reads even when the tile fill animation is subtle.
    Rectangle {
        id: _rail
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: root.active ? 3 : 0
        height: 22
        radius: 1.5
        antialiasing: true
        color: root.accentColor
        Behavior on width { NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }
    }

    Item {
        id: _iconSlot
        anchors.left: parent.left
        anchors.leftMargin: 13
        anchors.verticalCenter: parent.verticalCenter
        width: 22; height: 22

        Text {
            id: _icon
            property string shown: root.glyphText
            anchors.centerIn: parent
            text: shown
            transformOrigin: Item.Center
            color: root.active ? root.accentColor : Theme.withAlpha(Theme.subtext, 0.78)
            font.family: Settings.font
            font.pixelSize: Settings.fontSize + 5
            renderType: Text.NativeRendering

            Behavior on color { ColorAnimation { duration: Motion.medium } }

            // Pop the glyph on active/inactive swap; pairs with the rail grow.
            SequentialAnimation {
                id: _stamp
                NumberAnimation { target: _icon; property: "scale"; to: 0.0; duration: Motion.instant; easing.type: Easing.InBack; easing.overshoot: 1.4 }
                ScriptAction    { script: _icon.shown = root.glyphText }
                NumberAnimation { target: _icon; property: "scale"; from: 0.0; to: 1.0; duration: Motion.medium; easing.type: Easing.OutBack; easing.overshoot: 2.0 }
            }
        }

        // Missed-count badge rides the glyph's top-right corner (DND only).
        Rectangle {
            visible: root.badgeCount > 0
            anchors.horizontalCenter: parent.right
            anchors.verticalCenter: parent.top
            anchors.horizontalCenterOffset: -2
            anchors.verticalCenterOffset: 1
            width:  Math.max(15, _badgeTxt.implicitWidth + 7)
            height: 15
            radius: 7.5
            antialiasing: true
            color: root.accentColor
            border.width: 1
            border.color: Theme.mix(Theme.surface, root.accentColor, 0.55)
            z: 2

            Text {
                id: _badgeTxt
                anchors.centerIn: parent
                text: root.badgeCount > 99 ? "99+" : root.badgeCount
                color: Theme.background
                font.family: Settings.font
                font.pixelSize: Settings.fontSize - 4
                font.weight: Font.Bold
                renderType: Text.NativeRendering
            }

            // Badge tap routes to history instead of toggling; the grab blocks
            // root's tap.
            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: root.badgeActivated()
            }
        }
    }

    // Title + status. Title is the anchor line; status sits under it quieter and
    // smaller so the hierarchy is icon → name → state.
    Column {
        id: _labelCol
        anchors.left:  _iconSlot.right
        anchors.leftMargin: 11
        anchors.right: _chevron.visible ? _chevron.left : parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Text {
            width: parent.width
            text: root.title
            textFormat: Text.PlainText
            color: root.active ? Theme.text : Theme.withAlpha(Theme.text, 0.88)
            font.family: Settings.font
            font.pixelSize: Settings.fontSize
            font.weight: Font.Medium
            renderType: Text.NativeRendering
            elide: Text.ElideRight
            Behavior on color { ColorAnimation { duration: Motion.medium } }
        }

        Text {
            width: parent.width
            visible: root.status.length > 0
            text: root.status
            textFormat: Text.PlainText
            color: root.active ? Theme.withAlpha(root.accentColor, 0.85) : Theme.withAlpha(Theme.subtext, 0.62)
            font.family: Settings.font
            // Even step (was -3 → odd 9px); -3 landed digits on fractional
            // physical px at 1.25x and split "4000K" into "4°00K".
            font.pixelSize: Settings.fontSize - 2
            // Snap glyph advances to the pixel grid so adjacent digits stay joined.
            font.hintingPreference: Font.PreferFullHinting
            renderType: Text.NativeRendering
            elide: Text.ElideRight
            Behavior on color { ColorAnimation { duration: Motion.medium } }
        }
    }

    // Split-button: a recessed chevron zone with its own surface, divider and
    // hover, so it visibly presses apart from the toggle body.
    Item {
        id: _chevron
        visible: root.expandable
        width:  visible ? 38 : 0
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right

        // Hairline seam between the two press zones.
        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: 26
            color: root.active
                ? Theme.withAlpha(root.accentColor, 0.22)
                : Theme.withAlpha(Theme.subtext, 0.16)
        }

        // Recessed surface — fills on hover so the zone reads as its own button.
        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: 1
            color: Theme.withAlpha(Theme.subtext, _chevHover.hovered ? 0.10 : 0.0)
            // Square off the seam edge, round only the tile's own corner side.
            topRightRadius:    root.radius - 1
            bottomRightRadius: root.radius - 1
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        Text {
            id: _chevGlyph
            anchors.centerIn: parent
            text: "󰅀"
            color: _chevHover.hovered
                ? Theme.text
                : Theme.withAlpha(Theme.subtext, root.expanded ? 0.85 : 0.62)
            font.family: Settings.font
            font.pixelSize: Settings.fontSize + 1
            renderType: Text.NativeRendering
            rotation: root.expanded ? 180 : 0
            transformOrigin: Item.Center
            Behavior on rotation { NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }
            Behavior on color    { ColorAnimation  { duration: Motion.fast } }
        }

        HoverHandler { id: _chevHover; enabled: root.expandable; cursorShape: Qt.PointingHandCursor }
        // Use an exclusive MouseArea here instead of another TapHandler. Nested
        // TapHandlers can both accept the same tap, which would expand the row
        // and toggle the device immediately afterward (closing it again).
        MouseArea {
            anchors.fill: parent
            enabled: root.expandable
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expandToggled()
        }
    }
}
