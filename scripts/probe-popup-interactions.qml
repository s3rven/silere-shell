pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../config"
import "../services"
import "../modules/calendar"
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
        const hideRow = root._find(tray.contentItem,
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

    function _run(): void {
        root._checkCalendar()
        root._checkActions()
        root._checkTray()
        console.warn("PROBE-POPUP-INTERACTIONS checked " + root._checks + " behaviors")
    }

    Component.onCompleted: Qt.callLater(root._run)
}
