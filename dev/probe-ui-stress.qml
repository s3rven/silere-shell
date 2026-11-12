pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "config"
import "services"
import "modules/common"
import "modules/menu/controls"
import "modules/notifications"
import "modules/notifications/StackLayout.js" as StackLayout

// Real offscreen pointer input, repeated reflow and cancellation while animations
// are in flight. Each cycle samples the transient layout, not just its final state.
ShellRoot {
    id: root
    property int checks: 0
    property int failures: 0
    property int cycles: 0
    property int requestedCycles: Math.max(1, Number(Quickshell.env("SILERE_UI_STRESS_CYCLES") || 120))
    property int actions: 0
    property int changes: 0
    property int wheelChanges: 0

    function check(ok: bool, message: string): void {
        root.checks++
        if (!ok) {
            root.failures++
            if (root.failures <= 15) console.error("PROBE-FAIL UI stress cycle " + root.cycles + ": " + message)
        }
    }

    function finish(): void {
        console.log("PROBE-UI-STRESS " + (root.failures === 0 ? "passed" : "failed")
            + " " + root.checks + " checks over " + root.cycles + " cycles")
    }

    function find(item, predicate): var {
        if (predicate(item)) return item
        for (const child of item.children || []) {
            const found = root.find(child, predicate)
            if (found) return found
        }
        return null
    }

    function selectionInside(): bool {
        const selection = root.find(choices, item => item._column !== undefined)
        if (!selection || !selection.visible) return false
        return selection.x >= -0.5 && selection.y >= -0.5
            && selection.x + selection.width <= selection.parent.width + 0.5
            && selection.y + selection.height <= selection.parent.height + 0.5
    }

    Window {
        id: window
        visible: true
        width: 580; height: 640
        color: Theme.panel
        Rectangle {
            anchors.fill: parent
            color: Theme.withAlpha(Theme.panel, 1)
        }
        Item {
            id: host
            anchors.fill: parent
            ChoiceChipRow {
                id: choices
                x: 14; y: 14; width: 480
                label: ""
                model: [{value: "a", label: "One"}, {value: "b", label: "Two"},
                        {value: "c", label: "Three"}, {value: "d", label: "Four"}]
                currentValue: "d"
                onChosen: value => { currentValue = value; root.actions++ }
            }
            ToggleRow {
                id: toggle
                x: 14; y: 240; width: 360
                label: "Stress toggle"
                onToggled: next => { checked = next; root.actions++ }
            }
            ControlRow {
                id: control
                x: 14; y: 310; width: 360
                title: "Stress device"; showSwitch: true; badgeCount: 2; expandable: true
                onActivated: { active = !active; root.actions++ }
                onBadgeActivated: root.actions++
                onExpandToggled: root.actions++
            }
            InlineOptionRow {
                id: option
                x: 14; y: 380; width: 360
                label: "Stress option"; accessiblePrefix: "Stress"
                onTriggered: root.actions++
            }
            SliderTrack {
                id: slider
                x: 20; y: 460; width: 300; height: 30
                value: 0.5; commitOnRelease: true; interactionKey: "initial"
                onChanged: value => { slider.value = value; root.changes++ }
            }
            SelectRow {
                id: select
                x: 14; y: 520; width: 360
                label: "Stress dropdown"
                model: [{value: "a", label: "A"}, {value: "b", label: "B"}]
                currentValue: "a"
            }
            ShellListView {
                id: scrollList
                x: 410; y: 240; width: 140; height: 200
                model: scrollRows
                delegate: ShellText {
                    required property string label
                    required property int index
                    width: scrollList.width; height: 25 + (index % 4) * 15
                    text: label
                }
            }
            MenuScrollThumb {
                id: scrollThumb
                list: scrollList
            }
        }
        TestCase { id: input; when: false }
    }

    // the shape of the bar's system readings: a pill whose readings grow into details on hover
    Window {
        id: pillWindow
        visible: true
        width: 600; height: 60
        color: Theme.panel
        Pill {
            id: hoverPill
            y: 10
            glyph: "󰍛"
            shrinkDelay: 2400
            property string reading: "5%"
            // as the CPU reading does, the first text reads the same either way; only the pairs after it grow
            text: reading
            segments: [{ glyph: "󰘚", text: expanded ? "8.4 GB of 62 GB" : "13%", reserve: "00%" },
                { glyph: "󰔏", text: expanded ? "56°C" : "56°", reserve: "00°" }]
        }
        // a volume another app left off the 5% grid, and the accent hue strip
        SliderTrack {
            id: grabSlider
            x: 300; y: 4; width: 280; height: 20
            value: 0.67
            onChanged: v => { grabSlider.value = v; root.grabChanges++ }
        }
        GradientSlider {
            id: grabHue
            x: 300; y: 32; width: 280; height: 20
            position: 0.67
            onPicked: p => { grabHue.position = p; root.grabChanges++ }
        }
    }

    property int grabChanges: 0
    function checkHandleGrab(target: Item, center: real, label: string): void {
        const before = root.grabChanges
        input.mousePress(target, center, target.height / 2)
        input.mouseRelease(target, center, target.height / 2)
        input.mousePress(target, center + 3, target.height / 2)
        input.mouseMove(target, center + 4, target.height / 2)
        input.mouseRelease(target, center + 4, target.height / 2)
        root.check(root.grabChanges === before,
            "a click on the " + label + " handle, or a pixel's wobble on it, leaves a value off the grid alone")
        input.mousePress(target, center, target.height / 2)
        input.mouseMove(target, center + 40, target.height / 2)
        input.mouseRelease(target, center + 40, target.height / 2)
        root.check(root.grabChanges > before, "dragging the " + label + " handle still moves it")
    }

    function checkHoverRelease(): void {
        input.wait(300)
        const rest = hoverPill.rowWidth
        const p = hoverPill.mapToItem(pillWindow.contentItem, hoverPill.width / 2, hoverPill.height / 2)
        input.mouseMove(pillWindow.contentItem, p.x, p.y)
        input.wait(400)
        root.check(hoverPill.expanded && hoverPill.rowWidth > rest + 40, "hovering the pill reveals its details")
        input.mouseMove(pillWindow.contentItem, pillWindow.width - 5, 5)
        input.wait(300)
        root.check(!hoverPill.expanded && hoverPill.rowWidth === rest && hoverPill._minW <= hoverPill.rowWidth,
            "a pill closing its hover details settles on its readings, with no hover width held after them")
        // the hold itself stays for readings that shorten between ticks
        hoverPill.reading = "15%"
        input.wait(50)
        const wide = hoverPill.rowWidth
        hoverPill.reading = "5"
        input.wait(50)
        root.check(hoverPill._minW >= wide && hoverPill.rowWidth < wide,
            "a reading that shortens still holds the pill's width for its shrink delay")
        // a smaller interface scale is chosen, not a reading that flickers
        hoverPill.reading = "5%"
        const scaleWas = ShellSettings.uiScale
        ShellSettings.uiScale = 1.25
        input.wait(2600)
        ShellSettings.uiScale = 1.0
        input.wait(300)
        root.check(hoverPill._minW <= hoverPill.rowWidth,
            "a smaller interface scale settles every pill at once, with no old width held after its readings")
        ShellSettings.uiScale = scaleWas
        input.wait(100)
        root.checkHandleGrab(grabSlider, grabSlider._thumbCenter, "slider")
        root.checkHandleGrab(grabHue, grabHue._thumbCenter, "hue")
        pillWindow.visible = false
    }

    // a stack read from the service's popup list, as NotificationPopups reads it; its withdrawn handler and slot
    // gate are the popup's. The popup window itself needs layer shell, which this offscreen probe lacks
    Window {
        id: notifWindow
        visible: true
        width: 460; height: 420
        color: Theme.panel
        // the popup's "most visible" setting; 0 loads every card
        property int maxVisible: 0
        Column {
            x: 20; y: 20; width: 400
            Repeater {
                id: notifStack
                model: Notifications.popupModel
                Item {
                    id: notifSlot
                    required property var modelData
                    required property int index
                    property bool exitHeld: false
                    readonly property bool shouldLoad: StackLayout.slotLoads(index, notifStack.count,
                        notifWindow.maxVisible, false, false, exitHeld, Notifications.replyingId === notifSlot.modelData.id)
                    readonly property var card: notifLoader.item
                    width: 400; height: card ? card.implicitHeight : 0
                    visible: shouldLoad
                    Loader {
                        id: notifLoader
                        width: 400
                        active: notifSlot.shouldLoad
                        sourceComponent: NotificationCard {
                            width: 400
                            notification: notifSlot.modelData
                            notifId: notifSlot.modelData.id
                            createdAt: Date.now()
                            onLeaving: notifSlot.exitHeld = true
                            onDismissRequested: (id, n, expired) => Notifications.dismissObject(id, n, expired)
                        }
                    }
                }
            }
        }
        Connections {
            target: Notifications
            function onWithdrawn(notification): void {
                for (let i = 0; i < notifStack.count; i++) {
                    const slot = notifStack.itemAt(i)
                    if (!slot || slot.modelData !== notification || !slot.card) continue
                    if (slot.card.withdraw()) Notifications.holdWithdrawn(notification)
                }
            }
        }
    }

    Process { id: notifySend; stdout: StdioCollector { id: notifyOut } }
    function sendNotification(summary: string, actions: string): int {
        const before = Notifications.list.length
        notifySend.command = ["gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications",
            "--object-path", "/org/freedesktop/Notifications", "--method",
            "org.freedesktop.Notifications.Notify", "probe", "0", "", summary, "a body line",
            actions, "{}", "60000"]
        notifySend.running = true
        root.waitFor(() => !notifySend.running && Notifications.list.length > before, 3000)
        const m = /uint32 (\d+)/.exec(notifyOut.text)
        return m ? Number(m[1]) : -1
    }
    function closeNotification(id: int): void {
        notifySend.command = ["gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications",
            "--object-path", "/org/freedesktop/Notifications", "--method",
            "org.freedesktop.Notifications.CloseNotification", String(id)]
        notifySend.running = true
    }
    function waitFor(predicate, ms: int): bool {
        const until = Date.now() + ms
        while (!predicate() && Date.now() < until) input.wait(10)
        return predicate()
    }
    function freed(object): bool {
        try { return object === null || object.summary === undefined } catch (e) { return true }
    }

    function checkWithdrawnExit(): void {
        const motionWas = ShellSettings.reduceMotion
        ShellSettings.reduceMotion = false
        const id = root.sendNotification("Withdrawn by its sender", "[]")
        root.check(id > 0 && root.waitFor(() => notifStack.count === 1, 1000), "a sent notification reaches the stack")
        if (notifStack.count !== 1) { ShellSettings.reduceMotion = motionWas; return }
        const opening = notifStack.itemAt(0).card.collapseRatio
        input.wait(400)
        const shown = notifStack.itemAt(0).card
        root.check(opening < 0.5 && shown.collapseRatio === 1,
            "a new card opens its slot over a few frames, so the cards below it glide rather than jump (" + opening + ")")
        const sent = notifStack.itemAt(0).modelData
        root.closeNotification(id)
        root.waitFor(() => Notifications.list.length === 0, 2000)
        root.check(notifStack.count === 1 && shown._leaving && shown.summaryText === "Withdrawn by its sender",
            "a notification its sender closes stays in the stack, still readable, while its card slides out")
        const rim = root.find(shown, item => item._shownProgress !== undefined)
        root.check(rim !== null && rim._shownProgress > 0.5,
            "a leaving card keeps its countdown rim to fade out with it, instead of dropping it on the first frame")
        root.check(root.waitFor(() => notifStack.count === 0, 1000) && Notifications._withdrawals.length === 0,
            "the stack lets the card go once its exit ends")
        root.check(Notifications.historyModel.count > 0 && Notifications.historyModel.get(0).summary === "Withdrawn by its sender",
            "a withdrawn notification is still archived")
        input.wait(50)
        root.check(root.freed(sent), "a withdrawn notification is freed after its exit, not kept by the lock")

        // a notification that is not resident closes inside invoke(), before the card asks to dismiss it
        root.sendNotification("Answered with an action", "['open', 'Open']")
        root.waitFor(() => notifStack.count === 1, 1000)
        input.wait(400)
        const answered = notifStack.count === 1 ? notifStack.itemAt(0).card : null
        const action = answered ? answered.actionList[0] : null
        if (answered && action) answered.invokeAction(action)
        root.check(answered !== null && action && notifStack.count === 1 && answered._leaving,
            "an action that closes its notification still lets the card slide out")
        root.check(root.waitFor(() => notifStack.count === 0, 1000), "and then the card leaves the stack")

        ShellSettings.reduceMotion = true
        const quick = root.sendNotification("Withdrawn under reduced motion", "[]")
        root.waitFor(() => notifStack.count === 1, 1000)
        root.check(notifStack.count === 1 && notifStack.itemAt(0).card.collapseRatio === 1,
            "with reduced motion a new card takes its whole slot at once")
        root.closeNotification(quick)
        root.waitFor(() => Notifications.list.length === 0, 2000)
        root.check(notifStack.count === 0 && Notifications._withdrawals.length === 0,
            "with reduced motion a withdrawn card leaves at once, holding nothing")
        ShellSettings.reduceMotion = motionWas
        notifWindow.visible = false
    }

    // with a "most visible" limit, a newer card takes the last slot while an older one is still sliding out
    function checkExitOutlivesSlotLimit(): void {
        const motionWas = ShellSettings.reduceMotion
        ShellSettings.reduceMotion = false
        notifWindow.visible = true
        notifWindow.maxVisible = 1
        const older = root.sendNotification("Leaving as a newer card arrives", "[]")
        root.waitFor(() => notifStack.count === 1 && notifStack.itemAt(0).card !== null, 1000)
        input.wait(400)
        const leaving = notifStack.count === 1 ? notifStack.itemAt(0).card : null
        if (leaving) leaving.dismiss(false)
        const newer = root.sendNotification("Arrives during that exit", "[]")
        root.check(leaving !== null && older > 0 && newer > 0
                && root.waitFor(() => notifStack.count === 1, 1500)
                && notifStack.itemAt(0).modelData.summary === "Arrives during that exit",
            "a card still leaving when a newer one takes the last visible slot finishes its exit and leaves the stack, "
            + "instead of being unloaded mid-exit and coming back once the stack shrinks")
        root.closeNotification(newer)
        root.waitFor(() => notifStack.count === 0, 2000)
        notifWindow.maxVisible = 0
        notifWindow.visible = false
        ShellSettings.reduceMotion = motionWas
    }

    // the shape of a menu page with a slider on it, driven with real wheel events
    Window {
        id: wheelWindow
        visible: true
        width: 400; height: 300
        color: Theme.panel
        ShellFlickable {
            id: wheelPage
            anchors.fill: parent
            contentWidth: width
            contentHeight: 1200
            SliderTrack {
                id: wheelSlider
                x: 50; y: 400; width: 300; height: 30
                value: 0.5
                wheelKey: "probe-ui-stress-wheel"; wheelNeedsRest: true
                onChanged: value => { wheelSlider.value = value; root.wheelChanges++ }
            }
        }
    }

    ListModel {
        id: scrollRows
        Component.onCompleted: {
            for (let i = 0; i < 40; i++) append({label: "Entry " + (i + 1)})
        }
    }

    function checkScrollThumb(): void {
        input.wait(Motion.panelSettle + 50)
        root.check(scrollThumb.visible, "an overflowing list reveals its scrollbar")
        let p = scrollThumb.mapToItem(window.contentItem, -4, scrollThumb.height / 2)
        input.mouseMove(window.contentItem, p.x, p.y)
        input.mouseWheel(window.contentItem, p.x, p.y, 0, -120)
        input.wait(80)
        root.check(scrollList.contentY > scrollList.originY,
            "the scrollbar's wider hit area still passes wheel scrolling to the list")
        scrollList.cancelFlick()
        scrollList.positionViewAtBeginning()
        input.wait(30)
        const before = scrollList.contentY
        p = scrollThumb.mapToItem(window.contentItem, -4, scrollThumb.height / 2)
        input.mousePress(window.contentItem, p.x, p.y)
        root.check(scrollThumb.dragging && Math.abs(scrollList.contentY - before) < 0.01,
            "grabbing the wider scrollbar hit area preserves the current position")
        input.mouseMove(window.contentItem, p.x, p.y + 60)
        root.check(scrollList.contentY > before + 100,
            "dragging the scrollbar scrolls the list")
        input.mouseMove(window.contentItem, p.x, p.y + 60)
        input.wait(30)
        root.check(Math.abs(scrollThumb.y + scrollThumb._grabRatio * scrollThumb.height
                - p.y - 60) < 1,
            "a stationary pointer does not drift as the thumb moves beneath it")
        input.mouseMove(window.contentItem, p.x, scrollList.y + scrollList.height + 50)
        input.wait(30)
        root.check(Math.abs(scrollList.contentY - scrollList.originY
                - scrollList.contentHeight + scrollList.height) < 0.01,
            "dragging past the track reaches the exact bottom")
        input.mouseMove(window.contentItem, p.x, scrollList.y - 30)
        input.wait(30)
        root.check(Math.abs(scrollList.contentY - scrollList.originY) < 0.01,
            "dragging above the track reaches the exact top")
        input.mouseRelease(window.contentItem, p.x, scrollList.y - 30)
        root.check(!scrollThumb.dragging, "releasing the scrollbar ends the drag")

        // Removing rows above a retained viewport gives ListView a nonzero origin.
        scrollList.contentY = 500
        scrollRows.remove(0, 5)
        scrollList.forceLayout()
        input.wait(30)
        root.check(scrollList.originY !== 0, "the recycled list fixture has a shifted origin")
        p = scrollThumb.mapToItem(window.contentItem, -4, scrollThumb.height / 2)
        input.mousePress(window.contentItem, p.x, p.y)
        input.mouseMove(window.contentItem, p.x, scrollList.y + scrollList.height + 50)
        input.wait(30)
        root.check(scrollThumb.dragging && Math.abs(scrollList.contentY - scrollList.originY
                - scrollList.contentHeight + scrollList.height) < 0.01,
            "scrollbar dragging accounts for a recycled list's shifted origin")

        scrollThumb.contextKey = "replacement page"
        const canceledAt = scrollList.contentY
        input.mouseMove(window.contentItem, p.x, scrollList.y)
        input.mouseRelease(window.contentItem, p.x, scrollList.y)
        root.check(!scrollThumb.dragging && scrollList.contentY === canceledAt,
            "changing pages cancels a retained scrollbar drag")

        input.wait(Motion.panelSettle + 50)
        p = scrollThumb.mapToItem(window.contentItem, -4, scrollThumb.height / 2)
        input.mousePress(window.contentItem, p.x, p.y)
        root.check(scrollThumb.dragging, "the replacement page permits a fresh drag")
        scrollList.interactive = false
        input.mouseMove(window.contentItem, p.x, scrollList.y)
        input.mouseRelease(window.contentItem, p.x, scrollList.y)
        root.check(!scrollThumb.dragging && scrollList.contentY === canceledAt,
            "a disabled list cancels dragging without further movement")
        scrollList.interactive = true

        p = scrollThumb.mapToItem(window.contentItem, -4, scrollThumb.height / 2)
        input.mousePress(window.contentItem, p.x, p.y)
        host.visible = false
        input.mouseMove(window.contentItem, p.x, scrollList.y)
        input.mouseRelease(window.contentItem, p.x, scrollList.y)
        root.check(!scrollThumb.dragging && scrollList.contentY === canceledAt,
            "hiding the menu cancels dragging without further movement")
        host.visible = true

        input.wait(Motion.panelSettle + 50)
        p = scrollThumb.mapToItem(window.contentItem, -4, scrollThumb.height / 2)
        input.mousePress(window.contentItem, p.x, p.y)
        root.check(scrollThumb.dragging, "a revealed list permits another drag")
        scrollList.height += 20
        const resizedAt = scrollList.contentY
        input.mouseMove(window.contentItem, p.x, scrollList.y)
        input.mouseRelease(window.contentItem, p.x, scrollList.y)
        root.check(!scrollThumb.dragging && scrollList.contentY === resizedAt,
            "resizing the viewport cancels the old drag without moving its new contents")

        p = scrollThumb.mapToItem(window.contentItem, -4, scrollThumb.height / 2)
        input.mousePress(window.contentItem, p.x, p.y)
        root.check(scrollThumb.dragging, "a resized list permits a fresh drag")
        scrollRows.append({label: "New entry"})
        scrollList.forceLayout()
        input.wait(30)
        root.check(scrollThumb.dragging
                && Math.abs(scrollThumb.y + scrollThumb._grabRatio * scrollThumb.height - p.y) < 1,
            "a changing scroll range keeps the grabbed thumb beneath the stationary pointer")
        input.mouseRelease(window.contentItem, p.x, p.y)

        scrollRows.clear()
        scrollList.forceLayout()
        input.wait(30)
        root.check(!scrollThumb.visible && !scrollThumb.dragging,
            "a list that no longer overflows hides its scrollbar")
    }

    function wheelAt(p: point): void {
        input.mouseWheel(wheelWindow.contentItem, p.x, p.y, 0, -120)
    }

    function wheelSliderPoint(): point {
        return wheelSlider.mapToItem(wheelWindow.contentItem, wheelSlider.width / 2, wheelSlider.height / 2)
    }

    function settleWheelPage(y: real): void {
        wheelPage.cancelFlick()
        wheelPage.contentY = y
        input.wait(Scroll.pageLatchMs + 50)
    }

    function checkWheelLatch(): void {
        // Home's sliders sit on a page too short to scroll: moving onto one and wheeling at once
        // must reach it once the hover rests, not feed a page latch for as long as the wheel turns
        wheelPage.interactive = false
        root.settleWheelPage(360)
        let p = root.wheelSliderPoint()
        input.mouseMove(wheelWindow.contentItem, p.x, p.y - 200)
        input.wait(50)
        input.mouseMove(wheelWindow.contentItem, p.x, p.y)
        let before = root.wheelChanges
        for (let i = 0; i < 10; i++) {
            root.wheelAt(p)
            input.wait(100)
        }
        root.check(root.wheelChanges > before,
            "a slider takes a wheel gesture begun before its hover rested once the hover rests")

        // a clamp or a reveal moves the page without the user, so it is no gesture to yield to
        wheelPage.interactive = true
        root.settleWheelPage(360)
        p = root.wheelSliderPoint()
        input.mouseMove(wheelWindow.contentItem, p.x - 1, p.y)
        input.wait(Scroll.sliderRestMs + 50)
        wheelPage.contentY = 361
        wheelPage.contentY = 360
        before = root.wheelChanges
        root.wheelAt(root.wheelSliderPoint())
        input.wait(50)
        root.check(root.wheelChanges > before && wheelPage.contentY === 360,
            "a page moved by code leaves the next wheel with the rested slider")

        // a gesture scrolling the page keeps scrolling it when the slider passes under the pointer
        root.settleWheelPage(0)
        input.mouseMove(wheelWindow.contentItem, 200, 40)
        root.wheelAt(Qt.point(200, 40))
        input.wait(60)
        root.check(wheelPage.contentY > 0, "the wheel scrolls the page")
        wheelSlider._hoveredSince = Date.now() - 1000
        before = root.wheelChanges
        root.wheelAt(root.wheelSliderPoint())
        input.wait(60)
        root.check(root.wheelChanges === before, "a page gesture passes over a rested slider")

        // the same gesture run into the page's end keeps the wheel until it rests
        root.settleWheelPage(wheelPage.contentHeight - wheelPage.height - 30)
        input.mouseMove(wheelWindow.contentItem, 20, 20)
        root.wheelAt(Qt.point(20, 20))
        input.wait(40)
        root.wheelAt(Qt.point(20, 20))
        input.wait(40)
        wheelSlider._hoveredSince = Date.now() - 1000
        before = root.wheelChanges
        for (let i = 0; i < 4; i++) {
            root.wheelAt(root.wheelSliderPoint())
            input.wait(60)
        }
        root.check(root.wheelChanges === before, "wheeling on at the page's end does not nudge the slider")
        wheelPage.cancelFlick()
        wheelWindow.visible = false
    }

    Timer {
        interval: 150
        running: true
        onTriggered: {
            root.checkWheelLatch()
            root.checkHoverRelease()
            root.checkWithdrawnExit()
            root.checkExitOutlivesSlotLimit()
            root.checkScrollThumb()
            cycleTimer.start()
        }
    }
    Timer {
        id: cycleTimer
        interval: 1
        onTriggered: {
            ShellSettings.uiScale = [0.8, 1.0, 1.15, 1.25, 1.5][root.cycles % 5]
            ShellSettings.highContrast = root.cycles % 3 === 1
            ShellSettings.neutralTheme = root.cycles % 3 === 2
            ShellSettings.reduceMotion = true
            host.visible = true
            choices.width = 480
            choices.currentValue = "d"
            input.wait(20)
            root.check(root.selectionInside(), "wide choice selection stays within its group")

            ShellSettings.reduceMotion = false
            choices.width = 180
            root.check(root.selectionInside(), "selection stays inside immediately when columns wrap")
            input.wait(30)
            root.check(root.selectionInside(), "selection stays inside during reflow animation")

            toggle.available = false
            toggle.checked = true
            const beforeToggleOpacity = toggle._controlOpacity
            const beforeControlOpacity = control.opacity
            const beforeActions = root.actions
            host.visible = false
            root.check(toggle._controlOpacity === beforeToggleOpacity,
                "hiding an active dependency-limited toggle preserves its resting appearance")
            input.wait(20)
            root.check(Math.abs(control.opacity - beforeControlOpacity) < 0.000001,
                "hidden controls do not fade to a disabled appearance before reopening")
            const springs = []
            for (const resource of choices.resources) {
                if (resource.spring !== undefined && resource._tick !== undefined) springs.push(resource)
            }
            root.check(springs.length === 2 && springs.every(spring => !spring._tick.running),
                "hidden choice chips retire both selection animations")
            toggle.Accessible.toggleAction()
            control.Accessible.pressAction()
            control._activateBadge()
            control._toggleExpanded()
            option.Accessible.pressAction()
            const chip = root.find(choices, item => item.Accessible.role === Accessible.RadioButton)
            if (chip) chip.Accessible.pressAction()
            select.Accessible.pressAction()
            root.check(root.actions === beforeActions, "hidden setting rows reject retained actions")
            root.check(!MenuState.settingsSelectOpen && !select._open,
                "hidden dropdown cannot retain or claim picker ownership")
            host.visible = true

            const beforeChanges = root.changes
            input.mousePress(slider, 150, 15)
            input.mouseMove(slider, 240, 15)
            root.check(slider.dragging, "pointer drag starts on the restored slider")
            slider.interactionKey = "target-" + root.cycles
            input.mouseRelease(slider, 240, 15)
            root.check(!slider.dragging && root.changes === beforeChanges,
                "changing a target cancels a drag without committing to its replacement")
            select._setOpen(true)
            host.visible = false
            root.check(!select._open && !MenuState.settingsSelectOpen,
                "hiding an open dropdown releases ownership during its animation")
            host.visible = true
            input.mouseMove(window.contentItem, 570, 630)
            root.cycles++
            if (root.cycles < root.requestedCycles) {
                cycleTimer.restart()
                return
            }
            ShellSettings.reduceMotion = true
            input.wait(40)
            root.check(!slider.dragging && !select._open && !MenuState.settingsSelectOpen,
                "finishing the stress run leaves no unfinished drag or open picker")
            const capturePath = String(Quickshell.env("SILERE_UI_STRESS_CAPTURE") || "")
            if (capturePath.length === 0) {
                root.finish()
                return
            }
            const capturing = window.contentItem.grabToImage(result => {
                root.check(result.saveToFile(capturePath), "the UI preview image saves successfully")
                root.finish()
            })
            root.check(capturing, "the UI preview capture starts")
            if (!capturing) root.finish()
        }
    }
}
