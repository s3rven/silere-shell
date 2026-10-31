pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import "../../config"
import "../../services"
import "../common"

// the panel's left edge: the tab strip, the drawers that slide out of it and the power slot.
// The panel owns tabs and geometry; this owns what is drawn in that strip
Item {
    id: rail

    required property var menu
    signal scrollToTopRequested()

    // a drawer names the tabs itself, unless the panel is too narrow to show it
    readonly property bool labelsShown: !rail.menu._railExpanded || rail.menu.navW < rail.menu._navMinW
    readonly property real settingsNavHeight: _settingsDrawer.item?.implicitHeight ?? 0

    function holdDrawerLayouts(): void {
        _settingsDrawer.holdLayout()
        _recentDrawer.holdLayout()
    }

    function stopWarmDelays(): void {
        _settingsWarmDelay.stop()
        _recentWarmDelay.stop()
    }

    width: rail.menu.railW
    height: rail.menu.height

    Item {
        anchors.fill: parent
        clip: true

        Rectangle {
            x: 0; y: 0
            width: parent.width + rail.menu.radius
            height: parent.height
            radius: rail.menu.radius
            antialiasing: true
            color: Theme.menuPane
        }

        Rectangle {
            x: rail.menu.railCollapsedW
            width: Math.max(0, parent.width - x)
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            color: Theme.blend(Theme.menuPane, Theme.menuControl, 0.14)
            visible: parent.width > rail.menu.railCollapsedW + 0.5
        }

        RailDrawer {
            id: _settingsDrawer
            x: rail.menu.railCollapsedW
            width: rail.menu.navW
            revealedWidth: Math.max(0, rail.menu.railW - rail.menu.railCollapsedW)
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            shown: rail.menu._settingsNavVisible
            retained: rail.menu._settingsNavRetained
                || (MenuState.open && rail.menu.activeTab === 1)
            content: Component {
                SettingsNav {
                    powerOpen: rail.menu.powerOpen
                    onCurrentPageRetapped: rail.scrollToTopRequested()
                    onGroupToggled: rail.menu._armOuterHeightMotion()
                }
            }
        }

        RailDrawer {
            id: _recentDrawer
            x: rail.menu.railCollapsedW
            width: rail.menu.navW
            revealedWidth: Math.max(0, rail.menu.railW - rail.menu.railCollapsedW)
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            shown: rail.menu._recentNavVisible
            retained: rail.menu._recentRetained
                || (MenuState.open && rail.menu.activeTab === 2)
            content: Component {
                RecentNav {
                    onFilterPicked: rail.scrollToTopRequested()
                }
            }
        }

        Item {
            id: _powerRailSurface
            x: rail.menu.railCollapsedW
            width: rail.menu.navW
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
            height: rail.menu.powerOpen
                ? (_powerRailLoader.item?.implicitHeight ?? 0) : 0
            clip: true
            opacity: rail.menu.powerOpen ? 1 : 0
            visible: height > 0.5 || opacity > 0.001
            enabled: rail.menu.powerOpen

            MotionBehavior on height {
                id: _powerRailHeight
                NumberAnimation {
                    duration: _powerRailHeight.targetValue > 0 ? Motion.panelResize : Motion.panelCollapse
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: _powerRailHeight.targetValue > 0
                        ? Motion.emphasizedDecel : Motion.emphasizedAccel
                }
            }
            MotionBehavior on opacity {
                id: _powerRailFade
                NumberAnimation {
                    duration: Motion.fast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: _powerRailFade.targetValue > 0.5
                        ? Motion.standardDecel : Motion.standardAccel
                }
            }

            Loader {
                id: _powerRailLoader
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 9
                anchors.rightMargin: 9
                anchors.bottom: parent.bottom
                height: item ? item.implicitHeight : 0
                active: rail.menu.powerOpen || _powerRailSurface.height > 0.5
                sourceComponent: Component {
                    PowerRailContent { active: rail.menu.powerOpen }
                }
            }
        }

    }

    RailLabelGroup { id: _railLabels }

    Timer {
        id: _recentWarmDelay
        interval: 90
        onTriggered: if (_railRecent.hovered) rail.menu.warmRecent()
    }

    Timer {
        id: _settingsWarmDelay
        // ignore incidental sweeps down the icon rail; this is input intent detection, not visual motion, so reduce-motion does not collapse the delay to zero
        interval: 90
        onTriggered: if (_railSettings.hovered) rail.menu.warmSettings()
    }

    Rectangle {
        id: _railSelection
        // strip order is Home, Notifications, Settings; tabs are numbered 0, 2, 1
        readonly property int _slotIndex: rail.menu.activeTab === MenuState.mediaTab ? 3
            : rail.menu.activeTab === 2 ? 1
            : rail.menu.activeTab === 1 ? 2 : 0
        readonly property real _slot: _slotGlide.value
        SmoothGlide {
            id: _slotGlide
            target: _railSelection._slotIndex
            precision: 0.001
            gate: rail.menu._horizontalMotion
        }
        x: _railNav.x + (rail.menu.railCollapsedW - width) / 2
        y: _railNav.y + (_railHome.height - height) / 2
            + _slot * (_railHome.height + _railNav.spacing)
        // 30px is 37.5 device px at 1.25; whole pixels at a snapped position keep its outline even
        readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
        width: Metrics.devicePx(30, _dpr); height: width; radius: 9
        antialiasing: true
        color: Theme.menuControl
        transform: PixelSnap { item: _railSelection; dpr: _railSelection._dpr }
        OutlineBorder {
            radius: _railSelection.radius
            outlineColor: Theme.menuControlLine
        }
    }

    Column {
        id: _railNav
        width: rail.menu.railCollapsedW
        x: 0
        y: 10
        spacing: 6

        RailNavItem {
            id: _railHome
            labels: _railLabels
            glidingSelection: true
            railW: rail.menu.railCollapsedW
            glyph: "󰋜"
            label: "Home"
            labelPillEnabled: rail.labelsShown
            active: rail.menu.activeTab === 0
            onTapped: rail.menu.switchTab(0)
        }

        RailNavItem {
            id: _railRecent
            labels: _railLabels
            glidingSelection: true
            railW: rail.menu.railCollapsedW
            glyph: "󰋚"
            label: "Notifications"
            labelPillEnabled: rail.labelsShown
            active: rail.menu.activeTab === 2
            onTapped: rail.menu.switchTab(2)
            onHoveredChanged: {
                if (hovered) _recentWarmDelay.restart()
                else _recentWarmDelay.stop()
            }

            Rectangle {
                id: _railBadge
                readonly property bool _show: Notifications.hasHistory && !_railRecent.active
                readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
                anchors.horizontalCenter: parent.horizontalCenter
                // follows the icon's corner, which moves out as the rail's glyphs scale
                readonly property int _corner: Math.max(8, Math.round(Settings.iconSize * 0.62))
                anchors.horizontalCenterOffset: _corner
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -_corner
                // whole device pixels at a snapped position, like the rail selection beside it
                width: Metrics.devicePx(Math.max(height, _railBadgeCount.implicitWidth + 7), _dpr)
                height: Metrics.devicePx(Math.max(14, Settings.fontTiny + 4), _dpr); radius: height / 2
                transform: PixelSnap { item: _railBadge; dpr: _railBadge._dpr }
                color: Theme.accent; antialiasing: true
                opacity: _show ? 1.0 : 0.0
                scale:   _show ? 1.0 : 0.5
                visible: opacity > 0.01
                transformOrigin: Item.Center
                MotionBehavior on opacity {NumberAnimation { duration: Motion.fast } }
                MotionBehavior on scale   {NumberAnimation { duration: Motion.ms(120); easing.type: Easing.OutCubic } }
                OutlineBorder {
                    radius: parent.radius
                    outlineWidth: 2
                    outlineColor: Theme.menuPane
                }
                ShellText {
                    id: _railBadgeCount
                    anchors.fill: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: Notifications.historyCount > 99 ? "99+" : Notifications.historyCount
                    color: Theme.background
                    font.pixelSize: Settings.fontTiny
                    font.weight: Font.Bold
                }
            }
        }

        RailNavItem {
            id: _railSettings
            labels: _railLabels
            glidingSelection: true
            railW: rail.menu.railCollapsedW
            glyph: "󰒓"
            label: "Settings"
            labelPillEnabled: rail.labelsShown
            active: rail.menu.activeTab === 1
            onTapped: rail.menu.switchTab(1)
            onHoveredChanged: {
                if (hovered) _settingsWarmDelay.restart()
                else _settingsWarmDelay.stop()
            }
        }

        RailNavItem {
            id: _railMedia
            readonly property string _title: Media.displayTitle.length > 0
                ? Media.displayTitle : "Now Playing"
            visible: opacity > 0.01
            enabled: Media.shown
            opacity: Media.shown ? 1 : 0
            scale: Media.shown ? 1 : 0.8
            MotionBehavior on opacity { NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }
            MotionBehavior on scale { NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }
            labels: _railLabels
            glidingSelection: true
            railW: rail.menu.railCollapsedW
            label: _title.length > 32 ? _title.slice(0, 31) + "…" : _title
            labelPillEnabled: rail.labelsShown
            active: rail.menu.activeTab === MenuState.mediaTab
            onTapped: rail.menu.switchTab(MenuState.mediaTab)

            ClippingRectangle {
                id: _railCover
                readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
                anchors.centerIn: parent
                anchors.alignWhenCentered: false
                width: Metrics.devicePx(22, _dpr); height: width
                radius: 6
                color: Theme.menuControl
                opacity: Media.playing ? 1 : 0.55
                transform: PixelSnap { item: _railCover; dpr: _railCover._dpr }
                MotionBehavior on opacity { NumberAnimation { duration: Motion.medium } }

                ShellText {
                    anchors.centerIn: parent
                    opacity: 1 - _railArt.opacity
                    visible: opacity > 0.01
                    text: Media.metadataPrivacyProtected ? "󰌾" : "󰝚"
                    color: Theme.withAlpha(Theme.subtext, 0.70)
                    font.pixelSize: Settings.iconSize
                }
                Image {
                    id: _railArt
                    // the last cover stays up while the next one decodes, instead of blinking to the glyph
                    property bool _shown: false
                    anchors.fill: parent
                    source: _railMedia.visible ? Media.stableArtUrl : ""
                    onSourceChanged: if (String(source).length === 0) _shown = false
                    onStatusChanged: if (status === Image.Ready) _shown = true
                    retainWhileLoading: true
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    sourceSize.width: Math.ceil(_railCover.width * _railCover._dpr)
                    sourceSize.height: Math.ceil(_railCover.width * _railCover._dpr)
                    opacity: _shown ? 1 : 0
                    visible: opacity > 0.01
                    MotionBehavior on opacity { NumberAnimation { duration: Motion.fast } }
                }
                OutlineBorder {
                    z: 2
                    radius: _railCover.radius
                    outlineWidth: 1
                    outlineColor: Theme.menuControlLine
                }
            }
        }
    }

    Item {
        id: _railPowerSlot
        readonly property int gap: 10
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        anchors.left: parent.left
        width: rail.menu.railCollapsedW
        // derived, not summed: RailNavItem is rowHeightFor(34), which grows with the
        // font, so a hardcoded total drops the icon below its own inset at larger type
        height: _railDivider.height + _railPowerSlot.gap + _railPower.height
        z: 9

        Hairline {
            id: _railDivider
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: 18
            color: Theme.menuDivider
        }

        RailNavItem {
            id: _railPower
            labels: _railLabels
            anchors.top: _railDivider.bottom
            anchors.topMargin: _railPowerSlot.gap
            anchors.horizontalCenter: parent.horizontalCenter
            railW: rail.menu.railCollapsedW
            glyph: "󰐥"
            label: "Power"
            labelPillEnabled: rail.labelsShown
            accentColor: Theme.error
            active: rail.menu.powerOpen
            onTapped: rail.menu.powerOpen = !rail.menu.powerOpen
        }
    }
}
