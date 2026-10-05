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

    function fillVitals(item): void {
        item.active = false
        const grid = item.children.find(child => child.cells !== undefined)
        for (const tile of grid.children) {
            if (tile.value === undefined) continue
            tile.value = "100%"
            if (tile.label === "CPU") tile.sub = "125°"
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
        for (const loader of [narrowVitals, singleVitals, wideVitals]) {
            if (!loader.item) { failures.push("vitals fixture did not load"); continue }
            const grid = loader.item.children.find(child => child.cells !== undefined)
            const tiles = grid.children.filter(child => child.value !== undefined && child.visible)
            for (const tile of tiles) {
                const rows = tile.children.filter(child => child.spacing !== undefined)
                for (const row of rows)
                    if (row.x < tile.padL - 0.5
                            || row.x + row.implicitWidth > tile.width - tile.padR + 0.5)
                        failures.push(tile.label + " reading invades its tile padding at " + loader.width + "px")
                if (tile.y > 0 && tile.x < 0.5 && tile.divider)
                    failures.push("a wrapped first-column vital keeps an interior divider")
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
        return failures
    }

    Column {
        id: cases
        spacing: 8

        Loader { id: narrowVitals; width: 272; source: "../modules/menu/VitalsStrip.qml"; onLoaded: root.fillVitals(item) }
        Loader { id: singleVitals; width: 188; source: "../modules/menu/VitalsStrip.qml"; onLoaded: root.fillVitals(item) }
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
