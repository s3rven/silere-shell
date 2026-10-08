import QtQuick
import "../modules/menu/controls"

// readings and labels the hardware-free surface pass cannot populate; probe-fit scans them
Item {
    id: root
    height: cases.implicitHeight

    readonly property var dateChoices: [
        { value: "normal", label: "Wednesday Sep 30" },
        { value: "compact", label: "Sep 30" }
    ]

    function notificationFixture(): var {
        return { actions: [
                { identifier: "open", text: "Open", invoke: function() {} },
                { identifier: "remind", text: "Remind me", invoke: function() {} },
                { identifier: "dismiss", text: "Dismiss", invoke: function() {} },
                { identifier: "read", text: "Mark read", invoke: function() {} }
            ], hints: ({}), appIcon: "", image: "", appName: "Probe", desktopEntry: "",
            summary: "Action layout", body: "", urgency: 1, expireTimeout: 0,
            resident: true, transient: false, hasInlineReply: false }
    }

    function fillVitals(item): void {
        item.active = false
        for (const row of item.rows) {
            if (row.value === undefined) continue
            // CI has no battery; still measure a long battery time caption.
            row.visible = true
            row.value = "100%"
            if (row.label === "CPU") row.sub = "125°"
            if (row.label === "Memory") row.sub = "999G used"
            if (row.label === "Disk") row.sub = "999G free"
            if (row.label === "Battery") row.sub = "Full in 12h 59m"
        }
    }

    function descendants(item, predicate): var {
        let found = predicate(item) ? [item] : []
        for (const child of item.children || [])
            found = found.concat(root.descendants(child, predicate))
        return found
    }

    function layoutFailures(): var {
        const failures = []
        for (const loader of [narrowVitals, wideVitals]) {
            if (!loader.item) { failures.push("vitals fixture did not load"); continue }
            const rows = loader.item.rows.filter(child => child.value !== undefined && child.visible)
            if (rows.length !== 4) failures.push("vitals fixture must measure all four readings")
            for (const row of rows) {
                const names = row.children.find(child => child.spacing !== undefined)
                const value = row.children.find(child => child.horizontalAlignment === Text.AlignRight)
                if (!names || !value) { failures.push("a vital row lost its name or value"); continue }
                if (value.implicitWidth > value.width + 0.5)
                    failures.push(row.label + " reading overflows its reserved width at " + loader.width + "px")
                if (names.width < 64)
                    failures.push(row.label + " name has no room beside its bar at " + loader.width + "px")
            }
        }
        for (const choices of [narrowDate, wideDate, warnings, tabs]) {
            const options = root.descendants(choices, item => item.optionLabel !== undefined)
            const selected = options.find(item => item.active)
            const selection = root.descendants(choices, item => item._column !== undefined)[0]
            for (const option of options) {
                const p = option.mapToItem(choices, 0, 0)
                if (p.x < 13.5 || p.x + option.width > choices.width - 11.5
                        || p.y < 0 || p.y + option.height > choices.height + 0.5)
                    failures.push("choice button escapes its row: " + option.optionLabel)
            }
            if (selected && selection) {
                const selectedPos = selected.mapToItem(choices, 0, 0)
                const selectionPos = selection.mapToItem(choices, 0, 0)
                if (Math.abs(selectedPos.x - selectionPos.x) > 0.5
                        || Math.abs(selectedPos.y - selectionPos.y) > 0.5
                        || Math.abs(selected.width - selection.width) > 0.5
                        || Math.abs(selected.height - selection.height) > 0.5)
                    failures.push("selection outline misses its wrapped choice button")
            } else {
                failures.push("choice fixture has no selected button or outline")
            }
            if (choices === warnings && options.length === 4
                    && Math.abs(options[0].y - options[1].y) > 0.5)
                failures.push("four choices do not form balanced rows")
        }
        const narrow = narrowHeader.item
        const wide = wideHeader.item
        if (!narrow || !wide) failures.push("home header fixture did not load")
        else {
            const narrowDateText = narrow.children.find(item => item.text === narrow.dateText)
            const narrowUptime = narrow.children.find(item => item.text === narrow.uptimeText)
            if (narrowUptime.y < narrowDateText.y + narrowDateText.height)
                failures.push("narrow home metadata keeps competing for one line")
            const wideDateText = wide.children.find(item => item.text === wide.dateText)
            const wideUptime = wide.children.find(item => item.text === wide.uptimeText)
            if (Math.abs(wideDateText.y - wideUptime.y) > 0.5)
                failures.push("wide home metadata unnecessarily takes two lines")
        }
        if (!narrowHistory.item) failures.push("narrow history fixture did not load")
        else {
            const messages = root.descendants(narrowHistory.item,
                item => item.text === "All caught up" || item.text === "New notifications will appear here")
            for (const message of messages) {
                const p = message.mapToItem(narrowHistory.item, 0, 0)
                if (p.x < -0.5 || p.x + message.width > narrowHistory.width + 0.5
                        || message.contentWidth > message.width + 0.5)
                    failures.push("history empty-state text escapes the narrow pane")
            }
            if (messages.length !== 2) failures.push("narrow history fixture lacks its empty-state messages")
        }
        for (const loader of [narrowNotification, wideNotification]) {
            if (!loader.item) { failures.push("notification action fixture did not load"); continue }
            const buttons = root.descendants(loader.item, item => item.preferredWidth !== undefined)
            if (buttons.length !== 4) failures.push("notification fixture does not show all four actions")
            const rows = new Set()
            for (const button of buttons) {
                const p = button.mapToItem(loader.item, 0, 0)
                rows.add(Math.round(p.y))
                if (p.x < -0.5 || p.x + button.width > loader.width + 0.5)
                    failures.push("notification action escapes its card")
                for (const label of root.descendants(button, item => typeof item.text === "string"))
                    if (label.truncated === true)
                        failures.push("notification action label is truncated: " + label.text)
            }
            if (loader === narrowNotification && rows.size < 2)
                failures.push("narrow notification keeps squeezing four actions into one row")
            if (loader === wideNotification && rows.size !== 1)
                failures.push("wide notification unnecessarily wraps compact actions")
        }
        const dependency = root.descendants(blockedSetting, item => item.text === blockedSetting._detailText)[0]
        if (!dependency || dependency.truncated || dependency.contentWidth > dependency.width + 0.5)
            failures.push("the unavailable setting's explanation is clipped in a narrow pane")
        else if (blockedSetting.height < dependency.height + 24)
            failures.push("the unavailable setting does not grow to fit its explanation: row "
                + blockedSetting.height + ", detail " + dependency.height)
        return failures
    }

    Column {
        id: cases
        spacing: 8
        ToggleRow {
            id: blockedSetting
            width: 232
            label: "Background blur"
            description: "Frost what shows through"
            available: false
            dependsNote: "The compositor cannot enable this setting. Check the configuration in /home/user/"
                + "a".repeat(70) + "/configuration.conf and try again."
        }
        Loader {
            id: narrowHistory
            width: 232; height: 320
            Component.onCompleted: setSource("../modules/menu/RecentPage.qml", {
                width: 232, viewportHeight: 320, active: false, powerOpen: false
            })
        }
        Loader {
            id: narrowNotification
            width: 232
            Component.onCompleted: setSource("../modules/notifications/NotificationCard.qml", {
                width: 232, notification: root.notificationFixture(),
                notifId: 2147483645, createdAt: Date.now()
            })
        }
        Loader {
            id: wideNotification
            width: 520
            Component.onCompleted: setSource("../modules/notifications/NotificationCard.qml", {
                width: 520, notification: root.notificationFixture(),
                notifId: 2147483644, createdAt: Date.now()
            })
        }

        Loader { id: narrowVitals; width: 332; source: "../modules/menu/VitalsStrip.qml"; onLoaded: root.fillVitals(item) }
        Loader { id: wideVitals; width: 388; source: "../modules/menu/VitalsStrip.qml"; onLoaded: root.fillVitals(item) }
        ChoiceChipRow {
            id: narrowDate
            width: 232; label: "Style"; glyph: "󰸗"
            model: root.dateChoices; currentValue: "compact"
        }
        ChoiceChipRow {
            id: wideDate
            width: 388; label: "Style"; glyph: "󰸗"
            model: root.dateChoices; currentValue: "normal"
        }
        ChoiceChipRow {
            id: warnings
            width: 232; label: "Warnings"; currentValue: "both"
            model: [
                { value: "off", label: "Off" }, { value: "popup", label: "Popup" },
                { value: "glow", label: "Glow" }, { value: "both", label: "Both" }
            ]
        }
        ChoiceChipRow {
            id: tabs
            width: 232; currentValue: "input"
            model: [
                { value: "output", label: "Output" }, { value: "input", label: "Input" },
                { value: "apps", label: "Apps" }
            ]
        }
        HintText {
            width: 232
            text: "Could not read /home/user/" + "a".repeat(80) + "/settings.json"
        }
        UpdateStatusCard {
            width: 232
            title: "Update failed"
            detail: "Could not read /home/user/" + "a".repeat(80) + "/settings.json"
            detailError: true
        }
        Loader {
            id: narrowHeader
            width: 188; source: "../modules/menu/HomeHeader.qml"
            onLoaded: {
                item.weekday = "Wednesday"
                item.dateText = "September 30 · Week 40"
                item.uptimeText = "up 999d 23h"
            }
        }
        Loader {
            id: wideHeader
            width: 388; source: "../modules/menu/HomeHeader.qml"
            onLoaded: {
                item.weekday = "Wednesday"
                item.dateText = "September 30 · Week 40"
                item.uptimeText = "up 999d 23h"
            }
        }
    }
}
