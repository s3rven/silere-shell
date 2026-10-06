pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../config"
import "../services"
import "../modules/calendar"
import "../modules/notifications"
import "../modules/quickactions"
import "../modules/traymenu"

// run through test-panels.sh: real layer-shell backends, private settings, no mapped windows
Item {
    id: root
    required property ShellScreen targetScreen
    property int _checks: 0

    CalendarPopup { id: calendar; targetScreen: root.targetScreen; visible: false }
    QuickActionsPopup { id: actions; targetScreen: root.targetScreen; visible: false }
    TrayMenuPopup { id: tray; targetScreen: root.targetScreen; visible: false }
    NotificationPopups { id: notificationPopups; targetScreen: root.targetScreen; visible: false }
    QtObject { id: traySource; property string id: "popup-probe-tray" }
    QtObject { id: anonymousTraySource; property string id: "" }

    function _find(item, predicate): var {
        if (predicate(item)) return item
        const children = item.children || []
        for (let i = 0; i < children.length; i++) {
            const found = root._find(children[i], predicate)
            if (found) return found
        }
        return null
    }

    function _check(ok: bool, message: string): void {
        root._checks++
        if (!ok) console.warn("PROBE-FAIL popup interactions :: " + message)
    }

    function _isDate(date, year: int, month: int, day: int): bool {
        return date.getFullYear() === year && date.getMonth() === month && date.getDate() === day
    }

    function _checkCalendar(): void {
        const card = calendar.popupCard
        root._check(card !== null, "calendar card exists")
        if (!card) return

        ShellSettings.reduceMotion = true
        ShellSettings.calendarWeekStart = "monday"
        CalendarState.open = true
        card._go(2026, 0, -1)
        root._check(root._isDate(card._dateForCell(0), 2025, 11, 29),
            "January's leading cells belong to the previous year")
        const leading = root._find(card, item => item.index === 0 && item.date !== undefined)
        root._check(leading !== null && leading.Accessible.name.indexOf("2025") >= 0,
            "adjacent cells announce their actual year")
        card._activateDay(0)
        root._check(card.shownYear === 2025 && card.shownMonth === 11,
            "clicking a leading date navigates to the previous month")
        card._go(2026, 11, 1)
        card._activateDay(card._lead + card._daysThis)
        root._check(card.shownYear === 2027 && card.shownMonth === 0,
            "clicking a trailing date navigates into the next year")

        card._go(2024, 1, -1)
        const leapIndex = card._lead + 28
        root._check(root._isDate(card._dateForCell(leapIndex), 2024, 1, 29),
            "the grid includes leap day")
        card._activateDay(leapIndex)
        root._check(card.shownYear === 2024 && card.shownMonth === 1,
            "current-month dates are passive")
        const current = root._find(card, item => item.index === leapIndex && item.date !== undefined)
        root._check(current !== null && current.Accessible.role === Accessible.StaticText,
            "current-month dates are announced as text rather than controls")

        ShellSettings.reduceMotion = false
        card._go(2024, 2, 1)
        card._activateDay(0)
        root._check(card.dispMonth === 2,
            "a date cannot retarget navigation while the grid is changing months")
        ShellSettings.reduceMotion = true

        ShellSettings.calendarWeekStart = "sunday"
        card._go(2026, 0, 1)
        root._check(root._isDate(card._dateForCell(0), 2025, 11, 28),
            "adjacent dates follow the configured week start")
        card._activateDay(-1)
        card._activateDay(card._rowCount * 7)
        CalendarState.open = false
        card._activateDay(card._lead)
        root._check(card.dispYear === 2026 && card.dispMonth === 0,
            "invalid indices and closed calendars cannot navigate")

        const baseCell = card.cell
        ShellSettings.uiScale = ShellSettings.schemaFor("uiScale").max
        root._check(card.cell > baseCell && card.gridW === card.weekCol + card.cell * 7,
            "date targets and grid width grow with interface scaling")
        ShellSettings.uiScale = 1
    }

    function _checkActions(): void {
        const row = root._find(actions.popupCard, item => item.label === "Do Not Disturb")
        root._check(row !== null, "quick-action row exists")
        if (!row) return
        ShellSettings.dnd = false
        ShellSettings.dndSchedule = true
        ShellSettings.dndFrom = DateTime.hour24
        ShellSettings.dndTo = (DateTime.hour24 + 1) % 24
        root._check(Notifications.silencingActive && row.highlighted
            && !row.active && !row.Accessible.checked,
            "quiet hours are highlighted without announcing manual DND as checked")
        ShellSettings.dndSchedule = false
        const wasDnd = Notifications.dnd
        let triggered = false
        row.triggered.connect(() => { triggered = true })
        row.enabled = false
        row.warning = true
        row.detailText = "Blocked by the hardware switch"
        root._check(row.opacity === 1 && row.height > row._mainHeight,
            "disabled warnings remain readable and reserve space for their explanation")
        row._activate()
        root._check(!triggered && Notifications.dnd === wasDnd,
            "a disabled row cannot invoke its action")
        root._check(row.Accessible.description.indexOf(row.detailText) >= 0,
            "assistive readers receive the explanation")

        row.enabled = true
        row.warning = false
        row.detailText = ""
        root._check(row.height === row._mainHeight,
            "clearing a message restores the compact row")

        row.error = true
        row.detailText = "Could not change the power mode: " + "x".repeat(160)
        const detail = root._find(row, item => item.text === row.detailText)
        root._check(detail !== null && detail.wrapMode === Text.Wrap
            && detail.width < row.width && row.height >= detail.y + detail.implicitHeight,
            "long error messages wrap inside the row's bounds")
    }

    function _checkTray(): void {
        ShellSettings.trayWidget = true
        ShellSettings.trayHidden = ""
        ShellSettings.reduceMotion = true
        TrayMenuState.toggleAt(100, root.targetScreen, null, false, null, traySource)
        const hideRow = root._find(tray.popupCard,
            item => item.trayId === traySource.id && typeof item.hide === "function")
        root._check(hideRow !== null && hideRow.enabled,
            "a menu-less app has its own enabled hide action")
        const baseWidth = tray.menuWidth
        const baseHeight = hideRow ? hideRow.height : 0
        ShellSettings.uiScale = ShellSettings.schemaFor("uiScale").max
        root._check(tray.menuWidth > baseWidth && hideRow && hideRow.height > baseHeight,
            "tray menus and their click targets grow with interface scaling")
        ShellSettings.uiScale = 1

        let triggered = 0
        const action = { triggered: function() { triggered++ } }
        tray._activateEntry({ on: false, sub: false, modelData: action })
        root._check(triggered === 0 && TrayMenuState.open,
            "disabled tray menu entries cannot trigger or close the menu")
        let opened = true
        tray._activateEntry({ on: true, sub: true,
            _openFlyout: function() { opened = true } })
        root._check(opened && TrayMenuState.open && triggered === 0,
            "clicking a submenu already opened by hover keeps that branch open")
        tray._activateEntry({ on: true, sub: false, modelData: action })
        root._check(triggered === 1 && !TrayMenuState.open,
            "a leaf tray action triggers exactly once and closes the menu")
        if (hideRow) hideRow.hide()
        tray._activateEntry({ on: true, sub: false, modelData: action })
        root._check(triggered === 1 && !ShellSettings.trayItemHidden(traySource.id),
            "a closed tray popup cannot trigger its fading actions")
        TrayMenuState.toggleAt(100, root.targetScreen, null, false, null, traySource)
        if (hideRow) hideRow.hide()
        root._check(!TrayMenuState.open && ShellSettings.trayItemHidden(traySource.id),
            "the hide action hides only its tray app and closes the popup")
        ShellSettings.trayHidden = ""

        TrayMenuState.toggleAt(100, root.targetScreen, null, false, null, traySource)
        TrayMenuState.toggleAt(100, root.targetScreen, null, false, null, anonymousTraySource)
        root._check(hideRow && !hideRow.visible && hideRow.trayId.length === 0,
            "switching to an app without an ID clears the previous app's hide action")
        if (hideRow) hideRow.hide()
        root._check(TrayMenuState.open && !ShellSettings.trayItemHidden(traySource.id),
            "an anonymous app cannot hide the previous tray app")

        TrayMenuState.toggleAt(100, root.targetScreen, null, false, null, traySource)
        TrayMenuState.toggleAt(100, root.targetScreen, null, false, null, null)
        root._check(hideRow && !hideRow.visible && hideRow.trayId.length === 0,
            "opening without a source clears any latched hide action")
        if (hideRow) hideRow.hide()
        root._check(TrayMenuState.open && !ShellSettings.trayItemHidden(traySource.id),
            "a source-less popup cannot hide the previous tray app")
        TrayMenuState.close()
    }

    // the oversized MouseArea a popup keeps for clicks hyprland routes to its exclusive-focus window
    function _offMonitorCatcher(scope): var {
        return root._find(scope, item => item.pressAndHoldInterval !== undefined
            && item.acceptedButtons !== undefined && item.width > 20000)
    }

    function _catchesEveryButton(area): bool {
        return (area.acceptedButtons & Qt.LeftButton) !== 0
            && (area.acceptedButtons & Qt.RightButton) !== 0
            && (area.acceptedButtons & Qt.MiddleButton) !== 0
    }

    function _checkDismissal(): void {
        const fitted = [
            { name: "calendar", popup: calendar, state: CalendarState },
            { name: "quick actions", popup: actions, state: QuickActionsState },
            { name: "tray menu", popup: tray, state: TrayMenuState }
        ]
        for (const f of fitted) {
            const card = f.popup.popupCard
            const stage = card.parent
            const catcher = root._offMonitorCatcher(stage)
            const origin = catcher ? catcher.mapToItem(stage, 0, 0) : Qt.point(0, 0)
            root._check(catcher !== null && origin.x < -10000 && origin.y < -10000
                    && catcher.width > stage.width + 20000 && catcher.height > stage.height + 20000
                    && root._catchesEveryButton(catcher),
                f.name + " catches clicks of every button, also those offset onto another monitor")
            f.state.open = true
            const centre = Qt.point(card.x + card.width / 2, card.y + card.height / 2)
            f.popup._closeIfOutside(centre)
            root._check(f.state.open && !f.popup._outsideCard(centre),
                "a click on the " + f.name + " card keeps it open")
            f.popup._closeIfOutside(Qt.point(-5000, 40))
            root._check(!f.state.open, "a click on another monitor closes " + f.name)
        }
    }

    Component {
        id: fakeSubmenu
        Item { property bool opened: true; readonly property bool popupSurface: opened }
    }

    // submenus sit beside the card in the fitted strip, so the strip must reach them and a click on one is not outside
    function _checkTraySubmenus(): void {
        ShellSettings.reduceMotion = true
        const card = tray.popupCard
        const winW = card.winW
        const step = tray.menuWidth + 12
        let covered = 0
        for (const anchorX of [0, winW * 0.25, winW * 0.5, winW * 0.75, winW - 200, winW]) {
            TrayMenuState.toggleAt(anchorX, root.targetScreen, null, false, null, traySource)
            const l1 = Metrics.flyoutX(card.x + card.pad, tray.menuWidth, step, winW)
            const l2 = Metrics.flyoutX(l1 + 6, tray.menuWidth, step, winW)
            const lo = Math.min(l1, l2), hi = Math.max(l1, l2) + step
            if (card.placementSpan.x - tray.reachLeft <= lo
                    && card.placementSpan.y + card.targetWidth + tray.reachRight >= hi) covered++
            TrayMenuState.close()
        }
        root._check(covered === 6, "the tray strip keeps room for two submenu levels wherever the card sits")

        TrayMenuState.toggleAt(winW - 200, root.targetScreen, null, false, null, traySource)
        const sub = fakeSubmenu.createObject(tray.stage, { x: 40, y: card.y, width: step, height: 120 })
        const inside = Qt.point(sub.x + 10, sub.y + 10)
        tray._closeIfOutside(inside)
        root._check(TrayMenuState.open && !tray._outsideCard(inside) && tray._surfaceOpen,
            "a click on an open submenu keeps the tray menu open")
        root._check(card.placementSpan.x - tray.reachLeft <= sub.x,
            "the tray strip grows to reach a submenu past its two reserved levels")
        sub.opened = false
        sub.visible = false
        root._check(card.placementSpan.x - tray.reachLeft <= 40,
            "the tray strip keeps its width while the menu stays open after a deeper submenu fades")
        tray._closeIfOutside(inside)
        root._check(!TrayMenuState.open && !tray._surfaceOpen,
            "a click where a submenu has closed closes the tray menu")
        sub.destroy()
    }

    function _checkReplyFocus(): void {
        const popups = notificationPopups
        const focus = () => popups.WlrLayershell.keyboardFocus
        const owner = name => ({
            name: name, cancelled: 0,
            cancelReply: function() { this.cancelled++; popups._setReplyFocus(this, false) },
            focusReplyInput: function() {}
        })
        const first = owner("first")
        const second = owner("second")
        root._check(focus() === WlrKeyboardFocus.None, "notifications take no keys without a reply")
        popups._setReplyFocus(first, true)
        root._check(focus() === WlrKeyboardFocus.Exclusive,
            "starting a reply takes the keys at once, without waiting for the pointer to move")
        popups._setReplyFocus(second, true)
        const grab = (popups.contentItem.data || []).find(o => o && o.interval === 200 && o.running === true)
        root._check(first.cancelled === 1 && focus() === WlrKeyboardFocus.Exclusive && grab !== undefined,
            "a second reply cancels the first and takes the keys again")
        if (grab) grab.stop()
        root._check(focus() === WlrKeyboardFocus.OnDemand,
            "after the grab a reply is on demand, so clicking another window still works")
        popups._setReplyFocus(first, false)
        root._check(focus() === WlrKeyboardFocus.OnDemand,
            "a cancelled reply cannot release the keys of the reply that replaced it")
        popups._setReplyFocus(second, false)
        root._check(focus() === WlrKeyboardFocus.None, "closing the reply hands the keys back")
    }

    function _run(): void {
        root._checkCalendar()
        root._checkActions()
        root._checkTray()
        root._checkDismissal()
        root._checkTraySubmenus()
        root._checkReplyFocus()
        console.warn("PROBE-POPUP-INTERACTIONS checked " + root._checks + " behaviors")
    }

    Component.onCompleted: Qt.callLater(root._run)
}
