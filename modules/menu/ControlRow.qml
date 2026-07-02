import QtQuick
import "../../config"
import "../../services"

Item {
    id: root

    property string glyph:       ""
    property string title:       ""
    property string status:      ""    // muted subtitle under the title
    property string valueText:   ""    // right-aligned value (cyclers, no switch)
    property color  accentColor: Theme.accent
    property bool   active:       false
    property bool   available:    true
    property bool   showSwitch:   false
    property bool   expandable:   false
    property bool   expanded:     false
    property int    badgeCount:   0

    // Set by the enclosing SettingsCard's auto-rounding — do not assign.
    property real topRadius:    0
    property real bottomRadius: 0
    property real cardInset:    1

    signal activated()
    signal expandToggled()
    signal badgeActivated()

    readonly property bool _canTap: root.enabled && root.available

    function _activate(): void {
        if (!_canTap) return
        // animate the knob only on a real user flip, not section-driven re-checks
        if (showSwitch) _switch.armFlipAnimation()
        root.activated()
    }

    function _insideChevron(pos): bool {
        if (!root.expandable || !_chevron.visible) return false
        const x0 = _rightSlot.x + _chevron.x - 4
        const x1 = _rightSlot.x + _chevron.x + _chevron.width + 4
        return pos.x >= x0 && pos.x <= x1
    }

    function _insideBadge(pos): bool {
        if (root.badgeCount <= 0 || !_badge.visible) return false
        const mapped = _badge.mapFromItem(root, pos.x, pos.y)
        return mapped.x >= -4 && mapped.x <= _badge.width + 4
            && mapped.y >= -4 && mapped.y <= _badge.height + 4
    }

    width:          parent ? parent.width : 0
    height:         48
    implicitHeight: height

    opacity: _canTap ? 1.0 : 0.45
    Behavior on opacity { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.medium } }

    activeFocusOnTab: _canTap
    Accessible.role: root.showSwitch ? Accessible.CheckBox : Accessible.Button
    Accessible.name: root.title
    Accessible.description: root.status
    Accessible.checked: root.active
    Keys.onSpacePressed:  event => { if (!event.isAutoRepeat) root._activate(); event.accepted = true }
    Keys.onReturnPressed: event => { if (!event.isAutoRepeat) root._activate(); event.accepted = true }
    Keys.onEnterPressed:  event => { if (!event.isAutoRepeat) root._activate(); event.accepted = true }
    Keys.onRightPressed: event => {
        if (root._canTap && root.expandable && !root.expanded) {
            root.expandToggled()
            event.accepted = true
        } else {
            event.accepted = false
        }
    }
    Keys.onLeftPressed: event => {
        if (root._canTap && root.expandable && root.expanded) {
            root.expandToggled()
            event.accepted = true
        } else {
            event.accepted = false
        }
    }

    HoverHandler { id: _hover; cursorShape: root._canTap ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler {
        enabled: root._canTap
        onTapped: (eventPoint, button) => {
            if (!root._insideChevron(eventPoint.position) && !root._insideBadge(eventPoint.position)) root._activate()
        }
    }

    RowHoverBg {
        anchors.fill: parent
        topRadius:    root.topRadius
        bottomRadius: root.bottomRadius
        cardInset:    root.cardInset
        active:       (_hover.hovered || root.activeFocus) && root._canTap
        fillOpacity:  root.activeFocus ? 0.13 : 0.08
    }

    // grows from zero so the active state reads alongside the switch
    Rectangle {
        anchors.left:           parent.left
        anchors.leftMargin:     root.cardInset + 2
        anchors.verticalCenter: parent.verticalCenter
        width:  root.active ? 3 : 0
        height: 18
        radius: 1.5
        antialiasing: true
        color:  root.accentColor
        Behavior on width { enabled: root._ready && !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.medium; easing.type: root.active ? Easing.OutCubic : Easing.InCubic } }
    }

    Item {
        id: _iconSlot
        anchors.left:           parent.left
        anchors.leftMargin:     14
        anchors.verticalCenter: parent.verticalCenter
        width: 18; height: 18

        Text {
            id: _glyph
            anchors.centerIn: parent
            text:           root.glyph
            color:          root.active ? Theme.withAlpha(root.accentColor, 0.95)
                                        : Theme.withAlpha(Theme.subtext, 0.85)
            font.family:    Settings.font
            font.pixelSize: Settings.fontSize + 2
            renderType:     Text.NativeRendering
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        // Missed-count badge (DND) rides the glyph corner; its tap routes to history.
        Rectangle {
            id: _badge
            visible: root.badgeCount > 0
            anchors.horizontalCenter: parent.right
            anchors.verticalCenter:   parent.top
            anchors.horizontalCenterOffset: -2
            anchors.verticalCenterOffset:    1
            width:  Math.max(15, _badgeTxt.implicitWidth + 7)
            height: 15
            radius: 7.5
            antialiasing: true
            color: root.accentColor
            border.width: 1
            border.color: Theme.mix(Theme.menuCard, root.accentColor, 0.55)
            z: 2

            Text {
                id: _badgeTxt
                anchors.centerIn: parent
                text:  root.badgeCount > 99 ? "99+" : root.badgeCount
                color: Theme.background
                font.family: Settings.font
                font.pixelSize: Settings.fontSize - 4
                font.weight: Font.Bold
                renderType: Text.NativeRendering
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: root.badgeActivated()
            }
        }
    }

    Column {
        id: _textCol
        anchors.left:           _iconSlot.right
        anchors.leftMargin:     10
        anchors.right:          _rightSlot.left
        anchors.rightMargin:    8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Text {
            width:          parent.width
            text:           root.title
            textFormat:     Text.PlainText
            color:          root.active ? Theme.text : Theme.withAlpha(Theme.text, 0.85)
            font.family:    Settings.font
            font.pixelSize: Settings.fontSize
            font.weight:    Font.DemiBold
            font.hintingPreference: Font.PreferFullHinting
            renderType:     Text.NativeRendering
            elide:          Text.ElideRight
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        Text {
            visible:        root.status.length > 0
            width:          parent.width
            text:           root.status
            textFormat:     Text.PlainText
            color:          root.active ? Theme.mix(root.accentColor, Theme.text, 0.12)
                                        : Theme.withAlpha(Theme.subtext, 0.62)
            font.family:    Settings.font
            font.pixelSize: Math.max(10, Settings.fontSize - 2)
            font.weight:    Font.Medium
            font.hintingPreference: Font.PreferFullHinting
            renderType:     Text.NativeRendering
            elide:          Text.ElideRight
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }
    }

    Item {
        id: _rightSlot
        anchors.right:          parent.right
        anchors.rightMargin:    12
        anchors.verticalCenter: parent.verticalCenter
        height: 20
        readonly property real _ctrlW: root.showSwitch ? 34
                                     : (root.valueText.length > 0 ? Math.ceil(_valMetrics.advanceWidth) : 0)
        width: (_chevron.visible ? _chevron.width + 8 : 0) + _ctrlW

        TextMetrics { id: _valMetrics; font.family: Settings.font; font.pixelSize: Settings.fontSize - 1; text: root.valueText }

        // Shared switch visual, same knob as the settings ToggleRow.
        ToggleSwitch {
            id: _switch
            visible: root.showSwitch
            anchors.right:          parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked:     root.active
            accentColor: root.accentColor
        }

        Text {
            visible: !root.showSwitch && root.valueText.length > 0
            anchors.right:          parent.right
            anchors.verticalCenter: parent.verticalCenter
            text:           root.valueText
            color:          root.active ? Theme.mix(root.accentColor, Theme.text, 0.18)
                                        : Theme.withAlpha(Theme.text, 0.60)
            font.family:    Settings.font
            font.pixelSize: Settings.fontSize - 1
            font.weight:    Font.Medium
            renderType:     Text.NativeRendering
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        // MouseArea (not TapHandler) so it doesn't fire the row body tap too
        Item {
            id: _chevron
            visible: root.expandable
            width:  visible ? 24 : 0
            height: parent.height
            anchors.right: (root.showSwitch || root.valueText.length > 0) ? undefined : parent.right
            x: (root.showSwitch || root.valueText.length > 0)
                ? parent.width - _rightSlot._ctrlW - 8 - width
                : 0

            Text {
                anchors.centerIn: parent
                text: "󰅀"
                color: _chevHover.hovered ? Theme.text
                     : Theme.withAlpha(Theme.subtext, root.expanded ? 0.85 : 0.55)
                font.family: Settings.font
                font.pixelSize: Settings.fontSize
                renderType: Text.NativeRendering
                rotation: root.expanded ? 180 : 0
                transformOrigin: Item.Center
                Behavior on rotation { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }
                Behavior on color    { ColorAnimation { duration: Motion.fast } }
            }

            HoverHandler { id: _chevHover; enabled: root.expandable; cursorShape: Qt.PointingHandCursor }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                enabled: root.expandable
                cursorShape: Qt.PointingHandCursor
                onClicked: root.expandToggled()
            }
        }
    }

    // Gate the knob slide so it doesn't animate from its initial bound state.
    property bool _ready: false
    Component.onCompleted: _ready = true
}
