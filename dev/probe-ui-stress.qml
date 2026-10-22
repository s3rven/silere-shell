pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import Quickshell
import "config"
import "services"
import "modules/common"
import "modules/menu/controls"

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

    Timer {
        interval: 150
        running: true
        onTriggered: {
            root.checkScrollThumb()
            cycleTimer.start()
        }
    }
    Timer {
        id: cycleTimer
        interval: 1
        onTriggered: {
            ShellSettings.uiScale = [0.8, 1.0, 1.1, 1.15][root.cycles % 4]
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
