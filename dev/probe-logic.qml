pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth as Bt
import Quickshell.Services.Mpris as Mp
import Quickshell.Services.SystemTray as St
import Quickshell.Services.UPower as Up
import "config"
import "services"
import "modules/bar"
import "modules/common"
import "modules/bar/widgets"
import "modules/bar/widgets/workspaces"
import "modules/menu/controls"
import "modules/menu/settings"
import "modules/notifications"
import "services/SettingsMigrations.js" as SettingsMigrations
import "services/NiriEvents.js" as NiriEvents

// Small behavioral assertions for pure logic that a type-check or construction
// probe cannot validate. Keep this free of compositor and hardware dependencies.
ShellRoot {
    id: root

    property int _failures: 0
    property int _checks: 0
    property string _sentInlineReply: ""
    property int _confirmActions: 0

    QtObject {
        id: probeAnchor
        property real menuAnchorX: 42
    }
    QtObject {
        id: invalidProbeAnchor
        property string menuAnchorX: "not-a-number"
    }
    QtObject {
        id: pulseTarget
        property real value: 1
    }

    Component { id: pageShellFactory; PageShell {} }
    Component { id: settingsPageFactory; SettingsPage {} }
    Component {
        id: selectStubFactory
        QtObject {
            property bool folded: false
            function _setOpen(next: bool): void { if (!next) folded = true }
        }
    }
    Component { id: sliderTrackFactory; SliderTrack {} }
    Component {
        id: confirmButtonFactory
        ConfirmButton { label: "Probe confirm"; onConfirmed: root._confirmActions++ }
    }
    Component { id: gradientSliderFactory; GradientSlider {} }
    Component { id: toggleRowFactory; ToggleRow { width: 320; label: "Probe toggle" } }
    Component { id: controlRowFactory; ControlRow { width: 320; title: "Probe control" } }
    Component { id: inlineOptionFactory; InlineOptionRow { width: 320; label: "Probe option" } }
    Component { id: swatchRowFactory; SwatchRow { options: [{ name: "Probe accent" }] } }
    Component {
        id: choiceChipFactory
        ChoiceChipRow {
            width: 320
            label: "Probe choice"
            currentValue: "a"
            model: [{ value: "a", label: "A" }, { value: "b", label: "B" }]
        }
    }
    Component { id: quickSliderFactory; QuickSlider { width: 320; accessibleName: "Audio" } }
    Component {
        id: scrollListFactory
        ShellListView {
            width: 100; height: 96
            model: 20
            delegate: Rectangle { width: 100; height: 24 }
        }
    }
    Component { id: boundedProcessFactory; BoundedProcess {} }
    Component { id: persistedFileFactory; PersistedFile { writeAllowed: false } }
    Component { id: niriBackendFactory; CompositorNiri {} }
    Component { id: processFactory; Process {} }
    Component {
        id: keptNotificationFactory
        QtObject {
            property int id: 0
            property bool tracked: false
            property bool lastGeneration: true
            property string summary: ""
            property string body: ""
            property var hints: ({})
            signal closed()
        }
    }
    Component { id: supervisedProcessFactory; SupervisedProcess {} }
    Component { id: barUnderlineFactory; BarUnderline {} }
    Component { id: barLeftFactory; Item { property bool show: true; implicitWidth: 240; implicitHeight: 24 } }
    Component { id: barCenterFactory; Item { property bool show: true; implicitWidth: 120; implicitHeight: 24 } }
    Component { id: barRightFactory; Item { property bool show: true; implicitWidth: 60; implicitHeight: 24 } }
    Component {
        id: selectRowFactory
        SelectRow {
            width: 320
            label: "Probe select"
            currentValue: "a"
            model: [{ value: "a", label: "A" },
                    { value: "b", label: "B" }]
        }
    }
    Component { id: workspaceButtonFactory; WorkspaceButton {} }
    Component { id: pillFactory; Pill { visible: true; glyph: "a" } }
    Component { id: rollingTextFactory; RollingText { visible: true; text: "one" } }
    Component { id: collapsingTextFactory; CollapsingText { animate: false; tabularDigits: true; reserveText: ":00" } }
    Component { id: clockFactory; Clock { screen: null } }
    Component { id: updatesWidgetFactory; UpdatesWidget { screen: null } }
    Component {
        id: trayItemFactory
        QtObject {
            property string id: ""
            property string title: ""
            property string tooltipTitle: ""
            property string tooltipDescription: "Probe tooltip"
            property string icon: ""
            property int status: St.Status.Active
            property bool onlyMenu: false
            property bool hasMenu: false
            property QtObject menu: null
            property int activations: 0
            function activate(): void { activations++ }
            function secondaryActivate(): void {}
            function scroll(delta: int, horizontal: bool): void {}
        }
    }
    Component {
        id: trayWidgetFactory
        TrayWidget { trayModel: root._trayProbeItems; barActive: false; height: 36 }
    }
    FileView {
        id: trayIconFixture
        path: ConfigStore.directory + "/tray-probe.svg"
        blockWrites: true
        printErrors: false
    }
    FileView {
        id: notificationDiskFixture
        path: ConfigStore.notificationsPath
        blockLoading: true
        blockAllReads: true
        blockWrites: true
        printErrors: false
    }
    FileView {
        id: persistenceGuardFixture
        path: ConfigStore.directory + "/persistence-guard-probe.json"
        blockLoading: true
        blockAllReads: true
        blockWrites: true
        printErrors: false
    }
    Component { id: pulseLoopFactory; PulseLoop {} }
    Component {
        id: windowTitleFactory
        WindowTitle {
            screen: Quickshell.screens[0] ?? null
            barActive: false
        }
    }
    Component { id: workspaceStripFactory; Workspaces { screen: null } }
    Component {
        id: workspaceAppModelFactory
        WorkspaceAppModel {
            monitorName: "DP-1"
            visibleIdsKey: "1,2"
            visibleIndexById: ({ 1: 0, 2: 1 })
            workspaceToplevels: []
        }
    }
    Component {
        id: workspaceMarkerFactory
        WorkspaceMarker {
            style: "gem"
            rowHeight: 24
            cellWidth: 26
            targetX: 0
            shown: true
            inSpecial: false
            urgent: false
            barActive: true
            paging: false
            monitorReady: true
            shiftEnabled: true
        }
    }
    Component {
        id: notificationCardFactory
        NotificationCard {
            notification: ({
                actions: [], hints: ({}), appIcon: "", image: "",
                appName: "Probe", desktopEntry: "", summary: "Probe",
                body: "", urgency: 1, expireTimeout: 5000,
                resident: false, transient: false,
                hasInlineReply: true,
                inlineReplyPlaceholder: "Write a reply",
                sendInlineReply: function(text) { root._sentInlineReply = text }
            })
            notifId: 2147483646
            createdAt: Date.now()
        }
    }

    property var _timeoutProbe: null
    property var _killProbe: null
    property var _orphanCheck: null
    property var _missingProbe: null
    property var _missingSupervised: null
    property int _missingExit: -1
    readonly property string _orphanPidFile:
        (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp")
        + "/silere-bounded-orphan-" + Quickshell.processId

    function _check(condition: bool, label: string): void {
        root._checks++
        if (condition) return
        root._failures++
        console.warn("PROBE-FAIL " + label)
    }

    // the app rail derives its Repeater model this way; Qt never diffs a JS-array model,
    // so the rail's cost is set by how often this list's contents change
    function _railNames(): var {
        const out = [""]
        const apps = Notifications.historyApps
        for (let i = 0; i < apps.length; i++) out.push(apps[i].appName)
        return out
    }
    function _sameStrings(a, b): bool {
        if (a.length !== b.length) return false
        for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false
        return true
    }

    // setValue is the same coercion the settings file goes through on load
    function _checkCoerce(key: string, value, expected, label: string): void {
        const before = ShellSettings[key]
        ShellSettings.setValue(key, value)
        const got = ShellSettings[key]
        ShellSettings[key] = before
        const same = (typeof expected === "number" && typeof got === "number")
            ? Math.abs(got - expected) < 0.0001 : got === expected
        root._check(same, label + " (" + key + " became " + got + ", expected " + expected + ")")
    }

    function _hueDistance(a: real, b: real): real {
        const d = Math.abs(a - b) % 360
        return Math.min(d, 360 - d)
    }

    function _showsText(item, expected: string): bool {
        if (!item || item.visible === false) return false
        if (item.text === expected && item.contentWidth !== undefined) return true
        const children = item.children || []
        for (let i = 0; i < children.length; i++)
            if (root._showsText(children[i], expected)) return true
        return false
    }

    function _checkAccessibleControls(): void {
        const secondsWas = ShellSettings.showSeconds
        ShellSettings.setValue("showSeconds", false)
        const toggle = toggleRowFactory.createObject(root, { key: "showSeconds" })
        toggle.Accessible.toggleAction()
        root._check(ShellSettings.showSeconds && toggle.checked && toggle.Accessible.checked,
            "accessible checkbox toggles persist through the settings setter")
        toggle.enabled = false
        toggle.Accessible.toggleAction()
        root._check(ShellSettings.showSeconds,
            "a disabled checkbox rejects accessible toggle actions")
        toggle.enabled = true
        toggle.available = false
        toggle.Accessible.toggleAction()
        root._check(!ShellSettings.showSeconds && !toggle.checked,
            "an unavailable checked setting can still be switched off accessibly")
        toggle.Accessible.toggleAction()
        root._check(!ShellSettings.showSeconds,
            "an unavailable unchecked setting cannot be switched on accessibly")
        toggle.available = true
        toggle.Accessible.pressAction()
        root._check(ShellSettings.showSeconds && toggle.checked,
            "accessible checkbox press and toggle actions share the settings path")
        toggle.destroy()
        ShellSettings.setValue("showSeconds", secondsWas)

        const control = controlRowFactory.createObject(root, { showSwitch: true })
        let activations = 0
        control.activated.connect(() => { activations++; control.active = !control.active })
        control.Accessible.toggleAction()
        root._check(activations === 1 && control.active && control.Accessible.checked,
            "accessible switch toggles call the control's activation handler")
        control.enabled = false
        control.Accessible.toggleAction()
        control.enabled = true
        control.available = false
        control.Accessible.toggleAction()
        control.available = true
        control.passive = true
        control.Accessible.toggleAction()
        root._check(activations === 1,
            "disabled, unavailable and passive switches reject accessible toggles")
        control.passive = false
        control.showSwitch = false
        control.Accessible.toggleAction()
        root._check(activations === 1,
            "a button control does not respond to checkbox toggle actions")
        control.Accessible.pressAction()
        root._check(activations === 2,
            "a button control remains accessible through its press action")
        control.badgeCount = 2
        let badgeActions = 0
        control.badgeActivated.connect(() => badgeActions++)
        const badge = root._findTrayNode(control, item =>
            item.Accessible.name === "2 missed notifications")
        root._check(badge !== null, "a notification badge exposes its accessible action")
        if (badge !== null) {
            badge.Accessible.pressAction()
            root._check(badgeActions === 1, "an enabled notification badge opens its destination")
            control.enabled = false
            badge.Accessible.pressAction()
            control.enabled = true
            control.available = false
            badge.Accessible.pressAction()
            control.available = true
            control.passive = true
            badge.Accessible.pressAction()
            root._check(badgeActions === 1,
                "disabled, unavailable and passive rows reject accessible badge actions")
            control.passive = false
            control.badgeCount = 0
            badge.Accessible.pressAction()
            root._check(badgeActions === 1,
                "a removed notification badge rejects its retained accessible action")
        }
        control.destroy()

        const option = inlineOptionFactory.createObject(root, { accessiblePrefix: "Probe choice" })
        let selections = 0
        option.triggered.connect(() => { selections++; option.selected = true })
        option.Accessible.toggleAction()
        root._check(selections === 1 && option.selected && option.Accessible.checked,
            "accessible radio toggles select an inline option")
        option.Accessible.toggleAction()
        root._check(selections === 1 && option.selected,
            "toggling a selected inline radio does not deselect or retrigger it")
        option.selected = false
        option.enabled = false
        option.Accessible.toggleAction()
        option.enabled = true
        option.interactive = false
        option.Accessible.toggleAction()
        option.interactive = true
        option.accessiblePrefix = ""
        option.Accessible.toggleAction()
        root._check(selections === 1 && !option.selected,
            "disabled, non-interactive and button options reject radio toggles")
        option.destroy()

        const swatches = swatchRowFactory.createObject(root)
        let picks = 0
        swatches.picked.connect(index => { picks++; swatches.activeIndex = index })
        const swatch = root._findTrayNode(swatches, item => item.name === "Probe accent")
        root._check(swatch !== null, "the accent fixture creates an accessible swatch")
        if (swatch !== null) {
            swatch.Accessible.toggleAction()
            root._check(picks === 1 && swatches.activeIndex === 0 && swatch.Accessible.checked,
                "accessible radio toggles select an accent swatch")
            swatch.Accessible.toggleAction()
            swatches.activeIndex = -1
            swatches.enabled = false
            swatch.Accessible.toggleAction()
            root._check(picks === 1 && swatches.activeIndex === -1,
                "selected and disabled swatches reject additional toggle actions")
        }
        swatches.destroy()

        const choices = choiceChipFactory.createObject(root)
        let choicesMade = 0
        choices.chosen.connect(value => { choicesMade++; choices.currentValue = value })
        const chip = root._findTrayNode(choices, item => item.optionLabel === "B")
        root._check(chip !== null, "the accessible choice chip fixture creates its options")
        if (chip !== null) {
            chip.Accessible.toggleAction()
            root._check(choicesMade === 1 && choices.currentValue === "b" && chip.Accessible.checked,
                "accessible radio toggles select a choice chip")
            chip.Accessible.toggleAction()
            choices.currentValue = "a"
            choices.enabled = false
            chip.Accessible.toggleAction()
            root._check(choicesMade === 1 && choices.currentValue === "a",
                "selected and disabled choice chips reject additional toggle actions")
        }
        choices.destroy()

        const quick = quickSliderFactory.createObject(root, { expandable: true })
        let expansions = 0
        quick.expandToggled.connect(() => { expansions++; quick.expanded = !quick.expanded })
        const chevron = root._findTrayNode(quick, item => item.Accessible.name === "Show audio options")
        root._check(chevron !== null, "quick slider expansion has a named accessible button")
        if (chevron !== null) {
            chevron.Accessible.pressAction()
            root._check(expansions === 1 && quick.expanded
                    && chevron.Accessible.name === "Hide audio options",
                "accessible quick slider expansion updates the action name")
            quick.enabled = false
            chevron.Accessible.pressAction()
            quick.enabled = true
            quick.expandable = false
            chevron.Accessible.pressAction()
            root._check(expansions === 1,
                "disabled and non-expandable quick sliders reject accessible expansion")
        }
        quick.destroy()
    }

    function _run(): void {
        root._checkAccessibleControls()
        const pageMovedWas = Scroll._page.movedAt
        const scrollList = scrollListFactory.createObject(root)
        Scroll._page.movedAt = 0
        scrollList.contentY = 24
        root._check(Scroll.wheelBelongsToPage(0),
            "scrolling a nested list keeps the gesture on the page when a slider passes under the pointer")
        Scroll._page.movedAt = Date.now() - Scroll.pageLatchMs - 1
        root._check(!Scroll.wheelBelongsToPage(0),
            "a settled list releases its scroll gesture for deliberate slider adjustment")
        scrollList.destroy()
        Scroll._page.movedAt = pageMovedWas
        const palette = MatugenTheme._parsePalette(
            "{\"background\":\"#101116\",\"surface\":\"#1d1f26\","
            + "\"text\":\"#e9eaf0\",\"subtext\":\"#a0a4b0\","
            + "\"accent\":\"#ffffff\",\"error\":\"#dd92a2\","
            + "\"warning\":\"#d4ad77\",\"success\":\"#94bd8b\"}")
        root._check(palette !== null && palette.accent === "#ffffff"
                && MatugenTheme._parsePalette("{\"accent\":\"#ffffff\"}") === null
                && MatugenTheme._parsePalette("{\"accent\":\"red\"}") === null,
            "matugen palette accepts only complete six-digit hex role sets")
        const paletteEverWas = MatugenTheme._everLoaded
        const paletteStaleWas = MatugenTheme.paletteStale
        MatugenTheme._everLoaded = true
        MatugenTheme.paletteStale = false
        MatugenTheme._markUnreadable()
        root._check(MatugenTheme.paletteStale && !MatugenTheme.usingFallback,
            "a palette that disappears after loading is reported as retained")
        MatugenTheme._everLoaded = false
        MatugenTheme.paletteStale = false
        MatugenTheme._markUnreadable()
        root._check(!MatugenTheme.paletteStale && MatugenTheme.usingFallback,
            "a missing first palette remains the normal bundled fallback")
        MatugenTheme._everLoaded = paletteEverWas
        MatugenTheme.paletteStale = paletteStaleWas

        root._check(XdgPaths.resolveHome("/tmp/config ", "/home/probe", ".config")
                === "/tmp/config ",
            "an absolute XDG path keeps significant trailing whitespace")
        root._check(XdgPaths.resolveHome("relative", "/home/probe user", ".config")
                === "/home/probe user/.config",
            "a relative XDG path falls back to the absolute home without rewriting it")
        root._check(XdgPaths.resolveHome("relative", "relative-home", ".config") === "",
            "XDG path resolution rejects two relative roots")
        root._check(XdgPaths.resolveAbsolute("/run/user/probe ") === "/run/user/probe ",
            "an absolute XDG runtime path keeps significant trailing whitespace")
        root._check(XdgPaths.resolveAbsolute("relative-runtime") === "",
            "XDG runtime path resolution rejects a relative directory")
        root._check(ConfigStore.directoryRetryDelay(0) === 1000
                && ConfigStore.directoryRetryDelay(1) === 1000
                && ConfigStore.directoryRetryDelay(2) === 2000
                && ConfigStore.directoryRetryDelay(20) === 8000,
            "configuration directory retries use bounded exponential delays")
        root._check(Updates.sourceIdentity("pacman", true, true, false) === "pacman|paru"
                && Updates.sourceIdentity("pacman", true, false, true) === "pacman|yay"
                && Updates.sourceIdentity("pacman", false, true, true) === "pacman|"
                && Updates.sourceIdentity("aur", true, false, true) === "aur|yay",
            "update source identity follows package-manager and helper changes")

        const providerWas = ShellSettings.lockProvider
        ShellSettings.lockProvider = "gtklock"
        root._check(SystemTools.hasGtklock
                ? Settings.lockCommand.length === 1
                : Settings.lockCommand.length === 0,
            "a named lock provider resolves only when that program is installed")
        ShellSettings.lockProvider = "custom"
        const customWas = ShellSettings.lockCommandCustom
        ShellSettings.lockCommandCustom = "swaylock -f  --color 000000"
        root._check(Settings.lockCommand.length === 4
                && Settings.lockCommand[0] === "swaylock"
                && Settings.lockCommand[3] === "000000",
            "a custom lock command splits on whitespace runs")
        ShellSettings.lockCommandCustom = "   "
        root._check(Settings.lockCommand.length === 0,
            "a blank custom lock command leaves the lock action off")
        ShellSettings.lockCommandCustom = customWas
        ShellSettings.lockProvider = providerWas

        const nlWas = ShellSettings.nightLightProvider
        ShellSettings.nightLightProvider = "wlsunset"
        const wl = Settings.nightLightCommand(3400)
        root._check(SystemTools.hasWlsunset
                ? wl.length > 0 && wl[0] === "wlsunset"
                    && wl.indexOf("3400") > 0 && wl.indexOf("3399") > 0
                : wl.length === 0,
            "wlsunset holds one temperature by pairing it with a lower night value")
        ShellSettings.nightLightProvider = "hyprsunset"
        const hs = Settings.nightLightCommand(3400)
        root._check(SystemTools.hasHyprsunset
                ? hs.length === 3 && hs[0] === "hyprsunset" && hs[2] === "3400"
                : hs.length === 0,
            "a named night light provider resolves only when that program is installed")
        root._check(Settings.nightLightProviderArgv("hyprsunset", 99999).length === 0
                || Settings.nightLightProviderArgv("hyprsunset", 99999)[2] === "20000",
            "a night light temperature is clamped before it reaches the command")
        root._check(Settings.nightLightProviderArgv("nonesuch", 4000).length === 0,
            "an unknown night light provider resolves to no command")
        const wlFloor = Settings.nightLightProviderArgv("wlsunset", 1000)
        root._check(wlFloor.length === 0
                || (wlFloor[2] === "1001" && wlFloor[4] === "1000"),
            "wlsunset keeps its day above its night at the coldest setting")
        ShellSettings.nightLightProvider = nlWas

        root._check(Audio.deviceClass(null) === ""
                && Settings.soundSettingsCommand.length
                    === (SystemTools.hasPwvucontrol || SystemTools.hasPavucontrol ? 1 : 0),
            "the sound settings hand-off resolves to one mixer, or to none")

        const cap = (p) => Audio.capturesOutput(p)
        root._check(cap({ "stream.capture.sink": true })
                && cap({ "stream.capture.sink": "true" })
                && cap({ "target.object": "alsa_output.pci-0000_06_00.6.analog-stereo.monitor" })
                && cap({ "node.target": "combined.monitor" }),
            "a stream recording system output is not a microphone in use")
        root._check(!cap({})
                && !cap(null)
                && !cap({ "stream.capture.sink": false })
                && !cap({ "target.object": "alsa_input.pci-0000_06_00.6.analog-stereo" })
                && !cap({ "target.object": "bluez_input.F4_9D_8A_18_02_3B.0" }),
            "a stream recording a real source still counts as a microphone in use")

        const buttonIdle = Theme.buttonFill(Theme.accent, false, false)
        const buttonHover = Theme.buttonFill(Theme.accent, true, false)
        const buttonPress = Theme.buttonFill(Theme.accent, true, true)
        root._check(buttonIdle.a < buttonHover.a && buttonHover.a < buttonPress.a,
            "shared button fills deepen from rest through hover to press")
        const buttonLineIdle = Theme.buttonLine(Theme.accent, false, false)
        const buttonLineHover = Theme.buttonLine(Theme.accent, true, false)
        const buttonLinePress = Theme.buttonLine(Theme.accent, true, true)
        root._check(buttonLineIdle.a < buttonLineHover.a
                && buttonLineHover.a < buttonLinePress.a,
            "shared button outlines strengthen with interaction")

        const grooveIdle = Theme.controlTrackFill(Theme.accent, false, false, false)
        const grooveHover = Theme.controlTrackFill(Theme.accent, false, true, false)
        const groovePress = Theme.controlTrackFill(Theme.accent, false, true, true)
        root._check(Theme.lchOf(grooveIdle).L < Theme.lchOf(grooveHover).L
                && Theme.lchOf(grooveHover).L < Theme.lchOf(groovePress).L,
            "toggle and slider grooves brighten from rest through hover to press")
        const activeTrackIdle = Theme.controlTrackFill(
            Theme.accent, true, false, false)
        const activeTrackPress = Theme.controlTrackFill(
            Theme.accent, true, true, true)
        root._check(Theme.lchOf(activeTrackIdle).L
                < Theme.lchOf(activeTrackPress).L,
            "checked toggles and slider fills deepen on press")
        const activeLineIdle = Theme.controlTrackLine(
            Theme.accent, true, false, false)
        const activeLineHover = Theme.controlTrackLine(
            Theme.accent, true, true, false)
        const activeLinePress = Theme.controlTrackLine(
            Theme.accent, true, true, true)
        root._check(activeLineIdle.a < activeLineHover.a
                && activeLineHover.a < activeLinePress.a,
            "active toggle and slider outlines strengthen with interaction")

        let accentMinL = Infinity
        let accentMaxL = -Infinity
        let accentNames = ({})
        for (let i = 0; i < Theme.neutralAccentPresets.length; i++) {
            const preset = Theme.neutralAccentPresets[i]
            const lch = Theme.lchOf(preset.color)
            accentMinL = Math.min(accentMinL, lch.L)
            accentMaxL = Math.max(accentMaxL, lch.L)
            accentNames[preset.name] = true
        }
        root._check(Theme.neutralAccentPresets.length === 8
                && Object.keys(accentNames).length === 8,
            "neutral accent presets keep eight distinct named choices")
        root._check(accentMaxL - accentMinL < 0.35,
            "neutral accent presets carry equal perceived lightness")

        const layout = ShellSettings._normaliseBarWidgetLayout(
            ["media", "media", "unknown"], ["clock"], ["workspaces"])
        const combined = layout.left.concat(layout.center, layout.right)
        root._check(combined.length === ShellSettings.barWidgetKeys.length,
            "widget layout restores every known key")
        root._check(new Set(combined).size === combined.length,
            "widget layout removes duplicates")
        root._check(combined.indexOf("unknown") < 0,
            "widget layout drops unknown keys")
        root._check(layout.loc.media.zone === "left" && layout.loc.clock.zone === "center",
            "widget layout reports normalized locations")
        const legacyLayout = ShellSettings._normaliseBarWidgetLayout(
            "workspaces,media", "", "shellUpdate,tray,updates,network,volume,brightness,battery,clock")
        root._check(legacyLayout.center.length === 1
                && legacyLayout.center[0] === "windowTitle",
            "an older saved widget layout migrates the new window title to its center default")
        const homeLayout = ShellSettings._normaliseBarWidgetLayout("workspaces", "windowTitle", "clock")
        root._check(homeLayout.loc.media.zone === "left" && homeLayout.loc.battery.zone === "right",
            "a widget missing from every zone returns to its catalog zone")
        root._check(ShellSettings._defaults.barWidgetOrderLeft === "workspaces,media"
                && ShellSettings._defaults.barWidgetOrderCenter === "windowTitle"
                && ShellSettings._defaults.barWidgetOrderRight
                    === "shellUpdate,tray,updates,network,bluetooth,volume,microphone,brightness,battery,clock",
            "the widget catalog derives the shipped default layout")

        const workspaceStrip = workspaceStripFactory.createObject(root)
        const forwardCrossing = workspaceStrip._intermediateIndexes(0, 2)
        const reverseCrossing = workspaceStrip._intermediateIndexes(3, 0)
        root._check(forwardCrossing.length === 1 && forwardCrossing[0] === 1
                && reverseCrossing.join(",") === "2,1",
            "workspace hand-offs retain every crossed cell in travel order")
        root._check(workspaceStrip._intermediateIndexes(0, 1).length === 0,
            "adjacent workspace switches add no intermediate fade")
        root._check(workspaceStrip.visibleIds.length > 0
                && workspaceStrip._visibleIndex(workspaceStrip.visibleIds[0]) === 0
                && workspaceStrip._visibleIndex(999999) === -1,
            "workspace page IDs resolve through the shared index")
        const appIconsWere = ShellSettings.wsShowAppIcons
        ShellSettings.wsShowAppIcons = true
        const workspaceApps = workspaceAppModelFactory.createObject(root, { workspaceToplevels: [
            { output: "DP-1", wsId: 1, appId: "foot" },
            { output: "DP-1", wsId: 5, appId: "foot" },
            { output: "HDMI-A-1", wsId: 2, appId: "foot" }] })
        workspaceApps.rebuild()
        root._check(workspaceApps.appsFor(1).length === 1 && workspaceApps.appsFor(5).length === 0
                && workspaceApps.appsFor(2).length === 0,
            "workspace app icons cover only this output's visible workspaces")
        workspaceApps.destroy()
        ShellSettings.wsShowAppIcons = appIconsWere

        root._check(workspaceStrip._btnW(-1) === 0,
            "a slot with no workspace behind it takes no width in the row")
        root._check(workspaceStrip.slotCount === workspaceStrip.effectiveWsCount,
            "the strip renders exactly the slots it is set to")
        const earlyHandoff = workspaceStrip._handoffDelayAt(0, 100, 25)
        const laterHandoff = workspaceStrip._handoffDelayAt(0, 100, 75)
        root._check(earlyHandoff === 0 && laterHandoff > earlyHandoff,
            "workspace hand-off timing follows the marker's eased travel")
        root._check(workspaceStrip._handoffDelayAt(100, 0, 25) === laterHandoff,
            "a reversed jump staggers by distance travelled, not by index")
        root._check(workspaceStrip._handoffDelayAt(50, 50, 50) === 0,
            "a hand-off with no distance to cover waits for nothing")
        const targetPage = workspaceStrip.visibleIds.join(",")
        workspaceStrip._displayIds = [999999]
        workspaceStrip._displayActiveId = 999999
        root._check(workspaceStrip._displayIdsKey === "999999"
                && workspaceStrip._displayIndexById[999999] === 0
                && workspaceStrip.activeIndex === 0
                && workspaceStrip.visibleIds.join(",") === targetPage,
            "workspace page keeps its drawn cells and marker separate from the incoming page")
        workspaceStrip._initialized = true
        workspaceStrip._displayIds = workspaceStrip.visibleIds.slice(0, 1)
        workspaceStrip._displayActiveId = 999999
        workspaceStrip.visibleIdsChanged()
        root._check(workspaceStrip._displayIdsKey === targetPage
                && workspaceStrip._displayActiveId === workspaceStrip.activeId,
            "a page that grows without changing its first workspace also commits the active marker")
        workspaceStrip._displayIds = [999999]
        workspaceStrip._displayActiveId = 999999
        workspaceStrip.opacity = 0.4
        workspaceStrip._pageShift = 8
        workspaceStrip._settleGroupMotion()
        root._check(workspaceStrip.opacity === 1 && workspaceStrip._pageShift === 0
                && workspaceStrip._displayIdsKey === targetPage
                && workspaceStrip._displayActiveId === workspaceStrip.activeId,
            "retiring workspace page motion restores the target page and settled layout")
        MenuState.requestWarm(workspaceStrip, null)
        root._check(MenuState.warmRequested
                && MenuState.warmSource === workspaceStrip,
            "an active workspace can request asynchronous menu preparation")
        MenuState.requestWarm(probeAnchor, null)
        MenuState.cancelWarm(workspaceStrip)
        root._check(MenuState.warmSource === probeAnchor,
            "an older bar cannot cancel a newer menu warm request")
        MenuState.cancelWarm(probeAnchor)
        root._check(!MenuState.warmRequested && MenuState.warmScreen === null,
            "releasing the warm owner returns the menu loader to idle")
        workspaceStrip.destroy()

        root._check(WindowActions._norm("  Org.Example.App.desktop  ") === "org.example.app"
                && WindowActions._norm(null) === "",
            "window matching normalizes desktop ids and empty hints")
        root._check(WindowActions._compact("Org.Example-App.desktop") === "orgexampleapp",
            "window matching compacts punctuation after normalizing desktop ids")
        root._check(WindowActions._hasBrowserToken("org.mozilla.firefox", "firefox")
                && WindowActions._hasBrowserToken("microsoft-edge", "edge")
                && !WindowActions._hasBrowserToken("zenity", "zen")
                && !WindowActions._hasBrowserToken("operator", "opera"),
            "browser window matching uses complete class tokens")
        root._check(WindowActions._toPid("42.9") === 42
                && WindowActions._toPid(0) === -1
                && WindowActions._toPid("not-a-pid") === -1,
            "window matching accepts only positive numeric process ids")

        const hereRef = WindowActions._hereWorkspaceRef()
        const elsewhereRef = hereRef === 2147483647 ? hereRef - 1 : hereRef + 1
        const matchingClients = [
            { ref: "hidden", wsId: -1, wsRef: elsewhereRef, focusRank: 0 },
            { ref: "here", wsId: 1, wsRef: hereRef, focusRank: 1,
                pid: "77", cls: "org.example.App", initialClass: "" },
            { ref: "elsewhere", wsId: 2, wsRef: elsewhereRef, focusRank: 9,
                pid: 77, cls: "Example-App", initialClass: "org.example.Startup" },
            { wsId: 3, wsRef: elsewhereRef, focusRank: -1 }
        ]
        root._check(WindowActions._chooseMatchingSource(
                    matchingClients, function() { return true }).ref === "elsewhere",
            "window matching prefers the best client away from the current workspace")
        root._check(WindowActions._chooseMatchingSource(
                    matchingClients, function(c) { return c.ref === "here" }).ref === "here",
            "window matching falls back to the current workspace when it is the only match")
        const pidMatches = WindowActions._pidMatches(matchingClients, 77)
        root._check(pidMatches.length === 2 && pidMatches[0].ref === "here"
                && pidMatches[1].ref === "elsewhere",
            "window matching collects every client for a normalized process id")
        root._check(WindowActions._classMatches(matchingClients[1], "ORG.EXAMPLE.APP.desktop")
                && WindowActions._classMatches(matchingClients[2], "org-example-startup")
                && !WindowActions._classMatches(matchingClients[1], "different"),
            "window matching compares exact and punctuation-compacted classes")
        root._check(WindowActions._appMatches(matchingClients[1], "Example App")
                && WindowActions._appMatches(matchingClients[2], "Launcher Example App")
                && !WindowActions._appMatches(matchingClients[1], "Ex"),
            "window matching accepts bounded app-name suffixes without tiny fuzzy matches")
        const byStartup = WindowActions._resolveByDesktopEntry(
            matchingClients, "Probe.desktop", function(identity) {
                return identity === "probe"
                    ? { startupClass: "org.example.Startup", id: "missing" } : null
            })
        const byDesktopId = WindowActions._resolveByDesktopEntry(
            matchingClients, "Probe", function() {
                return { startupClass: "missing", id: "org.example.App.desktop" }
            })
        root._check(byStartup?.ref === "elsewhere" && byDesktopId?.ref === "here"
                && WindowActions._resolveByDesktopEntry(
                    matchingClients, "", function() { return ({}) }) === null,
            "desktop-entry matching tries startup class, desktop id and empty input safely")

        root._check(Motion.allowsMotion(false, false)
                && !Motion.allowsMotion(true, false)
                && !Motion.allowsMotion(false, true),
            "visible motion is disabled by idle and reduce-motion states")

        const pulseReduceWas = ShellSettings.reduceMotion
        ShellSettings.reduceMotion = false
        const pulseLoop = pulseLoopFactory.createObject(root, {
            target: pulseTarget, targetProperty: "value", active: true,
            duration: 50, restValue: 1
        })
        root._check(pulseLoop !== null && pulseLoop.running,
            "a positive-duration pulse starts while motion is allowed")
        pulseLoop.duration = 0
        root._check(!pulseLoop.running && pulseTarget.value === 1,
            "a live pulse settles instead of restarting as a zero-duration infinite loop")
        pulseLoop.destroy()
        ShellSettings.reduceMotion = pulseReduceWas

        const workspaceMarker = workspaceMarkerFactory.createObject(root)
        root._check(workspaceMarker !== null && workspaceMarker._motionAllowed(),
            "the active workspace marker permits effects while visible and awake")
        workspaceMarker.barActive = false
        root._check(!workspaceMarker._motionAllowed(),
            "a sleeping bar suppresses workspace marker effects")
        workspaceMarker._tapScale = 1.12
        workspaceMarker._moveScale = 1.08
        workspaceMarker._specialScale = 1.05
        workspaceMarker._glint = 0.4
        workspaceMarker._settleMotion()
        root._check(workspaceMarker._tapScale === 1
                && workspaceMarker._moveScale === 1
                && workspaceMarker._specialScale === 1
                && workspaceMarker._glint === -1.15,
            "retiring workspace effects restores every animated marker value")
        workspaceMarker.destroy()

        const pill = pillFactory.createObject(root)
        pill._ready = true
        root._check(pill !== null && pill.motionActive,
            "an awake pill on a visible bar permits content motion")
        pill.glyph = "b"
        root._check(pill._shownGlyph === "a",
            "an awake pill animates a glyph swap instead of jumping to it")
        pill.hoverActive = true
        pill.barActive = false
        root._check(!pill.motionActive && pill._shownGlyph === "b",
            "a sleeping bar lands the pending glyph without animating")
        root._check(!pill.hoverEnabled && !pill.expanded && !pill.hoverActive,
            "a sleeping pill clears a previously revealed hover value")
        pill.barActive = true
        pill.hoverActive = true
        pill.collapsed = true
        root._check(!pill.hoverEnabled && !pill.expanded && !pill.motionActive,
            "a collapsing pill stops revealing values and animating content")
        pill.collapsed = false
        pill.hoverActive = true
        pill.enabled = false
        root._check(!pill.hoverEnabled && !pill.hoverActive,
            "a disabled pill clears hover state even without a pointer exit")
        pill.enabled = true
        pill.text = "A current label"
        pill.animateText = true
        root._check(root._showsText(pill, "A current label"),
            "enabling animated pill text keeps the current label visible")
        pill.glyph = "c"
        pill.animateGlyph = false
        root._check(pill._shownGlyph === "c",
            "disabling glyph motion settles the latest icon")
        pill.destroy()

        const rolling = rollingTextFactory.createObject(root)
        root._check(rolling !== null, "a rolling readout builds")
        rolling._ready = true
        rolling.text = "two"
        root._check(rolling.clip, "an awake readout rolls between two values")
        rolling.animate = false
        root._check(!rolling.clip && rolling._shown === "two",
            "a sleeping readout drops the roll and lands on the value")
        rolling.tabularDigits = true
        rolling.reserveText = "00"
        rolling.text = "11"
        const clockDigitWidth = rolling.implicitWidth
        rolling.text = "88"
        root._check(rolling.implicitWidth === clockDigitWidth,
            "tabular clock digits hold their width across a digit change")
        rolling.text = "9"
        root._check(rolling.implicitWidth === clockDigitWidth,
            "a one-digit 12-hour hour retains the two-digit clock slot")
        rolling.destroy()

        const seconds = collapsingTextFactory.createObject(root)
        seconds.text = ":11"
        const secondsWidth = seconds.width
        seconds.text = ":58"
        root._check(seconds.width === secondsWidth,
            "seconds reserve space using the same numeral features as their text")
        seconds.text = ":100"
        root._check(seconds.width > secondsWidth && !seconds.clip,
            "a reserved readout grows rather than clipping text wider than its reserve")
        seconds.expanded = false
        root._check(seconds.width === 0, "a reserved readout still folds completely closed")
        seconds.destroy()

        const barClock = clockFactory.createObject(root)
        CalendarState.openAt(17, null, barClock)
        root._check(barClock._calendarOpen,
            "the clock reflects its open calendar even without pointer hover")
        CalendarState.close()
        root._check(!barClock._calendarOpen, "closing the calendar clears the clock's active state")
        barClock.destroy()

        const updateBadge = updatesWidgetFactory.createObject(root)
        updateBadge.show = true
        updateBadge.busy = true
        root._check(updateBadge.interactive,
            "package details remain reachable while an update check is running")
        updateBadge.activated()
        root._check(MenuState.settingsActive && MenuState.settingsSection === "updates"
                && MenuState.anchorSource === updateBadge,
            "the system updates badge opens its details anchored to the triggering widget")
        MenuState.close()
        updateBadge.destroy()

        const underline = barUnderlineFactory.createObject(root)
        root._check(underline !== null, "the reactive underline builds")
        if (underline) {
            const lineEffect = underline.children.find(child =>
                typeof child._clearNetLossFlash === "function")
            root._check(lineEffect !== undefined,
                "the reactive underline exposes its network flash reset")
            if (lineEffect) {
                lineEffect._sweepSpread = 0.19
                lineEffect._bloomBoost = 0.14
                lineEffect._clearNetLossFlash()
                root._check(lineEffect._sweepSpread === 0.28
                        && lineEffect._bloomBoost === 0,
                    "a canceled network flash restores its spread and bloom")
            }
        }
        underline.destroy()

        const notificationCard = notificationCardFactory.createObject(root)
        root._check(notificationCard !== null, "a notification card builds")
        root._sentInlineReply = ""
        root._check(notificationCard.hasInlineReply
                && notificationCard._sendInlineReply("  hello  ")
                && root._sentInlineReply === "hello",
            "an inline notification reply is trimmed and sent through its live object")
        root._sentInlineReply = ""
        root._check(!notificationCard._sendInlineReply("   ")
                && root._sentInlineReply.length === 0,
            "an empty inline notification reply is not sent")
        let dismissCompletions = 0
        notificationCard.dismissRequested.connect(function() { dismissCompletions++ })
        notificationCard._leaving = true
        notificationCard._completeDismiss()
        notificationCard._completeDismiss()
        root._check(dismissCompletions === 1 && !notificationCard._leaving,
            "an interrupted notification exit completes exactly once")
        notificationCard.destroy()

        root._check(OsdBarState._presentationAllowed(false, true)
                && !OsdBarState._presentationAllowed(true, true)
                && !OsdBarState._presentationAllowed(false, false),
            "OSD presentation is disabled while idle or globally switched off")
        root._check(OsdBarState._kindAllowedByFilter("volume", "both")
                && OsdBarState._kindAllowedByFilter("brightness", "both")
                && OsdBarState._kindAllowedByFilter("volume", "volume")
                && !OsdBarState._kindAllowedByFilter("brightness", "volume"),
            "OSD input filtering admits only the selected feedback kind")
        root._check(OsdBarState._kindAllowedByFilter("microphone", "both")
                && OsdBarState._kindAllowedByFilter("microphone", "volume")
                && !OsdBarState._kindAllowedByFilter("microphone", "brightness"),
            "microphone feedback follows the volume filter")

        const holdOpenWas = OverlayCoordinator._openCount
        const holdListWas = Notifications.list
        const holdCriticalWas = Notifications.lastCritical
        Notifications.list = []
        OverlayCoordinator._openCount = 1
        const heldWhileEmpty = OverlayCoordinator.notificationsHeld
        Notifications.list = [{ notification: { id: 91 }, id: 91, time: 1000 }]
        const heldOnArrival = OverlayCoordinator.notificationsHeld
        OverlayCoordinator._openCount = 0
        const releasedOnClose = !OverlayCoordinator.notificationsHeld
        OverlayCoordinator._openCount = 1
        const showingStays = !OverlayCoordinator.notificationsHeld
        Notifications.list = []
        const heldAfterLast = OverlayCoordinator.notificationsHeld
        Notifications.lastCritical = true
        const criticalReleases = !OverlayCoordinator.notificationsHeld
        Notifications.lastCritical = holdCriticalWas
        OverlayCoordinator._openCount = holdOpenWas
        Notifications.list = holdListWas
        root._check(heldWhileEmpty && heldOnArrival && releasedOnClose && showingStays
                && heldAfterLast && criticalReleases,
            "a new notification waits for an open popup unless cards are already showing or it is critical")
        root._check(!OverlayCoordinator._environmentBlocksControls(false, false)
                && OverlayCoordinator._environmentBlocksControls(true, false)
                && OverlayCoordinator._environmentBlocksControls(false, true),
            "screen blanking and overview activation retire open control surfaces")

        const fsSilenceWas = ShellSettings.notifFullscreenSilence
        const fsMediaWas = ShellSettings.mediaProgress
        const fsOsdWas = ShellSettings.osdEnabled
        const fsIntegratedWas = ShellSettings.osdBarIntegrated
        ShellSettings.notifFullscreenSilence = true
        ShellSettings.mediaProgress = false
        ShellSettings.osdEnabled = false
        root._check(FullscreenState.wanted,
            "notification silencing demands fullscreen tracking")
        ShellSettings.notifFullscreenSilence = false
        ShellSettings.osdEnabled = true
        ShellSettings.osdBarIntegrated = false
        root._check(!FullscreenState.wanted,
            "an OSD that is not part of the bar needs no fullscreen tracking")
        ShellSettings.osdBarIntegrated = true
        root._check(FullscreenState.wanted,
            "the integrated OSD demands fullscreen tracking")
        ShellSettings.notifFullscreenSilence = fsSilenceWas
        ShellSettings.mediaProgress = fsMediaWas
        ShellSettings.osdEnabled = fsOsdWas
        ShellSettings.osdBarIntegrated = fsIntegratedWas

        const settingsNavComponent = Qt.createComponent("file://"
            + Quickshell.shellDir + "/modules/menu/SettingsNav.qml")
        const settingsNav = settingsNavComponent.status === Component.Ready
            ? settingsNavComponent.createObject(root) : null
        root._check(settingsNav !== null,
            "the internal settings navigation is available to the behavior probe")
        if (settingsNav !== null) {
            const navPinnedWas = ShellSettings.settingsNavPinned
            ShellSettings.settingsNavPinned = false
            settingsNav._expandedGroup = 0
            const openHeight = settingsNav.implicitHeight
            let heightAtSignal = -1
            settingsNav.groupToggled.connect(() => heightAtSignal = settingsNav.implicitHeight)
            settingsNav._toggleGroup(0)
            root._check(heightAtSignal === openHeight
                    && settingsNav.implicitHeight < openHeight,
                "settings navigation arms panel motion before collapsing a group")
            settingsNav._expandedGroup = 0
            settingsNav._syncExpansionMode(false, "updates")
            root._check(settingsNav._expandedGroup
                    === settingsNav._groupIndexForSection("updates"),
                "leaving multi-group navigation keeps the selected settings group open")
            settingsNav._queueReveal(3)
            settingsNav._queueReveal(-1)
            root._check(settingsNav._pendingRevealGroup === 3,
                "viewport resize frames preserve an explicit settings group reveal")
            ShellSettings.settingsNavPinned = navPinnedWas
            settingsNav.destroy()
        }
        settingsNavComponent.destroy()

        const firstSelect = selectRowFactory.createObject(root)
        const secondSelect = selectRowFactory.createObject(root)
        root._check(firstSelect !== null && secondSelect !== null,
            "shared settings selects build for coordination checks")
        if (firstSelect && secondSelect) {
            firstSelect._setOpen(true)
            secondSelect._setOpen(true)
            root._check(!firstSelect._open && secondSelect._open
                    && MenuState._settingsSelectOwner === secondSelect,
                "opening a settings select folds the previous dropdown")
            secondSelect.model = []
            root._check(!secondSelect._open
                    && MenuState._settingsSelectOwner === null,
                "an open settings select folds when its choices disappear")
            const sectionBeforeSelectProbe = MenuState.settingsSection
            const sectionAfterSelectProbe = sectionBeforeSelectProbe === "theme"
                ? "interface" : "theme"
            firstSelect._setOpen(true)
            MenuState.setSettingsSection(sectionAfterSelectProbe)
            root._check(!firstSelect._open
                    && MenuState._settingsSelectOwner === null,
                "leaving a settings page folds its open dropdown")
            MenuState.setSettingsSection(sectionBeforeSelectProbe)
        }
        if (firstSelect) firstSelect.destroy()
        if (secondSelect) secondSelect.destroy()

        const confirmButton = confirmButtonFactory.createObject(root)
        root._confirmActions = 0
        confirmButton.request()
        root._check(confirmButton.armed && root._confirmActions === 0,
            "a confirmation button arms before running its action")
        confirmButton.request()
        root._check(confirmButton.armed && root._confirmActions === 0,
            "a double-click cannot confirm a destructive action")
        confirmButton._armedAtMs = Date.now() - Metrics.confirmGuardMs - 1
        confirmButton.request()
        root._check(!confirmButton.armed && root._confirmActions === 1,
            "a deliberate second request confirms exactly once")
        confirmButton.shown = false
        confirmButton.request()
        root._check(!confirmButton.armed && !confirmButton._interactive
                && root._confirmActions === 1,
            "a fading-out confirmation button rejects accessibility activation")
        confirmButton.shown = true
        confirmButton.visible = false
        confirmButton.request()
        root._check(!confirmButton.armed && !confirmButton._interactive
                && root._confirmActions === 1,
            "an invisible confirmation button cannot arm through accessibility")
        confirmButton.visible = true
        confirmButton.request()
        confirmButton.busy = true
        confirmButton.request()
        root._check(!confirmButton.armed && root._confirmActions === 1,
            "a busy confirmation button disarms and rejects new requests")
        confirmButton.busy = false
        confirmButton.request()
        confirmButton.enabled = false
        confirmButton.request()
        root._check(!confirmButton.armed && root._confirmActions === 1,
            "a disabled confirmation button disarms and rejects new requests")
        confirmButton.destroy()

        // available is temp>0, which drops to 0 every time the service is
        // released; a control gated on it flickers on every menu open
        const tempPathWas = CpuTemp._sensorPath
        const tempProbeWas = CpuTemp._probeComplete
        CpuTemp._sensorPath = ""
        CpuTemp._probeComplete = false
        root._check(!CpuTemp.sensorMissing,
            "temperature controls stay put until the sensor probe answers")
        CpuTemp._probeComplete = true
        root._check(CpuTemp.sensorMissing,
            "a finished probe that found nothing hides the temperature controls")
        root._check(!CpuTemp._needsSensorDetection(),
            "sensorless demand reuses the completed discovery result")
        CpuTemp._sensorPath = "/sys/class/hwmon/hwmon0/temp1_input"
        root._check(!CpuTemp.sensorMissing,
            "a detected sensor keeps its controls whatever the current reading")
        CpuTemp._sensorPath = tempPathWas
        CpuTemp._probeComplete = tempProbeWas

        const badSensorsWas = CpuTemp._badSensorPaths
        CpuTemp._badSensorPaths = ""
        CpuTemp._rejectSensor("/sys/class/hwmon/hwmon1/temp1_input")
        CpuTemp._rejectSensor("/sys/class/thermal/thermal_zone0/temp")
        CpuTemp._rejectSensor("/sys/class/hwmon/hwmon1/temp1_input")
        CpuTemp._rejectSensor("")
        root._check(CpuTemp._badSensorPaths
            === ":/sys/class/hwmon/hwmon1/temp1_input:/sys/class/thermal/thermal_zone0/temp:",
            "every failed sensor stays skipped, so two bad sensors cannot ping-pong")
        CpuTemp._badSensorPaths = badSensorsWas

        const tempStartedWas = CpuTemp._started
        const tempGenerationWas = CpuTemp._detectGeneration
        const tempWarningWas = ShellSettings.osdTempWarn
        CpuTemp._started = false
        CpuTemp._sensorPath = ""
        CpuTemp._probeComplete = true
        CpuTemp._rejectSensor("/sys/class/hwmon/hwmon1/temp1_input")
        root._check(!CpuTemp._sensorRetry.running,
            "missing CPU sensors do not poll while temperature monitoring is inactive")
        CpuTemp._sensorRetry.triggered()
        root._check(CpuTemp.sensorMissing && CpuTemp._badSensorPaths === "",
            "a delayed sensor retry reconsiders failed paths without flashing temperature controls")
        ShellSettings.osdTempWarn = true
        CpuTemp._started = true
        root._check(CpuTemp._sensorRetry.running,
            "missing CPU sensors schedule recovery while temperature warnings need readings")
        CpuTemp._started = false
        root._check(!CpuTemp._sensorRetry.running,
            "stopping temperature monitoring cancels the sensor recovery timer")
        CpuTemp._sensorPath = tempPathWas
        CpuTemp._probeComplete = tempProbeWas
        CpuTemp._badSensorPaths = badSensorsWas
        CpuTemp._detectGeneration = tempGenerationWas
        ShellSettings.osdTempWarn = tempWarningWas
        CpuTemp._started = tempStartedWas

        const shiftWas = ShellSettings.workspaceShift
        const reduceMotionWas = ShellSettings.reduceMotion
        ShellSettings.workspaceShift = true
        ShellSettings.reduceMotion = false
        const crossingCell = workspaceButtonFactory.createObject(root, {
            wsId: 2, monitorReady: true, active: false, occupied: false,
            urgent: false, apps: [], compact: false, iconSize: 12,
            cellWidth: 26, rowHeight: 24, barActive: true,
            initialized: true, paging: false, markerCovers: true
        })
        crossingCell.playMarkerPass(0)
        root._check(crossingCell && crossingCell.markerPassActive,
            "a crossed workspace starts its fade hand-off")
        crossingCell._markerPassCover = 0.6
        crossingCell.playMarkerPass(20)
        root._check(crossingCell.markerPassActive
                && crossingCell._markerPassCover === 0,
            "a repeated workspace hand-off restarts from full opacity")
        crossingCell.active = true
        root._check(!crossingCell.markerPassActive
                && crossingCell._markerPassCover === 0,
            "an active destination cancels any intermediate fade")
        crossingCell.active = false
        crossingCell.markerCovers = false
        crossingCell.playMarkerPass(0)
        root._check(!crossingCell.markerPassActive,
            "a bar marker leaves the cells it crosses alone")
        crossingCell.markerCovers = true
        crossingCell.playMarkerPass(0)
        crossingCell.scale = 0.7
        crossingCell._dotFade = 0.4
        crossingCell.barActive = false
        root._check(!crossingCell.markerPassActive
                && crossingCell._markerPassCover === 0
                && crossingCell.scale === 1
                && crossingCell._dotFade === 1,
            "a sleeping workspace cell retires transient motion at its bound state")
        crossingCell.destroy()
        ShellSettings.workspaceShift = shiftWas
        ShellSettings.reduceMotion = reduceMotionWas

        // the settings file is untrusted input and the README promises it is type-checked
        // and clamped; a hand-edited or truncated file reaches setValue the same way
        // every key, not just the sampled ones: a schema entry whose declared
        // type disagrees with its property only shows up as a coerced NaN or a
        // silently kept hostile value
        const hostile = [99999, -99999, 9e99, -9e99, 0, "", "  ", "tall", "true",
            "false", null, undefined, NaN, Infinity, -Infinity, [], ({}), "0x10"]
        let fuzzBad = ""
        let fuzzCount = 0
        const fuzzSchema = ShellSettings._schema
        for (let i = 0; i < fuzzSchema.length && fuzzBad.length === 0; i++) {
            const entry = fuzzSchema[i]
            const key = entry.k
            const before = ShellSettings[key]
            for (let j = 0; j < hostile.length; j++) {
                ShellSettings.setValue(key, hostile[j])
                const got = ShellSettings[key]
                fuzzCount++
                let ok = true
                if (entry.t === "bool") ok = typeof got === "boolean"
                else if (entry.t === "int")
                    ok = typeof got === "number" && isFinite(got)
                        && got >= entry.min && got <= entry.max
                        && Math.abs(got - Math.round(got)) < 1e-9
                else if (entry.t === "real")
                    ok = typeof got === "number" && isFinite(got)
                        && got >= entry.min - 1e-9 && got <= entry.max + 1e-9
                else if (entry.t === "enum")
                    ok = entry.vals.indexOf(got) >= 0
                else if (entry.t === "re")
                    ok = typeof got === "string" && entry.re.test(got)
                if (!ok) {
                    fuzzBad = key + " (" + entry.t + ") became " + JSON.stringify(got)
                        + " from " + JSON.stringify(hostile[j])
                    break
                }
            }
            ShellSettings[key] = before
        }
        root._check(fuzzBad.length === 0,
            "every setting survives hostile input: " + (fuzzBad.length === 0
                ? fuzzCount + " coercions held their type and range" : fuzzBad))

        root._checkCoerce("barHeight", 99999, 60, "an over-range int clamps to its maximum")
        root._checkCoerce("barHeight", -5, 24, "an under-range int clamps to its minimum")
        root._checkCoerce("barHeight", "tall", 36, "a non-numeric int is refused")
        root._checkCoerce("barHeight", 30, 32, "a stepped int snaps to its grid")
        root._checkCoerce("barGap", 5, 4, "the edge gap snaps to the 4px grid")
        root._checkCoerce("uiScale", 9e99, 1.15, "an over-range real clamps to its maximum")
        root._checkCoerce("uiScale", null, 1.0, "a null real is refused")
        root._checkCoerce("barPosition", "sideways", "top", "an unknown enum value is refused")
        root._checkCoerce("barPosition", "bottom", "bottom", "a known enum value is accepted")
        root._checkCoerce("osdEnabled", 42, true, "a numeric bool is refused")
        root._checkCoerce("osdEnabled", "false", false, "a stringified bool is accepted")
        root._checkCoerce("brightnessDevice", "../../etc/passwd", "",
            "a path-bearing device name is refused")
        root._checkCoerce("fontFamily", "A\u0007B", "", "a control character in a font name is refused")
        root._checkCoerce("notifHistoryLimit", -1, 5, "a negative history limit clamps up")

        const migratedV1 = ShellSettings._migrateSettingsObject({
            windowTitleCenterGap: true,
            underlineGlow: true,
            barBorderVisible: true,
            barCornerStyle: "flat",
            untouchedFutureShape: "keep until known-key coercion"
        }, 0)
        root._check(migratedV1.version === 1
                && migratedV1.applied.join(",") === "1"
                && migratedV1.value.__version === 1,
            "settings migrations apply each target version in order")
        root._check(migratedV1.value.barCenterInGap === true
                && migratedV1.value.windowTitleCenterGap === undefined
                && migratedV1.value.underlineLastStyle === "glow"
                && migratedV1.value.barBorderVisible === false
                && migratedV1.value.barRadius === 0
                && migratedV1.value.barCornerStyle === undefined,
            "the v0 to v1 fixture produces the explicit compatibility shape")
        root._check(migratedV1.value.untouchedFutureShape
                === "keep until known-key coercion",
            "a migration does not discard unrelated input before schema coercion")

        // the engine is asserted directly so these hold after the schema number moves on:
        // a registry gap must throw, because _applyText turns the throw into a refusal to
        // write, and that is the only thing keeping a half-migrated file off disk
        let migrationGapThrew = false
        let migrationGapValue = null
        try {
            migrationGapValue = SettingsMigrations.migrate({ barHeight: 40 }, 0, 2)
        } catch (e) {
            migrationGapThrew = true
        }
        root._check(migrationGapThrew && migrationGapValue === null,
            "a missing migration step throws instead of returning a half-migrated value")
        const migrationHeld = SettingsMigrations.migrate({ barHeight: 40 }, 1, 1)
        root._check(migrationHeld.applied.length === 0
                && migrationHeld.version === 1
                && migrationHeld.value.__version === undefined
                && migrationHeld.value.barHeight === 40,
            "migrating to the version already held stamps and changes nothing")
        const migrationNewer = SettingsMigrations.migrate({ barHeight: 40 }, 3, 1)
        root._check(migrationNewer.applied.length === 0 && migrationNewer.version === 3,
            "a value newer than the target is carried through untouched")
        // "settings written by a newer version than you run keep their unknown values
        // instead of being stripped" — a downgrade silently losing config is invisible
        // until the user upgrades again, so pin the round trip rather than the wording
        const savedVersion = ShellSettings._loadedVersion
        const savedFuture = ShellSettings._futureSettings
        const savedHeight = ShellSettings.barHeight
        const savedTouched = ShellSettings._futureTouched
        ShellSettings._loadedVersion = 999
        ShellSettings._futureSettings = ({
            __version: 999, unknownFutureKey: "keep", barHeight: 40, osdTimeout: 999999
        })
        ShellSettings.barHeight = 42
        ShellSettings._futureTouched = ({ barHeight: true })
        const future = JSON.parse(ShellSettings._serialize())
        root._check(future.osdTimeout === 999999,
            "a newer file's value this version would clamp is written back as it was")
        root._check(future.unknownFutureKey === "keep",
            "a key from a newer settings file survives a write by this version")
        root._check(future.__version === 999,
            "a newer settings version is not downgraded on write")
        root._check(future.barHeight === 42,
            "a value changed by this version still lands beside the unknown keys")

        ShellSettings._loadedVersion = savedVersion
        ShellSettings._futureSettings = savedFuture
        ShellSettings._futureTouched = savedTouched
        ShellSettings.barHeight = savedHeight
        const clean = JSON.parse(ShellSettings._serialize())
        root._check(Object.keys(clean).length === 1 && clean.__version === 1,
            "an unmodified settings file serializes to nothing but its version")

        // the sec: on every schema entry exists only to light the nav dots, and ci-lint
        // guards the attribution but not the reader; an unrelated refactor deleted the
        // reader once and nothing failed, so pin the mapping here.
        // per-key tracking gates on a completed load, which this offscreen probe never gets
        root._check(Object.keys(ShellSettings.modifiedSections).length === 0,
            "an unmodified settings file marks no settings page")
        const savedLoaded = ShellSettings._loaded
        ShellSettings._loaded = true

        const savedTone = ShellSettings.baseTone
        ShellSettings.baseTone = savedTone === "black" ? "graphite" : "black"
        root._check(ShellSettings.modifiedSections.theme === true,
            "a changed setting marks the page that owns it")
        ShellSettings.baseTone = savedTone
        root._check(ShellSettings.modifiedSections.theme === undefined,
            "restoring a setting clears its page")

        const savedBattGlow = ShellSettings.underlineBattGlow
        const savedGlow = ShellSettings.underlineGlow
        const savedBorder = ShellSettings.barBorderVisible
        ShellSettings.underlineGlow = true
        ShellSettings.underlineBattGlow = !savedBattGlow
        root._check(ShellSettings.modifiedSections.underline === true
                && ShellSettings.modifiedSections.warnings === true,
            "a setting owned by two pages marks both")
        // the event rows collapse behind the glow master, so a changed value behind that
        // gate would dot a page with nothing on it to clear
        ShellSettings.underlineGlow = savedGlow
        root._check(ShellSettings.modifiedSections.warnings === true
                && ShellSettings.modifiedSections.underline === undefined,
            "a value hidden behind a page's master toggle stops dotting that page")
        ShellSettings.underlineBattGlow = savedBattGlow
        root._check(ShellSettings.modifiedSections.warnings === undefined,
            "clearing the shared setting clears the page that still showed it")

        // the masters on one page are independent. Asserted on the gate rather than the
        // aggregate because flipping a master makes that master itself non-default, and a
        // visible master row is supposed to dot its own page.
        ShellSettings.barBorderVisible = true
        ShellSettings.underlineGlow = false
        root._check(ShellSettings._dotHidden("underline", "underlineBattGlow") === true,
            "a glow row stays hidden while another master on the page is on")
        root._check(ShellSettings._dotHidden("underline", "barLineStrength") === false,
            "the line strength follows the border master, not the glow one")
        ShellSettings.underlineGlow = true
        root._check(ShellSettings._dotHidden("underline", "underlineBattGlow") === false,
            "its own master brings a glow row back")
        ShellSettings.underlineGlow = savedGlow
        ShellSettings.barBorderVisible = savedBorder

        // osd and popups collapse behind their own masters the same way
        const savedOsdEnabled = ShellSettings.osdEnabled
        ShellSettings.osdEnabled = false
        root._check(ShellSettings._dotHidden("osd", "osdTimeout") === true
                && ShellSettings._dotHidden("osd", "osdEnabled") === false,
            "the OSD body hides behind its master while the master itself still counts")
        ShellSettings.osdEnabled = savedOsdEnabled
        root._check(ShellSettings._dotHidden("osd", "osdTimeout") === false,
            "the OSD body counts again once it is back on")

        // osdMatchBar nests a second gate behind osdBarIntegrated, so it needs a negated
        // rule on top of the section's own osdEnabled one
        const savedBarIntegrated = ShellSettings.osdBarIntegrated
        ShellSettings.osdBarIntegrated = true
        root._check(ShellSettings._dotHidden("osd", "osdMatchBar") === true
                && ShellSettings._dotHidden("osd", "osdBarIntegrated") === false,
            "match-bar hides behind bar-integrated while that toggle itself still counts")
        ShellSettings.osdBarIntegrated = savedBarIntegrated
        root._check(ShellSettings._dotHidden("osd", "osdMatchBar") === false,
            "match-bar counts again once bar-integrated is back off")

        const savedDndGate = ShellSettings.dndSchedule
        ShellSettings.dndSchedule = false
        root._check(ShellSettings._dotHidden("popups", "dndFrom") === true
                && ShellSettings._dotHidden("popups", "notifHistoryLimit") === false,
            "quiet hours hides its own times without touching the rest of Popups")
        ShellSettings.dndSchedule = savedDndGate

        const savedFloating = ShellSettings.barFloating
        const savedDots = ShellSettings.dotStyle
        ShellSettings.barFloating = false
        ShellSettings.dotStyle = "none"
        root._check(ShellSettings._dotHidden("surface", "barWidth") === true
                && ShellSettings._dotHidden("separators", "barSeparatorMode") === true
                && ShellSettings._dotHidden("separators", "dotStyle") === false,
            "a docked bar hides its width and dots set to none hide their placement")
        ShellSettings.barFloating = savedFloating
        ShellSettings.dotStyle = savedDots

        const opaqueA = Qt.rgba(0.1, 0.2, 0.3, 1), opaqueB = Qt.rgba(0.9, 0.5, 0.1, 1)
        const mixed = Theme.mix(opaqueA, opaqueB, 0.3), blended = Theme.blend(opaqueA, opaqueB, 0.3)
        const tinted = Theme.blend(Qt.rgba(1, 1, 1, 0.04), opaqueB, 0.25)
        root._check(Math.abs(mixed.r - blended.r) < 0.002 && Math.abs(mixed.g - blended.g) < 0.002
                && blended.a === 1 && tinted.a < 0.3 && tinted.r > 0.9,
            "blend matches mix for opaque colours and keeps a tint over glass a tint")
        const savedGlass = [ShellSettings.popupMatchBarOpacity, ShellSettings.barOpacity, ShellSettings.surfaceBlur]
        ShellSettings.popupMatchBarOpacity = true
        ShellSettings.barOpacity = 0.62
        ShellSettings.surfaceBlur = true
        // a machine whose compositor blocks blur never frosts, so only the solid half applies there
        const glassOn = Compositor.blurBlocker.length > 0 || Theme.glass
            && Theme.menuCard.a < 0.2 && Theme.menuPane.a < 0.2
            && Theme.menuControl.a < 0.2 && Theme.menuCardSolid.a === 1
            && Theme.controlKnobFill(Theme.accent, false, false, false).a === 1
        ShellSettings.surfaceBlur = false
        const unfrostedSolid = !Theme.frosted && !Theme.glass && Theme.popup.a === 1
            && Theme.menuCard.a === 1 && Theme.panel.a < 1
        ShellSettings.surfaceBlur = true
        ShellSettings.barOpacity = 1.0
        const glassOffOpaque = !Theme.glass && Theme.menuCard.a === 1 && Theme.menuControl.a === 1
        ShellSettings.popupMatchBarOpacity = savedGlass[0]
        ShellSettings.barOpacity = savedGlass[1]
        ShellSettings.surfaceBlur = savedGlass[2]
        root._check(glassOn && glassOffOpaque,
            "a translucent bar with matching popups turns the menu to tints, knobs and hover labels stay solid, and an opaque bar keeps it solid")
        root._check(unfrostedSolid,
            "with blur off popups and the menu stay solid while the bar keeps its own opacity")

        const savedSide = [ShellSettings.barFloating, ShellSettings.barWidth, ShellSettings.barGap]
        ShellSettings.barFloating = true
        ShellSettings.barWidth = 0.72
        ShellSettings.barGap = 4
        const sideAt72 = Metrics.barSideGap(2048)
        ShellSettings.barWidth = 1.0
        ShellSettings.barGap = 12
        const sideFull = Metrics.barSideGap(2048)
        ShellSettings.barFloating = false
        const sideDocked = Metrics.barSideGap(2048)
        ShellSettings.barFloating = savedSide[0]
        ShellSettings.barWidth = savedSide[1]
        ShellSettings.barGap = savedSide[2]
        root._check(sideAt72 === 288 && sideFull === 12 && sideDocked === 0,
            "the bar and notifications share one side gap: 288 at 72%, the edge gap at 100%, none docked (got "
                + sideAt72 + ", " + sideFull + ", " + sideDocked + ")")

        const savedNight = ShellSettings.nightLightTemp
        ShellSettings.nightLightTemp = savedNight === 4000 ? 3500 : 4000
        root._check(ShellSettings.modifiedCount === 0
                && Object.keys(ShellSettings.modifiedSections).length === 0,
            "a setting with no page of its own does not offer a reset")
        ShellSettings.nightLightTemp = savedNight
        const dndBeforeSave = ShellSettings.dnd
        ShellSettings.dnd = !dndBeforeSave
        void ShellSettings._serialize()
        root._check(ShellSettings.modifiedCount === 0,
            "saving a setting with no page of its own does not offer a reset either")
        ShellSettings.dnd = dndBeforeSave

        const beforeEdit = ShellSettings._serialize()
        const savedTitle = ShellSettings.showWindowTitle
        const savedSeconds = ShellSettings.showSeconds
        ShellSettings.showWindowTitle = !savedTitle
        const edited = JSON.parse(ShellSettings._serialize())
        edited.showSeconds = !savedSeconds
        let titleFires = 0
        let readyDrops = 0
        const onTitle = () => titleFires++
        const onReady = () => { if (!ShellSettings.ready) readyDrops++ }
        ShellSettings.showWindowTitleChanged.connect(onTitle)
        ShellSettings.readyChanged.connect(onReady)
        ShellSettings._applyText(JSON.stringify(edited))
        ShellSettings.showWindowTitleChanged.disconnect(onTitle)
        ShellSettings.readyChanged.disconnect(onReady)
        root._check(titleFires === 0 && readyDrops === 0
                && ShellSettings.showSeconds === !savedSeconds
                && ShellSettings.showWindowTitle === !savedTitle,
            "a hand edit applies only the key it changed and never drops ready")
        ShellSettings._applyText(beforeEdit)
        root._check(ShellSettings.showSeconds === savedSeconds
                && ShellSettings.showWindowTitle === savedTitle,
            "a key removed by hand falls back to its default")
        ShellSettings._applyText("{unfinished settings edit")
        root._check(ShellSettings._readError.length > 0
                && !ShellSettings.flushForUpdate()
                && ShellSettings.showSeconds === savedSeconds,
            "a malformed settings edit keeps current values and pauses saving")
        ShellSettings.setValue("showSeconds", !savedSeconds)
        ShellSettings._applyText(beforeEdit)
        root._check(ShellSettings._readError.length === 0
                && ShellSettings.showSeconds === savedSeconds,
            "restoring the exact previous settings file clears its error and reapplies disk values")
        root._check(ShellSettings.flushForUpdate(),
            "restoring the exact previous settings file re-enables saving")
        // recover the remaining probe even if the unchanged-file shortcut failed
        ShellSettings._applyText(beforeEdit.slice(0, -1) + "\n}")
        ShellSettings._loaded = savedLoaded

        // the visualizer table drives a live cava config; a wrong cell is a silent cost change
        const vizExpect = ({
            wave:  { eco: [10, 26], balanced: [16, 38], smooth: [22, 50] },
            bars:  { eco: [10, 23], balanced: [14, 35], smooth: [18, 47] },
            pulse: { eco: [8, 20],  balanced: [10, 32], smooth: [14, 44] }
        })
        let vizOk = true
        for (const style in vizExpect)
            for (const preset in vizExpect[style]) {
                const p = Media.vizProfile(style, preset, false)
                if (p.bars !== vizExpect[style][preset][0]
                        || p.fps !== vizExpect[style][preset][1]) vizOk = false
            }
        root._check(vizOk, "every visualizer style and preset keeps its tuned bars and frame rate")
        const vizLow = ({ eco: [6, 18], balanced: [8, 26], smooth: [10, 34] })
        let vizLowOk = true
        for (const preset in vizLow)
            for (const style of ["wave", "bars", "pulse"]) {
                const p = Media.vizProfile(style, preset, true)
                if (p.bars !== vizLow[preset][0] || p.fps !== vizLow[preset][1]) vizLowOk = false
            }
        root._check(vizLowOk, "low power overrides the shape for every style")
        root._check(Media.vizProfile("nonsense", "nonsense", false).bars === 16,
            "an unknown style and preset land on the balanced wave profile")

        // history is restored from JSON an older release wrote, so entry shape is not given
        root._check(Notifications._normalizeEntry(null) === null,
            "a null history entry is dropped")
        root._check(Notifications._normalizeEntry("nope") === null,
            "a history entry that is not an object is dropped")
        // bodies are legitimately multi-line, so plainText keeps newlines on purpose and
        // only takes out markup and the controls that can misrepresent what a sender wrote
        root._check(Notifications._normalizeEntry({ summary: "<b>bold</b> &amp; on" }).summary
                === "bold & on",
            "history text drops markup and decodes entities")
        root._check(Notifications._normalizeEntry({ body: "a\u202Eb" }).body === "ab",
            "history text drops a bidi override a sender embedded")
        root._check(Notifications.plainText("a\u061C\u200E\u206Ab", 32) === "ab",
            "notification body drops direction marks and deprecated bidi controls")
        root._check(Notifications._normalizeEntry({ body: "line1\nline2" }).body
                === "line1\nline2",
            "history text keeps the newlines a multi-line body needs")
        const safeHistoryNumbers = Notifications._normalizeEntry({
            id: "not-a-number", urgency: Infinity, time: "Infinity"
        })
        root._check(safeHistoryNumbers.id === -1 && safeHistoryNumbers.urgency === 1
                && safeHistoryNumbers.time === 0,
            "history replaces non-finite numeric roles with safe defaults")
        const boundedHistoryNumbers = Notifications._normalizeEntry({
            id: 12.9, urgency: 99, time: -1
        })
        root._check(boundedHistoryNumbers.id === 12 && boundedHistoryNumbers.urgency === 2
                && boundedHistoryNumbers.time === 0,
            "history bounds numeric roles before inserting them into the model")
        const restoredSeen = Notifications._normalizeSeenMap(JSON.parse(
            '{"1":true,"2":"true","-1":true,"2147483648":true,"__proto__":true}'))
        root._check(Object.getPrototypeOf(restoredSeen) === null
                && restoredSeen["1"] === true
                && Object.keys(restoredSeen).length === 1,
            "notification restore accepts only boolean read flags for valid ids")
        const restoredTimes = Notifications._normalizeTimesMap({
            "1": 1234, "2": "5678", "03": 9, "4": Infinity, "5": -1
        })
        root._check(Object.getPrototypeOf(restoredTimes) === null
                && restoredTimes["1"] === 1234 && restoredTimes["2"] === 5678
                && Object.keys(restoredTimes).length === 2,
            "notification restore keeps only finite timestamps for valid ids")

        const historySchema = ShellSettings.schemaFor("notifHistoryLimit")
        root._check(historySchema !== null && historySchema.max === 100,
            "the notification history limit still declares a schema ceiling")
        root._check(Notifications._capacityFor(20, 100, false) === 100
                && Notifications._capacityFor(20, 100, true) === 20,
            "history restores against the schema ceiling until settings load, then the limit")
        root._check(Notifications._capacityFor(100, 100, false) === 100
                && Notifications._capacityFor(1, 100, true) === 5,
            "a configured limit is never widened past the ceiling nor trimmed below the floor")

        const savedLimit = ShellSettings.notifHistoryLimit
        Notifications.clearHistory()
        ShellSettings.notifHistoryLimit = 5
        for (let i = 0; i < 12; i++)
            Notifications._prependHistory({ id: i, appName: "probe", summary: "s" + i, time: 1 })
        root._check(Notifications.historyCount === 5,
            "history stops growing at the configured limit")
        root._check(Notifications.historyModel.get(0).summary === "s11",
            "the newest history entry is first")
        // at capacity an insert and a trim cancel out in the count, so anything deriving
        // rows from history has to watch the revision or it freezes on a full list
        const revAtCap = Notifications.historyRevision
        const countAtCap = Notifications.historyCount
        Notifications._prependHistory({ id: 99, appName: "probe", summary: "s99", time: 1 })
        root._check(Notifications.historyCount === countAtCap
                && Notifications.historyRevision !== revAtCap,
            "a full history reports a revision even when its count cannot move")
        Notifications.clearHistory()
        Notifications._prependHistory({ id: 201, appName: "Alpha", summary: "a1", time: 1 })
        Notifications._prependHistory({ id: 202, appName: "Beta",  summary: "b1", time: 1 })
        Notifications._prependHistory({ id: 203, appName: "Alpha", summary: "a2", time: 1 })
        const apps = Notifications.historyApps
        root._check(apps.length === 2 && apps[0].appName === "Alpha"
                && apps[0].count === 2 && apps[1].count === 1,
            "the history app list counts each sender and leads with the most recent")
        const alphaRows = []
        for (let i = 0; i < Notifications.historyCount; i++) {
            const row = Notifications.historyModel.get(i)
            if (row.appName === "Alpha") alphaRows.push({ id: row.id, time: row.time,
                appName: row.appName, summary: row.summary, body: row.body })
        }
        Notifications.clearHistoryEntries(alphaRows)
        root._check(Notifications.historyCount === 1
                && Notifications.historyModel.get(0).appName === "Beta",
            "clearing one sender leaves the rest of the history alone")

        // a count carried in the rail's array would rebuild every row on each arrival and
        // re-resolve its icon, so only the identities may live in the model
        Notifications.clearHistory()
        Notifications._prependHistory({ id: 211, appName: "Alpha", summary: "a1", time: 1 })
        Notifications._prependHistory({ id: 212, appName: "Beta",  summary: "b1", time: 2 })
        const railBefore = root._railNames()
        // stays under the capacity this block configured, or a trim would drop the oldest
        // sender and change the row list for a reason that has nothing to do with counts
        for (let i = 0; i < 2; i++)
            Notifications._prependHistory({
                id: 220 + i, appName: "Beta", summary: "b" + i, time: 10 + i
            })
        root._check(root._sameStrings(railBefore, root._railNames())
                && Notifications.historyApps[0].count === 3,
            "repeat arrivals from the leading app move its count, not the rail's row list")
        Notifications._prependHistory({ id: 230, appName: "Gamma", summary: "g", time: 20 })
        root._check(!root._sameStrings(railBefore, root._railNames())
                && root._railNames().length === 4,
            "a sender the rail has never shown does change its row list")

        // the guard that matters: the rail's model must hold bare identities. A file-url
        // component reaches its own empty Notifications copy, so the contents are not the
        // point here — the element type is
        const navComponent = Qt.createComponent("file://"
            + Quickshell.shellDir + "/modules/menu/RecentNav.qml")
        const nav = navComponent.status === Component.Ready
            ? navComponent.createObject(root) : null
        root._check(nav !== null, "the app rail is available to the behavior probe")
        if (nav !== null) {
            const model = nav._names
            let allStrings = model.length > 0
            for (let i = 0; i < model.length; i++)
                if (typeof model[i] !== "string") allStrings = false
            root._check(allStrings,
                "the app rail's model carries identities, not rows that bake in a count")
            nav.destroy()
        }

        // the notifications page draws from a mirror of history, and a reassigned list
        // model resets the view: an arrival the filter excludes must not touch a row
        Notifications.clearHistory()
        const filteredComponent = Qt.createComponent("file://"
            + Quickshell.shellDir + "/modules/menu/FilteredHistory.qml")
        const filtered = filteredComponent.status === Component.Ready
            ? filteredComponent.createObject(root) : null
        root._check(filtered !== null,
            "the notifications page mirror is available to the behavior probe")
        if (filtered !== null) {
            // a file-url component resolves its own imports, so the singleton it would
            // reach is a second copy: hand it the model the probe is driving
            filtered.source = Notifications.historyModel
            Notifications._prependHistory({ id: 301, appName: "Alpha", summary: "a1", time: 10 })
            Notifications._prependHistory({ id: 302, appName: "Beta",  summary: "b1", time: 11 })
            filtered.revision = Notifications.historyRevision
            root._check(filtered.count === 2, "an empty filter mirrors the whole history")

            filtered.filter = "Alpha"
            root._check(filtered.count === 1
                    && filtered.model.get(0).summary === "a1",
                "a filter mirrors only the rows its app sent")

            let edits = filtered.inserts + filtered.removes
            Notifications._prependHistory({ id: 303, appName: "Beta", summary: "b2", time: 12 })
            filtered.revision = Notifications.historyRevision
            root._check(filtered.count === 1
                    && filtered.inserts + filtered.removes === edits,
                "an arrival another app sent leaves every filtered row in place")

            edits = filtered.inserts + filtered.removes
            Notifications._prependHistory({ id: 304, appName: "Alpha", summary: "a2", time: 13 })
            filtered.revision = Notifications.historyRevision
            root._check(filtered.count === 2
                    && filtered.model.get(0).summary === "a2"
                    && filtered.inserts + filtered.removes === edits + 1,
                "an arrival the filter keeps costs one row, not a rebuilt list")

            edits = filtered.inserts + filtered.removes
            filtered.sync()
            root._check(filtered.inserts + filtered.removes === edits,
                "re-syncing an unchanged history edits nothing")

            filtered.filter = ""
            root._check(filtered.count === 4, "clearing the filter mirrors every row again")

            // at capacity an arrival inserts and trims in one revision, so the mirror has
            // to move both ends and still leave the rows between them alone
            const cap = Notifications._historyCapacity
            Notifications.clearHistory()
            for (let i = 0; i < cap; i++)
                Notifications._prependHistory({
                    id: 600 + i, appName: "Cap", summary: "c" + i, time: 100 + i
                })
            filtered.revision = Notifications.historyRevision
            const full = filtered.count
            edits = filtered.inserts + filtered.removes
            Notifications._prependHistory({ id: 700, appName: "Cap", summary: "newest", time: 999 })
            filtered.revision = Notifications.historyRevision
            root._check(filtered.count === full
                    && filtered.model.get(0).summary === "newest"
                    && filtered.inserts + filtered.removes === edits + 2,
                "a full history moves only the row that arrived and the row that fell off")
            Notifications.clearHistory()
            Notifications._prependHistory({ id: 801, appName: "Mail", summary: "Release ready",
                body: "Review the deployment notes", time: 1001 })
            Notifications._prependHistory({ id: 802, appName: "Chat", summary: "Release discussion",
                body: "Bring the notes", time: 1002 })
            Notifications._prependHistory({ id: 803, appName: "Mail", summary: "Lunch",
                body: "Meet at 12:00 [cafe]", time: 1003 })
            filtered.revision = Notifications.historyRevision
            filtered.query = "  RELEASE   notes  "
            root._check(filtered.count === 2,
                "history search ignores case and whitespace and matches words across title and body")
            filtered.filter = "Mail"
            root._check(filtered.count === 1 && filtered.model.get(0).id === 801,
                "history search intersects the selected app filter")
            filtered.filter = ""
            filtered.query = "mail deployment"
            root._check(filtered.count === 1 && filtered.model.get(0).id === 801,
                "history search includes the sender alongside message text")
            filtered.query = "[cafe]"
            root._check(filtered.count === 1 && filtered.model.get(0).id === 803,
                "history search treats punctuation as literal text")
            filtered.query = "missing message"
            root._check(filtered.count === 0, "unmatched history search leaves an empty result")
            filtered.query = "  \t "
            root._check(filtered.count === 3, "whitespace-only search shows all history")
            filtered.active = false
            filtered.query = "release"
            root._check(filtered.count === 3, "hidden history defers search reconciliation")
            filtered.active = true
            root._check(filtered.count === 2, "reopening history applies the pending search")
            edits = filtered.inserts + filtered.removes
            Notifications._prependHistory({ id: 804, appName: "Music", summary: "Playing",
                body: "Another song", time: 1004 })
            filtered.revision = Notifications.historyRevision
            root._check(filtered.count === 2 && filtered.inserts + filtered.removes === edits,
                "an arrival excluded by search leaves matching delegates untouched")

            const snapshot = filtered.snapshot()
            Notifications._prependHistory({ id: 805, appName: "Mail", summary: "Release tomorrow",
                body: "New notes", time: 1005 })
            filtered.revision = Notifications.historyRevision
            root._check(filtered.count === 3 && snapshot.length === 2,
                "a clear snapshot stays fixed when matching notifications arrive")
            const beforeClear = Notifications.historyRevision
            Notifications.clearHistoryEntries(snapshot)
            filtered.revision = Notifications.historyRevision
            root._check(Notifications.historyCount === 3 && filtered.count === 1
                    && filtered.model.get(0).id === 805
                    && Notifications.historyRevision === beforeClear + 1,
                "clearing search results preserves unrelated rows and later arrivals in one revision")
            Notifications.clearHistoryEntries(snapshot)
            root._check(Notifications.historyRevision === beforeClear + 1,
                "clearing an already removed snapshot does not change history")
            const changedSnapshot = filtered.snapshot()
            Notifications.historyModel.setProperty(0, "body", "Updated after confirmation")
            Notifications.clearHistoryEntries(changedSnapshot)
            root._check(Notifications.historyCount === 3
                    && Notifications.historyModel.get(0).body === "Updated after confirmation",
                "a notification updated after confirmation survives clearing an older snapshot")

            // the rail chip, the clear-by-app filter and the row label all have to spell a
            // nameless sender the same way, or search misses what the row visibly says
            Notifications.clearHistory()
            Notifications._prependHistory({ id: 810, appName: "", summary: "Disk almost full",
                body: "Only 2GB left", time: 1010 })
            filtered.revision = Notifications.historyRevision
            filtered.query = ""
            const nameless = Notifications.historyApps
            root._check(nameless.length === 1
                    && nameless[0].appName === filtered.identityOf(
                        Notifications.historyModel.get(0).appName),
                "the app rail and the history row name a sender-less notification alike")
            filtered.query = filtered.identityOf("")
            root._check(filtered.count === 1,
                "history search finds a sender-less notification by the name its row shows")
            filtered.query = ""

            // rows lay out from flags on the model, so a flag has to follow its neighbours
            const flagsOf = () => {
                const out = []
                for (let i = 0; i < filtered.count; i++) {
                    const r = filtered.model.get(i)
                    out.push((r.first ? "F" : "-") + (r.showSection ? "S" : "-")
                        + (r.groupStart ? "<" : "-") + (r.groupEnd ? ">" : "-"))
                }
                return out.join(" ")
            }
            const dayMs = 86400000
            const today = new Date(2026, 8, 24, 12, 0).getTime()
            Notifications.clearHistory()
            Notifications._prependHistory({ id: 901, appName: "Chat", summary: "old", time: today - dayMs })
            Notifications._prependHistory({ id: 902, appName: "Mail", summary: "invoice", time: today - 3000 })
            Notifications._prependHistory({ id: 903, appName: "Chat", summary: "two", time: today - 2000 })
            Notifications._prependHistory({ id: 904, appName: "Chat", summary: "one", time: today - 1000 })
            filtered.revision = Notifications.historyRevision
            root._check(flagsOf() === "FS<- ---> --<> -S<>",
                "a run of one app shares a card, and a new day starts a section and a card")
            filtered.query = "two"
            root._check(flagsOf() === "FS<>",
                "a row left alone by a search becomes the first row, its own section and card")
            filtered.query = ""
            root._check(flagsOf() === "FS<- ---> --<> -S<>",
                "clearing a search puts every neighbour's flags back")
            Notifications._prependHistory({ id: 905, appName: "Chat", summary: "alert",
                urgency: 2, time: today })
            filtered.revision = Notifications.historyRevision
            root._check(flagsOf() === "FS<> --<- ---> --<> -S<>",
                "a critical row stands alone and demotes the old first row without a rebuild")
            filtered.destroy()
        }

        Notifications.clearHistory()
        Notifications._prependHistory({
            id: 71, appName: "Probe", summary: "Earlier session", time: 1
        })
        const archivedNotification = {
            transient: false, appName: "Probe", appIcon: "", desktopEntry: "",
            summary: "Current session", body: "", urgency: 1
        }
        const firstArchive = Notifications._archiveNotification(
            archivedNotification, 71, 2, false)
        archivedNotification.summary = "Current session update"
        const replacementArchive = Notifications._archiveNotification(
            archivedNotification, 71, 3, false)
        root._check(firstArchive && !replacementArchive
                && Notifications.historyCount === 2
                && Notifications.historyModel.get(0).summary === "Current session update"
                && Notifications.historyModel.get(0).sessionCurrent
                && Notifications.historyModel.get(1).summary === "Earlier session"
                && !Notifications.historyModel.get(1).sessionCurrent,
            "a reused server id coalesces this session's updates without replacing restored history")
        ShellSettings.notifHistoryLimit = 20
        for (let i = 0; i < 15; i++)
            Notifications._prependHistory({ id: 100 + i, appName: "probe", summary: "t" + i, time: 1 })
        ShellSettings.notifHistoryLimit = 7
        root._check(Notifications.historyCount === 7,
            "lowering the limit trims history that is already stored")
        Notifications.clearHistory()
        ShellSettings.notifHistoryLimit = savedLimit

        const savedDnd = ShellSettings.dndSchedule
        const savedFrom = ShellSettings.dndFrom
        const savedTo = ShellSettings.dndTo
        ShellSettings.dndSchedule = true
        ShellSettings.dndFrom = 9
        ShellSettings.dndTo = 9
        root._check(!Notifications._quietActive,
            "a quiet-hours range starting and ending on one hour silences nothing")
        ShellSettings.dndFrom = savedFrom
        ShellSettings.dndTo = savedTo
        ShellSettings.dndSchedule = savedDnd

        const savedSection = MenuState.settingsSection
        MenuState.setSettingsSection("popups")
        root._check(MenuState.settingsSection === "popups",
            "a known settings page is selected by name")
        MenuState.setSettingsSection("notifications")
        root._check(MenuState.settingsSection === "theme",
            "a settings page renamed since a keybind was written falls back to theme")
        root._check(MenuState._ipcSection("Surface") === "surface"
                && MenuState._ipcSection("INDICATORS") === "indicators",
            "a settings page typed over ipc matches without case")
        root._check(MenuState._ipcSection("Alerts") === "warnings"
                && MenuState._ipcSection("show-order") === "widgets"
                && MenuState._ipcSection("layout") === "surface",
            "ipc accepts the page labels the rail shows")
        root._check(MenuState._ipcSection("nosuchpage") === "nosuchpage",
            "an unknown ipc page name is left alone for the caller's message")
        MenuState.setSettingsSection("Surface")
        root._check(MenuState.settingsSection === "theme",
            "setSettingsSection itself stays case-exact")
        MenuState.setSettingsSection(savedSection)

        const tabWas = MenuState.activeTab
        const tabTarget = tabWas === MenuState.recentTab ? MenuState.homeTab : MenuState.recentTab
        let tabSeenWhileChanging = -1
        const noteTabChanging = function() { tabSeenWhileChanging = MenuState.activeTab }
        MenuState.tabChanging.connect(noteTabChanging)
        MenuState.selectTab(tabTarget)
        MenuState.tabChanging.disconnect(noteTabChanging)
        root._check(tabSeenWhileChanging === tabWas && MenuState.activeTab === tabTarget,
            "a tab change is announced while the old tab is still active")
        MenuState.selectTab(tabWas)

        const historyFloor = Metrics.rowHeightFor(416)
        const historyCap = Metrics.rowHeightFor(640)
        const historyMid = Math.round((historyFloor + historyCap) / 2)
        root._check(Metrics.historyViewportFor(2000, 0) === historyFloor
                && Metrics.historyViewportFor(2000, historyMid) === Metrics.snap4Up(historyMid)
                && Metrics.historyViewportFor(2000, 5000) === historyCap
                && Metrics.historyViewportFor(300, 5000) === 300,
            "the history page fits its content between the floor, the cap and the screen")

        const edgeShift = (size, s, dpr) => (Metrics.pixelScale(size, s, dpr) - 1) * size / 2 * dpr
        const wholePx = v => Math.abs(v - Math.round(v)) < 1e-9
        root._check(Metrics.pixelScale(28, Motion.hoverScale, 1.25) === 1
                && wholePx(edgeShift(28, Motion.pressScale, 1.25))
                && Math.round(edgeShift(28, Motion.pressScale, 1.25)) === -1
                && wholePx(edgeShift(80, Motion.hoverScale, 1.25))
                && wholePx(edgeShift(22, 1.04, 2))
                && Metrics.pixelScale(0, 1.5, 1.25) === 1,
            "a scaled outline moves each edge by whole device pixels")
        root._check(edgeShift(14, 1.18, 1.25) > edgeShift(14, 1.06, 1.25)
                && edgeShift(14, 1.06, 1.25) > 0,
            "a held slider thumb still lifts past its hover size")
        // a 232 px submenu from a row at x 1460 on a 2048 px screen fits either side
        root._check(Metrics.flyoutX(1460, 220, 232, 2048, true) === 1224
                && Metrics.flyoutX(1460, 220, 232, 2048, false) === 1684
                && Metrics.flyoutX(100, 220, 232, 2048, true) === 324
                && Metrics.flyoutX(1900, 220, 232, 2048, false) === 1664,
            "a nested submenu keeps opening the way its parent did and turns only at the screen edge")

        const weekStartWas = ShellSettings.calendarWeekStart
        root._check(CalendarState.weekStartFor("monday", 0) === 1
                && CalendarState.weekStartFor("sunday", 1) === 0
                && CalendarState.weekStartFor("locale", 6) === 6
                && CalendarState.weekStartFor("locale", 0) === 0,
            "calendar week start supports explicit days and the system's Sunday or Saturday")
        ShellSettings.calendarWeekStart = "monday"
        root._check(CalendarState.leadingDays(2024, 0) === 0
                && CalendarState.leadingDays(2024, 8) === 6
                && CalendarState.weekdayAt(5) === 6 && CalendarState.weekdayAt(6) === 0,
            "Monday-first calendar aligns month starts and weekend columns")
        root._check(CalendarState.weekForRow(2021, 0, 0) === 53
                && CalendarState.weekForRow(2021, 0, 1) === 1
                && CalendarState.weekForRow(2024, 11, 5) === 1,
            "calendar week numbers cross ISO week years correctly")
        ShellSettings.calendarWeekStart = "sunday"
        root._check(CalendarState.leadingDays(2024, 8) === 0
                && CalendarState.leadingDays(2024, 0) === 1
                && CalendarState.weekdayAt(0) === 0 && CalendarState.weekdayAt(6) === 6,
            "Sunday-first calendar rotates both leading days and weekend columns")
        root._check(CalendarState.weekForRow(2021, 0, 0) === 53
                && CalendarState.weekForRow(2021, 0, 1) === 1
                && CalendarState.weekForRow(2024, 11, 4) === 1,
            "Sunday-first week numbers use the row's Thursday across year boundaries")
        root._check(Math.ceil((CalendarState.leadingDays(2024, 1) + 29) / 7) === 5,
            "a leap-year February keeps the expected number of calendar rows")
        ShellSettings.calendarWeekStart = weekStartWas
        root._checkCoerce("calendarWeekStart", "bad", "monday", "invalid calendar week starts reset")
        root._checkCoerce("calendarWeekNumbers", false, false, "calendar week numbers can be hidden")

        CalendarState.toggleAt(probeAnchor.menuAnchorX, null, probeAnchor)
        root._check(CalendarState.effectiveAnchorX === 42,
            "calendar reads its live popup anchor")
        probeAnchor.menuAnchorX = 73
        root._check(CalendarState.effectiveAnchorX === 73,
            "calendar follows popup anchor movement")
        CalendarState.close()

        // reordering bar widgets hands the zone a new array, so its Repeater destroys and
        // rebuilds the widget this anchor points at; assigning null here is what that leaves
        MenuState.toggleAt(probeAnchor.menuAnchorX, null, probeAnchor)
        root._check(MenuState.open && MenuState.anchorSource === probeAnchor,
            "menu takes the anchor it was opened from")
        root._check(OverlayCoordinator.anyOpen && ControlSurfaces.anyOpen,
            "an open control surface reports through the popup registry")
        CalendarState.toggleAt(probeAnchor.menuAnchorX, null, probeAnchor)
        root._check(CalendarState.open && !MenuState.open
                && OverlayCoordinator.anyOpen && !ControlSurfaces.anyOpen,
            "opening the calendar closes the menu and leaves the control surfaces")
        CalendarState.close()
        MenuState.toggleAt(probeAnchor.menuAnchorX, null, probeAnchor)
        // a destroyed widget nulls the property with no assignment behind it
        MenuState.anchorSource = null
        root._check(MenuState.open && MenuState.anchorSource !== null
                && !MenuState._anchorClosing,
            "a vacant anchor is claimed by a live widget instead of closing the menu")
        MenuState.adoptAnchor(probeAnchor)
        root._check(MenuState.anchorSource !== probeAnchor,
            "a widget cannot take an anchor another one already holds")
        MenuState._setAnchor(null)
        root._check(MenuState.open && MenuState.anchorSource === null
                && !MenuState._anchorClosing,
            "deliberately clearing the anchor is not reclaimed and arms no close")
        MenuState.close()
        root._check(!MenuState.open && !MenuState._anchorClosing,
            "closing the menu leaves no pending anchor close")

        const popupEdge = Metrics.popupClearance(8)
        const topPopupY = Metrics.popupY(1000, 200, false, popupEdge)
        const bottomPopupY = Metrics.popupY(1000, 200, true, popupEdge)
        root._check(isFinite(topPopupY) && isFinite(bottomPopupY),
            "popup placement stays finite")
        root._check(topPopupY + bottomPopupY + 200 === 1000,
            "top and bottom popup placement is symmetric")

        root._check(Metrics.centeredSpanX(500, 200, 100, 900) === 400,
            "a span that fits the free gap centres on its axis")
        root._check(Metrics.centeredSpanX(500, 200, 450, 900) === 450,
            "a wide left zone pushes the centred span clear of it")
        root._check(Metrics.centeredSpanX(500, 200, 100, 550) === 350,
            "a wide right zone pulls the centred span back inside the gap")
        root._check(Metrics.centeredSpanX(500, 400, 400, 600) === 400,
            "a span wider than the free gap still starts at the gap")

        root._check(IconResolver.localSource("https://example.invalid/icon.png") === "",
            "icon resolver rejects remote URLs")
        root._check(IconResolver.localSource("data:image/png;base64,AAAA") === "",
            "icon resolver rejects data URLs")
        root._check(IconResolver.localSource("file://example.invalid/icon.png") === "",
            "icon resolver rejects remote file authorities")
        root._check(IconResolver.localSource("file:relative-icon.png") === "",
            "icon resolver rejects relative file URLs")
        root._check(IconResolver.localSource("file:///tmp/icon.png") === "file:///tmp/icon.png",
            "icon resolver keeps absolute file URLs")
        root._check(IconResolver.localSource("image://icon/test") === "image://icon/test",
            "icon resolver keeps Qt image providers")
        root._check(IconResolver.senderImageSource("/tmp/fifo.png") === ""
                && IconResolver.senderImageSource("file:///tmp/fifo.png") === "",
            "notification images never open sender-provided filesystem nodes")
        root._check(IconResolver.senderImageSource("image://qsimage/1")
                === "image://qsimage/1",
            "notification image providers remain available")
        root._check(IconResolver.senderImageSource("image://icon/x?path=/etc/passwd") === ""
                && IconResolver.senderIconSource("image://icon/x?path=/etc/passwd") === "",
            "notification images and icons cannot reach the filesystem-backed icon provider")
        const mc = IconResolver.appMeta("Minecraft* 1.21.1"), rdns = IconResolver.appMeta("org.silere.ProbeTool")
        const wine = IconResolver.appMeta("ProbeTool.exe")
        root._check(mc.fallback === "M" && rdns.name === "ProbeTool" && wine.name === "ProbeTool",
            "an app without an icon is named by a reverse-DNS id's last part, never by a version or .exe")
        root._check(IconResolver.senderIconSource("IMAGE://icon/x?path=/etc/passwd") === ""
                && IconResolver.iconSource("Image://Icon/x?path=/etc/passwd") === "",
            "the icon provider guard holds when the sender varies the scheme's case")
        root._check(IconResolver.trayIconSource(
                "image://icon/spotify-linux-32?path=/usr/share/spotify/icons")
                === "image://icon/spotify-linux-32?path=/usr/share/spotify/icons",
            "a tray item keeps the icon directory its app ships")
        root._check(IconResolver.trayIconSource("image://icon/x?path=/usr/share/../../etc") === ""
                && IconResolver.trayIconSource("image://icon/x?path=relative") === "",
            "a tray icon path cannot climb out of an absolute directory")
        root._check(IconResolver.trayIconSource("image://icon/a/b?path=/tmp") === ""
                && IconResolver.trayIconSource("image://evil/x") === "",
            "only the icon provider itself is reachable from a tray item")
        root._check(IconResolver.iconSource(
                "image://icon/spotify-linux-32?path=/usr/share/spotify/icons") === "",
            "the tray's allowance does not widen the shared icon resolver")
        root._check(IconResolver.senderImageSource("image://QsImage/1")
                === "image://QsImage/1",
            "a mixed-case in-memory provider stays available")
        root._check(IconResolver.senderIconSource("/tmp/fifo.png") === ""
                && IconResolver.senderIconSource("file:///tmp/fifo.png") === "",
            "notification icons never open sender-provided filesystem nodes")
        root._check(IconResolver.senderIconSource("/usr/share/icons/hicolor/48x48/apps/a b.png")
                    === "file:///usr/share/icons/hicolor/48x48/apps/a%20b.png"
                && IconResolver.senderIconSource("file:///usr/share/pixmaps/app.png")
                    === "file:///usr/share/pixmaps/app.png",
            "a notification icon file inside the system icon directories still shows")
        root._check(IconResolver.senderImageSource("/usr/share/icons/hicolor/64x64/apps/app.png")
                    === "file:///usr/share/icons/hicolor/64x64/apps/app.png"
                && IconResolver.senderImageSource("/home/user/Pictures/shot.png") === ""
                && IconResolver.senderImageSource("/usr/share/icons/../../../dev/zero") === "",
            "notify-send's image-path shows a system icon file and nothing outside those directories")
        root._check(IconResolver.senderImageSource("image://icon//usr/share/pixmaps/app.png")
                    === "file:///usr/share/pixmaps/app.png"
                && IconResolver.senderImageSource("IMAGE://Icon//home/user/app.png") === ""
                && IconResolver.senderImageSource("image://icon/a/../../x") === ""
                && IconResolver.senderImageSource("image://icon/x?path=/etc") === ""
                && IconResolver.senderImageSource("image://icon/") === "",
            "an image-path quickshell passes through the icon provider stays inside the same rules")
        root._check(IconResolver.senderIconSource("/usr/share/icons/../../../dev/zero") === ""
                && IconResolver.senderIconSource("file:///usr/share/icons/%2e%2e/%2e%2e/%2e%2e/dev/zero") === ""
                && IconResolver.senderIconSource("file://host/usr/share/icons/app.png") === ""
                && IconResolver.senderIconSource("/usr/share/iconsx/app.png") === ""
                && IconResolver.senderIconSource("/tmp/usr/share/icons/app.png") === "",
            "a notification icon path cannot climb or reach past the system icon directories")
        root._check(IconResolver.localSource("/tmp/icon #?.png")
                === "file:///tmp/icon%20%23%3F.png",
            "icon resolver encodes local file paths")
        root._check(SafeText.initial("firefox", "?") === "F",
            "icon resolver reads a plain initial")
        root._check(SafeText.initial("  ", "N") === "N",
            "icon resolver falls back on blank names")
        const emojiInitial = SafeText.initial("🦊 Firefox", "?")
        root._check(emojiInitial.codePointAt(0) === 0x1F98A && emojiInitial.length === 2,
            "icon resolver keeps a surrogate pair whole")

        const bounded = SafeText.boundedText("abcdef", 4)
        root._check(bounded === "abc…" && bounded.length === 4,
            "icon resolver bounds external labels")
        const boundedEmoji = SafeText.boundedText("ab🦊cd", 4)
        root._check(boundedEmoji === "ab…"
                && !(boundedEmoji.charCodeAt(boundedEmoji.length - 2) >= 0xD800
                    && boundedEmoji.charCodeAt(boundedEmoji.length - 2) <= 0xDBFF),
            "text clipping never leaves half a surrogate pair")
        root._check(SafeText.singleLineText("  alpha\nbeta\u202E  ", 32) === "alpha beta",
            "icon resolver flattens controls in external labels")
        root._check(SafeText.singleLineText("pay\u200Bpal\u200F", 32) === "pay pal"
                && SafeText.singleLineText("a\u061C\u206Ab", 32) === "a b",
            "single-line labels flatten invisible direction marks")
        root._check(SafeText.initial("👩🏽‍💻 developer", "?") === "👩🏽‍💻",
            "icon resolver keeps a joined emoji grapheme whole")
        root._check(SafeText.boundedText("ab👩🏽‍💻cd", 8) === "ab…",
            "text clipping never splits a joined emoji grapheme")

        const longWindowText = "x".repeat(Compositor.maxWindowTitleChars + 20)
        const boundedWindowText = SafeText.singleLineText(
            longWindowText, Compositor.maxWindowTitleChars)
        root._check(boundedWindowText.length === Compositor.maxWindowTitleChars
                && boundedWindowText.endsWith("…"),
            "compositor bounds client-controlled window text")
        root._check(SafeText.singleLineText("Editor\nspoof\u202E", 64)
                === "Editor spoof",
            "compositor sanitizes client-controlled window text")
        root._check(Compositor.windowTitle("\u25D0 build") === "build"
                && Compositor.windowTitle("\u280B cargo test") === "cargo test"
                && Compositor.windowTitle("\u2733 npm run dev") === "npm run dev",
            "a terminal's spinner glyph is not part of its window title")
        root._check(Compositor.windowTitle("\u25CF main.ts") === "\u25CF main.ts"
                && Compositor.windowTitle("* notes") === "* notes"
                && Compositor.windowTitle("\u2733") === "\u2733",
            "unsaved markers and a lone glyph stay in the window title")
        const hypr = Compositor.isHyprland ? Compositor._be : null
        if (hypr) {
            root._check(hypr.blurBlockerFrom('{"version": "0.55.4"}{"bool": true}') === "Needs Hyprland 0.56"
                    && hypr.blurBlockerFrom('{"tag": "v0.54.0"}') === "Needs Hyprland 0.56",
                "a Hyprland without the blur protocol is named on the blur row")
            root._check(hypr.blurBlockerFrom('{"version": "0.56.2"}{"option": "decoration:blur:enabled", "bool": false}') === "Off in Hyprland"
                    && hypr.blurBlockerFrom('{"version": "0.56.2"}{"bool": true}') === ""
                    && hypr.blurBlockerFrom('{"version": "1.0.0"}{"bool": true}') === ""
                    && hypr.blurBlockerFrom("") === "",
                "Hyprland's own blur switch is read, and an unreadable answer blames nothing")
            const seqWas = hypr._eventSeq
            hypr._seqAtFlip = -1
            hypr._silentFlips = 0
            for (let i = 0; i < 4; i++) {
                hypr._eventSeq++
                hypr._noteFocusFlip()
            }
            const liveOk = !hypr._socketDead
            for (let i = 0; i < 3; i++) hypr._noteFocusFlip()
            root._check(liveOk && hypr._socketDead,
                "focus flips with socket events stay healthy; three silent flips mark the event socket dead")
            hypr._socketDead = false
            hypr._silentFlips = 0
            hypr._seqAtFlip = -1
            hypr._eventSeq = seqWas
            const tickWas = hypr._layoutTick
            hypr._eventConn.onRawEvent({ name: "workspace", data: "1" })
            const afterV1 = hypr._layoutTick
            hypr._eventConn.onRawEvent({ name: "workspacev2", data: "1,1" })
            root._check(afterV1 === tickWas && hypr._layoutTick === tickWas + 1,
                "a workspace switch rebuilds the models once, on the v2 event only")
            hypr._eventSeq = seqWas
            root._check(hypr._wsNumber({ id: 3, name: "3" }) === 3
                    && hypr._wsNumber({ id: -98, name: "special:magic" }) === -98
                    && hypr._wsNumber({ address: "4", name: "4" }) === 4
                    && hypr._wsNumber({ address: "special:magic", name: "special:magic" }) === -1
                    && hypr._wsNumber(null) === -1,
                "a window's workspace resolves from a numeric id or a 0.57 numbered address")
            root._check(hypr._missingWorkspaceId([{ id: 1 }, { id: 2 }],
                        [{ lastIpcObject: { workspace: { id: 2 } } },
                         { lastIpcObject: { workspace: { address: "4", name: "4" } } }]) === 4
                    && hypr._missingWorkspaceId([{ id: 1 }, { id: 4 }],
                        [{ lastIpcObject: { workspace: { id: 4 } } },
                         { lastIpcObject: { workspace: { id: -98, name: "special:magic" } } }, null]) === -1,
                "a window on a numbered workspace the model lacks is found; known and special ones are not")
            const refreshKeyWas = hypr._workspaceRefreshKey
            const refreshTriesWas = hypr._workspaceRefreshTries
            hypr._workspaceRefreshKey = ""
            hypr._eventConn.onRawEvent({ name: "changeworkspaceid", data: "3,5" })
            const idChangeRefreshes = hypr._workspaceRefreshKey === "id:3,5"
                && hypr._workspaceRefreshTries === 1
            for (let i = 0; i < 4; i++) hypr._requestWorkspaceRefresh("id:3,5")
            root._check(idChangeRefreshes && hypr._workspaceRefreshTries === 3,
                "a workspace id change asks for a fresh workspace list, at most three times for one gap")
            hypr._workspaceRefreshKey = refreshKeyWas
            hypr._workspaceRefreshTries = refreshTriesWas
            hypr._eventSeq = seqWas
        }
        root._check(SafeText.lastNonEmptyLine("warning: retrying\n\nfatal: no route\n\n", "fallback") === "fatal: no route",
            "lastNonEmptyLine skips trailing blank lines")
        root._check(SafeText.lastNonEmptyLine("", "fallback") === "fallback"
                && SafeText.lastNonEmptyLine("   \n  \n", "fallback") === "fallback",
            "lastNonEmptyLine falls back on blank output")

        const titleWidget = windowTitleFactory.createObject(root, {
            widthBudget: 10000
        })
        root._check(titleWidget !== null,
            "the window-title widget builds for formatting checks")
        if (titleWidget) {
            root._check(titleWidget._labelKey("notes.md") === "notes md"
                    && titleWidget._labelKey("md") === "md",
                "window-title comparison keeps a dotted document name intact")
            root._check(titleWidget._withoutAppSuffix(
                    "Silere settings — Mozilla Firefox", "Firefox")
                    === "Silere settings",
                "a separately shown app is removed from branded title suffixes")
            root._check(titleWidget._withoutAppSuffix(
                    "Learn Firefox internals — Documentation", "Firefox")
                    === "Learn Firefox internals — Documentation",
                "ordinary title words that mention an app are left untouched")
            root._check(titleWidget._withoutAppSuffix(
                    "Topic — All about Firefox", "Firefox")
                    === "Topic — All about Firefox",
                "a descriptive suffix ending in an app name is not mistaken for branding")
            titleWidget._shownVisible = true
            titleWidget._shownShowApp = true
            titleWidget._shownApp = "Firefox"
            titleWidget._shownTitle = "Silere settings — Mozilla Firefox"
            root._check(titleWidget._displayText === "Firefox "
                    + ShellSettings.dotTextGlyph + " Silere settings"
                    && titleWidget._spokenText === "Firefox, Silere settings",
                "the visual and spoken window labels share the de-duplicated title")
            titleWidget._shownShowApp = false
            root._check(titleWidget._displayTitle
                    === "Silere settings — Mozilla Firefox",
                "title-only mode preserves application branding from the client")
            titleWidget._shownShowApp = true
            titleWidget._shownTitle = "Mozilla Firefox"
            root._check(!titleWidget._showAppAndTitle
                    && titleWidget._displayText === "Mozilla Firefox",
                "a branded app-only title is not repeated beside the app name")
            root._check(titleWidget._widthCap === Metrics.windowTitleWidthFor(false),
                "an ultrawide window title stops at the shared readable-width cap")
            titleWidget.compact = true
            root._check(titleWidget._widthCap === Metrics.windowTitleWidthFor(true)
                    && titleWidget._widthCap < Metrics.windowTitleWidthFor(false),
                "compact mode gives the window title a smaller readable-width cap")
            titleWidget.destroy()
        }

        const longMediaText = "m".repeat(Media.maxMetadataChars + 20)
        root._check(SafeText.singleLineText(longMediaText, Media.maxMetadataChars).length
                === Media.maxMetadataChars,
            "media service bounds player metadata")
        root._check(Media.artSource("data:image/png;base64,AAAA") === "",
            "media service rejects inline artwork data")
        const remoteArtWas = ShellSettings.mediaRemoteArt
        ShellSettings.mediaRemoteArt = false
        root._check(Media.artSource("https://example.invalid/cover.jpg") === "",
            "remote artwork stays unfetched while the setting is off")
        ShellSettings.mediaRemoteArt = true
        root._check(Media.artSource("https://example.invalid/cover.jpg")
                === "https://example.invalid/cover.jpg",
            "remote artwork is fetched once the setting allows it")
        root._check(Media.artSource("http://example.invalid/cover.jpg") === "",
            "plaintext artwork urls are refused at either setting")
        ShellSettings.mediaRemoteArt = remoteArtWas
        root._check(/^[0-9a-f]{32}\.img$/.test(Media.remoteArtName("https://example.invalid/a b.jpg")),
            "a saved cover is named by the url's hash, never by the url")
        const artFilesWas = Media._artFiles
        Media._artFetched("https://example.invalid/fetched.jpg", true)
        const savedArt = Media._artFiles["https://example.invalid/fetched.jpg"] ?? ""
        root._check(savedArt.startsWith("file://")
                && savedArt.endsWith("/" + Media.remoteArtName("https://example.invalid/fetched.jpg")),
            "remote artwork reaches the view only as the file curl saved")
        Media._artFetched("https://example.invalid/next.jpg", true,
            [Media.remoteArtName("https://example.invalid/fetched.jpg")])
        root._check(Media._artFiles["https://example.invalid/fetched.jpg"] === undefined
                && Media._artFiles["https://example.invalid/next.jpg"] !== undefined,
            "evicted cover art loses its cached URL so revisiting it can fetch again")
        Media._artFiles = artFilesWas
        const wantedArt = ["https://example.invalid/300.jpg", "https://example.invalid/640.jpg"]
        root._check(Media.nextArtFetch(wantedArt, {}, {}) === wantedArt[0]
                && Media.nextArtFetch(wantedArt, { [wantedArt[0]]: "file:///a" }, {}) === ""
                && Media.nextArtFetch(wantedArt, {}, { [wantedArt[0]]: true }) === wantedArt[1]
                && Media.nextArtFetch(wantedArt, {}, { [wantedArt[0]]: true, [wantedArt[1]]: true }) === "",
            "a cover's fallback url is downloaded only when the preferred one failed")
        root._check(Media.artSource("file://example.invalid/cover.jpg") === "",
            "media service rejects remote file artwork")
        root._check(Media.artSource("https://example.invalid/bad\ncover.jpg") === "",
            "media service rejects control characters in artwork URLs")
        root._check(Media.artSource("image://icon/x?path=/etc/passwd") === ""
                && Media.artSource("IMAGE://icon/x?path=/etc/passwd") === "",
            "media artwork cannot reach the filesystem-backed icon provider")
        root._check(Media.artSource("image://qsimage/1") === "image://qsimage/1",
            "media artwork keeps the in-memory image provider")
        root._check(Media.normalizedArtUrl("https://open.spotify.com/image/abc")
                === "https://i.scdn.co/image/abc",
            "media artwork rewrites Spotify's dead image host")
        root._check(Media.sizedArtUrl(
                    "https://i.scdn.co/image/ab67616d00004851deadbeef")
                === "https://i.scdn.co/image/ab67616d00001e02deadbeef"
                && Media.sizedArtUrl(
                    "https://i.scdn.co/image/ab67616d0000b273deadbeef")
                === "https://i.scdn.co/image/ab67616d00001e02deadbeef"
                && Media.sizedArtUrl(
                    "https://i.scdn.co/image/ab67616d00001e02deadbeef") === ""
                && Media.sizedArtUrl("https://example.invalid/cover.jpg") === "",
            "media artwork asks Spotify for the 300px cover the tile needs, not a thumbnail or the 640px original")
        root._check(Media.trackDirectory("file:///home/u/Music/A%20B/song.mp3")
                === "/home/u/Music/A B"
                && Media.trackDirectory("https://example.invalid/song.mp3") === ""
                && Media.trackDirectory("file:///home/u/../etc/song.mp3") === "",
            "media artwork resolves a local album directory without climbing out of it")
        root._check(Media.privacyPlaceholderSource("Zen is playing media") === "Zen"
                && Media.privacyPlaceholderSource("Song is playing") === "",
            "media recognises a browser's generic playback placeholder")
        root._check(Media.metadataIsPrivacyProtected(
                "Zen is playing media", "", "", "Zen", "firefox",
                "org.mpris.MediaPlayer2.firefox")
                && !Media.metadataIsPrivacyProtected(
                    "Zen is playing media", "", "https://youtube.com/watch?v=test",
                    "Zen", "firefox", "org.mpris.MediaPlayer2.firefox")
                && !Media.metadataIsPrivacyProtected(
                    "A real video", "Creator", "", "Zen", "firefox",
                    "org.mpris.MediaPlayer2.firefox"),
            "media distinguishes privacy-redacted browser playback from real metadata")
        root._check(Media._cavaNoiseReduction >= 0
                && Media._cavaNoiseReduction <= 1
                && Media._cavaConfigText.includes("method = pipewire")
                && Media._cavaConfigText.includes("method = raw")
                && Media._cavaConfigText.includes("data_format = ascii")
                && Media._cavaConfigText.includes("ascii_max_range = 12"),
            "media service emits a valid bounded Cava raw-output profile")
        root._check(Media.finiteNonnegative(NaN) === 0
                && Media.finiteNonnegative(Infinity) === 0
                && Media.finiteNonnegative(12.5) === 12.5,
            "media service normalizes non-finite timing metadata")
        root._check(Media.positionDemand(false, true, false)
                && !Media.positionDemand(false, true, true)
                && Media.positionDemand(true, false, true),
            "media progress pauses with a concealed bar but stays live for the menu")
        const emptyPlayer = { dbusName: "browser", playbackState: Mp.MprisPlaybackState.Stopped,
            trackTitle: "" }
        const loadedPlayer = { dbusName: "music", playbackState: Mp.MprisPlaybackState.Stopped,
            trackTitle: "Ready to resume" }
        const pausedPlayer = { dbusName: "video", playbackState: Mp.MprisPlaybackState.Paused,
            trackTitle: "" }
        const playable = Media.playablePlayers([null, emptyPlayer, loadedPlayer, pausedPlayer])
        root._check(playable.length === 2 && playable[0] === loadedPlayer
                && playable[1] === pausedPlayer,
            "the media switcher retains a stopped player with a loaded track but skips empty stopped players")
        const mirrorPlayer = { dbusName: "org.mpris.MediaPlayer2.playerctld",
            playbackState: Mp.MprisPlaybackState.Playing, trackTitle: "Mirror" }
        root._check(Media.playablePlayers([mirrorPlayer, loadedPlayer])[0] === loadedPlayer
                && Media.playablePlayers([mirrorPlayer]).length === 1
                && Media.playablePlayers([]).length === 0,
            "the media switcher hides duplicate mirrors while retaining a mirror-only session")
        root._check(Audio._out._clampVolume(NaN) === 0
                && Audio._out._clampVolume(Infinity) === 0
                && Audio._out._clampVolume(1.5) === 1,
            "audio service normalizes non-finite backend volume")
        const near = (a, b) => Math.abs(a - b) < 0.0001
        root._check(near(Audio._out._stepFrom(0.43, 0.05), 0.45)
                && near(Audio._out._stepFrom(0.43, -0.05), 0.40)
                && near(Audio._out._stepFrom(0.45, 0.10), 0.55)
                && near(Audio._out._stepFrom(0.45, -0.05), 0.40),
            "a volume notch lands on the step grid from any starting level")
        root._check(CpuTemp.temperatureDemand(false, true, false, false)
                && !CpuTemp.temperatureDemand(false, true, true, false)
                && CpuTemp.temperatureDemand(true, false, true, false)
                && CpuTemp.temperatureDemand(false, false, true, true),
            "temperature polling sleeps for a hidden underline without silencing alerts")
        root._check(Audio.sinkLabel({ description: "s".repeat(300) }).length === 256,
            "audio service bounds PipeWire sink labels")

        const track = sliderTrackFactory.createObject(root, {
            width: 100, value: 0.5, min: 0, max: 1, step: 0.1
        })
        let trackChanged = -1
        track.changed.connect(value => trackChanged = value)
        track.nudge(1, 10)
        root._check(track.shownValue === 1 && trackChanged === 1,
            "slider scroll steps stop at the maximum")
        track.nudge(-1, 10)
        root._check(track.shownValue === 0 && trackChanged === 0,
            "slider scroll steps stop at the minimum")
        root._check(track._posToVal(0) === 0 && track._posToVal(100) === 1,
            "slider inset endpoints preserve the full range")
        track.nudge(1, 5)
        track._press(track._thumbCenter + 5)
        const heldOnGrab = track.shownValue === 0.5
        track._drag(track._thumbCenter + 5 + 8.6)
        const draggedFromGrab = track.shownValue === 0.6
        track._press(95)
        root._check(heldOnGrab && draggedFromGrab && track.shownValue === 1,
            "pressing the slider handle off centre holds its value, and a press on the rail still jumps")
        track.nudge(-1, 10)
        track.min = 0.5; track.max = 3; track.step = 0.05
        root._check(track.minimumValue === 0.5 && track.maximumValue === 3
                && track.stepSize === 0.05,
            "slider accessibility exposes its live bounds and increment")
        root._check(String(track._snap(1.9)) === "1.9" && String(track._snap(0.96)) === "0.95",
            "slider steps land on the grid without float residue")
        track.min = 0; track.max = 1; track.step = 0.1
        track.Accessible.increaseAction()
        root._check(track.shownValue === 0.1 && trackChanged === 0.1,
            "accessible slider increase uses the configured increment")
        track.Accessible.decreaseAction()
        root._check(track.shownValue === 0 && trackChanged === 0,
            "accessible slider decrease uses the configured increment")
        track.step = 0
        track.max = 200
        track.Accessible.increaseAction()
        root._check(track.stepSize === 2 && track.shownValue === 2 && trackChanged === 2,
            "continuous slider accessibility reports the effective nudge increment")
        track.Accessible.decreaseAction()
        track.max = 1; track.step = 0.1
        track.enabled = false
        trackChanged = -1
        track.Accessible.increaseAction()
        root._check(track.shownValue === 0 && trackChanged === -1,
            "disabled slider ignores accessibility and programmatic nudges")
        track.enabled = true
        track.interactive = false
        track.nudge(1, 1)
        root._check(track.shownValue === 0,
            "non-interactive slider ignores scroll steps")
        track.destroy()

        const gradient = gradientSliderFactory.createObject(root, {
            width: 100, position: 0.5, displayScale: 360, wraps: true
        })
        let picked = -1
        gradient.picked.connect(value => picked = value)
        root._check(gradient._wrapped(1.0) === 0
                && Math.abs(gradient._wrapped(-0.25) - 0.75) < 0.000001,
            "wrapping colour slider folds a step past either end")
        root._check(Math.abs(gradient._clamped(2) - 359 / 360) < 0.000001
                && gradient._clamped(-1) === 0,
            "wrapping colour slider clamps to its last distinct value")
        root._check(gradient.minimumValue === 0 && gradient.maximumValue === 359
                && gradient.stepSize === 1,
            "hue slider accessibility exposes distinct degree bounds")
        gradient.position = 359 / 360
        gradient.Accessible.increaseAction()
        root._check(near(picked, 0),
            "accessible hue increase wraps past the final degree")
        gradient.wraps = false; gradient.displayScale = 100; gradient.position = 0.99
        gradient.Accessible.increaseAction()
        root._check(gradient.maximumValue === 100 && near(picked, 1),
            "non-wrapping colour slider accessibility reaches its inclusive maximum")
        gradient.enabled = false
        picked = -1
        gradient.Accessible.decreaseAction()
        root._check(picked === -1,
            "disabled colour sliders reject accessible changes")
        gradient.enabled = true
        gradient.interactive = false
        picked = -1
        gradient._nudge(1, 1)
        root._check(picked === -1,
            "non-interactive colour slider ignores scroll steps")
        gradient.destroy()

        const toolsWas = SystemTools._tools
        const familyWas = SystemTools.packageFamily
        const readyWas = SystemTools.ready
        const includeAurWas = ShellSettings.updatesIncludeAur
        ShellSettings.updatesIncludeAur = true
        const updateCommand = function(family, tools) {
            SystemTools.packageFamily = family
            SystemTools._tools = tools
            SystemTools.ready = true
            return Updates._cmd()
        }
        root._check(updateCommand("pacman", { checkupdates: true }).includes("checkupdates"),
            "package updates build the pacman command")
        root._check(!SystemTools.hasTimeout
                || Updates._limit(10, "checker").startsWith("timeout -k 2 10 "),
            "package update timeouts force helpers down after the TERM grace")
        const pacmanAurCommand = updateCommand("pacman", { checkupdates: true, paru: true })
        root._check(pacmanAurCommand.includes("aurrc=$?")
                && pacmanAurCommand.includes('[ "$aurrc" -ne 1 ]'),
            "package updates distinguish an empty AUR result from helper failure")
        root._check(updateCommand("pacman", { paru: true }).includes("paru -Qu"),
            "package updates build the AUR fallback command")
        root._check(Updates._cmd().includes('[ "$rc" -ne 1 ]'),
            "the AUR-only checker treats timeouts as failures")
        root._check(updateCommand("apt", { apt: true }).includes("apt list --upgradable"),
            "package updates build the apt command")
        root._check(updateCommand("dnf", { dnf: true }).includes("dnf -q check-update"),
            "package updates build the dnf command")
        root._check(updateCommand("zypper", { zypper: true }).includes("zypper -q list-updates"),
            "package updates build the zypper command")
        root._check(updateCommand("xbps", { "xbps-install": true }).includes("xbps-install -Mun"),
            "package updates build the XBPS command")
        root._check(Updates._countFrom("42\npackage") === 42
                && Updates._countFrom("42oops") === -1
                && Updates._countFrom("-1") === -1
                && Updates._countFrom("999999") === -1,
            "package updates reject malformed or implausible counts")
        SystemTools.packageFamily = "pacman"
        SystemTools._tools = { checkupdates: true, paru: true }
        ShellSettings.updatesIncludeAur = false
        root._check(!Updates._cmd().includes("paru -Qua")
                && Updates.managerLabel === "pacman",
            "package updates honor the disabled AUR source")
        ShellSettings.updatesIncludeAur = true
        Updates.count = 3
        Updates._parseDetail("3\nSPLIT 2 1\none 1 -> 2\ntwo 2 -> 3\naur 4 -> 5")
        root._check(Updates.repoCount === 2 && Updates.aurCount === 1
                && Updates.packages.length === 3 && Updates.packages[2].aur,
            "package updates split repository and AUR details")
        const crowded = ["91", "SPLIT 90 1"]
        for (let i = 0; i < Updates._maxDetail; i++)
            crowded.push("repo" + i + " 1 -> 2")
        crowded.push("DETAIL AUR", "foreign 3 -> 4")
        Updates.count = 91
        Updates._parseDetail(crowded.join("\n"))
        root._check(Updates.packages.length === Updates._maxDetail
                && Updates.packages[Updates.packages.length - 1].name === "foreign"
                && Updates.packages[Updates.packages.length - 1].aur,
            "package details reserve and label the AUR tail after repo truncation")
        SystemTools.packageFamily = "apt"
        SystemTools._tools = { apt: true }
        Updates.count = 2
        Updates._parseDetail("2\nListing...\nlibalpha/stable 2.0 amd64 [upgradable from: 1.0]\nbeta/stable 3.1 all [upgradable from: 3.0]")
        root._check(Updates.packages.length === 2
                && Updates.packages[0].name === "libalpha"
                && Updates.packages[0].from === "1.0"
                && Updates.packages[0].to === "2.0",
            "package updates parse apt details")
        SystemTools.packageFamily = "dnf"
        SystemTools._tools = { dnf: true }
        Updates.count = 1
        Updates._parseDetail("1\nalpha.x86_64 2.4-1 updates")
        root._check(Updates.packages.length === 1
                && Updates.packages[0].name === "alpha"
                && Updates.packages[0].to === "2.4-1",
            "package updates parse dnf details")
        SystemTools.packageFamily = "zypper"
        SystemTools._tools = { zypper: true }
        Updates.count = 1
        Updates._parseDetail("1\nv | repo | alpha | 1.0 | 2.0 | x86_64")
        root._check(Updates.packages.length === 1
                && Updates.packages[0].from === "1.0"
                && Updates.packages[0].to === "2.0",
            "package updates parse zypper details")
        SystemTools.packageFamily = "xbps"
        SystemTools._tools = { "xbps-install": true }
        Updates.count = 1
        // xbps-install -n prints: pkgver action arch repository installed-size download-size
        Updates._parseDetail("1\nalpha-2.0_1 update x86_64 https://repo-default.voidlinux.org/current 1024 512\n"
            + "beta-lib-3.1_2 install x86_64 https://repo-default.voidlinux.org/current 10 5")
        root._check(Updates.packages.length === 1
                && Updates.packages[0].name === "alpha"
                && Updates.packages[0].to === "2.0_1",
            "package updates parse XBPS details and skip new dependencies")
        const checkingWas = SystemTools.checking
        const lastErrorWas = SystemTools.lastError
        const revisionWas = SystemTools._scanRevision
        SystemTools.ready = false
        SystemTools.checking = true
        SystemTools._tools = { hyprctl: true }
        SystemTools._retryDelayMs = 0
        SystemTools._scanFailed("scan gave up")
        root._check(SystemTools.ready && !SystemTools.checking
                && SystemTools.lastError === "scan gave up"
                && SystemTools._tools.hyprctl === true
                && SystemTools._retryDelayMs === SystemTools._minRetryDelayMs
                && SystemTools._scanRevision === revisionWas + 1,
            "a capability scan that gives up keeps the last-known tools and arms a retry")
        root._check(SystemTools._repairOutcome(0, false) === "done"
                && SystemTools._repairOutcome(1, false) === "failed"
                && SystemTools._repairOutcome(0, true) === "failed",
            "a timed-out Matugen repair cannot be overwritten as successful on exit")
        SystemTools.checking = checkingWas
        SystemTools.lastError = lastErrorWas
        SystemTools._scanRevision = revisionWas
        const cpuActiveWas = SysInfo._active
        const cpuTotalWas = SysInfo._lastCpuTotal
        const cpuIdleWas = SysInfo._lastCpuIdle
        const cpuPctWas = SysInfo.cpuPct
        const cpuReadyWas = SysInfo.cpuReady
        SysInfo._active = true
        SysInfo.cpuReady = false
        SysInfo._lastCpuTotal = 0
        SysInfo._lastCpuIdle = 0
        // nonzero iowait: it counts as idle, and a sample without it proves nothing
        SysInfo._applyCpuStat("cpu  100 0 100 800 100 0 0 0 0 0\n")
        root._check(!SysInfo.cpuReady,
            "the Now page waits for a CPU delta before showing a percentage")
        SysInfo._applyCpuStat("cpu  150 0 150 900 150 0 0 0 0 0\n")
        root._check(SysInfo.cpuReady && Math.abs(SysInfo.cpuPct - 0.4) < 0.001,
            "cpu load counts iowait as idle, not as busy")
        // guest and guest_nice are already counted inside user and nice
        SysInfo._lastCpuTotal = 0
        SysInfo._lastCpuIdle = 0
        SysInfo._applyCpuStat("cpu  100 0 100 800 0 0 0 0 500 500\n")
        SysInfo._applyCpuStat("cpu  150 0 150 900 0 0 0 0 900 900\n")
        root._check(Math.abs(SysInfo.cpuPct - 0.5) < 0.001,
            "cpu load leaves out guest time already counted in user")
        SysInfo._applyCpuStat("cpu  1 0 1 8 0 0 0 0\n")
        root._check(!SysInfo.cpuReady && SysInfo.cpuPct === 0,
            "CPU counter rollback discards the stale percentage and re-primes")
        SysInfo._applyCpuStat("cpu  2 0 2 16 0 0 0 0\n")
        root._check(SysInfo.cpuReady && Math.abs(SysInfo.cpuPct - 0.2) < 0.001,
            "CPU readings recover after a counter reset")
        SysInfo._applyCpuStat("cpu  4 0 4 15 0 0 0 0\n")
        root._check(!SysInfo.cpuReady && SysInfo.cpuPct === 0,
            "an idle-counter rollback cannot flash a bogus 100 percent CPU load")
        SysInfo._applyCpuStat("cpu  broken 0 3 14 0 0 0 0\n")
        root._check(!SysInfo.cpuReady && SysInfo._lastCpuTotal === 0,
            "malformed CPU counters clear the sample rather than partially parsing it")
        SysInfo._applyCpuStat("cpu  10 0 10 80 0 0 0 0\n")
        root._check(!SysInfo.cpuReady,
            "the first valid CPU sample after a failed read is a baseline")
        SysInfo._lastCpuTotal = cpuTotalWas
        SysInfo._lastCpuIdle = cpuIdleWas
        SysInfo.cpuPct = cpuPctWas
        SysInfo.cpuReady = cpuReadyWas
        SysInfo._active = cpuActiveWas

        const memTotalWas = SysInfo.memTotalKb, memAvailWas = SysInfo.memAvailKb
        SysInfo._active = true
        SysInfo._applyMeminfo("MemTotal: 100 kB\nMemAvailable: 150 kB\n")
        root._check(SysInfo.memPct === 0 && SysInfo.memAvailKb === 100,
            "inconsistent memory samples cannot produce a negative percentage")
        SysInfo._applyMeminfo("MemTotal: 100 kB\n")
        root._check(SysInfo.memTotalKb === 0 && SysInfo.memPct === 0,
            "missing memory fields retire the previous reading")
        SysInfo.memTotalKb = memTotalWas
        SysInfo.memAvailKb = memAvailWas
        SysInfo._active = cpuActiveWas

        const brightnessToolsWas = SystemTools._tools
        const brightnessErrorWas = Brightness.lastError
        const brightnessQueuedWas = Brightness._applyQueued
        SystemTools._tools = Object.assign({}, brightnessToolsWas, { brightnessctl: true })
        Brightness.lastError = "Current display error"
        Brightness._applyQueued = true
        Brightness._acceptWriteResult(Brightness._device + "-old", 1, false, "Old display error")
        root._check(Brightness.lastError === "Current display error" && Brightness._applyQueued,
            "a completed write to the old display cannot overwrite the new display's status")
        Brightness._acceptWriteResult(Brightness._device + "-old", -1, true, "")
        root._check(Brightness.lastError === "Current display error" && Brightness._applyQueued,
            "an old display's timeout preserves the new display's queued brightness write")
        Brightness._acceptWriteResult(Brightness._device, 1, false, "Permission denied\n")
        root._check(Brightness.lastError === "Permission denied",
            "brightness failures on the current display remain visible")
        Brightness._acceptWriteResult(Brightness._device, -1, true, "")
        root._check(Brightness.lastError === "Brightness write timed out",
            "a timeout on the current display remains a failure")
        Brightness._acceptWriteResult(Brightness._device, 0, false, "")
        root._check(Brightness.lastError === "",
            "a successful write on the current display clears its previous error")
        Brightness.lastError = brightnessErrorWas
        Brightness._applyQueued = brightnessQueuedWas
        SystemTools._tools = brightnessToolsWas

        const niri = niriBackendFactory.createObject(root)
        niri._onLine(JSON.stringify({ WorkspacesChanged: { workspaces: [
            { id: 11, idx: 1, output: "DP-1", is_active: true,  is_focused: true },
            { id: 22, idx: 2, output: "DP-1", is_active: false, is_focused: false }
        ]}}))
        niri._onLine(JSON.stringify({ WindowsChanged: { windows: [
            { id: 90, workspace_id: 22, app_id: "probe.app", title: "t", pid: 1 }
        ]}}))
        const niriWs = niri.workspaces
        const niriById = {}
        for (let i = 0; i < niriWs.length; i++) niriById[niriWs[i].wsId] = niriWs[i]
        root._check(niriById[2] !== undefined && niriById[2].occupied === true,
            "a niri workspace holding an unfocused window reads as occupied")
        root._check(niriById[1] !== undefined && niriById[1].occupied === false,
            "a niri workspace holding no window reads as empty")
        const titleSettingWas = ShellSettings.showWindowTitle
        ShellSettings.showWindowTitle = true
        niri._titleSyncTimer.stop()
        niri._backgroundTitleSyncTimer.stop()
        niri._onLine(JSON.stringify({ WindowOpenedOrChanged: { window:
            { id: 90, workspace_id: 22, app_id: "probe.app", title: "background", pid: 1 }
        }}))
        root._check(niri._backgroundTitleSyncTimer.running
                && !niri._titleSyncTimer.running,
            "a background niri title waits for the batched title snapshot")
        niri._backgroundTitleSyncTimer.stop()
        niri._onLine(JSON.stringify({ WindowOpenedOrChanged: { window:
            { id: 90, workspace_id: 22, app_id: "probe.app", title: "focused", pid: 1,
              is_focused: true }
        }}))
        niri._titleSyncTimer.stop()
        niri._onLine(JSON.stringify({ WindowOpenedOrChanged: { window:
            { id: 90, workspace_id: 22, app_id: "probe.app", title: "focused again", pid: 1,
              is_focused: true }
        }}))
        root._check(niri._titleSyncTimer.running
                && !niri._backgroundTitleSyncTimer.running,
            "the focused niri title keeps the responsive title path")
        ShellSettings.showWindowTitle = false
        const titleBeforeAction = niri.toplevels[0].title
        const actionTitleEvent = Object.assign({}, niri._winRaw[0],
            { title: "new media title" })
        niri._onLine(JSON.stringify({ WindowOpenedOrChanged: { window: actionTitleEvent } }))
        root._check(niri.toplevels[0].title === titleBeforeAction,
            "a hidden niri title does not rebuild the window list on each event")
        niri.refreshToplevels()
        root._check(niri.toplevels[0].title === "new media title",
            "a window action refreshes the latest niri title on demand")
        ShellSettings.showWindowTitle = titleSettingWas

        // niri idx values are per-output, so both monitors carry an idx 1 and every
        // per-workspace event has to be scoped by output rather than by id alone
        niri._onLine(JSON.stringify({ WorkspacesChanged: { workspaces: [
            { id: 10, idx: 1, output: "DP-1", is_active: true,  is_focused: true },
            { id: 11, idx: 2, output: "DP-1", is_active: false, is_focused: false },
            { id: 20, idx: 1, output: "HDMI-A-1", is_active: true, is_focused: false }
        ]}}))
        const _niriByOutput = function() {
            const out = {}
            const list = niri.workspaces
            for (let i = 0; i < list.length; i++) {
                const w = list[i]
                if (w.active) out[w.output] = w.wsId
            }
            return out
        }
        niri._onLine(JSON.stringify({ WorkspaceActivated: { id: 11, focused: true } }))
        const niriActive = _niriByOutput()
        root._check(niriActive["DP-1"] === 2,
            "activating a niri workspace moves its own output to it")
        root._check(niriActive["HDMI-A-1"] === 1,
            "activating a niri workspace leaves the other output's active workspace alone")

        const niriCrossMove = niri.moveWorkspaceCommand(2, "HDMI-A-1", 90, "DP-1")
        root._check(niriCrossMove[0] === "sh"
                && niriCrossMove.join(" ").includes("move-window-to-monitor")
                && niriCrossMove.join(" ").includes("--window-id")
                && niriCrossMove[niriCrossMove.length - 2] === "HDMI-A-1"
                && niriCrossMove[niriCrossMove.length - 1] === "2",
            "a cross-output niri move resolves the workspace on the clicked monitor")
        const niriLocalMove = niri.moveWorkspaceCommand(2, "DP-1", 90, "DP-1")
        root._check(niriLocalMove[0] === "niri"
                && niriLocalMove.indexOf("--window-id") >= 0,
            "a same-output niri move addresses the original window directly")

        niri._onLine(JSON.stringify({ WorkspaceUrgencyChanged: { id: 20, urgent: true } }))
        const niriUrgent = niri.workspaces
        let urgentCount = 0
        let urgentOutput = ""
        for (let i = 0; i < niriUrgent.length; i++)
            if (niriUrgent[i].urgent) { urgentCount++; urgentOutput = niriUrgent[i].output }
        root._check(urgentCount === 1 && urgentOutput === "HDMI-A-1",
            "a niri urgency flag lands on the one workspace it names")

        niri._onLine(JSON.stringify({ WindowsChanged: { windows: [
            { id: 90, workspace_id: 11, app_id: "probe.app", title: "t", pid: 1 },
            { id: 91, workspace_id: 20, app_id: "probe.app", title: "u", pid: 1 }
        ]}}))
        niri._onLine(JSON.stringify({ WindowClosed: { id: 90 } }))
        const niriClosed = niri.workspaces
        let closedEmpty = false
        for (let i = 0; i < niriClosed.length; i++)
            if (niriClosed[i].output === "DP-1" && niriClosed[i].wsId === 2)
                closedEmpty = niriClosed[i].occupied === false
        root._check(closedEmpty,
            "closing the last niri window empties the workspace that held it")

        niri._onLine(JSON.stringify({ WindowFocusChanged: { id: 91 } }))
        const niriTops = niri.toplevels
        let focusedCount = 0
        for (let i = 0; i < niriTops.length; i++)
            if (niriTops[i].focused) focusedCount++
        root._check(focusedCount === 1,
            "niri focus lands on exactly one window")

        niri._onLine(JSON.stringify({ OverviewOpenedOrClosed: { is_open: true } }))
        const overviewOpened = niri.overviewActive
        niri._onLine(JSON.stringify({ OverviewOpenedOrClosed: { is_open: false } }))
        root._check(overviewOpened && !niri.overviewActive,
            "the niri overview flag follows the event both ways")

        niri.destroy()

        // nmcli -t escapes a colon inside a name; the VPN row is the only reader left
        const nmFields = Network._splitNmcliLine("home\\:vpn:vpn:activated")
        root._check(nmFields.length === 3 && nmFields[0] === "home:vpn"
                && nmFields[1] === "vpn" && nmFields[2] === "activated",
            "an escaped colon stays inside one nmcli field")
        const nmSlash = Network._splitNmcliLine("back\\\\slash:vpn")
        root._check(nmSlash.length === 2 && nmSlash[0] === "back\\slash",
            "an escaped backslash ends its own escape")
        const nmEmpty = Network._splitNmcliLine("a::b")
        root._check(nmEmpty.length === 3 && nmEmpty[1] === "",
            "an empty nmcli field is kept in place")

        const savedWeak = { active: false, known: true, signal: 20, ssid: "b" }
        const strangerStrong = { active: false, known: false, signal: 95, ssid: "a" }
        const joined = { active: true, known: false, signal: 10, ssid: "c" }
        root._check(Network._compareWifi(savedWeak, strangerStrong) < 0
                && Network._compareWifi(joined, savedWeak) < 0
                && Network._compareWifi(strangerStrong, savedWeak) > 0,
            "the Wi-Fi list ranks the connected network, then saved ones, then signal")

        const weakSavedAp = { connected: false, known: true, signalStrength: 0.3 }
        const strongUnknownAp = { connected: false, known: false, signalStrength: 0.9 }
        const connectedAp = { connected: true, known: false, signalStrength: 0.1 }
        root._check(Network._preferWifiNetwork(weakSavedAp, strongUnknownAp)
                && !Network._preferWifiNetwork(strongUnknownAp, weakSavedAp)
                && Network._preferWifiNetwork(connectedAp, weakSavedAp)
                && Network._preferWifiNetwork(
                    { connected: false, known: true, signalStrength: 0.8 }, weakSavedAp),
            "duplicate SSIDs choose connected, then saved, then strongest access point")

        const publishedWifiWas = Network._publishedWifiNetworks
        Network._publishedWifiNetworks = [{
            ssid: "probe", label: "Probe", glyph: "tier-2",
            secured: true, active: false, known: true
        }]
        const stableWifiModel = Network.wifiNetworks
        const equivalentWifiPublished = Network._publishWifiNetworks([{
            ssid: "probe", label: "Probe", glyph: "tier-2",
            secured: true, active: false, known: true
        }])
        root._check(!equivalentWifiPublished
                && Network.wifiNetworks === stableWifiModel,
            "unchanged visible Wi-Fi roles keep the published model identity")
        const changedWifiPublished = Network._publishWifiNetworks([{
            ssid: "probe", label: "Probe", glyph: "tier-3",
            secured: true, active: false, known: true
        }])
        root._check(changedWifiPublished
                && Network.wifiNetworks !== stableWifiModel,
            "a visible Wi-Fi tier change publishes a fresh model")
        Network._publishedWifiNetworks = publishedWifiWas

        const vpnStateWas = Network._vpnState
        Network._vpnState = ({ active: true, name: "stale probe VPN" })
        Network._vpnCandidateActive = true
        Network._vpnCandidateName = "stale probe VPN"
        Network._clearVpnState()
        root._check(!Network.hasVpn && Network.vpnName.length === 0
                && !Network._vpnCandidateActive
                && Network._vpnCandidateName.length === 0,
            "losing VPN detection clears both published and in-flight state")
        Network._vpnState = vpnStateWas

        const wheelKey = "probe-scroll"
        root._check(Scroll._processDelta(60, wheelKey, 120, 2, 0) === 0,
            "a half-notch wheel step emits nothing on its own")
        root._check(Scroll._processDelta(60, wheelKey, 120, 2, 0) === 1,
            "two half-notches accumulate into one step")
        root._check(Scroll._processDelta(600, wheelKey, 120, 2, 0) === 2,
            "one wheel burst emits at most the step ceiling")
        root._check(Scroll._processDelta(1, wheelKey, 120, 2, 0) === 0,
            "a capped wheel burst leaves no queued whole steps for the next movement")
        const remainderKey = "probe-scroll-remainder"
        root._check(Scroll._processDelta(660, remainderKey, 120, 2, 0) === 2
                && Scroll._processDelta(59, remainderKey, 120, 2, 0) === 0
                && Scroll._processDelta(1, remainderKey, 120, 2, 0) === 1,
            "a capped wheel burst retains its fractional notch")
        const negativeKey = "probe-scroll-negative"
        root._check(Scroll._processDelta(-660, negativeKey, 120, 2, 0) === -2
                && Scroll._processDelta(-59, negativeKey, 120, 2, 0) === 0
                && Scroll._processDelta(-1, negativeKey, 120, 2, 0) === -1,
            "negative wheel bursts discard excess whole steps and retain their fraction")
        const reverseKey = "probe-scroll-reverse"
        root._check(Scroll._processDelta(60, reverseKey, 60, 1, 0) === 1,
            "a touchpad can emit a complete notch with no remainder")
        Scroll._lastSteps[reverseKey] = Date.now()
        root._check(Scroll._processDelta(-60, reverseKey, 60, 1, 1000) === -1,
            "a touchpad direction reversal bypasses throttling even with no remainder")
        Scroll._lastSteps[reverseKey] = Date.now()
        root._check(Scroll._processDelta(20, reverseKey, 60, 1, 1000) === 0
                && Scroll._processDelta(40, reverseKey, 60, 1, 1000) === 1,
            "a touchpad reversal split across events bypasses the previous direction's throttle")
        const throttleKey = "probe-scroll-throttle"
        Scroll._lastSteps[throttleKey] = Date.now()
        root._check(Scroll._processDelta(180, throttleKey, 60, 1, 1000) === 0,
            "touchpad input respects the interval between steps")
        Scroll._lastSteps[throttleKey] = Date.now() - 2000
        root._check(Scroll._processDelta(1, throttleKey, 60, 1, 1000) === 1
                && Scroll._accums[throttleKey] === 1,
            "a throttled touchpad burst resumes with one step and no whole-step backlog")
        const notchUp = inverted => ({ angleDelta: { x: 0, y: 120 }, inverted: inverted })
        root._check(Scroll.processLevelWheel(notchUp(false), "probe-level-a") === 1
                && Scroll.processLevelWheel(notchUp(true), "probe-level-b") === -1
                && Scroll.processControlWheel(notchUp(true), "probe-level-c") === 1,
            "natural scrolling flips a level control but not content navigation")
        const pad = (x, y) => ({ angleDelta: { x: x, y: y }, pixelDelta: { x: x / 8, y: y / 8 },
            device: { type: PointerDevice.TouchPad } })
        let padSteps = 0
        for (let i = 0; i < 12; i++) padSteps += Scroll.processTrayWheel(pad(0, 12), "probe-tray-a").steps
        const trayNotch = Scroll.processTrayWheel(notchUp(false), "probe-tray-b")
        const trayLeft = Scroll.processTrayWheel({ angleDelta: { x: -120, y: 0 } }, "probe-tray-c")
        root._check(padSteps === 1 && trayNotch.steps === 1 && !trayNotch.horizontal
                && trayLeft.steps === -1 && trayLeft.horizontal,
            "a touchpad flick reaches a tray app as one step, not one call per event")

        SystemTools._tools = toolsWas
        SystemTools.packageFamily = familyWas
        SystemTools.ready = readyWas
        ShellSettings.updatesIncludeAur = includeAurWas

        const commitLines = []
        for (let i = 0; i < ShellUpdate.maxCommitDetail + 20; i++)
            commitLines.push("abcdef" + i + " " + "subject".repeat(100))
        const parsedCommits = ShellUpdate._parseCommits(commitLines.join("\n"))
        root._check(parsedCommits.length === ShellUpdate.maxCommitDetail,
            "shell update caps commit detail models")
        root._check(parsedCommits[0].subject.length === ShellUpdate.maxCommitSubjectChars,
            "shell update bounds commit subjects")
        const parsedKv = ShellUpdate._parseKv("__proto__=spoof\nsupported=1")
        root._check(Object.getPrototypeOf(parsedKv) === null && parsedKv.supported === "1",
            "shell update parses status into a prototype-safe map")
        ShellUpdate._parse("1\ntarget abc1234 v1.2.3 verified\nabc1234 signed release")
        root._check(ShellUpdate.targetVerified && ShellUpdate.targetTag === "v1.2.3",
            "shell update recognizes an explicitly verified release target")
        ShellUpdate._parseReleaseNotes("target v1.2.3\nAdded\tA **bounded** `summary`\nFixed\tA [bug](https://example.invalid)")
        root._check(ShellUpdate.releaseNotes.length === 2
                && ShellUpdate.releaseNotes[0].category === "Added"
                && ShellUpdate.releaseNotes[0].subject === "A bounded summary"
                && ShellUpdate.releaseNotes[1].subject === "A bug",
            "shell update parses categorized notes for the verified target")
        ShellUpdate._parseReleaseNotes("target v1.2.4\nAdded\tWrong release")
        root._check(ShellUpdate.releaseNotes.length === 0,
            "shell update rejects cached notes for another release")
        ShellUpdate._parseReleaseNotes("target v1.2.3\nForged\tUnknown category")
        root._check(ShellUpdate.releaseNotes.length === 0,
            "shell update rejects unknown release-note categories")
        ShellUpdate._parse("1\ntarget abc1234 v1.2.3\nabc1234 legacy update")
        root._check(!ShellUpdate.targetVerified,
            "shell update rejects legacy status without a verification marker")
        ShellUpdate._parse("7changes\ntarget abc1234 v1.2.3 verified extra\nabc1234 forged status")
        root._check(ShellUpdate.count === 0 && !ShellUpdate.targetVerified
                && ShellUpdate.targetTag.length === 0 && ShellUpdate._flagMalformed
                && ShellUpdate.statusText === "Status unavailable" && !ShellUpdate.upToDate,
            "shell update warns on partial counts and rejects inexact verification metadata")
        ShellUpdate._parse("100001\ntarget abc1234 v1.2.3 verified\nabc1234 oversized status")
        root._check(ShellUpdate.count === 0 && ShellUpdate._flagMalformed,
            "shell update warns on oversized cached pending counts")
        root._check(ShellUpdate._epochMsFrom("1234seconds") === 0
                && ShellUpdate._epochMsFrom("1234") === 1234000,
            "shell update accepts only whole epoch timestamps")
        const persistedErrorWas = ShellUpdate.persistedCheckError
        const persistedErrorMsWas = ShellUpdate.persistedCheckErrorMs
        const errorMalformedWas = ShellUpdate._errorMalformed
        ShellUpdate._parsePersistedError("1234\nfetch failed\ntry again")
        root._check(ShellUpdate.persistedCheckErrorMs === 1234000
                && ShellUpdate.persistedCheckError === "fetch failed try again"
                && !ShellUpdate._errorMalformed,
            "shell update safely parses persisted unattended failures")
        ShellUpdate._parsePersistedError("yesterday\nfetch failed")
        root._check(ShellUpdate.persistedCheckError.length === 0
                && ShellUpdate._errorMalformed,
            "shell update rejects malformed persisted failure state")
        const liveCheckErrorWas = ShellUpdate.lastCheckError
        const nowWas = ShellUpdate._nowMs
        ShellUpdate._parsePersistedError("1234\nfetch failed")
        ShellUpdate.lastCheckError = ""
        ShellUpdate._nowMs = 1234000 + 7200000
        root._check(ShellUpdate.checkErrorAge === "2 h ago",
            "a persisted update failure reports how long ago it happened")
        ShellUpdate.lastCheckError = "Update check failed"
        root._check(ShellUpdate.checkErrorAge === "",
            "a failure from this session is not stamped with the persisted age")
        ShellUpdate.lastCheckError = liveCheckErrorWas
        ShellUpdate._nowMs = nowWas
        ShellUpdate.persistedCheckError = persistedErrorWas
        ShellUpdate.persistedCheckErrorMs = persistedErrorMsWas
        ShellUpdate._errorMalformed = errorMalformedWas
        ShellUpdate._parse("")
        const checkedLoadedWas = ShellUpdate._checkedLoaded
        const flagLoadedWas = ShellUpdate._flagLoaded
        const flagReadErrorWas = ShellUpdate._flagReadError
        const flagMalformedWas = ShellUpdate._flagMalformed
        const checkedReadErrorWas = ShellUpdate._checkedReadError
        const errorLoadedWas = ShellUpdate._errorLoaded
        const errorReadErrorWas = ShellUpdate._errorReadError
        const lastCheckWas = ShellUpdate.lastCheckMs
        ShellUpdate._flagLoaded = false
        ShellUpdate._checkedLoaded = false
        ShellUpdate._errorLoaded = false
        ShellUpdate.lastCheckMs = 0
        root._check(ShellUpdate.statusText === "Reading status" && !ShellUpdate.upToDate,
            "shell update does not claim success before both status files load")
        ShellUpdate._flagLoaded = true
        ShellUpdate._checkedLoaded = true
        ShellUpdate._errorLoaded = true
        root._check(ShellUpdate.statusText === "Not checked yet" && !ShellUpdate.upToDate,
            "shell update does not call a missing check timestamp up to date")
        ShellUpdate._checkedReadError = true
        root._check(ShellUpdate.statusText === "Status unavailable" && !ShellUpdate.upToDate,
            "an unreadable update status cannot appear up to date")
        ShellUpdate.lastCheckMs = lastCheckWas
        ShellUpdate._flagLoaded = flagLoadedWas
        ShellUpdate._checkedLoaded = checkedLoadedWas
        ShellUpdate._flagReadError = flagReadErrorWas
        ShellUpdate._flagMalformed = flagMalformedWas
        ShellUpdate._checkedReadError = checkedReadErrorWas
        ShellUpdate._errorLoaded = errorLoadedWas
        ShellUpdate._errorReadError = errorReadErrorWas

        // a checkout demoted to development after an earlier managed check keeps its old
        // lastCheckMs forever (nothing clears it) — upToDate must not read that as current
        const installationModeWas = ShellUpdate.installationMode
        ShellUpdate._flagLoaded = true
        ShellUpdate._checkedLoaded = true
        ShellUpdate._errorLoaded = true
        ShellUpdate.lastCheckMs = 1234000
        ShellUpdate.installationMode = "development"
        root._check(!ShellUpdate.upToDate && ShellUpdate.statusDetail === "Managed with Git",
            "a stale check timestamp from before a checkout became development is not reported as up to date")
        ShellUpdate.installationMode = installationModeWas
        ShellUpdate.lastCheckMs = lastCheckWas
        ShellUpdate._flagLoaded = flagLoadedWas
        ShellUpdate._checkedLoaded = checkedLoadedWas
        ShellUpdate._errorLoaded = errorLoadedWas

        root._check(PowerProfiles.profileName(0) === "power-saver"
                && PowerProfiles.profileName(1) === "balanced"
                && PowerProfiles.profileName(2) === "performance"
                && PowerProfiles.profileName(99) === "",
            "power mode maps the native profile enum without parsing command output")
        root._check(JSON.stringify(PowerProfiles.cycleOrder(true, true))
                === JSON.stringify(["balanced", "performance", "power-saver"]),
            "power mode keeps the full native profile cycle when performance is available")
        root._check(JSON.stringify(PowerProfiles.cycleOrder(true, false))
                === JSON.stringify(["balanced", "power-saver"]),
            "power mode omits performance when the native service says it is unavailable")
        root._check(PowerProfiles.cycleOrder(false, true).length === 0,
            "power mode exposes no cycle before its service is available")
        root._check(PowerProfiles.labelFor("power-saver") === "Power Saver"
                && PowerProfiles.labelFor("nonsense") === ""
                && PowerProfiles.glyphFor("performance")
                    !== PowerProfiles.glyphFor("balanced"),
            "every power profile names and marks itself the same way in list and row")
        const fullOrder = PowerProfiles.cycleOrder(true, true)
        root._check(PowerProfiles.nextProfile("balanced", fullOrder) === "performance"
                && PowerProfiles.nextProfile("power-saver", fullOrder) === "balanced",
            "cycling a power mode names the profile it moves to, wrapping at the end")
        root._check(PowerProfiles.nextProfile("performance",
                    PowerProfiles.cycleOrder(true, false)) === ""
                && PowerProfiles.nextProfile("balanced", []) === "",
            "a power mode outside the offered cycle names no successor")

        // _onLine is replayed above; these reach the transforms behind it directly, where
        // the rebuild-don't-mutate contract and the empty cases are visible
        const wsRows = [
            { id: 1, output: "DP-1", is_active: true,  is_focused: true },
            { id: 2, output: "DP-1", is_active: false, is_focused: false },
            { id: 3, output: "HDMI-A-1", is_active: true, is_focused: false }
        ]
        const wsActivated = NiriEvents.workspacesWithActivated(wsRows, 2, true)
        const wsChurn = wsRows.map(w => Object.assign({}, w, { name: "renamed" }))
        root._check(NiriEvents.focusedWorkspaceChangeOutput(wsRows, wsChurn) === null
                && NiriEvents.focusedWorkspaceChangeOutput(wsRows,
                    wsActivated.workspaces) === "DP-1",
            "niri workspace-list churn emits activation only when focused workspace changes")
        root._check(wsActivated.output === "DP-1"
                && !wsActivated.workspaces[0].is_active
                && wsActivated.workspaces[1].is_active
                && wsActivated.workspaces[2].is_active,
            "activating a niri workspace deactivates only its own output")
        root._check(!wsActivated.workspaces[0].is_focused
                && wsActivated.workspaces[1].is_focused
                && !wsActivated.workspaces[2].is_focused,
            "a focused niri workspace activation moves focus across every output")
        root._check(wsRows[0].is_active === true && wsRows[1].is_active === false,
            "a niri workspace transform leaves the list it was given untouched")
        root._check(NiriEvents.workspacesWithActivated(wsRows, 99, false).output === "",
            "activating a niri workspace that is gone names no output")

        const wsUrgent = NiriEvents.workspacesWithUrgency(wsRows, 2, true)
        root._check(wsUrgent[1].is_urgent === true && wsUrgent[0].is_urgent === undefined
                && wsRows[1].is_urgent === undefined,
            "niri urgency marks one workspace without rewriting the others")

        const winRows = [
            { id: 10, title: "one", is_focused: true },
            { id: 11, title: "two", is_focused: false }
        ]
        const winOpened = NiriEvents.windowsWithUpsert(winRows, { id: 12, title: "new", is_focused: true })
        root._check(winOpened.length === 3 && winOpened[2].id === 12
                && !winOpened[0].is_focused && !winOpened[1].is_focused,
            "a focused niri window arriving unfocuses every window already open")
        const winReplaced = NiriEvents.windowsWithUpsert(winRows, { id: 11, title: "again", is_focused: false })
        root._check(winReplaced.length === 2 && winReplaced[1].title === "again"
                && winReplaced[0].is_focused === true,
            "a niri window that is already open is replaced in place, focus untouched")

        root._check(NiriEvents.windowsWithout(winRows, 10).length === 1
                && NiriEvents.windowsWithout(winRows, 10)[0].id === 11
                && winRows.length === 2,
            "closing a niri window drops only that row")
        const winFocused = NiriEvents.windowsWithFocus(winRows, 11)
        root._check(!winFocused[0].is_focused && winFocused[1].is_focused,
            "a niri focus change leaves exactly one window focused")
        const winStamped = NiriEvents.windowsWithFocusStamp(winRows, 11, { secs: 7, nanos: 3 })
        root._check(winStamped[1].focus_timestamp.secs === 7
                && winStamped[0].focus_timestamp === undefined,
            "a niri focus timestamp lands on the window it names")
        root._check(NiriEvents.indexOfWindow(winRows, 11) === 1
                && NiriEvents.indexOfWindow(winRows, 99) === -1
                && NiriEvents.indexOfWindow([null, { id: 5 }], 5) === 1,
            "a niri window lookup skips holes and reports a miss")

        // qt reads the 12-hour clock off the whole format string: an hour formatted on its
        // own still comes back 0-23 and lands beside a PM that contradicts it
        const clock12Was = ShellSettings.clock12h
        const oneAm    = new Date(2026, 0, 2, 1, 45)
        const onePm    = new Date(2026, 0, 2, 13, 45)
        const noon     = new Date(2026, 0, 2, 12, 5)
        const midnight = new Date(2026, 0, 2, 0, 5)
        ShellSettings.clock12h = false
        root._check(DateTime.clockText(onePm) === Qt.formatDateTime(onePm, "HH:mm")
                && DateTime.clockSuffix(onePm).length === 0,
            "the 24-hour clock reads straight through with no suffix")
        ShellSettings.clock12h = true
        root._check(DateTime.clockHour(onePm) === DateTime.clockHour(oneAm)
                && DateTime.clockHour(onePm) !== Qt.formatDateTime(onePm, "HH"),
            "the 12-hour clock counts the afternoon from one, not thirteen")
        root._check(DateTime.clockHour(midnight) === DateTime.clockHour(noon)
                && DateTime.clockSuffix(midnight) !== DateTime.clockSuffix(noon),
            "midnight and noon share an hour and split on the suffix")
        root._check(DateTime.clockText(onePm).indexOf(DateTime.clockSuffix(onePm)) > 0,
            "the composed clock text carries the suffix")
        root._check(DateTime.clockNeeded(true, false, false, false, false)
                && !DateTime.clockNeeded(true, true, false, false, false)
                && DateTime.clockNeeded(true, true, true, false, false)
                && DateTime.clockNeeded(false, true, false, false, true),
            "the clock sleeps behind overview unless a background consumer needs it")
        ShellSettings.clock12h = clock12Was

        // a minute tick armed before suspend fires late after wake; catching up re-reads the wall clock
        DateTime._lastMinute = "190001010000"
        DateTime.catchUp()
        root._check(DateTime._lastMinute === Qt.formatDateTime(new Date(), "yyyyMMddHHmm")
                && !DateTime._resync,
            "a stale clock catches up to the wall clock on a wake-time event")

        // auto is a mode, not a value: it must never consume the hand-picked temperature
        const autoWas = ShellSettings.nightLightAuto
        const tempWas = ShellSettings.nightLightTemp
        ShellSettings.nightLightAuto = false
        ShellSettings.nightLightTemp = 3400
        root._check(NightLight.temperature === 3400,
            "night light follows the manual temperature with auto off")
        ShellSettings.nightLightAuto = true
        root._check(NightLight.temperature === NightLight.suggestedTemp,
            "night light follows the sun with auto on")
        root._check(ShellSettings.nightLightTemp === 3400,
            "night light auto does not overwrite the saved manual temperature")
        ShellSettings.nightLightAuto = false
        root._check(NightLight.temperature === 3400,
            "night light restores the manual temperature when auto is turned off")
        ShellSettings.nightLightTemp = tempWas
        ShellSettings.nightLightAuto = autoWas

        const nightOnWas = ShellSettings.nightLightOn
        const nightProviderWas = ShellSettings.nightLightProvider
        const nightToolsWas = SystemTools._tools
        const nightReadyWas = SystemTools.ready
        SystemTools._tools = { wlsunset: true, pgrep: true, pkill: true }
        SystemTools.ready = true
        ShellSettings.nightLightProvider = "wlsunset"
        NightLight.toggle()
        root._check(NightLight.toolAvailable && NightLight._sandboxed && !NightLight.enabled
                && ShellSettings.nightLightOn === nightOnWas
                && NightLight._runningTool === "" && !NightLight._probedOnce,
            "a test copy of the shell never adopts, starts or stops the live night light")
        ShellSettings.nightLightOn = nightOnWas
        ShellSettings.nightLightProvider = nightProviderWas
        SystemTools._tools = nightToolsWas
        SystemTools.ready = nightReadyWas

        const geoResolvedWas = NightLight._geoResolved
        const autoLatWas = NightLight._autoLat
        const autoLonWas = NightLight._autoLon
        root._check(NightLight._parseCoord("+5657+02406")
                && Math.abs(NightLight._autoLat - 56.95) < 0.0001
                && Math.abs(NightLight._autoLon - 24.1) < 0.0001,
            "night light parses a valid zone-table coordinate")
        const validLat = NightLight._autoLat
        const validLon = NightLight._autoLon
        root._check(!NightLight._parseCoord("+9060+02406")
                && NightLight._autoLat === validLat && NightLight._autoLon === validLon,
            "night light rejects invalid coordinate minutes without replacing its location")
        root._check(!NightLight._parseCoord("+9001+18000")
                && !NightLight._parseCoord("+9000+18001"),
            "night light rejects coordinates beyond the latitude and longitude poles")
        root._check(NightLight.offStatusAt(NightLight.sunsetHour + 0.5, -5).startsWith("Sunrise ")
                && NightLight.offStatusAt(NightLight.sunriseHour - 0.5, -5).startsWith("Sunrise ")
                && NightLight.offStatusAt(NightLight.sunsetHour - 0.25, 3).startsWith("Sunset ")
                && NightLight.offStatusAt(NightLight._solarNoon, 40) === "",
            "night light off names the next sun event, sunrise once the sun has set")
        const vitals = Qt.createComponent("modules/menu/VitalsStrip.qml").createObject(root, { active: false })
        root._check(vitals !== null
                && vitals.sizeText(5 * 1048576) === "5.0G"
                && vitals.sizeText(5.6 * 1048576) === "5.6G"
                && vitals.sizeText(786 * 1048576) === "786G"
                && vitals.sizeText(1.2 * 1073741824) === "1.2T"
                && vitals.sizeText(0) === "" && vitals.sizeText(NaN) === "",
            "the vitals strip writes sizes in binary units with one decimal below ten")
        if (vitals) vitals.destroy()
        root._check(NightLight._probeState(0, false, false) === 1
                && NightLight._probeState(1, false, false) === 0
                && NightLight._probeState(1, false, true) === 1
                && NightLight._probeState(0, true, true) === -1
                && NightLight._probeState(2, false, false) === -1
                && NightLight._probeState(-1, false, false) === -1,
            "night light distinguishes an external daemon, no match, and a failed state probe")
        root._check(NightLight._temperatureUpdateSucceeded(0, false, "ok\n")
                && !NightLight._temperatureUpdateSucceeded(0, false, "unknown request\n")
                && !NightLight._temperatureUpdateSucceeded(1, false, "ok\n")
                && !NightLight._temperatureUpdateSucceeded(0, true, "ok\n"),
            "night light accepts only a confirmed live temperature update")
        NightLight._geoResolved = geoResolvedWas
        NightLight._autoLat = autoLatWas
        NightLight._autoLon = autoLonWas

        const cpuTempWas = CpuTemp.temp
        const cpuHotWas = CpuTemp.hot
        const cpuCriticalWas = CpuTemp.critical
        const cpuHotCountWas = CpuTemp._hotCount
        const cpuCriticalCountWas = CpuTemp._criticalCount
        CpuTemp.temp = 104
        CpuTemp.hot = true
        CpuTemp.critical = true
        CpuTemp._hotCount = 3
        CpuTemp._criticalCount = 3
        root._check(!CpuTemp._applySensorText("not-a-temperature")
                && CpuTemp.temp === 0 && !CpuTemp.hot && !CpuTemp.critical
                && CpuTemp._hotCount === 0 && CpuTemp._criticalCount === 0,
            "an invalid CPU sensor read retires its stale warning state")
        CpuTemp.temp = cpuTempWas
        CpuTemp.hot = cpuHotWas
        CpuTemp.critical = cpuCriticalWas
        CpuTemp._hotCount = cpuHotCountWas
        CpuTemp._criticalCount = cpuCriticalCountWas

        const cpuDetectGenerationWas = CpuTemp._detectGeneration
        CpuTemp._detectGeneration = 41
        root._check(CpuTemp._detectionIsCurrent(41)
                && !CpuTemp._detectionIsCurrent(40),
            "a canceled CPU sensor discovery cannot publish into a newer request")
        CpuTemp._detectGeneration = cpuDetectGenerationWas

        root._check(Battery.normalizedPercent(0.64) === 64
                && Battery.normalizedPercent(1) === 100
                && Battery.normalizedPercent(1.4) === 100
                && Battery.normalizedPercent(-1) === 0
                && Battery.normalizedPercent(NaN) === 0,
            "battery percentage reads quickshell's 0-1 charge and stays bounded")
        root._check(Battery.statusFor(true, Up.UPowerDeviceState.PendingCharge, false, false) === "not charging"
                && Battery.statusFor(true, Up.UPowerDeviceState.Discharging, false, false) === "discharging"
                && Battery.statusFor(true, Up.UPowerDeviceState.Unknown, false, false) === "on AC",
            "AC power alone does not claim the battery is charging")
        root._check(Battery.statusFor(true, Up.UPowerDeviceState.FullyCharged, false, false) === "charged"
                && Battery.statusFor(false, Up.UPowerDeviceState.Charging, false, false) === "",
            "battery status respects fully charged and absent devices")
        root._check(Battery.timeText(25, false) === "1m"
                && Battery.timeText(3601, true) === "+ 1h 1m"
                && Battery.timeText(Infinity, true) === "" && Battery.timeText(-1, false) === "",
            "battery estimates round up to a useful minute and reject invalid times")
        root._check(SystemAlerts.batteryWarningLevel(true, true) === "critical"
                && SystemAlerts.batteryWarningLevel(true, false) === "low"
                && SystemAlerts.batteryWarningLevel(false, false) === "",
            "a critical battery reading suppresses the duplicate low-battery alert")
        const dropout = SystemAlerts.batteryRearmState(false, false, 0, 20, 10, true, true)
        const plugged = SystemAlerts.batteryRearmState(true, false, 0, 20, 10, true, true)
        root._check(dropout.low && dropout.critical
                && !plugged.low && !plugged.critical,
            "a battery backend dropout keeps warning latches until a real plug reading")

        // the pulse only drives a hidden pill, an off underline glow and a shut menu here
        const battShowWas = ShellSettings.barShowBattery
        const battGlowMasterWas = ShellSettings.underlineGlow
        const battGlowWas = ShellSettings.underlineBattGlow
        const battMenuWas = MenuState.open
        MenuState.open = false
        ShellSettings.barShowBattery = false
        ShellSettings.underlineGlow = false
        ShellSettings.underlineBattGlow = false
        root._check(!Battery._alertWatched,
            "the battery alert rests when no surface draws it")
        ShellSettings.underlineBattGlow = true
        root._check(!Battery._alertWatched,
            "the battery glow toggle alone, without its master, does not keep the alert watched")
        ShellSettings.underlineGlow = true
        root._check(Battery._alertWatched,
            "the underline glow master plus its own toggle keeps the battery alert watched")
        ShellSettings.barShowBattery = battShowWas
        ShellSettings.underlineGlow = battGlowMasterWas
        ShellSettings.underlineBattGlow = battGlowWas
        MenuState.open = battMenuWas


        // the inner shell keeps timeout alive after a hook entrypoint backgrounds work and exits
        const hookArgv = ["/hooks/notification", "arg"]
        const wrapped = Hooks._wrapArgv(hookArgv)
        root._check(wrapped[0] === "timeout" && wrapped[1] === "--kill-after=2"
                && wrapped[2] === "30" && wrapped[3] === "bash"
                && wrapped[4] === "-c" && wrapped[5] === Hooks._groupWaitScript
                && wrapped[6] === "silere-hook"
                && wrapped[7] === "/hooks/notification" && wrapped[8] === "arg",
            "a hook runs under the wrapper that signals its whole process group")
        // SystemTools answers false until its scan lands, so the flag decides per run
        root._check(JSON.stringify(Hooks._containedArgv(hookArgv))
                === JSON.stringify(Hooks._contained ? wrapped : hookArgv),
            "a hook is wrapped only where the wrapper is actually available")
        root._check(Hooks._contained
                ? Hooks._runner0.timeoutMs > Hooks.maxRuntimeMs + Hooks._containGraceMs
                : Hooks._runner0.timeoutMs === Hooks.maxRuntimeMs,
            "the in-shell hook timer backstops the wrapper instead of racing it")

        // the lua config framework replaces the plain dispatchers, so the two
        // dispatch forms are the difference between switching and doing nothing
        const luaWas = HyprDispatch.useLua
        HyprDispatch.useLua = false
        root._check(HyprDispatch._text("workspace", 3) === "workspace 3",
            "dispatch builds the plain hyprland form")
        HyprDispatch.useLua = true
        root._check(HyprDispatch._text("workspace", 3)
                === "hl.dsp.focus({ workspace = 3 })",
            "dispatch builds the lua form for a workspace switch")
        root._check(HyprDispatch._text("focusmonitor", "DP-3")
                === "hl.dsp.focus({ monitor = \"DP-3\" })",
            "dispatch quotes a monitor name in the lua form")
        root._check(HyprDispatch._text("togglefloating", "") === "togglefloating",
            "dispatch passes an unmapped dispatcher through untouched")
        root._check(HyprDispatch.exitCommand()[4] === "hl.dsp.exit()",
            "a Lua config logs out with the Lua exit dispatcher")
        HyprDispatch.useLua = false
        root._check(HyprDispatch.exitCommand()[4] === "exit",
            "a classic config logs out with the exit dispatcher")
        HyprDispatch.useLua = luaWas

        const spacing = ShellSettings.schemaFor("barSpacing")
        root._check(spacing !== null && spacing.t === "int"
                && spacing.min === 4 && spacing.max === 24,
            "settings expose a row's schema by key")
        root._check(ShellSettings.schemaFor("noSuchSetting") === null,
            "settings reject an unknown schema key")
        root._check(ShellSettings.schemaFor("barRadius").sec === "surface",
            "roundness is attributed to the one page that carries its row")
        const spacingWas = ShellSettings.barSpacing
        ShellSettings.setValue("barSpacing", 999)
        root._check(ShellSettings.barSpacing === 24,
            "a key-bound row clamps to the schema maximum")
        ShellSettings.setValue("barSpacing", -5)
        root._check(ShellSettings.barSpacing === 4,
            "a key-bound row clamps to the schema minimum")
        ShellSettings.setValue("noSuchSetting", 1)

        // the tray gap once grew wider than the widget gap it sits inside, at both
        // ends of the range; each formula was fine alone, only the ordering broke
        let gapOrderHolds = true
        let gapSaturates = true
        let lastCompactGap = -1
        for (let s = spacing.min; s <= spacing.max; s++) {
            ShellSettings.setValue("barSpacing", s)
            for (let ci = 0; ci < 2; ci++) {
                const compact = ci === 0
                const gap = Metrics.widgetGapFor(compact)
                if (!(gap <= Metrics.titleGapFor(compact)
                        && Metrics.titleGapFor(compact) <= Metrics.dividerSpanFor(compact)))
                    gapOrderHolds = false
            }
            const compactGap = Metrics.widgetGapFor(true)
            if (compactGap < lastCompactGap) gapSaturates = false
            lastCompactGap = compactGap
        }
        root._check(gapOrderHolds,
            "bar spacing keeps widget gap <= title gap <= divider span at every setting")
        root._check(gapSaturates && Metrics.widgetGapFor(true) > 0,
            "compact widget gap never decreases as spacing increases")
        ShellSettings.barSpacing = spacingWas

        const originalLimit = ShellSettings.notifHistoryLimit
        ShellSettings._coerce({ k: "notifHistoryLimit", t: "int", min: 5, max: 100 }, 999)
        root._check(ShellSettings.notifHistoryLimit === 100,
            "settings clamp history limit high")
        ShellSettings._coerce({ k: "notifHistoryLimit", t: "int", min: 5, max: 100 }, -4)
        root._check(ShellSettings.notifHistoryLimit === 5,
            "settings clamp history limit low")
        ShellSettings.notifHistoryLimit = originalLimit
        const residue = ShellSettings._coerced({ k: "barLineStrength", t: "real", min: 0.5, max: 3 }, 1.9000000000000001)
        root._check(residue.ok && String(residue.value) === "1.9",
            "a saved real drops float residue on load")

        // the IPC surface reports failure from the same coercion the file load uses,
        // so a key added to the schema is scriptable without touching the handler
        const toneWas = ShellSettings.baseTone
        const timeoutWas = ShellSettings.osdTimeout
        root._check(ShellSettings.setValue("osdTimeout", 3000) === true,
            "a valid write reports that it applied")
        root._check(ShellSettings.setValue("osdTimeout", 999999) === true
                && ShellSettings.osdTimeout === 10000,
            "a clamped write still reports that it applied")
        root._check(ShellSettings.setValue("osdTimeout", "not a number") === false,
            "a non-numeric write to an int key reports that it did not apply")
        root._check(ShellSettings.setValue("baseTone", "banana") === false
                && ShellSettings.baseTone === toneWas,
            "an unknown enum value neither applies nor claims to")
        root._check(ShellSettings.setValue("noSuchSetting", 1) === false,
            "a write to an unknown key reports that it did not apply")
        ShellSettings.baseTone = toneWas
        ShellSettings.osdTimeout = timeoutWas

        root._check(ShellSettings._ipcKey("BARSPACING") === "barSpacing"
                && ShellSettings._ipcKey(" osdTimeout ") === "osdTimeout"
                && ShellSettings._ipcKey("noSuchSetting") === "noSuchSetting",
            "settings IPC trims hand-typed keys and folds known capitalization")
        const ipcSpacingWas = ShellSettings.barSpacing
        root._check(ShellSettings._ipcSet("BARSPACING", "999") === "24"
                && ShellSettings.barSpacing === 24,
            "a mixed-case IPC write resolves and reports its clamped value")
        ShellSettings.barSpacing = ipcSpacingWas

        const ipcLeftWas = ShellSettings.barWidgetOrderLeft
        const ipcCenterWas = ShellSettings.barWidgetOrderCenter
        const ipcRightWas = ShellSettings.barWidgetOrderRight
        const ipcOrderResult = ShellSettings._ipcSet(
            "BARWIDGETORDERCENTER", "clock,clock")
        const ipcOrder = ShellSettings.barWidgetOrderLeftKeys.concat(
            ShellSettings.barWidgetOrderCenterKeys,
            ShellSettings.barWidgetOrderRightKeys)
        root._check(ipcOrderResult === "clock,windowTitle"
                && ShellSettings.barWidgetLocate("clock").zone === "center",
            "a widget-order IPC write moves a key and restores center-default additions")
        root._check(ipcOrder.length === ShellSettings.barWidgetKeys.length
                && new Set(ipcOrder).size === ipcOrder.length,
            "a widget-order IPC write restores missing keys and removes duplicates")
        ShellSettings.setBarWidgetLayout(ipcLeftWas, ipcCenterWas, ipcRightWas)

        const trayHiddenWas = ShellSettings.trayHidden
        ShellSettings.trayHidden = ""
        ShellSettings.setTrayItemHidden("vicinae", true)
        ShellSettings.setTrayItemHidden("chrome_status,1", true)
        root._check(ShellSettings.trayItemHidden("chrome_status,1")
                && ShellSettings.trayHiddenIds.length === 2
                && ShellSettings.setValue("trayHidden", ShellSettings.trayHidden),
            "a hidden tray id holding a comma round-trips and passes the schema")
        ShellSettings.setTrayItemHidden("vicinae", false)
        root._check(!ShellSettings.trayItemHidden("vicinae")
                && ShellSettings.trayHiddenIds.length === 1,
            "showing a tray item removes only that id")
        ShellSettings.trayHidden = trayHiddenWas

        root._check(ShellSettings.constraintOf("barShowClock") === "true|false",
            "a bool key states its constraint")
        root._check(ShellSettings.constraintOf("barSpacing") === "4..24",
            "an int key states its range")
        root._check(ShellSettings.constraintOf("barGap") === "0..24 in steps of 4",
            "a stepped int key states its step")
        root._check(ShellSettings.constraintOf("baseTone") === "black|charcoal|graphite",
            "an enum key states its vocabulary")
        root._check(ShellSettings.constraintOf("noSuchSetting") === "",
            "an unknown key states no constraint")

        root._check(Hooks.events.indexOf("theme-changed") >= 0
                && Hooks.events.indexOf("../../evil") < 0,
            "hooks run only the event names they publish")
        root._check(!Hooks.has("theme-changed"),
            "a hook with no executable file is never reported active")
        Hooks.fire("theme-changed", ["#000000"])
        Hooks.fire("no-such-event", [])
        root._check(Hooks._runTimes.length === 0,
            "an unset hook spends no run budget rather than spawning")
        let hookRunsAllowed = 0
        for (let i = 0; i < Hooks.maxRunsPerSecond + 5; i++)
            if (Hooks._budgetAllows()) hookRunsAllowed++
        root._check(hookRunsAllowed === Hooks.maxRunsPerSecond,
            "an event storm stops at " + Hooks.maxRunsPerSecond + " hook runs a second")
        Hooks._runTimes = []

        const supervised = supervisedProcessFactory.createObject(root, {
            superviseWhen: false,
            _gaveUp: true,
            _cooldown: true,
            _restartCount: 4
        })
        supervised.retry()
        root._check(!supervised.gaveUp && !supervised._cooldown
                && supervised._restartCount === 0 && !supervised.running,
            "a retired supervised process can retry from a clean backoff state")
        supervised.destroy()

        NotifWatch.conflict = "stale-daemon"
        NotifWatch.recheck()
        root._check(NotifWatch.conflict === "",
            "a notification-owner recheck clears stale conflict state immediately")
        root._check(NotifWatch._sandboxed && !NotifWatch._checked,
            "a sandboxed shell does not report the desktop notification owner as a conflict")

        const hues = [0, 30, 90, 150, 210, 270, 330]
        for (let i = 0; i < hues.length; i++) {
            const expected = hues[i]
            const colour = Theme.lchColor(70.8, 38, expected)
            root._check(colour.r >= 0 && colour.r <= 1
                    && colour.g >= 0 && colour.g <= 1
                    && colour.b >= 0 && colour.b <= 1,
                "LCh colour stays in sRGB at hue " + expected)
            const measured = Theme.lchOf(colour)
            root._check(isFinite(measured.L) && isFinite(measured.C) && isFinite(measured.h),
                "LCh round trip stays finite at hue " + expected)
            root._check(root._hueDistance(measured.h, expected) < 1.0,
                "LCh gamut mapping preserves hue " + expected)
        }

        let presetLSum = 0
        for (let i = 0; i < Theme.neutralAccentPresets.length; i++)
            presetLSum += Theme.lchOf(Theme.neutralAccentPresets[i].color).L
        root._check(Math.abs(Theme._accentPresetL
                - presetLSum / Theme.neutralAccentPresets.length) < 0.5,
            "the balance target tracks the lightness the accent presets are solved at")

        const balanceCases = ["#b9c3ff", "#ff5c1a", "#1b2a6b", "#39ff14", "#ffd6e7"]
        for (let i = 0; i < balanceCases.length; i++) {
            const source = Theme.lchOf(balanceCases[i])
            const balanced = Theme.lchOf(Theme.balancedAccent(balanceCases[i]))
            root._check(Math.abs(balanced.L - Theme._accentPresetL) < 0.5,
                "a balanced accent lands on the preset lightness: " + balanceCases[i])
            root._check(root._hueDistance(balanced.h, source.h) < 1.0,
                "balancing an accent keeps its hue: " + balanceCases[i])
            root._check(balanced.C <= 38.5 && balanced.C >= 19.5,
                "a balanced accent carries preset chroma: " + balanceCases[i])
        }

        const balancedOnce = Theme.balancedAccent("#ff5c1a")
        const balancedTwice = Theme.balancedAccent(balancedOnce)
        root._check(Math.abs(Theme.lchOf(balancedOnce).L - Theme.lchOf(balancedTwice).L) < 0.05
                && Math.abs(Theme.lchOf(balancedOnce).C - Theme.lchOf(balancedTwice).C) < 0.05,
            "balancing an already balanced accent changes nothing")

        const greyAccent = Theme.lchOf("#8a8a8a")
        const greyBalanced = Theme.lchOf(Theme.balancedAccent("#8a8a8a"))
        root._check(greyAccent.C < 4 && greyBalanced.C < 4
                && Math.abs(greyBalanced.L - greyAccent.L) < 0.001,
            "a palette with no accent hue is left alone rather than invented")

        const accentBalanceWas = ShellSettings.matugenAccentBalance
        const sampleAccent = Qt.color("#ff5c1a")
        ShellSettings.matugenAccentBalance = false
        const unbalancedSource = Theme.sourcedAccent(sampleAccent)
        root._check(Math.abs(unbalancedSource.r - sampleAccent.r) < 0.000001
                && Math.abs(unbalancedSource.g - sampleAccent.g) < 0.000001
                && Math.abs(unbalancedSource.b - sampleAccent.b) < 0.000001,
            "wallpaper accent swatches keep the source color when balance is off")
        ShellSettings.matugenAccentBalance = true
        const balancedSource = Theme.sourcedAccent(sampleAccent)
        root._check(Math.abs(balancedSource.r - balancedOnce.r) < 0.000001
                && Math.abs(balancedSource.g - balancedOnce.g) < 0.000001
                && Math.abs(balancedSource.b - balancedOnce.b) < 0.000001,
            "wallpaper accent swatches use the applied color when balance is on")
        ShellSettings.matugenAccentBalance = accentBalanceWas

        root._check(Network._linkPriority(true, true) > Network._linkPriority(false, undefined)
                && Network._linkPriority(true, undefined) > Network._linkPriority(false, undefined),
            "a wired link outranks Wi-Fi, and an unreported link counts as up")
        root._check(Network._linkPriority(false, undefined) > Network._linkPriority(true, false),
            "Wi-Fi outranks a wired device with no carrier")

        const keptOff = QuickActionsState._airplaneRestore(true, true, false)
        root._check(keptOff.wifi && !keptOff.bt,
            "leaving airplane mode restores only the radios that were on")
        const nothingHeld = QuickActionsState._airplaneRestore(false, false, false)
        root._check(nothingHeld.wifi && nothingHeld.bt,
            "leaving airplane mode with nothing latched restores both radios")

        CalendarState.anchorSource = null
        CalendarState.anchorX = 640
        root._check(CalendarState.effectiveAnchorX === 640,
            "an anchorless calendar open falls back to the published anchor x")
        QuickActionsState.anchorSource = null
        QuickActionsState.anchorX = 512
        root._check(QuickActionsState.effectiveAnchorX === 512,
            "an anchorless quick actions open falls back to the published anchor x")

        Notifications._seen  = { "41": true, "42": true }
        Notifications._times = { "41": 1000, "42": 2000 }
        Notifications._forgetTrimmed(["41"])
        root._check(Notifications._seen["41"] === undefined
                && Notifications._times["41"] === undefined
                && Notifications._seen["42"] === true
                && Notifications._times["42"] === 2000,
            "a notification trimmed out of history drops its seen and time entries")

        Notifications._seen  = { "51": true, "52": true }
        Notifications._times = { "51": 1000, "52": 2000 }
        Notifications._updateTimes = { "51": 1100, "52": 2100 }
        const listBeforePrune = Notifications.list
        Notifications.list = [{ notification: { id: 51 }, id: 51, time: 1000 }]
        const serverWasSettled = Notifications._serverSettled
        Notifications._serverSettled = false
        Notifications._pruneOrphanState()
        root._check(Notifications._seen["52"] === true && Notifications._times["52"] === 2000,
            "pruning waits until a reload has handed the kept notifications back")
        Notifications._serverSettled = true
        Notifications._pruneOrphanState()
        Notifications._serverSettled = serverWasSettled
        Notifications.list = listBeforePrune
        root._check(Notifications._seen["51"] === true
                && Notifications._times["51"] === 1000
                && Notifications._updateTimes["51"] === 1100,
            "reload pruning preserves state for a notification the server still tracks")
        root._check(Notifications._seen["52"] === undefined
                && Notifications._times["52"] === undefined
                && Notifications._updateTimes["52"] === undefined,
            "state for ids neither history nor the server holds is pruned")

        const kept = keptNotificationFactory.createObject(root, { id: 61 })
        Notifications._times = { "61": 4200 }
        let shownDuringAdopt = 0
        const countShown = () => shownDuringAdopt++
        Notifications.notificationShown.connect(countShown)
        Notifications._adoptKept(kept)
        Notifications.notificationShown.disconnect(countShown)
        const adopted = Notifications.list.find(e => e.id === 61)
        root._check(adopted && adopted.time === 4200 && kept.tracked
                && Notifications._times["61"] === 4200 && shownDuringAdopt === 0,
            "a notification kept across a reload keeps its age and replays no arrival")
        Notifications._updateTimes["61"] = 1
        kept.body = "progress 50%"
        root._check(Notifications.updateTimeFor(61) > 1,
            "an in-place update to a live notification restarts its card timestamp")
        Notifications.list = Notifications.list.filter(e => e.id !== 61)
        Notifications._forgetState(61)
        kept.destroy()

        const liveNotification = { id: 53, tracked: true }
        Notifications.list = [{
            notification: liveNotification, id: 53, time: 2300
        }]
        const liveList = Notifications.list
        const updateTimes = Notifications._updateTimes
        Notifications._recordUpdateTime(53, 2400)
        const sameObjectIsNew = Notifications._upsertActiveNotification(
            liveNotification, 2400)
        root._check(!sameObjectIsNew && Notifications.list === liveList,
            "an in-place notification update keeps the active list stable")
        root._check(Notifications._updateTimes === updateTimes
                && Notifications.updateTimeFor(53) === 2400,
            "a notification update records its card timestamp without cloning the map")

        const replacementNotification = { id: 53, tracked: true, transient: false,
            appName: "Probe", summary: "Replacement", body: "", urgency: 1,
            appIcon: "", desktopEntry: "" }
        const replacementIsNew = Notifications._upsertActiveNotification(
            replacementNotification, 2500)
        root._check(replacementIsNew
                && Notifications.list !== liveList
                && Notifications.list[0].notification === replacementNotification
                && Notifications.list[0].time === 2300
                && !liveNotification.tracked,
            "a replacement notification still retires the old object and keeps its age")
        Notifications.clearHistory()
        Notifications._seen = { "53": true }
        Notifications._times = { "53": 2300 }
        Notifications._updateTimes = { "53": 2500 }
        const replacementList = Notifications.list
        Notifications._onClosed(53, liveNotification)
        Notifications._onClosed(53, liveNotification)
        Notifications._onClosed(53, { id: 53 })
        root._check(Notifications.list === replacementList
                && Notifications._seen["53"] === true
                && Notifications._times["53"] === 2300
                && Notifications._updateTimes["53"] === 2500
                && Notifications.historyCount === 0,
            "late, duplicate and unknown closes cannot retire a replacement notification or its state")
        Notifications._prependHistory({
            id: 53, appName: "Probe", appIcon: "", desktopEntry: "",
            summary: "Old instance", body: "", urgency: 1, time: 2200
        })
        Notifications.removeFromHistory(0)
        root._check(Notifications.historyCount === 0
                && Notifications._seen["53"] === true
                && Notifications._times["53"] === 2300
                && Notifications._updateTimes["53"] === 2500,
            "deleting old history preserves state for a live notification with a reused id")
        Notifications._onClosed(53, replacementNotification)
        root._check(Notifications.activeCount === 0 && Notifications.historyCount === 1
                && Notifications.historyModel.get(0).summary === "Replacement",
            "closing the current notification still archives and retires it")
        Notifications._onClosed(53, replacementNotification)
        root._check(Notifications.historyCount === 1,
            "repeating a current notification's close cannot duplicate its history")
        Notifications.clearHistory()
        Notifications.list = []
        Notifications._forgetState(53)

        let batchDismissed = 0
        const batchOne = {
            transient: false, tracked: true,
            appName: "Probe", appIcon: "", desktopEntry: "",
            summary: "Batch one", body: "", urgency: 1,
            dismiss: function() { batchDismissed++ }, expire: function() {}
        }
        const batchTwo = {
            transient: false, tracked: true,
            appName: "Probe", appIcon: "", desktopEntry: "",
            summary: "Batch two", body: "", urgency: 1,
            dismiss: function() { batchDismissed++ }, expire: function() {}
        }
        Notifications._times = { "54": 2600, "55": 2700 }
        Notifications.list = [
            { notification: batchOne, id: 54, time: 2600 },
            { notification: batchTwo, id: 55, time: 2700 }
        ]
        Notifications.dismissObjects([
            { notification: batchOne, id: 54 },
            { notification: batchTwo, id: 55 }
        ], false)
        root._check(batchDismissed === 2 && Notifications.activeCount === 0,
            "a batched popup clear dismisses every live notification")
        root._check(Notifications.historyCount === 2,
            "a batched popup clear archives every notification")
        Notifications.clearHistory()

        const scanAdapterWas = Bluetooth._scanAdapter
        const scanRequestedWas = Bluetooth._scanRequested
        const firstRadio = { enabled: true, discovering: false }
        const secondRadio = { enabled: true, discovering: false }
        Bluetooth._scanAdapter = null
        Bluetooth._scanRequested = true
        Bluetooth._syncDiscovery(firstRadio)
        root._check(firstRadio.discovering && Bluetooth._scanAdapter === firstRadio,
            "opening Bluetooth discovery starts the requested adapter")
        Bluetooth._syncDiscovery(secondRadio)
        root._check(!firstRadio.discovering && secondRadio.discovering
                && Bluetooth._scanAdapter === secondRadio,
            "Bluetooth discovery follows an adapter change even when both adapters are enabled")
        Bluetooth._syncDiscovery(null)
        root._check(!secondRadio.discovering && Bluetooth._scanAdapter === null,
            "losing an adapter releases its discovery session")
        Bluetooth._syncDiscovery(secondRadio)
        root._check(secondRadio.discovering,
            "a requested Bluetooth scan recovers when its adapter returns")
        secondRadio.enabled = false
        Bluetooth._syncDiscovery(secondRadio)
        root._check(!secondRadio.discovering && Bluetooth._scanAdapter === null,
            "disabling a Bluetooth adapter stops its discovery session")
        Bluetooth._scanRequested = false
        const otherOwnerRadio = { enabled: true, discovering: true }
        Bluetooth._syncDiscovery(otherOwnerRadio)
        root._check(otherOwnerRadio.discovering,
            "an idle Bluetooth picker leaves another owner's discovery untouched")
        Bluetooth._scanRequested = true
        Bluetooth._syncDiscovery(otherOwnerRadio)
        root._check(otherOwnerRadio.discovering && Bluetooth._scanAdapter === null,
            "opening the Bluetooth picker does not claim another owner's discovery")
        Bluetooth._scanRequested = false
        Bluetooth._syncDiscovery(otherOwnerRadio)
        root._check(otherOwnerRadio.discovering,
            "closing the Bluetooth picker leaves another owner's discovery running")
        Bluetooth._scanAdapter = scanAdapterWas
        Bluetooth._scanRequested = scanRequestedWas

        const closedAdapter = { pairable: false, pairableTimeout: 0 }
        Bluetooth._armPairable(closedAdapter)
        root._check(closedAdapter.pairable
                && closedAdapter.pairableTimeout === Bluetooth._pairableTimeoutSec,
            "a pairing attempt opens a bounded adapter pairing window")
        Bluetooth._restorePairable()
        root._check(!closedAdapter.pairable && closedAdapter.pairableTimeout === 0,
            "a completed pairing attempt restores the pairing window it changed")
        const openAdapter = { pairable: true, pairableTimeout: 120 }
        Bluetooth._armPairable(openAdapter)
        Bluetooth._restorePairable()
        root._check(openAdapter.pairable && openAdapter.pairableTimeout === 120,
            "pairing preserves an adapter another owner already made pairable")

        root._check(Bluetooth.deviceGlyph("audio-headset") === Bluetooth.deviceGlyph("audio-headphones"),
            "bluetooth glyphs group headsets with headphones")
        root._check(Bluetooth.deviceGlyph("input-mouse") !== Bluetooth.deviceGlyph("input-keyboard"),
            "bluetooth glyphs separate a pointer from a keyboard")
        root._check(Bluetooth.deviceGlyph("") === Bluetooth.deviceGlyph("unknown-device")
                && Bluetooth.deviceGlyph("").length > 0,
            "an unrecognised bluetooth device falls back to one generic glyph")
        root._check(Bluetooth.deviceGlyph("audio-card") === Bluetooth.deviceGlyph("speaker")
                && Bluetooth.deviceGlyph("audio-card") !== Bluetooth.deviceGlyph("audio-headphones"),
            "bluetooth glyphs read BlueZ's audio-card as a speaker, not headphones")
        root._check(Bluetooth.deviceGlyph("input-gaming") !== Bluetooth.deviceGlyph("unknown-device"),
            "a bluetooth controller gets its own glyph")
        root._check(Bluetooth.deviceGlyph("audio-headphones") === Bluetooth.deviceGlyph("audio-tape"),
            "an unlisted bluetooth audio device still reads as audio")
        root._check(Bluetooth.deviceGlyph("input-tablet") !== Bluetooth.deviceGlyph("phone"),
            "a bluetooth tablet is not read as a phone")
        const node = (n, d, ff, ic) => ({ name: n, description: d,
            properties: { "device.form-factor": ff, "device.icon-name": ic } })
        root._check(Audio.deviceClass(node("alsa_output.pci", "Speakers", "", "")) === "speaker"
                && Audio.deviceClass(node("alsa_output.usb", "Headset", "headset", "")) === "headset"
                && Audio.deviceClass(node("alsa_output.usb", "Dock", "", "audio-speakers")) === "speaker"
                && Audio.deviceClass(null) === "",
            "an audio sink is classed on what it states about itself")
        root._check(Audio.deviceClass(node("bluez_output.AA_BB.1", "Anything", "speaker", "")) === "speaker",
            "a bluetooth sink that states a form factor is believed over its bluez name")
        root._check(Audio.deviceClass(node("bluez_output.AA_BB.1", "Q45", "", "")) === "headset",
            "a bluetooth sink BlueZ cannot place still reads as a headset")
        const comboSink = { name: "combined", description: "Combined Headphones",
            properties: { "node.virtual": true, "node.group": "combine-1" } }
        const comboFeed = { isStream: true, properties: { "node.virtual": true, "node.group": "combine-1" } }
        const comboBuds = { name: "bluez_output.AA_BB.1", description: "Buds", isStream: false, properties: {} }
        const comboSpeakers = { name: "alsa_output.pci", description: "Analog Stereo", isStream: false,
            properties: { "device.api": "alsa" } }
        root._check(Audio.deviceClass(comboSink, []) === "speaker"
                && Audio.deviceClass(comboSink, [{ source: comboFeed, target: comboSpeakers }]) === "speaker"
                && Audio.deviceClass(comboSink, [{ source: comboFeed, target: comboBuds }]) === "headset",
            "a virtual sink is classed by the device it feeds, not by the name its config gave it")
        const loneSink = { name: "eq", properties: { "node.virtual": true } }
        root._check(Audio.feedsNothing(comboSink, [])
                && !Audio.feedsNothing(comboSink, [{ source: comboFeed, target: comboSpeakers }])
                && !Audio.feedsNothing(comboSpeakers, [])
                && !Audio.feedsNothing(loneSink, []),
            "only a virtual sink with visible routing and no link is said to reach no device")
        root._check(Audio.isAppStream({ "application.name": "Spotify" })
                && Audio.isAppStream({ "application.process.binary": "zen-bin" })
                && !Audio.isAppStream({ "media.name": "Combined Headphones output",
                    "node.name": "output.combined_bluez_output.X.1" })
                && !Audio.isAppStream({})
                && !Audio.isAppStream(null),
            "a stream with no application behind it is routing, not an app")
        root._check(Bluetooth.deviceGlyph("video-display") !== Bluetooth.deviceGlyph("unknown-device")
                && Bluetooth.deviceGlyph("printer") !== Bluetooth.deviceGlyph("unknown-device")
                && Bluetooth.deviceGlyph("camera-photo") !== Bluetooth.deviceGlyph("unknown-device")
                && Bluetooth.deviceGlyph("multimedia-player") !== Bluetooth.deviceGlyph("unknown-device"),
            "less common bluetooth device types still resolve a glyph")

        root._check(Bluetooth._attemptOutcome("pair", true, false, true, false, 0) === "ok",
            "a paired device settles a pair attempt as success")
        root._check(Bluetooth._attemptOutcome("pair", true, false, false, true, 0) === "",
            "a pair attempt still pairing stays in progress")
        root._check(Bluetooth._attemptOutcome("pair", true, false, false, false, 0) === "failed",
            "a started pair attempt that dropped back to idle reports failure")
        root._check(Bluetooth._attemptOutcome("pair", false, false, false, false, 0) === "",
            "a pair attempt BlueZ has not moved yet is not called a failure")
        root._check(Bluetooth._attemptOutcome("connect", true, true, false, false, 0) === "ok",
            "a connected device settles a connect attempt as success")
        root._check(Bluetooth._extendAttemptGuard("connect", false,
                Bt.BluetoothDeviceState.Connecting, 0)
                && Bluetooth._extendAttemptGuard("connect", false,
                    Bt.BluetoothDeviceState.Connecting, 1)
                && !Bluetooth._extendAttemptGuard("connect", false,
                    Bt.BluetoothDeviceState.Connecting, 2)
                && !Bluetooth._extendAttemptGuard("connect", false, 0, 0),
            "a connecting Bluetooth device gets bounded extra time before failing")

        const retiredNotification = {
            transient: false, tracked: true,
            appName: "Probe", appIcon: "", desktopEntry: "",
            summary: "Retire me", body: "", urgency: 1
        }
        Notifications._times = { "61": 3000 }
        Notifications.list = [{
            notification: retiredNotification, id: 61, time: 3000
        }]
        Notifications._retireActiveNotifications()
        root._check(Notifications.activeCount === 0 && !retiredNotification.tracked,
            "disabling popups retires cards instead of leaving timerless notifications")
        root._check(Notifications.historyCount === 1,
            "a notification retired with the popup window remains in history")
        Notifications.clearHistory()

        Hooks._queued = ({})
        Hooks._queueOrder = []
        Hooks._queue("workspace-changed", ["/hooks/workspace-changed", "1"])
        Hooks._queue("notification", ["/hooks/notification", "Probe"])
        Hooks._queue("workspace-changed", ["/hooks/workspace-changed", "5"])
        root._check(Hooks._queueOrder.length === 2
                && Hooks._queueOrder[0] === "workspace-changed"
                && Hooks._queued["workspace-changed"][1] === "5",
            "a hook waiting on a busy runner keeps its place and takes the newest arguments")
        Hooks._queued = ({})
        Hooks._queueOrder = []

        root._startSelectFadeProbe()
    }

    property var _barLayoutProbe: null

    function _startBarLayoutProbe(): void {
        const settings = {}
        for (const key of ["reduceMotion", "barCompact", "barAutoCompact", "barCenterInGap",
                "osdEnabled", "osdBarIntegrated", "barShowClock", "barShowVolume"])
            settings[key] = ShellSettings[key]
        const osd = {}
        for (const key of ["showing", "kind", "label", "muted", "icon", "nextIcon", "value"])
            osd[key] = OsdBarState[key]
        ShellSettings.reduceMotion = true
        ShellSettings.barCompact = false
        ShellSettings.barAutoCompact = true
        ShellSettings.barCenterInGap = true
        ShellSettings.osdEnabled = true
        ShellSettings.osdBarIntegrated = true
        ShellSettings.barShowClock = true
        ShellSettings.barShowVolume = true
        OsdBarState.showing = false
        const component = Qt.createComponent("modules/bar/BarContent.qml")
        const bar = component.createObject(root, {
            screen: Quickshell.screens[0] ?? null, width: 330, fitWidth: 330, height: 36
        })
        component.destroy()
        root._check(bar !== null, "responsive bar fixture builds")
        if (!bar) {
            for (const key of Object.keys(settings)) ShellSettings[key] = settings[key]
            for (const key of Object.keys(osd)) OsdBarState[key] = osd[key]
            root._startTrayProbe()
            return
        }
        const zones = bar.children.filter(item => item.orderKeys !== undefined)
        zones[0].widgetComponents = { workspaces: barLeftFactory }
        zones[0].orderKeys = ["workspaces"]
        zones[1].widgetComponents = { volume: barCenterFactory }
        zones[1].orderKeys = []
        zones[2].widgetComponents = { clock: barRightFactory }
        zones[2].orderKeys = ["clock"]
        // The offscreen platform has no ShellScreen. Exercise the real loader's
        // geometry while bypassing only its monitor-selection gate.
        const loader = bar.children.find(item => item.sourceComponent !== undefined && item.z === 2)
        loader.active = true
        root._barLayoutProbe = { step: 0, bar: bar, zones: zones, settings: settings, osd: osd }
        _barLayoutSettle.start()
    }

    Timer {
        id: _barLayoutSettle
        interval: 100
        onTriggered: {
            const s = root._barLayoutProbe
            const bar = s.bar
            const loader = bar.children.find(item => item.item && item.item._shouldShow !== undefined)
            const osd = loader ? loader.item : null
            switch (s.step++) {
            case 0:
                root._check(!bar.effectiveCompact && !bar.centerHasWidgets,
                    "an empty middle does not force a fitting bar into compact mode")
                bar.width = 600
                bar.fitWidth = 600
                s.zones[1].orderKeys = ["volume"]
                OsdBarState.kind = "volume"
                OsdBarState.label = "Volume"
                OsdBarState.icon = "V"
                OsdBarState.nextIcon = "V"
                OsdBarState.value = 1
                OsdBarState.muted = false
                OsdBarState.showing = true
                break
            case 1:
                root._check(osd && osd.state === "visible",
                    "the integrated OSD shows when enabled")
                root._check(loader && loader.x >= bar.titleFreeLeft
                        && loader.x + loader.width <= bar.titleFreeRight + 0.5,
                    "an integrated OSD stays clear of uneven side zones")
                ShellSettings.barCenterInGap = false
                bar.width = 440
                bar.fitWidth = 440
                break
            case 2: {
                // the side zones carry the live window title, so a fixed width can leave the gap uncrowded; narrow until it is
                const room = osd ? osd._availableWidth - osd._labelWidth : 0
                if (room >= 80 && (s.crowds || 0) < 3) {
                    s.crowds = (s.crowds || 0) + 1
                    bar.width = Math.max(1, bar.width - (room - 40))
                    bar.fitWidth = bar.width
                    s.step--
                    restart()
                    return
                }
                root._check(loader && loader.x >= bar.titleFreeLeft
                        && loader.x + loader.width <= bar.titleFreeRight + 0.5,
                    "a screen-centred OSD shifts into the available gap when crowded")
                const track = root._findTrayNode(osd, item => item.radius === 1.5
                    && item.height === 3)
                root._check(track && track.width > 0 && track.width < 80,
                    "a crowded integrated volume track contracts while retaining its reading")
                s.track = track
                OsdBarState.value = 0.01
                bar.width = 300 + bar.gap * 2 + osd._iconWidth + osd._labelWidth + 17
                bar.fitWidth = bar.width
                break
            }
            case 3:
                // The compact transition also changes divider widths. Trim
                // the measured remainder after those widths have settled.
                if (s.track && s.track.width > 1.5 && (s.trims || 0) < 3) {
                    s.trims = (s.trims || 0) + 1
                    bar.width = Math.max(1, bar.width + 1 - s.track.width)
                    bar.fitWidth = bar.width
                    s.step--
                    restart()
                    return
                }
                root._check(s.track && Math.abs(s.track.width - 1) < 0.5
                        && s.track.children[0].width <= s.track.width,
                    "a nearly squeezed-out volume track keeps its fill within its bounds")
                bar.width = 1
                bar.fitWidth = 1
                break
            case 4:
                root._check(osd && osd.width === 0 && osd.clip,
                    "an OSD with no free space clips its content instead of covering side widgets")
                OsdBarState.kind = "temp"
                OsdBarState.label = "A very long thermal warning ".repeat(20)
                bar.width = 600
                bar.fitWidth = 600
                break
            case 5: {
                const label = root._findTrayNode(osd, item => item.text === OsdBarState.label)
                root._check(osd && osd._labelWidth <= 240 * ShellSettings.uiScale
                        && label && label.truncated,
                    "long OSD alerts elide within a bounded width")
                root._check(osd && osd.Accessible.name === OsdBarState.label,
                    "an elided OSD alert retains its full accessible description")
                ShellSettings.osdEnabled = false
                root._check(osd && osd.state === "hidden" && !osd.visible,
                    "disabling OSD presentation hides a displayed integrated alert immediately")
                break
            }
            case 6:
                bar.destroy()
                for (const key of Object.keys(s.settings)) ShellSettings[key] = s.settings[key]
                for (const key of Object.keys(s.osd)) OsdBarState[key] = s.osd[key]
                root._barLayoutProbe = null
                root._startTrayProbe()
                return
            }
            restart()
        }
    }

    property var _selectFadeProbe: null
    property bool _selectReduceWas: false

    function _startSelectFadeProbe(): void {
        root._selectReduceWas = ShellSettings.reduceMotion
        ShellSettings.reduceMotion = false
        root._selectFadeProbe = selectRowFactory.createObject(root)
        root._selectFadeProbe._setOpen(true)
        _selectFadeSettle.start()
    }

    Timer {
        id: _selectFadeSettle
        interval: 300
        onTriggered: {
            const select = root._selectFadeProbe
            const option = root._findTrayNode(select, item =>
                typeof item.trigger === "function" && item.previewValue === "b")
            root._check(option !== null, "an open dropdown builds its option controls")
            if (option) {
                let choices = 0
                select.chosen.connect(function() { choices++ })
                select._setOpen(false)
                root._check(!option.enabled,
                    "closing a dropdown disables its retained option controls immediately")
                option.trigger()
                root._check(choices === 0,
                    "a fading dropdown option rejects accessibility activation")
                option.triggered()
                root._check(choices === 0,
                    "a late option signal cannot change a closed dropdown's setting")
                select._setOpen(true)
                option.trigger()
                root._check(choices === 1 && !select._open,
                    "a reopened dropdown accepts one choice and closes")
            }
            select.destroy()
            root._selectFadeProbe = null
            ShellSettings.reduceMotion = root._selectReduceWas
            root._startResourceProbe()
        }
    }

    property var _resourceProbe: null

    function _optionRows(item): var {
        let rows = item && item.optionFont !== undefined ? [item] : []
        for (const child of item?.children || []) rows = rows.concat(root._optionRows(child))
        return rows
    }

    function _startResourceProbe(): void {
        const state = { step: 0, reduce: ShellSettings.reduceMotion, open: MenuState.open }
        root._resourceProbe = state
        ShellSettings.reduceMotion = true
        MenuState.close()
        MenuState.requestWarm(probeAnchor, null)
        MenuState.requestWarm(invalidProbeAnchor, null)
        MenuState.cancelWarm(probeAnchor)
        state.select = selectRowFactory.createObject(root, {
            model: Array.from({ length: 1000 }, (_, i) => ({ value: "v" + i, label: "Option " + i })),
            currentValue: "v999"
        })
        state.select._setOpen(true)
        _resourceSettle.interval = 150
        _resourceSettle.restart()
    }

    Timer {
        id: _resourceSettle
        onTriggered: {
            const s = root._resourceProbe
            const select = s.select
            const rows = root._optionRows(select)
            switch (s.step++) {
            case 0: {
                const selected = rows.find(row => row.previewValue === "v999")
                const point = selected ? selected.mapToItem(select, 0, 0) : null
                root._check(rows.length > 0 && rows.length <= 16,
                    "a thousand-choice dropdown builds only its viewport and reuse pool")
                root._check(point && point.y >= select._headerH - 0.5
                        && point.y + selected.height <= select.height + 0.5,
                    "opening a long dropdown reveals the selected option at the end")
                select._revealOption(0)
                break
            }
            case 1:
                root._check(rows.some(row => row.previewValue === "v0") && rows.length <= 24,
                    "scrolling a long dropdown creates the first option with a bounded reuse pool")
                select._revealOption(999)
                break
            case 2: {
                const selected = rows.find(row => row.previewValue === "v999")
                let chosen = ""
                select.chosen.connect(value => { chosen = value })
                if (selected) selected.trigger()
                root._check(chosen === "v999" && !select._open,
                    "a recycled dropdown option chooses its current value and closes")
                break
            }
            case 3:
                root._check(rows.length === 0,
                    "closing a long dropdown releases its rows and reuse pool")
                _resourceSettle.interval = 2600
                break
            case 4:
                root._check(!MenuState.warmRequested && MenuState.warmScreen === null,
                    "an unused workspace hover releases the prepared menu after its warm budget")
                select.destroy()
                ShellSettings.reduceMotion = s.reduce
                MenuState.open = s.open
                root._resourceProbe = null
                root._startBarLayoutProbe()
                return
            }
            restart()
        }
    }

    property var _trayProbeItems: []
    property var _trayProbe: null

    function _findTrayNode(item, predicate): var {
        if (!item) return null
        if (predicate(item)) return item
        const children = item.children || []
        for (let i = 0; i < children.length; i++) {
            const found = root._findTrayNode(children[i], predicate)
            if (found) return found
        }
        return null
    }

    function _checkWidgetAccessibility(settings): void {
        const parentToggle = root._findTrayNode(settings, item =>
            item.Accessible.role === Accessible.CheckBox
                && item.Accessible.name === ShellSettings.barWidgetMeta.tray.label)
        const appToggle = root._findTrayNode(settings, item => item.modelData === "probe-a"
            && typeof item.toggleShown === "function")
        root._check(parentToggle !== null && appToggle !== null,
            "widget settings expose both parent and per-app checkbox controls")
        if (parentToggle === null || appToggle === null) return
        root._check(parentToggle.Accessible.checkable && appToggle.Accessible.checkable,
            "widget settings checkboxes advertise that their states can be changed")
        parentToggle.Accessible.pressAction()
        root._check(!ShellSettings.trayWidget,
            "accessible widget checkbox press updates its configured visibility")
        parentToggle.Accessible.toggleAction()
        root._check(ShellSettings.trayWidget,
            "accessible widget checkbox toggle restores its configured visibility")
        settings.enabled = false
        parentToggle.Accessible.toggleAction()
        appToggle.Accessible.toggleAction()
        root._check(ShellSettings.trayWidget && !ShellSettings.trayItemHidden("probe-a"),
            "disabled widget settings reject accessible parent and per-app toggles")
        settings.enabled = true
        // recover the fixture even if the disabled-state assertion failed
        ShellSettings.trayWidget = true
        ShellSettings.setTrayItemHidden("probe-a", false)
        appToggle.Accessible.pressAction()
        root._check(ShellSettings.trayItemHidden("probe-a"),
            "accessible per-app checkbox press hides its tray icon")
        appToggle.Accessible.toggleAction()
        root._check(!ShellSettings.trayItemHidden("probe-a"),
            "accessible per-app checkbox toggle shows its tray icon")
        settings._setTrayOpen(false)
        appToggle.Accessible.toggleAction()
        root._check(!ShellSettings.trayItemHidden("probe-a"),
            "a closed tray disclosure rejects retained accessible checkbox actions")
        settings._setTrayOpen(true)
        settings._beginDrag("clock")
        parentToggle.Accessible.toggleAction()
        appToggle.Accessible.toggleAction()
        root._check(ShellSettings.trayWidget && !ShellSettings.trayItemHidden("probe-a"),
            "widget reordering cannot change visibility through accessible toggle actions")
        settings._finishDrag("clock")
        ShellSettings.trayWidget = true
        ShellSettings.setTrayItemHidden("probe-a", false)
    }

    function _startTrayProbe(): void {
        const state = {
            step: 0, enabled: ShellSettings.trayWidget, hidden: ShellSettings.trayHidden,
            reduce: ShellSettings.reduceMotion,
            layout: [ShellSettings.barWidgetOrderLeft, ShellSettings.barWidgetOrderCenter,
                ShellSettings.barWidgetOrderRight]
        }
        root._trayProbe = state
        ShellSettings.reduceMotion = true
        ShellSettings.trayWidget = true
        ShellSettings.trayHidden = ""
        trayIconFixture.setText('<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><rect width="16" height="16" fill="#ff6600"/></svg>')
        const source = "file://" + trayIconFixture.path
        state.first = trayItemFactory.createObject(root, { id: "probe-a", title: "First app", icon: source })
        state.second = trayItemFactory.createObject(root, { id: "probe-b", title: "Second app", icon: source })
        root._trayProbeItems = [state.first, state.second]
        const zoneComponent = Qt.createComponent("modules/bar/BarZone.qml")
        state.zone = zoneComponent.createObject(root, {
            orderKeys: ["tray"], widgetComponents: { tray: trayWidgetFactory },
            compact: true, height: 36
        })
        const settingsComponent = Qt.createComponent("modules/menu/settings/DraggableWidgetList.qml")
        state.settings = settingsComponent.createObject(root, {
            width: 320, trayItems: Qt.binding(() => root._trayProbeItems)
        })
        state.settings._setTrayOpen(true)
        _trayProbeSettle.restart()
    }

    Timer {
        id: _trayProbeSettle
        interval: 100
        onTriggered: {
            const s = root._trayProbe
            const tile = root._findTrayNode(s.zone, item => typeof item.syncMenuAnchor === "function"
                && item.modelData === s.first)
            const icon = root._findTrayNode(tile, item => item.backer !== undefined)
            const widget = root._findTrayNode(s.zone, item => item.trayModel !== undefined)
            // Image decoding is asynchronous; a busy test host can take longer
            // than one tick even for this local SVG. Keep a bound so a broken
            // fixture still fails, and do not wait past an explicit image error.
            if (s.step === 0 && (!tile || !icon || icon.status === Image.Loading)
                    && (s.readyTicks ?? 0) < 20) {
                s.readyTicks = (s.readyTicks ?? 0) + 1
                _trayProbeSettle.restart()
                return
            }
            switch (s.step++) {
            case 0:
                s.tile = tile
                root._check(tile && icon && icon.status === Image.Ready && s.zone.implicitWidth > 0,
                    "a tray icon renders in its real bar zone")
                root._checkWidgetAccessibility(s.settings)
                s.settings._setTrayItemShown("probe-a", false)
                break
            case 1:
                root._check(tile === s.tile && tile.hidden && !tile.visible
                        && s.zone.implicitWidth > 0,
                    "hiding one tray app preserves its delegate and the other icon")
                s.settings._setTrayItemShown("probe-a", true)
                break
            case 2:
                root._check(tile === s.tile && tile.visible && icon && icon.status === Image.Ready,
                    "showing a hidden tray app reloads its icon without recreating its delegate")
                ShellSettings.setTrayItemHidden("probe-a", true)
                ShellSettings.setTrayItemHidden("probe-b", true)
                _trayProbeSettle.interval = 300
                break
            case 3:
                root._check(widget && !widget.show && widget.implicitWidth === 0
                        && s.zone.visibleKeys.length === 0,
                    "hiding every tray app removes the tray and its divider from the bar")
                s.settings._setTrayItemShown("probe-a", true)
                _trayProbeSettle.interval = 100
                break
            case 4:
                root._check(tile && tile.visible && icon && icon.status === Image.Ready
                        && s.zone.implicitWidth > 0 && s.zone.visibleKeys[0] === "tray"
                        && ShellSettings.trayItemHidden("probe-b"),
                    "showing an app restores an entirely hidden tray without unhiding other apps")
                ShellSettings.trayWidget = false
                break
            case 5:
                root._check(tile === s.tile && widget && !widget.show,
                    "a brief tray disable retains its delegates during the bar's unload delay")
                ShellSettings.trayWidget = true
                break
            case 6:
                root._check(tile === s.tile && tile.visible && icon && icon.status === Image.Ready,
                    "a quick tray off/on restores the same rendered icon")
                ShellSettings.trayWidget = false
                _trayProbeSettle.interval = 400
                break
            case 7:
                root._check(tile === null, "a persistently disabled tray releases its bar widget")
                ShellSettings.trayWidget = true
                _trayProbeSettle.interval = 100
                break
            case 8: {
                root._check(tile && tile.visible && icon && icon.status === Image.Ready
                        && s.zone.implicitWidth > 0,
                    "enabling an unloaded tray rebuilds its icons")
                ShellSettings.trayWidget = false
                const row = root._findTrayNode(s.settings, item => item.modelData === "probe-a"
                    && typeof item.toggleShown === "function")
                root._check(row && row.statusText === "Tray off" && !row.Accessible.checked,
                    "tray settings distinguish a saved visibility preference from the tray being off")
                if (row) row.toggleShown()
                root._check(ShellSettings.trayWidget && !ShellSettings.trayItemHidden("probe-a"),
                    "showing an app from its settings row also enables the tray")
                ShellSettings.setTrayItemHidden("probe-a", true)
                ShellSettings.setTrayItemHidden("stopped-app", true)
                s.settings._showAllTrayItems()
                root._check(ShellSettings.trayWidget && ShellSettings.trayHiddenIds.length === 0
                        && s.settings._trayIds.indexOf("stopped-app") >= 0
                        && s.layout[0] === ShellSettings.barWidgetOrderLeft
                        && s.layout[1] === ShellSettings.barWidgetOrderCenter
                        && s.layout[2] === ShellSettings.barWidgetOrderRight,
                    "show all restores running and stopped app preferences without resetting bar layout")
                const stopped = root._findTrayNode(s.settings, item => item.modelData === "stopped-app"
                    && item.statusText !== undefined)
                root._check(stopped && stopped.statusText === "Not running",
                    "restoring a stopped tray app explains why its icon is absent")

                const popup = TrayMenuState
                const handle = selectStubFactory.createObject(root)
                popup.toggleAt(17, null, handle, false, tile, s.first)
                popup.toggleAt(33, null, null, false, tile, s.second)
                root._check(popup.open && popup.sourceItem === s.second && popup.menuHandle === null,
                    "switching to a menu-less tray app keeps its own hide menu and source")
                popup.toggleAt(33, null, null, false, tile, s.second)
                root._check(!popup.open, "clicking the same tray menu's source closes it")
                popup.toggleAt(17, null, handle, false, tile, s.first)
                popup.menuHandle = null
                root._check(!popup.open, "a tray app losing its live menu closes the popup")
                popup.toggleAt(33, null, null, false, tile, s.second)
                popup.sourceItem = null
                root._check(!popup.open, "a menu-less app disappearing also closes its popup")
                popup.toggleAt(17, null, null, false, tile, s.first)
                ShellSettings.setTrayItemHidden("probe-a", true)
                root._check(!popup.open,
                    "hiding an app while its tray menu is open also closes that menu")
                ShellSettings.trayHidden = ""
                s.first.onlyMenu = true
                if (widget && tile) widget._activateItem(s.first, tile)
                root._check(popup.open && popup.sourceItem === s.first && s.first.activations === 0,
                    "a menu-only tray item's primary action always opens its menu")
                popup.close()
                handle.destroy()
                s.first.onlyMenu = false
                s.first.icon = ""
                root._check(tile && tile.fallbackVisible,
                    "a tray app without an icon shows its initial immediately")
                break
            }
            case 9: {
                root._check(tile && tile.visible && tile.fallbackVisible && s.zone.implicitWidth > 0,
                    "an icon-less app keeps a visible tray button and its bar slot")
                const initial = root._findTrayNode(tile, item => item.text === "F")
                root._check(initial && initial.visible && initial.parent.visible,
                    "the tray fallback contains the app's initial")
                if (widget && tile) widget._activateItem(s.first, tile)
                root._check(s.first.activations === 1,
                    "an icon-less tray app still responds to its primary action")
                const row = root._findTrayNode(s.settings, item => item.modelData === "probe-a"
                    && item.statusText !== undefined)
                const settingsInitial = root._findTrayNode(row, item => item.text === "F")
                root._check(row && row.statusText === "Shown" && settingsInitial && settingsInitial.visible,
                    "tray settings show a fallback without changing the app's visibility preference")
                s.first.icon = "file://" + ConfigStore.directory + "/missing-tray-icon.png"
                break
            }
            case 10:
                root._check(tile && tile.fallbackVisible && tile._providedIconFailed,
                    "a failed tray image falls back instead of leaving an empty button")
                s.first.icon = "file://" + trayIconFixture.path
                break
            case 11: {
                root._check(tile && icon && icon.status === Image.Ready
                        && !tile.fallbackVisible && !tile._providedIconFailed,
                    "a tray app gaining a valid icon replaces its fallback")
                s.zone.destroy()
                s.settings.destroy()
                root._trayProbeItems = []
                s.first.destroy()
                s.second.destroy()
                ShellSettings.trayHidden = s.hidden
                ShellSettings.trayWidget = s.enabled
                ShellSettings.reduceMotion = s.reduce
                root._trayProbe = null
                root._startHistoryPageProbe()
                return
            }
            }
            _trayProbeSettle.restart()
        }
    }

    property var _historyPage: null
    property bool _historyReduceWas: false

    function _startHistoryPageProbe(): void {
        root._historyReduceWas = ShellSettings.reduceMotion
        ShellSettings.reduceMotion = true
        MenuState.setRecentFilter("")
        MenuState.openAt(17, null, probeAnchor)
        Notifications.clearHistory()
        Notifications._prependHistory({ id: 901, appName: "Mail", summary: "Match this", time: 2001 })
        Notifications._prependHistory({ id: 902, appName: "Chat", summary: "Keep this", time: 2002 })
        const pageComponent = Qt.createComponent("modules/menu/RecentPage.qml")
        root._historyPage = pageComponent.status === Component.Ready
            ? pageComponent.createObject(root, {
                width: 332, viewportHeight: 520, active: true, powerOpen: false
            }) : null
        root._check(root._historyPage !== null, "the history page builds with its search field")
        if (!root._historyPage) {
            ShellSettings.reduceMotion = root._historyReduceWas
            MenuState.close()
            Notifications.clearHistory()
            root._startDirectAnchorProbe()
            return
        }
        root._check(root._historyPage.hasHistory,
            "history search is available when notifications exist")
        root._historyPage.searchText = "match"
        root._check(root._historyPage.rowCount === 1 && root._historyPage.searching,
            "typing in the history page filters its displayed rows")
        root._check(root._historyPage.dismissInline() && root._historyPage.rowCount === 2
                && !root._historyPage.searching && !root._historyPage.dismissInline(),
            "Escape clears search once before allowing the menu to close")
        root._historyPage.searchText = "match"
        root._historyPage.clearAll()
        root._check(Notifications.historyCount === 1
                && Notifications.historyModel.get(0).id === 902 && root._historyPage.rowCount === 0
                && root._historyPage.hasHistory && root._historyPage.searching,
            "search stays available when a query has no matches but history remains")
        Notifications.clearHistory()
        root._check(!root._historyPage.hasHistory && !root._historyPage.searching
                && root._historyPage.rowCount === 0,
            "empty history hides search and clears the stale query")
        Notifications._prependHistory({ id: 902, appName: "Chat", summary: "Keep this", time: 2002 })
        Notifications._prependHistory({ id: 903, appName: "Mail", summary: "Match again", time: 2003 })
        root._historyPage.searchText = "match"
        ShellSettings.reduceMotion = false
        root._historyPage.clearAll()
        root._check(root._historyPage._clearing, "animated history clear captures results before fading")
        Notifications._prependHistory({ id: 904, appName: "Mail", summary: "Match arrival", time: 2004 })
        MenuState.setRecentFilter("Chat")
        _historyClearSettle.restart()
    }

    Timer {
        id: _historyClearSettle
        interval: 300
        onTriggered: {
            root._check(!root._historyPage._clearing && Notifications.historyCount === 2
                    && Notifications.historyModel.get(0).id === 904
                    && Notifications.historyModel.get(1).id === 902,
                "animated clear preserves later arrivals and does not follow a changed app filter")
            root._historyPage.active = false
            root._check(root._historyPage.searchText.length === 0,
                "leaving history resets the search for its next visit")
            root._historyPage.destroy()
            root._historyPage = null
            MenuState.close()
            MenuState.setRecentFilter("")
            ShellSettings.reduceMotion = root._historyReduceWas
            Notifications.clearHistory()
            root._startDirectAnchorProbe()
        }
    }

    function _startDirectAnchorProbe(): void {
        const popup = TrayMenuState
        popup.close()
        popup.openAt(17, null, invalidProbeAnchor)
        root._check(popup.open && popup.effectiveAnchorX === 17,
            "an invalid live popup anchor falls back to its captured x")
        popup._setAnchor(probeAnchor)
        root._check(popup.anchorSource === probeAnchor,
            "setting a popup anchor retains the requested live object")
        root._check(popup.effectiveAnchorX === probeAnchor.menuAnchorX,
            "a popup reads the current x from its live anchor")
        popup.adoptAnchor(invalidProbeAnchor)
        root._check(popup.anchorSource === probeAnchor,
            "a second widget cannot steal an adopted popup anchor")

        popup.close()
        popup.anchorX = 23
        popup.openUnanchored()
        root._check(popup.open && popup.anchorSource === null
                && popup.triggerScreen === null && popup.effectiveAnchorX === 23,
            "an unanchored popup opens on its retained fallback without a trigger screen")
        popup.adoptAnchor(probeAnchor)
        root._check(popup.anchorSource === probeAnchor,
            "the first live widget can adopt an unanchored open popup")
        // Simulate QObject destruction, which clears the property without calling _setAnchor().
        popup.anchorSource = null
        _directAnchorRegrabSettle.restart()
    }

    Timer {
        id: _directAnchorRegrabSettle
        interval: 220
        onTriggered: {
            root._check(!TrayMenuState.open && TrayMenuState.anchorSource === null,
                "an open popup closes when no widget reclaims its dropped anchor")
            root._startAnchorTeardown()
        }
    }

    // A zone's Repeater renders a plain JS array, so writing a new order regenerates it:
    // the replacements are built first and the originals are destroyed on a later turn.
    // That out-of-order teardown is what closed the menu on a reorder and on a reset,
    // so drive the real settings writes through a stand-in for the widget holding the anchor.
    Item {
        id: anchorZone
        Repeater {
            id: anchorSlots
            model: ShellSettings.barWidgetOrderLeftKeys
            delegate: Item {
                required property string modelData
                property bool keepLoaded: false
                Component.onCompleted: keepLoaded = true
                Loader {
                    active: parent.keepLoaded
                    sourceComponent: parent.modelData === "workspaces" ? anchorHolder : null
                }
            }
        }
    }

    // the real widget, not a stand-in: its own reclaim wiring is what the teardown broke
    Component {
        id: anchorHolder
        Workspaces { screen: Quickshell.screens[0] ?? null }
    }

    function _liveAnchorHolder(): var {
        for (let i = 0; i < anchorSlots.count; i++) {
            const slot = anchorSlots.itemAt(i)
            if (slot && slot.modelData === "workspaces")
                return slot.children.length > 0 ? slot.children[0].item : null
        }
        return null
    }

    property bool _savedLoadedForTeardown: false
    function _startAnchorTeardown(): void {
        root._savedLoadedForTeardown = ShellSettings._loaded
        ShellSettings._loaded = true
        MenuState.toggleAt(7, Quickshell.screens[0] ?? null, null)
        MenuState._setAnchor(root._liveAnchorHolder())
        root._check(MenuState.open && MenuState.anchorSource !== null,
            "the anchor stand-in stands in for the widget the menu opened from")
        ShellSettings.setBarWidgetLayout(["media", "workspaces"],
            ShellSettings.barWidgetOrderCenterKeys, ShellSettings.barWidgetOrderRightKeys)
        ShellSettings.resetBarWidgets()
        _anchorTeardownSettle.restart()
    }

    Timer {
        id: _anchorTeardownSettle
        interval: 300
        onTriggered: {
            root._check(MenuState.open,
                "reordering and resetting bar widgets leaves the menu open")
            root._check(MenuState.anchorSource === root._liveAnchorHolder(),
                "the surviving widget, not a discarded rebuild, holds the menu anchor")
            MenuState.close()
            ShellSettings.resetBarWidgets()
            ShellSettings._loaded = root._savedLoadedForTeardown
            root._startPageMotionChecks()
        }
    }

    property var _motionPage: null
    property var _motionSettings: null
    property bool _motionReduceWas: false
    property int _motionStep: 0
    property int _motionWaits: 0

    // the gate runs its probes side by side, so a load can outlast a fixed wait on a busy machine
    function _motionNotYet(ready: bool): bool {
        if (ready || root._motionWaits >= 30) {
            root._motionWaits = 0
            return false
        }
        root._motionWaits++
        root._motionStep--
        _pageMotionCheck.interval = 100
        _pageMotionCheck.restart()
        return true
    }

    function _startPageMotionChecks(): void {
        root._motionReduceWas = ShellSettings.reduceMotion
        ShellSettings.reduceMotion = false
        MenuState.open = true
        root._motionPage = pageShellFactory.createObject(root, {
            active: true, powerOpen: false
        })
        root._motionStep = 0
        _pageMotionCheck.interval = 40
        _pageMotionCheck.restart()
    }

    Timer {
        id: _pageMotionCheck
        onTriggered: {
            const page = root._motionPage
            switch (root._motionStep++) {
            case 0:
                page.active = false
                interval = Motion.pageOut + 80
                restart()
                break
            case 1:
                root._check(page.opacity === 0 && Math.abs(page._pageShift) > 0
                        && page._pageLift < 0,
                    "a departing page completes its fade and two-axis movement")
                MenuState.close()
                MenuState.open = true
                page.active = true
                root._check(page.opacity === 1 && page._pageShift === 0
                        && page._pageLift === 0,
                    "reopening a retained page resets the completed exit offset")
                page._menuOpenSettled = true
                page.active = false
                ShellSettings.reduceMotion = true
                root._check(page.opacity === 0 && page._pageShift === 0
                        && page._pageLift === 0,
                    "enabling reduced motion settles an interrupted page exit")
                page.active = true
                root._check(page.opacity === 1 && page._pageShift === 0
                        && page._pageLift === 0,
                    "reduced-motion page entry has no lingering offset")
                ShellSettings.reduceMotion = false
                root._motionSettings = settingsPageFactory.createObject(root, {
                    active: true, powerOpen: false, width: 400
                })
                interval = 500
                restart()
                break
            case 2: {
                const settings = root._motionSettings
                if (root._motionNotYet(settings.contentReady)) break
                const detail = settings.children[0]
                const body = detail.children.find(child => child.sourceComponent !== undefined)
                root._check(settings.contentReady, "settings content finishes its initial load")
                body.active = false
                settings._awaitingSectionEnter = true
                detail.opacity = 0
                detail._startSectionEnter()
                root._check(settings._awaitingSectionEnter && detail.opacity === 0,
                    "a settings section waits for its loader before starting its reveal")
                body.active = true
                interval = 500
                restart()
                break
            }
            case 3: {
                const settings = root._motionSettings
                const detail = settings.children[0]
                const revealed = settings.contentReady && !settings._awaitingSectionEnter
                        && detail.opacity === 1 && detail._shift === 0
                        && detail._lift === 0
                if (root._motionNotYet(revealed)) break
                root._check(revealed, "a ready settings section completes its reveal")
                MenuState.close()
                MenuState.setSettingsSection("clock")
                root._check(settings._shownSection === "clock" && detail.opacity === 1
                        && detail._lift === 0,
                    "a settings change while the menu is closed settles without a fade")

                // README promises Escape steps back before it closes; Home and the
                // history page fold their inline state, so Settings has to as well
                root._check(!settings.dismissInline(),
                    "escape on settings with nothing open falls through to closing the menu")
                const selectStub = selectStubFactory.createObject(root)
                MenuState.claimSettingsSelect(selectStub)
                root._check(MenuState.settingsSelectOpen,
                    "an open settings dropdown is visible to the page")
                root._check(settings.dismissInline() && selectStub.folded
                        && !MenuState.settingsSelectOpen,
                    "escape on settings folds an open dropdown instead of closing the menu")
                selectStub.destroy()

                root._motionPage.destroy()
                root._motionSettings.destroy()
                root._motionPage = null
                root._motionSettings = null
                MenuState.setSettingsSection("theme")
                ShellSettings.reduceMotion = root._motionReduceWas
                root._runProcessChecks()
                break
            }
            }
        }
    }

    function _runProcessChecks(): void {
        root._timeoutProbe = boundedProcessFactory.createObject(root, {
            command: ["bash", "-c", "sleep 5"],
            timeoutMs: 80
        })
        let timeoutSeen = false
        root._timeoutProbe.timeoutReached.connect(function() {
            root._check(root._timeoutProbe.timedOut,
                "bounded process records its timeout")
            timeoutSeen = true
        })
        root._timeoutProbe.exited.connect(function() {
            if (!timeoutSeen) return
            root._check(!root._timeoutProbe.running,
                "bounded process stops a wedged helper")
            root._timeoutProbe.destroy()
            root._timeoutProbe = null
            Qt.callLater(root._runKillEscalationCheck)
        })
        root._timeoutProbe.running = true
    }

    // Process has no signal() and running = false is only a SIGTERM, so a child that traps it
    // outlives its own timeout and holds a runner slot for good unless the pid is killed
    function _runKillEscalationCheck(): void {
        root._killProbe = boundedProcessFactory.createObject(root, {
            command: ["bash", "-c",
                '(trap \'\' TERM; sleep 30) & echo $! > "$1"; '
                    + 'trap \'\' TERM; sleep 30',
                "silere-bounded-probe", root._orphanPidFile],
            timeoutMs: 80
        })
        const startedAt = Date.now()
        let refused = false
        root._killProbe.timeoutReached.connect(function() {
            refused = root._killProbe.running
        })
        root._killProbe.exited.connect(function() {
            root._check(refused,
                "a helper that traps SIGTERM survives the timeout's polite stop")
            root._check(Date.now() - startedAt < 10000,
                "a helper that traps SIGTERM is still killed outright")
            root._killProbe.destroy()
            root._killProbe = null
            _orphanSettle.restart()
        })
        root._killProbe.running = true
    }

    // the wrapper and its descendant fall in the same kill pass, so let that pass drain
    Timer {
        id: _orphanSettle
        interval: 400
        onTriggered: {
            root._orphanCheck = processFactory.createObject(root, {
                command: ["bash", "-c",
                    // a killed orphan re-parents to a PID 1 that may never reap it, and its
                    // /proc entry outlives it as a zombie
                    'read -r orphan < "$1" || exit 1; [ -n "$orphan" ] || exit 1; '
                        + 'IFS= read -r line 2>/dev/null < "/proc/$orphan/stat" || exit 0; '
                        + 'line=${line##*) }; [ "${line%% *}" = Z ]',
                    "silere-bounded-check", root._orphanPidFile]
            })
            root._orphanCheck.exited.connect(function(code) {
                root._check(code === 0,
                    "a bounded process terminates descendants with its wrapper")
                root._orphanCheck.destroy()
                root._orphanCheck = null
                Qt.callLater(root._runMissingBinaryCheck)
            })
            root._orphanCheck.running = true
        }
    }

    // Quickshell emits no exited for a binary that fails to start
    function _runMissingBinaryCheck(): void {
        root._missingProbe = boundedProcessFactory.createObject(root, {
            command: ["/nonexistent/silere-probe-binary"]
        })
        root._missingSupervised = supervisedProcessFactory.createObject(root, {
            command: ["/nonexistent/silere-probe-binary"]
        })
        root._missingProbe.exited.connect(function(code) { root._missingExit = code })
        root._missingProbe.running = true
        root._missingSupervised.superviseWhen = true
        _missingSettle.restart()
    }
    Timer {
        id: _missingSettle
        interval: 500
        onTriggered: {
            root._check(root._missingExit === 127 && !root._missingProbe.running,
                "a bounded process whose binary is missing still reports an exit")
            root._missingProbe.destroy()
            root._missingProbe = null
            root._check(root._missingSupervised.gaveUp && !root._missingSupervised.running,
                "a supervised process whose binary is missing gives up instead of wedging")
            root._missingSupervised.superviseWhen = false
            root._missingSupervised.destroy()
            root._missingSupervised = null
            Qt.callLater(root._startHistoryPersistenceProbe)
        }
    }

    property int _historyDiskCase: 0
    readonly property var _historyDiskCases: [
        { raw: '{"__version":2,"history":[],"futureField":"keep"}', name: "a newer-version history file" },
        { raw: '[{"summary":"keep malformed root"}]', name: "an array history root" },
        { raw: 'null', name: "a null history root" },
        { raw: '{"__version":1,"history":{"summary":"keep malformed history"}}', name: "a non-array history payload" }
    ]

    function _startHistoryPersistenceProbe(): void {
        root._historyDiskCase = 0
        root._prepareHistoryDiskCase()
    }

    function _prepareHistoryDiskCase(): void {
        // begin with saving enabled: a protected read must revoke earlier write permission
        Notifications._restoreFromDisk('{"__version":1,"history":[]}')
        const test = root._historyDiskCases[root._historyDiskCase]
        notificationDiskFixture.setText(test.raw)
        Notifications._restoreFromDisk(test.raw)
        root._check(Notifications.storeError.length > 0,
            test.name + " reports why persistence is paused")
        Notifications._prependHistory({ id: 9910 + root._historyDiskCase, appName: "Probe",
            summary: "Arrival after protected read " + root._historyDiskCase, time: 9910 + root._historyDiskCase })
        Notifications._saveHistory()
        _historyDiskSettle.restart()
    }

    Timer {
        id: _historyDiskSettle
        interval: 600
        onTriggered: _historyDiskReader.running = true
    }

    BoundedProcess {
        id: _historyDiskReader
        command: ["cat", ConfigStore.notificationsPath]
        timeoutMs: 2000
        stdout: StdioCollector { id: _historyDiskText }
        onExited: code => {
            root._check(code === 0, "the history persistence probe reads its file from disk")
            if (root._historyDiskCase < root._historyDiskCases.length) {
                const test = root._historyDiskCases[root._historyDiskCase]
                root._check(_historyDiskText.text === test.raw,
                    test.name + " remains untouched by a queued history save")
                root._historyDiskCase++
                if (root._historyDiskCase < root._historyDiskCases.length) {
                    root._prepareHistoryDiskCase()
                    return
                }
                const valid = '{"__version":1,"history":[]}'
                notificationDiskFixture.setText(valid)
                Notifications._restoreFromDisk(valid)
                Notifications._prependHistory({ id: 9901, appName: "Probe", summary: "History saving recovered", time: 9901 })
                Notifications._saveHistory()
                _historyDiskSettle.restart()
                return
            }
            const saved = JSON.parse(_historyDiskText.text)
            root._check(Notifications.storeError.length === 0
                    && saved.history.some(entry => entry.summary === "History saving recovered"),
                "a valid history file restores saving after a protected or malformed read")
            Qt.callLater(root._startNotificationTimingProbe)
        }
    }

    property var _notificationTimingCards: []
    property bool _notificationTimingReduceWas: false

    function _notificationExpiryTimer(card): var {
        const objects = card.data
        for (let i = 0; i < objects.length; i++)
            if (objects[i].fullInterval !== undefined) return objects[i]
        return null
    }

    function _startNotificationTimingProbe(): void {
        root._notificationTimingReduceWas = ShellSettings.reduceMotion
        ShellSettings.reduceMotion = true
        const template = {
            actions: [], hints: ({}), appIcon: "", image: "", appName: "Probe",
            desktopEntry: "", summary: "Timing probe", body: "", urgency: 1,
            expireTimeout: 350, resident: false, transient: false, hasInlineReply: false
        }
        root._notificationTimingCards = [
            notificationCardFactory.createObject(root, { notification: template }),
            notificationCardFactory.createObject(root, {
                notification: template, stackHovered: true
            }),
            notificationCardFactory.createObject(root, {
                notification: Object.assign({}, template, { expireTimeout: 0 })
            }),
            notificationCardFactory.createObject(root, {
                notification: Object.assign({}, template, { urgency: 2, expireTimeout: -1 })
            })
        ]
        _notificationTimingReplace.start()
        _notificationTimingBefore.start()
        _notificationTimingAfter.start()
    }

    Timer {
        id: _notificationTimingReplace
        interval: 350
        onTriggered: {
            const cards = root._notificationTimingCards
            for (let i = 0; i < cards.length; i++) {
                const timer = root._notificationExpiryTimer(cards[i])
                root._check(timer !== null, "a notification exposes its expiry timer to the timing probe")
                if (!timer) continue
                const before = timer.interval
                // the 400 ms minimum display interval holds for this short sender timeout
                cards[i].timeoutStartedAt = Date.now()
                if (i < 2)
                    root._check(timer.interval === before,
                        "a replacement can leave its notification timeout interval unchanged")
            }
            root._check(!root._notificationExpiryTimer(cards[2]).running
                    && !root._notificationExpiryTimer(cards[3]).running,
                "updating persistent and default-critical notifications keeps their timers stopped")
        }
    }

    Timer {
        id: _notificationTimingBefore
        interval: 600
        onTriggered: {
            const cards = root._notificationTimingCards
            root._check(cards[0].enabled,
                "updated notification content survives the original expiry deadline")
            root._check(cards[1].enabled,
                "updating a hovered notification keeps its timeout paused")
            cards[1].stackHovered = false
        }
    }

    Timer {
        id: _notificationTimingAfter
        interval: 1200
        onTriggered: {
            const cards = root._notificationTimingCards
            root._check(!cards[0].enabled,
                "an updated notification expires at its replacement deadline")
            root._check(!cards[1].enabled,
                "a notification updated while hovered expires after the pointer leaves")
            root._check(cards[2].enabled && cards[3].enabled,
                "persistent and default-critical notifications survive a content update")
            for (let i = 0; i < cards.length; i++) cards[i].destroy()
            root._notificationTimingCards = []
            ShellSettings.reduceMotion = root._notificationTimingReduceWas
            Qt.callLater(root._runPersistenceGuardsProbe)
        }
    }

    function _runPersistenceGuardsProbe(): void {
        const externalText = '{"source":"external edit"}'
        const sessionText = '{"source":"session"}'
        persistenceGuardFixture.setText(externalText)
        const store = persistedFileFactory.createObject(root, {
            path: persistenceGuardFixture.path,
            serialize: function() { return sessionText }
        })
        store.writeAllowed = true
        // hold the fileChanged-to-loaded window: a shutdown flush must not beat the owner's read
        store._reloading = true
        store.flush(true)
        persistenceGuardFixture.reload()
        root._check(persistenceGuardFixture.text() === externalText,
            "a forced flush preserves an external edit whose reload is still pending")
        root._check(store.lastSavedText.length === 0,
            "a protected flush does not claim stale in-memory text was saved")
        store._reloading = false
        store.flush(true)
        persistenceGuardFixture.reload()
        root._check(persistenceGuardFixture.text().trim() === sessionText,
            "a forced flush still saves when the file has no unresolved reload")
        store._pendingForDir = true
        store.stop()
        root._check(!store.pending,
            "stopping a writer cancels a deferred directory-ready save")
        store.queue()
        root._check(store.pending, "a stopped writer accepts a new save request")
        store.stop()
        root._check(!store.pending, "stopping a writer also cancels its debounce timer")
        store.destroy()
        Qt.callLater(root._finish)
    }

    function _finish(): void {
        ShellSettings.dnd = true
        ShellSettings.showSeconds = !ShellSettings._defaults.showSeconds
        ShellSettings.resetToDefaults()
        root._check(ShellSettings.dnd === true
                && ShellSettings.showSeconds === ShellSettings._defaults.showSeconds,
            "restoring settings keeps the live Do Not Disturb choice")
        if (root._failures === 0)
            console.warn("PROBE-LOGIC passed " + root._checks + " checks")
        else
            console.warn("PROBE-LOGIC failed " + root._failures + "/" + root._checks + " checks")
        Qt.exit(root._failures === 0 ? 0 : 1)
    }

    Component.onCompleted: Qt.callLater(root._run)
}
