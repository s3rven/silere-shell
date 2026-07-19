pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../services"
import "../common"

// mirrors MenuWindow's full-screen mask so an outside tap dismisses without an exclusive zone
PanelWindow {
    id: win

    required property ShellScreen targetScreen

    readonly property string _output: Compositor.monitorName(win.screen)
    property bool _ignoreOutsideTap: false

    Connections {
        target: Compositor
        function onWorkspaceActivated(output) {
            if (output === win._output && CalendarState.open) CalendarState.close()
        }
    }

    screen:        targetScreen
    color:         "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: "silere-calendar"
    WlrLayershell.keyboardFocus: CalendarState.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // unmap the full-screen surface while closed so it isn't holding a screen-sized GPU buffer at rest; stay mapped through the close anim, then drop
    visible: CalendarState.open || card.opacity > 0.001

    anchors { top: true; left: true; right: true; bottom: true }

    Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut; enabled: CalendarState.open; onActivated: CalendarState.close() }

    Connections {
        target: ShellSettings
        function onBarPositionChanged() {
            if (!CalendarState.open) {
                card.edgeOffset = card._closedOffset
                return
            }
            win._ignoreOutsideTap = true
            _outsideTapGuard.restart()
        }
    }

    Connections {
        target: CalendarState
        function onOpenChanged() {
            if (!CalendarState.open) {
                _outsideTapGuard.stop()
                win._ignoreOutsideTap = false
            }
        }
    }

    Timer {
        id: _outsideTapGuard
        interval: 250
        repeat: false
        onTriggered: win._ignoreOutsideTap = false
    }

    Item { id: _fillArea; anchors.fill: parent }
    mask: Region { item: CalendarState.open ? _fillArea : null }

    TapHandler {
        id: _dismiss
        enabled: CalendarState.open && card.scaleAmt > 0.95
        onTapped: {
            if (win._ignoreOutsideTap) return
            const p = _dismiss.point.position
            if (p.x < card.x || p.x > card.x + card.width ||
                p.y < card.y || p.y > card.y + card.height)
                CalendarState.close()
        }
    }

    Loader {
        active: CalendarState.open && ShellSettings.barFloating && ShellSettings.barShadow
        anchors.fill: card
        opacity: card.opacity
        z: -1
        sourceComponent: FloatingShadow {
            radius: card.radius
            atBottom: card.barBottom
        }
    }

    FloatingPopupCard {
        id: card
        win: win
        open: CalendarState.open
        anchorX: CalendarState.anchorX
        barBottom: ShellSettings.barPosition === "bottom"

        readonly property int  cell:     34
        readonly property int  pad:      14
        readonly property int  weekCol:  22   // ISO week-number axis, left of the grid
        readonly property int  panelW:   weekCol + cell * 7 + pad * 2

        // two month cursors: `disp*` leads (header, instant on nav), `shown*` trails.
        // grid renders `shown*`, catches up at the slide mid-point so the swap reads as one motion.
        property int dispYear:  2000
        property int dispMonth: 0
        property int shownYear:  2000
        property int shownMonth: 0
        property int navDir:     0      // -1 prev, +1 next — drives the slide direction

        // "today" captured fresh on each open — the card persists, so a readonly `new Date()` binding would freeze at first build and highlight the wrong day forever
        property int    _todayY:      -1
        property int    _todayM:      -1
        property int    _todayD:      -1
        property int    _todayWeek:   -1
        property string todayWeekday: ""

        // Monday-start.
        readonly property int _firstJs:  new Date(shownYear, shownMonth, 1).getDay()   // 0 = Sun
        readonly property int _lead:     (_firstJs + 6) % 7
        readonly property int _daysThis: new Date(shownYear, shownMonth + 1, 0).getDate()
        readonly property int _daysPrev: new Date(shownYear, shownMonth,     0).getDate()
        readonly property int _todayCell:
            (_todayY === shownYear && _todayM === shownMonth) ? _lead + _todayD - 1 : -1
        // rows this month needs (4–6); avoids a permanent blank 6th row
        readonly property int _rowCount: Math.ceil((_lead + _daysThis) / 7)
        // bound to the trailing cursor so the title swaps with the grid mid-slide
        readonly property string monthLabel: Qt.formatDateTime(new Date(shownYear, shownMonth, 1), "MMMM yyyy")

        // ISO week for grid row r — column 0 is the row's Monday; JS normalises the offset.
        function _weekForRow(r: int): int {
            return DateTime.isoWeek(new Date(card.shownYear, card.shownMonth, 1 - card._lead + r * 7))
        }

        // Snap both cursors (no slide), used on open so it just shows this month.
        function _snapToday(): void {
            const t = new Date()
            _todayY = t.getFullYear(); _todayM = t.getMonth(); _todayD = t.getDate()
            _todayWeek = DateTime.isoWeek(t)
            todayWeekday = Qt.formatDateTime(t, "dddd")
            dispYear  = _todayY; dispMonth  = _todayM
            shownYear = _todayY; shownMonth = _todayM
            _gridSwap.stop(); _grid.opacity = 1; _grid.xOff = 0
        }
        // Animated move to (y, m); dir picks the slide direction.
        function _go(y: int, m: int, dir: int): void {
            navDir = dir
            dispYear = y; dispMonth = m
            if (ShellSettings.reduceMotion) { _gridSwap.stop(); shownYear = y; shownMonth = m; _grid.opacity = 1; _grid.xOff = 0; return }
            _gridSwap.restart()
        }
        function _step(delta: int): void {
            let m = dispMonth + delta, y = dispYear
            while (m < 0)  { m += 12; y-- }
            while (m > 11) { m -= 12; y++ }
            _go(y, m, delta < 0 ? -1 : 1)
        }
        function _goToday(): void {
            const t = new Date()
            const cur = dispYear * 12 + dispMonth
            const tgt = t.getFullYear() * 12 + t.getMonth()
            if (tgt === cur) return
            _go(t.getFullYear(), t.getMonth(), tgt > cur ? 1 : -1)
        }
        function _activateToday(event): void {
            if (!event.isAutoRepeat) card._goToday()
            event.accepted = true
        }
        Connections {
            target: CalendarState
            function onOpenChanged() {
                if (CalendarState.open) {
                    card._snapToday()
                    card.forceActiveFocus()
                }
            }
        }
        // keep "today" current if held open across midnight, without yanking the user back from a navigated month
        Connections {
            target: DateTime
            function onCachedDateCoreChanged() {
                if (!CalendarState.open) return
                const t = new Date()
                card._todayY = t.getFullYear(); card._todayM = t.getMonth(); card._todayD = t.getDate()
                card._todayWeek = DateTime.isoWeek(t)
                card.todayWeekday = Qt.formatDateTime(t, "dddd")
            }
        }
        Component.onCompleted: card._snapToday()

        // month swap: old grid slides out + fades, shown cursor catches up at 0 opacity, new grid slides in from the other side + fades.
        // next moves the page left (content advances), prev moves it right.
        SequentialAnimation {
            id: _gridSwap
            ParallelAnimation {
                NumberAnimation { target: _grid; property: "opacity"; to: 0;                duration: Motion.fast; easing.type: Easing.InCubic }
                NumberAnimation { target: _grid; property: "xOff";    to: -card.navDir * 20; duration: Motion.fast; easing.type: Easing.InCubic }
            }
            ScriptAction {
                script: {
                    card.shownYear = card.dispYear
                    card.shownMonth = card.dispMonth
                    _grid.xOff = card.navDir * 20
                }
            }
            ParallelAnimation {
                NumberAnimation { target: _grid; property: "opacity"; to: 1; duration: Motion.normal; easing.type: Easing.OutCubic }
                NumberAnimation { target: _grid; property: "xOff";    to: 0; duration: Motion.medium; easing.type: Easing.OutCubic }
            }
        }

        width:  panelW
        height: _col.implicitHeight + pad * 2
        activeFocusOnTab: true
        Accessible.role: Accessible.Pane
        Accessible.name: "Calendar"

        Keys.onLeftPressed:  event => { card._step(-1); event.accepted = true }
        Keys.onRightPressed: event => { card._step(1);  event.accepted = true }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_PageUp) {
                card._step(-1)
                event.accepted = true
            } else if (event.key === Qt.Key_PageDown) {
                card._step(1)
                event.accepted = true
            } else if (event.key === Qt.Key_Home) {
                card._goToday()
                event.accepted = true
            }
        }

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (e) => {
                const n = Scroll.processControlWheel(e, "calendar")
                if (n !== 0) card._step(n > 0 ? -Math.abs(n) : Math.abs(n))
            }
        }

        Column {
            id: _col
            x: card.pad; y: card.pad
            width: card.panelW - card.pad * 2
            spacing: 6

            Item {
                id: _todayButton
                width: parent.width
                height: 40
                activeFocusOnTab: true

                Accessible.role: Accessible.Button
                Accessible.name: "Jump to today"
                Keys.onSpacePressed:  event => card._activateToday(event)
                Keys.onReturnPressed: event => card._activateToday(event)
                Keys.onEnterPressed:  event => card._activateToday(event)

                HoverHandler { id: _todayH; cursorShape: Qt.PointingHandCursor }
                TapHandler   { onTapped: card._goToday() }

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 11

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: card._todayD < 0 ? "" : card._todayD
                        color: Theme.accent
                        font.family: Settings.font; font.pixelSize: Settings.fontSize + 15; font.weight: Font.DemiBold
                        renderType: Text.NativeRendering
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text {
                            text: card.todayWeekday
                            color: (_todayH.hovered || _todayButton.activeFocus) ? Theme.text : Theme.withAlpha(Theme.text, 0.9)
                            font.family: Settings.font; font.pixelSize: Settings.fontSize + 1; font.weight: Font.DemiBold
                            renderType: Text.NativeRendering
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                        }
                        Text {
                            visible: card._todayWeek > 0
                            text: "Week " + card._todayWeek
                            color: Theme.withAlpha(Theme.subtext, 0.45)
                            font.family: Settings.font; font.pixelSize: Settings.fontSize - 2
                            renderType: Text.NativeRendering
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.withAlpha(Theme.subtext, 0.13) }

            Item {
                width: parent.width
                height: 30

                IconButton {
                    id: _prevButton
                    buttonSize: 26
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "󰅁"
                    accessibleName: "Previous month"
                    onTriggered: card._step(-1)
                }

                Item {
                    id: _monthButton
                    anchors.centerIn: parent
                    width: _mLabel.implicitWidth + 16; height: 26
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: "Jump to today"
                    Keys.onSpacePressed:  event => card._activateToday(event)
                    Keys.onReturnPressed: event => card._activateToday(event)
                    Keys.onEnterPressed:  event => card._activateToday(event)
                    HoverHandler { id: _mH; cursorShape: Qt.PointingHandCursor }
                    TapHandler   { onTapped: card._goToday() }
                    Text {
                        id: _mLabel
                        anchors.centerIn: parent
                        text: card.monthLabel
                        color: (_mH.hovered || _monthButton.activeFocus) ? Theme.text : Theme.withAlpha(Theme.text, 0.9)
                        font.family: Settings.font; font.pixelSize: Settings.fontSize + 1; font.weight: Font.DemiBold
                        renderType: Text.NativeRendering
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }
                }

                IconButton {
                    id: _nextButton
                    buttonSize: 26
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "󰅂"
                    accessibleName: "Next month"
                    onTriggered: card._step(1)
                }
            }

            Row {
                width: parent.width
                Item { width: card.weekCol; height: 22 }   // week-axis header slot
                Repeater {
                    model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                    delegate: Item {
                        id: dayHdr
                        required property int index
                        required property string modelData
                        width: card.cell; height: 22
                        Text {
                            anchors.centerIn: parent
                            text: dayHdr.modelData
                            color: Theme.withAlpha(Theme.subtext, dayHdr.index >= 5 ? 0.4 : 0.6)   // weekends quieter
                            font.family: Settings.font; font.pixelSize: Settings.fontSize - 3
                            font.weight: Font.Medium; font.capitalization: Font.AllUppercase
                            renderType: Text.NativeRendering
                        }
                    }
                }
            }

            // Day grid: a month change re-evaluates cell bindings, no delegate churn.
            Item {
                id: _gridWrap
                width: parent.width
                height: card._rowCount * card.cell
                clip: true
                Behavior on height {
                    enabled: !ShellSettings.reduceMotion
                    NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
                }

                // keyboard marks: one tab stop, arrows walk the month, Space toggles
                property int kbdIndex: -1
                readonly property int _kbdDay: kbdIndex - card._lead + 1
                activeFocusOnTab: true
                Accessible.role: Accessible.List
                Accessible.name: activeFocus && kbdIndex >= 0
                    ? Qt.formatDate(new Date(card.shownYear, card.shownMonth, _kbdDay), "d MMMM yyyy")
                    : "Calendar days"
                onActiveFocusChanged: if (activeFocus) kbdIndex = card._todayCell >= 0 ? card._todayCell : card._lead
                function _move(d: int): void {
                    kbdIndex = Math.max(card._lead, Math.min(card._lead + card._daysThis - 1, kbdIndex + d))
                }
                // month nav while focused: re-clamp so the ring can't sit on a spillover cell
                Connections {
                    target: card
                    function onShownMonthChanged() { if (_gridWrap.kbdIndex >= 0) _gridWrap._move(0) }
                    function onShownYearChanged()  { if (_gridWrap.kbdIndex >= 0) _gridWrap._move(0) }
                }
                function _toggle(event: var): void {
                    if (!event.isAutoRepeat && kbdIndex >= card._lead && _kbdDay <= card._daysThis)
                        CalendarState.toggleMark(card.shownYear, card.shownMonth, _kbdDay)
                    event.accepted = true
                }
                Keys.onLeftPressed:   e => { _gridWrap._move(-1); e.accepted = true }
                Keys.onRightPressed:  e => { _gridWrap._move(1);  e.accepted = true }
                Keys.onUpPressed:     e => { _gridWrap._move(-7); e.accepted = true }
                Keys.onDownPressed:   e => { _gridWrap._move(7);  e.accepted = true }
                Keys.onSpacePressed:  e => _gridWrap._toggle(e)
                Keys.onReturnPressed: e => _gridWrap._toggle(e)
                Keys.onEnterPressed:  e => _gridWrap._toggle(e)

                // ISO week axis — fixed reference the month slides beneath; fades with the grid swap so numbers change while invisible
                Column {
                    id: _weekAxis
                    x: 0
                    width: card.weekCol
                    opacity: _grid.opacity
                    Repeater {
                        model: card._rowCount
                        delegate: Item {
                            id: _weekRow
                            required property int index
                            width: card.weekCol
                            height: card.cell
                            Text {
                                anchors.centerIn: parent
                                text: card._weekForRow(_weekRow.index)
                                color: Theme.withAlpha(Theme.subtext, 0.38)
                                font.family: Settings.font
                                font.pixelSize: Settings.fontSize - 4
                                font.weight: Font.Medium
                                renderType: Text.NativeRendering
                            }
                        }
                    }
                }

                Rectangle {
                    x: card.weekCol - 1
                    y: 0
                    width: 1
                    height: parent.height
                    color: Theme.withAlpha(Theme.subtext, 0.10)
                }

                Grid {
                    id: _grid
                    property real xOff: 0
                    x: card.weekCol + xOff
                    width: card.cell * 7
                    columns: 7
                    // Layer only during the slide so translated NativeRendering text stays crisp.
                    layer.enabled: _gridSwap.running && !ShellSettings.reduceMotion

                    Repeater {
                        model: card._rowCount * 7
                        delegate: Item {
                            id: _dayCell
                            required property int index

                            readonly property bool cur:   index >= card._lead && index < card._lead + card._daysThis
                            readonly property bool today: index === card._todayCell
                            readonly property bool marked: cur
                                && CalendarState.marks[CalendarState.markKey(card.shownYear, card.shownMonth, dayNum)] === true
                            readonly property int  dayNum:
                                  index < card._lead                  ? card._daysPrev - card._lead + 1 + index
                                : index < card._lead + card._daysThis ? index - card._lead + 1
                                :                                       index - card._lead - card._daysThis + 1

                            width: card.cell; height: card.cell

                            Rectangle {
                                anchors.centerIn: parent
                                width: 30; height: 30; radius: 15
                                antialiasing: true
                                color: _dayCell.today ? Theme.accent
                                     : (_dayH.hovered && _dayCell.cur ? Theme.withAlpha(Theme.subtext, 0.10) : "transparent")
                                Behavior on color { ColorAnimation { duration: Motion.fast } }

                                HoverHandler { id: _dayH; enabled: _dayCell.cur; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    enabled: _dayCell.cur
                                    onTapped: CalendarState.toggleMark(card.shownYear, card.shownMonth, _dayCell.dayNum)
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: _dayCell.dayNum
                                    color: _dayCell.today ? Theme.surface
                                         : _dayCell.cur   ? Theme.withAlpha(Theme.text, 0.9)
                                         :                  Theme.withAlpha(Theme.subtext, 0.3)
                                    font.family: Settings.font
                                    font.pixelSize: Settings.fontSize
                                    font.weight: _dayCell.today ? Font.DemiBold : Font.Normal
                                    renderType: Text.NativeRendering
                                }

                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom; anchors.bottomMargin: 3
                                    width: 4; height: 4; radius: 2
                                    antialiasing: true
                                    color: _dayCell.today ? Theme.surface : Theme.accent
                                    opacity: _dayCell.marked ? 1 : 0
                                    scale:   _dayCell.marked ? 1 : 0.3
                                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                                    Behavior on scale   { enabled: !ShellSettings.reduceMotion; NumberAnimation { duration: Motion.ms(125); easing.type: Easing.OutCubic } }
                                }

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 30; height: 30; radius: 15
                                    antialiasing: true
                                    color: "transparent"
                                    border.width: 2
                                    border.color: Theme.withAlpha(Theme.accent, 0.6)
                                    visible: _gridWrap.activeFocus && _dayCell.index === _gridWrap.kbdIndex
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
