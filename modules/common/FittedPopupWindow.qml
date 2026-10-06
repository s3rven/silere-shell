pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../services"

PanelWindow {
    id: win

    required property ShellScreen targetScreen
    property bool open: false
    property string layerNamespace: "silere-popup"
    property FloatingPopupCard popupCard: null
    default property alias stageData: _stage.data
    // screen coordinates, for anything placed beside the card such as submenus
    readonly property Item stage: _stage
    // room the strip keeps past the card on each side, for what opens beside it
    property real reachLeft: 0
    property real reachRight: 0

    signal dismissed()
    signal escapePressed()

    readonly property string _output: Compositor.monitorName(win.screen)

    Connections {
        target: Compositor
        function onWorkspaceActivated(output) {
            if (output === win._output && win.open) win.dismissed()
        }
    }

    // full screen only to catch the closing click: the compositor recomposites every pixel of a surface Qt redraws, so the card animates in its own narrow window
    screen:        targetScreen
    color:         "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: win.layerNamespace
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    visible: win.open || cardWin.visible
    // layer surfaces stack in map order: mapped after the card, this window would cover it and take its clicks
    property bool _cardMayMap: false
    onVisibleChanged: {
        if (visible) Qt.callLater(() => win._cardMayMap = win.visible)
        else win._cardMayMap = false
    }

    anchors { top: true; left: true; right: true; bottom: true }

    Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut; enabled: win.open; onActivated: win.escapePressed() }

    OutsideTapGuard {
        id: _tapGuard
        open: win.open
    }

    Item { id: _fillArea; anchors.fill: parent }
    mask: Region { item: win.open ? _fillArea : null }
    // an empty region, not none: the popup's layer rule would otherwise blur the whole screen behind this window
    BackgroundEffect.blurRegion: Region { item: null }

    // a stage item beside the card that a click may land on marks itself popupSurface, as a submenu does
    readonly property bool _surfaceOpen: {
        const kids = _stage.children
        for (let i = 0; i < kids.length; i++)
            if (kids[i] && kids[i].popupSurface === true) return true
        return false
    }

    function _overSurface(p: point): bool {
        const kids = _stage.children
        for (let i = 0; i < kids.length; i++) {
            const k = kids[i]
            if (!k || k.popupSurface !== true) continue
            const local = k.mapFromItem(_stage, p.x, p.y)
            if (local.x >= 0 && local.x <= k.width && local.y >= 0 && local.y <= k.height) return true
        }
        return false
    }

    function _outsideCard(p: point): bool {
        const c = win.popupCard
        if (c && p.x >= c.x && p.x <= c.x + c.width && p.y >= c.y && p.y <= c.y + c.height) return false
        return !win._overSurface(p)
    }

    function _closeIfOutside(p: point): void {
        if (!_tapGuard.ignoring && _outsideCard(p)) win.dismissed()
    }

    TapHandler {
        id: _dismiss
        enabled: win.open
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onTapped: win._closeIfOutside(_dismiss.point.position)
    }

    PanelWindow {
        id: cardWin

        // room for the shadow; snapped so a moving anchor rarely reconfigures the surface
        readonly property int _slack: 48
        readonly property real _screenW: win.screen ? win.screen.width : 0
        readonly property point _span: win.popupCard ? win.popupCard.placementSpan : Qt.point(0, 0)
        readonly property real _targetW: win.popupCard ? win.popupCard.targetWidth : 0
        readonly property int _left: Math.max(0,
            64 * Math.floor((cardWin._span.x - _slack - win.reachLeft) / 64))
        readonly property int _right: Math.min(Math.ceil(_screenW),
            64 * Math.ceil((cardWin._span.y + cardWin._targetW + _slack + win.reachRight) / 64))

        screen:        win.screen
        color:         "transparent"
        exclusiveZone: -1
        WlrLayershell.namespace: win.layerNamespace
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: win.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        visible: (win.open || (win.popupCard !== null && win.popupCard.opacity > 0.001)) && win._cardMayMap

        anchors { top: true; bottom: true; left: true }
        margins.left: cardWin._left
        implicitWidth: Math.max(1, cardWin._right - cardWin._left)

        // the card alone: anywhere else in the strip has to fall through to the closing window below. With a surface open beside it the whole strip, so a gap between the two still reaches the outside catch
        mask: Region {
            item: !win.open ? null : win._surfaceOpen ? _stage : win.popupCard
            Region { item: _stage; intersection: Intersection.Intersect }
        }
        BackgroundEffect.blurRegion: Region {
            item: win.popupCard ? win.popupCard.blurItem : null
            radius: win.popupCard ? Math.round(win.popupCard.radius) : 0
            // a region rebuilds only when one of its own items moves, and the stage carries every card x shift
            Region { item: _stage; intersection: Intersection.Intersect }
        }

        // screen coordinates: the card places itself as it did in a full-screen window
        Item {
            id: _stage
            x: -cardWin._left
            width: cardWin._screenW
            height: parent.height

            // hyprland hands every click to the exclusive-focus surface, so one outside the card lands here, not on the window below; a MouseArea because pointer handlers drop points outside their window, oversized because a click on another monitor arrives offset by the layout
            MouseArea {
                id: _outsideCatch
                anchors.fill: parent
                anchors.margins: -16384
                enabled: win.open
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onPressed: mouse => mouse.accepted = win._outsideCard(_outsideCatch.mapToItem(_stage, mouse.x, mouse.y))
                onClicked: mouse => win._closeIfOutside(_outsideCatch.mapToItem(_stage, mouse.x, mouse.y))
            }
        }
    }
}
