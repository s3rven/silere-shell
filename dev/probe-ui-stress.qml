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
        }
        TestCase { id: input; when: false }
    }

    Timer {
        interval: 150
        running: true
        onTriggered: cycleTimer.start()
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
