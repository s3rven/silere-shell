import QtQuick
import Quickshell.Services.UPower as Up
import "../modules/menu/controls"
import "../config" as Config

// readings and labels the hardware-free surface pass cannot populate; probe-fit scans them
Item {
    id: root
    height: cases.implicitHeight

    readonly property var dateChoices: [
        { value: "normal", label: "Wednesday Sep 30" },
        { value: "compact", label: "Sep 30" }
    ]

    function notificationFixture(reply = false): var {
        return { actions: [
                { identifier: "open", text: "Open", invoke: function() {} },
                { identifier: "remind", text: "Remind me", invoke: function() {} },
                { identifier: "dismiss", text: "Dismiss", invoke: function() {} },
                { identifier: "read", text: "Mark read", invoke: function() {} }
            ], hints: ({}), appIcon: "", image: "", appName: "Probe", desktopEntry: "",
            summary: "Action layout", body: "", urgency: 1, expireTimeout: 0,
            resident: true, transient: false, hasInlineReply: reply,
            inlineReplyPlaceholder: "Reply", sendInlineReply: function() {} }
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
        for (const row of [slider, gradientSlider]) {
            const label = root.descendants(row, item => item.text === row.label)[0]
            const track = root.descendants(row, item => item.accessibleName === row.label
                && item.minimumValue !== undefined)[0]
            if (!label || !track) { failures.push("slider fixture lacks its label or track"); continue }
            const labelPos = label.mapToItem(row, 0, 0)
            const trackPos = track.mapToItem(row, 0, 0)
            if (label.contentHeight > label.height + 0.5
                    || labelPos.y + label.height + 3.5 > trackPos.y)
                failures.push("slider heading is cut off or overlaps its track: " + row.label)
        }
        for (const loader of [narrowVitals, wideVitals]) {
            if (!loader.item) { failures.push("vitals fixture did not load"); continue }
            const rows = loader.item.rows.filter(child => child.value !== undefined && child.visible)
            if (rows.length !== 4) failures.push("vitals fixture must measure all four readings")
            const bars = rows.map(row => row.children.find(child => child.wavelength !== undefined))
            if (bars.some(bar => !bar || Math.abs(bar.width - bars[0].width) > 0.5
                    || Math.abs(bar.x - bars[0].x) > 0.5))
                failures.push("vital bars differ in width or start at " + loader.width + "px")
            const cpu = rows.find(row => row.label === "CPU")
            if (cpu) {
                const names = cpu.children.find(child => child.inline !== undefined)
                const caption = cpu.sub
                const barWidth = loader.item._barW
                const rowHeight = cpu.height
                cpu.sub = ""
                const labelY = names?.y
                cpu.sub = "125° · A very long process name from the desktop launcher (123456)"
                if (cpu.height !== rowHeight || loader.item._barW !== barWidth || names?.y !== labelY)
                    failures.push("a busy process changed Home's vital layout at " + loader.width + "px"
                        + " (CPU height " + rowHeight + " → " + cpu.height
                        + ", bar width " + barWidth + " → " + loader.item._barW + ")")
                cpu.sub = caption
            }
            for (const row of rows) {
                const names = row.children.find(child => child.inline !== undefined)
                const value = row.children.find(child => child.horizontalAlignment === Text.AlignRight)
                if (!names || !value) { failures.push("a vital row lost its name or value"); continue }
                if (names.y < -0.5 || names.y + names.height > row.height + 0.5)
                    failures.push(row.label + " text escapes its row at " + loader.width + "px")
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
            for (const header of [narrow, wide]) {
                const day = header.children.find(item => item.text === header.weekday)
                const weather = header.children.find(item => item.text === header.weatherText)
                if (weather.visible && day.x + day.width > weather.x - 0.5)
                    failures.push("the weekday runs into the weather beside it")
            }
            if (!wide.children.find(item => item.text === wide.weatherText).visible)
                failures.push("a wide home header hides the weather it has room for")
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
            const card = loader.item
            const disc = root.descendants(card, item => (item.Accessible || {}).name === "Dismiss notification")[0]
            const title = root.descendants(card, item => item.text === card.titleText && item.wrapMode === Text.Wrap)[0]
            if (!disc || !title) failures.push("notification fixture lacks its title or dismiss disc")
            else {
                const d = disc.mapToItem(card, 0, 0), t = title.mapToItem(card, 0, 0)
                if (disc.width < Config.Metrics.rowHeightFor(24) || disc.height !== disc.width)
                    failures.push("notification dismiss disc ignores interface size")
                if (t.x + title.width > d.x - 5.5)
                    failures.push("notification title runs under its dismiss disc")
            }
            if (loader === narrowNotification && rows.size < 2)
                failures.push("narrow notification keeps squeezing four actions into one row")
            if (loader === wideNotification && rows.size !== 1)
                failures.push("wide notification unnecessarily wraps compact actions")
        }
        if (!replyNotification.item) failures.push("notification reply fixture did not load")
        else {
            const buttons = root.descendants(replyNotification.item,
                item => item.accessibleName === "Cancel reply" || item.accessibleName === "Send reply")
            if (buttons.length !== 2) failures.push("notification reply fixture lacks its controls")
            for (const button of buttons) {
                const bounds = button.mapToItem(replyNotification.item, 0, 0)
                if (button.width < Config.Metrics.rowHeightFor(28)
                        || button.height < Config.Metrics.rowHeightFor(28))
                    failures.push("notification reply target ignores interface size: " + button.accessibleName)
                if (bounds.x < -0.5 || bounds.x + button.width > replyNotification.width + 0.5)
                    failures.push("notification reply target escapes its narrow card")
            }
        }
        const dependency = root.descendants(blockedSetting, item => item.text === blockedSetting._detailText)[0]
        if (!dependency || dependency.truncated || dependency.contentWidth > dependency.width + 0.5)
            failures.push("the unavailable setting's explanation is clipped in a narrow pane")
        else if (blockedSetting.height < dependency.height + 24)
            failures.push("the unavailable setting does not grow to fit its explanation: row "
                + blockedSetting.height + ", detail " + dependency.height)
        for (const loader of [narrowUpdate, wideUpdate]) {
            const card = loader.item
            if (!card) { failures.push("update card fixture did not load"); continue }
            const status = root.descendants(card, item => item.text === card.status)[0]
            const version = root.descendants(card, item => item.text === card.meta)[0]
            const primary = root.descendants(card, item => item.accessibleName === card.primaryLabel)[0]
            const refresh = root.descendants(card, item => item.accessibleName === card.secondaryLabel)[0]
            if (!status || !version || !primary || !refresh) {
                failures.push("update card fixture lacks its status, version or actions")
                continue
            }
            if (!root.descendants(primary, item => item.visible && item.text === card.primaryLabel).length)
                failures.push("update card hides the install label at " + card.width + "px")
            if (version.truncated || version.contentWidth > version.width + 0.5)
                failures.push("update card clips the version at " + card.width + "px")
            const statusPos = status.mapToItem(card, 0, 0)
            const refreshPos = refresh.mapToItem(card, 0, 0)
            const primaryPos = primary.mapToItem(card, 0, 0)
            if (loader === narrowUpdate && refreshPos.y < statusPos.y + status.height - 0.5)
                failures.push("narrow update card crowds the status with its actions")
            if (loader === wideUpdate && refreshPos.x < statusPos.x + status.width - 0.5)
                failures.push("wide update card moved its actions below the status")
            if (refreshPos.x < -0.5 || primaryPos.x + primary.width > card.width + 0.5)
                failures.push("update actions escape the card at " + card.width + "px")
        }
        return failures
    }

    Component {
        id: updateCard
        UpdateStatusCard {
            title: "Silere Shell"
            meta: "v1.8.0 → v1.9.0"
            status: "A signed update is ready to install"
            primaryLabel: "Install"
            primaryGlyph: "󰅢"
            secondaryShown: true
            detail: "Release notes could not be read from /home/user/" + "a".repeat(80) + "/settings.json"
            detailError: true
        }
    }

    Column {
        id: cases
        spacing: 8
        SliderRow {
            id: slider
            width: 232
            label: "Bar opacity"
            glyph: "󰕾"
        }
        SliderRow {
            width: 232
            label: "Keyboard light"; glyph: "󰌌"
            min: 0; max: 2; step: 1; value: 0; displayValue: "Off"
        }
        ChoiceChipRow {
            width: 232; label: "Headset mode"; currentValue: "listening"
            model: [{ value: "listening", label: "Listening" }, { value: "calls", label: "Calls" }]
        }
        Loader {
            width: 232
            Component.onCompleted: setSource("../modules/menu/BatteryDetails.qml", {
                // two, so the per-battery header a single battery hides still meets the width check
                width: 232, devices: [
                    { type: Up.UPowerDeviceType.Battery, model: "Laptop battery", state: Up.UPowerDeviceState.Discharging,
                        percentage: 1, healthSupported: true, healthPercentage: 95,
                        energy: 100.5, energyCapacity: 120.7, changeRate: 32.5 },
                    { type: Up.UPowerDeviceType.Ups, model: "Desk UPS", state: Up.UPowerDeviceState.Charging,
                        percentage: 0.64, changeRate: 12.5 }]
            })
        }
        GradientSliderRow {
            id: gradientSlider
            width: 232
            label: "Hue"
            displayValue: "359°"
        }
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
            width: Math.max(520, Config.Metrics.snap4(400 * Config.Settings.fontSize / 12))
            Component.onCompleted: setSource("../modules/notifications/NotificationCard.qml", {
                width: wideNotification.width, notification: root.notificationFixture(),
                notifId: 2147483644, createdAt: Date.now()
            })
        }

        Loader {
            id: replyNotification
            width: 232
            Component.onCompleted: setSource("../modules/notifications/NotificationCard.qml", {
                width: 232, notification: root.notificationFixture(true),
                notifId: 2147483643, createdAt: Date.now()
            })
            onLoaded: item.beginReply()
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
        Loader { id: narrowUpdate; width: 232; sourceComponent: updateCard }
        Loader { id: wideUpdate; width: 456; sourceComponent: updateCard }
        Loader {
            id: narrowHeader
            width: 188; source: "../modules/menu/HomeHeader.qml"
            onLoaded: {
                item.weekday = "Wednesday"
                item.dateText = "September 30 · Week 40"
                item.uptimeText = "up 999d 23h"
                item.weatherText = "󰖙 -12°"
            }
        }
        Loader {
            id: wideHeader
            width: 388; source: "../modules/menu/HomeHeader.qml"
            onLoaded: {
                item.weekday = "Wednesday"
                item.dateText = "September 30 · Week 40"
                item.uptimeText = "up 999d 23h"
                item.weatherText = "󰖙 -12°"
            }
        }
    }
}
