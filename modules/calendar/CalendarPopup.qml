import QtQuick
import Quickshell
import Quickshell.Wayland._WlrLayerShell
import Quickshell.Hyprland
import "../../config"
import "../../services"

// Month calendar that pops beneath the bar clock. Render-only, it exists while
// open and holds nothing at rest. Click the clock to toggle; Escape or a click
// outside the card closes it; ←/→ step months. Mirrors MenuWindow's full-screen
// mask so an outside tap dismisses cleanly without an exclusive zone.
PanelWindow {
    id: win

    required property ShellScreen targetScreen

    readonly property HyprlandMonitor _monitor: Hyprland.monitorFor(win.screen)
    property bool _ignoreOutsideTap: false

    Connections {
        target: win._monitor
        function onActiveWorkspaceChanged() { if (CalendarState.open) CalendarState.close() }
    }

    screen:        targetScreen
    color:         "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: "silere-calendar"
    WlrLayershell.keyboardFocus: CalendarState.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Unmap the full-screen surface while closed so it isn't holding a screen-sized
    // GPU buffer at rest, stay mapped through the close animation, then drop it.
    visible: CalendarState.open || card.opacity > 0.001

    anchors { top: true; left: true; right: true; bottom: true }

    Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut; enabled: CalendarState.open; onActivated: CalendarState.close() }
    Shortcut { sequences: ["Left"];  context: Qt.ApplicationShortcut; enabled: CalendarState.open; onActivated: card._step(-1) }
    Shortcut { sequences: ["Right"]; context: Qt.ApplicationShortcut; enabled: CalendarState.open; onActivated: card._step(1)  }

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

    Rectangle {
        id: card

        readonly property int  cell:     34
        readonly property int  pad:      14
        readonly property int  panelW:   cell * 7 + pad * 2
        readonly property real _originX: Math.max(0, Math.min(panelW, CalendarState.anchorX - x))

        // Two month cursors: `disp*` leads (drives the header, updates instantly on
        // nav) while `shown*` trails, the grid renders `shown*` and only catches up
        // at the mid-point of the slide, so the swap reads as one motion.
        property int dispYear:  2000
        property int dispMonth: 0
        property int shownYear:  2000
        property int shownMonth: 0
        property int navDir:     0      // -1 prev, +1 next — drives the slide direction

        // "Today" captured on each open. The card persists between opens, so a
        // readonly `new Date()` binding would freeze at first build and the wrong
        // day would stay highlighted forever, capture it fresh instead.
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

        // ISO 8601 week number (Monday-start).
        function _isoWeek(d): int {
            const t = new Date(d); t.setHours(0, 0, 0, 0)
            t.setDate(t.getDate() + 3 - (t.getDay() + 6) % 7)
            const w1 = new Date(t.getFullYear(), 0, 4)
            return 1 + Math.round(((t - w1) / 86400000 - 3 + (w1.getDay() + 6) % 7) / 7)
        }

        // Snap both cursors (no slide), used on open so it just shows this month.
        function _snapToday(): void {
            const t = new Date()
            _todayY = t.getFullYear(); _todayM = t.getMonth(); _todayD = t.getDate()
            _todayWeek = card._isoWeek(t)
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

        Connections {
            target: CalendarState
            function onOpenChanged() { if (CalendarState.open) card._snapToday() }
        }
        // Keep "today" current if the popup is held open across midnight, without
        // yanking the user back from a month they've navigated to.
        Connections {
            target: DateTime
            function onCachedDateCoreChanged() {
                if (!CalendarState.open) return
                const t = new Date()
                card._todayY = t.getFullYear(); card._todayM = t.getMonth(); card._todayD = t.getDate()
                card._todayWeek = card._isoWeek(t)
                card.todayWeekday = Qt.formatDateTime(t, "dddd")
            }
        }
        Component.onCompleted: _snapToday()

        // Month swap: old grid slides out + fades, the shown cursor catches up at 0
        // opacity, the new grid slides in from the other side + fades. Next moves the
        // page left (content advances), prev moves it right.
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

        readonly property bool _barBottom: ShellSettings.barPosition === "bottom"

        readonly property int _barInset: ShellSettings.barFloating ? 4 : 0
        readonly property int _edgeY: _barInset + ShellSettings.barHeight + 8
        readonly property real _minX: radius + 4
        readonly property real _maxX: Math.max(_minX, win.width - panelW - _minX)

        // Trigger-proportional like the menu (see MenuWindow._place), whole px
        // so NativeRendering text stays crisp.
        readonly property real _t: Math.max(0, Math.min(win.width, CalendarState.anchorX))
        x: Math.round(Math.max(_minX, Math.min(_t - panelW * _t / Math.max(1, win.width), _maxX)))
        y: Math.round((_barBottom ? (win.height - _edgeY - height) : _edgeY) + edgeOffset)
        width:  panelW
        height: _col.implicitHeight + pad * 2
        radius: Theme.radiusPanel
        antialiasing: true
        // Same material as the bar/menu so the family reads as one.
        color: Theme.popup
        border.width: 1
        border.color: Theme.outline

        // Detached popup: rises from the bar-side edge, centred on the clock,
        // with a restrained scale and fade.
        property real scaleAmt: 0.985
        property real edgeOffset: _closedOffset
        readonly property real _closedOffset: _barBottom ? 8 : -8
        transform: Scale { origin.x: card._originX; origin.y: card._barBottom ? card.height : 0; xScale: card.scaleAmt; yScale: card.scaleAmt }
        state: CalendarState.open ? "visible" : "hidden"
        layer.enabled: !ShellSettings.reduceMotion && opacity > 0.001 && scaleAmt < 0.999

        states: [
            State { name: "hidden";  PropertyChanges { target: card; scaleAmt: 0.985; edgeOffset: card._closedOffset; opacity: 0 } },
            State { name: "visible"; PropertyChanges { target: card; scaleAmt: 1.0;  edgeOffset: 0; opacity: 1 } }
        ]
        transitions: [
            Transition {
                from: "*"; to: "visible"
                ParallelAnimation {
                    NumberAnimation { target: card; property: "scaleAmt";   to: 1.0; duration: Motion.ms(160); easing.type: Easing.OutCubic }
                    NumberAnimation { target: card; property: "edgeOffset"; to: 0;   duration: Motion.ms(160); easing.type: Easing.OutQuart }
                    NumberAnimation { target: card; property: "opacity";    to: 1.0; duration: Motion.ms(100); easing.type: Easing.OutCubic }
                }
            },
            Transition {
                from: "visible"; to: "hidden"
                ParallelAnimation {
                    NumberAnimation { target: card; property: "scaleAmt";   to: 0.985;             duration: Motion.ms(105); easing.type: Easing.InCubic }
                    NumberAnimation { target: card; property: "edgeOffset"; to: card._closedOffset; duration: Motion.ms(105); easing.type: Easing.InCubic }
                    NumberAnimation { target: card; property: "opacity";    to: 0.0;               duration: Motion.ms(90);  easing.type: Easing.InCubic }
                }
            }
        ]

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
                width: parent.width
                height: 40

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
                            color: _todayH.hovered ? Theme.text : Theme.withAlpha(Theme.text, 0.9)
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

                Rectangle {
                    width: 26; height: 26; radius: 13
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    antialiasing: true
                    color: _prevH.hovered ? Theme.withAlpha(Theme.subtext, 0.12) : "transparent"
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    HoverHandler { id: _prevH; cursorShape: Qt.PointingHandCursor }
                    TapHandler   { onTapped: card._step(-1) }
                    Text {
                        anchors.centerIn: parent; text: "󰅁"
                        color: Theme.withAlpha(Theme.subtext, _prevH.hovered ? 0.95 : 0.7)
                        font.family: Settings.font; font.pixelSize: Settings.fontSize + 2
                        renderType: Text.NativeRendering
                    }
                }

                Item {
                    anchors.centerIn: parent
                    width: _mLabel.implicitWidth + 16; height: 26
                    HoverHandler { id: _mH; cursorShape: Qt.PointingHandCursor }
                    TapHandler   { onTapped: card._goToday() }
                    Text {
                        id: _mLabel
                        anchors.centerIn: parent
                        text: card.monthLabel
                        color: _mH.hovered ? Theme.text : Theme.withAlpha(Theme.text, 0.9)
                        font.family: Settings.font; font.pixelSize: Settings.fontSize + 1; font.weight: Font.DemiBold
                        renderType: Text.NativeRendering
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }
                }

                Rectangle {
                    width: 26; height: 26; radius: 13
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    antialiasing: true
                    color: _nextH.hovered ? Theme.withAlpha(Theme.subtext, 0.12) : "transparent"
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    HoverHandler { id: _nextH; cursorShape: Qt.PointingHandCursor }
                    TapHandler   { onTapped: card._step(1) }
                    Text {
                        anchors.centerIn: parent; text: "󰅂"
                        color: Theme.withAlpha(Theme.subtext, _nextH.hovered ? 0.95 : 0.7)
                        font.family: Settings.font; font.pixelSize: Settings.fontSize + 2
                        renderType: Text.NativeRendering
                    }
                }
            }

            Row {
                width: parent.width
                Repeater {
                    model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                    delegate: Item {
                        required property int index
                        required property string modelData
                        width: card.cell; height: 22
                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: Theme.withAlpha(Theme.subtext, index >= 5 ? 0.4 : 0.6)   // weekends quieter
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

                Grid {
                    id: _grid
                    property real xOff: 0
                    x: xOff
                    width: parent.width
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

                                HoverHandler { id: _dayH; enabled: _dayCell.cur }   // display-only → no pointer cursor

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
                            }
                        }
                    }
                }
            }
        }
    }
}
