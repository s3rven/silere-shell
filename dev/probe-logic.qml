pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth as Bt
import Quickshell.Networking as Net
import Quickshell.Services.Mpris as Mp
import Quickshell.Services.SystemTray as St
import Quickshell.Services.UPower as Up
import "config"
import "config/PixelGeometry.js" as PixelGeometry
import "services/TimeZonePlace.js" as TimeZonePlace
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
import "modules/notifications/StackLayout.js" as StackLayout

// Small behavioral assertions for pure logic that a type-check or construction
// probe cannot validate. Keep this free of compositor and hardware dependencies.
ShellRoot {
    id: root

    property int _failures: 0
    property int _checks: 0
    property string _sentInlineReply: ""
    property int _confirmActions: 0
    property PwVolumeControl _volumeCancelProbe: null
    property bool _volumeCancelDone: false
    property bool _ignoredUpdatesDone: false
    property bool _helperUpdatesDone: false
    property bool _launchEnvDone: false
    property bool _zoneLinkDone: false
    property real _volumeCancelDeadline: 0

    QtObject {
        id: probeAnchor
        property real menuAnchorX: 42
    }
    // Controls that start hidden need a graphical parent for Qt's effective
    // visibility to update when the probe reveals them.
    Item { id: barFixtureHost }
    // a faded control fill, as on a slider or switch track
    Rectangle {
        id: glassFadeProbe
        visible: false
        color: Theme.menuControl
        ColorFade on color {}
    }
    // the same fill at the slower pace the OSD's colours keep
    Rectangle {
        id: slowFadeProbe
        visible: false
        color: Theme.menuControl
        ColorFade on color { id: slowFade; duration: Motion.medium }
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
    Component { id: drawerContentFactory; Item { implicitHeight: 100 } }
    Component {
        id: flickableFactory
        ShellFlickable { width: 100; height: 100; contentWidth: 100; contentHeight: 1000 }
    }
    Component {
        id: pageLoaderFactory
        PageLoader {
            layoutWidth: 332
            shown: true
            sourceComponent: PageShell { active: true; powerOpen: false }
        }
    }
    Component { id: settingsPageFactory; SettingsPage {} }
    // a page built while the menu is open: its loader's flags reach it before its build completes
    Component {
        id: openMenuPageLoaderFactory
        PageLoader {
            layoutWidth: 332
            shown: true
            pageActive: true
            animateOnCreate: true
            sourceComponent: PageShell {
                property bool built: false
                property real opaqueBeforeBuilt: 0
                onOpacityChanged: if (!built) opaqueBeforeBuilt = Math.max(opaqueBeforeBuilt, opacity)
                Component.onCompleted: built = true
            }
        }
    }
    Component {
        id: selectStubFactory
        QtObject {
            property bool folded: false
            function _setOpen(next: bool): void { if (!next) folded = true }
        }
    }
    Component { id: sliderTrackFactory; SliderTrack {} }
    Component { id: requestSetFactory; RequestSet {} }
    TestCase { id: discoveryClock; when: false }
    Component {
        id: keyboardFixtureFactory
        Window {
            id: fixture
            width: 420; height: 360; visible: true
            property int actions: 0
            property alias button: action
            property alias toggle: toggle
            property alias slider: slider
            property alias select: select
            property alias input: input
            ActionButton { id: action; label: "Keyboard action"; onTriggered: fixture.actions++ }
            ActionButton { y: 36; visible: false; label: "Hidden" }
            ActionButton { y: 72; enabled: false; label: "Disabled" }
            ToggleRow { id: toggle; y: 80; width: 400; label: "Keyboard toggle"; onToggled: nextChecked => checked = nextChecked }
            SliderTrack { id: slider; y: 140; width: 300; height: 24; value: 0.25; step: 0.25; onChanged: value => slider.value = value }
            SelectRow { id: select; y: 180; width: 400; label: "Keyboard picker"; model: [{value: 1, label: "First"}, {value: 2, label: "Second"}]; currentValue: 1; onChosen: value => currentValue = value }
            TestCase { id: input; when: false }
        }
    }
    Component { id: fadingRimFactory; FadingRim {} }
    Component {
        id: listKeyboardWindowFactory
        Window {
            id: fixture
            visible: true
            width: 320; height: 220
            property alias list: list
            property alias input: input
            property alias outside: outside
            property bool onlyFirst: false
            property var entries: [
                {label: "First", enabled: true}, {label: "Disabled", enabled: false},
                {label: "Busy", enabled: true, busy: true}, {label: "Last", enabled: true}
            ]
            ShellListView {
                id: list
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 160
                model: fixture.entries
                reuseItems: true
                cacheBuffer: 0
                delegate: InlineOptionRow {
                    required property int index
                    required property var modelData
                    width: list.width
                    label: modelData.label
                    enabled: modelData.enabled && (!fixture.onlyFirst || index === 0)
                    busy: modelData.busy === true
                }
            }
            ActionButton { id: outside; y: 180; label: "Outside list" }
            TestCase { id: input; when: false }
        }
    }
    Component {
        id: panelKeyboardWindowFactory
        Window {
            id: fixture
            visible: true
            width: 460; height: 1000
            property alias input: input
            property alias outside: outside
            property int escapes: 0
            Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut; onActivated: fixture.escapes++ }
            ActionButton { id: outside; y: 960; label: "Outside panel" }
            TestCase { id: input; when: false }
        }
    }
    Component {
        id: focusScrollWindowFactory
        Window {
            visible: true
            width: 380; height: 180
            property alias scroller: scroller
            property alias button: above
            property alias editor: editor.item
            property alias input: input
            ShellFlickable {
                id: scroller
                anchors.fill: parent
                contentWidth: width
                contentHeight: editor.y + editor.height + 24
                ActionButton { id: above; label: "Before editor" }
                Loader {
                    id: editor
                    y: 300
                    width: scroller.width
                    Component.onCompleted: setSource("modules/menu/settings/CommandEditor.qml", {
                        settingKey: "lockCommandCustom", label: "Lock command"
                    })
                }
            }
            TestCase { id: input; when: false }
        }
    }
    Component { id: perimeterFactory; PerimeterProgress { width: 320; height: 100 } }
    Component {
        id: confirmButtonFactory
        ConfirmButton { label: "Probe confirm"; onConfirmed: root._confirmActions++ }
    }
    Component { id: gradientSliderFactory; GradientSlider {} }
    Component { id: toggleRowFactory; ToggleRow { width: 320; label: "Probe toggle" } }
    Component {
        id: foldCardFactory
        SettingsCard {
            width: 320
            property alias head: _foldHead
            property alias fold: _foldSection
            property alias tail: _foldTail
            ToggleRow { id: _foldHead; label: "Probe head" }
            CollapsibleSection { id: _foldSection; ToggleRow { id: _foldTail; label: "Probe tail" } }
        }
    }
    Component { id: knobSwitchFactory; ToggleSwitch {} }
    Component { id: foldDisclosureFactory; Item { property real h: 0; property alias disclosure: _foldDisclosure; Disclosure on h { id: _foldDisclosure } } }
    Component { id: sliderRowFactory; SliderRow { width: 320; label: "Probe slider"; glyph: "󰕰" } }
    Component {
        id: insetScrollFactory
        Flickable {
            property real revealTopInset: 40
            property alias target: _insetTarget
            property alias pinnedTarget: _insetPinned
            width: 200; height: 100; contentWidth: 200; contentHeight: 600
            Item { id: _insetTarget; y: 300; width: 200; height: 20; activeFocusOnTab: true; FocusScroll {} }
            Item {
                readonly property bool pinnedToViewport: true
                y: 500; width: 200; height: 20
                Item { id: _insetPinned; width: 200; height: 20; activeFocusOnTab: true; FocusScroll {} }
            }
        }
    }
    Component { id: systemWidgetFactory; SystemWidget {} }
    Component { id: controlRowFactory; ControlRow { width: 320; title: "Probe control" } }
    Component { id: inlineOptionFactory; InlineOptionRow { width: 320; label: "Probe option" } }
    Component { id: updateStatusFactory; UpdateStatusCard { width: 320; title: "Probe update" } }
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
    Component { id: mediaButtonFactory; MediaButton { available: true; accessibleName: "Media action" } }
    Component {
        id: bluetoothDeviceFixture
        QtObject {
            property string address: "__silere_pairing_probe__"
            property string name: "Pairing probe"
            property string deviceName: name
            property string icon: ""
            property bool batteryAvailable: false
            property real battery: 0
            property bool paired: false
            property bool trusted: false
            property bool connected: false
            property bool pairing: true
            property int state: Bt.BluetoothDeviceState.Connecting
        }
    }
    Component {
        id: scrollListFactory
        ShellListView {
            width: 100; height: 96
            model: 20
            delegate: Rectangle { width: 100; height: 24 }
        }
    }
    Component { id: smoothGlideFactory; SmoothGlide { target: 0 } }
    Component { id: glideHostFactory; Item { property SmoothGlide glide: SmoothGlide { target: 0; duration: 240; holdsSnaps: true } } }
    Component {
        id: pixelSnapFactory
        Item {
            id: _snapFixture
            readonly property PixelSnap snap: _snapFixtureOffset
            x: 10.3
            width: 10; height: 10
            transform: PixelSnap { id: _snapFixtureOffset; item: _snapFixture; dpr: 1.25 }
        }
    }
    Component { id: mediaVisualizerFactory; MediaVisualizer { presentationActive: false } }
    Component { id: waveLineFactory; WaveLine { width: 200; height: 16; value: 0.75; flowing: true } }
    Component { id: volumeControlFactory; PwVolumeControl {} }
    Component { id: boundedProcessFactory; BoundedProcess {} }
    Component { id: persistedFileFactory; PersistedFile { writeAllowed: false } }
    Component { id: niriBackendFactory; CompositorNiri {} }
    Component {
        id: notificationSlotFactory
        QtObject { property real height: 0; property bool shouldLoad: true }
    }
    QtObject {
        id: stackLayoutProbe
        property var slots: []
        readonly property int count: slots.length
        property bool newestFirst: true
        readonly property var layout: StackLayout.measure(stackLayoutProbe, newestFirst)
        function itemAt(index: int): var { return slots[index] }
    }
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
        id: barFlexibleFactory
        Item {
            property bool show: true
            readonly property bool layoutVisible: implicitWidth > 0.5
            property real preferredWidth: 180
            property real layoutWidthLimit: -1
            implicitWidth: layoutWidthLimit >= 0 ? Math.min(preferredWidth, layoutWidthLimit) : preferredWidth
            implicitHeight: 24
        }
    }
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
    Component { id: stableObjectListFactory; StableObjectList {} }
    Component { id: stableListMemberFactory; QtObject { property bool playing: false } }
    Component {
        id: stableListObserverFactory
        QtObject {
            required property var model
            readonly property int playingCount: model.values.filter(item => item.playing).length
        }
    }
    Component { id: actionButtonFactory; ActionButton { label: "Probe action" } }
    Component { id: iconButtonFactory; IconButton { accessibleName: "Probe icon" } }
    Component { id: workspaceButtonFactory; WorkspaceButton {} }
    Component { id: workspaceUrgentTickFactory; WorkspaceUrgentTick {} }
    Component {
        id: barPointerFactory
        Window {
            id: fixture
            visible: true
            width: 420; height: 170
            color: Theme.panel
            property alias cell: cell
            property alias pill: hoverPill
            property alias input: inputDriver
            property alias tray: pointerTray
            property alias media: pointerMedia
            property var reports: []
            WorkspaceButton {
                id: cell
                x: 12; y: 20
                wsId: 2; monitorReady: true; active: false; occupied: true
                urgent: false; apps: []; compact: false; iconSize: 12
                cellWidth: 26; rowHeight: 24; barActive: true
                initialized: true; paging: false; markerCovers: true
                onHoverReported: (id, on) => fixture.reports = fixture.reports.concat(id + ":" + on)
            }
            Pill {
                id: hoverPill
                x: 80; y: 20
                width: implicitWidth; height: 24
                glyph: "V"; text: "42%"; interactive: true
                wheelKey: "probe:hover-pill"
            }
            TrayWidget { id: pointerTray; x: 170; y: 12; height: 48; trayModel: [] }
            MediaWidget { id: pointerMedia; x: 12; y: 110; height: 36; screen: null; layoutWidthLimit: 180 }
            TestCase { id: inputDriver; when: false }
        }
    }
    property var _barPointerWindow: null
    // the clock in a centred zone, the layout where its resize moves its middle least and its anchor most
    Component {
        id: clockAnchorFactory
        Window {
            visible: true
            width: 600; height: 60
            color: Theme.panel
            property alias clock: anchorClock
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                Item { width: 40; height: 20 }
                Clock { id: anchorClock; screen: null }
            }
        }
    }
    property var _clockAnchorWindow: null
    property int _clockAnchorStep: 0
    property bool _clockAnchorReduceWas: false
    property bool _clockAnchorDateWas: false
    Component {
        id: settingsSearchWindowFactory
        Window {
            visible: true
            width: 380; height: 300
            color: Theme.panel
            property alias search: searchLoader.item
            property alias input: inputDriver
            Loader {
                id: searchLoader
                width: parent.width
                source: "modules/menu/settings/SettingsSearch.qml"
                onLoaded: item.sectionChosen.connect(section => MenuState.setSettingsSection(section))
            }
            TestCase { id: inputDriver; when: false }
        }
    }
    Component {
        id: lockEditorWindowFactory
        Window {
            visible: true
            width: 380; height: 250
            color: Theme.panel
            property alias editor: editorLoader.item
            property alias input: inputDriver
            Loader {
                id: editorLoader
                width: parent.width
                source: "modules/menu/settings/LockCommandEditor.qml"
            }
            TestCase { id: inputDriver; when: false }
        }
    }
    Component { id: pillFactory; Pill { visible: true; glyph: "a" } }
    Component { id: detailPillFactory; Pill { readonly property bool layoutVisible: true; glyph: "a"; text: expanded ? "45% · A long detail" : "45%" } }
    Component { id: holdingWidgetFactory; Item { property bool holdOpen: false; readonly property bool layoutVisible: true; implicitWidth: 20; height: 36 } }
    Component { id: foldingWidgetFactory; Item { property bool show: true; property bool fading: false; readonly property bool layoutVisible: show || fading; implicitWidth: 20; height: 36 } }
    Component { id: rollingTextFactory; RollingText { visible: true; text: "one" } }
    Component { id: collapsingTextFactory; CollapsingText { animate: false; tabularDigits: true; reserveText: ":00" } }
    Component { id: clockFactory; Clock { screen: null } }
    Component { id: mediaWidgetFactory; MediaWidget { screen: null; height: 36 } }
    Component { id: updatesWidgetFactory; UpdatesWidget { screen: null } }
    Component { id: shellUpdateWidgetFactory; ShellUpdateWidget { screen: null } }
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
            property int wheelDelta: 0
            property int horizontalWheelDelta: 0
            function activate(): void { activations++ }
            function secondaryActivate(): void {}
            function scroll(delta: int, horizontal: bool): void {
                if (horizontal) horizontalWheelDelta += delta
                else wheelDelta += delta
            }
        }
    }
    Component {
        id: trayWidgetFactory
        TrayWidget { trayModel: root._trayProbeItems; height: 36 }
    }
    Component { id: shellIconFactory; ShellIcon {} }
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
    Component { id: motionHostFactory; Item { property real v: 0; MotionBehavior on v { NumberAnimation { duration: 2000 } } } }
    Component {
        id: windowTitleFactory
        WindowTitle {
            screen: Quickshell.screens[0] ?? null
            barActive: false
        }
    }
    Component { id: workspaceStripFactory; Workspaces { screen: null } }
    Component {
        id: workspaceSlotModelFactory
        WorkspaceSlotModel {
            monitorName: "DP-1"
            activeId: 1
            effectiveWsCount: 4
            perOutputWorkspaceIds: false
            workspaces: []
        }
    }
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

    Component {
        id: notificationKeyboardFactory
        Window {
            id: fixture
            visible: true
            width: 400; height: 500
            property int timeout: 300
            property int dismissed: 0
            property int actions: 0
            property alias card: card
            property alias outside: outside
            property alias input: input
            NotificationCard {
                id: card
                x: 20; y: 20; width: 360
                notification: ({
                    actions: [{ identifier: "open", text: "Open details", invoke: function() { fixture.actions++ } }],
                    hints: ({}), appIcon: "", image: "", appName: "Keyboard probe",
                    desktopEntry: "", summary: "Read this notification",
                    body: "First line\nSecond line\nThird line\nFourth line\nFifth line",
                    urgency: 1, expireTimeout: fixture.timeout, resident: false, transient: false,
                    hasInlineReply: true, inlineReplyPlaceholder: "Reply",
                    sendInlineReply: function(text) {}
                })
                notifId: 2147483643
                createdAt: Date.now()
                onDismissRequested: fixture.dismissed++
            }
            ActionButton { id: outside; y: 450; label: "Outside notification" }
            TestCase { id: input; when: false }
        }
    }

    Component {
        id: notificationIconWindowFactory
        FloatingWindow {
            visible: true
            implicitWidth: 400
            implicitHeight: 560
            property alias card: iconCard
            property alias input: iconInput
            TestCase { id: iconInput; when: false }
            NotificationCard {
                id: iconCard
                width: 320
                notification: ({
                    actions: [], hints: ({}), appIcon: "/usr/share/pixmaps/silere-probe-absent.png",
                    image: "", appName: "silere-probe-absent", desktopEntry: "", summary: "Icon probe",
                    body: "", urgency: 1, expireTimeout: 0, resident: false, transient: false,
                    hasInlineReply: false
                })
                notifId: 2147483642
                createdAt: Date.now()
            }
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
        for (const factory of [actionButtonFactory, iconButtonFactory, mediaButtonFactory]) {
            const visibilityHost = Qt.createQmlObject("import QtQuick; Item {}", barFixtureHost)
            const button = factory.createObject(visibilityHost)
            let buttonActions = 0
            button.triggered.connect(() => buttonActions++)
            button.Accessible.pressAction()
            root._check(buttonActions === 1 && button.Accessible.focusable,
                "a visible " + button.accessibleName + " accepts its accessible action")
            button.visible = false
            button.activate()
            button.Accessible.pressAction()
            root._check(buttonActions === 1 && !button.Accessible.focusable,
                "a hidden " + button.accessibleName + " rejects direct and accessible activation")
            button.visible = true
            visibilityHost.visible = false
            button.Accessible.pressAction()
            root._check(buttonActions === 1 && !button.Accessible.focusable,
                "hiding a parent also disables its " + button.accessibleName)
            visibilityHost.visible = true
            button.enabled = false
            button.Accessible.pressAction()
            root._check(buttonActions === 1, "a disabled " + button.accessibleName + " rejects activation")
            button.enabled = true
            button.Accessible.pressAction()
            root._check(buttonActions === 2 && button.Accessible.focusable,
                "a restored " + button.accessibleName + " becomes available again")
            visibilityHost.destroy()
        }
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
        toggle.dependsNote = "Install the missing helper to enable this setting"
        const dependencyMotionWas = ShellSettings.reduceMotion
        ShellSettings.reduceMotion = true
        const dependency = root._findTrayNode(toggle, item => item.text === toggle._detailText)
        root._check(toggle.opacity === 1 && dependency !== null
                && dependency.opacity === 1 && !toggle._canToggle,
            "an unavailable setting keeps its dependency explanation readable without enabling the control")
        root._check(dependency.maximumLineCount > 2,
            "dependency explanations can wrap beyond two lines instead of losing their reason")
        ShellSettings.reduceMotion = dependencyMotionWas
        toggle.available = true
        const togglePage = Qt.createQmlObject("import QtQuick\nItem {}", root)
        const noteRow = toggleRowFactory.createObject(togglePage, { dependsNote: "Needs a helper" })
        togglePage.enabled = false
        root._check(!noteRow.enabled && !noteRow._showDependsNote,
            "a page disabled for its transition does not flash a row's dependency note")
        togglePage.enabled = true
        noteRow.blocked = true
        root._check(!noteRow.enabled && noteRow._showDependsNote,
            "a row that refuses on its own explains why")
        togglePage.destroy()
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
        const optionMotionWas = ShellSettings.reduceMotion
        ShellSettings.reduceMotion = true
        option.interactive = true
        option.busy = true
        option.trigger()
        root._check(option.opacity === 1 && selections === 1,
            "a busy inline row keeps progress readable without accepting another action")
        option.enabled = false
        root._check(option.opacity === Theme.disabledOpacity,
            "a busy row still respects a disabled parent control")
        ShellSettings.reduceMotion = optionMotionWas
        option.destroy()

        const swatches = swatchRowFactory.createObject(barFixtureHost)
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
            swatches.enabled = true
            swatches.visible = false
            swatch.Accessible.pressAction()
            root._check(picks === 1 && !swatch.Accessible.focusable,
                "hidden accent swatches reject accessibility actions")
            swatches.visible = true
            swatch.Accessible.pressAction()
            root._check(picks === 2 && swatches.activeIndex === 0,
                "a revealed accent swatch becomes interactive again")
            const reduceWas = ShellSettings.reduceMotion
            ShellSettings.reduceMotion = false
            swatches.options = [{name: "A"}, {name: "B"}, {name: "C"}]
            const spring = swatches.resources.find(item => item._velocity !== undefined)
            swatches.activeIndex = 2
            root._check(spring && spring._tick.running,
                "an active swatch selection starts its frame driver")
            swatches.hoveredIndex = 2
            swatches.visible = false
            root._check(spring && !spring._tick.running && spring.value === spring.target
                    && swatches.hoveredIndex === -1,
                "hiding colour settings stops its selection frames and clears hover state")
            swatches.visible = true
            swatches.activeIndex = 0
            swatches.enabled = false
            root._check(spring && !spring._tick.running,
                "disabling a swatch group retires an in-flight selection spring")
            swatches.options = [{name: "A"}]
            swatches.activeIndex = 5
            root._check(swatches._slot === 0 && spring && spring.target === 0,
                "a removed swatch cannot leave its selection beyond the remaining options")
            ShellSettings.reduceMotion = reduceWas
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

        // Home builds this row on every open with its options closed; their controls wait for the first look
        const chipsIn = item => root._findTrayNode(item, node => node.currentValue !== undefined
            && node.model !== undefined && node.chosen !== undefined)
        const volumeReduceWas = ShellSettings.reduceMotion
        ShellSettings.reduceMotion = true
        const volumeRow = Qt.createComponent(Qt.resolvedUrl("modules/menu/VolumeRow.qml")).createObject(barFixtureHost, { width: 320 })
        const closedChips = chipsIn(volumeRow)
        volumeRow.open = true
        const openChips = chipsIn(volumeRow)
        volumeRow.open = false
        root._check(volumeRow !== null && closedChips === null && openChips !== null && chipsIn(volumeRow) === null,
            "the volume row builds its options only while they show")
        volumeRow.destroy()
        ShellSettings.reduceMotion = volumeReduceWas

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
        let levelChanges = 0
        let muteActions = 0
        quick.glyphClickable = true
        quick.glyphClicked.connect(() => { muteActions++; quick.muted = !quick.muted })
        const muteButton = root._findTrayNode(quick, item => item.Accessible.name === "Mute audio")
        root._check(muteButton !== null, "a quick slider exposes its named mute action")
        if (muteButton) {
            muteButton.Accessible.pressAction()
            root._check(muteActions === 1 && quick.muted
                    && muteButton.Accessible.name === "Unmute audio",
                "muting a device changes its accessible action to unmute")
            muteButton.Accessible.pressAction()
            root._check(muteActions === 2 && !quick.muted
                    && muteButton.Accessible.name === "Mute audio",
                "unmuting restores the mute action name")
            quick.enabled = false
            muteButton.Accessible.pressAction()
            quick.enabled = true
            quick.glyphClickable = false
            muteButton.Accessible.pressAction()
            root._check(muteActions === 2,
                "disabled or unavailable audio still rejects accessible mute actions")
        }
        quick.moved.connect(() => { levelChanges++ })
        quick.adjustable = false
        quick.expandable = true
        const level = root._findTrayNode(quick, item => typeof item.nudge === "function")
        root._check(level !== null, "a quick slider exposes its level control")
        if (level) {
            level.nudge(1, 1)
            root._check(!level.interactive && levelChanges === 0,
                "an unavailable device rejects level changes")
            quick._requestExpand()
            root._check(expansions === 2,
                "an unavailable level still permits opening its device picker")
            quick.adjustable = true
            level.nudge(1, 1)
            root._check(level.interactive && levelChanges === 1,
                "a recovered device immediately accepts level changes again")
        }
        quick.destroy()
    }

    function _checkNotificationKeyboard(): void {
        const motionWas = ShellSettings.reduceMotion
        ShellSettings.reduceMotion = true
        const fixture = notificationKeyboardFactory.createObject(root)
        fixture.requestActivate()
        fixture.input.wait(60)
        fixture.input.mouseMove(fixture.outside, 5, 5)
        const menuOpenWas = MenuState.open
        MenuState.open = false
        const runningBare = !fixture.card._paused
        MenuState.open = true
        const heldUnderPanel = fixture.card._paused
        MenuState.open = false
        root._check(runningBare && heldUnderPanel && !fixture.card._paused,
            "a notification's timeout waits while a panel is open and runs again once it closes")
        MenuState.open = menuOpenWas
        fixture.card.forceActiveFocus(Qt.TabFocusReason)
        fixture.input.wait(20)
        root._check(fixture.card.activeFocus && fixture.card._paused && fixture.card._expanded,
            "keyboard focus pauses and expands a notification without pointer hover")
        fixture.input.wait(460)
        root._check(fixture.card.enabled && fixture.dismissed === 0,
            "a keyboard-focused notification survives its original expiry deadline")
        const action = root._findTrayNode(fixture.card, item => item.Accessible.name === "Open details")
        if (action) action.forceActiveFocus(Qt.TabFocusReason)
        fixture.input.wait(20)
        root._check(action && action.activeFocus && fixture.card._paused && fixture.card._expanded,
            "focus on a notification action keeps its card readable and paused")
        const otherWindow = Qt.createQmlObject('import QtQuick; Window { visible: true; width: 100; height: 100 }', root)
        otherWindow.requestActivate()
        fixture.input.wait(40)
        root._check(!fixture.card._paused,
            "a notification stops holding its timeout when another window takes focus")
        otherWindow.close()
        otherWindow.destroy()
        fixture.requestActivate()
        fixture.input.wait(20)
        fixture.outside.forceActiveFocus(Qt.TabFocusReason)
        fixture.input.wait(300)
        root._check(!fixture.card._paused && !fixture.card._expanded && fixture.card.enabled,
            "leaving notification focus collapses it and resumes its remaining timeout")
        fixture.input.wait(160)
        root._check(!fixture.card.enabled && fixture.dismissed === 1
                && !root._notificationExpiryTimer(fixture.card).running,
            "a notification expires once focus leaves and its timeout finishes")
        fixture.close()
        fixture.destroy()

        const reply = notificationKeyboardFactory.createObject(root, { timeout: 0 })
        reply.requestActivate()
        reply.input.wait(60)
        reply.card.beginReply()
        reply.card.focusReplyInput()
        const field = root._findTrayNode(reply.card, item => item.maximumLength === 2048)
        if (field) { field.text = "reply"; field.cursorPosition = 0 }
        reply.input.keyClick(Qt.Key_Delete)
        root._check(field && field.text === "eply" && reply.card.enabled && reply.card._replyOpen,
            "Delete edits an inline reply without dismissing its notification")
        reply.card.cancelReply()
        reply.card.forceActiveFocus(Qt.TabFocusReason)
        reply.input.keyClick(Qt.Key_Delete)
        root._check(!reply.card.enabled && reply.dismissed === 1 && reply.actions === 0,
            "Delete dismisses a focused notification without running an action")
        reply.close()
        reply.destroy()

        const hidden = notificationKeyboardFactory.createObject(root, { timeout: 0 })
        let replyHeld = false
        let sentReplies = 0
        hidden.card.replyFocusRequested.connect((owner, active) => { replyHeld = active })
        const hiddenNote = Object.assign({}, hidden.card.notification, {
            resident: true, sendInlineReply: function(text) { sentReplies++ }
        })
        hidden.card.notification = hiddenNote
        hidden.card.beginReply()
        const hiddenField = root._findTrayNode(hidden.card, item => item.maximumLength === 2048)
        if (hiddenField) hiddenField.text = "Unsent draft"
        hidden.card.visible = false
        root._check(!hidden.card._replyOpen && !replyHeld && hiddenField && hiddenField.text.length === 0,
            "hiding a notification cancels its reply and releases keyboard ownership")
        hidden.card.cancelReply()
        hidden.card.beginReply()
        root._check(!hidden.card._replyOpen && !replyHeld,
            "a hidden notification cannot reopen its reply field")
        hidden.card.cancelReply()
        root._check(!hidden.card._sendInlineReply("Hidden reply") && sentReplies === 0,
            "a retained reply action cannot send from a hidden notification")
        hidden.card.invokeAction(hiddenNote.actions[0])
        root._check(hidden.actions === 0,
            "a retained notification action cannot run while its card is hidden")
        const actionsBeforeReveal = hidden.actions
        hidden.card.visible = true
        hidden.card.invokeAction(hiddenNote.actions[0])
        root._check(hidden.actions === actionsBeforeReveal + 1 && hidden.card.enabled,
            "a visible resident notification still runs its action and stays open")
        hidden.card.beginReply()
        hidden.visible = false
        hidden.input.wait(20)
        root._check(!hidden.card._replyOpen && !replyHeld,
            "unmapping a notification window releases reply ownership even when its card stays visible")
        hidden.card.cancelReply()
        const actionsBeforeUnmapped = hidden.actions
        hidden.card.beginReply()
        hidden.card.invokeAction(hiddenNote.actions[0])
        root._check(!hidden.card._replyOpen && hidden.actions === actionsBeforeUnmapped,
            "an unmapped notification window rejects retained reply and action callbacks")
        hidden.visible = true
        hidden.card.beginReply()
        hidden.card.enabled = false
        root._check(!hidden.card._replyOpen && !replyHeld,
            "disabling a notification also cancels its reply ownership")
        hidden.close()
        hidden.destroy()
        ShellSettings.reduceMotion = motionWas
    }

    function _checkHiddenBarControls(): void {
        const reduceWas = ShellSettings.reduceMotion
        const clockWas = ShellSettings.barShowClock
        const mediaWas = ShellSettings.barShowMedia
        const shownWas = Media.shown
        const shiftWas = ShellSettings.workspaceShift
        const urgentWas = ShellSettings.wsUrgentPulse
        ShellSettings.reduceMotion = false
        ShellSettings.barShowClock = true
        ShellSettings.barShowMedia = true
        ShellSettings.workspaceShift = true
        ShellSettings.wsUrgentPulse = true
        Media.shown = true
        CalendarState.close()
        const host = Qt.createQmlObject("import QtQuick; Item {}", barFixtureHost)
        const clock = clockFactory.createObject(host)
        const media = mediaWidgetFactory.createObject(host)
        const marker = workspaceMarkerFactory.createObject(host)
        const urgentTick = workspaceUrgentTickFactory.createObject(host, {
            liveId: 2, rowHeight: 24, barActive: true
        })
        const workspace = workspaceButtonFactory.createObject(host, {
            wsId: 2, monitorReady: true, active: false, occupied: false,
            urgent: false, apps: [], compact: false, iconSize: 12,
            cellWidth: 26, rowHeight: 24, barActive: true,
            initialized: true, paging: false, markerCovers: true
        })
        let switches = 0
        workspace.activateRequested.connect(() => switches++)
        clock.Accessible.pressAction()
        workspace.Accessible.pressAction()
        root._check(CalendarState.open && switches === 1 && media.Accessible.focusable,
            "visible bar widgets expose their accessible actions")
        CalendarState.close()
        clock._datePeek = true
        const clip = root._findTrayNode(media, item => item.preferredMaxW !== undefined)
        clip.opacity = 0.4
        clip._shown = "Previous track"
        workspace.playMarkerPass(0)
        marker.pulse()
        marker.targetX = 80
        root._check(workspace.markerPassActive && media._animatable,
            "visible bar widgets allow their transient motion")
        root._check(marker._travel.running && urgentTick._motionActive,
            "visible workspace markers allow travel and urgency motion")
        host.visible = false
        clock.Accessible.pressAction()
        clock._openCalendar()
        workspace.Accessible.pressAction()
        workspace._activate()
        root._check(!CalendarState.open && !clock._datePeek && !clock.Accessible.focusable,
            "hiding the clock's parent clears date peek and rejects retained calendar actions")
        root._check(switches === 1 && !workspace.Accessible.focusable,
            "hiding the workspace strip rejects retained workspace actions")
        root._check(!workspace.markerPassActive && workspace._markerPassCover === 0,
            "hiding a workspace cell retires its marker hand-off")
        workspace.playMarkerPass(0)
        root._check(!workspace.markerPassActive,
            "a hidden workspace cannot start a new marker hand-off")
        workspace.playNotificationPulse(true)
        workspace.urgent = true
        const urgentFx = root._findTrayNode(workspace, item => item.motionActive !== undefined)
        root._check(!workspace._notifPulseLoaded && urgentFx && !urgentFx.motionActive,
            "a hidden workspace runs neither notification nor urgency pulses")
        if (urgentFx) urgentFx.settled = true
        workspace.wsId = 3
        root._check(urgentFx && !urgentFx.settled,
            "a workspace slot paged onto another urgent workspace pulses for it again")
        workspace.wsId = 2
        root._check(!marker._travel.running && marker._glint === -1.15 && marker._tapScale === 1
                && !urgentTick._motionActive && urgentTick._pulse === 1,
            "hiding the workspace strip settles its marker and urgency indicator")
        marker.pulse()
        root._check(!marker._motionAllowed() && marker._tapScale === 1,
            "a hidden workspace marker rejects a retained pulse request")
        root._check(!media.Accessible.focusable && !media._canInteract && !media._animatable
                && clip.opacity === 1 && clip._shown === Media.label,
            "hiding media controls disables input and settles their label transition")
        root._check(!clock._animatable,
            "a hidden clock disables its readout animations")
        host.visible = true
        clock.Accessible.pressAction()
        workspace.Accessible.pressAction()
        root._check(CalendarState.open && switches === 2 && media.Accessible.focusable
                && media._animatable && clock._animatable,
            "revealing the bar restores its controls and motion gates")
        CalendarState.close()
        host.destroy()
        Media.shown = shownWas
        ShellSettings.workspaceShift = shiftWas
        ShellSettings.wsUrgentPulse = urgentWas
        ShellSettings.barShowMedia = mediaWas
        ShellSettings.barShowClock = clockWas
        ShellSettings.reduceMotion = reduceWas
    }

    function _checkWifiScanners(): void {
        let writes = 0
        const adapter = () => {
            let scanning = false
            return {
                type: Net.DeviceType.Wifi,
                get scannerEnabled() { return scanning },
                set scannerEnabled(value) { scanning = value; writes++ }
            }
        }
        const first = adapter()
        const wired = { type: Net.DeviceType.Wired, scannerEnabled: false }
        Network._applyScannerState([null, first, wired], true)
        root._check(first.scannerEnabled && !wired.scannerEnabled && writes === 1,
            "Wi-Fi discovery enables only Wi-Fi adapters")
        Network._applyScannerState([first, wired], true)
        root._check(writes === 1,
            "re-enumerating an unchanged adapter avoids a repeated scanner write")
        const second = adapter()
        Network._applyScannerState([first, second, wired], true)
        root._check(first.scannerEnabled && second.scannerEnabled && writes === 2,
            "a second Wi-Fi adapter joins ongoing discovery without restarting the first")
        const replacement = adapter()
        Network._applyScannerState([replacement, second], true)
        root._check(replacement.scannerEnabled && second.scannerEnabled && writes === 3,
            "a replacement Wi-Fi adapter inherits ongoing discovery")
        Network._applyScannerState([replacement, second, wired], false)
        root._check(!replacement.scannerEnabled && !second.scannerEnabled && writes === 5,
            "closing discovery stops every current Wi-Fi adapter")
        Network._applyScannerState([replacement, second], false)
        const closed = adapter()
        Network._applyScannerState([replacement, second, closed], false)
        root._check(writes === 5 && !closed.scannerEnabled,
            "enumeration with discovery closed leaves scanners stopped without writes")
    }

    function _checkDiscoveryRequests(): void {
        const requests = requestSetFactory.createObject(root)
        const first = {}
        const second = {}
        root._check(!requests.active && !requests.set(null, true) && !requests.set(first, false),
            "discovery demand ignores missing owners and unmatched releases")
        requests.set(first, true)
        root._check(requests.active && !requests.set(first, true),
            "a repeated open from one list does not add a second request")
        requests.set(second, true)
        requests.set(first, false)
        requests.set(first, false)
        root._check(requests.active,
            "closing or destroying an old list cannot release a replacement list's request")
        requests.set(second, false)
        root._check(!requests.active, "discovery demand stops when its last list releases it")
        requests.destroy()

        const scannerWas = Network._scannerWanted
        const bluetoothScanWas = Bluetooth._scanRequested
        const bluetoothErrorWas = Bluetooth.errorAddr
        const bluetoothKindWas = Bluetooth.errorKind
        const wifiErrorWas = Network.wifiError
        const wifiReasonWas = Network.wifiErrorReason
        for (const kind of ["Wifi", "Bluetooth", "Vpn"]) {
            const component = Qt.createComponent("modules/menu/" + kind + "List.qml")
            const oldList = component.status === Component.Ready
                ? component.createObject(barFixtureHost, { width: 320, open: false }) : null
            const newList = component.status === Component.Ready
                ? component.createObject(barFixtureHost, { width: 320, open: false }) : null
            root._check(oldList !== null && newList !== null, kind + " list handover fixtures build")
            if (oldList && newList) {
                // Seed demand without enabling real radios; exercise each list's actual teardown.
                const demand = kind === "Wifi" ? Network._scanRequests
                    : kind === "Bluetooth" ? Bluetooth._scanRequests : Vpn._requests
                demand.set(oldList, true)
                demand.set(newList, true)
                if (kind === "Wifi") Network._scannerWanted = true
                if (kind === "Bluetooth") {
                    Bluetooth._scanRequested = true
                    Bluetooth.errorAddr = "__handover__"
                    Bluetooth.errorKind = "pair"
                }
                oldList.destroy()
                discoveryClock.wait(1)
                root._check(demand.active
                        && (kind !== "Wifi" || Network._scannerWanted)
                        && (kind !== "Bluetooth" || (Bluetooth._scanRequested && Bluetooth.errorAddr === "__handover__"))
                        && (kind !== "Vpn" || Vpn.requested),
                    kind + " list destruction preserves its replacement's updates and state")
                newList.destroy()
                discoveryClock.wait(1)
                root._check(!demand.active
                        && (kind !== "Wifi" || !Network._scannerWanted)
                        && (kind !== "Bluetooth" || (!Bluetooth._scanRequested && Bluetooth.errorAddr === ""))
                        && (kind !== "Vpn" || !Vpn.requested),
                    kind + " list destruction releases the final request")
            } else {
                if (oldList) oldList.destroy()
                if (newList) newList.destroy()
            }
            component.destroy()
        }
        Network._scannerWanted = scannerWas
        Bluetooth._scanRequested = bluetoothScanWas
        Bluetooth.errorAddr = bluetoothErrorWas
        Bluetooth.errorKind = bluetoothKindWas
        Network.wifiError = wifiErrorWas
        Network.wifiErrorReason = wifiReasonWas
    }

    function _checkSandboxWritesNoDevice(): void {
        // the probe runs as every test does, sandboxed and not a preview: nothing it drives may reach the desk's hardware
        root._check(Quickshell.env("SILERE_SANDBOX") === "1" && !SystemTools.preview && !SystemTools.writesDevices,
            "a sandboxed test shell writes no device: brightness, Wi-Fi, Bluetooth and power mode refuse its changes")
    }

    function _checkOsdOverHome(): void {
        const was = { armed: OsdBarState._armed, open: MenuState.open, tab: MenuState.activeTab,
            x: MenuState.anchorX, screen: MenuState.triggerScreen, anchor: MenuState.anchorSource }
        const screen = Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        OsdBarState._armed = true
        OsdBarState._clearEntries()
        MenuState.selectTab(MenuState.homeTab)
        MenuState.openAt(100, screen, null)
        const onHome = MenuState.homeActive
        OsdBarState.show("volume", "", 0.5, "50%", false)
        OsdBarState.show("microphone", "", 0.5, "Microphone muted", true)
        root._check(onHome && OsdBarState._entryIndex("volume") < 0 && OsdBarState._entryIndex("microphone") >= 0,
            "over Home the volume OSD stays quiet beside its own slider, while a microphone mute, whose row is folded away, still answers")
        OsdBarState._clearEntries()
        MenuState.close()
        MenuState.selectTab(was.tab)
        if (was.open) MenuState.openAt(was.x, was.screen, was.anchor)
        OsdBarState._armed = was.armed
    }

    function _checkBrightnessOsdUnattended(): void {
        const was = { device: Brightness._device, max: Brightness.maxBrightness,
            level: Brightness.currentBrightness, ready: Brightness.ready, armed: OsdBarState._armed }
        const shown = level => {
            OsdBarState._clearEntries()
            Brightness.currentBrightness = level
            return OsdBarState._entryIndex("brightness") >= 0
        }
        OsdBarState._armed = true
        Brightness._device = "__silere_osd_probe__"
        Brightness.maxBrightness = 100
        Brightness.currentBrightness = 50
        Brightness.ready = true
        Idle._returned.stop()
        const attended = shown(60)
        Idle._returned.restart()
        const returning = shown(30)
        Idle._returned.stop()
        root._check(attended && !returning && shown(40),
            "a backlight restored as the user comes back shows no OSD, one changed while they are here does")
        OsdBarState._clearEntries()
        Brightness._device = was.device
        Brightness.maxBrightness = was.max
        Brightness.currentBrightness = was.level
        Brightness.ready = was.ready
        OsdBarState._armed = was.armed
    }

    function _checkOsdProfileHold(): void {
        const pendingWas = Audio._out.pendingApply
        OsdBarState._profileHoldTimer.restart()
        OsdBarState._heldVolumeWrite = false
        OsdBarState._volumeUpdateQueued = false
        OsdBarState._releaseProfileHold()
        const quiet = !OsdBarState._volumeUpdateQueued
        Audio._out.pendingApply = false
        Audio._out.pendingApply = true
        const held = OsdBarState._heldVolumeWrite
        OsdBarState._volumeUpdateQueued = false
        OsdBarState._releaseProfileHold()
        root._check(quiet && held && OsdBarState._volumeUpdateQueued && !OsdBarState._heldVolumeWrite,
            "a volume set during the hold after a headset mode change is shown when the hold ends, and a hold with none shows nothing")
        OsdBarState._profileHoldTimer.stop()
        OsdBarState._volumeUpdateQueued = false
        Audio._out.pendingApply = pendingWas
    }

    function _checkOsdLifetime(): void {
        const timeoutWas = ShellSettings.osdTimeout
        for (const timeout of [500, 2000, 10000]) {
            ShellSettings.osdTimeout = timeout
            OsdBarState._clearEntries()
            for (const kind of ["volume", "brightness", "battery", "temp", "notif"])
                OsdBarState._upsertEntry(kind, "", 0.5, kind, false, Theme.accent)
            const now = Date.now()
            OsdBarState._sweepEntries()
            let live = true
            for (let i = 0; i < OsdBarState.entries.count; i++) {
                const entry = OsdBarState.entries.get(i)
                live = live && !entry.closing && !OsdBarState._due(OsdBarState._expiresAt[entry.kind], now)
            }
            root._check(live && OsdBarState.activeCount === 5,
                "new level feedback and readable alerts survive their first expiry sweep at timeout " + timeout)
            OsdBarState._expiresAt.volume = Date.now() - 1
            OsdBarState._sweepEntries()
            root._check(OsdBarState.entries.get(OsdBarState._entryIndex("volume")).closing
                    && !OsdBarState.entries.get(OsdBarState._entryIndex("temp")).closing,
                "expired volume feedback closes without dismissing a readable warning at timeout " + timeout)
            OsdBarState._expiresAt.temp = Date.now() + 3600000
            OsdBarState._sweepEntries()
            root._check(OsdBarState.entries.get(OsdBarState._entryIndex("temp")).closing,
                "a clock rollback still retires an impossible OSD deadline at timeout " + timeout)
        }
        OsdBarState._clearEntries()
        ShellSettings.osdTimeout = timeoutWas

        OsdBarState._upsertEntry("volume", "", 0.48, "Headset · 48%", false, Theme.accent)
        OsdBarState._upsertEntry("brightness", "", 0.6, "60%", false, Theme.accent)
        OsdBarState._showDeviceName = true
        OsdBarState._hideDeviceName()
        root._check(!OsdBarState._showDeviceName && OsdBarState.kind === "brightness"
                && OsdBarState.label === "60%"
                && OsdBarState.entries.get(OsdBarState._entryIndex("volume")).label === Audio.label,
            "a volume device name expires even while brightness feedback is primary")
        OsdBarState._closeEntry(OsdBarState._entryIndex("brightness"))
        root._check(OsdBarState.kind === "volume" && OsdBarState.label === Audio.label,
            "returning to volume feedback cannot bring back an expired device name")
        OsdBarState._upsertEntry("volume", "", 0, "Muted", true, Theme.accent)
        OsdBarState._hideDeviceName()
        root._check(OsdBarState.label === "Muted",
            "device-name expiry preserves muted volume feedback")
        OsdBarState._clearEntries()
        OsdBarState._hideDeviceName()
        root._check(!OsdBarState.showing && OsdBarState.activeCount === 0,
            "device-name expiry never resurrects dismissed volume feedback")
        // a level beside an alert: the narrowest and widest pill the OSD draws
        root._check(OsdBarState.pillX(520, 272) + 272 / 2 === 520 / 2
                && OsdBarState.pillX(520, 272) % 4 === 0
                && OsdBarState.pillX(520, 520) === 0,
            "two OSD pills of different widths share one centre, on the 4px grid")

        // a repeat inside the commit window after a close is an echo, unless it reads differently
        const repeatWas = { armed: OsdBarState._armed, motion: ShellSettings.reduceMotion }
        OsdBarState._armed = true
        ShellSettings.reduceMotion = true
        OsdBarState._upsertEntry("battery", "", 0.05, "Critical Battery · 5%", false, Theme.error)
        OsdBarState._upsertEntry("power", "", 0, "Balanced", false, Theme.accent)
        OsdBarState._upsertEntry("volume", "", 0.45, "45%", false, Theme.accent)
        OsdBarState._closeEntry(OsdBarState._entryIndex("power"))
        OsdBarState._closeEntry(OsdBarState._entryIndex("volume"))
        OsdBarState.showAlert("power", "", 0, "Balanced", Theme.accent)
        const alertColourKept = String(OsdBarState.fillColor) === String(Theme.error)
        OsdBarState.show("volume", "", 0.45, "45%", false)
        root._check(alertColourKept && String(OsdBarState.fillColor) === String(Theme.error)
                && OsdBarState.kind === "battery"
                && OsdBarState.entries.get(OsdBarState._entryIndex("power")).closing
                && OsdBarState.entries.get(OsdBarState._entryIndex("volume")).closing,
            "a dropped repeat leaves the colour of the bar OSD's shown pill alone")
        OsdBarState._clearEntries()
        OsdBarState._upsertEntry("volume", "", 0.45, "45%", false, Theme.accent)
        OsdBarState._closeEntry(OsdBarState._entryIndex("volume"))
        OsdBarState.show("volume", "", 0.45, "45%", false)
        const echoDropped = OsdBarState.entries.get(OsdBarState._entryIndex("volume")).closing
        OsdBarState.show("volume", "", 0.45, "Speakers · 45%", false)
        root._check(echoDropped && OsdBarState.label === "Speakers · 45%"
                && !OsdBarState.entries.get(OsdBarState._entryIndex("volume")).closing,
            "an output switch at the level just shown still announces its name, while the level's echo stays dropped")
        OsdBarState._clearEntries()
        OsdBarState._armed = repeatWas.armed
        ShellSettings.reduceMotion = repeatWas.motion
    }

    function _checkWifiDraft(): void {
        const motionWas = ShellSettings.reduceMotion
        const errorWas = Network.wifiError
        const reasonWas = Network.wifiErrorReason
        const scannerWas = Network._scannerWanted
        const connectingWas = Network.wifiConnecting
        ShellSettings.reduceMotion = true
        const component = Qt.createComponent("modules/menu/WifiList.qml")
        const picker = component.status === Component.Ready
            ? component.createObject(root, { width: 320, open: true }) : null
        root._check(picker !== null, "the Wi-Fi picker builds for draft retention checks")
        if (picker) {
            const row = { ssid: "__silere_draft_probe__", label: "Draft probe", glyph: "",
                secured: true, psk: true, passwordless: false, profileOnly: false,
                active: false, known: false }
            picker._selected = row.ssid
            picker._networks = [row]
            picker._passwordDraft = "draft before scrolling"
            const list = root._findTrayNode(picker, item => typeof item.forceLayout === "function")
            if (list) list.forceLayout()
            let entry = root._findTrayNode(picker, item => item.index === 0 && item._sel === true)
            let input = root._findTrayNode(entry, item => item.echoMode === TextInput.Password)
            root._check(input !== null && input.text === "draft before scrolling",
                "the selected Wi-Fi row displays its picker's password draft")
            if (input) {
                input.clear()
                input.insert(0, "typed draft")
                root._check(picker._passwordDraft === "typed draft",
                    "editing a Wi-Fi password updates the draft outside its delegate")
            }
            picker._networks = []
            if (list) list.forceLayout()
            picker._networks = [Object.assign({}, row)]
            if (list) list.forceLayout()
            entry = root._findTrayNode(picker, item => item.index === 0 && item._sel === true)
            input = root._findTrayNode(entry, item => item.echoMode === TextInput.Password)
            root._check(input !== null && input.text === "typed draft",
                "recreating a scrolled Wi-Fi row restores the typed password")
            const reveal = root._findTrayNode(entry, item => item.Accessible.name === "Show Wi-Fi password")
            root._check(reveal !== null, "the Wi-Fi password field offers an accessible reveal control")
            if (reveal && input) {
                reveal.Accessible.pressAction()
                root._check(input.echoMode === TextInput.Normal && input.text === "typed draft"
                        && picker._passwordVisible && reveal.Accessible.checked,
                    "revealing a Wi-Fi password preserves its draft and reports its state")
                reveal.Accessible.pressAction()
                root._check(input.echoMode === TextInput.Password && !picker._passwordVisible,
                    "the Wi-Fi password can be masked again")
                Network.wifiConnecting = row.ssid
                reveal.Accessible.pressAction()
                root._check(input.readOnly && !picker._passwordVisible,
                    "an in-progress Wi-Fi connection freezes password edits and revelation")
                Network.wifiConnecting = ""
                picker._selected = row.ssid
                picker._networks = [row]
                if (list) list.forceLayout()
                entry = root._findTrayNode(picker, item => item.index === 0 && item._sel === true)
                picker._passwordDraft = "typed draft"
                picker._passwordVisible = true
            }
            Network.wifiError = row.ssid
            root._check(picker._passwordDraft === "" && !picker._passwordVisible,
                "a failed Wi-Fi attempt clears and remasks its selected password draft")
            picker._passwordDraft = "another draft"
            picker._selected = "another network"
            root._check(picker._passwordDraft === "",
                "selecting another Wi-Fi network clears the previous password draft")
            picker._passwordDraft = "new network draft"
            if (entry) entry._submitPassword()
            root._check(picker._passwordDraft === "new network draft",
                "a stale Wi-Fi row cannot consume another network's password draft")
            picker._passwordDraft = "closing draft"
            picker.open = false
            root._check(picker._passwordDraft === "" && picker._selected === "",
                "closing the Wi-Fi picker clears both its draft and selection")
            picker._networks = [row]
            const rows = root._findTrayNode(picker, item => typeof item.positionViewAtIndex === "function")
            root._check(rows !== null && rows.count === 1,
                "a closed Wi-Fi picker keeps its rows drawn: Home unloads it once its fold ends, not before")
            picker.destroy()
        }
        component.destroy()
        if (scannerWas) Network.scanWifi(false)
        Network.wifiError = errorWas
        Network.wifiErrorReason = reasonWas
        Network.wifiConnecting = connectingWas
        ShellSettings.reduceMotion = motionWas
    }

    // over a bottom bar a picker opens above its row, and switching pickers arms two holds on one page
    function _checkScrollHolds(): void {
        const flick = flickableFactory.createObject(root)
        const holdFor = y => {
            const row = Qt.createQmlObject("import QtQuick; Item { width: 100; height: 40 }", flick.contentItem)
            row.y = y
            const hold = Qt.createQmlObject("import \"modules/menu/controls\"; ScrollHold {}", root)
            hold.item = row
            return hold
        }
        const closing = holdFor(100), opening = holdFor(300)
        closing.arm(false)
        root._check(flick.scrollHold === closing, "a closing picker's hold takes the page when no other is at work")
        opening.arm(true)
        root._check(flick.scrollHold === opening && opening.leads,
            "the picker that opens takes the page from the one closing: its row is under the pointer")
        closing.arm(false)
        root._check(flick.scrollHold === opening, "a hold armed for a close yields to the one opening, whichever order they arm in")
        closing.item.y = 160
        flick.contentY = 0
        closing._hold()
        root._check(flick.contentY === 0, "a hold that yielded leaves the page where the leading hold keeps it")
        opening.item.y = 340
        opening._hold()
        root._check(flick.contentY === 40, "the leading hold scrolls its row back under the pointer")
        opening._y = NaN
        closing.arm(false)
        root._check(flick.scrollHold === closing, "a released hold no longer leads, so a later close holds its own row")
        closing.item.destroy(); opening.item.destroy(); closing.destroy(); opening.destroy(); flick.destroy()
    }

    function _checkPanelFocus(): void {
        const was = { motion: ShellSettings.reduceMotion, position: ShellSettings.barPosition,
            presentation: Audio._profilePresentation,
            devices: Brightness.devices }
        ShellSettings.reduceMotion = true
        const host = panelKeyboardWindowFactory.createObject(root)
        host.requestActivate()
        host.input.wait(30)
        const homeComponent = Qt.createComponent("modules/menu/HomePage.qml")
        for (const mode of [
            { position: "top", motion: true }, { position: "bottom", motion: true },
            { position: "top", motion: false }, { position: "bottom", motion: false }
        ]) {
            const position = mode.position
            ShellSettings.reduceMotion = mode.motion
            ShellSettings.barPosition = position
            const home = homeComponent.createObject(host.contentItem, { width: 440, active: true })
            home._togglePicker("dnd")
            host.input.wait(20)
            const option = root._findTrayNode(home, item => item.label === "For 1 hour")
            if (option) option.forceActiveFocus(Qt.TabFocusReason)
            home.dismissInline()
            host.input.wait(mode.motion ? 10 : Motion.medium + 60)
            root._check(option !== null && host.activeFocusItem
                    && host.activeFocusItem.Accessible.name === "Show Do Not Disturb options",
                "closing Home's " + position + " inline picker returns focus to its opener with reduced motion " + mode.motion)
            home._togglePicker("dnd")
            host.outside.forceActiveFocus(Qt.TabFocusReason)
            home.dismissInline()
            root._check(host.outside.activeFocus,
                "closing Home's " + position + " picker preserves focus outside the picker")
            home.destroy()
            host.input.wait(10)
        }
        homeComponent.destroy()
        ShellSettings.reduceMotion = true
        Audio._profilePresentation = { ready: true, micReady: true, volume: 0.5, effectiveVolume: 0.5,
            muted: false, name: "Probe output", micVolume: 0.5, micEffectiveVolume: 0.5,
            micMuted: false, sourceName: "Probe input" }
        for (const kind of ["Volume", "Brightness"]) {
            const component = Qt.createComponent("modules/menu/" + kind + "Row.qml")
            const control = component.createObject(host.contentItem, { width: 440, open: true })
            host.input.wait(10)
            if (kind === "Brightness") {
                // finish queued hardware reads before installing this inventory fixture
                Brightness.devices = [{ name: "__panel_focus_probe__" }, { name: "__dock_focus_probe__" }]
                control.open = true
            }
            const choice = root._findTrayNode(control, item => kind === "Volume"
                ? item.Accessible.role === Accessible.Slider && item.Accessible.name === "Microphone"
                : item.accessiblePrefix === "Brightness display")
            if (choice) choice.forceActiveFocus(Qt.TabFocusReason)
            control.closeInline()
            const returned = host.activeFocusItem
                && host.activeFocusItem.Accessible.name === "Show " + kind.toLowerCase() + " options"
            host.input.wait(10)
            root._check(choice !== null && returned,
                "closing " + kind + " choices returns focus to its expander")
            control.open = true
            host.outside.forceActiveFocus(Qt.TabFocusReason)
            control.closeInline()
            root._check(host.outside.activeFocus, kind + " choices never take focus from another control")
            control.destroy()
            host.input.wait(10)
            component.destroy()
        }
        Audio._profilePresentation = was.presentation
        Brightness.devices = was.devices
        const networks = Array.from({ length: 14 }, (_, i) => ({ ssid: "__panel_network_" + i,
            label: "Panel network " + i, glyph: "", secured: true, psk: true,
            passwordless: false, profileOnly: false, active: false, known: false }))
        const component = Qt.createComponent("modules/menu/WifiList.qml")
        const wifi = component.createObject(host.contentItem, { width: 440, open: true })
        // an open list starts the machine's real scanner (the system bus is not the probe's), and nearby networks replaced
        // these mid-check; dropping the request before that deferred start leaves the published list to the probe, and the
        // fixture hold keeps any other access point change (a signal update) from publishing over it
        Network.requestWifiScan(wifi, false)
        Network._wifiFixture = true
        Network._publishedWifiNetworks = networks
        const list = root._findTrayNode(wifi, item => item.currentIndex !== undefined && typeof item.forceLayout === "function")
        list.currentIndex = 7
        list.positionViewAtIndex(7, ListView.Contain)
        list.forceLayout()
        host.input.wait(10)
        const initial = root._findTrayNode(list.currentItem, item => item.Accessible.name === networks[7].label)
        if (initial) initial.forceActiveFocus(Qt.TabFocusReason)
        Network._publishedWifiNetworks = networks.slice().reverse()
        host.input.wait(30)
        root._check(initial !== null && host.activeFocusItem
                && host.activeFocusItem.Accessible.name === networks[7].label,
            "a Wi-Fi rescan preserves the focused network when signal ordering changes")
        const remaining = Network._publishedWifiNetworks.filter(item => item.ssid !== networks[7].ssid)
        Network._publishedWifiNetworks = remaining
        host.input.wait(30)
        root._check(host.activeFocusItem && host.activeFocusItem.Accessible.name === remaining[6].label,
            "a disappearing Wi-Fi network leaves keyboard focus on the nearest remaining row")
        const passwordRow = root._findTrayNode(wifi, item => item.Accessible.name === remaining[6].label)
        if (passwordRow) passwordRow.Accessible.pressAction()
        host.input.wait(20)
        const password = root._findTrayNode(wifi, item => item.Accessible.name === "Wi-Fi password" && item.activeFocus)
        if (password) password.insert(0, "draft password")
        Network._publishedWifiNetworks = [remaining[6]].concat(remaining.filter(item => item !== remaining[6]))
        host.input.wait(20)
        root._check(password && password.activeFocus && password.text === "draft password",
            "a Wi-Fi rescan while entering a password preserves the field, draft and focus")
        host.input.keyClick(Qt.Key_Escape)
        host.input.wait(30)
        root._check(password !== null && wifi._selected === "" && wifi._passwordDraft === ""
                && host.activeFocusItem && host.activeFocusItem.Accessible.name === remaining[6].label,
            "Escape cancels a Wi-Fi password draft and returns focus to its network")
        root._check(host.escapes === 0, "Wi-Fi password cancellation takes Escape before the panel's application shortcut")
        host.input.keyClick(Qt.Key_Escape)
        root._check(host.escapes === 1, "the next Escape is available to close the Wi-Fi picker")
        Network._publishedWifiNetworks = networks.slice().reverse()
        Network._publishedWifiNetworks = networks.slice()
        host.input.wait(30)
        root._check(host.activeFocusItem && host.activeFocusItem.Accessible.name === remaining[6].label,
            "back-to-back Wi-Fi scans retain the same pending focus target")
        Network._publishedWifiNetworks = networks.map(item => Object.assign({}, item))
        host.outside.forceActiveFocus(Qt.TabFocusReason)
        host.input.wait(30)
        root._check(host.outside.activeFocus, "a delayed Wi-Fi refresh cannot steal focus after Tab leaves the list")
        wifi.open = false
        // what releasing the scan publishes as the picker closes
        Network._publishedWifiNetworks = []
        root._check(list.count === networks.length && wifi._networks.length === networks.length,
            "a closing Wi-Fi picker keeps its rows through the fold when releasing the scan empties the networks")
        wifi.open = true
        root._check(list.count === Network.wifiNetworks.length,
            "a Wi-Fi picker reopened during its fold shows the networks as they are now, not the rows it kept")
        Network.requestWifiScan(wifi, false)
        wifi.open = false
        wifi.destroy()
        component.destroy()
        const editorComponent = Qt.createComponent("modules/menu/settings/CommandEditor.qml")
        const editor = editorComponent.createObject(host.contentItem, { width: 440, settingKey: "lockCommandCustom" })
        const command = root._findTrayNode(editor, item => item.maximumLength === 4096)
        editor.draft = editor.savedValue + " --unsaved"
        if (command) command.forceActiveFocus(Qt.TabFocusReason)
        const escapes = host.escapes
        host.input.keyClick(Qt.Key_Escape)
        root._check(command !== null && !editor.dirty && !command.activeFocus && host.escapes === escapes,
            "Escape reverts a command draft before the panel's application shortcut can close Settings")
        host.input.keyClick(Qt.Key_Escape)
        root._check(host.escapes === escapes + 1, "the next Escape can close Settings after discarding a command draft")
        editor.destroy()
        editorComponent.destroy()
        Network._wifiFixture = false
        ShellSettings.barPosition = was.position
        ShellSettings.reduceMotion = was.motion
        host.close()
        host.destroy()
    }

    function _checkAccentContrast(): void {
        const keys = ["reduceMotion", "neutralTheme", "neutralAccentAuto", "neutralAccent",
            "highContrast", "baseTone", "barOpacity", "surfaceBlur", "popupMatchBarOpacity",
            "matugenAccentBalance", "matugenAccentRole"]
        const saved = keys.map(key => ShellSettings[key])
        const paletteWas = MatugenTheme._palette
        ShellSettings.reduceMotion = true
        ShellSettings.neutralAccentAuto = false
        ShellSettings.matugenAccentBalance = false
        ShellSettings.matugenAccentRole = "primary"
        ShellSettings.surfaceBlur = true
        ShellSettings.popupMatchBarOpacity = true
        const marker = workspaceMarkerFactory.createObject(barFixtureHost)
        for (const neutral of [true, false]) for (const hc of [false, true])
        for (const opacity of [1, 0.62]) for (const tone of ["black", "charcoal", "graphite"])
        for (const color of ["#000000", "#111111", "#103323", "#23509a", "#9babe9", "#ffffff"]) {
            ShellSettings.neutralTheme = neutral
            ShellSettings.highContrast = hc
            ShellSettings.barOpacity = opacity
            ShellSettings.baseTone = tone
            ShellSettings.neutralAccent = color
            MatugenTheme._palette = Object.assign({}, paletteWas, { accent: color })
            const context = [neutral, hc, opacity, tone, color].join("/")
            root._check(Qt.colorEqual(Theme.accent, Qt.color(color))
                    && Theme.contrastRatio(Theme.barAccent, Theme.background) >= (hc ? 6.99 : 4.49)
                    && marker && Qt.colorEqual(marker.tint, Theme.barAccentMark),
                "bar indicators stay readable without changing the chosen accent: " + context)
            const barOverWhite = Theme.mix(Qt.color("#ffffff"), Theme.background, Theme.panelOpacity)
            const barOverBlack = Theme.mix(Qt.color("#000000"), Theme.background, Theme.panelOpacity)
            let mark = Infinity
            for (const ink of [Theme.barAccentMark, Theme.barError, Theme.barWarning, Theme.barSuccess])
                for (const bar of [barOverWhite, barOverBlack]) mark = Math.min(mark, Theme.contrastRatio(ink, bar))
            root._check(mark >= (hc ? 4.49 : 2.99),
                "the bar's marks and status glyphs hold a shape's contrast over light and dark wallpapers: "
                    + context + " contrast " + mark)
            // a mark asks less than a label, so it keeps at least the colour the label does
            root._check(Theme.lchOf(Theme.barAccentMark).C >= Theme.lchOf(Theme.barAccent).C - 0.5,
                "a bar mark keeps at least its label's colour: " + context)
            root._check(Theme.contrastRatio(Theme.barAccent, barOverWhite) >= (hc ? 6.99 : 4.49)
                    && Theme.contrastRatio(Theme.barText, barOverWhite) >= (hc ? 6.99 : 4.49)
                    && Theme.contrastRatio(Theme.barText, barOverBlack) >= (hc ? 6.99 : 4.49)
                    && Theme.contrastRatio(Theme.barSubtext, barOverWhite) >= (hc ? 6.99 : 2.99)
                    && Theme.contrastRatio(Theme.barSubtext, barOverBlack) >= (hc ? 6.99 : 2.99),
                "bar labels and accents remain readable over light and dark wallpapers: " + context)
            let lowest = Infinity
            for (const hovered of [false, true]) for (const pressed of [false, true]) {
                const knob = Theme.controlKnobFill(Theme.accent, true, hovered, pressed)
                const track = Theme.switchTrackFill(Theme.accent, true, hovered, pressed)
                for (const backdrop of ["#000000", "#ffffff"]) {
                    const card = Theme.glass
                        ? Theme.mix(Theme.mix(Qt.color(backdrop), Theme.background, Theme.popupOpacity),
                            Theme.text, Theme._cardK)
                        : Theme.menuCardSolid
                    lowest = Math.min(lowest, Theme.contrastRatio(knob, Theme.mix(card, track, track.a)))
                }
            }
            root._check(lowest >= 2.99,
                "selected switch knobs survive hover, press and light or dark glass backdrops: "
                    + context + " contrast " + lowest)
        }
        if (marker) marker.destroy()
        MatugenTheme._palette = paletteWas
        // restore motion last so returning to the original palette is immediate
        for (let i = keys.length - 1; i >= 0; i--) ShellSettings[keys[i]] = saved[i]
    }

    // contrast used to be bought with an srgb blend toward white, which greys a colour on the way
    function _checkContrastKeepsHue(): void {
        const hueGap = (a, b) => { const d = Math.abs(Theme.lchOf(a).h - Theme.lchOf(b).h); return Math.min(d, 360 - d) }
        // a see-through bar over a white wallpaper: the mid grey a label has to clear by 4.5:1
        const grey = Qt.color("#717273"), dark = Qt.color("#060708")
        // what the srgb blend left of the same ink at the same contrast
        const blended = ink => {
            let low = 0, high = 1
            for (let i = 0; i < 12; i++) {
                const middle = (low + high) / 2
                if (Theme.contrastRatio(Theme.blend(ink, Qt.color("white"), middle), grey) >= 4.5) high = middle
                else low = middle
            }
            return Theme.blend(ink, Qt.color("white"), high)
        }
        for (const hex of ["#b4d087", "#8fd6a8", "#e6c26a", "#ffb4a8", "#b9c3ff", "#d9b9ff"]) {
            const ink = Qt.color(hex)
            const lifted = Theme._readableAcross(ink, dark, grey, 4.5)
            root._check(Theme.contrastRatio(lifted, grey) >= 4.49 && hueGap(lifted, ink) < 4
                    && Theme.lchOf(lifted).C >= Theme.lchOf(blended(ink)).C - 0.3,
                "a lifted accent keeps its hue and no less colour than a blend toward white: " + hex
                    + " -> " + lifted + " chroma " + Theme.lchOf(lifted).C.toFixed(1))
        }
        const green = Theme._readableAcross(Qt.color("#b4d087"), dark, grey, 4.5)
        root._check(Theme.lchOf(green).C >= 20 && Theme.lchOf(blended(Qt.color("#b4d087"))).C < 8,
            "a green accent lifted to a label's contrast is still green, where the blend left an off-white: "
                + green + " chroma " + Theme.lchOf(green).C.toFixed(1))
        for (const hex of ["#ffb4a8", "#b9c3ff", "#d9b9ff", "#dd92a2", "#d4ad77"]) {
            const ink = Qt.color(hex)
            const mark = Theme._readableAcross(ink, dark, grey, 3.0)
            root._check(Theme.contrastRatio(mark, grey) >= 2.99 && hueGap(mark, ink) < 4
                    && Theme.lchOf(mark).C >= Theme.lchOf(ink).C * 0.8,
                "a mark's 3:1 leaves an accent its colour on a see-through bar: " + hex
                    + " -> " + mark + " chroma " + Theme.lchOf(mark).C.toFixed(1))
        }
        // the same split on the live theme: a see-through bar's mark keeps the accent its label has to give up
        const keys = ["reduceMotion", "neutralTheme", "neutralAccentAuto", "neutralAccent", "highContrast",
            "baseTone", "barOpacity"]
        const saved = keys.map(key => ShellSettings[key])
        ShellSettings.reduceMotion = true
        ShellSettings.neutralTheme = true
        ShellSettings.neutralAccentAuto = false
        ShellSettings.highContrast = false
        ShellSettings.baseTone = "charcoal"
        ShellSettings.barOpacity = 0.58
        for (const hex of ["#b9c3ff", "#ffb4a8", "#c99fd3"]) {
            ShellSettings.neutralAccent = hex
            const accent = Theme.lchOf(Theme.accent), mark = Theme.lchOf(Theme.barAccentMark)
            root._check(mark.C >= accent.C * 0.8 && Theme.lchOf(Theme.barAccent).C < accent.C * 0.5
                    && hueGap(Theme.barAccentMark, Theme.accent) < 4,
                "a see-through bar's marks keep the accent's colour: " + hex + " -> " + Theme.barAccentMark
                    + " chroma " + mark.C.toFixed(1) + " of " + accent.C.toFixed(1))
        }
        // an alert's tint arrives on the bar as a value: the icon and level are marks, the words a label
        const overWhite = Theme.mix(Qt.color("#ffffff"), Theme.background, Theme.panelOpacity)
        const alert = Qt.color("#dd92a2")
        root._check(Theme.contrastRatio(Theme.barInk(alert, false), overWhite) >= 2.99
                && Theme.contrastRatio(Theme.barInk(alert, true), overWhite) >= 4.49
                && Theme.contrastRatio(alert, overWhite) < 2.5
                && Theme.lchOf(Theme.barInk(alert, false)).C >= Theme.lchOf(alert).C * 0.8,
            "an alert's tint is lifted for the bar it lands on, as a mark and as a label")
        ShellSettings.barOpacity = 1
        root._check(Qt.colorEqual(Theme.barAccentMark, Theme.accent) && Qt.colorEqual(Theme.barAccent, Theme.accent)
                && Qt.colorEqual(Theme.barInk(alert, false), alert) && Qt.colorEqual(Theme.barInk(alert, true), alert),
            "an opaque bar leaves the accent and an alert's tint alone, mark and label")
        for (let i = keys.length - 1; i >= 0; i--) ShellSettings[keys[i]] = saved[i]
        // dark ink on a pale surface walks down, not up, and a translucent ink keeps its alpha
        const pale = Qt.color("#eeeeee")
        const down = Theme.readableText(Qt.color("#c9a227"), pale, 4.5)
        const sheer = Theme.readableText(Qt.rgba(0.6, 0.6, 0.65, 0.85), Qt.color("#68696b"), 3.0)
        root._check(Theme.contrastRatio(down, pale) >= 4.49 && Theme.lchOf(down).L < Theme.lchOf(Qt.color("#c9a227")).L
                && hueGap(down, Qt.color("#c9a227")) < 4 && Math.abs(sheer.a - 0.85) < 0.001
                && Theme.contrastRatio(sheer, Qt.color("#68696b")) >= 2.99,
            "ink on a pale surface darkens along its hue, and a translucent ink keeps its alpha")
        const grayInk = Theme.readableText(Qt.color("#777777"), Qt.color("#777777"), 4.5)
        root._check(Theme.lchOf(grayInk).C < 1.5 && Theme.contrastRatio(grayInk, Qt.color("#777777")) >= 4.49,
            "a colourless ink stays colourless when lifted")
    }

    // ink on a see-through popup has two backdrops to survive, a white window and a dark one. Solved against
    // the worse alone, white text put that backdrop at mid grey, where black beats white by a hair
    // the accent drawn as a word or a glyph: every accent the theme can choose, on glass and opaque
    function _checkAccentInk(): void {
        const keys = ["reduceMotion", "neutralTheme", "neutralAccentAuto", "neutralAccent", "highContrast", "baseTone",
            "barOpacity", "surfaceBlur", "popupMatchBarOpacity", "matugenAccentBalance", "matugenAccentRole", "matugenDepth"]
        const saved = keys.map(key => ShellSettings[key])
        const paletteWas = MatugenTheme._palette
        ShellSettings.reduceMotion = true
        ShellSettings.surfaceBlur = true
        ShellSettings.highContrast = false
        ShellSettings.barOpacity = 0.58
        ShellSettings.matugenDepth = "none"
        const dark = { background: "#121318", surface: "#1e1f25", text: "#e3e1e9", subtext: "#c6c5d0", accent: "#b9c3ff",
            error: "#ffb4ab", warning: "#e5bad8", success: "#c3c5dd" }
        const light = { background: "#fbf8ff", surface: "#efedf4", text: "#1b1b21", subtext: "#46464f", accent: "#525a92",
            error: "#ba1a1a", warning: "#77536d", success: "#5b5d72" }
        const cases = []
        for (const preset of Theme.neutralAccentPresets)
            cases.push({ neutral: true, auto: false, accent: preset.color, palette: dark, name: preset.name, preset: true })
        // a dark custom hex sinks under 3:1 even on an opaque menu
        for (const custom of ["#23509a", "#103323"])
            cases.push({ neutral: true, auto: false, accent: custom, palette: dark, name: "custom " + custom })
        cases.push({ neutral: true, auto: true, palette: dark, name: "auto" })
        for (const palette of [dark, light]) for (const role of ["primary", "secondary", "tertiary"])
            for (const balance of [false, true])
                cases.push({ neutral: false, auto: true, palette, role, balance,
                    name: (palette === light ? "light " : "") + role + (balance ? " balanced" : "") })
        const white = Qt.rgba(1, 1, 1, 1), black = Qt.rgba(0, 0, 0, 1)
        const lowestFor = ink => Theme.glass
            ? Math.min(Theme.contrastRatio(ink, Theme._controlOverBackdrop(Theme.background, Theme.text, Theme.popupOpacity, white)),
                Theme.contrastRatio(ink, Theme._controlOverBackdrop(Theme.background, Theme.text, Theme.popupOpacity, black)))
            : Theme.contrastRatio(ink, Theme._glassWorst)
        const hueGap = (a, b) => Math.abs(((a - b) % 360 + 540) % 360 - 180)
        const failed = { reads: [], hue: [], chosen: [], own: [], opaque: [], inkFor: [] }
        let liftedRuns = 0, runs = 0
        for (const glass of [true, false]) for (const tone of ["black", "charcoal"]) for (const c of cases) {
            ShellSettings.popupMatchBarOpacity = glass
            ShellSettings.baseTone = tone
            ShellSettings.neutralTheme = c.neutral
            ShellSettings.neutralAccentAuto = c.auto
            if (c.accent) ShellSettings.neutralAccent = c.accent
            ShellSettings.matugenAccentRole = c.role ?? "primary"
            ShellSettings.matugenAccentBalance = c.balance ?? false
            MatugenTheme._palette = c.palette
            runs++
            const context = (glass ? "glass/" : "opaque/") + tone + "/" + c.name
            const ink = Theme.accentInk, accent = Theme.accent
            const reads = lowestFor(ink)
            if (!(reads >= 2.99)) failed.reads.push(context + " " + reads.toFixed(2))
            const inkLch = Theme.lchOf(ink), accentLch = Theme.lchOf(accent)
            if (accentLch.C >= 4 && inkLch.C >= 4 && hueGap(inkLch.h, accentLch.h) > 4) failed.hue.push(context)
            if (!Qt.colorEqual(accent, Theme._tAccent) || (c.accent && !Qt.colorEqual(accent, Qt.color(c.accent))))
                failed.chosen.push(context)
            if (lowestFor(accent) >= 3.0 && !Qt.colorEqual(ink, accent)) failed.own.push(context)
            if (!glass && c.preset && !Qt.colorEqual(ink, accent)) failed.opaque.push(context)
            if (!Qt.colorEqual(Theme.inkFor(accent), ink) || !Qt.colorEqual(Theme.inkFor(Theme.error), Theme.error)
                    || !Qt.colorEqual(Theme.inkFor(Theme.warning), Theme.warning)
                    || !Qt.colorEqual(Theme.inkFor(Theme.success), Theme.success))
                failed.inkFor.push(context)
            if (!Qt.colorEqual(ink, accent)) liftedRuns++
        }
        root._check(runs === 92 && failed.reads.length === 0,
            "the accent as a word or a glyph holds 3:1 for every accent on glass and opaque: " + failed.reads.join(", "))
        root._check(failed.hue.length === 0, "the accent's ink keeps its hue: " + failed.hue.join(", "))
        root._check(failed.chosen.length === 0, "the chosen accent itself never moves: " + failed.chosen.join(", "))
        root._check(failed.own.length === 0 && failed.opaque.length === 0 && liftedRuns > 0,
            "an accent that already reads is its own ink, so every preset on an opaque menu draws as before: "
                + failed.own.concat(failed.opaque).join(", ") + " (lifted " + liftedRuns + ")")
        root._check(failed.inkFor.length === 0,
            "a control's tint as ink: the accent takes its ink, status colours stay as they are: " + failed.inkFor.join(", "))

        // real controls draw their words and glyphs with the ink and keep the accent for their fills
        ShellSettings.popupMatchBarOpacity = true
        ShellSettings.baseTone = "black"
        ShellSettings.neutralTheme = true
        ShellSettings.neutralAccentAuto = false
        ShellSettings.neutralAccent = "#9babe9"
        // a Text keeps its colour in 8 bits a channel
        const near = (a, b) => Math.abs(a.r - b.r) < 0.003 && Math.abs(a.g - b.g) < 0.003
            && Math.abs(a.b - b.b) < 0.003 && Math.abs(a.a - b.a) < 0.003
        const row = controlRowFactory.createObject(barFixtureHost, { glyph: "󰂯", active: true })
        const glyph = row ? root._findTrayNode(row, item => item.text === "󰂯") : null
        const option = inlineOptionFactory.createObject(barFixtureHost, { selected: true })
        const mark = option ? root._findTrayNode(option, item => item.text === "󰄬") : null
        const card = updateStatusFactory.createObject(barFixtureHost, { status: "Probe status", statusColor: Theme.accent })
        const words = card ? root._findTrayNode(card, item => item.text === "Probe status") : null
        const lifted = !Qt.colorEqual(Theme.accentInk, Theme.accent)
        root._check(lifted && glyph !== null && near(glyph.color, Theme.withAlpha(Theme.accentInk, 0.95)),
            "an active control row draws its glyph with the accent's ink")
        root._check(lifted && mark !== null && near(mark.color, Theme.accentInk),
            "a selected option draws its check mark with the accent's ink")
        root._check(lifted && words !== null && near(words.color, Theme.withAlpha(Theme.accentInk, 0.9)),
            "an update card in the accent draws its status line with the accent's ink")
        if (row) row.destroy()
        if (option) option.destroy()
        if (card) card.destroy()
        MatugenTheme._palette = paletteWas
        for (let i = keys.length - 1; i >= 0; i--) ShellSettings[keys[i]] = saved[i]
    }

    // a warning in Gold, a success in Leaf, an error in Coral, or any of them under an auto accent off a wallpaper
    // of the same hue, drew in the accent's own colour; on the bar an urgent workspace then read as the active one
    function _checkStatusApart(): void {
        const keys = ["reduceMotion", "neutralTheme", "neutralAccentAuto", "neutralAccent", "highContrast", "baseTone",
            "barOpacity", "matugenAccentBalance", "matugenAccentRole"]
        const saved = keys.map(key => ShellSettings[key])
        const paletteWas = MatugenTheme._palette
        ShellSettings.reduceMotion = true
        ShellSettings.highContrast = false
        ShellSettings.baseTone = "black"
        ShellSettings.barOpacity = 0.58
        ShellSettings.matugenAccentBalance = false
        const chromaGap = (a, b) => { const x = Theme._labOf(a), y = Theme._labOf(b); return Math.hypot(x.a - y.a, x.b - y.b) }
        // matugen 4.2 off an orange and a red source colour; the red one's error sits 1.5 from its primary
        const warm = { background: "#1a110e", surface: "#271d1a", text: "#f1dfd9", subtext: "#d8c2bb", accent: "#ffb59b",
            error: "#ffb4ab", warning: "#d5c68e", success: "#e7beaf" }
        const red = { background: "#1a1110", surface: "#271d1c", text: "#f1dedd", subtext: "#d8c2bf", accent: "#ffb3ad",
            error: "#ffb4ab", warning: "#e1c28c", success: "#e7bdb9" }
        const cases = Theme.neutralAccentPresets.map(p => ({ neutral: true, accent: p.color, name: p.name, palette: warm }))
        for (const palette of [warm, red]) for (const role of ["primary", "secondary"])
            cases.push({ neutral: false, role, palette, name: (palette === red ? "red " : "warm ") + role })
        const close = [], bar = [], moved = [], crowded = []
        for (const c of cases) {
            ShellSettings.neutralTheme = c.neutral
            ShellSettings.neutralAccentAuto = false
            if (c.accent) ShellSettings.neutralAccent = c.accent
            ShellSettings.matugenAccentRole = c.role ?? "primary"
            MatugenTheme._palette = c.palette
            // a turned status colour keeps clear of the other two, or stays at least as far as the palette had them
            const pairGap = list => Math.min(chromaGap(list[0], list[1]), chromaGap(list[0], list[2]), chromaGap(list[1], list[2]))
            const before = pairGap([Theme._errorSource, Theme._warningSource, Theme._successSource])
            const after = pairGap([Theme._tErrorBase, Theme._tWarningBase, Theme._tSuccessBase])
            if (after < Math.min(before, Theme._statusGap) - 0.5)
                crowded.push(c.name + " " + before.toFixed(1) + " -> " + after.toFixed(1))
            const pairs = [[Theme._tErrorBase, Theme.barError, Qt.color("#dd92a2")],
                [Theme._tWarningBase, Theme.barWarning, Theme._warnAnchor],
                [Theme._tSuccessBase, Theme.barSuccess, Theme._okAnchor]]
            for (const [base, mark, anchor] of pairs) {
                if (chromaGap(base, Theme.accent) < Theme._statusGap - 0.5) close.push(c.name + " " + base)
                if (chromaGap(mark, Theme.barAccentMark) < Theme._statusGap * 0.8) bar.push(c.name + " " + mark)
                if (!c.neutral) continue
                // an accent clear of the anchor leaves it exactly as it was; a moved one keeps its lightness, so its contrast
                const clear = chromaGap(anchor, Theme.accent) >= Theme._statusGap
                if (clear ? !Qt.colorEqual(base, anchor) : Math.abs(Theme.lchOf(base).L - Theme.lchOf(anchor).L) > 0.6)
                    moved.push(c.name + " " + anchor + " -> " + base)
            }
        }
        root._check(close.length === 0, "status colours keep clear of the accent on every preset and wallpaper role: "
            + close.join(", "))
        root._check(bar.length === 0, "a see-through bar's status marks keep clear of its accent marks: " + bar.join(", "))
        root._check(crowded.length === 0, "a status colour turned off the accent keeps clear of the other two: "
            + crowded.join(", "))
        root._check(moved.length === 0, "an accent clear of a status colour leaves it as it was, a moved one keeps its "
            + "lightness: " + moved.join(", "))
        MatugenTheme._palette = paletteWas
        for (let i = keys.length - 1; i >= 0; i--) ShellSettings[keys[i]] = saved[i]
    }

    // a wallpaper's palette eases every token, so local fades stand down for it; high contrast and the colour source flip
    // the formulas themselves, which no token eases, and a switch's knob snapped from the accent to grey without them
    function _checkModeSwitchFades(): void {
        const keys = ["reduceMotion", "highContrast", "neutralTheme", "neutralAccentAuto"]
        const saved = keys.map(key => ShellSettings[key])
        const paletteWas = MatugenTheme._palette
        ShellSettings.reduceMotion = false
        // either source takes this palette's accent; switching the source here would itself open a mode switch
        ShellSettings.neutralAccentAuto = true
        MatugenTheme._palette = { background: "#121318", surface: "#1e1f25", text: "#e3e1e9", subtext: "#c6c5d0",
            accent: "#b9c3ff", error: "#ffb4ab", warning: "#e5bad8", success: "#c3c5dd" }
        const wallpaper = Theme.paletteShifting
        ShellSettings.highContrast = !ShellSettings.highContrast
        const contrast = Theme.paletteShifting
        // the outlines' own lines blend between both forms and set off from where they were
        const contrastLines = Math.abs(Theme._hcK - (ShellSettings.highContrast ? 1 : 0)) > 0.5
        ShellSettings.highContrast = !ShellSettings.highContrast
        ShellSettings.neutralTheme = !ShellSettings.neutralTheme
        const source = Theme.paletteShifting
        const sourceLines = Math.abs(Theme._nK - (ShellSettings.neutralTheme ? 1 : 0)) > 0.5
        root._check(wallpaper && !contrast && !source,
            "a wallpaper's palette stands local colour fades down; a high contrast or source switch keeps them: "
                + [wallpaper, contrast, source].join(" "))
        root._check(contrastLines && sourceLines, "a high contrast or source switch eases the outlines' lines")
        // without motion the blend lands on each form exactly
        ShellSettings.reduceMotion = true
        ShellSettings.highContrast = true
        const hcExact = Qt.colorEqual(Theme.menuCardBorder, Theme.withAlpha(Theme.text, Theme.lineAlpha(0.22)))
        ShellSettings.highContrast = false
        ShellSettings.neutralTheme = true
        const neutralExact = Qt.colorEqual(Theme.menuCardBorder, Theme.withAlpha(Theme._lineBase, Theme.lineAlpha(0.105)))
            && Qt.colorEqual(Theme.outline, Theme.withAlpha(Theme._lineBase, Theme.lineAlpha(0.14)))
        root._check(hcExact && neutralExact, "with reduce motion, a mode switch sets the lines at once and exactly: "
            + [hcExact, neutralExact].join(" "))
        MatugenTheme._palette = paletteWas
        for (let i = keys.length - 1; i >= 0; i--) ShellSettings[keys[i]] = saved[i]
    }

    function _checkGlassInks(): void {
        const keys = ["reduceMotion", "neutralTheme", "neutralAccentAuto", "highContrast", "baseTone", "barOpacity",
            "surfaceBlur", "popupMatchBarOpacity", "matugenAccentBalance", "matugenAccentRole", "matugenDepth"]
        const saved = keys.map(key => ShellSettings[key])
        const paletteWas = MatugenTheme._palette
        ShellSettings.reduceMotion = true
        ShellSettings.surfaceBlur = true
        ShellSettings.popupMatchBarOpacity = true
        ShellSettings.barOpacity = 0.58
        ShellSettings.highContrast = false
        ShellSettings.matugenAccentBalance = false
        ShellSettings.matugenAccentRole = "primary"
        const palettes = [
            // matugen at --contrast 1: pure white text
            { background: "#101410", surface: "#1c211b", text: "#ffffff", subtext: "#d6dcd0", accent: "#e8f4e0",
              error: "#ffece9", warning: "#d0f8ff", success: "#e6f3de" },
            { background: "#1a1110", surface: "#271d1c", text: "#f1dfdc", subtext: "#d8c2be", accent: "#ffb4a8",
              error: "#ffb4ab", warning: "#dec48c", success: "#e7bdb6" },
            { background: "#121318", surface: "#1e1f25", text: "#e3e1e9", subtext: "#c6c5d0", accent: "#b9c3ff",
              error: "#ffb4ab", warning: "#e5bad8", success: "#c3c5dd" },
            { background: "#fbf8ff", surface: "#efedf4", text: "#1b1b21", subtext: "#46464f", accent: "#525a92",
              error: "#ba1a1a", warning: "#77536d", success: "#5b5d72" },
            { background: "#fff8f6", surface: "#fceae6", text: "#231918", subtext: "#534341", accent: "#904a40",
              error: "#ba1a1a", warning: "#725b2e", success: "#775651" }
        ]
        const white = Qt.rgba(1, 1, 1, 1), black = Qt.rgba(0, 0, 0, 1)
        for (const neutral of [false, true]) for (const palette of palettes)
        for (const depth of ["none", "deeper"]) {
            ShellSettings.neutralTheme = neutral
            ShellSettings.neutralAccentAuto = true
            ShellSettings.matugenDepth = depth
            ShellSettings.baseTone = depth === "none" ? "graphite" : "black"
            MatugenTheme._palette = palette
            const context = (neutral ? "neutral/" : "wallpaper/") + palette.accent + "/" + depth
            let lowest = Infinity, lowestInk = ""
            const inks = { subtext: Theme.subtext, detail: Theme.menuTextDetail, dependency: Theme.menuTextWarning,
                quiet: Theme.menuTextQuiet, accent: Theme.accentInk, error: Theme.error, warning: Theme.warning,
                success: Theme.success }
            for (const backdrop of [white, black]) {
                const control = Theme._controlOverBackdrop(Theme.background, Theme.text, Theme.popupOpacity, backdrop)
                for (const name in inks) {
                    const contrast = Theme.contrastRatio(inks[name], control)
                    if (contrast < lowest) { lowest = contrast; lowestInk = name }
                }
            }
            root._check(Theme.glass && lowest >= 2.99,
                "captions and status colours on glass read over a white window and a dark one: " + context
                    + " " + lowestInk + " " + lowest)
            root._check(Theme.contrastRatio(Theme.menuTextQuiet, Theme.background)
                    <= Theme.contrastRatio(Theme.menuTextDetail, Theme.background) + 0.01,
                "a quiet caption is never louder than the descriptions it sits among: " + context)
            // a dark menu's caption is lighter than its base and a light menu's darker, whatever the backdrop
            const lightBase = Theme.luminance(Theme.background) > 0.5
            root._check((Theme.luminance(Theme.subtext) > Theme.luminance(Theme.background)) !== lightBase
                    && (Theme.luminance(Theme.menuTextDetail) > Theme.luminance(Theme.background)) !== lightBase,
                "captions on glass stay on their text's side of the base: " + context)
        }
        // an opaque popup leaves every status colour exactly as the palette gave it
        ShellSettings.popupMatchBarOpacity = false
        ShellSettings.neutralTheme = false
        // dim enough that a glass solve would lift it, under an accent far enough off red to leave it alone
        const dim = Object.assign({}, palettes[2], { error: "#6a3b3d" })
        MatugenTheme._palette = dim
        root._check(!Theme.glass && Qt.colorEqual(Theme.error, dim.error)
                && Qt.colorEqual(Theme.subtext, Theme._tSubtextSolid),
            "an opaque popup keeps the palette's own status colours and caption")
        // matugen --contrast -1: its caption arrives near 4:1, and the hierarchy sink took it under 3:1
        const quiet = { background: "#16121b", surface: "#221e28", text: "#a8a0ae", subtext: "#87808e",
            accent: "#a974ff", error: "#ff5449", warning: "#af82ae", success: "#a188ac" }
        for (const depth of ["none", "deep", "deeper"]) {
            MatugenTheme._palette = quiet
            ShellSettings.matugenDepth = depth
            const caption = Theme.contrastRatio(Theme.subtext, Theme.menuControlSolid)
            root._check(caption >= 2.99 && Theme.contrastRatio(Theme._tSubtextSolid, Theme.menuControlSolid) < 2.999
                    && Theme.contrastRatio(Theme.text, Theme.menuControlSolid)
                        > Theme.contrastRatio(Theme.subtext, Theme.menuControlSolid),
                "a low-contrast palette's caption stops sinking where it still reads, under its label: "
                    + depth + " " + caption)
        }
        MatugenTheme._palette = paletteWas
        for (let i = keys.length - 1; i >= 0; i--) ShellSettings[keys[i]] = saved[i]
    }

    // matugen in light mode. Depth used to sink the base under dark ink, and high contrast forced white onto it
    function _checkLightPalette(): void {
        const keys = ["reduceMotion", "neutralTheme", "neutralAccentAuto", "highContrast", "baseTone", "barOpacity",
            "popupMatchBarOpacity", "matugenAccentBalance", "matugenAccentRole", "matugenDepth"]
        const saved = keys.map(key => ShellSettings[key])
        const paletteWas = MatugenTheme._palette
        ShellSettings.reduceMotion = true
        ShellSettings.popupMatchBarOpacity = false
        ShellSettings.barOpacity = 1
        ShellSettings.neutralTheme = false
        const palettes = [
            { background: "#fbf8ff", surface: "#efedf4", text: "#1b1b21", subtext: "#46464f", accent: "#525a92",
              error: "#ba1a1a", warning: "#77536d", success: "#5b5d72" },
            { background: "#fff8f6", surface: "#fceae6", text: "#231918", subtext: "#534341", accent: "#904a40",
              error: "#ba1a1a", warning: "#725b2e", success: "#775651" },
            { background: "#fdf8f8", surface: "#f1eded", text: "#1c1b1b", subtext: "#444748", accent: "#5f5e5e",
              error: "#ba1a1a", warning: "#5f5e5e", success: "#5f5e5e" }
        ]
        for (const palette of palettes) for (const depth of ["none", "deep", "deeper"]) for (const hc of [false, true])
        for (const balance of [false, true]) {
            MatugenTheme._palette = palette
            ShellSettings.matugenDepth = depth
            ShellSettings.highContrast = hc
            ShellSettings.matugenAccentBalance = balance
            const context = [palette.accent, depth, hc, balance].join("/")
            root._check(Theme.paletteLight && Theme._depthK === 0, "a light palette keeps its own base: " + context)
            let lowest = Infinity
            for (const surface of [Theme.menuCardSolid, Theme.menuControlSolid])
                for (const ink of [Theme.text, Theme.subtext, Theme.menuTextDetail, Theme.accent, Theme.error,
                    Theme.warning, Theme.success, Theme.barText, Theme.barAccent])
                    lowest = Math.min(lowest, Theme.contrastRatio(ink, surface))
            root._check(lowest >= 3.99, "text stays readable on a light palette: " + context + " contrast " + lowest)
        }
        const light = palettes[0]
        MatugenTheme._palette = light
        ShellSettings.highContrast = false
        ShellSettings.matugenAccentBalance = false
        const floor = Theme._solveGlassFloor(light.background, light.text, 4.5)
        root._check(Theme.contrastRatio(light.text,
                Theme._controlOverBackdrop(light.background, light.text, floor, Qt.rgba(0, 0, 0, 1))) >= 4.49,
            "light glass holds its text over a dark window, its worst backdrop")
        // the same palette as the neutral base's accent source: its accent was made for a light base
        ShellSettings.neutralTheme = true
        ShellSettings.neutralAccentAuto = true
        for (const palette of palettes) for (const tone of ["black", "charcoal", "graphite"]) {
            MatugenTheme._palette = palette
            ShellSettings.baseTone = tone
            root._check(!Theme.paletteLight && Theme.contrastRatio(Theme.accent, Theme.menuCardSolid) >= 4.5,
                "a light palette's accent stays readable on the neutral base: " + palette.accent + "/" + tone)
        }
        // and a dark palette is left exactly as it was
        const dark = { background: "#1a1110", surface: "#271d1c", text: "#f1dfdc", subtext: "#d8c2be", accent: "#ffb4a8",
            error: "#ffb4ab", warning: "#dec48c", success: "#e7bdb6" }
        MatugenTheme._palette = dark
        ShellSettings.neutralTheme = false
        ShellSettings.matugenDepth = "deeper"
        ShellSettings.matugenAccentBalance = false
        root._check(!Theme.paletteLight && Theme._depthK === 0.80 && Qt.colorEqual(Theme.accent, dark.accent)
                && Theme._accentPresetL === 70.8,
            "a dark palette keeps its depth, accent and balance target")
        MatugenTheme._palette = paletteWas
        for (let i = keys.length - 1; i >= 0; i--) ShellSettings[keys[i]] = saved[i]
    }

    function _checkConnectivityBarActions(): void {
        const was = { open: MenuState.open, tab: MenuState.activeTab, previous: MenuState.previousTab,
            anchor: MenuState.anchorSource, x: MenuState.anchorX, screen: MenuState.triggerScreen }
        const screen = Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        const wifiWas = Network.wifiEnabled
        const btWas = Bluetooth.enabled
        const pickers = { NetworkWidget: "wifi", BluetoothWidget: "bt", BrightnessWidget: "brightness", BatteryWidget: "power" }
        for (const name of Object.keys(pickers)) {
            const component = Qt.createComponent("modules/bar/widgets/" + name + ".qml")
            const widget = component.status === Component.Ready
                ? component.createObject(barFixtureHost, { screen: screen }) : null
            root._check(widget !== null && widget.interactive === widget.show,
                name + " offers its Home action whenever its status is shown")
            if (widget) {
                // exercise routing without requiring physical devices in CI
                widget.interactive = true
                widget.collapsed = false
                widget.visible = true
                MenuState.close()
                MenuState.selectTab(MenuState.settingsTab)
                widget.Accessible.pressAction()
                root._check(MenuState.open && MenuState.homeActive
                        && MenuState.anchorSource === widget && MenuState.triggerScreen === screen
                        && Network.wifiEnabled === wifiWas && Bluetooth.enabled === btWas,
                    name + " opens Home on its own screen without changing either radio")
                root._check(MenuState.homePicker === pickers[name],
                    name + " asks Home for its own picker")
                MenuState.close()
                root._check(MenuState.homePicker === "", name + "'s picker request goes with the menu")
                widget.barActive = false
                widget.activated()
                root._check(!MenuState.open, name + " rejects activation while its bar is inactive")
                widget.barActive = true
                widget.visible = false
                widget.activated()
                root._check(!MenuState.open, name + " rejects activation after it is hidden")
                widget.destroy()
            }
            component.destroy()
        }
        // the pill's right-click goes to the app Home's own "settings" rows open, and is offered only where one is installed
        const secondTools = SystemTools._tools
        const owners = { NetworkWidget: "nm-connection-editor", BluetoothWidget: "blueman-manager", SystemWidget: "missioncenter" }
        for (const name of Object.keys(owners)) {
            const component = Qt.createComponent("modules/bar/widgets/" + name + ".qml")
            const widget = component.status === Component.Ready ? component.createObject(barFixtureHost, { screen: screen }) : null
            SystemTools._tools = {}
            const without = widget !== null && !widget.hasSecondary
            SystemTools._tools = { [owners[name]]: true }
            root._check(without && widget.hasSecondary,
                name + " offers its right-click only where " + owners[name] + " is installed")
            if (widget) widget.destroy()
            component.destroy()
        }
        SystemTools._tools = secondTools
        const btComponent = Qt.createComponent("modules/bar/widgets/BluetoothWidget.qml")
        const bt = btComponent.status === Component.Ready ? btComponent.createObject(barFixtureHost, { screen: screen }) : null
        root._check(bt !== null && bt.restText(false, 64) === "64%" && bt.restText(false, 0) === "0%"
                && bt.restText(true, 64) === "" && bt.restText(false, -1) === "",
            "with values shown at rest, Bluetooth reads one device's charge beside its glyph, and nothing on a hover-only bar or without a reading")
        root._check(bt !== null && bt.lowCharge(SystemAlerts.btLowPct - 1) && !bt.lowCharge(SystemAlerts.btLowPct)
                && !bt.lowCharge(-1),
            "a Bluetooth device's glyph warns below the charge its low-battery alert fires at")
        if (bt) bt.destroy()
        btComponent.destroy()
        const volComponent = Qt.createComponent("modules/bar/widgets/Volume.qml")
        const vol = volComponent.status === Component.Ready ? volComponent.createObject(barFixtureHost) : null
        root._check(vol !== null && vol.outputLow(SystemAlerts.btLowPct - 1) && !vol.outputLow(SystemAlerts.btLowPct)
                && !vol.outputLow(-1),
            "the volume glyph warns below the same mark when its output is a Bluetooth device")
        if (vol) vol.destroy()
        volComponent.destroy()
        MenuState.selectTab(was.tab)
        MenuState._previousTab = was.previous
        if (was.open) MenuState.openAt(was.x, was.screen, was.anchor)
    }

    function _checkHomeWidgetPickers(home): void {
        const toolsWas = SystemTools._tools
        const brightnessWas = { device: Brightness._device, max: Brightness.maxBrightness,
            level: Brightness.currentBrightness, pending: Brightness.pendingPercent,
            ready: Brightness.ready, devices: Brightness.devices }
        let requested = null
        home.controlRequested.connect(control => requested = control)
        SystemTools._tools = Object.assign({}, toolsWas, {
            busctl: false, powerprofilesctl: true, brightnessctl: true
        })
        MenuState.homePicker = "power"
        root._check(MenuState.homePicker === "" && home._picker === "power"
                && requested && requested.title === "Power Mode",
            "the battery shortcut consumes its request and reveals power choices without changing the profile")

        Brightness._device = "__silere_widget_probe__"
        Brightness.maxBrightness = 100
        Brightness.currentBrightness = 50
        Brightness.ready = true
        Brightness.devices = [{ name: "__silere_widget_probe__" }]
        requested = null
        MenuState.homePicker = "brightness"
        const slider = requested ? root._findTrayNode(requested, item => item.accessibleName === "Brightness") : null
        root._check(home._picker === "" && requested && !requested.open && slider,
            "the brightness shortcut closes the other picker and reveals its single-backlight slider")
        const presentationWas = Audio._profilePresentation
        Audio._profilePresentation = { ready: true, micReady: true, volume: 0.5, effectiveVolume: 0.5, muted: false,
            name: "Probe output", micVolume: 0.5, micEffectiveVolume: 0.5, micMuted: false, sourceName: "Probe input" }
        const volumeRow = root._findTrayNode(home, item => item._hasApps !== undefined && item.closeInline !== undefined)
        const brightnessRow = root._findTrayNode(home, item => item._hasApps === undefined
            && item.closeInline !== undefined && item.reserveExpandSlot !== undefined)
        root._check(volumeRow && brightnessRow && volumeRow.visible && volumeRow.expandable && Audio.sinkCount < 2
                && !brightnessRow.expandable && brightnessRow.reserveExpandSlot && !volumeRow.reserveExpandSlot,
            "a volume chevron that only a microphone opens keeps the brightness track the same length")
        Audio._profilePresentation = presentationWas
        Brightness.devices = [{ name: "__silere_widget_probe__" }, { name: "__silere_second_backlight__" }]
        MenuState.homePicker = "brightness"
        root._check(requested && requested.open && Brightness.currentBrightness === 50,
            "multiple backlights open the device choices without changing the brightness")

        let requestedChoices = null
        const noteChoices = (control, choices) => requestedChoices = choices
        home.controlRequested.connect(noteChoices)
        home._closePicker()
        requested = null
        home._togglePicker("power")
        root._check(home._picker === "power" && requested && requested.title === "Power Mode"
                && requestedChoices && requestedChoices.above === Metrics.barAtBottom,
            "a picker opened by hand asks to be brought into view with the list drawn for it")
        requested = null
        home._togglePicker("power")
        root._check(home._picker === "" && requested === null, "closing a picker scrolls nothing")
        home._togglePicker("battery")
        root._check(home._picker === "battery" && requested && requested.sizeText !== undefined,
            "battery details opened at the foot of Home bring the system readings into view")
        const vitals = root._findTrayNode(home, item => item.batteryOpenable !== undefined && item.batteryShown !== undefined)
        const limitsWas = BatteryLimit.devices
        BatteryLimit.devices = [{ path: "/org/freedesktop/UPower/devices/battery_PROBE", nativePath: "PROBE",
            on: false, stopsAt: 80 }]
        if (vitals) vitals.batteryShown = true
        const detailsOpen = vitals !== null && vitals.batteryOpenable && home._picker === "battery"
        if (vitals) vitals.batteryShown = false
        root._check(detailsOpen && !vitals.batteryOpenable && home._picker === "",
            "battery details close with a battery UPower lost, so the next Escape is not spent on them")
        if (vitals) vitals.batteryShown = Qt.binding(() => Battery.available)
        BatteryLimit.devices = limitsWas
        home._closePicker()
        home.controlRequested.disconnect(noteChoices)

        SystemTools._tools = Object.assign({}, SystemTools._tools, { powerprofilesctl: false })
        requested = null
        MenuState.homePicker = "power"
        root._check(home._picker === "" && requested && requested.sizeText !== undefined,
            "without power profiles the battery shortcut closes inline controls and reveals system readings")

        Brightness._device = brightnessWas.device
        Brightness.maxBrightness = brightnessWas.max
        Brightness.currentBrightness = brightnessWas.level
        Brightness.pendingPercent = brightnessWas.pending
        Brightness.ready = brightnessWas.ready
        Brightness.devices = brightnessWas.devices
        SystemTools._tools = toolsWas
    }

    function _checkMenuContrast(): void {
        root._check(Math.abs(Theme.contrastRatio(Qt.color("white"), Qt.color("black")) - 21) < 0.001
                && Math.abs(Theme.contrastRatio(Qt.rgba(1, 1, 1, 0), Qt.color("black")) - 1) < 0.001,
            "menu contrast measurement composites translucent text over its reference surface")
        root._check(Qt.colorEqual(Theme.readableText(Qt.color("white"), Qt.color("black"), 4.5), Qt.color("white")),
            "already legible menu text keeps its exact color")
        for (const surface of [Qt.color("#111111"), Qt.color("#eeeeee")]) {
            const readable = Theme.readableText(surface, surface, 4.5)
            root._check(Theme.contrastRatio(readable, surface) >= 4.5,
                "low-contrast text gains only the contrast it needs on light and dark surfaces")
        }
        const saved = [ShellSettings.neutralTheme, ShellSettings.highContrast,
            ShellSettings.baseTone, ShellSettings.matugenDepth, ShellSettings.reduceMotion]
        ShellSettings.reduceMotion = true
        for (const neutral of [true, false]) {
            ShellSettings.neutralTheme = neutral
            for (const hc of [false, true]) {
                ShellSettings.highContrast = hc
                for (let i = 0; i < 3; i++) {
                    ShellSettings.baseTone = ["black", "charcoal", "graphite"][i]
                    ShellSettings.matugenDepth = ["deeper", "deep", "none"][i]
                    root._check(Theme.contrastRatio(Theme.menuTextDetail, Theme.menuControlSolid) >= 4.5
                            && Theme.contrastRatio(Theme.menuTextDetail, Theme.menuCardSolid) >= 4.5
                            && Theme.contrastRatio(Theme.menuTextWarning, Theme.menuControlSolid) >= 4.5,
                        "menu caption and dependency contrast holds for " + (neutral ? "neutral" : "wallpaper")
                            + " depth " + i + (hc ? " with high contrast" : ""))
                }
            }
        }
        ShellSettings.neutralTheme = saved[0]
        ShellSettings.highContrast = saved[1]
        ShellSettings.baseTone = saved[2]
        ShellSettings.matugenDepth = saved[3]
        ShellSettings.reduceMotion = saved[4]
    }

    function _checkPowerRail(): void {
        const component = Qt.createComponent("modules/menu/PowerRailRow.qml")
        const host = barLeftFactory.createObject(null)
        const row = component.status === Component.Ready
            ? component.createObject(host, { width: 196, confirm: true, label: "Reboot" }) : null
        root._check(row !== null, "the power rail builds for confirmation lifecycle checks")
        const motionWas = ShellSettings.reduceMotion
        if (row) {
            let actions = 0
            row.triggered.connect(() => actions++)
            ShellSettings.reduceMotion = false
            row.activate()
            root._check(row.armed && actions === 0,
                "a power action arms without running its command")
            row.activate()
            root._check(row.armed && actions === 0,
                "a double-click cannot confirm a power action")
            for (const offset of [-row.confirmTimeout - 1, 1000]) {
                row._confirmStartedMs = Date.now() + offset
                row.activate()
                root._check(row.armed && actions === 0
                        && row._confirmStartedMs <= Date.now()
                        && Date.now() - row._confirmStartedMs < Metrics.confirmGuardMs,
                    "an expired or future-dated power confirmation rearms before an overdue timer runs")
            }
            ShellSettings.reduceMotion = true
            root._check(row.armed && row._confirmProgress === 0,
                "enabling reduce motion stops a power confirmation's countdown animation")
            row.visible = false
            row.Accessible.pressAction()
            root._check(!row.armed && actions === 0,
                "hiding a power row disarms it and blocks accessible activation")
            row.visible = true
            row.activate()
            host.visible = false
            row.activate()
            root._check(!row.armed && actions === 0,
                "a hidden parent disarms its power confirmations too")
            row.destroy()
            const reopened = component.createObject(root, { width: 196, confirm: true, label: "Reboot" })
            reopened.triggered.connect(() => actions++)
            reopened.activate()
            reopened._confirmStartedMs = Date.now() - Metrics.confirmGuardMs - 1
            reopened.activate()
            root._check(!reopened.armed && actions === 1,
                "a newly opened power row still requires a deliberate second press")
            reopened.destroy()
        }
        ShellSettings.reduceMotion = motionWas
        host.destroy()
        component.destroy()
    }

    function _checkStackTags(): void {
        root._check(Notifications.stackTagOf({ hints: { "x-canonical-private-synchronous": "volume" } }) === "volume"
                && Notifications.stackTagOf({ hints: { "x-dunst-stack-tag": "bright" } }) === "bright"
                && Notifications.stackTagOf({ hints: {} }) === "" && Notifications.stackTagOf(null) === "",
            "the dunst and canonical stack tag hints name a notification's stack")
        const make = (id, app, tag) => Qt.createQmlObject("import QtQuick; QtObject { property int id: " + id
            + "; property string appName: \"" + app + "\"; property var hints: ({}); property bool tracked: true }", root)
        const same = make(9001, "volscript", ""), plain = make(9002, "volscript", ""), other = make(9003, "elsewhere", "")
        const next = make(9004, "volscript", "")
        same.hints = { "x-canonical-private-synchronous": "volume" }
        other.hints = { "x-canonical-private-synchronous": "volume" }
        next.hints = { "x-dunst-stack-tag": "volume" }
        const listWas = Notifications.list
        Notifications.list = [same, plain, other].map(n => ({ notification: n, id: n.id, time: 1000 }))
        const replaced = Notifications._retireStacked(next)
        const kept = Notifications.list.map(e => e.id)
        root._check(replaced && kept.length === 2 && kept[0] === 9002 && kept[1] === 9003 && !same.tracked && plain.tracked && other.tracked,
            "a tagged notification replaces the same app's card with that tag and leaves every other card alone")
        Notifications._consumeClosing(9001, same)
        Notifications.list = listWas
        for (const n of [same, plain, other, next]) n.destroy()

        const a = { n: "a" }, b = { n: "b" }, c = { n: "c" }, d = { n: "d" }
        const merged = Notifications.popupsWithLeaving([a, b, c], [a, c, d], [b])
        const first = Notifications.popupsWithLeaving([a, b, c], [b, c], [a])
        const gone = Notifications.popupsWithLeaving([a, b, c], [a, c], [])
        const order = (got, want) => got.length === want.length && got.every((v, i) => v === want[i])
        root._check(order(merged, [a, b, c, d]) && order(first, [a, b, c]) && order(gone, [a, c]),
            "the popup stack keeps a leaving card where it was, keeps the live order and drops a card that is not leaving")
    }

    function _checkThreadFolding(): void {
        // transient: the folded fixtures stay out of the real history
        const make = (id, app, summary, body) => ({
            id: id, appName: app, summary: summary, body: body, urgency: 1, hints: {},
            tracked: true, transient: true, expire() { this.tracked = false }
        })
        const listWas = Notifications.list
        const groupWas = ShellSettings.notifGroupThreads
        const replyingWas = Notifications.replyingId
        ShellSettings.notifGroupThreads = true
        Notifications.replyingId = -1

        const a1 = make(9101, "Chat", "Alex", "one"), mail = make(9102, "Mail", "Alex", "other app")
        const a2 = make(9103, "Chat", "Alex", "two\n  lines"), a3 = make(9104, "Chat", "Alex", "three")
        const crit = make(9105, "Chat", "Alex", "urgent"), tagged = make(9106, "Chat", "Alex", "tagged")
        const progress = make(9107, "Chat", "Alex", "50%"), blank = make(9108, "Chat", "", "no sender")
        crit.urgency = 2
        tagged.hints = { "x-dunst-stack-tag": "alex" }
        progress.hints = { "value": 50 }
        root._check(Notifications.threadKeyOf(a1) === Notifications.threadKeyOf(a3)
                && Notifications.threadKeyOf(a1) !== Notifications.threadKeyOf(mail)
                && Notifications.threadKeyOf(crit) === "" && Notifications.threadKeyOf(tagged) === ""
                && Notifications.threadKeyOf(progress) === "" && Notifications.threadKeyOf(blank) === ""
                && Notifications.threadKeyOf(null) === "",
            "a thread is one app and sender, never a critical, stack-tagged, progress or unnamed card")

        Notifications.list = [a1, mail, a2].map((n, i) => ({ notification: n, id: n.id, time: 1000 + i }))
        let foldedIn = []
        const watch = ids => { foldedIn = ids }
        Notifications.threadFoldedInPlace.connect(watch)
        const folded = Notifications._foldThread(a3)
        const thread = Notifications.threadFor(a3.id)
        root._check(folded && Notifications.list.length === 1 && Notifications.list[0].id === 9102
                && !a1.tracked && !a2.tracked && mail.tracked
                && thread && thread.count === 3 && thread.lines.length === 2
                && thread.lines[0] === "one" && thread.lines[1] === "two lines",
            "a new message folds the same sender's cards into one thread, oldest line first, and leaves other apps alone")
        root._check(foldedIn.length === 2 && foldedIn.indexOf("9103") >= 0,
            "folding the newest card on screen is announced so the stack replaces it in place")

        const a4 = make(9109, "Chat", "Alex", "four")
        Notifications.list = [{ notification: a3, id: a3.id, time: 1003 }]
        Notifications.replyingId = a3.id
        root._check(!Notifications._foldThread(a4) && a3.tracked,
            "a card with an open reply is never folded away under the person typing")
        Notifications.replyingId = -1
        foldedIn = []
        root._check(Notifications._foldThread(a4) && !a3.tracked
                && Notifications.threadFor(a4.id).count === 4
                && Notifications.threadFor(a4.id).lines.join("|") === "one|two lines|three"
                && Notifications.threadFor(a3.id) === null,
            "a thread carries its count forward, keeps its last three lines, and drops the folded card's state")

        const a5 = make(9110, "Chat", "Alex", "five")
        Notifications.list = [{ notification: a4, id: a4.id, time: 1004 }]
        ShellSettings.notifGroupThreads = false
        root._check(!Notifications._foldThread(a5) && a4.tracked,
            "with grouping off every message keeps its own card")
        Notifications._forgetState(a4.id)
        root._check(Notifications.threadFor(a4.id) === null,
            "forgetting a notification forgets its thread")

        const mutedWas = ShellSettings.notifMutedApps
        const bypassWas = ShellSettings.notifCriticalBypass
        ShellSettings.notifMutedApps = ""
        ShellSettings.setNotifAppMuted("Team, Inc.", true)
        ShellSettings.setNotifAppMuted("Chat", true)
        ShellSettings.setNotifAppMuted("Chat", true)
        root._check(ShellSettings.notifMutedAppNames.length === 2
                && ShellSettings.notifAppMuted("Team, Inc.") && !ShellSettings.notifAppMuted("Team")
                && ShellSettings._coerced(ShellSettings.schemaFor("notifMutedApps"), ShellSettings.notifMutedApps).ok,
            "muted app names round-trip through the stored list, commas included, without duplicates")
        ShellSettings.notifCriticalBypass = true
        root._check(Notifications.mutesPopup(a1)
                && !Notifications.mutesPopup(mail) && !Notifications.mutesPopup(null),
            "a muted app's popups are held back, other apps are not")
        root._check(!Notifications.mutesPopup(crit),
            "a critical alert from a muted app follows the same bypass as do not disturb")
        ShellSettings.notifCriticalBypass = false
        root._check(Notifications.mutesPopup(crit),
            "without the critical bypass a muted app stays muted")
        ShellSettings.setNotifAppMuted("Chat", false)
        root._check(!Notifications.mutesPopup(a1) && ShellSettings.notifAppMuted("Team, Inc."),
            "unmuting one app leaves the others muted")
        ShellSettings.setNotifAppMuted("Unknown", true)
        root._check(Notifications.mutesPopup({ appName: " ", urgency: 1 })
                && !Notifications.mutesPopup({ appName: "Probe", urgency: 1 }),
            "muting history's Unknown page mutes the senders with no name it lists")
        ShellSettings.notifCriticalBypass = bypassWas
        ShellSettings.notifMutedApps = mutedWas

        Notifications.threadFoldedInPlace.disconnect(watch)
        for (const n of [a1, a2, a3]) Notifications._consumeClosing(n.id, n)
        Notifications._forgetTrimmed(["9101", "9103", "9104", "9109", "9110"])
        Notifications.list = listWas
        Notifications.replyingId = replyingWas
        ShellSettings.notifGroupThreads = groupWas
    }

    function _checkBrightnessChoices(): void {
        const labels = list => Brightness.choicesFor(list.map(name => ({ name: name, type: "raw" })))
            .map(c => c.label).join("|")
        root._check(labels(["amdgpu_bl2", "nvidia_0"]) === "Automatic|AMD graphics|NVIDIA graphics"
                && labels(["ddcci5"]) === "Automatic|External display"
                && labels(["weird_bl"]) === "Automatic|weird_bl",
            "backlight choices read as the hardware they drive")
        root._check(labels(["acpi_video0", "acpi_video1", "intel_backlight"])
                === "Automatic|acpi_video0|acpi_video1|Intel graphics",
            "two backlights of one kind keep their own names")
        const names = raw => Brightness.parseDevices(raw).map(d => d.name).join("|")
        root._check(names("amdgpu_bl2\traw\t65535\t0\nnvidia_0\traw\t100\t1\n") === "amdgpu_bl2"
                && names("amdgpu_bl1\traw\t255\t1\nnvidia_0\traw\t100\t0\n") === "nvidia_0"
                && names("amdgpu_bl2\traw\t65535\t1\nnvidia_0\traw\t100\t1\n") === "amdgpu_bl2|nvidia_0"
                && names("acpi_video0\tfirmware\t15\nbad name\traw\t9\t0\nzero\traw\t0\t0\n") === "acpi_video0",
            "a backlight whose panel is disconnected is not offered unless every backlight is")
    }

    function _checkBluetoothRowRelease(): void {
        const connecting = Bt.BluetoothDeviceState.Connecting
        const disconnecting = Bt.BluetoothDeviceState.Disconnecting
        const connected = Bt.BluetoothDeviceState.Connected
        root._check(Bluetooth.deviceBusy(connecting, false, false)
                && Bluetooth.deviceBusy(disconnecting, false, false)
                && !Bluetooth.deviceBusy(connected, false, false),
            "a Bluetooth row is busy only while its device is changing state")
        root._check(!Bluetooth.deviceBusy(connecting, false, true),
            "a timed-out Bluetooth attempt releases its row even if the device still says connecting")
        root._check(!Bluetooth.deviceBusy(connecting, true, false),
            "a pairing row stays usable so it can be cancelled")
        const dev = (name, paired, connected, pairing) => ({ address: "4E:5B:85:24:93:E7",
            deviceName: name, paired: paired, connected: connected, pairing: pairing })
        root._check(!Bluetooth.listed(dev("", false, false, false))
                && !Bluetooth.listed(dev("4E-5B-85-24-93-E7", false, false, false))
                && Bluetooth.listed(dev("JBL GO 2", false, false, false)),
            "the Bluetooth picker leaves out an unpaired device known only by its address")
        root._check(Bluetooth.listed(dev("", true, false, false))
                && Bluetooth.listed(dev("", false, true, false))
                && Bluetooth.listed(dev("", false, false, true)),
            "a nameless device stays listed while paired, connected or pairing")
    }

    function _checkBarSizing(): void {
        const scaleWas = ShellSettings.uiScale
        const heightWas = ShellSettings.barHeight
        const motionWas = ShellSettings.reduceMotion
        const helperWas = ShellSettings.mediaWidgetHelper
        ShellSettings.reduceMotion = true
        ShellSettings.mediaWidgetHelper = true
        const media = mediaWidgetFactory.createObject(barFixtureHost)
        for (const scale of [1, 1.25, 1.5]) {
            ShellSettings.uiScale = scale
            for (const height of [24, 28, 36, 44]) {
                ShellSettings.barHeight = height
                const actualHeight = Metrics.barHeight ?? ShellSettings.barHeight
                root._check(actualHeight >= Metrics.barRowHeight + 4 && actualHeight >= height,
                    "bar height leaves room for its controls at " + scale + "x / " + height + "px")
                root._check(Metrics.popupClearance(8) >= Metrics.barEdgeInset + actualHeight + 8,
                    "popups clear the actual bar height at " + scale + "x / " + height + "px")
            }
            const icon = root._findTrayNode(media, item => item.text === media._playGlyph && item.font !== undefined)
            root._check(icon && icon.parent.width >= Metrics.iconCellFor(icon.font.pixelSize),
                "the media helper keeps a full icon cell at " + scale + "x")
        }
        media.destroy()
        ShellSettings.uiScale = scaleWas
        ShellSettings.barHeight = heightWas
        ShellSettings.reduceMotion = motionWas
        ShellSettings.mediaWidgetHelper = helperWas
    }

    function _checkWorkspaceIndicators(): void {
        const keys = ["reduceMotion", "wsShowNumbers", "wsShowAppIcons", "wsUrgentPulse",
            "valuesOnHover", "uiScale", "barIconSize"]
        const saved = keys.map(key => ShellSettings[key])
        ShellSettings.reduceMotion = true
        ShellSettings.wsShowNumbers = false
        ShellSettings.wsShowAppIcons = false
        ShellSettings.wsUrgentPulse = false
        const cell = workspaceButtonFactory.createObject(barFixtureHost, {
            wsId: 12, monitorReady: true, active: false, occupied: false,
            urgent: false, apps: [], compact: false, iconSize: 14,
            cellWidth: 40, rowHeight: 24, barActive: true,
            initialized: true, paging: false, markerCovers: true,
            workspaceName: "Research"
        })
        const dot = root._findTrayNode(cell, item => item.objectName === "workspace-dot")
        const urgent = root._findTrayNode(cell, item => item.objectName === "workspace-urgent-mark")
        root._check(dot && dot.color.a === 0 && dot.children.some(child => child.outlineColor?.a > 0),
            "an empty workspace uses an outlined indicator rather than a dim occupied dot")
        const emptyWidth = dot ? dot.width : 0
        cell.occupied = true
        root._check(dot && dot.color.a > 0 && dot.width > emptyWidth,
            "an occupied workspace has a larger filled indicator")
        ShellSettings.wsShowAppIcons = true
        cell.apps = [{ icon: "", fallback: "F", name: "Firefox", count: 1 }]
        cell.hiddenAppCount = 2
        cell.urgent = true
        root._check(urgent && urgent.visible && cell._pulseOpacity === 1
                && !ShellSettings.wsUrgentPulse,
            "an urgent workspace remains marked with app icons and urgency animation disabled")
        root._check(cell.Accessible.name.indexOf("Research") >= 0
                && cell.Accessible.description.indexOf("Needs attention") >= 0
                && cell.Accessible.description.indexOf("Firefox") >= 0
                && cell.Accessible.description.indexOf("2 more applications") >= 0,
            "workspace accessibility exposes its name, urgency and hidden applications")
        const overflow = root._findTrayNode(cell, item => item.objectName === "workspace-app-overflow")
        root._check(overflow && overflow.visible && overflow.text === "+2" && overflow.width >= overflow.implicitWidth,
            "hidden workspace apps have a readable overflow count")
        cell.hiddenAppCount = 20
        root._check(overflow && overflow.text === "9+",
            "large app overflow counts stay within their reserved cell")
        cell.apps = cell.apps.concat([{ icon: "", fallback: "T", name: "Terminal", count: 1 }])
        cell.compact = true
        root._check(cell.Accessible.description.indexOf("Firefox") >= 0
                && cell.Accessible.description.indexOf("Terminal") < 0,
            "compact workspace descriptions count hidden icons without listing them twice")
        cell.urgent = false
        root._check(urgent && !urgent.visible,
            "the persistent urgent indicator clears when the workspace no longer needs attention")
        cell.destroy()
        const strip = workspaceStripFactory.createObject(barFixtureHost)
        ShellSettings.wsShowNumbers = true
        for (const scale of [1, 1.5]) {
            ShellSettings.uiScale = scale
            const measure = Qt.createQmlObject('import QtQuick; TextMetrics {}', root)
            measure.font.family = Settings.font
            measure.font.pixelSize = Settings.fontLabel
            measure.text = "1000000"
            root._check(strip._btnW(1000000) >= Math.ceil(measure.advanceWidth * 1.12) + 10,
                "long workspace numbers fit their cells at " + scale + "x")
            ShellSettings.barIconSize = 20
            root._check(strip._iconSz <= strip.btnH - 4,
                "large workspace icons leave room for state indicators at " + scale + "x")
            measure.destroy()
        }
        strip.destroy()
        const tick = workspaceUrgentTickFactory.createObject(barFixtureHost, {
            liveId: 17, rowHeight: 24, barActive: true, before: true
        })
        root._check(tick.Accessible.description.indexOf("Before") >= 0 && tick.width >= 24,
            "an urgent workspace outside the page has a full-size directional target")
        tick.before = false
        root._check(tick.Accessible.description.indexOf("After") >= 0,
            "the urgent target follows its side of the current page")
        tick.destroy()
        {
            const highlightWas = ShellSettings.barHoverHighlight, pulseWas = ShellSettings.wsUrgentPulse
            ShellSettings.wsUrgentPulse = false
            const host = keyboardFixtureFactory.createObject(root)
            const hovered = workspaceUrgentTickFactory.createObject(host.contentItem, {
                liveId: 4, rowHeight: 24, barActive: true, x: 200, y: 300
            })
            const label = root._findTrayNode(hovered, item => item.text !== undefined && item._hot !== undefined)
            host.requestActivate()
            ShellSettings.barHoverHighlight = false
            host.input.mouseMove(hovered, hovered.width / 2, hovered.height / 2)
            const quiet = label && label.opacity === 0.9 && label.scale === 1
            ShellSettings.barHoverHighlight = true
            root._check(quiet && label._hot && label.opacity === 1,
                "an urgent workspace tick brightens under the pointer only with hover highlights on")
            hovered.destroy()
            host.destroy()
            ShellSettings.barHoverHighlight = highlightWas
            ShellSettings.wsUrgentPulse = pulseWas
        }
        for (let i = 0; i < keys.length; i++) ShellSettings[keys[i]] = saved[i]
    }

    function _checkAccentPills(): void {
        const was = ShellSettings.barAccentPills
        // a see-through bar and a dark accent, so the mark, the label and the menu's accent are three colours
        const themeKeys = ["reduceMotion", "neutralTheme", "neutralAccentAuto", "neutralAccent", "barOpacity"]
        const themeWas = themeKeys.map(key => ShellSettings[key])
        ShellSettings.reduceMotion = true
        ShellSettings.neutralTheme = true
        ShellSettings.neutralAccentAuto = false
        ShellSettings.neutralAccent = "#23509a"
        ShellSettings.barOpacity = 0.58
        const pill = pillFactory.createObject(root, { text: "48%" })
        ShellSettings.barAccentPills = false
        root._check(Qt.colorEqual(pill._restGlyphColor, Theme.barText),
            "bar icons rest at the neutral text colour by default")
        ShellSettings.barAccentPills = true
        root._check(Qt.colorEqual(pill._restGlyphColor, Theme.barAccentMark)
                && !Qt.colorEqual(Theme.barAccentMark, Theme.barAccent)
                && Qt.colorEqual(pill.levelColor, Theme.barAccentMark)
                && Qt.colorEqual(pill.textColor, Theme.barSubtext),
            "accent widget icons tint the glyph and leave the text alone")
        pill.glyphColor = Theme.subtext
        const inactive = Qt.colorEqual(pill._restGlyphColor, Theme.subtext)
        pill.glyphColor = Theme.warning
        const warning = Qt.colorEqual(pill._restGlyphColor, Theme.warning)
        pill.glyphColor = Theme.error
        root._check(inactive && warning && Qt.colorEqual(pill._restGlyphColor, Theme.error),
            "accent widget icons keep inactive, warning and error glyphs meaningful")
        pill.destroy()
        ShellSettings.barAccentPills = was
        for (let i = themeKeys.length - 1; i >= 0; i--) ShellSettings[themeKeys[i]] = themeWas[i]
    }

    function _checkSystemWidget(): void {
        const was = {
            show: ShellSettings.barShowSystem, cpu: ShellSettings.systemShowCpu,
            mem: ShellSettings.systemShowMemory, temp: ShellSettings.systemShowTemp,
            ready: SysInfo.cpuReady, pct: SysInfo.cpuPct, high: SysInfo.cpuHigh,
            busy: SysInfo._cpuBusySamples, active: SysInfo._active,
            cpuTotal: SysInfo._lastCpuTotal, cpuIdle: SysInfo._lastCpuIdle,
            total: SysInfo.memTotalKb, avail: SysInfo.memAvailKb,
            hoverValues: ShellSettings.valuesOnHover
        }
        ShellSettings.valuesOnHover = false
        // off, so SysInfo stays inactive and keeps the readings written here
        ShellSettings.barShowSystem = false
        ShellSettings.systemShowCpu = true
        ShellSettings.systemShowMemory = true
        ShellSettings.systemShowTemp = false
        SysInfo.cpuReady = true
        SysInfo.cpuPct = 0.14
        SysInfo.cpuHigh = false
        SysInfo._cpuBusySamples = 0
        SysInfo.memTotalKb = 32 * 1048576
        SysInfo.memAvailKb = 32 * 1048576 * 0.68
        const w = systemWidgetFactory.createObject(barFixtureHost)
        const wRow = w.children.find(item => typeof item.forceLayout === "function")
        root._check(w.text === "14%" && w.glyph === "󰍛" && w.severity === 0
                && w.segments.length === 1 && w.segments[0].glyph === "󰘚" && w.segments[0].text === "32%"
                && w._parts[1].detail === "10 GB of 32 GB",
            "the system monitor reads CPU then memory, each beside its own glyph, with the amounts on hover")
        root._check(w.reserveText === "00%" && w.segments[0].reserve === "00%",
            "the monitor reserves two digits per reading so ticking values keep its width")
        wRow.forceLayout()
        const twoDigitW = w.rowWidth
        SysInfo.cpuPct = 0.06
        wRow.forceLayout()
        root._check(w.text === "6%" && w.rowWidth === twoDigitW && twoDigitW > 0,
            "a one-digit reading fills its reserve and keeps to its own glyph")
        SysInfo._active = true
        SysInfo._clearCpuSample()
        SysInfo._applyCpuStat("cpu 100 0 0 100 0 0 0 0\n")
        SysInfo._applyCpuStat("cpu 200 0 0 100 0 0 0 0\n")
        const single = w.severity === 0
        SysInfo._applyCpuStat("cpu 300 0 0 100 0 0 0 0\n")
        const rose = w.severity === 1
        const second = systemWidgetFactory.createObject(barFixtureHost)
        root._check(single && rose && SysInfo.cpuPct === 1 && second.severity === 1,
            "identical 100% CPU samples warn on every monitor, including a newly created widget")
        second.destroy()
        SysInfo._applyCpuStat("cpu 380 0 0 120 0 0 0 0\n")
        const held = w.severity === 1
        SysInfo._applyCpuStat("cpu 440 0 0 160 0 0 0 0\n")
        root._check(held && w.severity === 0,
            "the CPU warning holds as load eases and lets go only well below its entry threshold")
        SysInfo._applyCpuStat("cpu 540 0 0 160 0 0 0 0\n")
        SysInfo._applyCpuStat("cpu 620 0 0 180 0 0 0 0\n")
        SysInfo._applyCpuStat("cpu 720 0 0 180 0 0 0 0\n")
        root._check(w.severity === 0,
            "separate CPU spikes do not count as consecutive busy samples")
        SysInfo._applyCpuStat("cpu 820 0 0 180 0 0 0 0\n")
        SysInfo._applyCpuStat("cpu broken\n")
        root._check(!SysInfo.cpuHigh && SysInfo._cpuBusySamples === 0 && w.severity === 0,
            "a failed CPU read clears both the warning and its sample count")
        SysInfo._active = was.active
        SysInfo.memAvailKb = 32 * 1048576 * 0.24
        const memWarned = w.severity === 1
        SysInfo.memAvailKb = 32 * 1048576 * 0.26
        const memHeld = w.severity === 1
        SysInfo.memAvailKb = 32 * 1048576 * 0.29
        root._check(memWarned && memHeld && w.severity === 0
                && SysInfo.usageLevel(0.88, 2) === 2 && SysInfo.usageLevel(0.86, 2) === 1
                && SysInfo.usageLevel(0.74, 0) === 0 && SysInfo.usageLevel(0.95, 0) === 2,
            "memory and disk warnings let go only three points under their line, so a reading on it does not blink")
        SysInfo.memAvailKb = 32 * 1048576 * 0.03
        root._check(w.severity === 2 && Qt.colorEqual(w.segments[0].color, Theme.error)
                && Qt.colorEqual(w.glyphColor, Theme.barText),
            "nearly full memory turns its own glyph red, not the CPU's")
        ShellSettings.systemShowCpu = false
        root._check(w.glyph === "󰘚" && w.text === "97%",
            "with CPU off the monitor leads with memory")
        SysInfo.cpuReady = false
        ShellSettings.systemShowCpu = true
        root._check(w.text.startsWith("—") && w.severity === 2,
            "a CPU reading not yet sampled shows a dash rather than a stale value")
        ShellSettings.valuesOnHover = true
        root._check(w.text === "" && w.glyph === "󰍛" && w.segments.length === 0
                && Qt.colorEqual(w.glyphColor, Theme.error),
            "with values on hover the monitor rests as its glyph, still tinted")

        const topWas = { shown: SysInfo.topShown, name: SysInfo.topName, pid: SysInfo.topPid, share: SysInfo.topShare,
            samples: SysInfo._topSamples, last: SysInfo._topLast, active: SysInfo._active }
        const procLine = (pid, name, utime, stime) => pid + " (" + name + ") R 1 " + pid + " " + pid
            + " 0 -1 0 0 0 0 0 " + utime + " " + stime + " 0 0 20 0 1 0 1 0 0"
        const statAt = (user, idle, procs) => ["cpu " + user + " 0 0 " + idle + " 0 0 0 0",
            "cpu0 " + user / 2 + " 0 0 " + idle / 2 + " 0 0 0 0", "cpu1 " + user / 2 + " 0 0 " + idle / 2 + " 0 0 0 0",
            "intr 1 2 3"].concat(procs).join("\n") + "\n"
        const firstTop = SysInfo.processSample(statAt(1000, 1000,
            [procLine(41, "ffmpeg", 100, 20), procLine(42, "Web Content (2)", 50, 10), procLine(43, "make", 5, 5)]))
        const secondTop = SysInfo.processSample(statAt(1300, 1100,
            [procLine(41, "ffmpeg", 250, 50), procLine(42, "Web Content (2)", 90, 20), procLine(43, "cc1", 400, 5)]))
        const thirdTop = SysInfo.processSample(statAt(1600, 1200,
            [procLine(41, "ffmpeg", 400, 80), procLine(42, "Web Content (2)", 100, 20)]))
        const busiestTop = SysInfo.busiestProcess(firstTop, secondTop)
        root._check(firstTop.cpus === 2 && firstTop.names["42"] === "Web Content (2)" && firstTop.ticks["41"] === 120
                && busiestTop !== null && busiestTop.pid === 41 && busiestTop.name === "ffmpeg"
                && Math.abs(busiestTop.share - 0.45) < 1e-9 && Math.abs(busiestTop.cores - 0.9) < 1e-9
                && SysInfo.busiestProcess(null, secondTop) === null && SysInfo.busiestProcess(secondTop, firstTop) === null,
            "the busiest process has the most CPU ticks since the last sample, and a reused PID is left out")
        const oddTop = SysInfo.processSample("cpu 10 0 0 10 0 0 0 0\n77 (a) b (c) R 1 2 3 4 5 6 7 8 9 10 11 12\n"
            + "79 (z) R 1 2 3 4 5 6 7 8 9 10 11  13 14\n80 (w) R 1 2 3 4 5 6 7 8 9 10 11\nabc (q) R 1\n81 (nope R 1 2\n")
        root._check(oddTop.names["77"] === "a) b (c" && oddTop.ticks["77"] === 23 && oddTop.ticks["79"] === 11
                && oddTop.ticks["80"] === undefined && Object.keys(oddTop.ticks).length === 2 && oddTop.total === 20,
            "a process name holding brackets and spaces, an empty field and a cut-short line each parse as /proc means them")
        const heavyTop = { cores: 0.9 }, easingTop = { cores: 0.7 }, lightTop = { cores: 0.2 }
        root._check([SysInfo.topSamplesAfter(heavyTop, 0.1, 0), SysInfo.topSamplesAfter(heavyTop, 0.1, 1),
                SysInfo.topSamplesAfter(easingTop, 0.1, 2), SysInfo.topSamplesAfter(lightTop, 0.1, 2),
                SysInfo.topSamplesAfter(lightTop, 0.6, 0), SysInfo.topSamplesAfter(easingTop, 0.1, 1),
                SysInfo.topSamplesAfter(null, 0.9, 2)].join() === "1,2,2,0,1,0,0",
            "a busy machine or a process holding a core is named after two samples and let go under a lower line")
        SysInfo.cpuReady = true
        SysInfo.cpuPct = 0.62
        SysInfo._topLast = null
        SysInfo._topSamples = 0
        SysInfo._applyTop(firstTop)
        SysInfo._applyTop(secondTop)
        const topNotYet = !SysInfo.topShown && w._parts[0].detail === "62%"
        SysInfo._applyTop(thirdTop)
        root._check(topNotYet && SysInfo.topShown && SysInfo.topName === "ffmpeg" && SysInfo.topPid === 41
                && w._parts[0].detail === "62% · ffmpeg (41)" && w._parts[0].value === "62%"
                && w._parts[0].spoken === "CPU 62%, most by ffmpeg",
            "the monitor's hover names the busiest process and its ID while the CPU is busy")
        const topOwner = ({})
        SysInfo._active = false
        SysInfo.requestTopProcess(topOwner, true)
        const topQuietOff = !SysInfo._topWanted && SysInfo.topShown
        SysInfo._active = true
        const topWantedOn = SysInfo._topWanted
        SysInfo.requestTopProcess(topOwner, false)
        // held while the page that asked fades out, then forgotten
        const topHeld = !SysInfo._topWanted && SysInfo.topShown && SysInfo._topRelease.running
        SysInfo._topRelease.stop()
        SysInfo._topRelease.triggered()
        root._check(topQuietOff && topWantedOn && topHeld && !SysInfo._topWanted && !SysInfo.topShown
                && SysInfo.topName === "" && w._parts[0].detail === "62%",
            "the busiest process is read only while a view asks for it, and forgotten once that view has faded out")
        SysInfo.topName = "cc1plus"
        SysInfo.topPid = 48211
        w._minW = 999
        SysInfo.topShown = true
        const heldOnArrival = w._minW
        w._minW = 999
        SysInfo.topPid = 48212
        const heldOnSwap = w._minW
        SysInfo.topShown = false
        root._check(heldOnArrival === 0 && heldOnSwap === 999 && w._minW === 0,
            "the busiest process coming or going lets the monitor's width go at once; another taking its place is held")
        SysInfo._active = topWas.active
        SysInfo.topShown = topWas.shown
        SysInfo.topName = topWas.name
        SysInfo.topPid = topWas.pid
        SysInfo.topShare = topWas.share
        SysInfo._topSamples = topWas.samples
        SysInfo._topLast = topWas.last
        w.destroy()
        ShellSettings.valuesOnHover = was.hoverValues
        ShellSettings.barShowSystem = was.show
        ShellSettings.systemShowCpu = was.cpu
        ShellSettings.systemShowMemory = was.mem
        ShellSettings.systemShowTemp = was.temp
        SysInfo.cpuReady = was.ready
        SysInfo.cpuPct = was.pct
        SysInfo.cpuHigh = was.high
        SysInfo._cpuBusySamples = was.busy
        SysInfo._lastCpuTotal = was.cpuTotal
        SysInfo._lastCpuIdle = was.cpuIdle
        SysInfo.memTotalKb = was.total
        SysInfo.memAvailKb = was.avail
    }

    // an asynchronous Loader parents the page before its build finishes: a page drawn opaque then showed its half-built rows
    function _checkPageBuildHidden(): void {
        const openWas = MenuState.open
        const reduceWas = ShellSettings.reduceMotion
        ShellSettings.reduceMotion = false
        MenuState.open = true
        const loader = openMenuPageLoaderFactory.createObject(root)
        const page = loader ? loader.item : null
        root._check(page !== null && page.active && page.built && page.opaqueBeforeBuilt < 0.001 && page.opacity < 0.001,
            "a page built while the menu is open stays hidden until it has finished building, then fades in")
        if (loader) loader.destroy()
        MenuState.open = openWas
        ShellSettings.reduceMotion = reduceWas
    }

    // Home lets go of its readings as it starts to fade out, on a close or a tab switch; a tile blanked on that first frame
    function _checkReadingsOutlastFade(): void {
        const was = {
            show: ShellSettings.barShowSystem, cpu: ShellSettings.systemShowCpu, warn: ShellSettings.osdTempWarn,
            active: SysInfo._active, ready: SysInfo.cpuReady, pct: SysInfo.cpuPct,
            path: CpuTemp._sensorPath, probed: CpuTemp._probeComplete, temp: CpuTemp.temp
        }
        const unwanted = !SysInfo._homeWanted && !CpuTemp._wanted
        ShellSettings.systemShowCpu = true
        ShellSettings.barShowSystem = true
        // active by hand, as in _checkSystemWidget: activating for real would read /proc after this check restores
        SysInfo._active = true
        SysInfo.cpuReady = true
        SysInfo.cpuPct = 0.42
        ShellSettings.barShowSystem = false
        const cpuHeld = SysInfo._active && SysInfo.cpuReady && SysInfo.cpuPct === 0.42 && SysInfo._releaseHold.running
        SysInfo._releaseHold.stop()
        SysInfo._releaseHold.triggered()
        root._check(unwanted && cpuHeld && !SysInfo._active && !SysInfo.cpuReady,
            "the CPU reading outlasts the fade of the page that stops wanting it, then stops")

        // no sensor to read or to look for, so only the hold moves the reading
        CpuTemp._sensorPath = ""
        CpuTemp._probeComplete = true
        const warmedWas = CpuTemp._warmedUp
        ShellSettings.osdTempWarn = true
        CpuTemp._sample(55)
        CpuTemp._warmedUp = true
        ShellSettings.osdTempWarn = false
        const tempHeld = CpuTemp.temp === 55 && CpuTemp._releaseHold.running
        ShellSettings.osdTempWarn = true
        // nothing was reset, so its alerts are not held back by a fresh warm-up either
        const tempResumed = !CpuTemp._releaseHold.running && CpuTemp.temp === 55 && CpuTemp._warmedUp
        ShellSettings.osdTempWarn = false
        CpuTemp._releaseHold.stop()
        CpuTemp._releaseHold.triggered()
        root._check(tempHeld && tempResumed && CpuTemp.temp === 0,
            "the temperature outlasts the fade of the page that stops wanting it, and carries on when wanted again first")

        ShellSettings.osdTempWarn = was.warn
        CpuTemp._warmedUp = warmedWas
        CpuTemp._sensorPath = was.path
        CpuTemp._probeComplete = was.probed
        CpuTemp.temp = was.temp
        ShellSettings.barShowSystem = was.show
        ShellSettings.systemShowCpu = was.cpu
        SysInfo._releaseHold.stop()
        SysInfo._active = was.active
        SysInfo.cpuReady = was.ready
        SysInfo.cpuPct = was.pct
    }

    function _checkAppHandoffs(): void {
        const toolsWas = SystemTools._tools
        SystemTools._tools = { kitty: true, btop: true, nmtui: true }
        root._check(Settings.systemMonitorCommand.join(" ") === "kitty btop"
                && Settings.networkSettingsCommand.join(" ") === "kitty nmtui",
            "without xdg-terminal-exec a terminal app opens in the first common terminal found")
        SystemTools._tools = { "xdg-terminal-exec": true, kitty: true, htop: true, missioncenter: true }
        root._check(Settings.systemMonitorCommand.join(" ") === "missioncenter"
                && Settings.inTerminal(["htop"]).join(" ") === "xdg-terminal-exec htop",
            "a desktop system monitor wins, and xdg-terminal-exec keeps the user's own terminal")
        SystemTools._tools = { btop: true }
        root._check(Settings.systemMonitorCommand.length === 0 && Settings.inTerminal(["btop"]).length === 0,
            "a terminal monitor with no terminal to host it offers no action")
        SystemTools._tools = toolsWas
    }

    function _checkInputRecovery(): void {
        const lookup = InputState._capsLookup
        const was = { enabled: ShellSettings.barShowKeyboard, command: lookup.command.slice(),
            path: InputState._capsPath, caps: InputState.capsLock, failures: InputState._capsFailures }
        const settle = function() {
            const deadline = Date.now() + 3000
            while (lookup.running && Date.now() < deadline) discoveryClock.wait(10)
        }
        ShellSettings.barShowKeyboard = false
        settle()
        lookup.command = ["/nonexistent/silere-probe-caps-lookup"]
        InputState._capsPath = ""
        InputState._capsFailures = 0
        ShellSettings.barShowKeyboard = true
        settle()
        root._check(!lookup.running && InputState._capsFailures === 1
                && InputState._capsRetry.running && InputState._capsRetry.interval === 5000,
            "a missing Caps Lock sensor schedules rediscovery without opening the menu")
        InputState._capsRetry.triggered()
        settle()
        root._check(!lookup.running && InputState._capsFailures === 2
                && InputState._capsRetry.running && InputState._capsRetry.interval === 10000,
            "a failed Caps Lock retry backs off instead of continuously spawning discovery")
        InputState._capsFailures = 5
        root._check(InputState._capsRetry.interval === 60000,
            "Caps Lock discovery retries stay bounded to one minute")
        InputState._capsPath = "/sys/class/leds/silere-probe::capslock/brightness"
        InputState.capsLock = true
        InputState._capsReadFailed()
        root._check(!InputState.capsAvailable && !InputState.capsLock && InputState._capsRetry.running,
            "an unplugged Caps Lock sensor clears its stale state and resumes discovery")
        const overviewWas = OverviewState._hyprActive
        OverviewState._hyprActive = true
        const overviewQuiet = OverviewState.active && !InputState._wanted && !InputState._capsRetry.running
        OverviewState._hyprActive = overviewWas
        settle()
        root._check(overviewQuiet && InputState._wanted && InputState._capsRetry.running,
            "the Caps Lock light is not read while the overview hides the bar, as the bar's other readings are not")
        ShellSettings.barShowKeyboard = false
        InputState.refreshCaps()
        root._check(!lookup.running && !InputState._capsRetry.running,
            "a hidden keyboard widget stops discovery retries and ignores refresh requests")
        InputState._capsPath = "/sys/class/leds/silere-probe::capslock/brightness"
        InputState.capsLock = true
        InputState._capsReadFailed()
        root._check(InputState.capsAvailable && InputState.capsLock,
            "a read invalidated while the widget is hidden preserves its cached keyboard path")
        lookup.command = was.command
        InputState._capsPath = was.path
        InputState.capsLock = was.caps
        InputState._capsFailures = was.failures
        ShellSettings.barShowKeyboard = was.enabled

        const codesWas = InputState._layoutCodes
        InputState._layoutCodes = ({})
        root._check(InputState.shortLabel("Latvian") === "LV" && InputState.shortLabel("Ukrainian") === "UK",
            "without the xkb registry, layout labels come from the language name")
        InputState._layoutCodes = InputState.layoutCodesFrom("! model\n  pc105           Generic 105-key PC\n\n"
            + "! layout\n  us              English (US)\n  ee              Estonian\n  ua              Ukrainian\n\n"
            + "! variant\n  intl            us: English (US, intl., with dead keys)\n  us              ba: Bosnian (US)\n\n"
            + "! option\n  grp             Switching to another layout\n")
        root._check(InputState.shortLabel("Ukrainian") === "UA" && InputState.shortLabel("Estonian") === "EE"
                && InputState.shortLabel("English (US, intl., with dead keys)") === "US"
                && InputState.shortLabel("Bosnian (US)") === "BA"
                && InputState.shortLabel("Generic 105-key PC") === "GE"
                && InputState.shortLabel("constructor") === "CO",
            "layout labels use the xkb code of the layout or variant, never a model, option or prototype name")
        InputState._layoutCodes = codesWas
    }

    function _checkWeather(): void {
        const codes = [0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67,
            71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 97, 99]
        root._check(codes.every(c => Weather.conditionFor(c).length > 0
                && Weather.glyphFor(c, true).length > 0 && Weather.glyphFor(c, false).length > 0)
                && Weather.conditionFor(4) === "" && Weather.glyphFor(-1, true) === "",
            "every WMO code Open-Meteo reports has a label and a day and night glyph")
        root._check(Weather.glyphFor(0, true) !== Weather.glyphFor(0, false),
            "a clear night does not show the sun")

        const reading = Weather.parseForecast({ current: { temperature_2m: 8.6, weather_code: 3, is_day: 0 },
            daily: { temperature_2m_max: [11.4], temperature_2m_min: [7.5] } })
        root._check(reading && reading.temperature === 9 && reading.code === 3
                && reading.high === 11 && reading.low === 8 && reading.isDay === false,
            "a forecast reads as rounded current, high and low temperatures with the day flag")
        root._check(Weather.parseForecast(null) === null
                && Weather.parseForecast({ current: { temperature_2m: "9", weather_code: 3 },
                    daily: { temperature_2m_max: [11], temperature_2m_min: [7] } }) === null
                && Weather.parseForecast({ current: { temperature_2m: 9, weather_code: 3 },
                    daily: { temperature_2m_max: [], temperature_2m_min: [7] } }) === null,
            "a partial or malformed forecast is rejected rather than shown")
        const forecast = day => ({ current: { temperature_2m: 9, weather_code: 0, is_day: day },
            daily: { temperature_2m_max: [11], temperature_2m_min: [7] } })
        root._check(codes.every(code => {
            const data = forecast(1)
            data.current.weather_code = code
            return Weather.parseForecast(data)?.code === code
        }) && Weather.conditionFor(97) === "Heavy thunderstorm",
            "every documented weather code, including heavy thunderstorms, is accepted unchanged")
        root._check(Weather.parseForecast(forecast(1))?.isDay === true
                && [undefined, null, "0", 2].every(day => Weather.parseForecast(forecast(day)) === null),
            "a missing or invalid weather day flag cannot turn a night forecast into sunshine")
        const invertedRange = forecast(1)
        invertedRange.daily.temperature_2m_min = [12]
        root._check([2.5, 4, 52, 72, 4294967296, -4294967296].every(code => {
            const data = forecast(1)
            data.current.weather_code = code
            return Weather.parseForecast(data) === null
        }) && Weather.parseForecast(invertedRange) === null,
            "invalid weather codes and an inverted daily range do not replace the last forecast")

        const url = Weather.forecastUrl(56.9496, 24.1052, true)
        root._check(url.startsWith("https://api.open-meteo.com/") && url.indexOf("latitude=56.95") > 0
                && url.indexOf("longitude=24.11") > 0 && url.indexOf("temperature_unit=fahrenheit") > 0
                && Weather.forecastUrl(1, 2, false).indexOf("temperature_unit") < 0,
            "requests send rounded coordinates over https")

        const fetched = new Date(2026, 10, 1, 12, 0).getTime()
        const key = Weather._key(fetched)
        root._check(Weather.cacheFresh(fetched, key, fetched)
                && Weather.cacheFresh(fetched, key, fetched + Weather.maxAgeMs - 1)
                && !Weather.cacheFresh(fetched, key, fetched + Weather.maxAgeMs),
            "weather cache reuse ends at its thirty-minute boundary")
        root._check(!Weather.cacheFresh(fetched, key, fetched - 1)
                && !Weather.cacheFresh(0, key, fetched)
                && !Weather.cacheFresh(NaN, key, fetched)
                && !Weather.cacheFresh(fetched, "another unit", fetched),
            "a clock adjustment, missing timestamp, or different units cannot reuse a reading")
        const midnight = new Date(2026, 10, 2, 0, 0).getTime()
        root._check(!Weather.cacheFresh(midnight - 60000, Weather._key(midnight - 60000), midnight),
            "yesterday's daily high and low expire at midnight even inside the cache lifetime")
        const newYear = new Date(2027, 0, 1, 0, 0).getTime()
        root._check(!Weather.cacheFresh(newYear - 60000, Weather._key(newYear - 60000), newYear),
            "weather cache dates include the year when the calendar rolls over")

        const line = TimeZonePlace.parseLine("+5657+02406\tEurope/Riga\n")
        root._check(line && Math.abs(line.lat - 56.95) < 0.001 && Math.abs(line.lon - 24.1) < 0.001
                && line.zone === "Europe/Riga" && TimeZonePlace.parseLine("garbage") === null
                && TimeZonePlace.placeName("America/Argentina/Buenos_Aires") === "Buenos Aires",
            "the time zone lookup yields coordinates and a readable city name")
        const shared = TimeZonePlace.parseLine("+4339-07923\tAmerica/Toronto\tCA,BS\n")
        root._check(shared?.country === "CA" && line.country === ""
                && TimeZonePlace.usesFahrenheit("US") && TimeZonePlace.usesFahrenheit("BS")
                && !TimeZonePlace.usesFahrenheit("CA") && !TimeZonePlace.usesFahrenheit(""),
            "a zone shared by several countries reads as its city's own, for the weather unit")
        root._check(!Weather.fahrenheitFor("auto", true, "LV") && Weather.fahrenheitFor("auto", true, "US")
                && Weather.fahrenheitFor("auto", true, "") && !Weather.fahrenheitFor("auto", false, "US")
                && Weather.fahrenheitFor("f", false, "LV") && !Weather.fahrenheitFor("c", true, "US"),
            "the default US locale reads Fahrenheit only in a city that uses it, a metric locale holds, and a picked unit wins")
        // the lookup, run as written over a three-line tz database: $1 is the script
        const zoneRun = processFactory.createObject(root, { command: ["bash", "-c",
            "d=$(mktemp -d) || exit 1; trap 'rm -rf \"$d\"' EXIT; "
            + "printf 'L Europe/Berlin Europe/Stockholm\\nL Asia/Kolkata Asia/Calcutta\\n' > \"$d/tzdata.zi\"; "
            + "printf 'DE\\t+5230+01322\\tEurope/Berlin\\nIN\\t+2232+08822\\tAsia/Kolkata\\n' > \"$d/zone1970.tab\"; "
            + "printf 'SE\\t+5920+01803\\tEurope/Stockholm\\n' > \"$d/zone.tab\"; "
            + "run() { bash -c \"$script\" tz \"$1\" \"$d\"; }; script=\"$1\"; "
            + "[ \"$(run Europe/Stockholm)\" = \"$(printf '+5920+01803\\tEurope/Stockholm\\tSE')\" ] "
            + "&& [ \"$(run Asia/Calcutta)\" = \"$(printf '+2232+08822\\tAsia/Kolkata\\tIN')\" ] && [ -z \"$(run Nope/Zone)\" ]",
            "check", TimeZonePlace.script] })
        zoneRun.exited.connect(function(code) {
            root._check(code === 0, "a time zone merged into another country's keeps its own city, and an alias follows its link")
            root._zoneLinkDone = true
            zoneRun.destroy()
        })
        zoneRun.running = true
        root._check(!Weather.enabled && !Weather.loading && !Weather.hasData,
            "weather stays idle while it is switched off")
        ShellSettings.clockShowWeather = true
        root._check(!Weather.loading && !Weather.hasData && !Weather._zoneLookup.running,
            "showing weather on the bar fetches nothing while weather itself is off")
        ShellSettings.clockShowWeather = false
        const movedPlaceWas = Weather._place
        const movedFetchedWas = Weather._fetchedAt
        Weather._place = { lat: 1, lon: 2, name: "Here", offset: 120 }
        Weather._fetchedAt = 42
        const placeKept = !Weather.forgetMovedPlace(120) && Weather._place !== null && Weather._fetchedAt === 42
        const placeDropped = Weather.forgetMovedPlace(60) && Weather._place === null && Weather._fetchedAt === 0
        Weather._place = movedPlaceWas
        Weather._fetchedAt = movedFetchedWas
        root._check(placeKept && placeDropped,
            "weather drops a place found under another time zone offset, and keeps one found under this one")
        const lookup = Weather._zoneLookup
        if (lookup) {
            const commandWas = lookup.command.slice()
            const placeWas = Weather._place
            lookup.command = ["sleep", "2"]
            // Park the request before enabling the row, even if another fixture left the calendar open.
            Weather.loading = true
            ShellSettings.weatherEnabled = true
            Weather._place = null
            Weather._fetchedAt = Date.now()
            Weather._fetchedFor = Weather._key(Weather._fetchedAt)
            Weather.loading = false
            Weather.request(false)
            root._check(!Weather.loading && !lookup.running,
                "opening a calendar with a fresh forecast does not start a lookup")
            const weatherClock = clockFactory.createObject(root)
            const barWeatherWas = ShellSettings.clockShowWeather
            ShellSettings.clockShowWeather = true
            const barShowsFresh = weatherClock._weather.length > 0
            Weather.failed = true
            const barHidesFailed = weatherClock._weather === ""
            Weather.failed = false
            ShellSettings.clockShowWeather = barWeatherWas
            weatherClock.destroy()
            root._check(barShowsFresh && barHidesFailed,
                "the bar shows a weather reading only while its refresh works")
            Weather.failed = true
            Weather._triedAt = Date.now() - 60000
            Weather._barTick()
            const barWaits = !Weather.loading && !lookup.running
            Weather.request(false)
            root._check(barWaits && Date.now() - Weather._triedAt < 5000,
                "the bar waits out a failed weather lookup, and every attempt is timed for that wait")
            root._check(Weather.loading && lookup.running,
                "reopening after a failed refresh retries even when its previous reading is inside the cache lifetime")
            ShellSettings.weatherEnabled = false
            if (lookup.running) lookup.running = false
            lookup.command = commandWas
            Weather._place = placeWas
            root._check(!Weather.loading && !Weather.failed && !Weather.hasData,
                "disabling weather clears a retried request and its previous reading")

            const onlineWas = { clock: ShellSettings.barShowClock, weather: ShellSettings.clockShowWeather,
                issue: Network.connectivityIssue }
            const settleDeadline = Date.now() + 1000
            while ((lookup.running || Weather._discardLookup) && Date.now() < settleDeadline) discoveryClock.wait(10)
            lookup.command = ["sleep", "2"]
            Weather._place = null
            Weather.loading = true
            ShellSettings.weatherEnabled = true
            Weather.loading = false
            Weather.failed = true
            Weather._triedAt = Date.now()
            ShellSettings.barShowClock = true
            ShellSettings.clockShowWeather = true
            const offlineWaits = !Weather.loading && !lookup.running
            Network.connectivityIssue = "portal"
            const portalWaits = !Weather.loading
            Network.connectivityIssue = ""
            const signedIn = Weather.loading && lookup.running
            root._check(offlineWaits && portalWaits && signedIn === Network.connected,
                "a bar weather refresh that failed behind a sign-in page retries once the internet answers, connected "
                    + Network.connected)
            Network.connectivityIssue = onlineWas.issue
            ShellSettings.clockShowWeather = onlineWas.weather
            ShellSettings.barShowClock = onlineWas.clock
            ShellSettings.weatherEnabled = false
            if (lookup.running) lookup.running = false
            lookup.command = commandWas
            Weather._place = placeWas

            // a wake from suspend: nothing failed, the reading predates the sleep, and the network comes back
            const wakeDeadline = Date.now() + 1000
            while ((lookup.running || Weather._discardLookup) && Date.now() < wakeDeadline) discoveryClock.wait(10)
            lookup.command = ["sleep", "2"]
            Weather._place = null
            Weather.loading = true
            ShellSettings.weatherEnabled = true
            Weather._fetchedAt = Date.now()
            Weather._fetchedFor = Weather._key(Weather._fetchedAt)
            Weather.loading = false
            Weather.failed = false
            ShellSettings.barShowClock = true
            ShellSettings.clockShowWeather = true
            Weather._networkBack(true)
            const freshKept = !Weather.loading && !lookup.running
            Weather._fetchedAt = Date.now() - Weather.maxAgeMs - 1
            Weather._networkBack(false)
            const offlineKept = !Weather.loading && !lookup.running
            Weather._networkBack(true)
            root._check(freshKept && offlineKept && Weather.loading && lookup.running,
                "a reconnect refreshes a bar weather reading that went stale during suspend, and leaves a fresh one")
            ShellSettings.weatherEnabled = false
            if (lookup.running) lookup.running = false
            const unitDeadline = Date.now() + 1000
            while ((lookup.running || Weather._discardLookup) && Date.now() < unitDeadline) discoveryClock.wait(10)
            const unitChoiceWas = ShellSettings.weatherUnit
            ShellSettings.weatherUnit = "c"
            Weather.loading = true
            ShellSettings.weatherEnabled = true
            Weather._fetchedAt = Date.now()
            Weather._fetchedFor = Weather._key(Weather._fetchedAt)
            Weather._readingFahrenheit = false
            Weather.loading = false
            Weather.failed = false
            ShellSettings.weatherUnit = "f"
            root._check(Weather.unit === "°C" && Weather.loading && lookup.running,
                "switching the weather unit fetches again, and the shown reading keeps the unit it came in")
            ShellSettings.weatherUnit = unitChoiceWas
            ShellSettings.clockShowWeather = onlineWas.weather
            ShellSettings.barShowClock = onlineWas.clock
            ShellSettings.weatherEnabled = false
            if (lookup.running) lookup.running = false
            lookup.command = commandWas
            Weather._place = placeWas

            discoveryClock.wait(30)
            let lookupStarts = 0
            const countLookupStart = () => { if (lookup.running) lookupStarts++ }
            lookup.runningChanged.connect(countLookupStart)
            lookup.command = ["sleep", "2"]
            Weather._place = null
            Weather.loading = true
            ShellSettings.weatherEnabled = true
            Weather.loading = false
            Weather.request(true)
            const firstStartDeadline = Date.now() + 1000
            while (lookupStarts < 1 && Date.now() < firstStartDeadline) discoveryClock.wait(10)
            root._check(lookupStarts === 1 && lookup.running && Weather.loading,
                "the weather cancellation fixture starts a location lookup")
            ShellSettings.weatherEnabled = false
            Weather.loading = true
            ShellSettings.weatherEnabled = true
            Weather.loading = false
            Weather.request(true)
            const restartDeadline = Date.now() + 1000
            while (lookupStarts < 2 && Date.now() < restartDeadline) discoveryClock.wait(10)
            root._check(lookupStarts === 2 && lookup.running && Weather.loading && !Weather.failed,
                "a quick weather off/on starts a fresh lookup instead of reusing the cancelled request")
            ShellSettings.weatherEnabled = false
            const stopDeadline = Date.now() + 1000
            while (lookup.running && Date.now() < stopDeadline) discoveryClock.wait(10)
            root._check(!lookup.running && !Weather.loading && !Weather.hasData,
                "switching weather off stops its location process")
            if (lookup.running) lookup.running = false
            lookup.runningChanged.disconnect(countLookupStart)
            lookup.command = commandWas
            Weather._place = placeWas
        }
    }

    function _checkPillTextBaseline(): void {
        let mismatched = []
        for (let h = 28; h <= 44; h++) {
            const host = Qt.createQmlObject("import QtQuick; Item {}", barFixtureHost)
            host.height = h
            const pill = pillFactory.createObject(host, { text: "48%" })
            pill.anchors.verticalCenter = host.verticalCenter
            const label = Qt.createQmlObject("import \"modules/common\"; import \"config\"; ShellText { text: \"20:30\"; font.pixelSize: Settings.fontSize }", host)
            label.anchors.verticalCenter = host.verticalCenter
            const text = root._findTrayNode(pill, item => item !== pill && item.text === "48%")
            if (!text || text.mapToItem(host, 0, 0).y !== label.mapToItem(host, 0, 0).y) mismatched.push(h)
            host.destroy()
        }
        root._check(mismatched.length === 0,
            "a pill's value sits on the same line as the clock at every bar height, mismatched at " + mismatched.join(","))
    }

    function _checkBluetoothPairing(): void {
        const component = Qt.createComponent("modules/menu/BluetoothList.qml")
        const picker = component.status === Component.Ready
            ? component.createObject(root, { width: 320 }) : null
        const device = bluetoothDeviceFixture.createObject(root)
        root._check(picker !== null, "the Bluetooth picker builds for pairing cancellation checks")
        if (picker) {
            const list = root._findTrayNode(picker, item => item.objectName === "bluetooth-devices")
            if (list) {
                list.visible = true
                list.model = [device]
                list.forceLayout()
            }
            const row = root._findTrayNode(picker, item => item.modelData === device)
            root._check(row !== null, "a pairing Bluetooth device creates an actionable row")
            if (row) {
                let actions = 0
                row.triggered.connect(() => actions++)
                row.Accessible.pressAction()
                root._check(row.status === "Cancel?" && !row.busy && actions === 1,
                    "a device pairing while connecting still accepts its cancel action")
                device.pairing = false
                row.Accessible.pressAction()
                root._check(row.busy && actions === 1,
                    "an ordinary Bluetooth connection still blocks repeat actions")
            }
            picker.destroy()
        }
        device.destroy()
        component.destroy()
        const bonded = bluetoothDeviceFixture.createObject(root, {
            paired: true, connected: true, pairing: false, state: -1 })
        const stranger = bluetoothDeviceFixture.createObject(root, {
            paired: false, connected: true, pairing: false, state: -1 })
        Bluetooth._trustDevice(bonded, false)
        Bluetooth._trustDevice(stranger, false)
        root._check(bonded.trusted && !stranger.trusted,
            "a successful connect trusts a paired device so it can reconnect by itself, never an unpaired one")
        const elsewhere = bluetoothDeviceFixture.createObject(root, {
            paired: true, connected: true, pairing: false, state: -1 })
        const idle = bluetoothDeviceFixture.createObject(root, {
            paired: true, connected: false, pairing: false, state: -1 })
        stranger.trusted = false
        Bluetooth._trustConnected([elsewhere, idle, stranger, null])
        root._check(elsewhere.trusted && !idle.trusted && !stranger.trusted,
            "a paired device connected by another tool is trusted, a disconnected or unpaired one is not")
        elsewhere.destroy()
        idle.destroy()
        bonded.destroy()
        stranger.destroy()
    }

    function _checkConnectivityConfirmations(): void {
        const device = bluetoothDeviceFixture.createObject(root, {
            pairing: false, paired: true, connected: true, state: -1
        })
        const cases = [
            { name: "Wi-Fi", path: "modules/menu/WifiList.qml", identity: "__silere_confirmation_probe__" },
            { name: "Bluetooth", path: "modules/menu/BluetoothList.qml", identity: device.address }
        ]
        for (const test of cases) {
            const component = Qt.createComponent(test.path)
            const picker = component.status === Component.Ready
                ? component.createObject(root, { width: 320 }) : null
            root._check(picker !== null, test.name + " builds for confirmation deadline checks")
            if (picker) {
                const list = root._findTrayNode(picker, item => test.name === "Bluetooth"
                    ? item.objectName === "bluetooth-devices"
                    : item.model !== undefined && typeof item.forceLayout === "function")
                for (const disconnect of [true, false]) {
                    device.connected = disconnect
                    const entry = test.name === "Bluetooth" ? device : {
                        ssid: test.identity, label: "Confirmation probe", glyph: "",
                        secured: true, psk: true, passwordless: false, profileOnly: false,
                        active: disconnect, known: true
                    }
                    list.visible = true
                    list.model = [entry]
                    list.forceLayout()
                    const row = root._findTrayNode(picker, item => typeof item._forgetTap === "function")
                    root._check(row !== null, test.name + " creates its confirmation row")
                    if (!row) continue
                    const arm = picker._confirm
                    const key = (disconnect ? "disconnect:" : "forget:") + test.identity
                    const request = () => disconnect ? row._activate() : row._forgetTap()
                    const label = test.name + (disconnect ? " disconnect" : " forget")
                    request()
                    request()
                    root._check(arm.key === key,
                        label + " arms and rejects an immediate double-click")
                    for (const offset of [-3001, 1000]) {
                        arm.armedAtMs = Date.now() + offset
                        request()
                        root._check(arm.key === key
                                && arm.armedAtMs <= Date.now()
                                && Date.now() - arm.armedAtMs < Metrics.confirmGuardMs,
                            label + " rearms an expired or future-dated confirmation without running its action")
                    }
                    arm.armedAtMs = Date.now() - Metrics.confirmGuardMs - 1
                    const fired = arm.press(key)
                    root._check(fired && arm.key === "",
                        label + " runs on a second press inside the window and disarms")
                    if (test.name === "Bluetooth") {
                        arm.press(key)
                        Bluetooth.adapterChanged()
                        root._check(arm.key === "", label + " clears when its Bluetooth controller changes")
                        arm.clear()
                    }
                    if (disconnect) continue
                    const keyHost = keyboardFixtureFactory.createObject(root)
                    const pickerParent = picker.parent
                    picker.parent = keyHost.contentItem
                    keyHost.requestActivate()
                    keyHost.input.wait(80)
                    row.forceActiveFocus(Qt.TabFocusReason)
                    keyHost.input.keyClick(Qt.Key_Delete)
                    root._check(arm.key === key, label + " arms from the Delete key")
                    arm.clear()
                    picker.parent = pickerParent
                    keyHost.destroy()
                }
                picker.destroy()
            }
            component.destroy()
        }
        device.destroy()
    }

    function _checkSmoothGlide(): void {
        const reduceWas = ShellSettings.reduceMotion
        ShellSettings.reduceMotion = false
        const wave = waveLineFactory.createObject(barFixtureHost)
        root._check(wave.flowAllowed(false, false)
                && !wave.flowAllowed(true, false) && !wave.flowAllowed(false, true),
            "continuous slider waves stop during quiet idle and reduced motion")
        wave.visible = false
        root._check(!wave.flowAllowed(false, false), "a hidden slider wave never starts its timer")
        wave.visible = true
        wave.waveOpacity = 0
        root._check(!wave.flowAllowed(false, false), "a transparent slider wave never starts its timer")
        wave.waveOpacity = 1
        wave.reveal = 0
        root._check(!wave.flowAllowed(false, false), "a fully clipped slider wave never starts its timer")
        wave.reveal = 1
        wave.flowing = false
        for (const phase of [0, 0.27, 0.91]) {
            wave.phase = phase
            const values = wave._path.match(/-?\d+(?:\.\d+)?/g).map(Number)
            let matchesSine = true
            // every cubic endpoint lands on the tapered sine, including the final partial wavelength; this catches drift in the recurrence
            const ramp = Math.min(wave._waveLength / 2, wave._len / 2)
            const env = d => { const t = Math.max(0, Math.min(1, d / ramp)); return t * t * (3 - 2 * t) }
            for (let i = 6; i < values.length; i += 6) {
                const x = values[i], y = values[i + 1], d = x - wave.thickness / 2
                const expected = wave.height / 2 + wave._amp * env(d) * env(wave._len - d) * Math.sin(
                    d * 2 * Math.PI / wave._waveLength - phase * 2 * Math.PI)
                matchesSine = matchesSine && Math.abs(y - expected) < 0.002
            }
            root._check(matchesSine, "slider wave endpoints keep their sine shape at phase " + phase)
            root._check(Math.abs(values[1] - wave.height / 2) < 0.002
                    && Math.abs(values[values.length - 1] - wave.height / 2) < 0.002,
                "a slider wave starts and ends on the track's centre line at phase " + phase)
        }
        wave.value = 0.04
        root._check(wave._path.indexOf(" H ") > 0, "a short slider level keeps its simple straight path")
        wave.destroy()
        const glide = smoothGlideFactory.createObject(root, { target: 360, duration: 240 })
        root._check(glide.value === 360 && !glide.running,
            "a newly built panel glide starts at its destination")
        glide.target = 600
        let monotonic = true
        for (let i = 0; i < 12; i++) {
            const before = glide.value
            glide._advance(1 / 240)
            monotonic = monotonic && glide.value > before && glide.value < 600
        }
        root._check(monotonic, "panel geometry advances every high-refresh frame without overshoot")
        const slowFrames = smoothGlideFactory.createObject(root, { target: 0, duration: 240 })
        const fastFrames = smoothGlideFactory.createObject(root, { target: 0, duration: 240 })
        slowFrames.target = 240
        fastFrames.target = 240
        for (let i = 0; i < 12; i++) slowFrames._advance(1 / 60)
        for (let i = 0; i < 48; i++) fastFrames._advance(1 / 240)
        root._check(Math.abs(slowFrames.value - fastFrames.value) < 0.000001
                && Math.abs(slowFrames._velocity - fastFrames._velocity) < 0.000001,
            "panel timing is the same at 60 Hz and 240 Hz")
        slowFrames.destroy()
        fastFrames.destroy()
        const interruptedValue = glide.value
        const interruptedVelocity = glide._velocity
        glide.target = 612
        root._check(glide.value === interruptedValue && glide._velocity === interruptedVelocity,
            "content reflow retargets a panel without resetting its position or velocity")
        glide._advance(1 / 240)
        root._check(glide.value > interruptedValue && glide._velocity > 0,
            "a retargeted growing panel continues moving on the next frame")
        glide.target = 400
        for (let i = 0; i < 240; i++) glide._advance(1 / 240)
        root._check(glide.value === 400 && glide._velocity === 0 && !glide.running,
            "a reversed panel glide settles exactly without a bouncing edge")
        glide.target = 800
        glide._advance(1 / 60)
        ShellSettings.reduceMotion = true
        root._check(glide.value === 800 && glide._velocity === 0 && !glide.running,
            "reduced motion settles an interrupted panel glide immediately")
        ShellSettings.reduceMotion = false
        glide.target = 900
        glide._advance(1 / 60)
        glide.gate = false
        root._check(glide.value === 900 && !glide.running,
            "closing or hiding a panel settles its geometry and stops the frame loop")
        glide.target = 1000
        root._check(glide.value === 1000 && !glide.running,
            "hidden panel geometry follows new content without animating")
        glide.gate = true
        glide.duration = 0
        glide.target = 1100
        root._check(glide.value === 1100 && !glide.running,
            "a zero-duration panel glide is immediate and never divides by zero")
        glide.destroy()
        const slot = smoothGlideFactory.createObject(root, { precision: 0.001 })
        slot.target = 1
        for (let i = 0; i < 5; i++) slot._advance(0.05)
        root._check(slot.running && slot.value < 1 && slot.value > 0.99,
            "a normalized selection glide keeps its final pixels smooth instead of snapping a tenth of a row")
        for (let i = 0; i < 20; i++) slot._advance(0.05)
        root._check(slot.value === 1 && !slot.running,
            "a selection glide still settles exactly at its row")
        slot.destroy()
        const glidesWas = Motion.layoutGlides
        const barGlide = smoothGlideFactory.createObject(root, { target: 0, duration: 240 })
        barGlide.target = 50
        const barGlideCounted = Motion.layoutGlides !== glidesWas
        barGlide.destroy()
        root._check(!barGlideCounted,
            "a bar glide keeps pixel snaps following it frame by frame")
        const counted = smoothGlideFactory.createObject(root, { target: 0, duration: 240, holdsSnaps: true })
        counted.target = 50
        const countedWhileMoving = Motion.layoutGlides === glidesWas + 1 && Motion.layoutGliding
        counted._snap()
        root._check(countedWhileMoving && Motion.layoutGlides === glidesWas,
            "a moving panel glide is counted until it settles")
        const snapped = pixelSnapFactory.createObject(barFixtureHost)
        const snappedAtRest = Math.abs(snapped.snap.x - 0.1) < 1e-6
        counted.target = 80
        snapped.x = 10.7
        const heldWhileGliding = Math.abs(snapped.snap.x - 0.1) < 1e-6
        counted._snap()
        root._check(snappedAtRest && heldWhileGliding && Math.abs(snapped.snap.x + 0.3) < 1e-6,
            "a pixel snap holds its offset through a glide and re-snaps once it settles")
        snapped.destroy()
        counted.destroy()
        // torn down mid-flight with its owner, as a closing popup is; _finish reads the count once the deletion has run
        const host = glideHostFactory.createObject(barFixtureHost)
        host.glide.target = 120
        host.destroy()
        ShellSettings.reduceMotion = reduceWas
    }

    function _checkPageLayout(): void {
        const loader = pageLoaderFactory.createObject(root)
        root._check(loader.item !== null && loader.item.width === 332,
            "a page loader sizes its page to the settled content width")
        // MenuState announces the departure before changing shared geometry.
        loader.scrollOffset = 240
        loader.holdLayout()
        loader.shown = false
        for (let i = 0; i < 60; i++) loader.layoutWidth = 388 - i / 4
        root._check(loader.width === 332 && loader.item.width === 332,
            "a departing page does not reflow during the viewport's resize")
        loader.scrollOffset = 0
        root._check(loader.y === -240,
            "a departing page keeps its visible rows when the shared scroll resets")
        loader.holdLayout()
        root._check(loader.y === -240,
            "taking another departure snapshot preserves an already held scroll position")
        loader.layoutWidth = 388
        loader.shown = true
        root._check(loader.width === 388 && loader.item.width === 388 && loader.y === 0,
            "returning to a retained page restores its current layout width")
        loader.layoutWidth = 280
        root._check(loader.item.width === 280,
            "a visible page follows later screen or interface-size changes")
        loader.shown = false
        loader.layoutWidth = 240
        root._check(loader.item.width === 280,
            "hiding a loader preserves layout even without a pre-change snapshot")
        loader.destroy()
        const drawerFactory = Qt.createComponent("modules/menu/RailDrawer.qml")
        const drawer = drawerFactory.createObject(barFixtureHost, {
            shown: true, retained: true, width: 160, height: 200, content: drawerContentFactory
        })
        const drawerLoader = drawer.children.find(item => item.sourceComponent !== undefined)
        drawerLoader.asynchronous = false
        drawer.holdLayout()
        drawer.shown = false
        drawer.width = 112
        root._check(drawerLoader.item && drawerLoader.item.width === 160,
            "an outgoing sidebar preserves its label layout while the panel contracts")
        drawer.shown = true
        root._check(drawerLoader.item && drawerLoader.item.width === 112,
            "a returning sidebar reflows to the current panel width")
        drawer.destroy()
        drawerFactory.destroy()
        const flick = flickableFactory.createObject(root)
        flick.contentY = 400
        flick.flick(0, -1200)
        root._check(flick.flicking, "the scroll-reset probe starts with live flick momentum")
        flick.scrollToTop()
        root._check(!flick.flicking && flick.contentY === flick.originY,
            "returning to the top stops momentum before the next page can inherit it")
        flick.destroy()
    }

    function _runSettingsDiagnosticsProbe(): void {
        const toolsWas = SystemTools._tools
        const readyWas = SystemTools.ready
        const errorWas = SystemTools.lastError
        const lockWas = ShellSettings.lockProvider
        const customWas = ShellSettings.lockCommandCustom
        const nightWas = ShellSettings.nightLightProvider
        const overlayWas = ShellSettings.overlayMonitor
        const tabWas = MenuState.activeTab
        const openWas = MenuState.open
        const sectionWas = MenuState.settingsSection
        // No selected provider is installed; availability must reflect the choice,
        // even when another compatible provider would work automatically.
        SystemTools._tools = ({ "notify-send": true, wlsunset: true })
        SystemTools.ready = true
        SystemTools.lastError = ""
        ShellSettings.lockProvider = "custom"
        ShellSettings.lockCommandCustom = ""
        ShellSettings.nightLightProvider = "hyprsunset"
        const diagnosticsComponent = Qt.createComponent("modules/menu/settings/SettingsMaintenanceSection.qml")
        const diagnostics = diagnosticsComponent.status === Component.Ready
            ? diagnosticsComponent.createObject(root, { width: 360 }) : null
        root._check(diagnostics !== null, "diagnostics builds for behavioral checks")
        if (diagnostics) {
            const deviceRows = diagnostics._deviceChecks
            root._check(deviceRows.some(row => row.id === "audio") && deviceRows.some(row => row.id === "microphone"),
                "diagnostics describes output and microphone readiness without requiring real audio devices")
            const btRow = deviceRows.find(row => row.id === "bluetooth")
            root._check(!btRow || (btRow.action === "interface") === (Bluetooth.adapterCount > 1),
                "the Bluetooth check links to Interface only when there is a controller to choose there")
            const writeErrorsWas = [Brightness.lastError, DisplayBrightness._writeError, KeyboardBrightness._writeError]
            Brightness.lastError = "Could not set brightness"
            DisplayBrightness._writeError = "Display brightness could not be changed."
            KeyboardBrightness._writeError = "Keyboard light could not be changed. Check UPower permissions."
            DeviceDiagnostics.activate("brightness")
            DeviceDiagnostics.activate("displays")
            DeviceDiagnostics.activate("keyboardBrightness")
            root._check(Brightness.lastError === "" && DisplayBrightness._writeError === ""
                    && KeyboardBrightness._writeError === "",
                "a Diagnostics retry clears a write error that a re-read alone keeps")
            Brightness.lastError = writeErrorsWas[0]
            DisplayBrightness._writeError = writeErrorsWas[1]
            KeyboardBrightness._writeError = writeErrorsWas[2]
            const summary = DeviceDiagnostics.snapshot()
            root._check(summary.schemaVersion === 1 && summary.audio.name === undefined
                    && summary.bluetooth.name === undefined && summary.network.ssid === undefined
                    && summary.screens.every(screen => screen.name === undefined && screen.serial === undefined),
                "shareable diagnostics omit device names, network names and display serials")
            const copiedWas = Quickshell.clipboardText
            const copyStateWas = DeviceDiagnostics.copyState
            const copyErrorWas = DeviceDiagnostics.copyError
            DeviceDiagnostics.acceptReport(0, true, '{"schemaVersion":1,"runtime":{},"availability":{}}')
            root._check(DeviceDiagnostics.copyState === "failed" && Quickshell.clipboardText === copiedWas,
                "a timed-out diagnostic copy cannot replace the clipboard or claim success")
            DeviceDiagnostics.acceptReport(0, false, "malformed")
            root._check(DeviceDiagnostics.copyState === "failed" && Quickshell.clipboardText === copiedWas,
                "malformed diagnostic output preserves the clipboard and offers an error")
            DeviceDiagnostics.acceptReport(0, false, '{"schemaVersion":1,"runtime":{},"availability":{}}')
            const copiedReport = JSON.parse(Quickshell.clipboardText)
            root._check(DeviceDiagnostics.copyState === "done" && copiedReport.devices.schemaVersion === 1
                    && copiedReport.devices.audio.name === undefined,
                "copying diagnostics adds the current allowlisted device state to a valid versioned report")
            const holding = DeviceDiagnostics._copiedHoldTimer.running
            DeviceDiagnostics._copiedHoldTimer.stop()
            DeviceDiagnostics._copiedHoldTimer.triggered()
            root._check(holding && DeviceDiagnostics.copyState === "",
                "a copied diagnostic report returns to Copy after the same hold as the VPN address")
            Quickshell.clipboardText = copiedWas
            DeviceDiagnostics.copyState = copyStateWas
            DeviceDiagnostics.copyError = copyErrorWas
            root._check(diagnostics._attentionIssues.some(issue =>
                    issue.n === "Screen lock unavailable" && issue.a === "devices")
                    && diagnostics._attentionIssues.some(issue =>
                        issue.n === "Night light unavailable" && issue.a === "devices"),
                "unavailable selected programs link to the page that can fix them")
            ShellSettings.lockProvider = "auto"
            ShellSettings.nightLightProvider = "auto"
            root._check(!diagnostics._attentionIssues.some(issue =>
                    issue.n === "Screen lock unavailable" || issue.n === "Night light unavailable")
                    && diagnostics._optionalIssues.some(issue => issue.n === "Screen lock")
                    && !diagnostics._optionalIssues.some(issue => issue.n === "Night light"),
                "automatic providers keep missing add-ons optional and use installed alternatives")
            const disclosure = root._findTrayNode(diagnostics, item =>
                item.title === "Optional features" && typeof item._activate === "function")
            root._check(disclosure !== null && !diagnostics._optionalExpanded,
                "optional diagnostics start folded")
            if (disclosure) {
                disclosure._activate()
                root._check(diagnostics._optionalExpanded, "the optional-features row opens its list")
                disclosure._toggleExpanded()
                root._check(!diagnostics._optionalExpanded, "the optional-features chevron folds its list")
            }
            MenuState.setSettingsSection("maintenance")
            MenuState.selectTab(MenuState.settingsTab)
            MenuState.open = true
            const restoreRow = root._findTrayNode(diagnostics, item =>
                item.title === "Restore default settings" && typeof item._activate === "function")
            root._check(restoreRow !== null, "diagnostics exposes the restore-defaults control")
            if (restoreRow) {
                ShellSettings.lockProvider = "custom"
                restoreRow._activate()
                restoreRow._activate()
                root._check(diagnostics._armed && ShellSettings.lockProvider === "custom",
                    "a double-click cannot restore settings")
                diagnostics._armedAtMs = Date.now() - 3001
                restoreRow._activate()
                root._check(diagnostics._armed && ShellSettings.lockProvider === "custom"
                        && Date.now() - diagnostics._armedAtMs < Metrics.confirmGuardMs,
                    "an expired restore prompt rearms before a delayed timer can run")
                diagnostics._armedAtMs = Date.now() + 60000
                restoreRow._activate()
                root._check(diagnostics._armed && diagnostics._armedAtMs <= Date.now()
                        && ShellSettings.lockProvider === "custom",
                    "a backwards clock change restarts the restore prompt")
                diagnostics._disarm()
            }
            diagnostics._armed = true
            MenuState.selectTab(MenuState.homeTab)
            root._check(!diagnostics._armed, "leaving a cached diagnostics page disarms restore defaults")
            diagnostics.destroy()
        }
        diagnosticsComponent.destroy()

        const updatesComponent = Qt.createComponent("modules/menu/settings/SettingsUpdatesSection.qml")
        const updatesPage = updatesComponent.status === Component.Ready
            ? updatesComponent.createObject(root, { width: 360, animationActive: false }) : null
        root._check(updatesPage !== null, "update controls build for confirmation lifecycle checks")
        if (updatesPage) {
            MenuState.selectTab(MenuState.settingsTab)
            MenuState.open = true
            MenuState.setSettingsSection("updates")
            const pendingWas = ShellUpdate.count
            const verifiedWas = ShellUpdate.targetVerified
            const applyErrorWas = ShellUpdate.lastApplyError
            const targetStateWas = {
                targetTag: ShellUpdate.targetTag, targetRevision: ShellUpdate.targetRevision,
                summary: ShellUpdate.summary, pendingCommits: ShellUpdate.pendingCommits
            }
            // keeps the backend unable to apply even if a guard regresses
            ShellUpdate.targetVerified = false
            ShellUpdate.count = 1
            updatesPage._triggerShellAction()
            updatesPage._triggerShellAction()
            root._check(updatesPage._installArmed,
                "a double-click cannot confirm a shell update")
            updatesPage._installArmedAtMs = Date.now() - 10001
            updatesPage._triggerShellAction()
            root._check(updatesPage._installArmed
                    && Date.now() - updatesPage._installArmedAtMs < Metrics.confirmGuardMs,
                "an expired update prompt rearms before a delayed timer can run")
            updatesPage._installArmedAtMs = Date.now() + 60000
            updatesPage._triggerShellAction()
            root._check(updatesPage._installArmed && updatesPage._installArmedAtMs <= Date.now(),
                "a backwards clock change restarts the update prompt")
            updatesPage._disarmInstall()
            ShellUpdate._parse("1\ntarget " + "a".repeat(40) + " v7.8.9 verified\nabc1234 release")
            root._check(ShellUpdate.targetRevision === "a".repeat(40),
                "the update review retains its exact target revision")
            updatesPage._installArmed = true
            ShellUpdate._parse("1\ntarget " + "b".repeat(40) + " v7.8.9 verified\nabc1234 release")
            root._check(!updatesPage._installArmed,
                "changing a reviewed revision cancels confirmation even when its tag and count stay the same")
            updatesPage._disarmInstall()
            for (const key of Object.keys(targetStateWas)) ShellUpdate[key] = targetStateWas[key]
            ShellUpdate.count = pendingWas
            ShellUpdate.targetVerified = verifiedWas
            ShellUpdate.lastApplyError = applyErrorWas
            updatesPage._installArmed = true
            MenuState.setSettingsSection("clock")
            root._check(!updatesPage._installArmed,
                "leaving the system overview cancels an update-install confirmation")
            updatesPage._installArmed = true
            MenuState.selectTab(MenuState.homeTab)
            root._check(!updatesPage._installArmed,
                "leaving cached settings cancels an update-install confirmation")
            updatesPage.destroy()
        }
        updatesComponent.destroy()

        ShellSettings.overlayMonitor = "disconnected-probe-monitor"
        const devicesComponent = Qt.createComponent("modules/menu/settings/SettingsDevicesSection.qml")
        const devicesPage = devicesComponent.status === Component.Ready
            ? devicesComponent.createObject(root, { width: 360 }) : null
        root._check(devicesPage !== null, "devices builds for display recovery checks")
        if (devicesPage) {
            const picker = root._findTrayNode(devicesPage, item => item.key === "overlayMonitor")
            root._check(picker !== null && picker.enabled
                    && picker.model.some(choice => choice.value === ""),
                "a disconnected overlay display stays editable with a Follow focus choice")
            ShellSettings.overlayMonitor = ""
            root._check(devicesPage._hasOverlayChoice === devicesPage._hasMultiScreen,
                "clearing display routing hides the unnecessary single-display picker")
            root._check(root._findTrayNode(devicesPage, item => item.key === "lockProvider") !== null
                    && root._findTrayNode(devicesPage, item => item.key === "nightLightProvider") !== null
                    && root._findTrayNode(devicesPage, item => item.key === "ddcBrightnessEnabled") !== null,
                "system program choices and external brightness live on Devices")
            devicesPage.destroy()
        }
        devicesComponent.destroy()
        const interfaceComponent = Qt.createComponent("modules/menu/settings/SettingsInterfaceSection.qml")
        const interfacePage = interfaceComponent.status === Component.Ready
            ? interfaceComponent.createObject(root, { width: 360 }) : null
        root._check(interfacePage !== null
                && root._findTrayNode(interfacePage, item => item.key === "fontFamily") !== null
                && ["overlayMonitor", "lockProvider", "nightLightProvider", "ddcBrightnessEnabled", "brightnessDevice"]
                    .every(key => root._findTrayNode(interfacePage, item => item.key === key) === null),
            "Interface keeps text and accessibility, and no device or program row")
        if (interfacePage) interfacePage.destroy()
        interfaceComponent.destroy()
        SystemTools._tools = toolsWas
        SystemTools.ready = readyWas
        SystemTools.lastError = errorWas
        ShellSettings.lockProvider = lockWas
        ShellSettings.lockCommandCustom = customWas
        ShellSettings.nightLightProvider = nightWas
        ShellSettings.overlayMonitor = overlayWas
        MenuState.selectTab(tabWas)
        MenuState.open = openWas
        MenuState.setSettingsSection(sectionWas)
    }

    function _run(): void {
        root._checksRailScrollAndMic()
        root._checksControlFillsAndWidgetCatalog()
        root._checksWorkspaceScrollAndMenuWarm()
        root._checksWindowActivationAndMarker()
        root._checksBarPills()
        root._checksUnderline()
        root._checksVisualizerAndRim()
        root._checksCountdownsAndClockSteps()
        root._checksSurfaceGatingAndDropdowns()
        root._checksConfirmButtonsAndCpuSensors()
        root._checksWorkspaceHandoffAndSettingsFile()
        root._checksSettingsMarksAndVisualizerProfiles()
        root._checksNotificationHistory()
        root._checksSettingsSearchAndText()
        root._checksWindowTextAndToolOutput()
        root._checksWindowTitle()
        root._checksMediaWidgetAndTime()
        root._checksNowPlayingAndHomeDisplays()
        root._checksRailWavesAndAudioRoutes()
        root._checksAudioAndSliders()
        root._checksUpdatesSysInfoAndGestures()
        root._checksShellUpdate()
        root._checksPowerModeAndPresentation()
        root._checksKeyboardNavigationAndAlerts()
        root._checksNightLightAndSensors()
        root._checksBatteryAndHooks()
        root._checksDispatchAndNotificationOwner()
        root._checksAccentBalanceAndAnchors()
        root._checksNotificationStatePruning()
        root._checksNotificationTitlesIconsAndLimit()
        root._checksDisplayIdentityAndBluetoothDiscovery()
        root._checksBluetoothBrightnessAndHookQueue()
    }

    function _checksRailScrollAndMic(): void {
        root._checkSmoothGlide()
        root._checkPageLayout()
        root._checkAccessibleControls()
        root._checkNotificationKeyboard()
        root._checkHiddenBarControls()
        root._checkWifiScanners()
        root._checkDiscoveryRequests()
        root._checkOsdLifetime()
        root._checkOsdProfileHold()
        root._checkBrightnessOsdUnattended()
        root._checkOsdOverHome()
        root._checkSandboxWritesNoDevice()
        root._checkWifiDraft()
        root._checkScrollHolds()
        root._checkPanelFocus()
        root._checkPowerRail()
        root._checkPillTextBaseline()
        root._checkStackTags()
        root._checkThreadFolding()
        root._checkWeather()
        root._checkInputRecovery()
        root._checkBarSizing()
        root._checkWorkspaceIndicators()
        root._checkAccentPills()
        root._checkBluetoothRowRelease()
        root._checkBrightnessChoices()
        root._checkSystemWidget()
        root._checkReadingsOutlastFade()
        root._checkPageBuildHidden()
        root._checkAppHandoffs()
        root._checkBluetoothPairing()
        root._checkConnectivityConfirmations()
        root._checkMenuContrast()
        root._checkAccentContrast()
        root._checkLightPalette()
        root._checkContrastKeepsHue()
        root._checkGlassInks()
        root._checkAccentInk()
        root._checkStatusApart()
        root._check(MenuState.adjacentTab(MenuState.homeTab, false, 1) === MenuState.recentTab
                && MenuState.adjacentTab(MenuState.recentTab, false, 1) === MenuState.settingsTab
                && MenuState.adjacentTab(MenuState.settingsTab, false, 1) === MenuState.homeTab
                && MenuState.adjacentTab(MenuState.homeTab, false, -1) === MenuState.settingsTab
                && MenuState.adjacentTab(MenuState.settingsTab, true, 1) === MenuState.mediaTab
                && MenuState.adjacentTab(MenuState.homeTab, true, -1) === MenuState.mediaTab
                && MenuState.adjacentTab(MenuState.mediaTab, false, 1) === MenuState.recentTab,
            "Ctrl+Tab walks the rail's order, around the ends, past Now Playing when nothing plays")
        root._checkConnectivityBarActions()
        const pageMovedWas = Scroll._page.movedAt
        const scrollList = scrollListFactory.createObject(root)
        Scroll._page.movedAt = 0
        scrollList.contentY = 24
        root._check(Scroll._page.movedAt === 0 && !Scroll.wheelBelongsToPage(0),
            "a list moved by code leaves the wheel with a slider under the pointer")
        Scroll._page.movedAt = Date.now() - Scroll.pageLatchMs - 1
        root._check(!Scroll.wheelBelongsToPage(0),
            "a settled list releases its scroll gesture for deliberate slider adjustment")
        const latchedAt = Date.now() - Scroll.pageLatchMs / 2
        Scroll._page.movedAt = latchedAt
        root._check(Scroll.wheelBelongsToPage(0) && Scroll._page.movedAt > latchedAt,
            "a wheel query renews the page latch while the page holds the gesture")
        Scroll._page.movedAt = 0
        root._check(Scroll.wheelBelongsToPage(Date.now()) && Scroll._page.movedAt === 0,
            "a hover that has not rested passes the wheel on without starting a page latch")
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
        const updateCheckedAt = 10000000
        root._check(!Updates.backgroundCheckDue(updateCheckedAt, false, updateCheckedAt + 3599999)
                && Updates.backgroundCheckDue(updateCheckedAt, false, updateCheckedAt + 3600000),
            "reconnecting rechecks an hour-old package result while keeping a recent successful one")
        root._check(Updates.backgroundCheckDue(updateCheckedAt, true, updateCheckedAt + 1)
                && Updates.backgroundCheckDue(0, false, updateCheckedAt)
                && Updates.backgroundCheckDue(updateCheckedAt, false, updateCheckedAt - 1),
            "package checks resume after a failure, an uncompleted first check, or a clock rollback")

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
        root._check(Settings.splitCommand('"" --flag').length === 0
                && Settings.splitCommand("swaylock \\").length === 0
                && Settings.splitCommand("swaylock 'unclosed").length === 0,
            "empty program names and incomplete quoting never enable a lock command")
        root._check(JSON.stringify(Settings.splitCommand('swaylock --image "/home/me/Lock screen.png"'))
                === JSON.stringify(["swaylock", "--image", "/home/me/Lock screen.png"])
                && JSON.stringify(Settings.splitCommand('program ""')) === JSON.stringify(["program", ""]),
            "custom commands preserve quoted paths and intentional empty arguments")
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
        // hyprsunset talks to Hyprland, so outside a Hyprland session it stays off even when installed
        root._check(SystemTools.hasHyprsunset && Compositor.isHyprland
                ? hs.length === 3 && hs[0] === "hyprsunset" && hs[2] === "3400"
                : hs.length === 0,
            "a named night light provider resolves only when that program is installed")
        root._check(Settings.nightLightProviderArgv("hyprsunset", 10).length === 0
                || Settings.nightLightProviderArgv("hyprsunset", 10)[2] === "1000",
            "a night light temperature is clamped before it reaches the command")
        root._check(Settings.hyprsunsetNeutral(6500) && Settings.hyprsunsetNeutral(99999)
                && !Settings.hyprsunsetNeutral(6499) && !Settings.hyprsunsetNeutral(3400),
            "daylight runs hyprsunset's identity matrix, every warmer step a temperature")
        const hsDay = Settings.nightLightProviderArgv("hyprsunset", 6500)
        root._check(hsDay.length === 0 || (hsDay.length === 2 && hsDay[1] === "-i"),
            "night light starts hyprsunset neutral at daylight")
        root._check(Settings.nightLightProviderArgv("nonesuch", 4000).length === 0,
            "an unknown night light provider resolves to no command")
        const wlFloor = Settings.nightLightProviderArgv("wlsunset", 1000)
        root._check(wlFloor.length === 0
                || (wlFloor[2] === "1001" && wlFloor[4] === "1000"),
            "wlsunset keeps its day above its night at the coldest setting")
        ShellSettings.nightLightProvider = nlWas

        root._check(Brightness.notchLevel(13, 2, 15, 5) === 3
                && Brightness.notchLevel(20, 3, 15, -5) === 2
                && Brightness.notchLevel(13, 2, 15, -5) === 1,
            "a brightness notch on a 15-level backlight always moves one level")
        root._check(Brightness.notchLevel(45, 29491, 65535, 5) === 32768
                && Brightness.notchLevel(47, 30801, 65535, -5) === 29491,
            "a brightness notch on a fine backlight lands on the 5% grid")
        root._check(Brightness.notchLevel(100, 15, 15, 5) === 15
                && Brightness.notchLevel(7, 1, 15, -5) === 1,
            "a brightness notch stops at full and never turns the backlight off")

        root._check(Audio.deviceClass(null) === ""
                && Settings.soundSettingsCommand.length
                    === (SystemTools.hasPwvucontrol || SystemTools.hasPavucontrol ? 1 : 0),
            "the sound settings hand-off resolves to one mixer, or to none")

        const speakerNode = { id: 1 }
        const builtInMic = { id: 2 }
        const usbMic = { id: 3 }
        const playbackNode = { id: 4 }
        const recordingNode = { id: 5 }
        const trackedAudio = Audio.trackedNodes(speakerNode, builtInMic, [speakerNode],
            [builtInMic, usbMic], [playbackNode], [recordingNode])
        root._check(trackedAudio.length === 5 && trackedAudio.indexOf(usbMic) >= 0
                && trackedAudio.indexOf(playbackNode) >= 0 && trackedAudio.indexOf(recordingNode) >= 0,
            "audio tracking binds non-default microphones as well as devices and application streams")
        root._check(trackedAudio.filter(node => node === speakerNode).length === 1
                && trackedAudio.filter(node => node === builtInMic).length === 1,
            "default devices and repeated node roles bind only once")
        const replacedNode = { name: "headset" }
        root._check(Audio.namesake("headset", [{ name: "speaker" }, replacedNode]) === replacedNode
                && Audio.namesake("headset", [{ name: "speaker" }]) === null
                && Audio.namesake("", [{ name: "" }]) === null,
            "a default device replaced under its own name is found by that name; no name finds nothing")
        OsdBarState._clearEntries()
        OsdBarState._updateVolume()
        root._check(!Audio.ready && OsdBarState.activeCount === 0,
            "an output that is not there claims no mute on the OSD")
        root._check(Audio.trackedNodes(null, null, [null], [], [], []).length === 0,
            "a disconnected PipeWire graph leaves no tracked devices")
        const replacementMic = { id: 3 }
        const replacedAudio = Audio.trackedNodes(speakerNode, replacementMic, [speakerNode],
            [replacementMic], [], [])
        root._check(replacedAudio.indexOf(replacementMic) >= 0 && replacedAudio.indexOf(usbMic) < 0
                && replacedAudio.indexOf(builtInMic) < 0,
            "a microphone replacement tracks the new object and releases retired inputs")
        let metadataReads = 0
        const unboundMic = { get properties() { metadataReads++; return {} } }
        Audio.trackedNodes(null, null, [], [unboundMic], [], [])
        root._check(metadataReads === 0,
            "choosing nodes to track never depends on metadata that tracking itself populates")

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
    }

    // a card's corners and dividers follow what is on screen: a folding section is still there, and a Roundness change reshapes rows that stay put
    function _checkSettingsFolds(): void {
        // no motion: a Behavior would turn the stand-in heights below into glides
        const reduceWas = ShellSettings.reduceMotion
        ShellSettings.reduceMotion = true
        // restored even if a step throws, or every motion check after this one runs without motion
        try {
            const card = foldCardFactory.createObject(root)
            discoveryClock.wait(20)
            const r0 = card.radius
            const settled = card.head.topRadius === r0 && card.head.bottomRadius === 0 && card.tail.bottomRadius === r0
            // stand in for a frame mid-fold: the section is closing but still shows part of its row
            card.fold.expanded = false
            card.fold.height = 20
            discoveryClock.wait(20)
            const midFold = card.fold.layoutPresent === true && card.head.bottomRadius === 0 && card.tail.bottomRadius === r0
            card.fold.height = 0
            discoveryClock.wait(20)
            const folded = card.fold.layoutPresent === false && card.head.bottomRadius === r0
            root._check(settled && midFold && folded,
                "the row above a folding section keeps its divider and square corners until the fold is gone")
            card.radius = r0 + 6
            discoveryClock.wait(20)
            root._check(card.head.topRadius === r0 + 6 && card.head.bottomRadius === r0 + 6,
                "a card's end rows take its new corners when Roundness changes")
            card.destroy()
        } finally {
            ShellSettings.reduceMotion = reduceWas
        }

        // the end slope of a cubic bezier, relative to the average speed: above 1 the motion is still accelerating as it stops
        const endSlope = c => (1 - c[3]) / Math.max(1e-6, 1 - c[2])
        const host = foldDisclosureFactory.createObject(root)
        const d = host.disclosure
        root._check(d.exitEasing === Easing.BezierSpline && endSlope(d.exitCurve) < 1
                && d.enterEasing === Easing.BezierSpline && endSlope(d.enterCurve) < 1,
            "a fold eases into rest both ways, so the rows below never land at full speed")
        host.destroy()

        // the release stretch eases the knob's width while the flip slides it: a destination read off that width
        // moved every frame, restarted the slide each time, and held the knob still until the stretch had settled
        const knobReduceWas = ShellSettings.reduceMotion
        ShellSettings.reduceMotion = true
        try {
            const sw = knobSwitchFactory.createObject(root, { checked: true })
            const knob = root._findTrayNode(sw, it => it._restWidth !== undefined)
            sw._animateX = true
            const aimed = knob.x
            knob.width = knob._restWidth + 3
            const held = Math.abs(knob.x - aimed) < 0.01
            sw._animateX = false
            const pinned = Math.abs(knob.x + knob.width - (aimed + knob._restWidth)) < 0.01
            root._check(held && pinned,
                "a toggle's slide aims past the release stretch, while a held knob keeps its outer edge pinned")
            sw.destroy()
        } finally {
            ShellSettings.reduceMotion = knobReduceWas
        }
    }

    function _checksControlFillsAndWidgetCatalog(): void {
        root._checkSettingsFolds()
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
                    === "shellUpdate,tray,updates,system,network,bluetooth,keyboard,volume,microphone,brightness,battery,clock",
            "the widget catalog derives the shipped default layout")
    }

    function _checksWorkspaceScrollAndMenuWarm(): void {
        const workspaceStrip = workspaceStripFactory.createObject(root)
        const workspaceScrollWas = ShellSettings.wsScrollSwitch
        ShellSettings.wsScrollSwitch = true
        root._check(workspaceStrip._wheelKey === "workspaces:" + workspaceStrip.monitorName,
            "workspace scroll gestures are keyed by the targeted monitor")
        Scroll._processDelta(30, workspaceStrip._wheelKey, 60, 1, 0)
        workspaceStrip.barActive = false
        root._check(!workspaceStrip._scrollEnabled && Scroll._accums[workspaceStrip._wheelKey] === undefined,
            "concealing a workspace strip disables scrolling and clears its partial gesture")
        workspaceStrip.barActive = true
        Scroll._processDelta(30, workspaceStrip._wheelKey, 60, 1, 0)
        ShellSettings.wsScrollSwitch = false
        root._check(Scroll._accums[workspaceStrip._wheelKey] === undefined,
            "disabling workspace scrolling forgets its unfinished touchpad gesture")
        ShellSettings.wsScrollSwitch = workspaceScrollWas
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
        const pulseId = workspaceStrip.visibleIds[0]
        root._check(workspaceStrip._pulseIndex(pulseId, "OTHER-1", true) === -1
                && workspaceStrip._pulseIndex(pulseId, workspaceStrip.monitorName, true) === 0
                && workspaceStrip._pulseIndex(pulseId, "", true) === 0
                && workspaceStrip._pulseIndex(pulseId, "OTHER-1", false) === 0,
            "with workspace ids per output, a notification pulses only the bar of the sender's monitor")
        const slots = workspaceSlotModelFactory.createObject(root)
        let pageCasesMatch = true
        for (let scenario = 0; scenario < 120; scenario++) {
            const rows = []
            for (let id = 1; id <= 16; id++) {
                if ((id * 7 + scenario) % 5 === 0) continue
                rows.push({ wsId: id, output: (id + scenario) % 3 === 0 ? "HDMI-A-1" : "DP-1" })
            }
            slots.workspaces = rows
            slots.activeId = scenario % 19 + 1
            slots.effectiveWsCount = scenario % 5 + 1
            slots.perOutputWorkspaceIds = scenario % 2 === 0
            slots.monitorName = scenario % 11 === 0 ? "" : "DP-1"
            const own = rows.filter(row => row.output === slots.monitorName)
            const lowest = Math.min(slots.activeId, ...own.map(row => row.wsId))
            const follows = !slots.perOutputWorkspaceIds
                && rows.some(row => row.wsId < lowest && row.output !== slots.monitorName)
            const anchor = follows ? lowest : 1
            const cap = slots.perOutputWorkspaceIds && own.length > 0
                ? Math.max(...own.map(row => row.wsId)) : 0
            const allowed = []
            for (let id = anchor; id <= (cap || 40); id++) {
                if (!slots.perOutputWorkspaceIds && slots.monitorName.length > 0
                        && rows.some(row => row.wsId === id && row.output !== slots.monitorName)) continue
                allowed.push(id)
            }
            // Count the uncapped positions before active, including when it exceeds the cap.
            let before = 0
            for (let id = anchor; id < slots.activeId; id++) {
                if (!slots.perOutputWorkspaceIds && slots.monitorName.length > 0
                        && rows.some(row => row.wsId === id && row.output !== slots.monitorName)) continue
                before++
            }
            const start = Math.floor(before / slots.effectiveWsCount) * slots.effectiveWsCount
            const expected = allowed.slice(start, start + slots.effectiveWsCount).join(",")
            if (slots.visibleIdsKey !== expected) pageCasesMatch = false
        }
        root._check(pageCasesMatch,
            "workspace page arithmetic preserves output ownership, gaps, caps and slot counts")
        slots.monitorName = "DP-1"
        slots.perOutputWorkspaceIds = false
        slots.effectiveWsCount = 4
        slots.workspaces = [{ wsId: 1, output: "DP-1" }, { wsId: 2, output: "HDMI-A-1" }]
        slots.activeId = 1000000
        root._check(slots.visibleIdsKey === "999998,999999,1000000,1000001",
            "high workspace IDs resolve directly without scanning the intervening integers")
        slots.effectiveWsCount = 5
        slots.workspaces = [{ wsId: 4, output: "DP-1" }]
        slots.activeId = 4
        root._check(slots.visibleIdsKey === "1,2,3,4,5",
            "a lone monitor keeps the first page after Hyprland drops the empty workspaces below")
        slots.workspaces = [{ wsId: 2, output: "DP-1" }, { wsId: 7, output: "HDMI-A-1" }]
        slots.activeId = 2
        const firstMonitor = slots.visibleIdsKey
        slots.monitorName = "HDMI-A-1"
        slots.activeId = 7
        root._check(firstMonitor === "1,2,3,4,5" && slots.visibleIdsKey === "7,8,9,10,11",
            "the first monitor pages from 1 while the next one keeps its own ids")
        slots.destroy()
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
        const iconsBefore = workspaceApps.workspaceApps
        const visibleKeyBefore = workspaceApps._workspaceAppsKey
        workspaceApps.workspaceToplevels = workspaceApps.workspaceToplevels.concat([
            { output: "DP-1", wsId: 5, appId: "hidden app" }])
        root._check(workspaceApps._workspaceAppsKey === visibleKeyBefore
                && workspaceApps.workspaceApps === iconsBefore,
            "a window on a hidden workspace cannot rebuild the drawn workspace icons")
        workspaceApps.visibleIdsKey = "5"
        workspaceApps.visibleIndexById = ({ 5: 0 })
        root._check(workspaceApps.appsFor(1).length === 0 && workspaceApps.appsFor(5).length === 2,
            "switching workspace pages picks up identities deferred while their page was hidden")
        const pageIconsBefore = workspaceApps.appsFor(5)
        workspaceApps.rebuild()
        root._check(workspaceApps.appsFor(5) === pageIconsBefore,
            "equal workspace icon fields retain their existing delegates")
        workspaceApps.workspaceToplevels = workspaceApps.workspaceToplevels.concat([
            { output: "DP-1", wsId: 5, appId: "foot" }])
        root._check(workspaceApps.appsFor(5)[0].count === 2
                && workspaceApps.appsFor(5) !== pageIconsBefore,
            "a visible app count change refreshes its workspace icons")
        workspaceApps.visibleIdsKey = "1"
        workspaceApps.visibleIndexById = ({ 1: 0 })
        const workspaceWindows = ["app.one", "app.two", "app.three", "app.four", "app.five"]
            .map(appId => ({ output: "DP-1", wsId: 1, appId: appId }))
        workspaceApps.workspaceToplevels = workspaceWindows
        workspaceApps.rebuild()
        root._check(workspaceApps.appsFor(1).length === 3 && workspaceApps.appCountFor(1) === 5,
            "workspace icons keep three delegates while counting apps beyond the visible limit")
        const orderedApps = workspaceApps.appsFor(1)
        workspaceApps.workspaceToplevels = workspaceWindows.slice().reverse()
        workspaceApps.rebuild()
        root._check(workspaceApps.appsFor(1) === orderedApps,
            "compositor window reordering keeps workspace icon positions and delegates stable")
        workspaceApps.workspaceToplevels = workspaceWindows.slice(1)
        workspaceApps.rebuild()
        root._check(workspaceApps.appsFor(1).map(app => app.appId).join(",") === "app.two,app.three,app.four"
                && workspaceApps.appCountFor(1) === 4,
            "closing an app retains surviving icons and fills only the released slot")
        workspaceApps.workspaceToplevels = workspaceWindows.slice(1).concat(workspaceWindows[1])
        workspaceApps.rebuild()
        root._check(workspaceApps.appCountFor(1) === 4 && workspaceApps.appsFor(1)[0].count === 2,
            "multiple windows of an app affect its badge without inflating app overflow")
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
    }

    function _checksWindowActivationAndMarker(): void {
        const kittyGuess = { pid: 1638, cls: "kitty", ref: "c" }
        root._check(WindowActions.focusIsSourceApp(kittyGuess, [
                    { pid: 1638, cls: "kitty", ref: "a", focused: false },
                    { pid: 1638, cls: "kitty", ref: "b", focused: true }])
                && !WindowActions.focusIsSourceApp(kittyGuess, [
                    { pid: 1638, cls: "kitty", ref: "a", focused: false },
                    { pid: 900, cls: "zen", ref: "z", focused: true }])
                && !WindowActions.focusIsSourceApp(kittyGuess, [])
                && !WindowActions.focusIsSourceApp(null, [{ pid: 1, cls: "x", focused: true }]),
            "a notification click keeps the window the app raised itself instead of guessing another")
        const raisedPool = [{ ref: "0xa", pid: 1638, cls: "kitty" }, { ref: "0xb", pid: 1638, cls: "kitty" }]
        root._check(WindowActions.raisedSource(raisedPool, ["0xb"], []).ref === "0xb"
                && WindowActions.raisedSource(raisedPool, ["0xa", "0xb"], ["0xa"]).ref === "0xb"
                && WindowActions.raisedSource(raisedPool, ["0xa"], ["0xa"]) === null
                && WindowActions.raisedSource(raisedPool, [], []) === null
                && WindowActions.raisedSource(null, ["0xb"], []) === null
                && WindowActions.raisedSource(raisedPool, ["0xb"], [], kittyGuess).ref === "0xb"
                && WindowActions.raisedSource(raisedPool, ["0xb"], [], { pid: 900, cls: "zen" }) === null
                && WindowActions.raisedSource(raisedPool, ["0xb"], [], { pid: 0, cls: "kitty" }).ref === "0xb"
                && Array.isArray(Compositor.urgentRefs),
            "a notification click follows the window its app just marked urgent, not one already asking")
        WindowActions._watchRaise(kittyGuess, false)
        const buttonWatch = WindowActions._pendingSource === kittyGuess && WindowActions._sourceFallback.running
        WindowActions._sourceFallback.triggered()
        const buttonGuessed = WindowActions._pendingSource !== null || WindowActions._guessSource
        WindowActions.focusNotificationSourceAfterAction(null)
        root._check(buttonWatch && !buttonGuessed && WindowActions._guessSource && WindowActions._pendingSource === null,
            "a notification button's click follows only its sender's raise and guesses no window, the default action still may")
        WindowActions._sourceFallback.stop()
        WindowActions._guessSource = false
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

        const parentCacheWas = WindowActions._parentPidCache
        const parentNow = Date.now()
        WindowActions._parentPidCache = {
            future: { value: 7, time: parentNow + 60000 },
            expired: { value: 8, time: parentNow - WindowActions._parentPidCacheTtlMs - 1 },
            invalid: { value: 9, time: "not-a-time" },
            recent: { value: 10, time: parentNow }
        }
        WindowActions._pruneParentPidCache(parentNow)
        root._check(Object.keys(WindowActions._parentPidCache).join(",") === "recent",
            "parent PID cache pruning drops expired, invalid and future timestamps")
        // no linux pid reaches this value, so a fresh /proc lookup must miss
        WindowActions._parentPidCache = {
            "2147483647": { value: 77, time: parentNow + 60000 }
        }
        root._check(WindowActions._parentPid(2147483647) === -1,
            "a backwards clock change cannot reuse a stale notification process parent")
        WindowActions._parentPidCache = parentCacheWas

        const hereRef = WindowActions._hereWorkspace().ref
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
        const namedClients = [
            { ref: "mail", wsId: -1338, wsRef: -1338, wsName: "mail", focusRank: 0 },
            { ref: "chat", wsId: -1338, wsRef: -1338, wsName: "chat", focusRank: 4 }
        ]
        const onMail = { ref: -1338, name: "mail" }
        root._check(WindowActions._chooseMatchingSource(namedClients, () => true, onMail).ref === "chat"
                && WindowActions._chooseMatchingSource(namedClients, c => c.ref === "mail", onMail).ref === "mail"
                && WindowActions._chooseMatchingSource(namedClients, () => true, { ref: 3, name: "3" }).ref === "mail"
                && WindowActions._chooseMatchingSource([{ ref: "here", wsId: 1, wsRef: 11, focusRank: 0 },
                    { ref: "away", wsId: 2, wsRef: 12, focusRank: 4 }], () => true, { ref: 11, name: "chat" }).ref === "away",
            "on a named workspace, a window on another named one counts as elsewhere")
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

        // under a fullscreen window nothing draws a frame, and a job left in flight there stops every Timer
        ShellSettings.reduceMotion = false
        const unseenWas = Motion.unseen
        const motionHost = motionHostFactory.createObject(root)
        const unseenGlide = smoothGlideFactory.createObject(root, { target: 0, duration: 240 })
        unseenGlide.target = 360
        const unseenPulse = pulseLoopFactory.createObject(root, {
            target: pulseTarget, targetProperty: "value", active: true, duration: 50, restValue: 1
        })
        const pulsing = unseenPulse.running
        Motion.unseen = true
        motionHost.v = 100
        root._check(motionHost.v === 100 && unseenGlide.value === 360
                && pulsing && !unseenPulse.running && pulseTarget.value === 1 && !Motion.allowsMotion(false, false),
            "while a fullscreen window hides the shell, changes land at once, glides snap and loops rest")
        Motion.unseen = unseenWas
        motionHost.destroy()
        unseenGlide.destroy()
        unseenPulse.destroy()
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

        const glideMarker = workspaceMarkerFactory.createObject(root)
        const travel = glideMarker._travel
        glideMarker.targetX = 100
        root._check(travel.running && glideMarker.x === 0,
            "a workspace switch glides the marker instead of jumping to the new cell")
        for (let i = 0; i < 5; i++) travel._advance(1 / 240)
        const outward = travel._velocity
        glideMarker.targetX = 0
        travel._advance(1 / 240)
        root._check(outward > 0 && glideMarker.x > 0 && glideMarker.x < 100
                && travel._velocity > -outward,
            "switching back mid-travel slows the marker through the turn instead of reversing in one frame")
        glideMarker.paging = true
        glideMarker.targetX = 300
        root._check(glideMarker.x === 300 && !travel.running,
            "a page change still places the marker at once")
        glideMarker.destroy()

        const lineHost = Qt.createQmlObject("import QtQuick; Item { y: 2 }", root)
        const lineMarker = workspaceMarkerFactory.createObject(lineHost, { style: "bar" })
        lineMarker._dpr = 1.25
        const lineTop = lineMarker.mapToItem(null, 0, 0).y * 1.25
        const lineBottom = lineMarker.mapToItem(null, 0, lineMarker.height).y * 1.25
        root._check(Math.abs(lineTop - Math.round(lineTop)) < 0.01
                && Math.abs(lineBottom - Math.round(lineBottom)) < 0.01
                && Math.round(lineBottom - lineTop) === 4,
            "the line marker sits on whole device pixels at 1.25, four of them tall")
        lineMarker.destroy()
        lineHost.destroy()

        const hitCell = workspaceButtonFactory.createObject(root, {
            wsId: 3, monitorReady: true, active: false, occupied: true,
            urgent: false, apps: [], compact: false, iconSize: 14,
            cellWidth: 26, rowHeight: 24, barActive: true,
            initialized: true, paging: false, markerCovers: true,
            hitTop: 6, hitBottom: 6, hitGap: 3
        })
        const hit = root._findTrayNode(hitCell, item => item.objectName === "workspace-hit")
        root._check(hit && hit.x === -1.5 && hit.y === -6 && hit.width === 29 && hit.height === 36
                && hit.data.filter(o => o.cursorShape !== undefined).length === 2,
            "a workspace's click target spans the bar's height and half the gap to each neighbour")
        hitCell.destroy()
        const hitTick = workspaceUrgentTickFactory.createObject(root, {
            liveId: 9, rowHeight: 24, barActive: true, hitTop: 6, hitBottom: 6
        })
        const tickHit = root._findTrayNode(hitTick, item => item.objectName === "workspace-tick-hit")
        root._check(tickHit && tickHit.y === -6 && tickHit.height === 36 && tickHit.width === hitTick.width
                && tickHit.data.filter(o => o.cursorShape !== undefined).length === 2,
            "the off-page urgent arrow's click target spans the bar's height too")
        hitTick.destroy()
        const tallStrip = workspaceStripFactory.createObject(root)
        const stripRow = root._findTrayNode(tallStrip, item => item.objectName === "workspace-strip")
        root._check(tallStrip.implicitHeight === Metrics.barHeight && tallStrip._rowY > 0
                && Math.abs(tallStrip._rowY + tallStrip.btnH + tallStrip._rowBelow - tallStrip.height) < 0.01
                && Math.abs(tallStrip._rowY - tallStrip._rowBelow) < 0.01
                && stripRow && stripRow.y === tallStrip._rowY && stripRow.height === tallStrip.btnH,
            "the workspace strip takes the bar's height and keeps its row centred in it")
        tallStrip.destroy()
        {
            const keys = ["reduceMotion", "neutralTheme", "baseTone", "barOpacity", "highContrast", "wsUrgentPulse"]
            const saved = keys.map(key => ShellSettings[key])
            ShellSettings.reduceMotion = true
            ShellSettings.neutralTheme = true
            ShellSettings.baseTone = "charcoal"
            ShellSettings.barOpacity = 0.58
            ShellSettings.highContrast = false
            ShellSettings.wsUrgentPulse = false
            const overWhite = Theme.mix(Qt.color("#ffffff"), Theme.background, Theme.panelOpacity)
            const overBlack = Theme.mix(Qt.color("#000000"), Theme.background, Theme.panelOpacity)
            const legible = ink => Math.min(Theme.contrastRatio(ink, overWhite), Theme.contrastRatio(ink, overBlack))
            const urgentCell = workspaceButtonFactory.createObject(barFixtureHost, {
                wsId: 7, monitorReady: true, active: false, occupied: true,
                urgent: true, apps: [], compact: false, iconSize: 14,
                cellWidth: 26, rowHeight: 24, barActive: true,
                initialized: true, paging: false, markerCovers: true
            })
            const number = root._findTrayNode(urgentCell, item => item.text === "7" && item.font !== undefined)
            const urgentTick = workspaceUrgentTickFactory.createObject(barFixtureHost, {
                liveId: 9, rowHeight: 24, barActive: true
            })
            const arrow = root._findTrayNode(urgentTick, item => item._hot !== undefined)
            root._check(legible(Theme.barWarning) < 4.49 && number !== null && arrow !== null
                    && legible(number.color) >= 4.49 && legible(arrow.color) >= 4.49,
                "an urgent workspace's number and its off-page arrow are words: a label's contrast on a see-through bar, not a mark's")
            urgentCell.destroy()
            urgentTick.destroy()
            for (let i = keys.length - 1; i >= 0; i--) ShellSettings[keys[i]] = saved[i]
        }
    }

    function _checksBarPills(): void {
        const pill = pillFactory.createObject(root)
        pill._ready = true
        pill.interactive = true
        let activations = 0
        pill.activated.connect(() => activations++)
        pill.Accessible.pressAction()
        root._check(activations === 1, "an awake bar pill accepts its accessible action")
        root._check(pill !== null && pill.motionActive,
            "an awake pill on a visible bar permits content motion")
        pill.glyph = "b"
        root._check(pill._shownGlyph === "a",
            "an awake pill animates a glyph swap instead of jumping to it")
        pill.hoverActive = true
        pill.barActive = false
        pill.Accessible.pressAction()
        root._check(activations === 1 && !pill.Accessible.focusable,
            "a sleeping bar pill rejects accessible activation")
        root._check(!pill.motionActive && pill._shownGlyph === "b",
            "a sleeping bar lands the pending glyph without animating")
        root._check(!pill.hoverEnabled && !pill.expanded && !pill.hoverActive,
            "a sleeping pill clears a previously revealed hover value")
        pill.barActive = true
        pill.hoverActive = true
        pill.collapsed = true
        pill.Accessible.pressAction()
        root._check(activations === 1,
            "a fading bar pill rejects activation before its width finishes collapsing")
        root._check(!pill.hoverEnabled && !pill.expanded && !pill.motionActive,
            "a collapsing pill stops revealing values and animating content")
        pill.collapsed = false
        pill.hoverActive = true
        pill.enabled = false
        pill.Accessible.pressAction()
        root._check(activations === 1, "a disabled bar pill rejects accessible activation")
        root._check(!pill.hoverEnabled && !pill.hoverActive,
            "a disabled pill clears hover state even without a pointer exit")
        pill.enabled = true
        {
            const hoverRow = pill.children.find(item => typeof item.forceLayout === "function")
            pill.shrinkDelay = 2400
            pill.text = Qt.binding(() => pill.expanded ? "English (US)" : "us")
            pill.hoverActive = true
            hoverRow.forceLayout()
            const revealedW = pill.rowWidth
            root._check(pill.expanded && pill._minW >= revealedW,
                "a hover reveal widens the pill to its full label")
            pill.hoverActive = false
            hoverRow.forceLayout()
            root._check(!pill.expanded && pill._minW <= pill.rowWidth && pill.rowWidth < revealedW,
                "a hover reveal closes without holding the wide label's width")
            pill.shrinkDelay = 600
        }
        {
            const held = pillFactory.createObject(root, { text: "12.4 MB/s" })
            const heldRow = held.children.find(item => typeof item.forceLayout === "function")
            heldRow.forceLayout()
            held.width = heldRow.width + held.horizontalPadding * 2 + 30
            const pinned = heldRow.x === held.horizontalPadding
            // as in the first frame of a hover reveal: the reading has grown, the width has not caught up
            held.width = heldRow.width + held.horizontalPadding * 2 - 20
            const revealing = heldRow.x === held.horizontalPadding && held.clip
            held.collapsed = true
            const folding = heldRow.x < held.horizontalPadding && heldRow.width > 0
            held.collapsed = false
            root._check(pinned && revealing && folding && heldRow.x < held.horizontalPadding,
                "an open pill keeps its content at its padding while its edge uncovers a longer reading, and folds it into the centre and out of it")
            held.destroy()
        }
        {
            const motionWas = ShellSettings.reduceMotion
            ShellSettings.reduceMotion = true
            const narrow = pillFactory.createObject(root, { text: "" })
            const wide = pillFactory.createObject(root, { text: "A long reading on a wide pill" })
            const capOf = p => p.children.find(item => item.hot !== undefined && item.selected !== undefined)
            const caps = [capOf(narrow), capOf(wide)]
            const at = () => caps.map(c => c.parent.width - c.width)
            const rest = at()
            caps.forEach(c => c.hot = true)
            const hot = at()
            const shown = caps.every(c => c.opacity === 1 && c.visible)
            caps.forEach(c => { c.hot = false; c.pressed = true })
            const pressed = at()
            root._check(caps.every(c => c !== undefined) && wide.width > narrow.width * 3
                    && rest.every(d => d === 2) && hot.every(d => d === 0) && shown
                    && pressed.every(d => Math.abs(d - 0.8) < 1e-6),
                "the bar's hover capsule settles the same pixel onto a narrow pill and a wide one, and dips less on a press")
            narrow.destroy()
            wide.destroy()
            ShellSettings.reduceMotion = false
            const lv = pillFactory.createObject(root, { text: "45% · A long output name",
                levelValue: 1, levelVisible: true, shrinkDelay: 0 })
            lv._ready = true
            const lvRow = lv.children.find(item => typeof item.forceLayout === "function")
            const track = lv.children.find(item => item.height === 2 && item.children.length === 2)
            const glide = lv.data.find(item => item.precision !== undefined && item._advance !== undefined)
            lv.text = "45%"
            lvRow.forceLayout()
            let worst = 0, steps = 0
            for (; steps < 12 && glide && glide.running; steps++) {
                glide._advance(0.016)
                worst = Math.max(worst, track.children[1].width - track.width)
            }
            root._check(track !== undefined && steps > 3 && worst < 1,
                "a pill's level fill keeps inside its track while the pill shrinks, not " + Math.round(worst) + " px past it")
            lv.destroy()

            // the system monitor's hover: its first reading grows in the middle of the row, between glyphs
            const sp = pillFactory.createObject(root, { text: "20%", reserveText: "00%", shrinkDelay: 0,
                segments: [{ glyph: "b", text: "50°", reserve: "00°" }] })
            sp._ready = true
            const spRow = sp.children.find(item => typeof item.forceLayout === "function")
            const glidesOf = obj => (obj.data ?? []).reduce((out, it) =>
                out.concat(it._advance !== undefined && it.precision !== undefined ? [it] : [], it.data ? glidesOf(it) : []), [])
            const tailOf = () => spRow.children.filter(item => item._finalW !== undefined).pop()
            const settle = () => { sp.width = Math.ceil(sp.implicitWidth); spRow.forceLayout() }
            // the trailing reading's distance from the pill's far edge, which stays put in a right-hand zone
            const tailGap = () => sp.width - (tailOf().mapToItem(sp, 0, 0).x)
            settle()
            const restGap = tailGap()
            sp.text = "12 GB of 62 GB"
            // the relayout a real frame does before the first glide step
            spRow.forceLayout()
            const finalAtOnce = sp.rowWidth > 100
            let drift = 0, frames = 0
            const targets = []
            for (; frames < 40 && glidesOf(sp).some(g => g.running); frames++) {
                glidesOf(sp).forEach(g => g._advance(0.016))
                // read before the relayout: the Row measures at polish, after the glide step in the same frame
                targets.push(sp.rowWidth)
                settle()
                drift = Math.max(drift, Math.abs(tailGap() - restGap))
            }
            root._check(tailOf() !== undefined && finalAtOnce && frames > 3 && drift < 1.5,
                "a reading growing between a pill's glyphs uncovers in place: the readings after it hold within a pixel, not "
                    + Math.round(drift) + " px")
            root._check(targets.length > 3 && targets.every(w => w === sp.rowWidth)
                    && sp.rowWidth === Math.ceil(spRow.implicitWidth),
                "a segmented pill heads for the row's laid-out width through its readings' glides, between relayouts too: "
                    + [...new Set(targets)].join(", ") + " for " + Math.ceil(spRow.implicitWidth))
            sp.destroy()

            root._check(lv.concealsAs("45% · Speakers", "45%", true) && lv.concealsAs("45%", "", true)
                    && !lv.concealsAs("100%", "10%", false) && !lv.concealsAs("45% · Speakers", "46%", true)
                    && !lv.concealsAs("45%", "45% · Speakers", true),
                "only a reading cut back to its own start as a hover closes is drawn on the way out")
            const gp = pillFactory.createObject(root)
            gp.text = Qt.binding(() => gp.expanded ? "45% · Speakers" : "45%")
            gp._ready = true
            const gpRow = gp.children.find(item => typeof item.forceLayout === "function")
            const gpGlide = gp.data.find(item => item.precision !== undefined && item._advance !== undefined)
            gp.hoverActive = true
            gpRow.forceLayout()
            gpGlide._snap()
            const openW = gp.width
            discoveryClock.wait(1)
            gp.hoverActive = false
            gpRow.forceLayout()
            const ghost = root._findTrayNode(gp, item => item.text === "45% · Speakers" && item.visible)
            const drawnShort = root._findTrayNode(gp, item => item !== gp && item.text === "45%" && item.visible)
            const closing = gp._ghostText === "45% · Speakers" && ghost !== null && drawnShort === null
                && gpGlide.running && gp.clip
            for (let i = 0; i < 200 && gpGlide.running; i++) gpGlide._advance(0.016)
            const settled = gp._ghostText === "" && gp.width < openW && !gp.clip
                && root._findTrayNode(gp, item => item !== gp && item.text === "45%" && item.visible) !== null
            gp._expandedBefore = false
            gp.text = "46%"
            root._check(closing && settled && gp._ghostText === "",
                "a hover closing keeps the cut-back reading drawn until the pill's edge has closed over it, and a new value never lingers")
            gp.destroy()

            // the pointer moving from one pill to the next inside a zone keeps the first one's detail open. The pointer is
            // stood in for: under a loaded check.sh synthetic moves stopped reaching the zone at all. Measured with real
            // moves in a standalone walk: aimed at a neighbour's centre, 1 of 3 landed before, 3 of 3 after
            // a widget switched on later unfolds out of nothing; the zone's first widgets and a reorder's rebuilt ones do not
            {
                const growZone = Qt.createComponent("modules/bar/BarZone.qml").createObject(barFixtureHost, {
                    orderKeys: ["network"], compact: false, height: 36,
                    widgetComponents: { network: detailPillFactory, volume: detailPillFactory }
                })
                const pillsOf = () => {
                    const out = []
                    const walk = it => { if (it.holdOpen !== undefined) out.push(it); for (const c of it.children) walk(c) }
                    walk(growZone)
                    return out
                }
                const firstWide = pillsOf().length === 1 && pillsOf()[0].implicitWidth > 0
                const builtDeadline = Date.now() + 1000
                while ((!growZone._built || growZone.visibleKeys.length !== 1) && Date.now() < builtDeadline) discoveryClock.wait(10)
                growZone.orderKeys = ["network", "volume"]
                const pills = pillsOf()
                const fresh = pills.find(p => p.implicitWidth === 0 && p._unfoldPending)
                const kept = pills.find(p => p !== fresh)
                const startDeadline = Date.now() + 1000
                while (fresh && fresh._unfoldPending && Date.now() < startDeadline) discoveryClock.wait(5)
                const glide = fresh ? fresh.data.find(it => it.precision !== undefined && it._advance !== undefined) : null
                if (glide) for (let i = 0; i < 3; i++) glide._advance(0.016)
                const opening = fresh && fresh.implicitWidth > 0 && glide && glide.value < glide.target
                root._check(firstWide, "a bar zone's first widgets arrive with the bar, whole")
                root._check(pills.length === 2 && fresh !== undefined && opening,
                    "a bar widget switched on later unfolds out of nothing instead of landing whole")
                root._check(pills.length === 2 && kept !== undefined && kept !== fresh && kept.implicitWidth > 0,
                    "a widget rebuilt in place by a reorder arrives whole")
                growZone.destroy()
            }
            // a widget folding away keeps its layout until the fold ends; its divider goes as the fold starts, beside it
            {
                const foldZone = Qt.createComponent("modules/bar/BarZone.qml").createObject(barFixtureHost, {
                    orderKeys: ["network", "volume"], compact: false, height: 36,
                    widgetComponents: { network: foldingWidgetFactory, volume: foldingWidgetFactory }
                })
                const deadline = Date.now() + 1000
                while (foldZone.visibleKeys.length !== 2 && Date.now() < deadline) discoveryClock.wait(10)
                const both = foldZone.visibleKeys.length === 2
                const folding = root._findTrayNode(foldZone, item => item.fading !== undefined)
                folding.fading = true
                folding.show = false
                discoveryClock.wait(10)
                root._check(both && folding.layoutVisible && foldZone.visibleKeys.length === 1,
                    "a bar widget folding away gives up its divider as the fold starts, not in one step after it")
                foldZone.destroy()
            }
            const valuesWas = ShellSettings.valuesOnHover
            ShellSettings.valuesOnHover = false
            const zone = Qt.createComponent("modules/bar/BarZone.qml").createObject(barFixtureHost, {
                orderKeys: ["network", "volume"], compact: false, height: 36,
                widgetComponents: { network: detailPillFactory, volume: detailPillFactory }
            })
            const netPill = zone ? root._findTrayNode(zone, item => item.holdOpen !== undefined) : null
            const volPill = zone ? root._findTrayNode(zone, item => item.holdOpen !== undefined && item !== netPill) : null
            // the slot's key, read from the pill's own Loader: the hold is claimed by key
            const keyOf = pill => pill?.parent?.loadedKey ?? ""
            let held = false, bound = false, closed = false, alone = false, handed = false, kept = false
            if (netPill && volPill && netPill !== volPill) {
                zone.pointerInside = true
                zone.claimHold(keyOf(volPill))
                bound = volPill.holdOpen && !netPill.holdOpen
                volPill.hoverActive = true
                volPill._pointerChanged(false)
                held = volPill.expanded
                // settling on the next widget hands it the hold, and the detail left behind closes
                netPill.hoverActive = true
                zone.claimHold(keyOf(netPill))
                handed = !volPill.holdOpen && !volPill.expanded && netPill.holdOpen && netPill.expanded
                netPill._pointerChanged(false)
                kept = netPill.expanded
                zone.pointerInside = false
                closed = !netPill.holdOpen && !volPill.expanded && !netPill.expanded
                volPill.hoverActive = true
                volPill._pointerChanged(false)
                alone = !volPill.expanded
            }
            root._check(bound && held && closed && alone,
                "a pill's hover detail stays open while the pointer moves on inside its bar zone, and every one closes as it leaves")
            root._check(handed && kept,
                "settling on another widget in the zone closes the detail left behind, so only one shows at a time")
            // hung from the right, a detail to the right of the widget settled on stays: folding it would slide that widget away
            let rightKept = false, rightLeft = false
            if (netPill && volPill && netPill !== volPill) {
                zone.anchoredAt = Qt.AlignRight
                zone.pointerInside = true
                zone.claimHold(keyOf(volPill))
                zone.claimHold(keyOf(netPill))
                rightKept = volPill.holdOpen && netPill.holdOpen
                zone._heldKeys = []
                zone.claimHold(keyOf(netPill))
                zone.claimHold(keyOf(volPill))
                rightLeft = !netPill.holdOpen && volPill.holdOpen
                zone.pointerInside = false
                zone.anchoredAt = Qt.AlignLeft
            }
            root._check(rightKept && rightLeft && !netPill.holdOpen && !volPill.holdOpen,
                "in a zone hung from the right, a detail folding never slides the widget settled on; the rest close on leaving")
            // a popup opened from the zone takes the pointer; the details it found open wait for it to close
            let popupHeld = false, popupReleased = false, elsewhere = false
            if (netPill && volPill && netPill !== volPill) {
                const openWas = OverlayCoordinator._openCount
                zone.pointerInside = true
                zone.claimHold(keyOf(volPill))
                volPill.hoverActive = true
                OverlayCoordinator._openCount = 1
                zone.pointerInside = false
                volPill._pointerChanged(false)
                popupHeld = volPill.expanded && zone.holding
                OverlayCoordinator._openCount = 0
                popupReleased = !volPill.expanded && !zone.holding
                // a popup opened while the pointer was elsewhere holds nothing here
                OverlayCoordinator._openCount = 1
                elsewhere = !zone.holding
                OverlayCoordinator._openCount = openWas
            }
            root._check(popupHeld && popupReleased && elsewhere,
                "a popup opened from a bar zone keeps the details it found open until it closes, and one opened elsewhere holds none")
            zone?.destroy()
            ShellSettings.valuesOnHover = valuesWas
            ShellSettings.reduceMotion = motionWas
        }
        pill.text = "A current label"
        pill.animateText = true
        root._check(root._showsText(pill, "A current label"),
            "enabling animated pill text keeps the current label visible")
        pill.glyph = "c"
        pill.animateGlyph = false
        root._check(pill._shownGlyph === "c",
            "disabling glyph motion settles the latest icon")
        const label = root._findTrayNode(pill, item => item._hasShownText !== undefined
            && item._shown !== undefined)
        const swap = label?.parent.data.find(item => item.animations?.length === 3)
        let swaps = 0
        if (swap) swap.started.connect(() => swaps++)
        pill.text = "First reading"
        pill.text = "Second reading"
        pill.text = "Latest reading"
        root._check(swap && swaps === 1,
            "rapid pill readings share a text fade instead of postponing it with every update")
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
        barClock._datePeek = true
        barClock.barActive = false
        barClock.Accessible.pressAction()
        root._check(!CalendarState.open && !barClock._datePeek,
            "a sleeping clock clears its date peek and rejects opening the calendar")
        barClock.barActive = true
        barClock.enabled = false
        barClock.Accessible.pressAction()
        root._check(!CalendarState.open, "a disabled clock rejects opening the calendar")
        const digitSlot = (after) => root._findTrayNode(barClock, item => item !== after
            && item.reserveText !== undefined && item.horizontalAlignment === Text.AlignRight)
        const hourSlot = digitSlot(null), minuteSlot = digitSlot(hourSlot)
        const clock12Before = ShellSettings.clock12h, hourBefore = DateTime.cachedHour
        ShellSettings.clock12h = true
        DateTime.cachedHour = "3"
        const narrowHour = hourSlot.implicitWidth < minuteSlot.implicitWidth
        DateTime.cachedHour = "10"
        root._check(narrowHour && hourSlot.implicitWidth === minuteSlot.implicitWidth,
            "a one-digit 12-hour hour leaves no blank digit before it, and 10-12 still take two")
        ShellSettings.clock12h = clock12Before
        DateTime.cachedHour = hourBefore
        barClock.destroy()

        const statusClock = clockFactory.createObject(root)
        const statusGlyph = glyph => root._findTrayNode(statusClock, item => item.text === glyph && item.expanded !== undefined)
        const statusDndWas = ShellSettings.dnd, statusMissedWas = Notifications.missedCount
        ShellSettings.dnd = false
        Notifications.presentationMode = true
        Notifications.missedCount = 2
        root._check(statusGlyph("󰐨 ").expanded && !statusGlyph("󱒃 ").expanded
                && statusGlyph("󰂛 ").expanded && Qt.colorEqual(statusGlyph("󰂛 ").color, Theme.barAccentMark)
                && statusClock.accessibleName.indexOf(", 2 missed notifications") >= 0,
            "presentation mode shows a quiet glyph and the bell takes the accent for held-back notifications")
        Idle.keepAwake = true
        root._check(!statusGlyph("󰅶 ").expanded,
            "presentation mode already keeps the screen awake, so the clock shows no second cup")
        Idle.keepAwake = false
        Notifications.presentationMode = false
        root._check(Notifications.missedCount === 0 && !statusGlyph("󰂛 ").expanded,
            "ending the silence clears the held-back count and folds the bell")
        ShellSettings.dnd = statusDndWas
        Notifications.missedCount = statusMissedWas
        statusClock.destroy()
        {
            const keys = ["reduceMotion", "neutralTheme", "neutralAccentAuto", "neutralAccent", "barOpacity", "highContrast"]
            const saved = keys.map(key => ShellSettings[key])
            ShellSettings.reduceMotion = true
            ShellSettings.neutralTheme = true
            ShellSettings.neutralAccentAuto = false
            ShellSettings.neutralAccent = "#23509a"
            ShellSettings.barOpacity = 0.58
            ShellSettings.highContrast = false
            Notifications.presentationMode = true
            Notifications.missedCount = 2
            const markClock = clockFactory.createObject(root)
            const bell = root._findTrayNode(markClock, item => item.text === "󰂛 " && item.expanded !== undefined)
            const activeCell = workspaceButtonFactory.createObject(barFixtureHost, {
                wsId: 2, monitorReady: true, active: true, occupied: true,
                urgent: false, apps: [], compact: false, iconSize: 14,
                cellWidth: 26, rowHeight: 24, barActive: true,
                initialized: true, paging: false, markerCovers: false
            })
            const activeDot = root._findTrayNode(activeCell, item => item.objectName === "workspace-dot")
            root._check(!Qt.colorEqual(Theme.barAccentMark, Theme.barAccent)
                    && bell !== null && bell.expanded && Qt.colorEqual(bell.color, Theme.barAccentMark)
                    && activeDot !== null && Qt.colorEqual(activeDot.color, Theme.barAccentMark),
                "on a see-through bar the missed-notification bell and the active workspace dot keep the accent a label gives up")
            markClock.destroy()
            activeCell.destroy()
            Notifications.presentationMode = false
            Notifications.missedCount = statusMissedWas
            for (let i = keys.length - 1; i >= 0; i--) ShellSettings[keys[i]] = saved[i]
        }

        const updateBadge = updatesWidgetFactory.createObject(barFixtureHost)
        updateBadge.show = true
        updateBadge.busy = true
        root._check(updateBadge.interactive,
            "package details remain reachable while an update check is running")
        updateBadge.activated()
        root._check(MenuState.settingsActive && MenuState.settingsSection === "updates"
                && MenuState.anchorSource === updateBadge,
            "the system updates badge opens its details anchored to the triggering widget")
        MenuState.close()
        updateBadge.barActive = false
        updateBadge.activated()
        root._check(!MenuState.open,
            "a sleeping update badge rejects a late activation signal")
        updateBadge.destroy()

        {
            // a write through the opacity behaviour would only start a fade
            const reduceWas = ShellSettings.reduceMotion
            ShellSettings.reduceMotion = true
            for (const name of ["SystemWidget", "KeyboardWidget"]) {
                const pill = Qt.createComponent("modules/bar/widgets/" + name + ".qml").createObject(barFixtureHost)
                pill.opacity = 0.5
                const fading = !pill.show && pill.layoutVisible === true
                pill.opacity = 0
                root._check(fading && pill.layoutVisible === false,
                    name + " keeps its bar slot while it fades out, as the other pills do, and gives it up once faded")
                pill.destroy()
            }
            ShellSettings.reduceMotion = reduceWas
        }
        {
            const capsWas = { path: InputState._capsPath, caps: InputState.capsLock }
            InputState._capsPath = "/sys/class/leds/silere-probe::capslock/brightness"
            InputState.capsLock = true
            const keys = Qt.createComponent("modules/bar/widgets/KeyboardWidget.qml").createObject(barFixtureHost)
            root._check(InputState.layout.length > 0
                    || (keys.text === "CAPS" && keys.accessibleName === "Keyboard, Caps Lock on"),
                "a keyboard pill lit only by its Caps Lock light reads and speaks without an empty layout slot")
            keys.destroy()
            InputState._capsPath = capsWas.path
            InputState.capsLock = capsWas.caps
        }
        {
            const vol = Qt.createComponent("modules/bar/widgets/Volume.qml").createObject(barFixtureHost)
            root._check(vol !== null && vol.warnsForOutput(false, 1) && vol.warnsForOutput(true, 2)
                    && !vol.warnsForOutput(true, 1),
                "the volume glyph warns for a dying headset unless a shown Bluetooth pill reads that lone device's charge")
            if (vol) vol.destroy()
        }
    }

    function _checksUnderline(): void {
        const underline = barUnderlineFactory.createObject(root)
        root._check(underline !== null, "the reactive underline builds")
        if (underline) {
            const lineEffect = underline.children.find(child =>
                typeof child._clearNetLossFlash === "function")
            root._check(lineEffect !== undefined,
                "the reactive underline exposes its network flash reset")
            if (lineEffect) {
                const networkFlash = lineEffect.resources.find(r => r.objectName === "networkFlash")
                const networkFade = lineEffect.resources.find(r => r.objectName === "networkFade")
                root._check(networkFlash !== undefined && networkFade !== undefined,
                    "network glow animations can be inspected independently")
                const netGlowWas = ShellSettings.underlineNetGlow
                const netReduceWas = ShellSettings.reduceMotion
                ShellSettings.underlineNetGlow = true
                ShellSettings.reduceMotion = false
                lineEffect._lastNetConnected = true
                lineEffect._updateNetGlow(true, false)
                root._check(networkFlash.running,
                    "the first disconnect after a connected startup flashes immediately")
                lineEffect._stopTransient()
                lineEffect._networkGlow = 0.3
                lineEffect._updateNetGlow(true, true)
                root._check(networkFade.running,
                    "reconnecting fades a visible network glow")
                lineEffect._stopTransient()
                root._check(!networkFlash.running && !networkFade.running
                        && lineEffect._networkGlow === 0,
                    "settling transient glows also stops the reconnect fade")
                lineEffect._updateNetGlow(true, true)
                root._check(!networkFade.running,
                    "an already dark network glow starts no reconnect animation")
                ShellSettings.reduceMotion = true
                lineEffect._networkGlow = 0.3
                lineEffect._updateNetGlow(true, true)
                root._check(lineEffect._networkGlow === 0 && !networkFade.running,
                    "reduced motion settles a reconnect without animating")
                ShellSettings.underlineNetGlow = false
                lineEffect._lastNetConnected = true
                ShellSettings.underlineNetGlow = true
                root._check(lineEffect._lastNetConnected === (Network.available && Network.connected),
                    "re-enabling network feedback seeds the current connection state")
                ShellSettings.underlineNetGlow = netGlowWas
                ShellSettings.reduceMotion = netReduceWas
                networkFlash.spread = 0.19
                networkFlash.bloom = 0.14
                lineEffect._clearNetLossFlash()
                root._check(networkFlash.spread === 0.28
                        && networkFlash.bloom === 0,
                    "a canceled network flash restores its spread and bloom")
                const notificationFlash = lineEffect.resources.find(r => r.objectName === "notificationFlash")
                const notifGlowWas = ShellSettings.underlineNotifGlow
                const screenshotGlowWas = ShellSettings.underlineScreenshotGlow
                ShellSettings.reduceMotion = false
                ShellSettings.underlineNotifGlow = true
                ShellSettings.underlineNetGlow = true
                ShellSettings.underlineScreenshotGlow = true
                const arrivalCount = Notifications.activeCount
                Notifications.notificationShown("Probe", "First arrival", false)
                root._check(notificationFlash.running && !lineEffect._notifCritical
                        && Notifications.activeCount === arrivalCount,
                    "a notification arrival flashes without needing the active popup count to change")
                lineEffect._stopTransient()
                Notifications.notificationShown("Probe", "Critical arrival", true)
                root._check(notificationFlash.running && lineEffect._notifCritical,
                    "the arrival signal supplies the notification's own critical color")
                const criticalWas = CpuTemp.critical
                const tempGlowWas = ShellSettings.underlineTempGlow
                ShellSettings.underlineTempGlow = true
                CpuTemp.critical = true
                underline.quiet = true
                root._check(!notificationFlash.running && !networkFlash.running
                        && lineEffect._tempSteady && lineEffect._tempGlow === 0.5,
                    "quiet idle stops underline motion while retaining a steady critical temperature warning")
                Notifications.notificationShown("Probe", "Quiet arrival", true)
                Screenshot.flashed()
                root._check(!notificationFlash.running && !lineEffect._shotActive
                        && !lineEffect._skipNextNotif && !lineEffect._canRunEventMotion(),
                    "quiet arrivals start no underline flash and leave no screenshot suppression behind")
                underline.quiet = false
                Notifications.notificationShown("Probe", "After quiet", false)
                root._check(notificationFlash.running && !lineEffect._notifCritical,
                    "the first arrival after quiet idle can flash immediately")
                CpuTemp.critical = criticalWas
                ShellSettings.underlineTempGlow = tempGlowWas
                lineEffect._stopTransient()
                lineEffect._playNotification(true)
                notificationFlash.spread = 0.19
                notificationFlash.bloom = 0.14
                lineEffect._lastNetConnected = true
                lineEffect._updateNetGlow(true, false)
                lineEffect._playScreenshot()
                root._check(notificationFlash.running && networkFlash.running
                        && notificationFlash.spread === 0.19 && notificationFlash.bloom === 0.14,
                    "network and screenshot arrivals preserve an active notification envelope")
                root._check(lineEffect._notifCritical
                        && lineEffect._effectColorTarget === Theme.error,
                    "a critical notification keeps its semantic color during a screenshot")
                lineEffect._clearNetLossFlash()
                root._check(notificationFlash.running && lineEffect._sweepSpread === 0.19
                        && lineEffect._bloomBoost >= 0.14,
                    "canceling a network pulse does not reset notification geometry")
                ShellSettings.underlineScreenshotGlow = false
                root._check(notificationFlash.running && notificationFlash.bloom === 0.14,
                    "disabling screenshot feedback preserves the other event envelopes")
                networkFlash.play(0)
                networkFlash.glow = 0.42
                networkFlash.bloom = 0.22
                ShellSettings.underlineNotifGlow = false
                root._check(!notificationFlash.running && networkFlash.running
                        && lineEffect._networkGlow === 0.42 && networkFlash.bloom === 0.22,
                    "disabling notification feedback preserves an active network pulse")
                lineEffect._stopTransient()
                root._check(!notificationFlash.running && !networkFlash.running
                        && notificationFlash.glow === 0 && networkFlash.glow === 0
                        && lineEffect._bloomBoost === 0 && lineEffect._sweepSpread === 0.28,
                    "settling all event envelopes leaves no geometry or glow behind")
                const fullWidthWas = ShellSettings.underlineFullWidth
                const softLayers = underline.children.filter(item => item.modelData !== undefined
                    && item.center !== undefined)
                ShellSettings.reduceMotion = true
                lineEffect._sweepCenter = 0.2
                ShellSettings.underlineFullWidth = true
                root._check(softLayers.length === 6 && softLayers.every(layer => layer.center === 0.5
                        && layer.spread === 0.46 && layer.edge === lineEffect._renderEdge),
                    "full-width underline feedback spreads every soft layer across the bar")
                ShellSettings.underlineFullWidth = false
                root._check(softLayers.every(layer => layer.center === 0.2),
                    "localized underline feedback keeps its event position when full width is turned off")
                ShellSettings.underlineFullWidth = fullWidthWas
                ShellSettings.underlineNotifGlow = notifGlowWas
                ShellSettings.underlineNetGlow = netGlowWas
                ShellSettings.underlineScreenshotGlow = screenshotGlowWas
                ShellSettings.reduceMotion = true
                lineEffect._effectColor = Qt.rgba(0.25, 0.5, 0.75, 1)
                root._check(Math.abs(lineEffect._stopColor.r - lineEffect._effectColor.r) < 0.002
                        && Math.abs(lineEffect._stopColorMid.b - lineEffect._effectColor.b) < 0.002
                        && Math.abs(lineEffect._stopColor.a - 0.9) < 0.002
                        && Math.abs(lineEffect._stopColorMid.a - 0.45) < 0.002,
                    "every underline stop derives its RGB from the same eased effect color")
                ShellSettings.reduceMotion = netReduceWas
            }
        }
        underline.destroy()
    }

    function _checksVisualizerAndRim(): void {
        const visualizer = mediaVisualizerFactory.createObject(root, { width: 200, height: 20 })
        const band = visualizer.textBand(40, 12, 28)
        visualizer._fillH = 40
        visualizer.textTop = 12
        root._check(band && band.top === 0.3 && band.bottom === 0.7 && visualizer.textBand(40, -1, -1) === null
                && visualizer.textBand(40, 30, 20) === null && visualizer.textBand(40, 0, 40).top === 0.05
                && visualizer.textBand(40, 0, 40).bottom === 0.97 && visualizer._fillH === -1,
            "the media wave goes quiet across the title's own band, kept inside the gradient, and repaints when it moves")
        visualizer.textTop = -1
        const edgeGradients = []
        const edgeContext = {
            createLinearGradient: function(x0, y0, x1, y1) {
                const gradient = { start: x0, end: x1, addColorStop: function() {} }
                edgeGradients.push(gradient)
                return gradient
            },
            fillRect: function() {}
        }
        visualizer._fadeEdges(edgeContext)
        visualizer._fadeEdges(edgeContext)
        root._check(edgeGradients.length === 2,
            "the audio visualizer reuses unchanged edge-fade gradients")
        visualizer.edgeFadeMax = 30
        visualizer._fadeEdges(edgeContext)
        root._check(edgeGradients.length === 4 && edgeGradients[2].end === 30
                && edgeGradients[3].start === 170,
            "changing the audio fade width invalidates both cached gradients")
        visualizer.width = 200.25
        visualizer._fadeEdges(edgeContext)
        root._check(edgeGradients.length === 6 && edgeGradients[5].end === 200.25,
            "a fractional visualizer resize cannot reuse gradients from the old bounds")
        root._check(edgeContext.globalCompositeOperation === "source-over",
            "audio edge fading restores the normal compositing mode")
        visualizer.width = 200
        visualizer.followRim = true
        visualizer.rimRadius = 16
        visualizer.rimInset = 3
        visualizer._fadeEdges(edgeContext)
        root._check(edgeGradients.length === 8 && edgeGradients[6].start === 3 && edgeGradients[6].end === 15
                && edgeGradients[7].start === 185 && edgeGradients[7].end === 197,
            "a rim spectrum fades over its corner arcs, measured from the surface edge, not the canvas")
        root._check(visualizer._taper(10, 10, 190) === 0 && visualizer._taper(190, 10, 190) === 0
                && visualizer._taper(100, 10, 190) === 1,
            "the rim spectrum rests on the edge where the straight run meets each arc")
        visualizer.rimRadius = 400
        root._check(visualizer._rimR() === 97, "a rim radius never exceeds half the surface")
        visualizer.destroy()

        const glowComponent = Qt.createComponent("modules/bar/GlowLine.qml")
        root._check(glowComponent.status === Component.Ready, "the glow gradient builds")
        const glowLine = glowComponent.createObject(root, {
            width: 200, peak: Qt.rgba(0.8, 0.6, 0.2, 0.9), edge: Qt.rgba(0.2, 0.4, 0.8, 0.45)
        })
        for (const bounds of [[0.02, 0.98], [-0.5, 1.5], [0.8, 0.2], [1, 1], [-1, -1]]) {
            glowLine.loClamp = bounds[0]
            glowLine.hiClamp = bounds[1]
            for (const center of [-1, 0, 0.01, 0.5, 0.99, 1, 2]) {
                glowLine.center = center
                for (const spread of [-1, 0, 0.02, 0.28, 1, 2]) {
                    glowLine.spread = spread
                    const stops = glowLine.gradient.stops
                    let ordered = true, previous = 0
                    for (let i = 0; i < stops.length; i++) {
                        const position = stops[i].position
                        if (!isFinite(position) || position < previous || position > 1) ordered = false
                        previous = position
                    }
                    root._check(ordered,
                        "glow stops stay ordered and bounded for " + bounds + "/" + center + "/" + spread)
                }
            }
        }
        root._check(glowLine._shoulderLow.a > glowLine.edge.a
                && glowLine._shoulderHigh.a < glowLine.peak.a
                && glowLine._edgeLow.a < glowLine._edgeHigh.a
                && glowLine._edgeHigh.a < glowLine.edge.a,
            "smooth glow shoulders preserve the translucent color hierarchy")
        glowLine.loClamp = 0.02
        glowLine.hiClamp = 0.98
        glowLine.center = 0.5
        glowLine.spread = 0.28
        const smoothStops = glowLine.gradient.stops
        let smoothEnergy = 0
        for (let i = 1; i < smoothStops.length; i++) {
            smoothEnergy += (smoothStops[i].position - smoothStops[i - 1].position)
                * (smoothStops[i].color.a + smoothStops[i - 1].color.a) / 2
        }
        const linearEnergy = glowLine.edge.a * (glowLine._l + 1 - glowLine._r) / 2
            + (glowLine.edge.a + glowLine.peak.a) * (glowLine._r - glowLine._l) / 2
        root._check(Math.abs(smoothEnergy - linearEnergy) < 0.002,
            "smoothing a glow preserves its integrated opacity instead of making it brighter")
        const halfGlow = glowLine._mixColor(glowLine.edge, glowLine.peak, 0.5)
        root._check(Math.abs(halfGlow.a - 0.675) < 0.002
                && Math.abs(halfGlow.r - 0.5) < 0.002,
            "glow color interpolation preserves alpha together with RGB")
        glowLine.peak = "transparent"
        glowLine.edge = "transparent"
        root._check(!glowLine.visible, "a fully transparent glow gradient does not render")
        glowLine.destroy()

        for (const dpr of [1, 1.25, 1.5, 1.75, 2, 2.5]) {
            for (const width of [1, 1.5, 2]) {
                const stroke = PixelGeometry.stroke(width, dpr)
                const inset = PixelGeometry.inset(1, stroke, dpr)
                root._check(Math.abs(stroke * dpr - Math.round(stroke * dpr)) < 1e-6
                        && Math.abs((inset - stroke / 2) * dpr
                            - Math.round((inset - stroke / 2) * dpr)) < 1e-6,
                    "outline and countdown edges share the device pixel grid at " + dpr + "x")
            }
        }
        root._check(PixelGeometry.stroke(1, 1.5) === 1 / 1.5
                && PixelGeometry.stroke(0, 1.25) === 0,
            "thin strokes round half pixels down and zero width stays disabled")
        const fadingRim = fadingRimFactory.createObject(root, {
            width: 100, height: 40, radius: 50, band: 1.25, rimColor: "white"
        })
        root._check(fadingRim._band === 1 && fadingRim._radius === 20,
            "a floating glow rim snaps its band and clamps oversized corners")
        fadingRim.band = 0
        root._check(!fadingRim.visible, "a zero-width glow rim is not drawn")
        fadingRim.band = 100
        root._check(fadingRim._band === 20,
            "an oversized glow band cannot invert its inner rectangle")
        fadingRim.destroy()
    }

    function _checksCountdownsAndClockSteps(): void {
        const notificationCard = notificationCardFactory.createObject(root)
        const clock = Qt.createQmlObject("import QtQuick; QtObject { signal tick() }", root)
        const ownWas = notificationCard._ownCountdown.running
        notificationCard.countdownClock = clock
        const ownWithClock = notificationCard._ownCountdown.running
        notificationCard._timeoutProgress = 0.123
        clock.tick()
        root._check(ownWas && !ownWithClock && notificationCard._timeoutProgress !== 0.123,
            "a card in a stack follows the shared countdown tick instead of a timer of its own")
        notificationCard.countdownClock = null
        clock.destroy()
        const rim = perimeterFactory.createObject(root, {
            arcWidth: notificationCard._borderWidth, inset: notificationCard._borderWidth / 2,
            cornerRadius: 15, progress: 0.5
        })
        root._check(Math.abs(rim._arcInset - rim._arcStroke / 2) < 0.001
                && rim._pathWidth === rim.width - rim._arcStroke,
            "the countdown follows the same inset and width as the notification outline")
        rim.width = 320; rim.height = 90
        rim._shownProgress = 0.4
        const arc = rim.data[1]
        const mid = ((arc.trim.offset + arc.trim.end / 2) % 1 + 1) % 1
        root._check(Math.abs(arc.trim.end - 0.4) < 1e-6 && Math.abs(mid - rim._topCentre) < 1e-6,
            "the countdown arc stays centred on the top edge as it shrinks")
        rim._shownProgress = 1
        root._check(arc.trim.end === 1 && arc.trim.offset === 0,
            "a full countdown ring is drawn untrimmed, so its translucent caps never overlap")
        rim.destroy()
        notificationCard._updateTime()
        root._check(notificationCard._timeUpdateMs > 30000 && notificationCard._timeUpdateMs <= 60000,
            "a new notification schedules its age label for the next minute boundary")
        root._check(notificationCard !== null, "a notification card builds")
        root._check(notificationCard.actionColumns(400, 80, 4) === 4
                && notificationCard.actionColumns(232, 90, 4) === 2
                && notificationCard.actionColumns(160, 120, 3) === 1
                && notificationCard.actionColumns(0, 120, 4) === 1
                && notificationCard.actionColumns(400, 90, 0) === 1,
            "notification actions use only as many columns as their labels and card width allow")
        root._check(notificationCard.actionColumns(330, 90, 4) === 2
                && notificationCard.actionsInRow(0, 3, 2) === 2
                && notificationCard.actionsInRow(2, 3, 2) === 1
                && notificationCard.actionsInRow(3, 4, 2) === 2
                && notificationCard.actionsInRow(0, 1, 1) === 1,
            "wrapped notification actions balance their rows and stretch a short last row")
        root._sentInlineReply = ""
        root._check(notificationCard.hasInlineReply
                && notificationCard._sendInlineReply("  hello  ")
                && root._sentInlineReply === "hello",
            "an inline notification reply is trimmed and sent through its live object")
        root._sentInlineReply = ""
        root._check(!notificationCard._sendInlineReply("   ")
                && root._sentInlineReply.length === 0,
            "an empty inline notification reply is not sent")
        const upperAction = { identifier: "Default", text: "Capitalized action", invoke: function() {} }
        const exactAction = { identifier: "default", text: "Open", invoke: function() {} }
        const actionCard = notificationCardFactory.createObject(root, {
            notification: Object.assign({}, notificationCard.notification, {
                actions: [upperAction, exactAction], expireTimeout: 0, resident: true
            })
        })
        root._check(actionCard._defaultAction.identifier === "default"
                && actionCard.actionList.length === 1
                && actionCard.actionList[0].identifier === "Default",
            "only the exact default action key is reserved for clicking the notification")
        actionCard.notification = Object.assign({}, actionCard.notification, { actions: [upperAction] })
        root._check(actionCard._defaultAction === null && actionCard.actionList.length === 1,
            "a capitalized action key remains a visible button without becoming the primary action")
        actionCard.destroy()

        root._check(notificationCard.swipeOffset(120, 1) === 120
                && notificationCard.swipeOffset(-120, -1) === -120
                && notificationCard.swipeOffset(-400, 1) < 0
                && notificationCard.swipeOffset(-400, 1) > -16
                && Math.abs(notificationCard.swipeOffset(400, 0)) < 16
                && notificationCard.swipeOffset(0, 1) === 0,
            "a swiped notification follows the pointer freely only toward its own screen edge")
        root._check(notificationCard.swipeDismisses(140, 0, 400)
                && notificationCard.swipeDismisses(-140, 0, 400)
                && !notificationCard.swipeDismisses(120, 0, 400)
                && notificationCard.swipeDismisses(40, 1.2, 400)
                && !notificationCard.swipeDismisses(40, -1.2, 400)
                && !notificationCard.swipeDismisses(12, 2, 400),
            "a swiped notification lets go past a third of its width or on a fling the same way")
        const swipeMotionWas = ShellSettings.reduceMotion
        ShellSettings.reduceMotion = true
        const swipeCard = notificationCardFactory.createObject(root, {
            width: 300, slideDir: 1,
            notification: Object.assign({}, notificationCard.notification, { expireTimeout: 0 })
        })
        let swipeDismissals = 0
        swipeCard.dismissRequested.connect((id, note, expired) => { if (!expired) swipeDismissals++ })
        swipeCard._beginSwipe(0)
        swipeCard._moveSwipe(60)
        swipeCard._endSwipe(false)
        root._check(swipeCard.enabled && !swipeCard._swiping && swipeDismissals === 0,
            "a cancelled swipe returns the notification to the stack")
        swipeCard._beginSwipe(0)
        swipeCard._moveSwipe(-200)
        swipeCard._swipeStamp = 0
        swipeCard._endSwipe(true)
        root._check(!swipeCard.enabled && !swipeCard._swiping && swipeDismissals === 1,
            "a notification swiped past a third of its width is dismissed, not expired")
        swipeCard.destroy()
        ShellSettings.reduceMotion = swipeMotionWas

        const idleMotionWas = ShellSettings.reduceMotion
        ShellSettings.reduceMotion = true
        const idleTemplate = Object.assign({}, notificationCard.notification, { expireTimeout: 0 })
        const persistentIdleCard = notificationCardFactory.createObject(root, { notification: idleTemplate })
        const criticalIdleCard = notificationCardFactory.createObject(root, {
            notification: Object.assign({}, idleTemplate, { urgency: 2, expireTimeout: -1 })
        })
        const ordinaryIdleCard = notificationCardFactory.createObject(root, {
            notification: Object.assign({}, idleTemplate, { expireTimeout: 5000 })
        })
        const timedCriticalIdleCard = notificationCardFactory.createObject(root, {
            notification: Object.assign({}, idleTemplate, { urgency: 2, expireTimeout: 5000 })
        })
        let persistentIdleDismissals = 0
        let timedIdleDismissals = 0
        persistentIdleCard.dismissRequested.connect(() => { persistentIdleDismissals++ })
        criticalIdleCard.dismissRequested.connect(() => { persistentIdleDismissals++ })
        ordinaryIdleCard.dismissRequested.connect((id, note, expired) => { if (expired) timedIdleDismissals++ })
        timedCriticalIdleCard.dismissRequested.connect((id, note, expired) => { if (expired) timedIdleDismissals++ })
        persistentIdleCard.beginReply()
        criticalIdleCard.beginReply()
        for (const item of [persistentIdleCard, criticalIdleCard, ordinaryIdleCard, timedCriticalIdleCard])
            item._handleIdle(true)
        root._check(persistentIdleCard.enabled && criticalIdleCard.enabled && persistentIdleDismissals === 0,
            "entering idle preserves zero-timeout and default-critical notifications")
        root._check(!persistentIdleCard._replyOpen && !criticalIdleCard._replyOpen,
            "persistent notifications release an abandoned reply when the session goes idle")
        root._check(!ordinaryIdleCard.enabled && !timedCriticalIdleCard.enabled && timedIdleDismissals === 2,
            "idle still expires ordinary notifications and critical alerts with an explicit timeout")
        persistentIdleCard._handleIdle(false)
        criticalIdleCard._handleIdle(false)
        root._check(persistentIdleCard.enabled && criticalIdleCard.enabled,
            "persistent notifications remain available when the session wakes")
        for (const item of [persistentIdleCard, criticalIdleCard, ordinaryIdleCard, timedCriticalIdleCard])
            item.destroy()
        ShellSettings.reduceMotion = idleMotionWas
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
        const stepNow = Date.now()
        const steppedAhead = stepNow + 3 * 3600 * 1000
        root._check(OsdBarState._due(stepNow, stepNow) && !OsdBarState._due(stepNow + 500, stepNow)
                && OsdBarState._due(steppedAhead, stepNow),
            "an OSD deadline set before the wall clock stepped back is due rather than hours away")
        const steppedCard = notificationCardFactory.createObject(root, {
            notification: Object.assign({}, idleTemplate, { expireTimeout: 5000 })
        })
        steppedCard.timeoutStartedAt = steppedAhead
        const steppedTimer = root._notificationExpiryTimer(steppedCard)
        root._check(steppedTimer !== null && steppedTimer.interval <= 5000,
            "a notification stamped before the wall clock stepped back keeps its own timeout")
        steppedCard.destroy()
    }

    function _checksSurfaceGatingAndDropdowns(): void {
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
        const pickerHost = Qt.createQmlObject("import QtQuick; Item {}", barFixtureHost)
        const visibilitySelect = selectRowFactory.createObject(pickerHost)
        visibilitySelect._setOpen(true)
        root._check(visibilitySelect._open && MenuState._settingsSelectOwner === visibilitySelect,
            "a visible dropdown claims the shared settings-picker state")
        visibilitySelect.visible = false
        root._check(!visibilitySelect._open && MenuState._settingsSelectOwner === null
                && !visibilitySelect.Accessible.focusable,
            "hiding a dropdown folds it and releases its settings-picker state")
        visibilitySelect.Accessible.pressAction()
        visibilitySelect._setOpen(true)
        root._check(!visibilitySelect._open && MenuState._settingsSelectOwner === null,
            "a hidden dropdown rejects both accessible and direct open requests")
        visibilitySelect.visible = true
        visibilitySelect._setOpen(true)
        pickerHost.visible = false
        root._check(!visibilitySelect._open && MenuState._settingsSelectOwner === null,
            "hiding a dropdown's parent also releases its open-picker ownership")
        pickerHost.visible = true
        visibilitySelect.Accessible.pressAction()
        root._check(visibilitySelect._open && visibilitySelect.Accessible.focusable
                && MenuState._settingsSelectOwner === visibilitySelect,
            "a restored dropdown can open and claim ownership again")
        visibilitySelect._setOpen(false)
        pickerHost.destroy()
        if (firstSelect) firstSelect.destroy()
        if (secondSelect) secondSelect.destroy()

        // a page that failed to load offers a reload: the menu closes first, then comes back where it was
        const reloadWas = { open: MenuState.open, tab: MenuState.activeTab, section: MenuState.settingsSection }
        MenuState.setSettingsSection("popups")
        MenuState.showTab(MenuState.settingsTab)
        MenuState.reloadShell()
        const reloadClosed = !MenuState.open && MenuState.reloadPending
        // nothing may really reload the probe: with nothing pending, the shell's unload call and the fallback stand aside
        MenuState.reloadPending = false
        MenuState.setSettingsSection("theme")
        MenuState._returnAfterReload()
        const reloadReturned = MenuState.open && MenuState.activeTab === MenuState.settingsTab
            && MenuState.settingsSection === "popups"
        MenuState.close()
        MenuState._returnAfterReload()
        const reloadReturnedOnce = !MenuState.open
        MenuState.reloadNow()
        root._check(reloadClosed && reloadReturned && reloadReturnedOnce,
            "reloading from a failed page closes the menu, then reopens it once on the same tab and page")
        MenuState.selectTab(reloadWas.tab)
        MenuState.setSettingsSection(reloadWas.section)
        if (reloadWas.open) MenuState.openUnanchored()
        else MenuState.close()
    }

    function _checksConfirmButtonsAndCpuSensors(): void {
        const confirmButton = confirmButtonFactory.createObject(root)
        root._confirmActions = 0
        confirmButton.request()
        root._check(confirmButton.armed && root._confirmActions === 0,
            "a confirmation button arms before running its action")
        confirmButton.request()
        root._check(confirmButton.armed && root._confirmActions === 0,
            "a double-click cannot confirm a destructive action")
        confirmButton._armedAtMs = Date.now() - 3001
        confirmButton.request()
        root._check(confirmButton.armed && root._confirmActions === 0
                && Date.now() - confirmButton._armedAtMs < Metrics.confirmGuardMs,
            "an expired confirmation rearms when its cleanup timer has not fired yet")
        confirmButton._armedAtMs = Date.now() + 1000
        confirmButton.request()
        root._check(confirmButton.armed && root._confirmActions === 0
                && confirmButton._armedAtMs <= Date.now(),
            "a backwards clock change restarts the confirmation window")
        confirmButton._armedAtMs = Date.now() - Metrics.confirmGuardMs - 1
        confirmButton.request()
        root._check(!confirmButton.armed && root._confirmActions === 1,
            "a deliberate second request confirms exactly once")
        confirmButton.request()
        confirmButton._armLeft = 0.2
        confirmButton.disarm()
        confirmButton.request()
        root._check(confirmButton.armed && confirmButton._armLeft === 1 && root._confirmActions === 1,
            "rearming starts the confirmation window full again")
        confirmButton._armLeft = 0.4
        const confirmArc = root._findTrayNode(confirmButton, item => item.arcColor !== undefined)
        root._check(confirmArc !== null && confirmArc.progress === 0.4
                && confirmArc.cornerRadius === confirmButton.radius,
            "an armed confirm button runs its window out around its outline")
        confirmButton.disarm()
        root._check(root._findTrayNode(confirmButton, item => item.arcColor !== undefined) === null,
            "a confirm button at rest draws no countdown")
        confirmButton.needsConfirm = false
        confirmButton.request()
        root._check(!confirmButton.armed && root._confirmActions === 2,
            "a button for an action nothing is lost to fires on the first request")
        confirmButton.needsConfirm = true
        root._confirmActions = 1
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
    }

    function _checksWorkspaceHandoffAndSettingsFile(): void {
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
        let menuRequests = 0
        crossingCell.anchorMenuRequested.connect(() => menuRequests++)
        crossingCell.active = true
        crossingCell.Accessible.pressAction()
        root._check(menuRequests === 0,
            "a sleeping workspace cell rejects its accessible menu action")
        crossingCell.barActive = true
        crossingCell.wsId = -1
        crossingCell.Accessible.pressAction()
        root._check(menuRequests === 0,
            "a fading empty workspace slot cannot open a menu")
        crossingCell.wsId = 2
        crossingCell.Accessible.pressAction()
        root._check(menuRequests === 1,
            "a restored workspace cell accepts its menu action again")
        const urgentTick = workspaceUrgentTickFactory.createObject(barFixtureHost, {
            liveId: 7, rowHeight: 24, barActive: true
        })
        let urgentJumps = 0
        urgentTick.jumpRequested.connect(() => urgentJumps++)
        urgentTick.Accessible.pressAction()
        root._check(urgentJumps === 1 && urgentTick.Accessible.focusable,
            "an awake urgent-workspace indicator accepts its jump action")
        urgentTick.barActive = false
        urgentTick.Accessible.pressAction()
        root._check(urgentJumps === 1 && !urgentTick.Accessible.focusable,
            "a concealed urgent-workspace indicator rejects activation")
        urgentTick.barActive = true
        urgentTick.enabled = false
        urgentTick._jump()
        root._check(urgentJumps === 1, "a disabled urgent-workspace indicator cannot switch workspaces")
        urgentTick.enabled = true
        urgentTick.liveId = 0
        urgentTick._jump()
        root._check(urgentJumps === 1, "a fading urgent-workspace indicator cannot jump to its stale target")
        urgentTick.destroy()
        const sideTick = workspaceUrgentTickFactory.createObject(barFixtureHost, {
            liveId: 9, rowHeight: 24, barActive: true, before: false
        })
        const sideLabel = () => root._findTrayNode(sideTick, item => item.text !== undefined)?.text ?? ""
        sideTick.before = true
        sideTick.liveId = 0
        discoveryClock.wait(1)
        const fadingSide = sideLabel()
        sideTick.liveId = 2
        discoveryClock.wait(1)
        root._check(fadingSide === "› 9" && sideLabel() === "‹ 2",
            "a fading urgent-workspace arrow keeps its side while the strip clears it, and the next one takes its own")
        sideTick.destroy()
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
        root._checkCoerce("uiScale", 9e99, 1.5, "an over-range real clamps to its maximum")
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
        const everyStep = Array.from({ length: ShellSettings._settingsVersion }, (_, i) => i + 1).join(",")
        root._check(migratedV1.version === ShellSettings._settingsVersion
                && migratedV1.applied.join(",") === everyStep
                && migratedV1.value.__version === ShellSettings._settingsVersion,
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
            migrationGapValue = SettingsMigrations.migrate({ barHeight: 40 }, 0, 99)
        } catch (e) {
            migrationGapThrew = true
        }
        root._check(migrationGapThrew && migrationGapValue === null,
            "a missing migration step throws instead of returning a half-migrated value")
        const migrationRollback = SettingsMigrations.migrate({ uiScale: 1.5, notifMutedApps: "Slack" }, 1, 2)
        root._check(migrationRollback.version === 2 && migrationRollback.value.uiScale === 1.5
                && migrationRollback.value.notifMutedApps === "Slack",
            "the 1.5 schema step only marks the file, so a rollback to 1.4 keeps what it cannot read")
        const migrationSince16 = SettingsMigrations.migrate({ clockShowWeather: true,
            overlayMonitorIdentity: "AUO|0x1637|0x00006000", barMonitorIdentities: { "eDP-2": "AUO|0x1637|0x00006000" } },
            2, ShellSettings._settingsVersion)
        root._check(ShellSettings._settingsVersion >= 3 && migrationSince16.version === ShellSettings._settingsVersion
                && migrationSince16.value.clockShowWeather === true
                && migrationSince16.value.overlayMonitorIdentity === "AUO|0x1637|0x00006000"
                && migrationSince16.value.barMonitorIdentities["eDP-2"] === "AUO|0x1637|0x00006000",
            "the schema moved past 1.6's, so a rollback to 1.6 keeps the settings added since")
        const migrationSince17 = SettingsMigrations.migrate({ mediaPauseOnDisconnect: false }, 3, ShellSettings._settingsVersion)
        root._check(ShellSettings._settingsVersion >= 4 && migrationSince17.version === ShellSettings._settingsVersion
                && migrationSince17.value.mediaPauseOnDisconnect === false,
            "the schema moved past 1.7's, so a rollback to 1.7 keeps the headphone pause setting")
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
        root._check(Object.keys(clean).length === 1 && clean.__version === ShellSettings._settingsVersion,
            "an unmodified settings file serializes to nothing but its version")

        // the sec: on every schema entry exists only to light the nav dots, and ci-lint
        // guards the attribution but not the reader; an unrelated refactor deleted the
        // reader once and nothing failed, so pin the mapping here.
        // per-key tracking gates on a completed load, which this offscreen probe never gets
        root._check(Object.keys(ShellSettings.modifiedSections).length === 0,
            "an unmodified settings file marks no settings page")
    }

    function _checksSettingsMarksAndVisualizerProfiles(): void {
        const savedLoaded = ShellSettings._loaded
        ShellSettings._loaded = true

        const savedTone = ShellSettings.baseTone
        ShellSettings.baseTone = savedTone === "black" ? "graphite" : "black"
        root._check(ShellSettings.modifiedSections.theme === true,
            "a changed setting marks the page that owns it")
        ShellSettings.baseTone = savedTone
        root._check(ShellSettings.modifiedSections.theme === undefined,
            "restoring a setting clears its page")

        const lockBeforeAttribution = ShellSettings.lockProvider
        ShellSettings.lockProvider = "custom"
        root._check(ShellSettings.modifiedSections.devices === true
                && ShellSettings.modifiedSections.interface === undefined
                && ShellSettings.modifiedSections.maintenance === undefined,
            "program preferences mark Devices rather than Interface or Diagnostics")
        ShellSettings.lockProvider = lockBeforeAttribution

        const savedBattGlow = ShellSettings.underlineBattGlow
        const savedGlow = ShellSettings.underlineGlow
        const savedBorder = ShellSettings.barBorderVisible
        ShellSettings.underlineGlow = true
        ShellSettings.underlineBattGlow = !savedBattGlow
        root._check(ShellSettings.modifiedSections.underline === true
                && ShellSettings.modifiedSections.warnings === true,
            "a setting owned by two pages marks both")
        // the event rows collapse behind the glow master, and Alerts offers no Glow choice without it,
        // so a changed value behind that gate would dot a page with nothing on it to clear
        ShellSettings.underlineGlow = savedGlow
        root._check(ShellSettings.modifiedSections.warnings === undefined
                && ShellSettings.modifiedSections.underline === undefined,
            "a value hidden behind the glow master stops dotting both pages that fold it")
        ShellSettings.underlineGlow = true
        ShellSettings.underlineBattGlow = savedBattGlow
        root._check(ShellSettings.modifiedSections.warnings === undefined,
            "clearing the shared setting clears the page that still showed it")
        ShellSettings.underlineGlow = savedGlow

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
                && ShellSettings._dotHidden("popups", "notifCriticalBypass") === false,
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
        const savedRadius = ShellSettings.barRadius
        ShellSettings.barRadius = 0
        const docked = [Theme.radiusCard, Theme.radiusControl, Theme.radiusInline, Theme.radiusField].join()
        ShellSettings.barFloating = true
        const flat = [Theme.radiusCard, Theme.radiusInline, Theme.radiusField].join()
        ShellSettings.barRadius = 21
        root._check(docked === "12,10,8,6" && flat === "0,0,0"
                && Theme.radiusCard === 18 && Theme.radiusField === 9,
            "inner corners follow a floating bar's roundness and keep the stock steps when docked")
        ShellSettings.barRadius = savedRadius
        ShellSettings.barFloating = savedFloating
        ShellSettings.dotStyle = savedDots

        const savedNeutral = ShellSettings.neutralTheme
        ShellSettings.neutralTheme = true
        const neutralBase = ShellSettings._dotHidden("theme", "matugenDepth") && !ShellSettings._dotHidden("theme", "baseTone")
        ShellSettings.neutralTheme = false
        root._check(neutralBase && ShellSettings._dotHidden("theme", "baseTone")
                && !ShellSettings._dotHidden("theme", "matugenDepth"),
            "the Base row of the other source stays out of the Theme page's dot and Reset")
        ShellSettings.neutralTheme = savedNeutral
        const savedBarOpacity = ShellSettings.barOpacity
        ShellSettings.barOpacity = 1
        const opaqueHides = ShellSettings._dotHidden("theme", "surfaceBlur")
        ShellSettings.barOpacity = 0.9
        root._check(opaqueHides && !ShellSettings._dotHidden("theme", "surfaceBlur"),
            "an opaque bar keeps the folded blur rows out of the Theme page's dot and Reset")
        ShellSettings.barOpacity = savedBarOpacity

        const savedAccentAuto = ShellSettings.neutralAccentAuto
        ShellSettings.neutralTheme = true
        ShellSettings.neutralAccentAuto = false
        const pickedHides = ShellSettings._dotHidden("theme", "matugenAccentBalance")
        ShellSettings.neutralAccentAuto = true
        const autoShows = !ShellSettings._dotHidden("theme", "matugenAccentBalance")
        ShellSettings.neutralTheme = false
        ShellSettings.neutralAccentAuto = false
        root._check(pickedHides && autoShows && !ShellSettings._dotHidden("theme", "matugenAccentBalance"),
            "Balance accent counts on the Theme page only where the page shows it: wallpaper or auto accent")
        ShellSettings.neutralTheme = savedNeutral
        ShellSettings.neutralAccentAuto = savedAccentAuto

        const savedBattWarn = ShellSettings.osdBatteryWarn, savedTempWarn = ShellSettings.osdTempWarn
        ShellSettings.osdBatteryWarn = false
        ShellSettings.osdTempWarn = false
        const bothOffHides = ShellSettings._dotHidden("warnings", "sysAlertTimeout")
        ShellSettings.osdTempWarn = true
        root._check(bothOffHides && !ShellSettings._dotHidden("warnings", "sysAlertTimeout")
                && ShellSettings._dotHidden("warnings", "osdChargedNotify") === !ShellSettings.osdEnabled,
            "Dismiss after leaves the Alerts page's dot and Reset while both desktop alerts are off, and only then")
        ShellSettings.osdBatteryWarn = savedBattWarn
        ShellSettings.osdTempWarn = savedTempWarn

        const opaqueA = Qt.rgba(0.1, 0.2, 0.3, 1), opaqueB = Qt.rgba(0.9, 0.5, 0.1, 1)
        const mixed = Theme.mix(opaqueA, opaqueB, 0.3), blended = Theme.blend(opaqueA, opaqueB, 0.3)
        const tinted = Theme.blend(Qt.rgba(1, 1, 1, 0.04), opaqueB, 0.25)
        root._check(Math.abs(mixed.r - blended.r) < 0.002 && Math.abs(mixed.g - blended.g) < 0.002
                && blended.a === 1 && tinted.a < 0.3 && tinted.r > 0.9,
            "blend matches mix for opaque colours and keeps a tint over glass a tint")
        const savedGlass = [ShellSettings.popupMatchBarOpacity, ShellSettings.barOpacity, ShellSettings.surfaceBlur]
        const reduceGlassWas = ShellSettings.reduceMotion
        ShellSettings.reduceMotion = false
        ShellSettings.barOpacity = 0.62
        ShellSettings.surfaceBlur = false
        ShellSettings.popupMatchBarOpacity = true
        // a string, not the colour: a value-type read stays tied to the property and would follow it
        const solidFill = String(glassFadeProbe.color)
        ShellSettings.surfaceBlur = true
        // a fade between an opaque slab and a see-through tint passes through a half-opaque grey
        root._check(Theme.glass && Qt.colorEqual(glassFadeProbe.color, Theme.menuControl)
                && !Qt.colorEqual(solidFill, Theme.menuControl),
            "turning blur on switches faded control fills to glass at once instead of fading through a light grey")
        root._check(Qt.colorEqual(slowFadeProbe.color, Theme.menuControl) && slowFade.duration === Motion.medium,
            "a colour fade given its own pace still stands down for a palette shift")
        ShellSettings.reduceMotion = reduceGlassWas
        // a machine whose compositor blocks blur never frosts, so only the solid half applies there
        const glassOn = Compositor.blurBlocker.length > 0 || Theme.glass
            && Theme.menuCard.a < 0.2 && Theme.menuPane.a < 0.2
            && Theme.menuControl.a < 0.2 && Theme.menuCardSolid.a === 1
            && Theme.controlKnobFill(Theme.accent, false, false, false).a < 0.5
            && Theme.controlKnobFill(Theme.accent, true, false, false).a === 1
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
            "a translucent bar with matching popups turns the menu and off switch knobs to tints, on knobs and hover labels stay solid, and an opaque bar keeps it solid")
        const floorWas = [ShellSettings.popupMatchBarOpacity, ShellSettings.barOpacity, ShellSettings.surfaceBlur]
        ShellSettings.popupMatchBarOpacity = true
        ShellSettings.surfaceBlur = true
        ShellSettings.barOpacity = 0.4
        const heldAt = Theme.popupOpacity
        const heldWorst = Theme._controlOverWorst(Theme._tBackground, Theme._tText, heldAt)
        const labelHolds = Theme.contrastRatio(Theme._tText, heldWorst) >= 4.5
        const subtextLifted = Theme.contrastRatio(Theme._tSubtext, heldWorst) >= 2.99
            && !Qt.colorEqual(Theme._tSubtext, Theme._tSubtextSolid)
        const detailBelowLabel = Theme.contrastRatio(Theme._tMenuTextDetail, heldWorst)
            < Theme.contrastRatio(Theme._tText, heldWorst)
        ShellSettings.barOpacity = 0.95
        const followsAbove = Math.abs(Theme.popupOpacity - 0.95) < 0.001
            && Qt.colorEqual(Theme._tSubtext, Theme._tSubtextSolid)
        ShellSettings.popupMatchBarOpacity = false
        const opaqueUntouched = Theme.popupOpacity === 1 && Qt.colorEqual(Theme._tSubtext, Theme._tSubtextSolid)
        ShellSettings.popupMatchBarOpacity = floorWas[0]
        ShellSettings.barOpacity = floorWas[1]
        ShellSettings.surfaceBlur = floorWas[2]
        root._check(heldAt === Theme.glassFloor && heldAt > 0.5 && heldAt < 0.8 && labelHolds
                && subtextLifted && detailBelowLabel && followsAbove && opaqueUntouched,
            "popups under a very translucent bar hold at the floor where labels read over white, secondary text lifts only there, and detail stays below labels")
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
        // a file-watch reload from an earlier write can still be in flight under load, and unsaved text waits for it
        root._check(ShellSettings._persistence.writeAllowed && !ShellSettings._persistence.writePaused
                && (ShellSettings._persistence._reloading || ShellSettings.flushForUpdate()),
            "restoring the exact previous settings file re-enables saving")
        const settingsStore = ShellSettings._persistence
        root._check(settingsStore !== undefined, "the settings store is available for persistence barrier checks")
        if (settingsStore) {
            const pausedWas = settingsStore.writePaused
            const reloadingWas = settingsStore._reloading
            settingsStore.writePaused = true
            root._check(!ShellSettings.flushForUpdate(),
                "a pending migration backup cannot report settings safely saved for an update")
            settingsStore.writePaused = false
            settingsStore._reloading = true
            const savedWas = settingsStore.lastSavedText
            settingsStore.lastSavedText = ""
            root._check(!ShellSettings.flushForUpdate(),
                "unsaved settings wait for an unresolved settings reload before an update")
            settingsStore.lastSavedText = settingsStore.serialize()
            root._check(ShellSettings.flushForUpdate(),
                "a settings reload echoing the last write does not block an update")
            settingsStore.lastSavedText = savedWas
            settingsStore.writePaused = pausedWas
            settingsStore._reloading = reloadingWas
        }
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
        // 1024 frames at 48 kHz is about 47 reads a second: fresh audio for nearly every frame of Smooth's 50 fps
        let fastestViz = 0
        for (const style of ["wave", "bars", "pulse"])
            for (const preset of ["eco", "balanced", "smooth"])
                fastestViz = Math.max(fastestViz, Media.vizProfile(style, preset, false).fps)
        root._check(Media.cavaEnvironment.PIPEWIRE_LATENCY === "1024/48000" && 48000 / 1024 >= 0.9 * fastestViz,
            "cava asks PipeWire for its stock quantum, not 512 frames, and that still feeds the fastest preset")
    }

    function _checksNotificationHistory(): void {
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
        root._check(Notifications.plainText("**Done.** Two **files** changed", 64)
                === "Done. Two files changed",
            "markdown bold markers from a terminal agent are dropped")
        root._check(Notifications.plainText("2**3 and 4**5, f(**kw) **open", 64)
                === "2**3 and 4**5, f(**kw) **open",
            "unpaired or mid-word asterisks stay as the sender wrote them")
        root._check(Notifications.plainText("** spaced ** and ****", 64)
                === "** spaced ** and ****",
            "asterisks that do not hug a word are not treated as bold")
        root._check(Notifications.plainText("```text Add notes with a TCP checker ```", 128)
                === "Add notes with a TCP checker",
            "a code fence a terminal agent flattened onto one line drops with its language word")
        root._check(Notifications.plainText("Done:\n```bash\nmake check\n```\nok", 128)
                === "Done:\nmake check\nok",
            "a fenced block on its own lines keeps the lines it wrapped")
        root._check(Notifications.plainText("Run `make check` then [open the notes](/tmp/notes.md)", 128)
                === "Run make check then open the notes",
            "inline code and link markup show only the text a reader would see")
        root._check(Notifications.plainText("it`s 3`4 and [a] (b)", 128) === "it`s 3`4 and [a] (b)",
            "a stray backtick or bracket outside markdown syntax stays")
        for (const example of [
            ["Run `<b>literal</b>` now", "Run <b>literal</b> now"],
            ["Use `**literal** [x](url)`", "Use **literal** [x](url)"],
            ["```html\n<b>literal</b>\n```", "<b>literal</b>\n"],
            ["```python\nprint(\"**value** [x](url)\")\n```", "print(\"**value** [x](url)\")\n"],
            ["```\necho first\n```", "echo first\n"],
            ["``` echo first ```", "echo first"],
            ["Before\n```\n\n  indented\n\n```\nAfter", "Before\n\n  indented\n\nAfter"],
            ["````markdown\n```js\n`x`\n```\n````", "```js\n`x`\n```\n"],
            ["~~~html\n<b>x</b>\n~~~", "<b>x</b>\n"],
            ["```html\n<b>unfinished</b>", "<b>unfinished</b>"],
            ["Use ``a ` b`` now", "Use a ` b now"],
            ["Use ````keep words with ``` inside````.", "Use keep words with ``` inside."],
            ["```text\none\n~~~\ntwo\n```\nend", "one\n~~~\ntwo\nend"],
            ["```text\r\none\r\n```", "one\r\n"],
            ["**Bold** and `<b>code</b>` and [notes](url)", "Bold and <b>code</b> and notes"],
            ["**`<b>bold code</b>`**", "<b>bold code</b>"],
            ["[Run `**literal**`](url)", "Run **literal**"],
            ["`<b>a</b>` and `**b**`", "<b>a</b> and **b**"],
            ["x\u00000\u0000 `real`", "x0 real"],
            ["`&amp;` and &amp;", "&amp; and &"],
            ["```text\na\u202Eb\u0000c\n```", "abc\n"]
        ]) root._check(Notifications.plainText(example[0], 512) === example[1],
            "notification code keeps its literal contents: " + JSON.stringify(example[0]))
        root._check(Notifications._normalizeEntry({ body: "line1\nline2" }).body
                === "line1\nline2",
            "history text keeps the newlines a multi-line body needs")
        const escapedHistory = Notifications._normalizeEntry({
            summary: "&lt;b&gt;literal&lt;/b&gt;", body: "&amp;amp;\nsecond line"
        })
        const restoredEscapedHistory = Notifications._normalizeEntry(escapedHistory, true)
        root._check(escapedHistory.summary === "<b>literal</b>"
                && restoredEscapedHistory.summary === escapedHistory.summary
                && restoredEscapedHistory.body === "&amp;\nsecond line",
            "restoring stored plain text preserves literal markup and entities without decoding again")
        root._check(Notifications._normalizeEntry({ body: "a\u202Eb" }, true).body === "ab",
            "stored plain text is still stripped of misleading direction controls")
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
        Notifications._prependHistory({ id: 251, appName: "Chat", summary: "third", time: 30 })
        Notifications._prependHistory({ id: 250, appName: "Chat", summary: "second", time: 20 })
        Notifications._prependHistory({ id: 249, appName: "Chat", summary: "first", time: 10 })
        Notifications._prependHistory({ id: 252, appName: "Chat", summary: "fourth", time: 30 })
        root._check(["fourth", "third", "second", "first"].every((s, i) =>
                Notifications.historyModel.get(i).summary === s),
            "history lists a burst by arrival even when its popups close newest first")
        Notifications.clearHistory()
        Notifications._prependHistory({ id: 271, appName: "Chat", summary: "from a clock ahead", time: Date.now() + 3600000 })
        Notifications._prependHistory({ id: 272, appName: "Chat", summary: "now", time: Date.now() })
        root._check(Notifications.historyModel.get(0).id === 272,
            "a new arrival stays above a row dated after now by a clock that went back")
        Notifications.clearHistory()
        Notifications._prependHistory({ id: 261, appName: "Agent", summary: "Approval requested", time: 10 })
        Notifications._prependHistory({ id: 262, appName: "Agent", summary: "Approval requested", time: 20 })
        Notifications._prependHistory({ id: 260, appName: "Agent", summary: "Approval requested", time: 5 })
        root._check(Notifications.historyCount === 1 && Notifications.historyModel.get(0).id === 262,
            "a sender repeating itself word for word keeps one row at its latest time")
        Notifications._prependHistory({ id: 263, appName: "Agent", summary: "Approval requested", body: "make", time: 30 })
        Notifications._prependHistory({ id: 264, appName: "Shell", summary: "Approval requested", time: 40 })
        Notifications._prependHistory({ id: 265, appName: "Agent", summary: "Approval requested", time: 50 })
        root._check([265, 264, 263, 262].every((id, i) => Notifications.historyModel.get(i).id === id),
            "a repeat with another body, another sender or a row between them keeps its own row")
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
                appName: row.appName, appIcon: row.appIcon, desktopEntry: row.desktopEntry,
                summary: row.summary, body: row.body, urgency: row.urgency })
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
            root._check(Object.getPrototypeOf(nav._appsByName) === null
                    && nav._appFor("constructor") === null,
                "the app rail index cannot mistake a JavaScript built-in for a sender")
            nav._appsByName["constructor"] = { appName: "constructor", count: 7 }
            nav._appsByName["__proto__"] = { appName: "__proto__", count: 3 }
            root._check(nav._countFor("constructor") === 7
                    && nav._countFor("__proto__") === 3
                    && nav._appFor("missing sender") === null,
                "indexed app counts preserve literal sender identities and missing results")
            const railRows = () => {
                const rows = {}
                const walk = item => {
                    if (typeof item.modelData === "string" && item.isAll !== undefined) rows[item.modelData] = item
                    for (const child of item.children) walk(child)
                }
                walk(nav)
                return rows
            }
            nav._names = ["", "Alpha", "Beta", "Gamma"]
            const railBefore = railRows()
            nav._names = ["", "Gamma", "Alpha", "Beta"]
            const railAfter = railRows()
            root._check(railBefore["Alpha"] && railAfter["Alpha"] === railBefore["Alpha"]
                    && railAfter["Gamma"] === railBefore["Gamma"],
                "a sender moving up the app rail keeps every row, so icons and focus survive")
            railAfter["Alpha"].parent.forceLayout()
            root._check(railAfter["Gamma"].y < railAfter["Alpha"].y && railAfter["Alpha"].y < railAfter["Beta"].y,
                "the app rail draws its rows in the new order")
            nav._names = ["", "Gamma", "Beta"]
            const railRemoved = railRows()
            root._check(railRemoved["Alpha"] === undefined && railRemoved["Beta"] === railBefore["Beta"],
                "a sender leaving the app rail takes only its own row")
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
            Notifications._prependHistory({ id: 803, appName: "Māil", summary: "Lunch in Rīga",
                body: "Meet at 12:00 [cafe] Café re\u0301sume\u0301 Привет 👩‍💻", time: 1003 })
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
            edits = filtered.inserts + filtered.removes
            filtered.query = "mail riga resume"
            root._check(filtered.count === 1 && filtered.model.get(0).id === 803
                    && filtered.model.get(0).appName === "Māil"
                    && filtered.model.get(0).summary === "Lunch in Rīga"
                    && filtered.inserts + filtered.removes === edits,
                "history search folds accents across sender, title and combining-mark body text without rebuilding a matching row")
            filtered.query = "RĪGA RÉSUMÉ"
            root._check(filtered.count === 1 && filtered.model.get(0).id === 803,
                "accented uppercase queries match composed and decomposed notification text")
            filtered.filter = "Mail"
            root._check(filtered.count === 0,
                "accent-insensitive history search keeps the app filter's exact sender identity")
            filtered.filter = "Māil"
            root._check(filtered.count === 1 && filtered.model.get(0).id === 803,
                "an exact accented sender filter intersects the normalized search")
            filtered.filter = ""
            filtered.query = "ПРИВЕТ 👩‍💻"
            root._check(filtered.count === 1 && filtered.model.get(0).id === 803,
                "history search preserves non-Latin text and joined emoji")
            filtered.query = "missing message"
            root._check(filtered.count === 0, "unmatched history search leaves an empty result")
            filtered.query = "  \t "
            root._check(filtered.count === 3, "whitespace-only search shows all history")
            const stableContentKey = filtered.model.get(0).contentKey
            filtered.sync()
            root._check(typeof stableContentKey === "string"
                    && filtered.model.get(0).contentKey === stableContentKey
                    && filtered.snapshot()[0].contentKey === undefined,
                "history caches row keys without exposing them in clear snapshots")
            const originalSearchBody = Notifications.historyModel.get(0).body
            filtered.query = "searchable marker"
            Notifications.historyModel.setProperty(0, "body", "Updated searchable marker")
            filtered.sync()
            root._check(filtered.count === 1 && filtered.model.get(0).id === 803,
                "a manual history sync searches the edited message text")
            filtered.revision++
            filtered.query = "searchable marker"
            root._check(filtered.count === 1
                    && filtered.model.get(0).id === 803
                    && filtered.model.get(0).contentKey !== stableContentKey,
                "an in-place source update refreshes the cached key and search results")
            Notifications.historyModel.setProperty(0, "body", originalSearchBody)
            filtered.revision++
            filtered.query = ""
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
            filtered.sync()
            root._check(flagsOf() === "FS<> --<- ---> --<> -S<>",
                "an unchanged history keeps critical and day boundaries intact")
            Notifications._prependHistory({ id: 906, appName: "Chat", summary: "second alert",
                urgency: 2, time: today + 1000 })
            filtered.revision = Notifications.historyRevision
            root._check(flagsOf().startsWith("FS<> --<> --<- --->"),
                "consecutive critical notifications each keep a separate card")
            // Reconciliation should preserve rows when order changes, and batch
            // adjacent removals instead of notifying the view once per entry.
            filtered.query = ""
            filtered.filter = ""
            const beforeReorder = filtered.snapshot()
            edits = filtered.inserts + filtered.removes
            let countChanges = 0
            const countChanged = () => { countChanges++ }
            filtered.model.countChanged.connect(countChanged)
            Notifications.historyModel.move(2, 0, 1)
            filtered.revision++
            root._check(filtered.model.get(0).id === beforeReorder[2].id
                    && filtered.model.get(1).id === beforeReorder[0].id
                    && filtered.inserts + filtered.removes === edits && countChanges === 0,
                "reordering history moves existing rows without inserts, removals or count changes")
            root._check(flagsOf() === "FS<> --<> --<> --<> --<>",
                "moving a normal row between critical rows recomputes every group boundary")
            Notifications.historyModel.move(0, 2, 1)
            filtered.revision++
            root._check(filtered.inserts + filtered.removes === edits && countChanges === 0
                    && flagsOf().startsWith("FS<> --<> --<- --->"),
                "restoring history order reuses every row and restores grouping")
            const removedBefore = filtered.removes
            countChanges = 0
            filtered.query = "no matching history entries"
            root._check(filtered.count === 0 && countChanges === 1
                    && filtered.removes === removedBefore + beforeReorder.length,
                "an empty search result removes a contiguous history in one model operation")
            countChanges = 0
            filtered.query = ""
            root._check(filtered.count === beforeReorder.length && countChanges === 1,
                "clearing search restores a contiguous history in one model operation")
            countChanges = 0
            filtered.query = "alert"
            root._check(filtered.count === 2 && countChanges === 1
                    && filtered.model.get(0).id === 906 && filtered.model.get(1).id === 905,
                "search removes a trailing run together and keeps matching rows")
            filtered.query = ""
            countChanges = 0
            filtered.query = "two"
            root._check(filtered.count === 1 && countChanges === 2
                    && filtered.model.get(0).id === 903 && flagsOf() === "FS<>",
                "search batches removals on both sides of a retained row")
            filtered.model.countChanged.disconnect(countChanged)
            const replacementSearchEntry = { id: 999, time: 100, urgency: 1,
                appName: "Replacement", summary: "New source", body: "Fresh message",
                appIcon: "", desktopEntry: "" }
            filtered.source = { count: 1, get: function() { return replacementSearchEntry } }
            filtered.query = "fresh message"
            root._check(filtered.count === 1 && filtered.model.get(0).id === 999,
                "replacing a history source searches the new source")
            filtered.source = null
            root._check(filtered.count === 0, "removing the history source clears its results")
            filtered.destroy()
        }

        // Individual deletion and Clear must both keep a row updated after its snapshot.
        for (const changedRole of [{ key: "body", value: "Updated body" },
                { key: "urgency", value: 2 }, { key: "appIcon", value: "updated-icon" },
                { key: "desktopEntry", value: "org.example.Updated" }]) {
            Notifications.clearHistory()
            Notifications._prependHistory({ id: 70, time: 1,
                appName: "Probe", summary: "Same summary", body: "Original body" })
            const oldEntry = Notifications._normalizeEntry(Notifications.historyModel.get(0), true)
            Notifications.historyModel.setProperty(0, changedRole.key, changedRole.value)
            const revisionBeforeDelete = Notifications.historyRevision
            Notifications.removeFromHistory(oldEntry)
            Notifications.clearHistoryEntries([oldEntry])
            root._check(Notifications.historyCount === 1
                    && Notifications.historyRevision === revisionBeforeDelete,
                "stale history deletion preserves an updated " + changedRole.key)
            if (Notifications.historyCount > 0) {
                const currentEntry = Notifications._normalizeEntry(Notifications.historyModel.get(0), true)
                Notifications.removeFromHistory(currentEntry)
            }
            root._check(Notifications.historyCount === 0,
                "a current history snapshot can delete the updated " + changedRole.key)
        }

        Notifications.clearHistory()
        Notifications._prependHistory({
            id: 71, appName: "Probe", summary: "Earlier session", time: 1
        })
        const archivedNotification = {
            transient: false, appName: "Probe", appIcon: "", desktopEntry: "",
            summary: "Current session", body: "", urgency: 1
        }
        const escapedNotification = Object.assign({}, archivedNotification, {
            summary: "&lt;b&gt;literal&lt;/b&gt;", body: "&amp;amp;"
        })
        Notifications._archiveNotification(escapedNotification, 72, 2, false)
        root._check(Notifications.historyModel.get(0).summary === "<b>literal</b>"
                && Notifications.historyModel.get(0).body === "&amp;",
            "archiving sender text bounds and decodes it only once")
        Notifications.removeFromHistory(0)
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
        let trimCountChanges = 0
        const noteTrim = () => { trimCountChanges++ }
        Notifications.historyModel.countChanged.connect(noteTrim)
        ShellSettings.notifHistoryLimit = 7
        Notifications.historyModel.countChanged.disconnect(noteTrim)
        root._check(Notifications.historyCount === 7,
            "lowering the limit trims history that is already stored")
        root._check(trimCountChanges === 1,
            "lowering the history limit removes the excess rows in one model edit")
        Notifications.clearHistory()

        // rows are newest first; the app holding the most gives up its oldest, and among equals the
        // one whose oldest row is oldest overall. Names are keyed as the rail keys them
        root._check(JSON.stringify(Notifications.historyEvictions(
                    ["Chat", "Chat", "Mail", "Chat", "Shot", " Chat "], 4)) === "[5,3]"
                && JSON.stringify(Notifications.historyEvictions(["A", "B", "A", "B"], 3)) === "[3]"
                && JSON.stringify(Notifications.historyEvictions(["", "Unknown", "X"], 2)) === "[1]"
                && Notifications.historyEvictions(["A", "B"], 5).length === 0,
            "a full history evicts the oldest row of the app holding the most rows")
        ShellSettings.notifHistoryLimit = 5
        Notifications._prependHistory({ id: 9801, appName: "Shot", summary: "saved", time: 1 })
        Notifications._prependHistory({ id: 9802, appName: "Mail", summary: "done", time: 2 })
        for (let i = 0; i < 10; i++)
            Notifications._prependHistory({ id: 9810 + i, appName: "Chat", summary: "m" + i, time: 10 + i })
        const keptRows = []
        for (let i = 0; i < Notifications.historyCount; i++) keptRows.push(Notifications.historyModel.get(i).summary)
        root._check(keptRows.join(",") === "m9,m8,m7,done,saved",
            "a busy chat keeps its newest rows without pushing other apps out of history (" + keptRows + ")")
        Notifications.clearHistory()
        ShellSettings.notifHistoryLimit = savedLimit

        const historyPersistentWas = ShellSettings.notifHistoryPersistent
        ShellSettings.notifHistoryPersistent = false
        Notifications._prependHistory({ id: 9901, appName: "Probe",
            summary: "Memory only", time: 9901 })
        Notifications._saveHistory()
        root._check(Notifications.historyCount === 1
                && JSON.parse(Notifications._serializeDisk()).history.length === 0,
            "history remains in memory without putting notification text into the disk payload")
        ShellSettings.notifHistoryPersistent = true
        const historyPayload = Notifications._serializeDisk()
        root._check(JSON.parse(historyPayload).history[0].summary === "Memory only",
            "enabling history persistence captures rows accumulated while it was off")
        Notifications._saveHistory()
        root._check(Notifications._serializeDisk() === historyPayload,
            "saving an unchanged history keeps the same payload")
        Notifications._prependHistory({ id: 9902, appName: "Probe",
            summary: "New revision", time: 9902 })
        Notifications._saveHistory()
        root._check(JSON.parse(Notifications._serializeDisk()).history[0].summary === "New revision",
            "a changed history refreshes the serialized payload")
        ShellSettings.notifHistoryPersistent = false
        root._check(Notifications.historyCount === 0
                && JSON.parse(Notifications._serializeDisk()).history.length === 0,
            "disabling history persistence clears the previously serialized text")
        ShellSettings.notifHistoryPersistent = historyPersistentWas

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

        // an app picked in History goes with the menu, as its search does: the missed-notification badge opens every app
        const filterWas = { open: MenuState.open, tab: MenuState.activeTab }
        MenuState.showTab(MenuState.recentTab)
        MenuState.setRecentFilter("Chat")
        MenuState.selectTab(MenuState.homeTab)
        MenuState.selectTab(MenuState.recentTab)
        const filterKeptWhileOpen = MenuState.recentFilter === "Chat"
        MenuState.close()
        const filterKeptWhileClosing = MenuState.recentFilter === "Chat"
        MenuState.showTab(MenuState.recentTab)
        root._check(filterKeptWhileOpen && filterKeptWhileClosing && MenuState.open && MenuState.recentFilter === "",
            "a history app filter survives a tab switch, stays put while the menu closes and is gone when it reopens")
        const missedWas = { count: Notifications.missedCount, dnd: ShellSettings.dnd }
        ShellSettings.dnd = true
        MenuState.selectTab(MenuState.homeTab)
        Notifications.missedCount = 3
        const missedKeptOnHome = Notifications.missedCount === 3
        MenuState.selectTab(MenuState.recentTab)
        root._check(missedKeptOnHome && Notifications.missedCount === 0 && Notifications.silencingActive,
            "opening History ends the missed count while Do Not Disturb stays on, so its badge never opens a page already read")
        const missedInFront = Notifications.missedOnArrival(true, false, "Chat")
        MenuState.setRecentFilter("Mail")
        const missedBehindFilter = Notifications.missedOnArrival(true, false, "Chat")
        const shownUnderOwnFilter = Notifications.missedOnArrival(true, false, " Mail ")
        MenuState.setRecentFilter("")
        MenuState.selectTab(MenuState.homeTab)
        root._check(!missedInFront && missedBehindFilter && !shownUnderOwnFilter
                && Notifications.missedOnArrival(true, false, "Chat")
                && Notifications.missedOnArrival(false, true, "Chat") && !Notifications.missedOnArrival(false, false, "Chat"),
            "a silenced notification whose row lands on the History page in front of you is not missed; behind another app's filter it is")
        ShellSettings.dnd = missedWas.dnd
        Notifications.missedCount = missedWas.count
        MenuState.setRecentFilter("")
        MenuState.selectTab(filterWas.tab)
        if (filterWas.open) MenuState.openUnanchored()
        else MenuState.close()
    }

    function _checksSettingsSearchAndText(): void {
        const savedSection = MenuState.settingsSection
        root._check(MenuState._settingsSearchEntries.length === MenuState._flatSections.length
                && MenuState._settingsSearchEntries.every(row => MenuState._flatSections.indexOf(row.section) >= 0),
            "settings search indexes each available section once without constructing pages")
        // a renamed setting or section would leave its search words pointing at nothing, silently
        root._check(Object.keys(MenuState._settingsKeyAliases).every(k => ShellSettings._schemaByKey[k] !== undefined)
                && Object.keys(MenuState._settingsSearchAliases).every(s => MenuState._flatSections.indexOf(s) >= 0),
            "every search alias names a real setting or section")
        root._check(MenuState.searchSettings("").length === 0
                && MenuState.searchSettings("   ").length === 0
                && MenuState.searchSettings("!!!").length === 0,
            "empty and punctuation-only settings queries show no results")
        root._check(MenuState.searchSettings("FONT").some(row => row.section === "interface")
                && MenuState.searchSettings("transparency").some(row => row.section === "theme")
                && MenuState.searchSettings("do not disturb").some(row => row.section === "popups")
                && MenuState.searchSettings("reset defaults").some(row => row.section === "updates"),
            "settings search recognizes common feature names and aliases")
        const topSection = query => (MenuState.searchSettings(query)[0] || {}).section
        root._check(topSection("bigger text") === "interface" && topSection("zoom") === "interface"
                && topSection("margin") === "surface" && topSection("tooltip") === "surface"
                && topSection("caps lock") === "widgets" && topSection("screen lock") === "devices",
            "settings search finds a setting by the everyday word for it, not only by its label")
        root._check(MenuState.searchSettings("history retention").some(row => row.section === "history")
                && MenuState.searchSettings("brightness display").some(row => row.section === "devices")
                && MenuState.searchSettings("night-light").some(row => row.section === "devices"),
            "settings search matches all words and normalizes punctuation")
        root._check(MenuState.searchSettings("notifHistoryDays").some(row => row.section === "history")
                && MenuState.searchSettings("calendarWeekStart").some(row => row.section === "clock")
                && MenuState.searchSettings("fontFamily").some(row => row.section === "interface"),
            "settings search accepts exact configuration names as well as plain-language queries")
        root._check(MenuState.searchSettings("font battery").length === 0
                && MenuState.searchSettings("no such feature qzx").length === 0,
            "unrelated terms cannot produce a misleading settings match")
        const lockHits = MenuState.searchSettings("lock")
        root._check(lockHits[0]?.section === "devices" && !lockHits.some(row => row.section === "clock")
                && !MenuState.searchSettings("light").some(row => row.section === "surface")
                && MenuState.searchSettings("wi-fi").some(row => row.section === "indicators")
                && MenuState.searchSettings("12h")[0]?.key === "clock12h",
            "settings search matches word starts, so lock finds the screen lock rather than the clock")
        root._check(MenuState.searchSettings(" ".repeat(256) + "font").length === 0,
            "settings queries have a bounded input budget")
        const barMatches = MenuState.searchSettings("bar")
        root._check(barMatches.length > 3 && barMatches.slice(0, 3).every(row => row.group === "Bar")
                && barMatches[0].section === "surface"
                && MenuState.searchSettings("media")[0].section === "media",
            "visible section and group names outrank incidental configuration-key matches")
        root._check(MenuState._settingsSearchEntries.map(row => row.section).join(",")
                === MenuState._flatSections.join(","),
            "ranking search results leaves the cached index in navigation order")
        const keyedHit = MenuState.searchSettings("notifHistoryDays").find(row => row.section === "history")
        const quietHit = MenuState.searchSettings("dnd from").find(row => row.section === "popups")
        const aliasHit = MenuState.searchSettings("quiet hours").find(row => row.section === "popups")
        root._check(keyedHit && keyedHit.key === "notifHistoryDays"
                && quietHit && quietHit.key === "dndFrom"
                && aliasHit && aliasHit.key === ""
                && MenuState._settingsSearchEntries.every(row => row.key === undefined),
            "a settings result names the setting it matched without touching the cached index")
        const labelHit = (query, section) => MenuState.searchSettings(query).find(row => row.section === section)
        root._check(labelHit("keep after restart", "history")?.key === "notifHistoryPersistent"
                && labelHit("shell shadows", "theme")?.key === "barShadow"
                && labelHit("network speed", "indicators")?.key === "networkTrafficStats"
                && labelHit("switch animation", "workspaces")?.key === "workspaceShift",
            "settings search finds a row by the label it shows, not only by its configuration name")
        root._check(labelHit("track package updates", "updates")?.key === "updatesWidget"
                && labelHit("track package updates", "widgets")?.key === "updatesWidget"
                && labelHit("underlineTempGlow", "warnings")?.key === "underlineTempGlow",
            "a setting shared by two sections is searchable from both")
        const top = query => MenuState.searchSettings(query)[0] ?? {}
        root._check(top("format").section === "clock" && top("format").key === "clock12h"
                && top("mode").section === "underline"
                && top("notification pulse").section === "workspaces"
                && top("app icon").key === "showWindowTitleIcon"
                && top("low battery warning").key === "osdBatteryWarn"
                && top("pause when headphones disconnect").key === "mediaPauseOnDisconnect"
                && top("source").section === "theme",
            "a row titled exactly like the query outranks pages that only share its words")
        root._check(top("keyboard layout").section === "widgets" && top("keyboard").key === "barShowKeyboard"
                && top("update").section === "updates" && top("reset").section === "updates"
                && top("dark mode").section === "theme" && top("blue light").section === "devices",
            "settings search answers everyday words and the widget names on Show & order")
        root._check(ShellSettings._schema.every(e => !e.l || e.sec.split(",").every(sec =>
                MenuState.searchSettings(e.l).some(row => row.section === sec && row.key === e.k))),
            "every labelled setting is found on each of its pages by the label it shows")
        const revealPage = settingsPageFactory.createObject(root, { width: 320, active: false })
        const builtSections = {}
        const sectionFor = sec => builtSections[sec]
            ?? (builtSections[sec] = revealPage._sectionComponents[sec].createObject(barFixtureHost, { width: 320 }))
        const rowsFor = (sec, key) => {
            const out = []
            root._findTrayNode(sectionFor(sec), it => {
                if ((it.key === key || it.searchKey === key) && it.topRadius !== undefined) out.push(it)
                return false
            })
            return out
        }
        const reachable = (sec, key, hops) => rowsFor(sec, key).length > 0
            || (hops > 0 && revealPage.revealRowFor(sec, key).length > 0
                && reachable(sec, revealPage.revealRowFor(sec, key), hops - 1))
        // Show & order rows, the muted apps list and the glow half of an alert chip are not yet keyed
        const unkeyed = ["showWindowTitle@widgets", "updatesWidget@widgets", "barShowSystem@widgets",
            "notifMutedApps@history", "underlineBattGlow@warnings", "underlineTempGlow@warnings"]
        const unreachable = []
        for (const e of ShellSettings._schema.filter(e => e.l))
            for (const sec of e.sec.split(","))
                if (unkeyed.indexOf(e.k + "@" + sec) < 0 && !reachable(sec, e.k, 3)) unreachable.push(e.k + "@" + sec)
        root._check(unreachable.length === 0,
            "every labelled setting has a row on each of its pages for search to flash: " + unreachable.join(" "))
        root._check(revealPage._keyRow(sectionFor("media"), "mediaWidgetFormat")?.label === "Artist"
                && revealPage._keyRow(sectionFor("clock"), "clock12h")?.label === "Format",
            "search reveals a row that writes its setting through its own handler")
        const battRows = rowsFor("warnings", "osdBatteryWarn")
        if (battRows.length === 2) {
            battRows[0].parent.parent.visible = false
            battRows[1].parent.parent.visible = true
        }
        root._check(battRows.length === 2 && revealPage._keyRow(sectionFor("warnings"), "osdBatteryWarn") === battRows[1],
            "search reveals the shown row when a setting has one per hardware case")
        const savedMuted = ShellSettings.notifMutedApps
        ShellSettings.setNotifAppMuted("Discord", true)
        const mutedRow = root._findTrayNode(sectionFor("history"), it => it.label === "Discord")
        root._check(mutedRow?.Accessible.name === "Mute popups from Discord" && mutedRow.Accessible.checked,
            "a muted app's row says what its check box does")
        ShellSettings.notifMutedApps = savedMuted
        const health = root._findTrayNode(sectionFor("updates"), it => typeof it._toggleDevices === "function")
        const openedWithWarnings = health && health._devicesExpanded === (health._deviceWarnings > 0)
        if (health) health._toggleDevices()
        const foldedByHand = health && health._devicesTouched && health._devicesExpanded === (health._deviceWarnings === 0)
        if (health) health._devicesExpanded = false
        if (health) health._deviceWarningsChanged()
        root._check(openedWithWarnings && foldedByHand && health._devicesExpanded === false,
            "device checks open with the page only when one needs attention, and stay as they were folded by hand")
        for (const sec in builtSections) builtSections[sec].destroy()
        revealPage.destroy()
        const sameAs = (typo, word) => MenuState.searchSettings(typo).map(row => row.section).join(",")
            === MenuState.searchSettings(word).map(row => row.section).join(",") && MenuState.searchSettings(word).length > 0
        root._check(sameAs("worksapce", "workspace") && sameAs("brigthness", "brightness")
                && sameAs("notifcations", "notifications") && sameAs("wrok", "work")
                && sameAs("visualiser", "visualizer") && sameAs("bluetoth", "bluetooth")
                && sameAs("nigth ligth", "night light"),
            "a mistyped or swapped letter still finds the setting")
        root._check(MenuState.searchSettings("spotify").length === 0 && MenuState.searchSettings("bars").length > 0
                && MenuState.searchSettings("qzxv").length === 0 && MenuState._correctedTerm("clok") === "clock"
                && MenuState._correctedTerm("lok") === "lok",
            "typo correction leaves exact matches, short words and unrelated names alone")
        const landsOn = (query, key) => (MenuState.searchSettings(query)[0] ?? {}).key === key
        root._check(landsOn("wave", "mediaVisualizerStyle") && landsOn("balanced", "mediaVisualizerPreset")
                && landsOn("tall", "barHeight") && landsOn("wide", "barSpacing") && landsOn("warm", "nightLightProvider")
                && landsOn("battery percentage", "valuesOnHover") && landsOn("charging", "batteryAutoHide")
                && landsOn("systray", "trayWidget") && MenuState._correctedTerm("charging") === "charging",
            "a row's chip names and everyday words find that row, not a word spelled near them")
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
        root._check(MenuState._ipcSection("Diagnostics") === "updates"
                && MenuState._ipcSection("maintenance") === "updates"
                && MenuState._ipcSection("Overview") === "updates"
                && MenuState._ipcSection("system") === "updates",
            "the system overview accepts both combined and former page names")
        MenuState.setSettingsSection("maintenance")
        root._check(MenuState.settingsSection === "updates"
                && MenuState._flatSections.indexOf("maintenance") < 0,
            "the former diagnostics id selects the one combined settings page")
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
        root._check(CalendarState.weekdayLabelFor(0, Qt.locale("en_US")).toUpperCase() === "S"
                && CalendarState.weekdayLabelFor(0, Qt.locale("fr_FR")).toUpperCase() === "D",
            "calendar weekday captions follow the requested locale instead of fixed English initials")
        root._check(CalendarState.weekendFor(0, [1, 2, 3, 4, 5])
                && CalendarState.weekendFor(6, [1, 2, 3, 4, 5])
                && !CalendarState.weekendFor(5, [1, 2, 3, 4, 5]),
            "calendar weekend shading respects a Monday-to-Friday working week")
        root._check(CalendarState.weekendFor(5, [0, 1, 2, 3, 4])
                && CalendarState.weekendFor(6, [0, 1, 2, 3, 4])
                && !CalendarState.weekendFor(0, [0, 1, 2, 3, 4]),
            "a Sunday-to-Thursday working week shades Friday and Saturday instead of Sunday")
        root._check(CalendarState.weekendFor(5, Qt.locale("he_IL").weekDays)
                && !CalendarState.weekendFor(0, Qt.locale("he_IL").weekDays),
            "a locale's own working days shade its weekend, not the Saturday and Sunday fallback")
        root._check(CalendarState.weekendFor(5, [0, 1, 2, 3, 4, 6])
                && !CalendarState.weekendFor(6, [0, 1, 2, 3, 4, 6])
                && CalendarState.weekendFor(0, null) && CalendarState.weekendFor(6, []),
            "calendar weekends support a single rest day and retain a fallback for unavailable locale data")
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
        root._check(MenuState.open && MenuState.anchorSource !== null,
            "a vacant anchor is claimed by a live widget instead of closing the menu")
        MenuState.adoptAnchor(probeAnchor)
        root._check(MenuState.anchorSource !== probeAnchor,
            "a widget cannot take an anchor another one already holds")
        MenuState._setAnchor(null)
        root._check(MenuState.open && MenuState.anchorSource === null,
            "deliberately clearing the anchor is not reclaimed")
        MenuState.close()

        const popupEdge = Metrics.popupClearance(8)
        const topPopupY = Metrics.popupY(1000, 200, false, popupEdge)
        const bottomPopupY = Metrics.popupY(1000, 200, true, popupEdge)
        root._check(isFinite(topPopupY) && isFinite(bottomPopupY),
            "popup placement stays finite")
        root._check(topPopupY + bottomPopupY + 200 === 1000,
            "top and bottom popup placement is symmetric")
        const anchoredBottom = bottomPopupY + 200
        root._check(Metrics.popupY(1000, 200.25, true, popupEdge) + 200.25 === anchoredBottom
                && Metrics.popupY(1000, 201.75, true, popupEdge) + 201.75 === anchoredBottom,
            "bottom-anchored popups keep their edge fixed through fractional resize frames")
        root._check(Metrics.popupY(1000, 204, true, popupEdge) % 4 === 0,
            "a settled bottom popup still lands on the shared pixel grid")

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
        // measured on Hyprland at 1.25: the screen reports 2, and a theme icon asked for 20 came back as 50
        root._check(IconResolver.decodeSide("image://icon/spotify-linux-32?path=/usr/share/spotify/icons", 16, 1.25, 2) === 8
                && IconResolver.decodeSide("image://icon/x", 16, 1, 2) === 8
                && IconResolver.decodeSide("image://icon/x", 16, 2, 2) === 8
                && IconResolver.decodeSide("image://icon/x", 16, 1.25, 1) === 16,
            "a theme icon asks for its device size divided by both ratios that scale the request")
        root._check(IconResolver.decodeSide("image://qspixmap/7/0", 16, 1.25, 2) === 16
                && IconResolver.decodeSide("file:///usr/share/icons/x.svg", 16, 1.25, 2) === 16
                && IconResolver.decodeSide("file:///usr/share/pixmaps/x.png", 16, 1.25, 2) === 20,
            "a tray pixmap or an SVG is scaled once by the window ratio, and a raster file is decoded as asked")
        root._check(IconResolver.themeScaleMissing("image://icon/x", 8, 16, 1.25, 2)
                && !IconResolver.themeScaleMissing("image://icon/x", 16, 16, 1.25, 2)
                && !IconResolver.themeScaleMissing("image://icon/x", 8, 16, 1.25, 1)
                && !IconResolver.themeScaleMissing("image://qspixmap/7/0", 8, 16, 1.25, 2),
            "an icon notices a theme provider that stopped scaling twice, and nothing else")
        // this probe's screen is 1x, so a theme icon told to expect a factor of 2 meets exactly that provider
        const unscaled = shellIconFactory.createObject(root, { side: 16, iconScale: 2, source: "image://icon/silere-probe-absent" })
        const scaledAsUsual = shellIconFactory.createObject(root, { side: 16, iconScale: 1, source: "image://icon/silere-probe-absent" })
        root._check(unscaled.status === Image.Ready && !unscaled.themeScaled && unscaled.backer.sourceSize.width === 16
                && scaledAsUsual.themeScaled && scaledAsUsual.backer.sourceSize.width === 16
                && unscaled.width === 16,
            "an icon whose theme request comes back unscaled asks once more at its full size")
        unscaled.destroy()
        scaledAsUsual.destroy()
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
        root._check(IconResolver.senderIconSource("/usr/lib/kitty/logo/kitty.png") === "file:///usr/lib/kitty/logo/kitty.png"
                && IconResolver.senderImageSource("image://icon//usr/share/discord/discord.png")
                    === "file:///usr/share/discord/discord.png"
                && IconResolver.senderIconSource("/usr/libexec/x.png") === ""
                && IconResolver.senderIconSource("/usr/local/bin/x.png") === ""
                && IconResolver.senderIconSource("/usr/lib/../../tmp/fifo.png") === ""
                && IconResolver.senderIconSource("/var/tmp/fifo.png") === ""
                && IconResolver.senderIconSource("/nix/store/0000-user-added/icon.png") === "",
            "an icon a terminal or packaged app passes from its own root-owned folder shows, and nothing a user could plant")
        const alert = SystemAlerts.alertCommand("-x battery low", "10%", "normal", "battery-caution", 10000)
        root._check(alert.indexOf("--app-name=Silere Shell") > 0 && alert.indexOf("--icon=battery-caution") > 0
                && alert.indexOf("--expire-time=10000") > 0
                && alert.indexOf("--") === alert.length - 3 && alert[alert.length - 2] === "-x battery low"
                && SystemAlerts.alertCommand("a", "b", "critical", "", 0).indexOf("--icon=dialog-information") > 0,
            "Silere's own alerts carry one app name and an icon, and a dash-named device still reaches the summary")
        root._check(IconResolver.senderImageSource("image://icon//usr/share/pixmaps/app.png")
                    === "file:///usr/share/pixmaps/app.png"
                && IconResolver.senderImageSource("IMAGE://Icon//home/user/app.png") === ""
                && IconResolver.senderImageSource("image://icon/a/../../x") === ""
                && IconResolver.senderImageSource("image://icon/x?path=/etc") === ""
                && IconResolver.senderImageSource("image://icon/") === "",
            "an image-path quickshell passes through the icon provider stays inside the same rules")
        root._check(IconResolver.hintedIconName("image://icon/applets-screenshooter") === "applets-screenshooter"
                && IconResolver.hintedIconName("image://icon//usr/share/pixmaps/app.png") === "/usr/share/pixmaps/app.png"
                && IconResolver.hintedIconName("image://icon/a/../../x") === ""
                && IconResolver.hintedIconName("image://icon/x?path=/etc") === ""
                && IconResolver.hintedIconName("image://qsimage/1") === ""
                && IconResolver.hintedIconName("/usr/share/pixmaps/app.png") === ""
                && IconResolver.senderIconSource(IconResolver.hintedIconName("IMAGE://Icon//home/user/app.png")) === "",
            "the icon notify-send names through image-path is kept by name, and a path still meets the icon folder rules")
        const hintedEntry = n => Notifications._notificationHistoryEntry(Object.assign({ appName: "Screenshot",
            summary: "Saved", body: "", urgency: 1, transient: false, desktopEntry: "" }, n), 1, 0)
        root._check(hintedEntry({ appIcon: "", image: "image://icon/applets-screenshooter" }).appIcon === "applets-screenshooter"
                && hintedEntry({ appIcon: "kitty", image: "image://icon/applets-screenshooter" }).appIcon === "kitty"
                && hintedEntry({ appIcon: "", image: "image://qsimage/7" }).appIcon === "",
            "history keeps the icon notify-send sent as an image when the app named none")
        root._check(IconResolver.senderIconSource("/usr/share/icons/../../../dev/zero") === ""
                && IconResolver.senderIconSource("file:///usr/share/icons/%2e%2e/%2e%2e/%2e%2e/dev/zero") === ""
                && IconResolver.senderIconSource("file://host/usr/share/icons/app.png") === ""
                && IconResolver.senderIconSource("/usr/sharex/app.png") === ""
                && IconResolver.senderIconSource("/tmp/usr/share/icons/app.png") === "",
            "a notification icon path cannot climb or reach past the root-owned system folders")
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
    }

    function _checksWindowTextAndToolOutput(): void {
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
            const keyboardWas = { layout: hypr.keyboardLayout, revision: hypr._keyboardRevision, count: hypr.keyboardLayoutCount }
            const keyboardSnapshot = JSON.stringify({ keyboards: [null,
                { main: false, active_keymap: "English (US)" },
                { main: true, active_keymap: "Latvian" }] })
            hypr._acceptKeyboardSnapshot(keyboardSnapshot, hypr._keyboardRevision)
            root._check(hypr.keyboardLayout === "Latvian",
                "the keyboard snapshot selects the main keyboard and tolerates a missing entry")
            const beforeLayoutEvent = hypr._keyboardRevision
            hypr._eventConn.onRawEvent({ name: "activelayout", data: "at-keyboard,English (US, intl.)" })
            hypr._acceptKeyboardSnapshot(keyboardSnapshot, beforeLayoutEvent)
            root._check(hypr.keyboardLayout === "English (US, intl.)",
                "a layout event wins over an older in-flight devices snapshot and preserves commas in the layout")
            hypr._eventConn.onRawEvent({ name: "activelayout", data: "missing delimiter" })
            hypr._eventConn.onRawEvent({ name: "activelayout", data: "at-keyboard," })
            hypr._acceptKeyboardSnapshot('{"keyboards":{}}', hypr._keyboardRevision)
            hypr._acceptKeyboardSnapshot("not JSON", hypr._keyboardRevision)
            root._check(hypr.keyboardLayout === "English (US, intl.)"
                    && hypr._keyboardRevision === beforeLayoutEvent + 1,
                "malformed keyboard events and snapshots preserve the last known layout")
            hypr._eventConn.onRawEvent({ name: "activelayout", data: "hl-virtual-keyboard-wtype,error" })
            hypr._eventConn.onRawEvent({ name: "activelayout", data: "hl-virtual-keyboard,English (US)" })
            hypr._acceptKeyboardSnapshot(JSON.stringify({ keyboards: [
                { name: "hl-virtual-keyboard-wtype", main: true, active_keymap: "error" },
                { name: "at-translated-set-2-keyboard", main: false, active_keymap: "Latvian" }] }),
                hypr._keyboardRevision)
            root._check(hypr.keyboardLayout === "Latvian" && hypr._keyboardRevision === beforeLayoutEvent + 1,
                "a virtual keyboard's own keymap never replaces the physical keyboard's layout")
            hypr._acceptKeyboardSnapshot('{"keyboards":[]}', hypr._keyboardRevision)
            root._check(hypr.keyboardLayout === "",
                "a valid snapshot with no keyboard clears its removed layout")
            hypr.keyboardLayout = keyboardWas.layout
            hypr._keyboardRevision = keyboardWas.revision
            hypr.keyboardLayoutCount = keyboardWas.count
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
            const liveOk = !hypr._socketDead && !hypr._socketConfirm.running
            for (let i = 0; i < 3; i++) hypr._noteFocusFlip()
            const armedOnly = hypr._socketConfirm.running && !hypr._socketDead
            hypr._eventSeq++
            hypr._socketConfirm.stop()
            hypr._socketConfirm.triggered()
            const lateOk = !hypr._socketDead
            hypr._seqAtFlip = -1
            hypr._silentFlips = 0
            for (let i = 0; i < 4; i++) hypr._noteFocusFlip()
            hypr._socketConfirm.stop()
            hypr._socketConfirm.triggered()
            root._check(liveOk && armedOnly && lateOk && hypr._socketDead,
                "focus flips with socket events stay healthy; events landing after three silent flips keep the shell up, silence after them marks the socket dead")
            hypr._socketConfirm.stop()
            hypr._socketDead = false
            hypr._silentFlips = 0
            hypr._seqAtFlip = -1
            // the queued events land, then one more flip comes just before the deadline, its own event not yet read
            for (let i = 0; i < 4; i++) hypr._noteFocusFlip()
            hypr._eventSeq++
            hypr._noteFocusFlip()
            hypr._socketConfirm.stop()
            hypr._socketConfirm.triggered()
            root._check(!hypr._socketDead,
                "events that arrived during the confirmation keep the shell up, even with a flip right before its end")
            hypr._socketConfirm.stop()
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
            root._check(hypr._workspaceId({ id: 3, name: "3" }) === 3
                    && hypr._workspaceId({ id: -1, name: "mail" }) === hypr.namedWorkspaceId
                    && hypr.namedWorkspaceId < -1337
                    && hypr._workspaceId({ id: -1340, name: "mail" }) === -1340
                    && hypr._workspaceId({ id: -1, name: "" }) === -1
                    && hypr._workspaceId(null) === -1,
                "a 0.57 named workspace reads as named, and only a missing one as no data")
            const specialMons = [
                { name: "DP-1", lastIpcObject: { specialWorkspace: { id: -98, name: "special:magic" } } },
                { name: "DP-2", lastIpcObject: { specialWorkspace: { id: 0, name: "" } } },
                { name: "DP-3", lastIpcObject: { specialWorkspace: { id: -97, name: "special:term" } } },
                { name: "DP-4", lastIpcObject: {} }, null]
            root._check(JSON.stringify(hypr.serialsFrom([
                    { lastIpcObject: { name: "eDP-2", serial: " 0x00006000 " } },
                    { lastIpcObject: { name: "DP-1", serial: "" } }, { lastIpcObject: { name: "DP-2" } },
                    { lastIpcObject: null }, null])) === '{"eDP-2":"0x00006000"}',
                "hyprland's monitor replies give a serial only where one was reported")
            root._check(JSON.stringify(hypr.specialFromMonitors(specialMons, { "DP-3": true })) === '{"DP-1":true}',
                "the first monitor read marks a special workspace shown before startup, unless an event spoke since")
            const specialWas = hypr._specialOn
            const heardWas = Object.assign({}, hypr._specialHeard)
            hypr._specialOn = { "DP-1": true, "DP-3": true }
            hypr._eventConn.onRawEvent({ name: "monitorremoved", data: "DP-1" })
            root._check(JSON.stringify(hypr._specialOn) === '{"DP-3":true}'
                    && hypr.specialFromMonitors(specialMons, hypr._specialHeard)["DP-1"] === undefined,
                "a disconnected output loses its special marker and a late startup snapshot cannot restore it")
            hypr._eventConn.onRawEvent({ name: "monitorremovedv2", data: "2,DP-3,Screen, with comma" })
            root._check(Object.keys(hypr._specialOn).length === 0,
                "the v2 monitor removal clears the correct output even when its description contains commas")
            hypr._specialOn = specialWas
            for (const key of Object.keys(hypr._specialHeard)) delete hypr._specialHeard[key]
            Object.assign(hypr._specialHeard, heardWas)
            hypr._eventSeq = seqWas
            const onNamed = { ref: "0xa", wsId: hypr.namedWorkspaceId, wsRef: hypr.namedWorkspaceId, focusRank: 2 }
            const noWorkspace = { ref: "0xb", wsId: -1, wsRef: -1, focusRank: 0 }
            root._check(WindowActions._chooseSource([noWorkspace, onNamed]) === onNamed
                    && WindowActions._chooseSource([noWorkspace]) === null,
                "a window on a named or special workspace can be found, and one on no workspace cannot")
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
            const closedWas = hypr._closedAddrs
            hypr._closedAddrs = ({})
            hypr._eventConn.onRawEvent({ name: "closewindow", data: "5561ab" })
            const ghost = { address: "5561ab", lastIpcObject: { address: "0x5561ab", workspace: { id: 2 } } }
            const live = { address: "77aa", lastIpcObject: { address: "0x77aa", workspace: { id: 1 } } }
            const kept = hypr._withoutClosed([ghost, live], hypr._closedAddrs)
            root._check(kept.length === 1 && kept[0] === live
                    && hypr._missingWorkspaceId([{ id: 1 }], hypr._withoutClosed([ghost, live], hypr._closedAddrs)) === -1,
                "a window hyprland closed stays off the bar when a stale client snapshot brings it back")
            hypr._eventConn.onRawEvent({ name: "openwindow", data: "5561ab,2,kitty,title" })
            root._check(hypr._withoutClosed([ghost], hypr._closedAddrs).length === 1,
                "a new window at a closed window's address shows again")
            for (let i = 0; i < 70; i++) hypr._eventConn.onRawEvent({ name: "closewindow", data: "f" + i })
            root._check(Object.keys(hypr._closedAddrs).length === 64
                    && hypr._closedAddrs["0xf69"] === true && hypr._closedAddrs["0xf0"] === undefined,
                "closed windows are remembered up to the newest 64")
            root._check(hypr._evictable(["0xa", "0xb", "0xc"], [{ address: "a" }, null]) === "0xb"
                    && hypr._evictable(["0xa", "0xb"], [{ address: "a" }, { address: "b" }]) === "0xa",
                "the closed-window memory forgets a window quickshell already dropped before a ghost it still lists")
            hypr._closedAddrs = closedWas
            const activeWas = hypr._activeAddr
            const unfocusedWas = hypr._unfocused
            const settleWas = hypr._refreshSettleTimer.running
            hypr._refreshSettleTimer.stop()
            const focusTickWas = hypr._layoutTick
            hypr._eventConn.onRawEvent({ name: "activewindowv2", data: "fa01" })
            hypr._eventConn.onRawEvent({ name: "activewindowv2", data: "fb02" })
            hypr._eventConn.onRawEvent({ name: "activewindowv2", data: "fa01" })
            const focusAsked = hypr._refreshSettleTimer.running || hypr._layoutTick !== focusTickWas
            const focusOrdered = hypr._focusOrder["fa01"] > hypr._focusOrder["fb02"]
            hypr._eventConn.onRawEvent({ name: "closewindow", data: "fb02" })
            root._check(!focusAsked && focusOrdered && hypr._focusOrder["fb02"] === undefined,
                "a focus change ranks windows from its own events, rebuilding nothing quickshell's own update did not")
            const stale = { address: "0xfa01", focusHistoryID: 0 }
            root._check(hypr.focusRankOf("fa01", stale) < hypr.focusRankOf("fc03", { address: "0xfc03", focusHistoryID: 0 })
                    && hypr.focusRankOf("fc03", { focusHistoryID: 2 }) === 2 && hypr.focusRankOf("fc03", null) === 9999
                    && hypr.focusRankOf("fc03", null, true) < hypr.focusRankOf("fa01", stale),
                "the focused window ranks first, then the ones focused this session, then hyprland's last listing")
            delete hypr._focusOrder["fa01"]
            hypr._refreshSettleTimer.stop()
            hypr._refreshAgain = false
            hypr._eventConn.onRawEvent({ name: "createworkspacev2", data: "7,7" })
            const createArmed = hypr._refreshSettleTimer.running
            hypr._eventConn.onRawEvent({ name: "createworkspacev2", data: "8,8" })
            root._check(createArmed && hypr._refreshAgain === false,
                "a new workspace runs the workspace checks without asking hyprland for every client")
            hypr._refreshSettleTimer.stop()
            hypr._refreshAgain = false
            hypr._closedAddrs = closedWas
            hypr._activeAddr = activeWas
            hypr._unfocused = unfocusedWas
            if (settleWas) hypr._refreshSettleTimer.restart()
            hypr._eventSeq = seqWas
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
            const replyWindows = [0, 1, 2].map(i => Qt.createQmlObject(
                "import QtQuick; QtObject { property string address: \"c" + i + "\"; property var lastIpcObject: ({}) }", root))
            let copyRebuilds = 0
            const countCopyRebuild = () => copyRebuilds++
            hypr._ipcCopiesChanged.connect(countCopyRebuild)
            const watchModelWas = hypr._ipcWatch.model
            hypr._ipcWatch.model = replyWindows
            discoveryClock.wait(1)
            const listRebuilds = copyRebuilds
            for (const w of replyWindows) w.lastIpcObject = { address: "0x" + w.address, focusHistoryID: 1 }
            const rebuiltInReply = copyRebuilds - listRebuilds
            discoveryClock.wait(1)
            hypr._ipcCopiesChanged.disconnect(countCopyRebuild)
            hypr._ipcWatch.model = watchModelWas
            discoveryClock.wait(1)
            for (const w of replyWindows) w.destroy()
            root._check(listRebuilds === 1 && rebuiltInReply === 0 && copyRebuilds === 2,
                "a new window list and a burst of window replies each rebuild the shared window copies once, after the event")
            const liveIpc = { address: "0xa1", workspace: { id: 2, name: "2" }, focusHistoryID: 3 }
            const copied = hypr.ipcCopiesOf([{ address: "a1", lastIpcObject: liveIpc }, null,
                { address: "", lastIpcObject: { address: "0x0" } }, { address: "b2", lastIpcObject: null }])
            root._check(Object.keys(copied).join() === "a1,b2" && copied.a1 !== liveIpc
                    && copied.a1.workspace.id === 2 && copied.a1.focusHistoryID === 3 && copied.b2 === null,
                "each window's IPC map is copied once, as plain data, under its address")
            const unsynced = { address: "d4" }
            const addressWas = hypr._addr(unsynced)
            hypr._addressOf.set(unsynced, "d4")
            const addressSynced = hypr._addr(unsynced)
            hypr._syncIpcCopies()
            root._check(addressWas === "" && addressSynced === "d4" && hypr._addr(unsynced) === "" && hypr._addr(null) === "",
                "the window models learn an address from the copy sync, never by reading the window, which signals it on every reply")
            hypr._addressOf.set(unsynced, "d4")
            const revWas = hypr._addressRev
            hypr._syncIpcCopies()
            const revOnChange = hypr._addressRev
            hypr._syncIpcCopies()
            root._check(revOnChange === revWas + 1 && hypr._addressRev === revOnChange,
                "a sync that changes the windows tells the active window and urgency to look again, and a reply with the same windows does not")
            const oddClass = "kit\u202Ety\n\u0007app"
            const cleaned = hypr._identity(oddClass)
            for (let i = 0; i < 300; i++) hypr._identity("probe-class-" + i)
            root._check(cleaned === SafeText.singleLineText(oddClass, Compositor.maxWindowIdentityChars)
                    && hypr._identity(oddClass) === cleaned && hypr._identity("__proto__") === "__proto__"
                    && hypr._identity(null) === "" && Object.keys(hypr._identities).length <= 256,
                "a window identity is cleaned once and remembered, any name included, in a bounded cache")
            root._check(hypr.monitorlessWorkspaceId([{ id: 2, monitor: { name: "A" } }, null, { id: -98, monitor: null },
                    { id: 4, monitor: null }]) === 4
                    && hypr.monitorlessWorkspaceId([{ id: 2, monitor: { name: "A" } }, { id: -98, monitor: null }]) === -1,
                "a numbered workspace with no monitor is found, so the bar asks for the workspace list again")
            root._check(!hypr._shortcuts.owns && hypr._shortcuts._held.length === 0,
                "a shell silere run did not start claims no Hyprland global shortcut")
        }
        root._check(SafeText.lastNonEmptyLine("warning: retrying\n\nfatal: no route\n\n", "fallback") === "fatal: no route",
            "lastNonEmptyLine skips trailing blank lines")
        root._check(SafeText.lastNonEmptyLine("fatal: no route\n\u202E\u0000\n", "fallback") === "fatal: no route"
                && SafeText.lastNonEmptyLine("\u202E\u0000", "fallback") === "fallback",
            "error summaries skip lines that become empty after sanitizing control characters")
        root._check(SafeText.lastNonEmptyLine("old\r\n  failed\r\n\t\r\n", "fallback") === "failed"
                && SafeText.lastNonEmptyLine("failed", "fallback") === "failed",
            "error summaries preserve Windows line endings and an unterminated final line")
        root._check(SafeText.lastNonEmptyLine("noise\n".repeat(10000) + "final failure\n", "fallback") === "final failure",
            "a long tool log still reports its final non-empty error")
        root._check(SafeText.lastNonEmptyLine("", "fallback") === "fallback"
                && SafeText.lastNonEmptyLine("   \n  \n", "fallback") === "fallback",
            "lastNonEmptyLine falls back on blank output")
    }

    function _checksWindowTitle(): void {
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
            titleWidget.layoutWidthLimit = 32
            root._check(titleWidget._naturalWidth <= 32 && titleWidget.preferredWidth > 32
                    && titleWidget._spokenText.length > 0,
                "a crowded title elides to its layout budget while retaining its natural width and accessible text")
            titleWidget.layoutWidthLimit = 0
            root._check(titleWidget._naturalWidth === 0 && titleWidget._measuredContentWidth === 0,
                "a title can yield all of its space without retaining padding over adjacent controls")
            titleWidget.barActive = false
        root._check(!titleWidget._widthGlide._motionAllowed && !titleWidget._widthGlide.running,
            "a title under the overview does not run its per-frame width glide")
        titleWidget.barActive = true
        // as in a bar slot: the slot hides with the title, and hiding stops the glide
        const reduceWas = ShellSettings.reduceMotion
        ShellSettings.reduceMotion = false
        const slot = Qt.createQmlObject("import QtQuick; Item { property Item title: null; visible: title !== null && title.layoutVisible }", barFixtureHost)
        titleWidget.layoutWidthLimit = -1
        titleWidget.parent = slot
        slot.title = titleWidget
        titleWidget._shownVisible = true
        titleWidget._shownShowApp = false
        titleWidget._shownTitle = "A title on its way out"
        titleWidget._widthGlide._snap()
        titleWidget._op = 0
        titleWidget._shownTitle = ""
        const glide = titleWidget._widthGlide
        for (let i = 0; i < 200 && glide.running; i++) glide._advance(0.016)
        root._check(glide.value === 0 && titleWidget.implicitWidth === 0 && !slot.visible,
            "a title gliding shut ends at zero width instead of stopping a fraction short when its slot hides")
        titleWidget._shownTitle = "A title on its way out"
        glide._snap()
        titleWidget._shownTitle = ""
        glide._advance(0.016)
        const midway = glide.running && glide.value > 0.5 && slot.visible
        ShellSettings.reduceMotion = true
        root._check(midway && !glide.running && glide.value === 0 && titleWidget.implicitWidth === 0 && !slot.visible,
            "Reduce motion switched on while a title glides shut ends the glide at zero as its slot hides")
        ShellSettings.reduceMotion = reduceWas
        titleWidget.destroy()
        slot.destroy()
        {
            // first: switching it on settles the title back onto the compositor's
            ShellSettings.reduceMotion = true
            const host = keyboardFixtureFactory.createObject(root)
            const cut = windowTitleFactory.createObject(host.contentItem, { widthBudget: 10000, barActive: true, y: 200 })
            cut.layoutWidthLimit = 120
            cut._shownVisible = true
            cut._shownShowApp = false
            cut._shownTitle = "A window title far too long for the bar to show it whole"
            cut._widthGlide._snap()
            cut._op = 1
            const drawn = root._findTrayNode(cut, item => item.textFormat === Text.StyledText)
            host.requestActivate()
            host.input.mouseMove(cut, 30, cut.height / 2)
            const end = drawn && drawn.elide === Text.ElideLeft && !cut._marqueeLive
            host.input.mouseMove(host.contentItem, 400, 20)
            const start = drawn && drawn.elide === Text.ElideRight
            root._check(cut._overflow > 2 && end && start,
                "under Reduce motion a cut-short title shows its end under the pointer instead of scrolling, and its start again after")
            ShellSettings.reduceMotion = reduceWas
            cut.destroy()
            host.destroy()
        }
        }
        {
            const fontWas = ShellSettings.fontFamily
            ShellSettings.fontFamily = "DejaVu Sans"
            const glyphTitle = windowTitleFactory.createObject(root, { widthBudget: 10000 })
            glyphTitle._shownVisible = true
            glyphTitle._shownShowApp = false
            glyphTitle._shownTitle = "\uF489 notes.md in a project"
            const drawn = root._findTrayNode(glyphTitle, item => item.textFormat === Text.StyledText)
            root._check(Settings.font !== Settings.iconFont && drawn !== null
                    && Math.abs(glyphTitle._fullTextWidth - Math.ceil(drawn.implicitWidth)) <= 1,
                "a title carrying an icon glyph is measured in the font it is drawn in, so it elides only where it overflows")
            glyphTitle.destroy()
            ShellSettings.fontFamily = fontWas
        }
    }

    function _checksMediaWidgetAndTime(): void {
        const mediaComponent = Qt.createComponent("modules/bar/widgets/MediaWidget.qml")
        const mediaShownWas = Media.shown
        const showMediaWas = ShellSettings.barShowMedia
        const helperWas = ShellSettings.mediaWidgetHelper
        const mediaReduceWas = ShellSettings.reduceMotion
        ShellSettings.reduceMotion = true
        ShellSettings.barShowMedia = true
        ShellSettings.mediaWidgetHelper = true
        Media.shown = true
        const mediaWidget = mediaComponent.createObject(barFixtureHost, { height: 36 })
        root._check(mediaWidget !== null, "the media widget builds for crowded layout checks")
        if (mediaWidget) {
            const clip = root._findTrayNode(mediaWidget, item => item.preferredMaxW !== undefined)
            const contentRow = mediaWidget.children.find(item => typeof item.forceLayout === "function")
            clip._shown = "A long track title for a crowded bar"
            contentRow.forceLayout()
            const preferred = mediaWidget.preferredWidth
            mediaWidget.layoutWidthLimit = 48
            contentRow.forceLayout()
            root._check(mediaWidget.implicitWidth > 0 && mediaWidget.implicitWidth <= 48
                    && mediaWidget.preferredWidth === preferred
                    && clip.width <= 48 - mediaWidget._contentOverhead,
                "media text contracts around its play control without feeding the fitted width back into measurement")
            mediaWidget.layoutWidthLimit = 0
            contentRow.forceLayout()
            root._check(mediaWidget.implicitWidth === 0 && clip.width === 0,
                "a media widget with no layout room keeps nonnegative clipped geometry")
            mediaWidget.layoutWidthLimit = -1
            contentRow.forceLayout()
            root._check(clip.width > 0
                    && Math.abs(contentRow.implicitWidth + mediaWidget._pillPad * 2 - preferred) < 1,
                "removing a media layout limit restores the preferred text space")
            mediaWidget.layoutWidthLimit = 0
            contentRow.forceLayout()
            ShellSettings.reduceMotion = false
            root._check(!clip.needsScroll,
                "a fully squeezed-out media label runs no invisible marquee animation")
            // as when a neighbour's glide narrows the fit limit on every frame of a crowded bar
            const mediaGlide = mediaWidget.data.find(item => item._advance !== undefined)
            const squeezeStart = Math.floor(preferred) - 4
            mediaWidget.layoutWidthLimit = squeezeStart
            contentRow.forceLayout()
            mediaGlide?._snap()
            const squeezeFrom = mediaWidget.implicitWidth
            let followed = 0
            for (let i = 1; i <= 10; i++) {
                const before = mediaWidget.implicitWidth
                mediaWidget.layoutWidthLimit = squeezeStart - i * 6
                contentRow.forceLayout()
                mediaGlide?._advance(0.016)
                if (mediaWidget.implicitWidth < before) followed++
            }
            root._check(mediaGlide !== undefined && squeezeFrom === squeezeStart && followed === 10
                    && mediaWidget.implicitWidth >= squeezeStart - 60,
                "a media title follows a fit limit that moves on every frame, rather than holding until it stops")
            mediaWidget.destroy()
        }
        mediaComponent.destroy()
        Media.shown = mediaShownWas
        ShellSettings.barShowMedia = showMediaWas
        ShellSettings.mediaWidgetHelper = helperWas
        ShellSettings.reduceMotion = mediaReduceWas

        const longMediaText = "m".repeat(Media.maxMetadataChars + 20)
        root._check(SafeText.singleLineText(longMediaText, Media.maxMetadataChars).length
                === Media.maxMetadataChars,
            "media service bounds player metadata")
        root._check(Media.artSource("data:image/png;base64,AAAA") === "",
            "media service rejects inline artwork data")
        const remoteArtWas = ShellSettings.mediaRemoteArt
        root._check(!Media.artDemand(true, true, false, false, false)
                && !Media.artDemand(true, false, true, false, false),
            "a closed menu does not download covers for the bar's text-only media widget")
        root._check(Media.artDemand(true, true, false, true, false)
                && Media.artDemand(true, false, true, true, false),
            "a visible media rail or Now Playing page resumes cover fetching")
        root._check(!Media.artDemand(true, false, false, true, false),
            "an open menu with no visible cover leaves artwork downloads asleep")
        root._check(!Media.artDemand(true, true, true, true, true)
                && !Media.artDemand(false, true, true, true, false),
            "quiet idle and an absent player suspend cover requests")
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
        const artMissesWas = Media._artMisses
        const artRetryWas = Media._artRetryPending
        const unrelatedArt = "https://example.invalid/old-track.jpg"
        Media._artMisses = { [wantedArt[0]]: true, [wantedArt[1]]: true, [unrelatedArt]: true }
        root._check(Media._clearArtMisses(wantedArt)
                && Media.nextArtFetch(wantedArt, {}, Media._artMisses) === wantedArt[0]
                && Media._artMisses[unrelatedArt] === true,
            "an artwork retry reopens the current cover without retrying unrelated dead URLs")
        root._check(!Media._clearArtMisses(wantedArt) && !Media._clearArtMisses([]),
            "an artwork retry with no relevant misses leaves the cache unchanged")
        Media._artRetryPending = true
        Media._artFetched(wantedArt[0], false)
        Media._finishArtRetry(wantedArt)
        root._check(!Media._artRetryPending
                && Media.nextArtFetch(wantedArt, {}, Media._artMisses) === wantedArt[0]
                && Media._artMisses[unrelatedArt] === true,
            "a reconnect during a failing download retains its retry until after the failure is recorded")
        Media._artMisses = { [wantedArt[0]]: true }
        Media._finishArtRetry(wantedArt)
        root._check(Media._artMisses[wantedArt[0]] === true,
            "a consumed artwork retry does not reopen the same failed URL repeatedly")
        const artFetch = Media._artDownload
        root._check(artFetch !== null && !artFetch.running,
            "the internet recovery fixture finds an idle artwork downloader")
        if (artFetch && !artFetch.running) {
            const commandWas = artFetch.command
            const issueWas = Network.connectivityIssue
            ShellSettings.mediaRemoteArt = true
            artFetch.exec(["sleep", "2"])
            for (const issue of ["portal", "limited"]) {
                Media._artRetryPending = false
                Network.connectivityIssue = issue
                root._check(!Media._artRetryPending,
                    "an internet issue does not retry an artwork request: " + issue)
                Network.connectivityIssue = ""
                root._check(Media._artRetryPending === Network.connected,
                    "internet recovery queues an artwork retry even during a download: " + issue)
            }
            Network.connectivityIssue = issueWas
            artFetch.running = false
            artFetch.command = commandWas
            ShellSettings.mediaRemoteArt = remoteArtWas
        }
        Media._artMisses = artMissesWas
        Media._artFiles = artFilesWas
        Media._artRetryPending = artRetryWas
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
        root._check(["eco", "balanced", "smooth", "nonsense"].every(p => {
                    const v = Media.vizNoiseReduction(p)
                    return Number.isInteger(v) && v > 10 && v <= 100
                })
                && Media.vizNoiseReduction("eco") > Media.vizNoiseReduction("balanced")
                && Media.vizNoiseReduction("balanced") > Media.vizNoiseReduction("smooth")
                && Media._cavaConfigText.includes("noise_reduction = " + Media.vizNoiseReduction(Media._vizPreset) + "\n"),
            "cava smoothing is a percentage above the falloff floor, calmest on Eco")
        root._check(Media._cavaConfigText.includes("method = pipewire")
                && Media._cavaConfigText.includes("method = raw")
                && Media._cavaConfigText.includes("data_format = ascii")
                && Media._cavaConfigText.includes("ascii_max_range = " + Media._cavaRange),
            "media service emits a valid bounded Cava raw-output profile")
        root._check(Media.vizLevel(0, 64) === 0 && Media.vizLevel(64, 64) === 1
                && Media.vizLevel(99, 64) === 1 && Media.vizLevel(-3, 64) === 0
                && Media.vizLevel(NaN, 64) === 0 && Media.vizLevel(10, 0) === 0,
            "visualizer levels stay inside the bar for any cava value")
        root._check(Media.vizLevel(10, 64) > 0.3 && Media.vizLevel(1, 64) < 0.1,
            "a typical cava band reads as a third of the bar while the first step stays small")
        root._check(Media.vizDensity("underline") === 4 && Media.vizDensity("center") === 2
                && Media.vizDensity("media") === 1 && Media.vizDensity("nonsense") === 1,
            "wider visualizer positions get proportionally more bars")
        root._check(Media.vizPresetFor("smooth", true) === "eco"
                && Media.vizPresetFor("smooth", false) === "smooth"
                && Media.vizPresetFor("eco", true) === "eco",
            "the visualizer runs at Eco on battery and keeps the chosen preset on the charger")
        root._check(Media.finiteNonnegative(NaN) === 0
                && Media.finiteNonnegative(Infinity) === 0
                && Media.finiteNonnegative(12.5) === 12.5,
            "media service normalizes non-finite timing metadata")
        root._check(Media.positionDemand(false, true, false)
                && !Media.positionDemand(false, true, true)
                && Media.positionDemand(true, false, true),
            "media progress pauses with a concealed bar but stays live for the menu")
        root._check(Media.formatElapsed(66, 3725) === "0:01:06"
                && Media.formatElapsed(600, 3725) === "0:10:00"
                && Media.formatElapsed(3725, 3725) === "1:02:05"
                && Media.formatElapsed(136, 302) === "2:16"
                && Media.formatElapsed(NaN, 0) === "0:00",
            "elapsed time takes the total's shape so both ends of the seek bar match")
        root._check(Media.formatRemaining(64.9, 485.4) === "\u22127:01"
                && Media.formatRemaining(66, 3725) === "\u22121:00:59"
                && Media.formatRemaining(9999, 302) === "\u22120:00"
                && Media.formatElapsed(64.9, 485.4) === "1:04",
            "the time left and the elapsed time add up to the length shown, and never run below zero")
    }

    function _checksNowPlayingAndHomeDisplays(): void {
        // Now Playing loads by url as Settings and History do, and the menu's reload page reads this for all three
        const brokenPage = pageLoaderFactory.createObject(root)
        const loadedClean = brokenPage !== null && brokenPage.status === Loader.Ready && brokenPage.failed === false
        if (brokenPage) brokenPage.source = "modules/menu/no-such-page.qml"
        root._check(loadedClean && brokenPage.status === Loader.Error && brokenPage.failed === true,
            "a page loader reports a page that failed to load, and not one that loaded")
        if (brokenPage) brokenPage.destroy()
        const mediaPageComponent = Qt.createComponent("modules/menu/MediaPage.qml")
        const mediaPage = mediaPageComponent.status === Component.Ready
            ? mediaPageComponent.createObject(root, { width: 332, active: false, powerOpen: false }) : null
        root._check(mediaPage !== null && mediaPage.implicitHeight > 332,
            "the now playing page builds around a full-width cover")
        const barsWas = Media.barHeights
        Media.barHeights = [0.4, 0.6]
        root._check(Media.loudness() === -1 && mediaPage !== null && !mediaPage._swellClient
                && mediaPage.swellLevel() === -1,
            "with cava stopped a leftover frame is no reading for the seek wave, and the page holds no visualizer client")
        Media.barHeights = barsWas
        if (mediaPage) {
            const tabWas = MenuState.activeTab
            const openWas = MenuState.open
            const motionWas = ShellSettings.reduceMotion
            ShellSettings.reduceMotion = false
            MenuState.selectTab(MenuState.mediaTab)
            MenuState.open = true
            mediaPage.active = true
            const textSwap = mediaPage.data.find(item => item.animations?.length === 3)
            const playGlyph = root._findTrayNode(mediaPage, item => item.target !== undefined
                && item.shown !== undefined && item._ready !== undefined)
            const playStamp = playGlyph?.data.find(item => item.animations?.length === 3)
            root._check(mediaPage._coverWanted && textSwap && playStamp,
                "an active now playing page requests its cover and exposes its playback animations")
            if (textSwap && playStamp) {
                textSwap.restart()
                playStamp.restart()
                root._check(textSwap.running && playStamp.running,
                    "the media motion probe begins with active animation work")
                mediaPage.active = false
                root._check(!textSwap.running && !playStamp.running
                        && mediaPage._textOpacity === 1 && mediaPage._textSlide === 0
                        && playGlyph.scale === 1 && playGlyph.shown === playGlyph.target,
                    "leaving now playing stops ongoing animations and settles the current playback icon")
                root._check(!mediaPage._coverWanted,
                    "a departing media page stops cover decoding and retries")
            }
            // a running scroll stands in for the hover
            const titleClip = root._findTrayNode(mediaPage, item => item._slideMs !== undefined)
            const titleScroll = titleClip ? titleClip.data.find(item => item.animations?.length === 4) : null
            const titleText = titleClip ? root._findTrayNode(titleClip, item => item._unrolled !== undefined) : null
            let titleRestarts = 0
            const noteRestart = () => { if (titleScroll.running) titleRestarts++ }
            if (titleScroll && titleText) {
                mediaPage._shownTitle = "A long title that scrolls ".repeat(6)
                titleScroll.running = true
                titleScroll.runningChanged.connect(noteRestart)
                titleText.x = -60
                mediaPage._shownTitle = "The next long title ".repeat(4)
                titleScroll.runningChanged.disconnect(noteRestart)
            }
            root._check(titleScroll && titleText && titleText.x === 0 && titleScroll.running && titleRestarts > 0,
                "a track change mid-scroll starts the new title's scroll over from its first letter")
            mediaPage.settleVisuals()
            const host = keyboardFixtureFactory.createObject(root)
            mediaPage.parent = host.contentItem
            ShellSettings.reduceMotion = true
            mediaPage.active = true
            mediaPage.settleVisual(true)
            const openPlayer = root._findTrayNode(mediaPage,
                item => item.Accessible.name.indexOf("Open ") === 0)
            root._check(openPlayer !== null, "the media page exposes its open-player action")
            if (openPlayer) {
                // Reveal the real control without requiring a player on the desktop's bus.
                openPlayer.visible = true
                host.requestActivate()
                host.input.wait(10)
                const previous = openPlayer.nextItemInFocusChain(false)
                previous.forceActiveFocus(Qt.TabFocusReason)
                host.input.keyClick(Qt.Key_Tab)
                root._check(openPlayer.Accessible.focusable && openPlayer.activeFocusOnTab && openPlayer.activeFocus,
                    "Tab reaches the media page's open-player action")
                MenuState.close()
                host.input.wait(10)
                root._check(!openPlayer.Accessible.focusable && !openPlayer.activeFocusOnTab && !openPlayer.activeFocus,
                    "closing the menu releases its open-player keyboard focus")
                MenuState.open = true
                mediaPage.active = false
                openPlayer.Accessible.pressAction()
                host.input.wait(10)
                root._check(!openPlayer.Accessible.focusable && !openPlayer.activeFocusOnTab && !openPlayer.activeFocus,
                    "leaving the media page releases its open-player keyboard focus")
                root._check(MenuState.open,
                    "a stale open-player accessibility action cannot close the menu from an inactive page")
            }
            mediaPage.parent = null
            host.close()
            host.destroy()
            ShellSettings.reduceMotion = motionWas
            MenuState.selectTab(tabWas)
            MenuState.open = openWas
            mediaPage.destroy()
        }
        const homeComponent = Qt.createComponent("modules/menu/HomePage.qml")
        const home = homeComponent.status === Component.Ready
            ? homeComponent.createObject(root, { width: 332, active: false, powerOpen: false }) : null
        root._check(home !== null && home.implicitHeight > 0,
            "the home page builds as one column")
        if (home) {
            const host = keyboardFixtureFactory.createObject(root)
            home.parent = host.contentItem
            const vpn = root._findTrayNode(home, item => item.title === "VPN" && item.expandable !== undefined)
            const addressWas = Network.vpnAddress
            Network.vpnAddress = ""
            home.active = true
            home.settleVisual(true)
            if (vpn) {
                // The fixture has no NetworkManager; reveal its connectivity group explicitly.
                for (let item = vpn; item && item !== home; item = item.parent) item.visible = true
                vpn.expandable = true
                vpn.Accessible.pressAction()
            }
            root._check(vpn && vpn._canTap && home._picker === "vpn",
                "the disconnected VPN row opens its saved-profile picker through the normal action")
            root._checkHomeWidgetPickers(home)
            Network.vpnAddress = addressWas
            const keyboardErrorWas = KeyboardBrightness._readError
            const backlightWas = Brightness.ready
            const externalWas = DisplayBrightness.displays
            Brightness.ready = false
            DisplayBrightness.displays = []
            KeyboardBrightness._readError = ""
            const displayHidden = !home._displayShown
            const ddcOffWas = ShellSettings.ddcDisabledDisplays
            const ddcKey = "card1-DP-1:" + "a".repeat(64)
            DisplayBrightness.displays = [{ key: ddcKey, connector: "card1-DP-1", label: "DP-1", bus: "7",
                identity: "a".repeat(64), unreadable: false, percent: 50 }]
            const ddcShown = home._displayShown
            ShellSettings.ddcDisabledDisplays = ddcKey
            const ddcOffHidden = !home._displayShown
            ShellSettings.ddcDisabledDisplays = ddcOffWas
            DisplayBrightness.displays = []
            root._check(displayHidden && ddcShown && ddcOffHidden,
                "Home's display group counts an external display only while its slider shows")
            KeyboardBrightness._readError = "Could not read keyboard lighting. Check UPower."
            const keyboardHint = root._findTrayNode(home, item => item.text === KeyboardBrightness._readError
                && item.textColor !== undefined)
            root._check(displayHidden && !KeyboardBrightness.ready && home._displayShown
                    && keyboardHint !== null && keyboardHint.visible,
                "a keyboard light that cannot be read keeps Home's display group and shows its error there")
            KeyboardBrightness._readError = keyboardErrorWas
            DisplayBrightness.displays = externalWas
            Brightness.ready = backlightWas
            // a wired desktop with no Bluetooth and no saved VPN: the VPN row waits for a profile, so the card has no row
            const vpnWas = { profiles: Vpn.profiles, list: Vpn._listError, action: Vpn._actionError }
            home._wifiAvailable = false
            home._btAvailable = false
            Vpn.profiles = []
            Vpn._listError = ""
            Vpn._actionError = ""
            const cardHasRow = Network.hasVpn || home._signInShown
            const emptyHidden = home._connShown === cardHasRow && home._vpnShown === Network.hasVpn
            Vpn.profiles = [{ uuid: "probe-uuid", name: "Probe VPN", active: false }]
            const savedShown = home._connShown === (cardHasRow || Vpn.available) && home._vpnShown === home._connShown
            Vpn.profiles = vpnWas.profiles
            Vpn._listError = vpnWas.list
            Vpn._actionError = vpnWas.action
            root._check(emptyHidden && savedShown,
                "Home's Connectivity card shows only while one of its rows does: a VPN list that could be read is not a row")
            home._wifiAvailable = true
            home._togglePicker("wifi")
            home._wifiAvailable = false
            const wifiPickerGone = home._picker === ""
            home._togglePicker("vpn")
            if (vpn) vpn.expandable = false
            root._check(wifiPickerGone && vpn && home._picker === "",
                "Home's Wi-Fi and VPN pickers close when their adapter or NetworkManager goes away")
            const vpnStateWas = Network._vpnState
            Vpn.profiles = []
            Vpn._listError = ""
            Vpn._actionError = ""
            Network._vpnState = ({ active: true, name: "probe VPN", uuid: "" })
            home._togglePicker("vpn")
            const vpnPickerOpen = home._picker === "vpn"
            Network._vpnState = ({ active: false, name: "", uuid: "" })
            root._check(vpnPickerOpen && home._picker === "",
                "Home's VPN picker closes with its row when the tunnel goes and no saved profile is left")
            Network._vpnState = vpnStateWas
            Vpn.profiles = vpnWas.profiles
            Vpn._listError = vpnWas.list
            Vpn._actionError = vpnWas.action
            home.destroy()
            host.close()
            host.destroy()
        }

        // the backlight choices name what they choose, as the output and input choices beside them do
        const backlightsWas = Brightness.devices
        const backlightReduceWas = ShellSettings.reduceMotion
        ShellSettings.reduceMotion = true
        Brightness.devices = [{ name: "__silere_probe_panel__" }, { name: "__silere_probe_dock__" }]
        const brightnessRow = Qt.createComponent(Qt.resolvedUrl("modules/menu/BrightnessRow.qml"))
            .createObject(barFixtureHost, { width: 320, open: true })
        const backlightChoice = root._findTrayNode(brightnessRow, item => item.accessiblePrefix !== undefined
            && item.label === "__silere_probe_dock__")
        root._check(backlightChoice !== null
                && backlightChoice.Accessible.name === "Brightness display: __silere_probe_dock__"
                && backlightChoice.Accessible.role === Accessible.RadioButton && backlightChoice.Accessible.checkable,
            "a backlight choice on Home is announced as a named, checkable choice")
        if (brightnessRow) brightnessRow.destroy()
        Brightness.devices = backlightsWas
        ShellSettings.reduceMotion = backlightReduceWas
    }

    function _checksRailWavesAndAudioRoutes(): void {
        root._check(MenuState.tabPosition(MenuState.mediaTab) === 3
                && MenuState._validTab(MenuState.mediaTab) === MenuState.mediaTab
                && MenuState.mediaActive === (MenuState.open && MenuState.activeTab === MenuState.mediaTab)
                && Media.positionDemand(true, false, true) && !Media.positionDemand(false, false, false),
            "the now playing page sits after Settings in the rail and keeps the seek bar live while shown")
        const waveComponent = Qt.createComponent("modules/common/WaveLine.qml")
        const shortWave = waveComponent.status === Component.Ready
            ? waveComponent.createObject(root, { width: 120, height: 10, value: 0.06 }) : null
        const longWave = waveComponent.status === Component.Ready
            ? waveComponent.createObject(root, { width: 120, height: 10, value: 0.9 }) : null
        root._check(shortWave !== null && shortWave._path.length > 0 && shortWave._amp === 0
                && longWave !== null && longWave._amp > 0 && longWave._path.indexOf(" C ") > 0
                && longWave._endX <= 120 * 0.9,
            "a wave level stays flat while shorter than a wavelength and never runs past its level")
        if (shortWave && longWave) {
            const reduceWas = ShellSettings.reduceMotion
            ShellSettings.reduceMotion = false
            shortWave.flowing = true
            longWave.flowing = true
            root._check(!shortWave._flowing && shortWave._path.includes(" H ")
                    && longWave._flowing,
                "flat short waves use a line and do not wake a flow timer")
            longWave.flowMs = 0
            root._check(!longWave._flowing,
                "a zero wave period stops flow instead of dividing by zero")
            longWave.flowMs = 1600
            longWave.visible = false
            root._check(!longWave._flowing, "a concealed wave stops its flow timer")
            longWave.visible = true
            longWave.reveal = 0
            root._check(!longWave._flowing, "an unrevealed wave does not keep ticking")
            longWave.reveal = 1
            ShellSettings.reduceMotion = true
            root._check(!longWave._flowing, "reduced motion stops a running wave")
            longWave.amplitude = 0
            root._check(longWave._path.includes(" H ") && !longWave._path.includes(" C "),
                "a paused flat wave uses one straight segment")
            longWave.wavelength = 0
            root._check(isFinite(longWave._amp) && !longWave._path.includes("NaN"),
                "a zero wavelength keeps the wave geometry finite")
            ShellSettings.reduceMotion = reduceWas
        }
        if (shortWave) shortWave.destroy()
        if (longWave) longWave.destroy()
        const swellWave = waveComponent.status === Component.Ready
            ? waveComponent.createObject(root, { width: 160, height: 12, value: 0.9, amplitude: 2.5 }) : null
        if (swellWave) {
            const peak = () => Math.max(...swellWave._path.match(/-?\d+(?:\.\d+)?/g).map(Number)
                .filter((v, i) => i % 2 === 1).map(y => Math.abs(y - swellWave.height / 2)))
            const rest = swellWave.swellFactor()
            let level = 1
            swellWave.swellSource = () => level
            for (let i = 0; i < 20; i++) swellWave._step()
            const loud = swellWave.swellFactor(), loudPeak = peak()
            level = 0
            for (let i = 0; i < 20; i++) swellWave._step()
            const quiet = swellWave.swellFactor(), quietPeak = peak()
            level = -1
            for (let i = 0; i < 40; i++) swellWave._step()
            const unknown = swellWave.swellFactor()
            swellWave.swellSource = null
            root._check(rest === 1 && loud > 1.3 && loud <= 1.45 && quiet >= 0.55 && quiet < 0.65
                    && loudPeak > quietPeak * 1.5 && loudPeak + swellWave.thickness / 2 <= swellWave.height / 2
                    && Math.abs(unknown - 1) < 0.02 && swellWave.swellFactor() === 1,
                "a seek wave swells with the music's level inside its own height, settles without a reading, and rests without a source")
            swellWave.destroy()
        }
        const L = Mp.MprisLoopState
        root._check(Media.nextLoopState(L.None) === L.Playlist
                && Media.nextLoopState(L.Playlist) === L.Track
                && Media.nextLoopState(L.Track) === L.None,
            "repeat cycles off, all, then one track")
        const firstMember = stableListMemberFactory.createObject(root)
        const secondMember = stableListMemberFactory.createObject(root)
        const stablePlayers = stableObjectListFactory.createObject(root, {
            source: [firstMember, secondMember]
        })
        const listObserver = stableListObserverFactory.createObject(root, { model: stablePlayers })
        const originalPlayers = stablePlayers.values
        let listChanges = 0
        const noteListChange = () => listChanges++
        stablePlayers.valuesChanged.connect(noteListChange)
        for (let i = 0; i < 1000; i++) stablePlayers.source = [firstMember, secondMember]
        root._check(stablePlayers.values === originalPlayers && listChanges === 0,
            "a thousand unchanged player lists preserve one model snapshot without rebuilding rows")
        firstMember.playing = true
        root._check(listObserver.playingCount === 1 && listChanges === 0,
            "player properties still update consumers without replacing the stable list")
        stablePlayers.source = [secondMember, firstMember]
        root._check(stablePlayers.values[0] === secondMember && listChanges === 1,
            "reordering players publishes exactly one new model snapshot")
        const replacementMember = stableListMemberFactory.createObject(root)
        stablePlayers.source = [secondMember, replacementMember]
        root._check(stablePlayers.values[1] === replacementMember && listChanges === 2
                && listObserver.playingCount === 0,
            "a replacement player updates the model even when its count stays unchanged")
        const mutablePlayers = [firstMember]
        stablePlayers.source = mutablePlayers
        mutablePlayers.push(secondMember)
        root._check(stablePlayers.values.length === 1,
            "a caller's mutation cannot silently change a published player list")
        stablePlayers.sync()
        root._check(stablePlayers.values.length === 2 && listChanges === 4,
            "explicit synchronization publishes an in-place source mutation once")
        stablePlayers.source = null
        root._check(stablePlayers.values.length === 0 && listChanges === 5,
            "an absent player source clears the model")
        stablePlayers.source = []
        root._check(listChanges === 5, "an unchanged empty player list produces no notification")
        stablePlayers.valuesChanged.disconnect(noteListChange)
        listObserver.destroy()
        stablePlayers.destroy()
        firstMember.destroy()
        secondMember.destroy()
        replacementMember.destroy()
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
        const pausedState = Mp.MprisPlaybackState.Paused, playingState = Mp.MprisPlaybackState.Playing
        const music = { dbusName: "music", isPlaying: false, playbackState: pausedState }
        const video = { dbusName: "video", isPlaying: false, playbackState: pausedState }
        const radio = { dbusName: "radio", isPlaying: true, playbackState: playingState }
        const stream = { dbusName: "stream", isPlaying: true, playbackState: playingState }
        root._check(Media.pickPlayer([music, video], "", {}) === music
                && Media.pickPlayer([music, video], "", { music: 1, video: 2 }) === video
                && Media.pickPlayer([music, radio], "", { music: 5, radio: 1 }) === radio
                && Media.pickPlayer([radio, stream], "", { radio: 1, stream: 2 }) === stream
                && Media.pickPlayer([radio, video], "video", {}) === video
                && Media.pickPlayer([null, loadedPlayer], "", {}) === loadedPlayer,
            "the media card follows the most recently active player, like the media keys, unless one is pinned")
        root._check(Audio._out._clampVolume(NaN) === 0
                && Audio._out._clampVolume(Infinity) === 0
                && Audio._out._clampVolume(1.5) === 1,
            "audio service normalizes non-finite backend volume")
        const volumeControl = volumeControlFactory.createObject(root)
        volumeControl._wpctl.command = ["sleep", "5"]
        volumeControl._wpctl.running = true
        volumeControl._wpctlAgain = true
        volumeControl._wpctlGap.start()
        volumeControl.pendingApply = true
        volumeControl.sync()
        root._check(!volumeControl._wpctlAgain && !volumeControl._wpctlGap.running
                && !volumeControl.pendingApply,
            "resynchronizing audio cancels the old route's process and queued fallback writes")
        root._volumeCancelProbe = volumeControl
        root._volumeCancelDeadline = Date.now() + 1000
        _volumeCancelCheck.restart()
    }

    function _checksAudioAndSliders(): void {
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
        const btSink = profile => ({ description: "Q45", isSink: true,
            properties: { "api.bluez5.profile": profile } })
        root._check(Audio.sinkLabel(btSink("headset-head-unit")) === "Q45 · Call mode"
                && Audio.sinkLabel(btSink("a2dp-sink")) === "Q45"
                && Audio.sinkLabel({ description: "Q45", isSink: false,
                    properties: { "api.bluez5.profile": "headset-head-unit" } }) === "Q45"
                && Audio.sinkLabel({ description: "Speakers" }) === "Speakers",
            "a bluetooth output on its hands-free profile is named as call mode, a microphone never is")
        const alsa = (desc, profile) => ({ description: desc, isSink: true,
            properties: { "device.profile.description": profile } })
        const analog = alsa("Ryzen HD Audio Controller Analog Stereo", "Analog Stereo")
        const digital = alsa("Ryzen HD Audio Controller Digital Stereo (IEC958)", "Digital Stereo (IEC958)")
        root._check(Audio.sinkLabel(analog, [analog]) === "Ryzen HD Audio Controller"
                && Audio.sinkLabel(alsa("Analog Stereo", "Analog Stereo"), []) === "Analog Stereo",
            "an ALSA output drops its profile from its name")
        root._check(Audio.sinkLabel(analog, [analog, digital]) === "Ryzen HD Audio Controller Analog Stereo"
                && Audio.sinkLabel(digital, [analog, digital]) === "Ryzen HD Audio Controller Digital Stereo (IEC958)",
            "two outputs of one card keep their profiles so they stay apart")

        const audioStatus = JSON.parse(Audio._ipc.status())
        root._check(audioStatus.output.ready === Audio.ready
                && audioStatus.input.ready === Audio.micReady
                && audioStatus.output.name === Audio.sinkName
                && audioStatus.input.name === Audio.sourceName
                && audioStatus.output.volume >= 0 && audioStatus.output.volume <= 100
                && audioStatus.input.volume >= 0 && audioStatus.input.volume <= 100,
            "audio IPC reports bounded output and microphone state without opening a surface")
        const audioVolumeWas = Audio._out.targetVolume
        const micVolumeWas = Audio._in.targetVolume
        const headsetProfiles = [{ id: 77, type: "PipeWire:Interface:Device", info: { params: {
            EnumProfile: [{ index: 1, name: "a2dp-sink", priority: 10 },
                { index: 2, name: "a2dp-sink-sbc_xq", priority: 20 },
                { index: 3, name: "headset-head-unit", priority: 1 },
                { index: 4, name: "headset-head-unit-msbc", priority: 2 },
                { index: 5, name: "headset-head-unit", priority: 50, available: "no" },
                { index: -1, name: "a2dp-sink", priority: 100 },
                { index: "9", name: "a2dp-sink", priority: 100 }], Profile: [{ index: 1 }]
        } } }]
        const headsetModes = AudioMode.profilesFor(headsetProfiles, "77")
        root._check(headsetModes.listening === 2 && headsetModes.calls === 4 && headsetModes.active === "listening"
                && AudioMode.profilesFor(headsetProfiles, "78").calls === -1
                && AudioMode.profilesFor({}, "77").listening === -1,
            "headset mode discovery prefers supported profiles and rejects malformed indices or another device")
        root._check(AudioMode.kindOf("bap-sink") === "listening" && AudioMode.kindOf("bap-duplex") === "calls"
                && AudioMode.kindOf("off") === ""
                && AudioMode.deviceId({ ready: true, properties: { "device.api": "alsa", "device.id": 77 } }) === ""
                && AudioMode.deviceIdentity({ properties: { "api.bluez5.address": "AA_BB_CC_DD_EE_FF" } }) === "aa:bb:cc:dd:ee:ff",
            "headset modes cover classic and LE Audio while limiting switching to identified Bluetooth devices")
        root._check(Audio.bluetoothAddress({ name: "bluez_output.F4_9D_8A_18_02_3B.1", properties: {} }) === "f4:9d:8a:18:02:3b"
                && Audio.bluetoothAddress({ name: "alsa_output.pci", properties: { "api.bluez5.address": "junk" } }) === ""
                && Audio.bluetoothAddress(null) === ""
                && Bluetooth.batteryForAddress("f4:9d:8a:18:02:3b", [
                    { address: "AA:BB:CC:DD:EE:FF", connected: true, batteryAvailable: true, battery: 0.9 },
                    { address: "F4:9D:8A:18:02:3B", connected: true, batteryAvailable: true, battery: 0.1 }]) === 10
                && Bluetooth.batteryForAddress("f4:9d:8a:18:02:3b", [
                    { address: "F4:9D:8A:18:02:3B", connected: false, batteryAvailable: true, battery: 0.1 }]) === -1
                && Bluetooth.batteryForAddress("", [{ address: "", connected: true, batteryAvailable: true, battery: 0.5 }]) === -1,
            "an output's charge comes from the connected Bluetooth device its sink names, and from no other")
        const dropped = (wasHeadset, wasName, nextName, nextHeadset, wasListed, switching) =>
            Audio.headphonesDropped(wasHeadset, wasName, nextName, nextHeadset, wasListed, switching)
        root._check(dropped(true, "bluez_output.AA_BB_CC_DD_EE_FF.1", "alsa_output.speaker", false, false, false)
                && !dropped(true, "bluez_output.AA_BB_CC_DD_EE_FF.1", "alsa_output.speaker", false, true, false)
                && !dropped(true, "bluez_output.AA_BB_CC_DD_EE_FF.1", "usb_headset", true, false, false)
                && !dropped(false, "alsa_output.hdmi", "alsa_output.speaker", false, false, false)
                && !dropped(true, "bluez_output.AA_BB_CC_DD_EE_FF.1", "alsa_output.speaker", false, false, true)
                && !dropped(true, "bluez_output.AA_BB_CC_DD_EE_FF.1", "bluez_output.AA_BB_CC_DD_EE_FF.1", false, false, false)
                && !dropped(true, "", "alsa_output.speaker", false, false, false),
            "only headphones that vanish for a non-headset output count as dropped, never a switch the user made or a mode change")
        root._check(Bluetooth.connectedDevice("aa:bb:cc:dd:ee:ff", [{ address: "AA:BB:CC:DD:EE:FF", connected: true }]) !== null
                && Bluetooth.connectedDevice("aa:bb:cc:dd:ee:ff", [{ address: "AA:BB:CC:DD:EE:FF", connected: false }]) === null
                && Bluetooth.connectedDevice("", [{ address: "", connected: true }]) === null,
            "a lost headset counts as gone once BlueZ no longer lists it connected")
        const pauseWas = ShellSettings.mediaPauseOnDisconnect
        const pauses = []
        const fakePlayer = (name, playing, canPause) => ({ dbusName: name, isPlaying: playing, canPause: canPause,
            pause: () => pauses.push(name) })
        const lostPlayers = [fakePlayer("org.mpris.MediaPlayer2.spotify", true, true),
            fakePlayer("org.mpris.MediaPlayer2.playerctld", true, true),
            fakePlayer("org.mpris.MediaPlayer2.firefox", false, true),
            fakePlayer("org.mpris.MediaPlayer2.stream", true, false)]
        ShellSettings.mediaPauseOnDisconnect = true
        const pausedOn = Audio.pauseForSpeakers(lostPlayers)
        const pausedNames = pauses.join(",")
        ShellSettings.mediaPauseOnDisconnect = false
        const pausedOff = Audio.pauseForSpeakers(lostPlayers)
        ShellSettings.mediaPauseOnDisconnect = pauseWas
        root._check(pausedOn === 1 && pausedNames === "org.mpris.MediaPlayer2.spotify" && pausedOff === 0 && pauses.length === 1
                && ShellSettings._defaults.mediaPauseOnDisconnect === true,
            "headphone loss pauses each playing player that can pause, not playerctld's mirror, and nothing once switched off")
        Audio.beginProfileSwitch()
        root._check(Audio.profileSwitching && !Audio._out.enabled && !Audio._in.enabled
                && Audio.ready === audioStatus.output.ready && Audio.sinkName === audioStatus.output.name,
            "headset switching preserves the presented audio state and suspends queued volume writes")
        Audio._profilePresentation = Object.assign({}, Audio._profilePresentation, { muted: true, volume: 0, effectiveVolume: 0.43 })
        root._check(JSON.parse(Audio._ipc.status()).output.volume === 43 && Audio.uiVolume === 0,
            "audio status preserves the remembered level while a muted headset changes modes")
        root._check([Audio._ipc.setVolume(50), Audio._ipc.volumeUp(), Audio._ipc.volumeDown(), Audio._ipc.toggleMute(),
                Audio._ipc.setMicVolume(50), Audio._ipc.micUp(), Audio._ipc.toggleMicMute(), Audio._ipc.cycleInput(),
                Audio._ipc.cycleOutput()].every(reply => reply === "error: audio device is changing"),
            "audio IPC rejects edits during a headset transition instead of targeting a temporary fallback")
        Audio.endProfileSwitch()
        Audio._releaseProfilePresentation()
        root._check(!Audio.profileSwitching && Audio._profilePresentation === null,
            "finishing a headset transition releases its temporary presentation state")
        root._check(Audio._out.needsWpctl({ "device.api": "alsa", "card.profile.device": "3" }, true, false)
                && Audio._out.needsWpctl({ "device.api": "bluez5" }, true, false)
                && !Audio._out.needsWpctl({ "device.api": "alsa", "card.profile.device": "3" }, true, true)
                && !Audio._out.needsWpctl({ "device.api": "alsa", "card.profile.device": "3" }, false, false)
                && !Audio._out.needsWpctl({ "application.name": "stream" }, true, false)
                && !Audio._out.needsWpctl(null, true, false),
            "volume on a card-routed or bluetooth node goes through wpctl only where quickshell 0.3.1 would drop the write")
        const keyboardRows = KeyboardBrightness.parseDevices("/org/freedesktop/UPower/KbdBacklight/led0\t0\t2\tfixture\n"
            + "/org/freedesktop/UPower/KbdBacklight/led1\t1\t0\tfixture\n"
            + "/org/freedesktop/UPower/KbdBacklight/led2\t3\t2\tfixture\n"
            + "/org/other\t1\t2\tfixture\n"
            + "/org/freedesktop/UPower/KbdBacklight/led3\t1\t2147483648\tfixture\n")
        root._check(keyboardRows.length === 1 && keyboardRows[0].level === 0 && keyboardRows[0].maximum === 2,
            "keyboard lighting accepts off and hides invalid or unsupported hardware levels")
        root._check(KeyboardBrightness.lightName('s "/sys/devices/platform/asus-nb-wmi/leds/asus::kbd_backlight"') === "asus"
                && KeyboardBrightness.lightName('s "tpacpi::kbd_backlight"') === "tpacpi"
                && KeyboardBrightness.lightName('s ":rgb:kbd_backlight"') === "rgb"
                && KeyboardBrightness.lightName('s ""') === "" && KeyboardBrightness.lightName("unknown") === ""
                && KeyboardBrightness.lightName('s "evil\\"$(x)::kbd"') === "evilx",
            "a keyboard light is named by its LED's device, and nothing but name characters reaches the label")
        const namedLights = KeyboardBrightness.choicesFor([{ key: "a", identity: 's "asus::kbd_backlight"' },
            { key: "b", identity: 's "dell::kbd_backlight"' }, { key: "c", identity: "unknown" }]).map(c => c.label)
        const twinLights = KeyboardBrightness.choicesFor([{ key: "a", identity: 's "asus::kbd_backlight"' },
            { key: "b", identity: 's "asus::kbd_backlight_1"' }]).map(c => c.label)
        root._check(namedLights.join("|") === "Keyboard light · asus|Keyboard light · dell|Keyboard light 3"
                && twinLights.join("|") === "Keyboard light 1|Keyboard light 2",
            "several keyboard lights are told apart by name, and a nameless or repeated one keeps its number")
        root._check(Audio._ipc.setVolume(-1).indexOf("error:") === 0
                && Audio._ipc.setVolume(101).indexOf("error:") === 0
                && Audio._ipc.setMicVolume(-1).indexOf("error:") === 0
                && Audio._ipc.setMicVolume(101).indexOf("error:") === 0
                && Audio._out.targetVolume === audioVolumeWas && Audio._in.targetVolume === micVolumeWas,
            "audio IPC rejects out-of-range percentages before changing either device")
        if (!Audio.ready) {
            root._check([Audio._ipc.setVolume(50), Audio._ipc.volumeUp(),
                    Audio._ipc.volumeDown(), Audio._ipc.toggleMute()].every(reply => reply.indexOf("error:") === 0),
                "audio IPC reports an unavailable output without pretending to change it")
        }
        if (!Audio.micReady) {
            root._check([Audio._ipc.setMicVolume(50), Audio._ipc.micUp(),
                    Audio._ipc.micDown(), Audio._ipc.toggleMicMute()].every(reply => reply.indexOf("error:") === 0),
                "audio IPC reports an unavailable microphone without pretending to change it")
        }
        if (Audio.sinks.length < 2 && Audio.sources.length < 2) {
            root._check(Audio._ipc.cycleOutput().indexOf("error:") === 0
                    && Audio._ipc.cycleInput().indexOf("error:") === 0,
                "audio IPC explains when there is no alternative device to cycle to")
        }

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
        track._release()
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
        track.step = 0.3
        track.value = 1
        track.nudge(-1, 1)
        root._check(near(track.shownValue, 0.9),
            "stepping back from an uneven slider maximum reaches the nearest grid point")
        track.nudge(-1, 2)
        root._check(near(track.shownValue, 0.3),
            "larger slider nudges count grid steps after leaving an uneven endpoint")
        track.value = 0
        track.step = 0
        track.max = 200
        track.Accessible.increaseAction()
        root._check(track.stepSize === 2 && track.shownValue === 2 && trackChanged === 2,
            "continuous slider accessibility reports the effective nudge increment")
        track.Accessible.decreaseAction()
        track.max = 1; track.value = 0.5
        track.nudgeStep = 5 / 7200
        track.Accessible.increaseAction()
        root._check(near((track.shownValue - 0.5) * 7200, 5)
                && near(track._posToVal(track._railInset + track._railWidth * 0.12345), 0.12345),
            "continuous playback controls move five seconds on a long track while pointer seeking stays exact")
        track.nudge(-1, 10)
        root._check(near(track.shownValue * 7200, 3555),
            "a larger continuous seek counts ten time increments rather than ten percent of the track")
        track.nudgeStep = 0
        track.value = 0
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
        track.interactive = true
        track.commitOnRelease = true
        track.value = 0.25
        trackChanged = -1
        track.interactionKey = "first track"
        track._press(85)
        root._check(track.dragging && trackChanged === -1 && track.shownValue > 0.8,
            "a playback seek previews its destination without changing playback before release")
        track.wheelKey = "probe-slider-target"
        Scroll._processDelta(60, track.wheelKey, 120, 2, 0)
        track.interactionKey = "next track"
        root._check(Scroll._processDelta(60, track.wheelKey, 120, 2, 0) === 0,
            "changing a slider target also discards the previous wheel remainder")
        track._drag(95)
        track._release()
        root._check(!track.dragging && trackChanged === -1 && track.shownValue === track.value,
            "changing tracks cancels a seek so its release cannot reposition the new track")
        track._press(85)
        track._release()
        root._check(trackChanged > 0.8 && !track.dragging,
            "a fresh seek after a track change commits normally")
        trackChanged = -1
        track.value = 0.15
        track.nudge(1, 1)
        const steppedTo = track.shownValue
        track.value = 0.16
        const seekWaits = trackChanged === -1 && track.shownValue === steppedTo && steppedTo > 0.16
        discoveryClock.wait(Scroll.sliderRestMs + 60)
        const seekLanded = trackChanged === steppedTo
        trackChanged = -1
        track.nudge(1, 1)
        track._press(85)
        discoveryClock.wait(Scroll.sliderRestMs + 60)
        const dragHeld = trackChanged === -1
        track._release()
        root._check(seekWaits && seekLanded && dragHeld && trackChanged > 0.8,
            "a stepped seek holds its target while playback moves and seeks there once the steps rest, unless a drag takes over")
        trackChanged = -1
        track._press(85)
        track.visible = false
        track._release()
        track.nudge(1, 1)
        root._check(!track.dragging && trackChanged === -1,
            "hiding a slider cancels unfinished input and rejects accessibility changes")
        track.visible = true
        track._press(85)
        track.interactive = false
        track._release()
        root._check(trackChanged === -1 && track.shownValue === track.value,
            "losing seek capability cancels its preview without committing")
        track.interactive = true
        for (const rangeChange of [{ key: "max", value: 2 },
                { key: "min", value: 0.1 }, { key: "step", value: 0.2 }]) {
            trackChanged = -1
            track._press(85)
            Scroll._processDelta(60, track.wheelKey, 120, 2, 0)
            track[rangeChange.key] = rangeChange.value
            track._drag(95)
            track._release()
            root._check(!track.dragging && trackChanged === -1
                    && track.shownValue === track.value
                    && Scroll._processDelta(60, track.wheelKey, 120, 2, 0) === 0,
                "changing slider " + rangeChange.key + " cancels its drag and wheel remainder")
            Scroll.resetControl(track.wheelKey)
        }
        track.wheelKey = "probe-slider-old-key"
        Scroll._processDelta(60, track.wheelKey, 120, 2, 0)
        track.wheelKey = "probe-slider-new-key"
        root._check(Scroll._processDelta(60, "probe-slider-old-key", 120, 2, 0) === 0,
            "changing a slider wheel key clears the old control's unfinished gesture")
        Scroll.resetControl("probe-slider-old-key")
        const stopsFor = (min, max, step) => {
            track.min = min; track.max = max; track.step = step
            return track._stopCount
        }
        root._check(stopsFor(1, 10, 1) === 8 && stopsFor(0, 24, 4) === 5 && stopsFor(50, 105, 5) === 10
                && stopsFor(0, 1, 0.3) === 3 && stopsFor(0, 1, 0.05) === 0 && stopsFor(0, 1, 0) === 0,
            "a slider marks the inner stops of a short grid and leaves a fine or continuous one plain")
        track.destroy()
        const spineScaleWas = ShellSettings.uiScale
        const spineSlider = sliderRowFactory.createObject(barFixtureHost)
        const spineToggle = toggleRowFactory.createObject(barFixtureHost, { glyph: "󰕰" })
        const labelX = (row, text) => {
            const label = root._findTrayNode(row, item => item.text === text && item.font !== undefined)
            return label ? label.mapToItem(row, 0, 0).x : -1
        }
        const spines = []
        for (const scale of [1, 1.5]) {
            ShellSettings.uiScale = scale
            spines.push([labelX(spineSlider, "Probe slider"), labelX(spineToggle, "Probe toggle")])
        }
        ShellSettings.uiScale = spineScaleWas
        root._check(spines.every(pair => pair[0] > 0 && pair[0] === pair[1]) && spines[1][0] > spines[0][0],
            "a slider row's label stays on the toggle rows' column when large type widens the glyph slot")
        // a page goes invisible as its fade ends: a row laid out by its own effective visibility shifted then, and back
        const shade = drawerContentFactory.createObject(barFixtureHost)
        spineSlider.parent = shade
        const labelShown = labelX(spineSlider, "Probe slider")
        shade.visible = false
        const labelHidden = labelX(spineSlider, "Probe slider")
        spineSlider.parent = barFixtureHost
        shade.destroy()
        root._check(labelShown > 0 && labelHidden === labelShown,
            "a row keeps its glyph slot while its page is out of sight, so showing the page relays nothing out")
        spineSlider.destroy()
        spineToggle.destroy()

        const deviceSlider = quickSliderFactory.createObject(barFixtureHost, {
            width: 320, value: 0.25, accessibleName: "Probe device"
        })
        const deviceTrack = deviceSlider.children.find(child => typeof child._press === "function")
        let deviceMoves = 0
        deviceSlider.moved.connect(value => { deviceMoves++; deviceSlider.value = value })
        const hasInteractionKey = typeof deviceSlider.interactionKey === "string"
        if (hasInteractionKey) deviceSlider.interactionKey = "device-a"
        deviceTrack._press(deviceTrack.width * 0.8)
        root._check(deviceTrack.dragging && deviceMoves > 0,
            "a device slider accepts a drag on the original target")
        deviceMoves = 0
        deviceSlider.value = 0.1
        if (hasInteractionKey) deviceSlider.interactionKey = "device-b"
        deviceTrack._drag(deviceTrack.width * 0.9)
        deviceTrack._release()
        root._check(deviceMoves === 0 && !deviceTrack.dragging
                && Math.abs(deviceTrack.shownValue - 0.1) < 0.0001,
            "a device change through the menu wrapper cancels the old drag")
        let glyphActions = 0, expandActions = 0
        deviceSlider.glyphClickable = true
        deviceSlider.expandable = true
        deviceSlider.glyphClicked.connect(() => glyphActions++)
        deviceSlider.expandToggled.connect(() => expandActions++)
        const deviceGlyph = deviceSlider.children.find(child =>
            child.Accessible.name === "Mute probe device")
        deviceSlider.visible = false
        if (deviceGlyph) deviceGlyph.Accessible.pressAction()
        deviceSlider._requestExpand()
        root._check(deviceGlyph && !deviceGlyph.Accessible.focusable
                && glyphActions === 0 && expandActions === 0,
            "hidden device controls reject mute and expansion actions")
        deviceSlider.visible = true
        if (deviceGlyph) deviceGlyph.Accessible.pressAction()
        deviceSlider._requestExpand()
        root._check(glyphActions === 1 && expandActions === 1,
            "showing device controls restores their guarded actions")
        deviceSlider.destroy()
        const appSliderA = quickSliderFactory.createObject(barFixtureHost, {
            width: 320, wheelKey: "appvolume", interactionKey: "app-a"
        })
        const appSliderB = quickSliderFactory.createObject(barFixtureHost, {
            width: 320, wheelKey: "appvolume", interactionKey: "app-b"
        })
        const appTrackA = appSliderA.children.find(child => typeof child._press === "function")
        const appTrackB = appSliderB.children.find(child => typeof child._press === "function")
        root._check(appTrackA.wheelKey !== appTrackB.wheelKey
                && Scroll._processDelta(30, appTrackA.wheelKey, 60, 1, 0) === 0
                && Scroll._processDelta(30, appTrackB.wheelKey, 60, 1, 0) === 0
                && Scroll._processDelta(30, appTrackA.wheelKey, 60, 1, 0) === 1
                && Scroll._processDelta(30, appTrackB.wheelKey, 60, 1, 0) === 1,
            "each app slider accumulates touchpad steps only for its own target")
        appSliderA.destroy()
        appSliderB.destroy()

        const gradient = gradientSliderFactory.createObject(barFixtureHost, {
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
        gradient.interactive = true
        gradient.visible = false
        picked = -1
        Scroll._processDelta(60, gradient.wheelKey, 120, 2, 0)
        gradient.visible = true
        gradient.visible = false
        gradient.Accessible.increaseAction()
        gradient._pickAt(50)
        root._check(Scroll._accums[gradient.wheelKey] === undefined,
            "hiding a color slider discards its unfinished wheel gesture")
        root._check(picked === -1 && !gradient.Accessible.focusable,
            "hidden color sliders reject accessibility changes and leave the focus order")
        gradient.visible = true
        gradient.Accessible.decreaseAction()
        root._check(picked >= 0,
            "a color slider becomes interactive again when it is shown")
        const oldGradientKey = gradient.wheelKey
        Scroll._processDelta(60, oldGradientKey, 120, 2, 0)
        gradient.wheelKey = "probe-gradient-new-key"
        root._check(Scroll._processDelta(60, oldGradientKey, 120, 2, 0) === 0,
            "changing a colour slider wheel key clears the old control's unfinished gesture")
        Scroll.resetControl(oldGradientKey)
        gradient.destroy()
    }

    function _checksUpdatesSysInfoAndGestures(): void {
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
        const updatesWidgetWas = ShellSettings.updatesWidget
        // No package command should launch while exercising result publication.
        SystemTools.ready = false
        ShellSettings.updatesWidget = true
        Updates._acceptCheckResult(0, "3\none 1 -> 2\n")
        const lastGoodPackages = Updates.packages
        root._check(Updates.count === 3 && Updates.packages.length === 1
                && !Updates.lastFailed && Updates._failStreak === 0,
            "a successful package checker publishes its count and details")
        Updates._acceptCheckResult(9, "0\n")
        root._check(Updates.count === 3 && Updates.packages === lastGoodPackages
                && Updates.lastFailed && Updates._failStreak === 1
                && Updates.lastError === "Package check failed (exit 9)",
            "a failed package checker cannot replace good results with partial output")
        Updates._acceptCheckResult(127, "")
        root._check(Updates.count === 3 && Updates._failStreak === 2
                && Updates.lastError === "Package check failed (exit 127)",
            "a package checker that fails to start reports its exit status")
        Updates._acceptCheckResult(0, "ERR helper unavailable\n")
        root._check(Updates.count === 3 && Updates.lastFailed
                && Updates.lastError === "helper unavailable",
            "a wrapper's explicit package error remains a failure even with exit zero")
        Updates._acceptCheckResult(0, "not a count\n")
        root._check(Updates.count === 3 && Updates.lastFailed
                && Updates.lastError === "Package check returned an invalid count",
            "a successful package process still needs a valid count")
        Updates._acceptCheckResult(0, "0\n")
        root._check(Updates.count === 0 && Updates.packages.length === 0
                && !Updates.lastFailed && Updates.lastError === ""
                && Updates._failStreak === 0 && Updates.ready,
            "a completed package check recovers from previous failures")
        ShellSettings.updatesWidget = false
        Updates._acceptCheckResult(0, "8\n")
        root._check(Updates.count === 0 && !Updates.lastFailed,
            "a late package result cannot repopulate a disabled widget")
        const reconnect = Updates._reconnectTimer
        root._check(reconnect !== null, "the internet recovery fixture finds the package retry timer")
        if (reconnect) {
            const issueWas = Network.connectivityIssue
            const checkedWas = Updates.lastCheckMs
            ShellSettings.updatesWidget = true
            SystemTools.packageFamily = "pacman"
            SystemTools._tools = { checkupdates: true }
            SystemTools.ready = true
            Updates.lastFailed = true
            Updates.lastCheckMs = Date.now()
            for (const issue of ["portal", "limited"]) {
                reconnect.stop()
                Network.connectivityIssue = issue
                root._check(!reconnect.running,
                    "an internet issue does not queue a background package retry: " + issue)
                Network.connectivityIssue = ""
                root._check(reconnect.running === (Network.connected && !Idle.isIdle),
                    "internet recovery queues a failed package check without a link change: " + issue)
            }
            reconnect.stop()
            Updates.lastFailed = false
            Network.connectivityIssue = "portal"
            Network.connectivityIssue = ""
            root._check(!reconnect.running,
                "internet recovery keeps a recent successful package result")
            Network.connectivityIssue = issueWas
            ShellSettings.updatesWidget = false
            SystemTools.ready = false
            Updates.lastCheckMs = checkedWas
        }
        ShellSettings.updatesWidget = updatesWidgetWas
        SystemTools.ready = true
        SystemTools.packageFamily = "pacman"
        SystemTools._tools = { checkupdates: true, paru: true }
        ShellSettings.updatesIncludeAur = false
        root._check(!Updates._cmd().includes("paru -Qua")
                && Updates.managerLabel === "pacman",
            "package updates honor the disabled AUR source")
        ShellSettings.updatesIncludeAur = true
        // the generated check, run as written: paru tags a package held in IgnorePkg, in German unless LC_ALL=C
        const ignoredStubs = "checkupdates() { printf 'core 1-1 -> 1-2\\n'; }; "
            + "paru() { [ \"$LC_ALL\" = C ] && t='[ignored]' || t='[ignoriert]'; "
            + "printf 'aurpkg 1-1 -> 1-2\\npinned 1-1 -> 1-2 %s\\n' \"$t\"; }; "
        const ignoredRun = processFactory.createObject(root, { command: ["bash", "-c",
            "out=$(" + ignoredStubs + Updates._cmd() + "); [ \"$(printf '%s\\n' \"$out\" | sed -n 2p)\" = 'SPLIT 1 1' ]"] })
        ignoredRun.exited.connect(function(code) {
            root._check(code === 0, "an AUR package held back by IgnorePkg is not counted as an update")
            root._ignoredUpdatesDone = true
            ignoredRun.destroy()
        })
        ignoredRun.running = true
        // without checkupdates, paru -Qu lists both sources; only a foreign package is the AUR's
        SystemTools._tools = { paru: true }
        const helperStubs = "paru() { printf 'core 1-1 -> 1-2\\naurpkg 3-1 -> 3-2\\n'; }; "
            + "pacman() { [ \"$*\" = -Qqm ] && printf 'aurpkg\\nunrelated\\n'; }; "
        const helperRun = processFactory.createObject(root, { command: ["bash", "-c",
            "out=$(" + helperStubs + Updates._cmd() + "); "
            + "[ \"$out\" = \"$(printf '2\\nSPLIT 1 1\\ncore 1-1 -> 1-2\\nDETAIL AUR\\naurpkg 3-1 -> 3-2')\" ]"] })
        helperRun.exited.connect(function(code) {
            root._check(code === 0, "a helper-only update check splits repository and AUR packages")
            root._helperUpdatesDone = true
            helperRun.destroy()
        })
        helperRun.running = true
        Updates.count = 2
        Updates._parseDetail("2\nSPLIT 1 1\ncore 1-1 -> 1-2\nDETAIL AUR\naurpkg 3-1 -> 3-2")
        root._check(Updates.manager === "aur" && Updates.repoCount === 1 && Updates.aurCount === 1
                && !Updates.packages[0].aur && Updates.packages[1].aur,
            "a helper-only update list tags only its AUR packages as AUR")
        Updates.count = 1
        Updates._parseDetail("1\naurpkg 3-1 -> 3-2")
        root._check(Updates.aurCount === 1 && Updates.packages[0].aur,
            "an unsplit helper-only list still reads as the helper's")
        SystemTools._tools = { checkupdates: true, paru: true }
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
        const cpuHighWas = SysInfo.cpuHigh
        const cpuBusyWas = SysInfo._cpuBusySamples
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
        SysInfo.cpuHigh = cpuHighWas
        SysInfo._cpuBusySamples = cpuBusyWas
        SysInfo._active = cpuActiveWas

        const memTotalWas = SysInfo.memTotalKb, memAvailWas = SysInfo.memAvailKb
        SysInfo._active = true
        SysInfo._applyMeminfo("MemTotal: 100 kB\nMemAvailable: 150 kB\n")
        root._check(SysInfo.memPct === 0 && SysInfo.memAvailKb === 100,
            "inconsistent memory samples cannot produce a negative percentage")
        SysInfo._applyMeminfo("MemTotal: 100 kB\n")
        root._check(SysInfo.memTotalKb === 0 && SysInfo.memPct === 0,
            "missing memory fields retire the previous reading")
        const memSeen = []
        const watchMem = () => memSeen.push(SysInfo.memPct)
        SysInfo.memPctChanged.connect(watchMem)
        SysInfo._applyMeminfo("MemTotal: 16000000 kB\nMemAvailable: 12000000 kB\n")
        SysInfo._applyMeminfo("MemTotal: 100 kB\n")
        SysInfo.memPctChanged.disconnect(watchMem)
        root._check(memSeen.length > 0 && memSeen.every(p => p < 0.5),
            "a first memory reading, and one that fails, never pass through 100% used on the way")
        const swapWas = [SysInfo.swapTotalKb, SysInfo.swapUsedKb, SysInfo.memPressure, SysInfo._memStalled]
        const pressureLine = value => "some avg10=" + value + " avg60=0.00 avg300=0.00 total=1943\n"
            + "full avg10=99.00 avg60=0.00 avg300=0.00 total=1662\n"
        SysInfo._applyPressure(pressureLine("0.00"))
        SysInfo._applyMeminfo("MemTotal: 16000000 kB\nMemAvailable: 9000000 kB\n"
            + "SwapCached: 900000 kB\nSwapTotal: 16000000 kB\nSwapFree: 14000000 kB\n")
        root._check(SysInfo.swapUsedKb === 2000000 && !SysInfo.swapActive,
            "swap sitting in zram with nothing stalled stays out of the memory line")
        SysInfo._applyPressure(pressureLine("12.50"))
        root._check(SysInfo.memPressure === 12.5 && SysInfo.swapActive,
            "swap shows once the kernel reports tasks stalled on memory")
        SysInfo._applyPressure(pressureLine("6.00"))
        const heldWhileEasing = SysInfo.swapActive
        SysInfo._applyPressure(pressureLine("4.99"))
        root._check(heldWhileEasing && !SysInfo.swapActive,
            "a stall holds the swap figure until the pressure has really eased")
        SysInfo._applyPressure(pressureLine("6.00"))
        root._check(!SysInfo.swapActive,
            "easing pressure alone does not bring the swap figure back")
        SysInfo._applyPressure(pressureLine("50.00"))
        SysInfo._applyPressure("")
        root._check(SysInfo.memPressure === 0 && !SysInfo.swapActive,
            "a kernel without pressure accounting leaves swap unreported")
        SysInfo._applyPressure(pressureLine("50.00"))
        SysInfo._applyMeminfo("MemTotal: 16000000 kB\nMemAvailable: 9000000 kB\n"
            + "SwapTotal: 0 kB\nSwapFree: 0 kB\n")
        root._check(SysInfo.swapUsedKb === 0 && !SysInfo.swapActive,
            "memory pressure on a machine with no swap names no swap figure")
        SysInfo.swapTotalKb = swapWas[0]
        SysInfo.swapUsedKb = swapWas[1]
        SysInfo.memPressure = swapWas[2]
        SysInfo._memStalled = swapWas[3]
        SysInfo.memTotalKb = memTotalWas
        SysInfo.memAvailKb = memAvailWas
        SysInfo._active = cpuActiveWas

        const diskWas = [SysInfo.diskTotalKb, SysInfo.diskUsedKb, SysInfo.diskAvailKb,
            SysInfo._lastDiskReadMs]
        SysInfo._active = true
        root._check(SysInfo._applyDiskStat("Filesystem 1024-blocks Used Available Capacity Mounted on\n"
                + "/dev/root 1000 200 750 22% /\n")
                && SysInfo.diskTotalKb === 1000 && SysInfo.diskUsedKb === 200
                && SysInfo.diskAvailKb === 750
                && Math.abs(SysInfo.diskPct - 200 / 950) < 0.0001,
            "disk readings preserve reserved blocks when parsing df directly")
        root._check(SysInfo._applyDiskStat("device with spaces 5000000000 3000000000 1900000000 62% /\n")
                && SysInfo.diskTotalKb === 5000000000 && SysInfo.diskUsedKb === 3000000000
                && SysInfo.diskAvailKb === 1900000000,
            "disk readings accept large filesystems and device names with spaces")
        const diskReadAt = SysInfo._lastDiskReadMs
        root._check(!SysInfo._applyDiskStat("/dev/root 1000 broken 750 22% /\n")
                && !SysInfo._applyDiskStat("/dev/root 1000 200 750 22% /home\n")
                && !SysInfo._applyDiskStat("")
                && SysInfo.diskTotalKb === 5000000000 && SysInfo._lastDiskReadMs === diskReadAt,
            "failed or unrelated disk samples leave the last valid reading and freshness intact")
        SysInfo._active = false
        root._check(!SysInfo._applyDiskStat("/dev/root 1000 200 750 22% /\n")
                && SysInfo.diskTotalKb === 5000000000,
            "a disk result arriving after Home closes cannot update its cached sample")
        SysInfo.diskTotalKb = diskWas[0]
        SysInfo.diskUsedKb = diskWas[1]
        SysInfo.diskAvailKb = diskWas[2]
        SysInfo._lastDiskReadMs = diskWas[3]
        SysInfo._active = cpuActiveWas

        const brightnessReadWas = {
            level: Brightness.currentBrightness, pending: Brightness.pendingPercent,
            currentValid: Brightness._currentValid, maxValid: Brightness._maxValid,
            ready: Brightness.ready, attempts: Brightness._reprobeAttempts
        }
        Brightness.currentBrightness = 50
        Brightness._currentValid = true
        Brightness._maxValid = true
        Brightness._syncReady()
        Brightness._applyDebounceTimer.restart()
        Brightness._applyBrightnessRead(20)
        root._check(Brightness.currentBrightness === 50 && Brightness.ready,
            "an old brightness read cannot overwrite scroll steps waiting to be written")
        Brightness._applyBrightnessRead(-1)
        root._check(Brightness.currentBrightness === 50 && Brightness.ready,
            "a late failed read cannot disable brightness while a new level is queued")
        Brightness._applyDebounceTimer.stop()
        Brightness._applyBrightnessRead(70)
        root._check(Brightness.currentBrightness === 70 && Brightness.ready,
            "brightness readback resumes once queued writes have finished")
        const vanishWas = { max: Brightness.maxBrightness, armed: OsdBarState._armed }
        OsdBarState._armed = true
        Idle._returned.stop()
        Brightness.maxBrightness = 100
        Brightness._reprobeAttempts = 3
        OsdBarState._clearEntries()
        Brightness._applyBrightnessRead(40)
        const liveOsd = OsdBarState._entryIndex("brightness") >= 0
        OsdBarState._clearEntries()
        Brightness._applyBrightnessRead(-1)
        const lostQuiet = !Brightness.ready && OsdBarState._entryIndex("brightness") < 0
        Brightness._applyBrightnessRead(40)
        root._check(liveOsd && lostQuiet && Brightness.ready && OsdBarState._entryIndex("brightness") < 0,
            "a backlight that stops answering and comes back shows no brightness OSD, a change while it answers does")
        OsdBarState._clearEntries()
        OsdBarState._armed = vanishWas.armed
        Brightness.maxBrightness = vanishWas.max
        Brightness.currentBrightness = brightnessReadWas.level
        Brightness.pendingPercent = brightnessReadWas.pending
        Brightness._currentValid = brightnessReadWas.currentValid
        Brightness._maxValid = brightnessReadWas.maxValid
        Brightness.ready = brightnessReadWas.ready
        Brightness._reprobeAttempts = brightnessReadWas.attempts

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
        const niriOutputs = JSON.stringify({
            "eDP-1": { name: "eDP-1", make: "BOE", model: "NE160QDM", serial: " 0x0A1B " },
            "DP-1": { name: "DP-1", make: "Dell", model: "U2723QE", serial: null },
            "HDMI-A-1": { name: "HDMI-A-1", make: "LG", model: "27GL850", serial: "  " }
        })
        const niriSerials = niri.serialsFrom(niriOutputs)
        root._check(JSON.stringify(niriSerials) === JSON.stringify({ "eDP-1": "0x0A1B" })
                && Object.keys(niri.serialsFrom("not json")).length === 0
                && Object.keys(niri.serialsFrom("[1,2]")).length === 0,
            "niri's output list yields each monitor's serial by connector, and nothing from a missing or broken one")
        {
            // niri itself is not here: a stand-in prints the list as niri msg --json outputs does
            const reader = niri._outputsReader
            reader.command = ["sh", "-c", "printf '%s' \"$1\"", "niri", niriOutputs]
            reader.running = true
            const readDeadline = Date.now() + 3000
            while (reader.running && Date.now() < readDeadline) discoveryClock.wait(10)
            root._check(niri.monitorSerials["eDP-1"] === "0x0A1B" && niri.monitorSerials["DP-1"] === undefined,
                "the niri backend publishes the serials it reads, so display choices follow the monitor on niri too")
        }
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

        niri._onLine(JSON.stringify({ KeyboardLayoutsChanged: { keyboard_layouts: {
            names: ["English (US)", "Latvian"], current_idx: 0
        }}}))
        niri._onLine(JSON.stringify({ KeyboardLayoutSwitched: { idx: 1 } }))
        root._check(niri.keyboardLayout === "Latvian", "niri layout events update the active input language")
        const sharingEvents = []
        niri.sharingState.connect(active => sharingEvents.push(active))
        niri._onLine(JSON.stringify({ CastsChanged: { casts: [] } }))
        niri._onLine(JSON.stringify({ CastStartedOrChanged: { cast: { stream_id: 1 } } }))
        niri._onLine(JSON.stringify({ CastStartedOrChanged: { cast: { stream_id: 1 } } }))
        niri._onLine(JSON.stringify({ CastStartedOrChanged: { cast: { stream_id: 2 } } }))
        niri._onLine(JSON.stringify({ CastStopped: { stream_id: 1 } }))
        root._check(niri.sharingSupported && niri._castIds.length === 1 && sharingEvents[sharingEvents.length - 1],
            "niri sharing counts streams by identity and stays private while another cast is active")
        niri._onLine(JSON.stringify({ CastStopped: { stream_id: 2 } }))
        root._check(!sharingEvents[sharingEvents.length - 1], "niri sharing ends when its last stream stops")

        niri._overview = true
        niri._titleSyncTimer.start()
        niri._backgroundTitleSyncTimer.start()
        niri._resetDisconnectedState()
        root._check(niri.workspaces.length === 0 && niri.toplevels.length === 0
                && niri.workspaceToplevels.length === 0 && niri.activeToplevel === null
                && niri.focusedMonitor === "" && niri.focusedWorkspaceRef === -1
                && !niri.overviewActive,
            "a dropped niri socket clears stale windows, workspaces and overview state")
        root._check(!niri._titleSyncTimer.running && !niri._backgroundTitleSyncTimer.running,
            "a dropped niri socket cancels queued title snapshots")
        niri._onLine(JSON.stringify({ WorkspacesChanged: { workspaces: [
            { id: 30, idx: 1, output: "DP-2", is_active: true, is_focused: true }
        ]}}))
        niri._onLine(JSON.stringify({ WindowsChanged: { windows: [
            { id: 92, workspace_id: 30, app_id: "probe.reconnected", is_focused: true }
        ]}}))
        root._check(niri.workspaces.length === 1 && niri.workspaces[0].occupied
                && niri.activeToplevel.ref === 92 && niri.focusedMonitor === "DP-2",
            "fresh niri snapshots repopulate state after a disconnect")

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

        const netDev = "Inter-|   Receive |  Transmit\n face |bytes    packets\n"
            + "  wlo1: 1 2 3\n    lo: 4 5 6\n  tun0: 7 8 9\n"
        root._check(Network.interfaceNames(netDev) === "lo tun0 wlo1"
                && Network.interfaceNames(netDev.replace("  tun0: 7 8 9\n", "")) === "lo wlo1"
                && Network.interfaceNames("") === "",
            "the interface list names every interface and skips the header")
        const interfacesWas = Network._interfaceNames
        Network._vpnSettleTimer.stop()
        Network._interfaceNames = "lo wlo1"
        Network._applyInterfaceNames("  wlo1: 1\n  lo: 2\n")
        const unchangedArmed = Network._vpnSettleTimer.running
        Network._applyInterfaceNames("  wlo1: 1\n  lo: 2\n  wg0: 3\n")
        const tunnelArmed = Network._vpnSettleTimer.running
        const tunnelNames = Network._interfaceNames
        Network._vpnSettleTimer.stop()
        Network._interfaceNames = interfacesWas
        root._check(!unchangedArmed && tunnelArmed && tunnelNames === "lo wg0 wlo1",
            "a tunnel interface appearing rechecks the VPN, an unchanged list does not")

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

        const wifiConnectingWas = Network.wifiConnecting
        const wifiErrorWas = Network.wifiError
        const wifiReasonWas = Network.wifiErrorReason
        Network.wifiError = "probe failure"
        Network.wifiErrorReason = Net.ConnectionFailReason.WifiAuthTimeout
        root._check(Network.wifiErrorText === "Wrong password" && Network.wifiErrorNeedsSecret,
            "an authentication timeout offers a password retry")
        Network.wifiErrorReason = Net.ConnectionFailReason.NoSecrets
        root._check(Network.wifiErrorText === "Wrong password" && Network.wifiErrorNeedsSecret,
            "a refused key reads as a wrong password, the way NetworkManager reports a mistyped one")
        Network.wifiErrorReason = Net.ConnectionFailReason.WifiNetworkLost
        root._check(Network.wifiErrorText === "Out of range" && !Network.wifiErrorNeedsSecret,
            "a lost Wi-Fi network says it is out of range rather than offering a password retry")
        Network.wifiErrorReason = Net.ConnectionFailReason.WifiClientDisconnected
        root._check(Network.wifiErrorText === "Failed" && !Network.wifiErrorNeedsSecret,
            "an interrupted Wi-Fi connection reports a plain failure")
        Network.clearWifiError()
        root._check(Network.wifiErrorText === "" && !Network.wifiErrorNeedsSecret,
            "clearing a Wi-Fi error also removes its status")
        Network.wifiConnecting = "probe replacement AP"
        Network.wifiError = "old failure"
        root._check(!Network._acceptWifiLink({ name: "another network", connected: true })
                && !Network._acceptWifiLink({ name: "probe replacement AP", connected: false })
                && !Network._acceptWifiLink(null)
                && Network.wifiConnecting === "probe replacement AP",
            "an unrelated, disconnected or missing access point cannot finish a Wi-Fi attempt")
        root._check(Network._acceptWifiLink({ name: "probe replacement AP", connected: true })
                && Network.wifiConnecting === "" && Network.wifiError === ""
                && Network._pendingNetwork === null,
            "a replacement access point confirms Wi-Fi success and clears stale errors")
        root._check(!Network._acceptWifiLink({ name: "probe replacement AP", connected: true }),
            "a settled Wi-Fi attempt cannot be completed twice")
        Network.wifiConnecting = wifiConnectingWas
        Network.wifiError = wifiErrorWas
        Network.wifiErrorReason = wifiReasonWas

        const vpnStateWas = Network._vpnState
        Network._vpnState = ({ active: true, name: "stale probe VPN" })
        Network._vpnCandidateActive = true
        Network._vpnCandidateName = "stale probe VPN"
        const vpnAddressForWas = Network._vpnAddressFor
        Network._vpnAddressFor = "probe-uuid"
        Network.vpnAddress = "10.10.14.2"
        Network._clearVpnState()
        root._check(!Network.hasVpn && Network.vpnName.length === 0
                && !Network._vpnCandidateActive
                && Network._vpnCandidateName.length === 0,
            "losing VPN detection clears both published and in-flight state")
        root._check(Network.vpnAddress.length === 0 && Network._vpnAddressFor.length === 0,
            "a VPN going away takes its address off the Connectivity card")
        Network._vpnAddressFor = ""
        Network._vpnState = ({ active: true, name: "probe VPN", uuid: "probe-up-uuid" })
        root._check(Network._vpnAddressFor === "probe-up-uuid",
            "a tunnel coming up asks for its address from the state change itself")
        Network._vpnState = vpnStateWas
        Network._vpnAddressFor = vpnAddressForWas
        root._check(Network.vpnAddressFrom("10.10.14.23/23\n") === "10.10.14.23"
                && Network.vpnAddressFrom("10.8.0.2/24 | 10.8.0.3/24") === "10.8.0.2"
                && Network.vpnAddressFrom("") === ""
                && Network.vpnAddressFrom("fe80::1/64") === "",
            "the VPN row shows the tunnel's first IPv4 address without its prefix")
        root._check(Network.vpnAddressFrom("\nfd00:1234::2/64\n") === "fd00:1234::2"
                && Network.vpnAddressFrom("2001:db8::1/128 | 2001:db8::2/64") === "2001:db8::1"
                && Network.vpnAddressFrom("2001:db8:0:1:2:3:4:5/64") === "2001:db8:0:1:2:3:4:5"
                && Network.vpnAddressFrom("::ffff:192.0.2.1/128") === "::ffff:192.0.2.1",
            "IPv6-only VPNs expose compressed, full and IPv4-mapped tunnel addresses")
        root._check(Network.vpnAddressFrom("fd00::2/64\n10.8.0.2/24\n") === "10.8.0.2"
                && Network.vpnAddressFrom("10.8.0.2/24\nfd00::2/64\n") === "10.8.0.2",
            "dual-stack VPNs keep their IPv4 address regardless of field order")
        root._check(Network.vpnAddressFrom("not-an-address\nfd00::2/64\nfe80::1/64") === "fd00::2"
                && Network.vpnAddressFrom("fe80::1/64\nfd00::2/64") === "fd00::2",
            "a malformed line or a link-local address cannot hide the tunnel's routable address")

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
        const expiredKey = "probe-scroll-expired"
        Scroll._processDelta(60, expiredKey, 120, 2, 0)
        Scroll._expires[expiredKey] = Date.now() - 1
        root._check(Scroll._processDelta(60, expiredKey, 120, 2, 0) === 0,
            "input arriving before a delayed cleanup does not reuse an expired half-notch")
        const rollbackKey = "probe-scroll-clock-rollback"
        Scroll._processDelta(60, rollbackKey, 120, 2, 0)
        Scroll._expires[rollbackKey] = Date.now() + 3600000
        root._check(Scroll._processDelta(60, rollbackKey, 120, 2, 0) === 0,
            "a clock rollback discards a previous wheel gesture's half-notch")
        Scroll._lastSteps[rollbackKey] = Date.now() + 3600000
        Scroll._expires[rollbackKey] = Date.now() + 3600000
        root._check(Scroll._processDelta(120, rollbackKey, 120, 2, 1000) === 1,
            "a clock rollback cannot leave wheel steps throttled until the old time returns")
        Scroll._expires[rollbackKey] = Date.now() + 3600000
        Scroll._expireKeys(Date.now())
        root._check(Scroll._expires[rollbackKey] === undefined
                && Scroll._lastSteps[rollbackKey] === undefined,
            "shared wheel cleanup removes gestures stamped before a clock rollback")
        const rollbackPageWas = Scroll._page.movedAt
        Scroll._page.movedAt = Date.now() + 3600000
        root._check(!Scroll.wheelBelongsToPage(Date.now() + 3600000),
            "future page and hover timestamps cannot keep a slider's wheel input on the page")
        Scroll._page.movedAt = rollbackPageWas
        const cleanupTime = Date.now()
        const retainedKey = "probe-scroll-retained"
        Scroll._processDelta(40, retainedKey, 120, 2, 0)
        Scroll._expires[expiredKey] = cleanupTime
        Scroll._expires[retainedKey] = cleanupTime + Scroll.resetMs
        root._check(Scroll._expireKeys(cleanupTime) > 0
                && Scroll._accums[expiredKey] === undefined
                && Scroll._directions[expiredKey] === undefined
                && Scroll._lastSteps[expiredKey] === undefined
                && Scroll._expires[expiredKey] === undefined
                && Scroll._accums[retainedKey] === 40,
            "wheel cleanup removes expired state while preserving another control's gesture")
        root._check(Scroll._processDelta(80, retainedKey, 120, 2, 0) === 1,
            "a gesture retained by shared cleanup finishes its own notch")
        for (const reservedKey of ["__proto__", "constructor", "toString"]) {
            root._check(Scroll._processDelta(60, reservedKey, 120, 2, 0) === 0
                    && Scroll._processDelta(60, reservedKey, 120, 2, 0) === 1,
                "wheel keys remain independent for " + reservedKey)
        }
        Scroll._expireKeys(Date.now() + 2000)
        root._check(Object.keys(Scroll._expires).length === 0
                && Object.keys(Scroll._accums).length === 0
                && Object.keys(Scroll._directions).length === 0
                && Object.keys(Scroll._lastSteps).length === 0,
            "completed wheel gestures leave no retained control state")
        const notchUp = inverted => ({ angleDelta: { x: 0, y: 120 }, inverted: inverted })
        root._check(Scroll.processLevelWheel(notchUp(false), "probe-level-a") === 1
                && Scroll.processLevelWheel(notchUp(true), "probe-level-b") === -1
                && Scroll.processControlWheel(notchUp(true), "probe-level-c") === 1,
            "natural scrolling flips a level control but not content navigation")
        const pad = (x, y) => ({ angleDelta: { x: x, y: y }, pixelDelta: { x: x / 8, y: y / 8 },
            device: { type: PointerDevice.TouchPad } })
        const phaseKey = "probe-gesture-phase"
        Scroll.processControlWheel(pad(0, 40), phaseKey)
        Scroll.processControlWheel(Object.assign(pad(0, 0), { phase: Qt.ScrollEnd }), phaseKey)
        root._check(Scroll.processControlWheel(pad(0, 20), phaseKey) === 0,
            "a completed touchpad gesture cannot lend its remainder to the next gesture")
        Scroll.processControlWheel(Object.assign(pad(0, 40), { phase: Qt.ScrollBegin }), phaseKey)
        root._check(Scroll._accums[phaseKey] === 40,
            "a touchpad begin discards old state while retaining its own delta")
        Scroll.resetControl(phaseKey)
        const trayPhaseKey = "probe-tray-gesture-phase"
        Scroll.processTrayWheel(pad(0, 40), trayPhaseKey)
        Scroll.processTrayWheel(pad(40, 0), trayPhaseKey)
        Scroll.processTrayWheel(Object.assign(pad(0, 0), { phase: Qt.ScrollEnd }), trayPhaseKey)
        root._check(Scroll.processTrayWheel(pad(0, 20), trayPhaseKey).steps === 0
                && Scroll.processTrayWheel(pad(20, 0), trayPhaseKey).steps === 0,
            "a tray gesture end clears both axis remainders")
        Scroll.resetControl(trayPhaseKey + ":h")
        Scroll.resetControl(trayPhaseKey + ":v")
        for (const axes of [[80, 0], [80, 10]]) {
            const key = "probe-horizontal:" + axes[1]
            Scroll.processControlWheel(pad(0, 40), key)
            const rejected = Scroll.processControlWheel(pad(axes[0], axes[1]), key)
            root._check(rejected === 0 && Scroll._accums[key] === undefined
                    && Scroll._directions[key] === undefined && Scroll._lastSteps[key] === undefined
                    && Scroll._expires[key] === undefined
                    && Scroll.processControlWheel(pad(0, 20), key) === 0,
                "a horizontal touchpad gesture discards the previous control remainder (vertical " + axes[1] + ")")
            Scroll.resetControl(key)
        }
        const horizontalThrottleKey = "probe-horizontal-throttle"
        Scroll.processControlWheel(pad(0, 60), horizontalThrottleKey)
        Scroll._lastSteps[horizontalThrottleKey] = Date.now() + 1000
        Scroll.processControlWheel(pad(80, 10), horizontalThrottleKey)
        root._check(Scroll.processControlWheel(pad(0, 60), horizontalThrottleKey) === 1,
            "returning from a horizontal gesture starts a new control step without the old throttle")
        Scroll.resetControl(horizontalThrottleKey)
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
    }

    function _checksShellUpdate(): void {
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

        const checkoutStateWas = {
            versionReady: ShellUpdate.versionReady, versionError: ShellUpdate.versionError,
            installationMode: ShellUpdate.installationMode, packaged: ShellUpdate.packaged,
            count: ShellUpdate.count,
            lastCheckMs: ShellUpdate.lastCheckMs, _flagLoaded: ShellUpdate._flagLoaded,
            _checkedLoaded: ShellUpdate._checkedLoaded, _errorLoaded: ShellUpdate._errorLoaded
        }
        ShellUpdate._flagLoaded = true
        ShellUpdate._checkedLoaded = true
        ShellUpdate._errorLoaded = true
        ShellUpdate.lastCheckMs = 1234000
        ShellUpdate.installationMode = "managed"
        ShellUpdate.packaged = false
        ShellUpdate.versionReady = false
        ShellUpdate.versionError = ""
        root._check(!ShellUpdate.upToDate && ShellUpdate.statusText === "Reading checkout",
            "a cached successful check waits for the checkout state before claiming up to date")
        ShellUpdate.versionError = "The checkout state check timed out"
        root._check(!ShellUpdate.upToDate && ShellUpdate.statusText === "Status unavailable"
                && ShellUpdate.statusReadError === ShellUpdate.versionError,
            "a failed checkout verification is reported instead of a cached up-to-date result")
        const shellUpdateShownWas = ShellSettings.barShowShellUpdate
        ShellSettings.barShowShellUpdate = true
        ShellUpdate.versionError = ""
        ShellUpdate.count = 1
        const shellUpdatePill = shellUpdateWidgetFactory.createObject(barFixtureHost)
        root._check(shellUpdatePill !== null, "the shell update widget builds for installation-mode checks")
        if (shellUpdatePill) {
            root._check(shellUpdatePill.show, "a managed checkout shows its pending release in the bar")
            ShellUpdate.packaged = true
            root._check(!shellUpdatePill.show, "a package install hides stale self-update cache entries")
            ShellUpdate.packaged = false
            ShellUpdate.installationMode = "development"
            root._check(!shellUpdatePill.show, "a development checkout hides stale self-update cache entries")
            shellUpdatePill.destroy()
        }
        ShellSettings.barShowShellUpdate = shellUpdateShownWas
        for (const key of Object.keys(checkoutStateWas)) ShellUpdate[key] = checkoutStateWas[key]
    }

    function _checksPowerModeAndPresentation(): void {
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
        root._check(PowerProfiles.outsideChoice("balanced", "performance", false, false)
                && !PowerProfiles.outsideChoice("", "performance", false, false)
                && !PowerProfiles.outsideChoice("balanced", "", false, false)
                && !PowerProfiles.outsideChoice("balanced", "balanced", false, false),
            "only a change between two live modes counts as a choice made outside the menu")
        root._check(!PowerProfiles.outsideChoice("balanced", "performance", true, false)
                && !PowerProfiles.outsideChoice("balanced", "performance", false, true),
            "Silere's own write and a settling source are no outside choice")
        const fullOrder = PowerProfiles.cycleOrder(true, true)
        root._check(PowerProfiles.nextProfile("balanced", fullOrder) === "performance"
                && PowerProfiles.nextProfile("power-saver", fullOrder) === "balanced",
            "cycling a power mode names the profile it moves to, wrapping at the end")
        root._check(PowerProfiles.nextProfile("performance",
                    PowerProfiles.cycleOrder(true, false)) === ""
                && PowerProfiles.nextProfile("balanced", []) === "",
            "a power mode outside the offered cycle names no successor")
        root._check(JSON.stringify(PowerProfiles.commandFor("balanced", true, true))
                === JSON.stringify(["powerprofilesctl", "set", "balanced"]),
            "power mode prefers its dedicated CLI when both write tools are present")
        root._check(JSON.stringify(PowerProfiles.commandFor("power-saver", false, true))
                === JSON.stringify(["busctl", "--system", "--timeout=5", "set-property",
                    "net.hadess.PowerProfiles", "/net/hadess/PowerProfiles",
                    "net.hadess.PowerProfiles", "ActiveProfile", "s", "power-saver"])
                && PowerProfiles.commandFor("balanced", false, false).length === 0,
            "the power-mode fallback bounds its system-bus write and preserves the profile argument")
        const profileToolsWas = SystemTools._tools
        const profileErrorWas = PowerProfiles.lastError
        SystemTools._tools = { busctl: true, "@powerprofiles": true }
        root._check(PowerProfiles.available, "a daemon and busctl support power changes without the dedicated CLI")
        const rememberProfileWas = ShellSettings.powerProfileRemember
        ShellSettings.powerProfileRemember = true
        PowerProfiles._sourceSettleTimer.stop()
        PowerProfiles._setter.exec(["sleep", "2"])
        root._check(PowerProfiles._setter.running,
            "the power-mode timing probe starts its private writer without changing a hardware profile")
        PowerProfiles._sourceSettleTimer.triggered()
        root._check(PowerProfiles._sourceSettleTimer.running,
            "a charger change during a busy power-mode write stays queued for restoration")
        PowerProfiles._sourceSettleTimer.stop()
        ShellSettings.powerProfileRemember = false
        PowerProfiles._sourceSettleTimer.triggered()
        root._check(!PowerProfiles._sourceSettleTimer.running,
            "disabling remembered power modes cancels a delayed charger restore")
        PowerProfiles._setter.running = false
        ShellSettings.powerProfileRemember = rememberProfileWas
        PowerProfiles._acceptSetResult(1, false, "details\nPermission denied\n")
        root._check(PowerProfiles.lastError === "Permission denied",
            "a failed power-mode fallback exposes the command's useful error")
        PowerProfiles._acceptSetResult(0, true, "")
        root._check(PowerProfiles.lastError === "Power mode change timed out",
            "a timed-out power change cannot be accepted as successful")
        PowerProfiles._acceptSetResult(1, false, "")
        root._check(PowerProfiles.lastError === "Could not change the power mode",
            "a power-mode failure without stderr still has an explanation")
        PowerProfiles._acceptSetResult(0, false, "old error")
        root._check(PowerProfiles.lastError === "", "a successful power change clears its previous error")
        SystemTools._tools = { "@powerprofiles": true }
        root._check(!PowerProfiles.available, "a detected daemon without a write tool does not advertise a usable control")
        SystemTools._tools = { busctl: true, powerprofilesctl: true }
        root._check(!PowerProfiles.available, "a power CLI beside a daemon that does not answer offers no control")
        PowerProfiles._acceptSetResult(1, false, "late failure")
        root._check(PowerProfiles.lastError === "", "a retired power service ignores a late command result")
        SystemTools._tools = profileToolsWas
        PowerProfiles.lastError = profileErrorWas

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
        root._check(NiriEvents.workspacesWithActivated(wsRows, 99, true).workspaces === wsRows,
            "a stale focused activation preserves the current workspace focus and model")
        root._check(NiriEvents.workspacesWithActivated(wsRows, 1, true).workspaces === wsRows,
            "a duplicate workspace activation leaves the model unchanged")
        root._check(NiriEvents.workspacesWithActivated(wsRows, 2, false).workspaces[2] === wsRows[2],
            "activating one output preserves the other output's workspace objects")

        const wsUrgent = NiriEvents.workspacesWithUrgency(wsRows, 2, true)
        root._check(wsUrgent[1].is_urgent === true && wsUrgent[0].is_urgent === undefined
                && wsRows[1].is_urgent === undefined,
            "niri urgency marks one workspace without rewriting the others")
        root._check(NiriEvents.workspacesWithUrgency(wsUrgent, 2, true) === wsUrgent
                && NiriEvents.workspacesWithUrgency(wsRows, 99, true) === wsRows
                && NiriEvents.workspacesWithUrgency(wsRows, 2, false) === wsRows,
            "duplicate, absent and already-clear urgency events leave the model unchanged")

        const winRows = [
            { id: 10, title: "one", is_focused: true },
            { id: 11, title: "two", is_focused: false }
        ]
        const winOpened = NiriEvents.windowsWithUpsert(winRows, { id: 12, title: "new", is_focused: true })
        root._check(winOpened.length === 3 && winOpened[2].id === 12
                && !winOpened[0].is_focused && !winOpened[1].is_focused,
            "a focused niri window arriving unfocuses every window already open")
        root._check(winOpened[1] === winRows[1] && winRows[0].is_focused,
            "opening a focused window preserves unfocused objects and the previous snapshot")
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
        root._check(NiriEvents.windowsWithFocus(winFocused, 11) === winFocused
                && NiriEvents.windowsWithout(winRows, 99) === winRows,
            "duplicate focus and late close events leave the window model unchanged")
        const noFocusedWindows = NiriEvents.windowsWithFocus(winFocused, null)
        root._check(!noFocusedWindows[0].is_focused && !noFocusedWindows[1].is_focused
                && NiriEvents.windowsWithFocus(noFocusedWindows, null) === noFocusedWindows,
            "clearing window focus updates it once and then leaves the model unchanged")
        const winStamped = NiriEvents.windowsWithFocusStamp(winRows, 11, { secs: 7, nanos: 3 })
        root._check(winStamped[1].focus_timestamp.secs === 7
                && winStamped[0].focus_timestamp === undefined,
            "a niri focus timestamp lands on the window it names")
        root._check(NiriEvents.windowsWithFocusStamp(winStamped, 11, { secs: 7, nanos: 3 }) === winStamped
                && NiriEvents.windowsWithFocusStamp(winRows, 99, { secs: 7, nanos: 3 }) === winRows,
            "duplicate timestamps and timestamps for closed windows leave the model unchanged")
        const stampCleared = NiriEvents.windowsWithFocusStamp(winStamped, 11, null)
        root._check(stampCleared[1].focus_timestamp === null
                && winStamped[1].focus_timestamp.secs === 7,
            "clearing a timestamp leaves the previous snapshot untouched")
        root._check(NiriEvents.indexOfWindow(winRows, 11) === 1
                && NiriEvents.indexOfWindow(winRows, 99) === -1
                && NiriEvents.indexOfWindow([null, { id: 5 }], 5) === 1,
            "a niri window lookup skips holes and reports a miss")

        for (const count of [0, 1, 5, 50]) {
            const slots = []
            for (let i = 0; i < count; i++)
                slots.push(i % 7 === 3 ? null : { shouldLoad: i % 3 !== 1, height: 40 + i * 0.5 })
            for (const newestFirst of [false, true]) {
                let reads = 0
                const stack = { count: count, itemAt: index => { reads++; return slots[index] } }
                const measured = StackLayout.measure(stack, newestFirst)
                let positionsMatch = true
                for (let i = 0; i < count; i++) {
                    let expected = 0
                    for (let j = 0; j < count; j++)
                        if ((newestFirst ? j > i : j < i) && slots[j] && slots[j].shouldLoad)
                            expected += slots[j].height
                    if (measured.tops[i] !== expected) positionsMatch = false
                }
                const expectedHeight = slots.reduce((sum, slot) =>
                    sum + (slot && slot.shouldLoad ? slot.height : 0), 0)
                root._check(positionsMatch && measured.height === expectedHeight && reads === count,
                    "notification layout reads " + count + " slots once with newest-first=" + newestFirst)
            }
        }
        // the oldest of four with three shown: only a reply in progress, or the other holds, keeps it
        root._check(!StackLayout.slotLoads(0, 4, 3, false, false, false, false)
                && StackLayout.slotLoads(0, 4, 3, false, false, false, true)
                && StackLayout.slotLoads(3, 4, 3, false, false, false, false)
                && StackLayout.slotLoads(0, 4, 3, false, false, true, false),
            "a card with a reply in progress stays when newer notifications push it past the visible ones, and leaves with the rest once the reply ends")
        // a removed slot (index -1) keeps a card it has, lets a fold run out, and never builds a card for a closed notification
        root._check(!StackLayout.slotInLimit(-1, 3, 3, false, false, false, false, false)
                && StackLayout.slotInLimit(-1, 3, 3, false, false, false, false, true)
                && !StackLayout.slotInLimit(0, 4, 3, false, false, false, false, true)
                && StackLayout.slotInLimit(3, 4, 3, false, false, false, false, false),
            "a notification closed while hidden behind the more chip gets no card on its way out")
        const firstSlot = notificationSlotFactory.createObject(root, { height: 80 })
        const secondSlot = notificationSlotFactory.createObject(root, { height: 120 })
        stackLayoutProbe.slots = [firstSlot, secondSlot]
        root._check(stackLayoutProbe.layout.tops[0] === 120 && stackLayoutProbe.layout.height === 200,
            "the shared popup layout places newest notifications first")
        secondSlot.height = 144.5
        root._check(stackLayoutProbe.layout.tops[0] === 144.5 && stackLayoutProbe.layout.height === 224.5,
            "animated card heights invalidate the shared popup layout")
        secondSlot.shouldLoad = false
        root._check(stackLayoutProbe.layout.tops[0] === 0 && stackLayoutProbe.layout.height === 80,
            "folding a card removes its height from the shared popup layout")
        secondSlot.shouldLoad = true
        stackLayoutProbe.newestFirst = false
        root._check(stackLayoutProbe.layout.tops[1] === 80 && stackLayoutProbe.layout.height === 224.5,
            "a bottom bar reverses popup order without changing the total height")
        stackLayoutProbe.slots = []
        firstSlot.destroy()
        secondSlot.destroy()
        // a lone card starts 8 px under the bar: the window's 2 and the column's 6
        const chipStep = Metrics.rowHeightFor(30) + StackLayout.columnSpacing
        root._check((Metrics.popupClearanceOn(null, 2) + 6 + chipStep) % 4 === 0 && chipStep % 4 === 0,
            "notification cards under the clear chip, and the more chip under them, keep the 4px grid a lone card has")

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

        const trayRowA = { flyoutOpen: true }
        const trayRowB = { flyoutOpen: false }
        root._check(TrayMenuState.siblingFlyoutOpen([trayRowA, trayRowB, null], trayRowB)
                && !TrayMenuState.siblingFlyoutOpen([trayRowA, trayRowB], trayRowA)
                && !TrayMenuState.siblingFlyoutOpen([], trayRowB),
            "a tray submenu waits for a pause only while a sibling's submenu is open")
        const stopA = { keyboardStop: true }
        const stopB = { keyboardStop: true }
        const skipped = { keyboardStop: false }
        const stops = [skipped, stopA, {}, skipped, stopB, null]
        root._check(TrayMenuState.stepStop(stops, null, 1) === stopA && TrayMenuState.stepStop(stops, null, -1) === stopB
                && TrayMenuState.stepStop(stops, stopA, 1) === stopB && TrayMenuState.stepStop(stops, stopB, 1) === stopA
                && TrayMenuState.stepStop(stops, stopA, -1) === stopB && TrayMenuState.stepStop(stops, skipped, 1) === stopA
                && TrayMenuState.stepStop([skipped], null, 1) === null && TrayMenuState.stepStop(null, null, 1) === null,
            "arrow keys in a tray menu wrap over its usable entries and skip the rest")
        const outerFlyout = { opened: true, parentFlyout: null }
        const innerFlyout = { opened: true, parentFlyout: outerFlyout }
        const otherFlyout = { opened: true, parentFlyout: null }
        const flyoutRow = { parent: { parent: innerFlyout } }
        root._check(TrayMenuState.flyoutOf(flyoutRow) === innerFlyout && TrayMenuState.flyoutOf({ parent: {} }) === null
                && TrayMenuState.flyoutOf(null) === null
                && TrayMenuState.branchHolds(outerFlyout, innerFlyout) && TrayMenuState.branchHolds(innerFlyout, innerFlyout)
                && !TrayMenuState.branchHolds(innerFlyout, outerFlyout) && !TrayMenuState.branchHolds(otherFlyout, innerFlyout)
                && !TrayMenuState.branchHolds(outerFlyout, null) && !TrayMenuState.branchHolds(null, innerFlyout),
            "a tray submenu holding the keyboard focus, or opening one that does, stays open")
        const rule = { isSeparator: true }
        const item = { isSeparator: false }
        const rows = [rule, item, rule, rule, item, rule, rule]
        root._check(rows.map((row, i) => row.isSeparator ? (TrayMenuState.strayRule(rows, i) ? "x" : "-") : "a")
                .join("") === "xa-xaxx"
                && TrayMenuState.strayRule([rule, rule], 1) && TrayMenuState.strayRule([item, rule], 1),
            "a tray menu draws one rule between entries and none leading, trailing or doubled")
        const plainEntry = { isSeparator: false, buttonType: 0, icon: "" }
        const iconEntry = { isSeparator: false, buttonType: 0, icon: "image://qsimage/3/0" }
        const checkEntry = { isSeparator: false, buttonType: 1, icon: "" }
        const iconRule = { isSeparator: true, buttonType: 0, icon: "image://qsimage/4/0" }
        root._check(TrayMenuState.menuHasLead([plainEntry, iconEntry]) && TrayMenuState.menuHasLead([checkEntry, plainEntry])
                && !TrayMenuState.menuHasLead([plainEntry, iconRule, plainEntry])
                && !TrayMenuState.menuHasLead([plainEntry, { isSeparator: false, buttonType: 0, icon: "image://evil/x" }])
                && !TrayMenuState.menuHasLead([]) && !TrayMenuState.menuHasLead(null),
            "one icon or check mark gives a whole tray menu one label column, and a refused icon gives none")
        root._check(TrayMenuState.fitWidth([{ naturalWidth: 100 }, {}], 220, 332) === 220
                && TrayMenuState.fitWidth([{ naturalWidth: 231 }, { naturalWidth: 90 }], 220, 332) === 232
                && TrayMenuState.fitWidth([{ naturalWidth: 900 }], 220, 332) === 332
                && TrayMenuState.fitWidth([], 220, 332) === 220,
            "a tray menu widens to its longest row on the 4px grid, between its base and its cap")
        const dndAt = new Date(2026, 9, 11, 14, 31, 20).getTime()
        root._check(Notifications.dndEndFor(dndAt, 60) === new Date(2026, 9, 11, 15, 32).getTime()
                && Notifications.dndEndAtHour(dndAt, 8) === new Date(2026, 9, 12, 8, 0).getTime()
                && Notifications.dndEndAtHour(new Date(2026, 9, 11, 2, 0).getTime(), 8)
                    === new Date(2026, 9, 11, 8, 0).getTime(),
            "timed Do Not Disturb ends on a whole minute, or at the next morning hour still ahead")
        const dndWas = ShellSettings.dnd
        const dndUntilWas = ShellSettings.dndUntil
        Notifications.setDnd(true, Date.now() + 3600000)
        const timedShown = Notifications.dndUntil > 0 && Notifications.dndUntilText.indexOf("Until ") === 0
        ShellSettings.dnd = false
        const clearedByOff = ShellSettings.dndUntil === 0
        Notifications.setDnd(true, Date.now() - 1000)
        Notifications._expireDnd()
        const expired = !ShellSettings.dnd && ShellSettings.dndUntil === 0
        Notifications.toggleDnd()
        const manualOpenEnded = ShellSettings.dnd && Notifications.dndUntil === 0
        root._check(timedShown && clearedByOff && expired && manualOpenEnded,
            "Do Not Disturb for a while shows its end, expires, and leaves no stale end behind")
        ShellSettings.dnd = dndWas
        ShellSettings.dndUntil = dndUntilWas

        const awakeWas = Idle.keepAwake
        Idle.keepAwakeFor(dndAt, 60)
        const awakeTimed = Idle.keepAwake && Idle.keepAwakeUntil === new Date(2026, 9, 11, 15, 32).getTime()
            && Idle.keepAwakeUntilText.indexOf("Until ") === 0
        Idle.keepAwake = false
        const awakeClearedByOff = Idle.keepAwakeUntil === 0
        Idle.setKeepAwake(true, Date.now() - 1000)
        Idle._expireAwake()
        const awakeExpired = !Idle.keepAwake && Idle.keepAwakeUntil === 0
        Idle.toggleKeepAwake()
        const awakeOpenEnded = Idle.keepAwake && Idle.keepAwakeUntil === 0
        root._check(awakeTimed && awakeClearedByOff && awakeExpired && awakeOpenEnded,
            "Keep Awake for a while ends on a whole minute, expires, and leaves no stale end behind")
        Idle.setKeepAwake(awakeWas, 0)

        // measured on hyprland 0.56: grim is one 250 ms burst, a recording a start per frame stopped 500 ms later
        const castIdle = { casts: 0, since: 0, last: 0, sharing: false }
        let shot = Compositor.castStep(castIdle, "start", 1000)
        shot = Compositor.castStep(shot, "stop", 1250)
        const shotHeld = Compositor.castStep(shot, "tick", 1750)
        shot = Compositor.castStep(shotHeld, "tick", 2500)
        shot = Compositor.castStep(shot, "tick", 4000)
        root._check(!shotHeld.sharing && shotHeld.since === 1000 && !shot.sharing && shot.since === 0,
            "a screenshot's single capture burst never reads as sharing the screen")
        // the ticks run every 500 ms, so a shot can land before the last one is forgotten
        let shots = castIdle
        for (let at = 1000; at <= 5000; at += 700) {
            shots = Compositor.castStep(shots, "start", at)
            shots = Compositor.castStep(shots, "stop", at + 30)
            if (shots.sharing) break
        }
        root._check(!shots.sharing,
            "screenshots taken a moment apart never add up to sharing the screen")
        let cast = castIdle
        let castAt = 16
        for (; castAt <= 1600; castAt += 16) {
            cast = Compositor.castStep(cast, "start", castAt)
            if (castAt > 500) cast = Compositor.castStep(cast, "stop", castAt)
        }
        const castArmed = cast.sharing
        while (cast.casts > 0) cast = Compositor.castStep(cast, "stop", castAt += 16)
        const castDrained = cast.casts === 0 && cast.sharing
        const castHeld = Compositor.castStep(cast, "tick", 3000).sharing
        cast = Compositor.castStep(cast, "tick", 4200)
        const castReleased = !cast.sharing && cast.since === 0
        const stray = Compositor.castStep(castIdle, "stop", 10)
        root._check(castArmed && castDrained && castHeld && castReleased
                && stray.casts === 0 && !stray.sharing,
            "a recording reads as sharing once it outlasts a screenshot and ends once its frames stop")
        const shareWas = Compositor.screenSharing
        const shareSilenceWas = ShellSettings.notifScreenShareSilence
        Compositor.screenSharing = true
        ShellSettings.notifScreenShareSilence = true
        const shareSilenced = Notifications.screenShareSilenced && Notifications.silencingActive
        ShellSettings.notifScreenShareSilence = false
        const shareOptedOut = !Notifications.screenShareSilenced
        root._check(shareSilenced && shareOptedOut,
            "sharing the screen silences popups unless that is switched off")
        ShellSettings.notifScreenShareSilence = shareSilenceWas
        Compositor.screenSharing = shareWas

        root._check(!Notifications.allowsPopup(true, false, false, true, true)
                && !Notifications.allowsPopup(false, false, false, true, true)
                && Notifications.allowsPopup(true, true, true, false, true)
                && !Notifications.allowsPopup(true, true, false, false, false),
            "presentation privacy suppresses every app urgency independently of quiet-hours bypass")
        Notifications.presentationMode = true
        root._check(Notifications.screenShareSilenced && Notifications.activeCount === 0,
            "manual presentation mode hides and retires existing popup state on either compositor")
        Notifications.presentationMode = false
        root._check(Notifications.activeCount === 0,
            "ending presentation mode does not replay retired notification cards")
    }

    function _checksKeyboardNavigationAndAlerts(): void {
        const keyboard = keyboardFixtureFactory.createObject(root)
        keyboard.input.wait(1)
        const railComponent = Qt.createComponent("file://" + Quickshell.shellDir + "/modules/menu/RailNavItem.qml")
        const railItem = railComponent.status === Component.Ready
            ? railComponent.createObject(keyboard.toggle.parent, { glyph: "a", label: "Settings" }) : null
        root._check(railItem !== null, "a rail item is available to the behavior probe")
        if (railItem !== null) {
            const railPill = root._findTrayNode(railItem, item => item._keyboardFocus !== undefined)
            railItem.forceActiveFocus(Qt.TabFocusReason)
            const shownByTab = railItem.activeFocus && railPill._show
            railItem.labelPillEnabled = false
            const hiddenInDrawer = !railPill._show
            railItem.labelPillEnabled = true
            keyboard.toggle.forceActiveFocus(Qt.TabFocusReason)
            const hiddenAfterLeave = !railPill._show
            root._check(shownByTab && hiddenInDrawer && hiddenAfterLeave,
                "a rail icon reached by keyboard names itself, unless the drawer already does")
            keyboard.input.mouseMove(railItem, 10, 10)
            keyboard.input.wait(120)
            const railHoverWorked = railItem.hovered
            railItem.forceActiveFocus(Qt.MouseFocusReason)
            keyboard.input.mouseMove(keyboard.slider, 10, 10)
            keyboard.input.wait(120)
            root._check(railHoverWorked && railItem.activeFocus && !railItem.hovered && !railPill._show,
                "a rail icon focused by the pointer does not pin its label open")
            railItem.destroy()
        }
        const powerComponent = Qt.createComponent("file://" + Quickshell.shellDir + "/modules/menu/PowerRailRow.qml")
        const powerFirst = powerComponent.createObject(keyboard.toggle.parent, { width: 200, label: "Lock" })
        const powerSecond = powerComponent.createObject(keyboard.toggle.parent, { width: 200, y: 40, label: "Sleep" })
        keyboard.input.wait(1)
        powerFirst.forceActiveFocus(Qt.TabFocusReason)
        keyboard.input.keyClick(Qt.Key_Down)
        root._check(powerSecond.activeFocus, "arrow keys walk the power drawer like the rest of the rail")
        powerFirst.destroy()
        powerSecond.destroy()
        keyboard.requestActivate()
        keyboard.input.wait(80)
        keyboard.button.forceActiveFocus(Qt.TabFocusReason)
        keyboard.input.keyClick(Qt.Key_Return)
        root._check(keyboard.actions === 1 && keyboard.button.activeFocusOnTab,
            "a real Enter key activates the shared button through its normal action")
        const keyOwner = root._findTrayNode(keyboard.button, item => item.canInteract !== undefined && item.handleKey !== undefined)
        const toggleOwner = root._findTrayNode(keyboard.toggle, item => item.canInteract !== undefined && item.handleKey !== undefined)
        const ringOf = owner => owner ? owner.children.find(child => child.sourceComponent !== undefined) : undefined
        root._check(!!ringOf(keyOwner) && !!ringOf(keyOwner).item && ringOf(keyOwner).item._stroke !== undefined
                && !!ringOf(toggleOwner) && ringOf(toggleOwner).item === null,
            "only the focused control builds its focus ring")
        keyOwner.interactive = false
        keyboard.input.wait(1)
        root._check(!keyboard.button.activeFocus && !keyboard.button.activeFocusOnTab,
            "a control that becomes inert releases keyboard focus and its tab stop")
        keyboard.input.keyClick(Qt.Key_Tab)
        root._check(keyboard.toggle.activeFocus,
            "Tab skips hidden and disabled controls and focuses the next usable row")
        root._check(ringOf(keyOwner).item === null && !!ringOf(toggleOwner).item,
            "the focus ring moves with the focus and is freed behind it")
        keyboard.input.keyClick(Qt.Key_Space)
        root._check(keyboard.toggle.checked, "Space toggles the focused setting")
        keyboard.slider.forceActiveFocus(Qt.TabFocusReason)
        keyboard.input.keyClick(Qt.Key_Right)
        root._check(keyboard.slider.value === 0.5, "arrow keys adjust the focused slider by its own step")
        keyboard.input.keyClick(Qt.Key_End)
        root._check(keyboard.slider.value === 1, "End reaches the slider maximum")
        keyboard.select.forceActiveFocus(Qt.TabFocusReason)
        keyboard.input.keyClick(Qt.Key_Return)
        keyboard.input.keyClick(Qt.Key_Down)
        keyboard.input.keyClick(Qt.Key_Return)
        root._check(keyboard.select.currentValue === 2 && !keyboard.select._open,
            "Enter and arrows choose an inline picker option without a pointer")
        keyboard.select.model = Array.from({ length: 40 }, (_, i) => ({ value: i, label: "Option " + i }))
        keyboard.select.currentValue = 17
        keyboard.input.mouseClick(keyboard.select, 20, keyboard.select._headerH / 2)
        keyboard.select.forceActiveFocus(Qt.TabFocusReason)
        keyboard.input.keyClick(Qt.Key_Return)
        root._check(keyboard.select.currentValue === 17 && !keyboard.select._open,
            "Enter after opening a dropdown by pointer keeps its selected option")
        keyboard.select.currentValue = 0
        keyboard.select.forceActiveFocus(Qt.TabFocusReason)
        keyboard.input.keyClick(Qt.Key_Return)
        keyboard.input.wait(Motion.normal + 60)
        const typedList = root._findTrayNode(keyboard.select, item => typeof item.positionViewAtIndex === "function")
        keyboard.input.keyClick(Qt.Key_End)
        const reachedEnd = typedList.currentIndex === 39
        keyboard.input.keyClick(Qt.Key_Home)
        const reachedHome = typedList.currentIndex === 0
        keyboard.input.keyClick(Qt.Key_PageDown)
        root._check(reachedEnd && reachedHome && typedList.currentIndex === 7,
            "Home, End and the page keys walk an open dropdown")
        for (const c of "option 17") keyboard.input.keyClick(c)
        root._check(typedList.currentIndex === 17 && keyboard.select._typed === "option 17"
                && keyboard.select._open,
            "typing finds a row, and a space in a name does not choose it")
        keyboard.input.keyClick(Qt.Key_Return)
        root._check(keyboard.select.currentValue === 17 && !keyboard.select._open
                && keyboard.select._typed === "",
            "Enter chooses the row typing found and clears the text")
        keyboard.input.keyClick(Qt.Key_Return)
        for (const c of "n 3") keyboard.input.keyClick(c)
        root._check(typedList.currentIndex === 3,
            "typing falls back to a match inside a name")
        keyboard.input.keyClick(Qt.Key_Backspace)
        root._check(keyboard.select._typed === "n ", "Backspace trims the typed text")
        keyboard.input.keyClick(Qt.Key_Return)
        keyboard.button.forceActiveFocus(Qt.TabFocusReason)
        keyboard.input.mouseMove(keyboard.select, 20, keyboard.select._headerH / 2)
        keyboard.input.mouseClick(keyboard.select, 20, keyboard.select._headerH / 2)
        keyboard.input.keyClick("o")
        root._check(keyboard.select.activeFocus && keyboard.select._pointerFocus && keyboard.select._typed === "o",
            "a dropdown opened by pointer hears typing without drawing a focus ring")
        keyboard.input.keyClick(Qt.Key_Return)
        keyboard.select.currentValue = 0
        keyboard.select.forceActiveFocus(Qt.TabFocusReason)
        keyboard.input.keyClick(Qt.Key_Return)
        for (let i = 0; i < 12; i++) keyboard.input.keyClick(Qt.Key_Down)
        keyboard.input.wait(Motion.normal + 100)
        const keyboardList = root._findTrayNode(keyboard.select, item => typeof item.positionViewAtIndex === "function")
        const keyboardCursor = keyboardList.currentItem
        const cursorBounds = keyboardCursor ? keyboardCursor.mapToItem(keyboardList, 0, 0,
            keyboardCursor.width, keyboardCursor.height) : null
        root._check(keyboardList.currentIndex === 12 && cursorBounds && cursorBounds.y >= -0.5
                && cursorBounds.y + cursorBounds.height <= keyboardList.height + 0.5,
            "dropdown expansion keeps the keyboard cursor visible instead of jumping to the committed choice")
        keyboard.select._setOpen(false)
        keyboard.select.model = [
            { value: 0, label: "Apple" }, { value: 1, label: "Apricot" },
            { value: 2, label: "Banana" }, { value: 3, label: "Blueberry" },
            { value: 4, label: "Cafeteria" }, { value: 5, label: "Café Noir" }
        ]
        keyboard.select.currentValue = 0
        keyboard.select.forceActiveFocus(Qt.TabFocusReason)
        keyboard.input.keyClick(Qt.Key_Return)
        keyboard.input.keyClick("b")
        const firstInitial = keyboardList.currentIndex
        keyboard.input.keyClick("b")
        const secondInitial = keyboardList.currentIndex
        keyboard.input.keyClick("b")
        root._check(firstInitial === 2 && secondInitial === 3 && keyboardList.currentIndex === 2
                && keyboard.select._typed === "b",
            "repeating an initial cycles matching dropdown choices and wraps")
        keyboard.input.keyClick("l")
        root._check(keyboardList.currentIndex === 3 && keyboard.select._typed === "bl",
            "typing another letter resumes prefix search after cycling")
        keyboard.select._setOpen(false)
        keyboard.select._setOpen(true)
        keyboard.input.keyClick("b")
        keyboard.input.keyClick("l")
        keyboard.input.keyClick(Qt.Key_Backspace)
        root._check(keyboardList.currentIndex === 2 && keyboard.select._typed === "b",
            "Backspace updates the dropdown selection to match the corrected query")
        keyboard.select._typed = ""
        for (const character of "cafe noir") keyboard.input.keyClick(character)
        root._check(keyboardList.currentIndex === 5,
            "dropdown search finds accented labels from unaccented typing")
        keyboard.select._setOpen(false)
        keyboard.select._typeAhead("a")
        root._check(keyboard.select._typed === "",
            "a closed dropdown ignores retained typeahead requests")
        keyboard.select._setOpen(true)
        keyboard.select._typeAhead("x".repeat(1000))
        root._check(keyboard.select._typed.length <= 256,
            "dropdown typeahead keeps a bounded query while typing continues")
        keyboard.select._setOpen(false)
        keyboard.close()
        keyboard.destroy()

        const listKeyboard = listKeyboardWindowFactory.createObject(root)
        listKeyboard.requestActivate()
        listKeyboard.input.wait(60)
        listKeyboard.list.forceLayout()
        listKeyboard.list.currentItem.forceActiveFocus(Qt.TabFocusReason)
        listKeyboard.input.keyClick(Qt.Key_Down)
        listKeyboard.input.wait(30)
        root._check(listKeyboard.list.currentIndex === 3 && listKeyboard.list.currentItem.activeFocus,
            "list arrows skip disabled and busy rows")
        listKeyboard.input.keyClick(Qt.Key_Up)
        listKeyboard.input.wait(30)
        root._check(listKeyboard.list.currentIndex === 0 && listKeyboard.list.currentItem.activeFocus,
            "list arrows skip inert rows in the reverse direction too")
        listKeyboard.onlyFirst = true
        listKeyboard.input.keyClick(Qt.Key_Down)
        listKeyboard.input.wait(30)
        root._check(listKeyboard.list.currentIndex === 0 && listKeyboard.list.currentItem.activeFocus,
            "a list with no later usable row keeps its original focus and current index")
        listKeyboard.onlyFirst = false
        listKeyboard.entries = Array.from({ length: 100 }, (_, i) => ({ label: "Row " + i,
            enabled: i === 0 || i === 99 }))
        listKeyboard.list.currentIndex = 0
        listKeyboard.list.forceLayout()
        listKeyboard.input.wait(20)
        listKeyboard.list.currentItem.forceActiveFocus(Qt.TabFocusReason)
        listKeyboard.input.keyClick(Qt.Key_Down)
        // the search advances one delegate per event-loop turn, so a 98-row
        // disabled span settles in far more turns than a fixed pause can bound
        // once other probes share the machine; wait for the destination to
        // actually arrive rather than guess a duration
        for (let w = 0; w < 80 && listKeyboard.list.currentIndex !== 99; w++)
            listKeyboard.input.wait(25)
        listKeyboard.input.wait(30)
        root._check(listKeyboard.list.currentIndex === 99 && listKeyboard.list.currentItem
                && listKeyboard.list.currentItem.activeFocus,
            "list navigation skips a long disabled range even when its original delegate is pooled")
        listKeyboard.list.currentIndex = 0
        listKeyboard.list.positionViewAtIndex(0, ListView.Beginning)
        listKeyboard.list.forceLayout()
        listKeyboard.input.wait(20)
        listKeyboard.list.currentItem.forceActiveFocus(Qt.TabFocusReason)
        listKeyboard.input.keyClick(Qt.Key_Down)
        listKeyboard.outside.forceActiveFocus(Qt.TabFocusReason)
        listKeyboard.input.wait(60)
        root._check(listKeyboard.outside.activeFocus,
            "a pending list search cannot steal focus after the user moves to another control")
        listKeyboard.close()
        listKeyboard.destroy()

        const launcherWas = ShellSettings.lockCommandCustom
        ShellSettings.lockCommandCustom = "fuzzel"
        const focusScroll = focusScrollWindowFactory.createObject(root)
        focusScroll.requestActivate()
        focusScroll.input.wait(60)
        const commandField = root._findTrayNode(focusScroll.editor, item => item.maximumLength !== undefined)
        focusScroll.button.forceActiveFocus(Qt.TabFocusReason)
        focusScroll.input.keyClick(Qt.Key_Tab)
        focusScroll.input.wait(30)
        const fieldBounds = commandField.parent.mapToItem(focusScroll.scroller, 0, 0,
            commandField.parent.width, commandField.parent.height)
        root._check(commandField.activeFocus && fieldBounds.y >= -0.5
                && fieldBounds.y + fieldBounds.height <= focusScroll.scroller.height + 0.5,
            "Tab reveals the complete command field when it starts below the viewport")
        commandField.cursorPosition = commandField.text.length
        focusScroll.input.keyClick(Qt.Key_Space)
        focusScroll.input.keyClick(Qt.Key_X)
        root._check(focusScroll.editor.draft === "fuzzel x" && ShellSettings.lockCommandCustom === "fuzzel",
            "revealing a native field keeps ordinary typing and spaces in the unsaved draft")
        focusScroll.scroller.contentY = 0
        focusScroll.scroller.flick(0, -1000)
        focusScroll.input.keyClick(Qt.Key_Tab)
        focusScroll.input.wait(30)
        root._check(!focusScroll.scroller.flicking && focusScroll.scroller.contentY > 0,
            "keyboard focus stops an active flick so the revealed control stays visible")
        focusScroll.close()
        focusScroll.destroy()
        ShellSettings.lockCommandCustom = launcherWas

        const vpnProfiles = Vpn.parseProfiles("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa:vpn:Work\\:one:no\n"
            + "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb:wireguard:Work:yes\n"
            + "cccccccc-cccc-cccc-cccc-cccccccccccc:ethernet:Ethernet:yes\n"
            + "invalid:vpn:Invalid:yes")
        root._check(vpnProfiles.length === 2 && vpnProfiles[0].active
                && vpnProfiles[1].name === "Work:one" && vpnProfiles[0].uuid !== vpnProfiles[1].uuid,
            "saved VPN parsing preserves escaped names and identifies multiple profiles by UUID")
        const vpnWas = Vpn.profiles
        const vpnAnswer = () => Vpn.parseProfiles("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa:vpn:Work:no\n")
        Vpn._publishProfiles(vpnAnswer())
        const vpnPublished = Vpn.profiles
        Vpn._publishProfiles(vpnAnswer())
        root._check(vpnPublished.length === 1 && Vpn.profiles === vpnPublished,
            "an unchanged VPN poll keeps its list, so open rows and focus survive")
        Vpn._publishProfiles(Vpn.parseProfiles("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa:vpn:Work:yes\n"))
        root._check(Vpn.profiles !== vpnPublished && Vpn.profiles[0].active,
            "a VPN that connects does update the list")
        Vpn.profiles = vpnWas

        root._check(PowerProfiles.profileForSource(false, "balanced", "power-saver", "power-saver") === "balanced"
                && PowerProfiles.profileForSource(true, "balanced", "power-saver", "balanced") === "power-saver"
                && PowerProfiles.profileForSource(true, "balanced", "", "balanced") === ""
                && PowerProfiles.profileForSource(false, "balanced", "power-saver", "balanced") === "",
            "a power source restores the mode last picked on it, and leaves an unpicked source alone")

        const bt = (pct) => [{ address: "AA", name: "Headset", pct: pct }]
        let btStep = SystemAlerts.btAlertStep({}, bt(18), 20, 25)
        const btFirst = btStep.alerts.length === 1 && btStep.alerts[0].name === "Headset"
        btStep = SystemAlerts.btAlertStep(btStep.warned, bt(15), 20, 25)
        const btOnce = btStep.alerts.length === 0
        btStep = SystemAlerts.btAlertStep(btStep.warned, bt(22), 20, 25)
        const btHeld = btStep.alerts.length === 0 && btStep.warned.AA === true
        const btRearmed = SystemAlerts.btAlertStep(
            SystemAlerts.btAlertStep(btStep.warned, bt(30), 20, 25).warned, bt(18), 20, 25).alerts.length === 1
        const btReconnect = SystemAlerts.btAlertStep(
            SystemAlerts.btAlertStep(btStep.warned, [], 20, 25).warned, bt(18), 20, 25).alerts.length === 1
        root._check(btFirst && btOnce && btHeld && btRearmed && btReconnect,
            "a bluetooth device warns once when low, and again only after charging or reconnecting")
        const missingBattery = SystemAlerts.btAlertStep({ AA: true }, bt(-1), 20, 25)
        root._check(missingBattery.warned.AA === true && missingBattery.alerts.length === 0
                && SystemAlerts.btAlertStep(missingBattery.warned, bt(18), 20, 25).alerts.length === 0,
            "a missing connected Bluetooth battery reading cannot rearm a sent warning")
        root._check([-1, NaN, Infinity, null, "18", 101].every(value =>
                SystemAlerts.btAlertStep({}, bt(value), 20, 25).alerts.length === 0),
            "missing or invalid Bluetooth battery readings never become low-battery alerts")
        root._check(SystemAlerts.btAlertStep({}, bt(0), 20, 25).alerts.length === 1,
            "a real zero-percent Bluetooth reading still warns")

        // a minute tick armed before suspend fires late after wake; catching up re-reads the wall clock
        DateTime._lastMinute = "190001010000"
        DateTime.catchUp()
        root._check(DateTime._lastMinute === Qt.formatDateTime(new Date(), "yyyyMMddHHmm")
                && !DateTime._resync,
            "a stale clock catches up to the wall clock on a wake-time event")
    }

    function _checksNightLightAndSensors(): void {
        // the sun arc writes hours and minutes as the battery and uptime do
        root._check(NightLight._dur(65) === "1h 5m" && NightLight._dur(120) === "2h 0m"
                && NightLight._dur(45) === "45m" && NightLight._dur(-3) === "0m",
            "the sun arc writes minutes without a leading zero, as the battery and uptime do")

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
        SystemTools._tools = { wlsunset: true, pgrep: true }
        SystemTools.ready = true
        ShellSettings.nightLightProvider = "wlsunset"
        NightLight.toggle()
        root._check(NightLight.toolAvailable && NightLight._sandboxed && !NightLight.enabled
                && ShellSettings.nightLightOn === nightOnWas
                && NightLight._runningTool === "" && !NightLight._probedOnce,
            "a test copy of the shell never adopts, starts or stops the live night light")
        const nightRestoreWas = NightLight._restoreDone
        NightLight._restoreDone = true
        ShellSettings.nightLightOn = !ShellSettings.nightLightOn
        root._check(!NightLight.enabled && NightLight._runningTool === "" && !NightLight._toggling,
            "a restore that flips night light in a test copy still leaves the live one alone")
        ShellSettings.nightLightOn = nightOnWas
        NightLight._restoreDone = nightRestoreWas
        const nightErrorWas = NightLight.lastError
        for (const result of [
            { code: 127, status: 0, timedOut: false },
            { code: 1, status: 1, timedOut: false },
            { code: 15, status: 1, timedOut: false },
            { code: 0, status: 0, timedOut: true },
            { code: 2, status: 0, timedOut: false }
        ]) {
            NightLight._runningTool = "wlsunset"
            NightLight._pendingEnable = true
            NightLight._acceptStopResult(result.code, result.status, result.timedOut)
            root._check(NightLight.lastError === "Could not stop the external night light"
                    && NightLight._runningTool === "wlsunset" && !NightLight._pendingEnable
                    && !NightLight.enabled,
                "a failed night-light stop preserves its source and cancels a queued replacement: "
                    + JSON.stringify(result))
        }
        for (const code of [0, 1]) {
            NightLight._acceptStopResult(code, 0, false)
            root._check(NightLight.lastError === "" && NightLight._runningTool === "",
                "a confirmed night-light stop or no-match clears its previous failure: " + code)
            NightLight._runningTool = "wlsunset"
        }
        NightLight._runningTool = ""
        NightLight.lastError = nightErrorWas
        ShellSettings.nightLightOn = nightOnWas
        ShellSettings.nightLightProvider = nightProviderWas
        SystemTools._tools = nightToolsWas
        SystemTools.ready = nightReadyWas

        const geoResolvedWas = NightLight._geoResolved
        const winterLon = -new Date(2026, 0, 1).getTimezoneOffset() / 4
        const summerLon = -new Date(2026, 6, 1).getTimezoneOffset() / 4
        root._check(NightLight.standardOffsetLon(2026) === Math.min(winterLon, summerLon),
            "the fallback longitude follows standard time, not summer time")
        const autoLatWas = NightLight._autoLat
        const autoLonWas = NightLight._autoLon
        root._check(NightLight._parseCoord("+5657+02406")
                && Math.abs(NightLight._autoLat - 56.95) < 0.0001
                && Math.abs(NightLight._autoLon - 24.1) < 0.0001,
            "night light parses a valid zone-table coordinate")
        root._check(NightLight._geoOffset === new Date().getTimezoneOffset()
                && NightLight.zoneMoved(true, 120, 60) && !NightLight.zoneMoved(true, 120, 120)
                && !NightLight.zoneMoved(false, 120, 60),
            "night light notes the time zone a place was found under, and looks again only once that changes")
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
        if (vitals) {
            const diskRow = root._findTrayNode(vitals, item => item.label === "Disk" && item.sub !== undefined)
            const diskWas = [SysInfo.diskTotalKb, SysInfo.diskAvailKb]
            SysInfo.diskTotalKb = 1000; SysInfo.diskAvailKb = 0
            const fullCaption = diskRow ? diskRow.sub : ""
            SysInfo.diskTotalKb = 0
            root._check(fullCaption === "Full" && diskRow.sub === "",
                "a full disk says so in its caption, and an unread disk leaves the caption empty")
            SysInfo.diskTotalKb = diskWas[0]; SysInfo.diskAvailKb = diskWas[1]
            const cpuRow = root._findTrayNode(vitals, item => item.label === "CPU" && item.sub !== undefined)
            const busiestWas = [SysInfo.topShown, SysInfo.topName, SysInfo.topPid]
            SysInfo.topName = "ffmpeg"; SysInfo.topPid = 41; SysInfo.topShown = true
            const busiestCaption = cpuRow ? cpuRow.sub : ""
            SysInfo.topShown = false
            root._check(busiestCaption.endsWith("ffmpeg (41)") && cpuRow.sub.indexOf("ffmpeg") < 0,
                "Home's CPU caption names the busiest process while it matters, beside the temperature")
            SysInfo.topShown = busiestWas[0]; SysInfo.topName = busiestWas[1]; SysInfo.topPid = busiestWas[2]
            const reduceWas = ShellSettings.reduceMotion
            ShellSettings.reduceMotion = false
            vitals.active = true
            vitals._introRows()
            const row = root._findTrayNode(vitals, item => typeof item.settleIntro === "function")
            root._check(row !== null && row._grow === 0,
                "the home vitals intro starts while its page is active")
            vitals.active = false
            root._check(row !== null && row._grow === 1,
                "leaving home settles its intro instead of animating a cached page")
            vitals.active = true
            vitals._introRows()
            ShellSettings.reduceMotion = true
            root._check(row !== null && row._grow === 1,
                "enabling reduced motion settles an in-progress vitals intro")
            ShellSettings.reduceMotion = reduceWas
            vitals.destroy()
        }
        root._check(NightLight._probeState(0, 0, false, false) === 1
                && NightLight._probeState(1, 0, false, false) === 0
                && NightLight._probeState(1, 0, false, true) === 1
                && NightLight._probeState(0, 0, true, true) === -1
                && NightLight._probeState(2, 0, false, false) === -1
                && NightLight._probeState(-1, 0, false, false) === -1,
            "night light distinguishes an external daemon, no match, and a failed state probe")
        root._check(NightLight._probeState(1, 1, false, false) === -1
                && NightLight._probeState(1, 1, false, true) === -1,
            "a crashed night-light state probe cannot claim the daemon is absent or trigger its restoration")
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
    }

    function _checksBatteryAndHooks(): void {
        root._check(Battery.normalizedPercent(0.64) === 64
                && Battery.normalizedPercent(1) === 100
                && Battery.normalizedPercent(1.4) === 100
                && Battery.normalizedPercent(-1) === 0
                && Battery.normalizedPercent(NaN) === 0,
            "battery percentage reads quickshell's 0-1 charge and stays bounded")
        const detailBattery = { ready: true, isPresent: true, powerSupply: true,
            type: Up.UPowerDeviceType.Battery, state: Up.UPowerDeviceState.Discharging,
            percentage: 0.64, healthSupported: true, healthPercentage: 92,
            energy: 32, energyCapacity: 50, changeRate: 12.3, model: "Fixture battery", nativePath: "BAT1" }
        const batteryDetails = Battery.detailsFor([detailBattery])
        root._check(batteryDetails.length === 1 && batteryDetails[0].charge === "64%"
                && batteryDetails[0].health === "92%" && batteryDetails[0].energy === "32 / 50 Wh"
                && batteryDetails[0].power === "12.3 W" && batteryDetails[0].powerLabel === "Power use",
            "battery details preserve health's native percent and energy and power units")
        root._check(batteryDetails[0].nativePath === "BAT1"
                && Battery.detailsFor([Object.assign({}, detailBattery, { nativePath: undefined })])[0].nativePath === "",
            "each battery's details carry the kernel's name for it, which ties the row to its charge limit")
        const limitPath = "/org/freedesktop/UPower/devices/battery_"
        const limitRows = BatteryLimit.parseDevices([
            limitPath + "BAT1\tBAT1\ton\t0", limitPath + "BAT0\tBAT0\toff\t80",
            limitPath + "BAT1\tBAT1\toff\t0", "/org/freedesktop/UPower/KbdBacklight\tBAT2\ton\t0",
            limitPath + "BAT3\t../BAT1\ton\t0", limitPath + "BAT4\tBAT4\tmaybe\t0",
            limitPath + "BAT5\tBAT5\ton\t100", limitPath + "BAT6\tBAT6\ton", ""].join("\n"))
        root._check(limitRows.length === 2 && limitRows[0].nativePath === "BAT1" && limitRows[0].on
                && limitRows[0].stopsAt === 0 && limitRows[0].path === limitPath + "BAT1"
                && limitRows[1].nativePath === "BAT0" && !limitRows[1].on && limitRows[1].stopsAt === 80,
            "charge limit rows keep a battery object with a plain name, a state and a stop under 100, once each")
        root._check(BatteryLimit.describe({ on: true, stopsAt: 80 }) === "Stops at 80% to slow wear"
                && BatteryLimit.describe({ on: true, stopsAt: 0 }) === "Stops short of full to slow wear"
                && BatteryLimit.describe(null) === "",
            "the charge limit names its stop where the kernel gives one, and only its intent where it gives none")
        const bareBattery = Battery.detailsFor([Object.assign({}, detailBattery, { state: Up.UPowerDeviceState.FullyCharged,
            healthSupported: false, energyCapacity: 0, changeRate: 0 })])
        root._check(bareBattery.length === 1 && !Battery.detailsShown(bareBattery) && Battery.detailsShown(batteryDetails)
                && Battery.detailsShown(bareBattery.concat(bareBattery)),
            "one battery with no health, energy or power reading offers no details panel, since nothing would be in it")
        const twoBatteries = Battery.detailsFor([detailBattery,
            Object.assign({}, detailBattery, { state: Up.UPowerDeviceState.Charging, percentage: 0,
                healthSupported: false, energyCapacity: 0, changeRate: 9 })])
        root._check(twoBatteries.length === 2 && twoBatteries[0].name !== twoBatteries[1].name
                && twoBatteries[1].charge === "0%" && twoBatteries[1].health === ""
                && twoBatteries[1].energy === "" && twoBatteries[1].powerLabel === "Charging power",
            "multiple batteries retain their own readings and omit unsupported measurements")
        root._check(Battery.detailsFor([null, Object.assign({}, detailBattery, { ready: false }),
                Object.assign({}, detailBattery, { isPresent: false }),
                Object.assign({}, detailBattery, { powerSupply: false })]).length === 0,
            "battery details exclude unready, absent and peripheral batteries")
        const upsDetails = Battery.detailsFor([Object.assign({}, detailBattery, { type: Up.UPowerDeviceType.Ups,
            healthPercentage: NaN, energy: Infinity, changeRate: -1, percentage: NaN })])[0]
        root._check(upsDetails.name === "UPS" && upsDetails.charge === "" && upsDetails.health === ""
                && upsDetails.energy === "" && upsDetails.power === "",
            "UPS details reject malformed measurements without displaying invented zeros")
        const batteryAndUps = Battery.detailsFor([detailBattery, Object.assign({}, detailBattery, {
            type: Up.UPowerDeviceType.Ups, state: Up.UPowerDeviceState.Charging, changeRate: -8.5 })])
        root._check(batteryAndUps[0].name === "Battery" && batteryAndUps[1].name === "UPS" && batteryAndUps[1].power === "8.5 W",
            "a battery beside a UPS keeps plain names, and a charging rate signed as UPower's spec allows still shows")
        root._check(Battery.validReading(true, 0.01) && Battery.validReading(true, 0.72),
            "a battery with any charge keeps its readout and warning eligibility")
        root._check(!Battery.validReading(true, 0)
                && !Battery.validReading(false, 0.5)
                && !Battery.validReading(true, NaN)
                && !Battery.validReading(true, -1),
            "the boot placeholder, an absent or an invalid battery is neither drawn nor warned about")
        root._check(Battery.statusFor(true, Up.UPowerDeviceState.PendingCharge, false, false) === "charge limit"
                && Battery.statusFor(true, Up.UPowerDeviceState.PendingCharge, true, false) === "not charging"
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
        let batteryNotice = Battery.notificationStateFor(null, false, 0,
            false, false, false, 20, 10)
        root._check(batteryNotice === null,
            "an unavailable startup battery cannot seed notification state")
        const loginLow = Battery.notificationStateFor(null, true, 15,
            true, false, false, 20, 10)
        root._check(loginLow.warning === "" && loginLow.lowSeen && !loginLow.criticalSeen,
            "a low battery at login is a quiet baseline")
        root._check(Battery.notificationStateFor(loginLow, true, 9,
                true, false, false, 20, 10).warning === "critical",
            "a low login baseline still warns when it turns critical")
        batteryNotice = Battery.notificationStateFor(batteryNotice, true, 8,
            true, false, false, 20, 10)
        root._check(batteryNotice.warning === "critical" && batteryNotice.lowSeen && batteryNotice.criticalSeen,
            "a critical battery at login warns even when UPower reports late")
        batteryNotice = Battery.notificationStateFor(batteryNotice, true, 7,
            true, false, false, 20, 10)
        root._check(batteryNotice.warning === "critical",
            "a critical warning holds steady while the level keeps falling")
        batteryNotice = Battery.notificationStateFor(batteryNotice, true, 50,
            true, false, false, 20, 10)
        batteryNotice = Battery.notificationStateFor(batteryNotice, true, 19,
            true, false, false, 20, 10)
        root._check(batteryNotice.warning === "low",
            "a real low-battery crossing after login raises a warning")
        batteryNotice = Battery.notificationStateFor(batteryNotice, true, 20,
            true, false, false, 20, 10)
        batteryNotice = Battery.notificationStateFor(batteryNotice, true, 19,
            true, false, false, 20, 10)
        root._check(batteryNotice.warning === "",
            "a reading that wobbles around the low threshold does not repeat its alert")
        batteryNotice = Battery.notificationStateFor(batteryNotice, true, 9,
            true, false, false, 20, 10)
        root._check(batteryNotice.warning === "critical",
            "an existing low warning can still escalate to critical")
        const batteryNoticeBeforeDropout = batteryNotice
        batteryNotice = Battery.notificationStateFor(batteryNotice, false, 0,
            false, false, false, 20, 10)
        root._check(batteryNotice === batteryNoticeBeforeDropout,
            "a backend dropout preserves battery notification state")
        batteryNotice = Battery.notificationStateFor(batteryNotice, true, 9,
            false, true, false, 20, 10)
        root._check(batteryNotice.warning === "" && !batteryNotice.lowSeen && !batteryNotice.criticalSeen,
            "plugging in below both thresholds clears warnings and rearms them")
        batteryNotice = Battery.notificationStateFor(batteryNotice, true, 9,
            true, false, false, 20, 10)
        root._check(batteryNotice.warning === "critical" && batteryNotice.lowSeen,
            "a jump directly to critical raises only the critical warning")
        const startupFull = Battery.notificationStateFor(null, true, 100,
            false, false, true, 20, 10)
        root._check(startupFull.chargeRevision === 0 && !startupFull.chargeComplete,
            "an initially full battery never announces a completed charge")
        let chargeNotice = Battery.notificationStateFor(null, true, 80,
            false, true, false, 20, 10)
        chargeNotice = Battery.notificationStateFor(chargeNotice, true, 99,
            false, true, true, 20, 10)
        root._check(chargeNotice.chargeRevision === 1 && chargeNotice.chargeComplete,
            "a charge observed after login announces completion")
        chargeNotice = Battery.notificationStateFor(chargeNotice, true, 98,
            false, true, false, 20, 10)
        chargeNotice = Battery.notificationStateFor(chargeNotice, true, 99,
            false, true, true, 20, 10)
        root._check(chargeNotice.chargeRevision === 1 && !chargeNotice.chargeComplete,
            "full-charge jitter neither repeats an alert nor revives an expired completion")
        chargeNotice = Battery.notificationStateFor(chargeNotice, true, 96,
            true, false, false, 20, 10)
        chargeNotice = Battery.notificationStateFor(chargeNotice, true, 96,
            false, true, false, 20, 10)
        chargeNotice = Battery.notificationStateFor(chargeNotice, true, 100,
            false, false, true, 20, 10)
        root._check(chargeNotice.chargeRevision === 2 && chargeNotice.chargeComplete,
            "a later charge cycle can announce completion again")
        let plugFull = Battery.notificationStateFor(null, true, 100,
            true, false, true, 20, 10)
        plugFull = Battery.notificationStateFor(plugFull, true, 100,
            false, false, true, 20, 10)
        root._check(plugFull.chargeRevision === 0 && !plugFull.chargeComplete,
            "plugging in an already-full battery is not a completed charge")
        root._check(Network.formatRate(1023.4) === "1023 B/s " && Network.formatRate(1023.6) === " 1.0 KB/s"
                && Network.formatRate(1048575) === " 1.0 MB/s" && Network.formatRate(1073741823) === " 1.0 GB/s"
                && Network.formatRate(102350) === " 100 KB/s" && Network.formatRate(0) === "   0 B/s ",
            "a traffic rate that rounds up to 1024 moves to the next unit instead of printing 1024")
        root._check(Network.wifiPasswordless(Net.WifiSecurityType.Unknown, false) && !Network.wifiPasswordless(Net.WifiSecurityType.Unknown, true)
                && Network.wifiPasswordless(Net.WifiSecurityType.Open, true) && !Network.wifiPasswordless(Net.WifiSecurityType.Wpa2Psk, false),
            "an Unknown network joins without a password only where quickshell 0.3.1 mislabels open ones")
        root._check(SystemTools.versionAtLeast("0.3.2", "0.3.2") && SystemTools.versionAtLeast("0.4", "0.3.2")
                && SystemTools.versionAtLeast("0.3.10", "0.3.2") && !SystemTools.versionAtLeast("0.3.1", "0.3.2")
                && !SystemTools.versionAtLeast("", "0.3.2") && !SystemTools.versionAtLeast("git", "0.3.2"),
            "Quickshell version gates compare numerically and stay closed on an unknown version")
        root._check(OsdBarState.holdFor("volume", 2000) === 2000 && OsdBarState.holdFor("battery", 2000) === 5000
                && OsdBarState.holdFor("temp", 8000) === 8000 && OsdBarState.holdFor("brightness", 100) === 500,
            "an alert stays up long enough to read while level feedback keeps the chosen timeout")
        root._check(OsdBarState.powerChangeShown("balanced", "performance", false)
                && !OsdBarState.powerChangeShown("", "balanced", false)
                && !OsdBarState.powerChangeShown("balanced", "", false)
                && !OsdBarState.powerChangeShown("balanced", "balanced", false)
                && !OsdBarState.powerChangeShown("balanced", "power-saver", true)
                && !OsdBarState._hasBarKind("power"),
            "a power mode change shows a label-only osd, but not the first read, a daemon restart or under the open menu")
        root._check(SystemAlerts.criticalPopupFor(true, true, false, false)
                && SystemAlerts.criticalPopupFor(true, true, true, true)
                && !SystemAlerts.criticalPopupFor(true, true, false, true)
                && !SystemAlerts.criticalPopupFor(true, false, true, false)
                && !SystemAlerts.criticalPopupFor(false, true, true, false),
            "a critical alert takes the desktop popup only where one appears, and the OSD otherwise")
        root._check(!SystemAlerts.criticalPopsUp,
            "a sandboxed run never sends a desktop alert, so its critical alerts stay in the OSD")
        const gpuMem = "MemTotal: 1000 kB\nPageTables: 400 kB\n"
        root._check(SysInfo.gpuReclaimKb("nr_page_table_pages 100\nnr_gpu_reclaim 25\n", gpuMem) === 100,
            "the GPU pool converts from pages at the size this machine uses")
        root._check(SysInfo.gpuReclaimKb("nr_page_table_pages 25\nnr_gpu_reclaim 25\n", gpuMem) === 400,
            "a 16K page kernel reads the same pool correctly")
        root._check(SysInfo.gpuReclaimKb("nr_gpu_reclaim 25\n", "") === 100,
            "without page tables to compare, the pool assumes ordinary pages")
        root._check(SysInfo.gpuReclaimKb("nr_anon_pages 25\n", gpuMem) === 0,
            "a kernel that does not count the pool leaves the reading alone")
        root._check(!ShellSettings.firstRun && !ShellSettings.trayWidget,
            "a profile that already has a settings file is not greeted as a new one, and keeps the tray's default")
        ShellSettings._firstRun = true
        ShellSettings.markFirstRunSeen()
        root._check(!ShellSettings.firstRun,
            "the welcome is spent once sent, so a later start in the same session cannot repeat it")
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

        // a run is counted by its budget stamp; the hook file does not exist, so nothing it names can start
        const hookPresentWas = Hooks._present
        const hookRunTimesWas = Hooks._runTimes
        const hookCriticalTimesWas = Hooks._criticalTimes
        const battStateWas = Battery._notificationState
        Hooks._runTimes = []
        Hooks._criticalTimes = []
        Hooks._present = { "battery-critical": true }
        let wobbleState = null
        for (const pct of [11, 9.9, 10.1, 9.9, 10.2, 9.8]) {
            wobbleState = Battery.notificationStateFor(wobbleState, true, pct, true, false, false, 20, 10)
            Battery._notificationState = wobbleState
        }
        root._check(Hooks._runTimes.length === 1,
            "the battery-critical hook runs once per settled crossing, not again as the level wobbles across the line")
        Hooks._present = hookPresentWas
        Battery._notificationState = battStateWas

        const updateCountWas = Updates.count
        Updates.count = 5
        Hooks._runTimes = []
        Hooks._present = { "update-available": true }
        Updates.count = 2
        const updateDropRuns = Hooks._runTimes.length
        Updates.count = 4
        root._check(updateDropRuns === 0 && Hooks._runTimes.length === 1,
            "an update-available hook found by a rescan fires on the next rise, never on a falling count")
        Hooks._present = hookPresentWas
        Updates.count = updateCountWas

        Hooks._runTimes = []
        Hooks._workspaceKey = "stale"
        Hooks._present = { "workspace-changed": true }
        root._check(Hooks._workspaceKey === Hooks._workspaceKeyOf(Compositor.focusedWorkspaceRef,
                    Compositor.activeWorkspace(Compositor.focusedMonitor)),
            "a workspace-changed hook found by a rescan starts from the workspace already shown")
        const threeWs = { wsId: 3, name: "3", output: "DP-1", active: true }
        const mailWs = { wsId: -1338, name: "mail", output: "DP-1", active: true }
        const chatWs = { wsId: -1338, name: "chat", output: "DP-1", active: true }
        for (const [ref, ws] of [[3, threeWs], [-1338, mailWs], [-1338, chatWs], [-1338, chatWs], [-1, null]])
            Hooks._workspaceSeen(ref, ws)
        root._check(Hooks._runTimes.length === 3
                && Hooks._workspaceArgument(threeWs) === "3" && Hooks._workspaceArgument(chatWs) === "chat",
            "the workspace-changed hook hears a switch between two named workspaces, gets the number or the name, and stays quiet for a lost workspace")
        Hooks._present = hookPresentWas
        Hooks._runTimes = hookRunTimesWas
        Hooks._criticalTimes = hookCriticalTimesWas
    }

    function _checksDispatchAndNotificationOwner(): void {
        // the fallback a refused dispatch takes, run as written behind a hyprctl that refuses
        const toolsWas = SystemTools._tools, toolsReadyWas = SystemTools.ready
        SystemTools._tools = Object.assign({}, toolsWas, { hyprctl: true })
        SystemTools.ready = true
        const fallback = HyprDispatch.launchCommand(["sh", "-c", "printf %s \"${SILERE_GLOBAL_SHORTCUTS-unset}\""])
        SystemTools._tools = toolsWas
        SystemTools.ready = toolsReadyWas
        const fallbackRun = processFactory.createObject(root, { command: ["bash", "-c",
            "d=$(mktemp -d) || exit 2; printf '#!/bin/sh\\nexit 1\\n' > \"$d/hyprctl\"; chmod +x \"$d/hyprctl\"; "
            + "out=$(PATH=\"$d:$PATH\" SILERE_GLOBAL_SHORTCUTS=1 \"$@\"); rm -rf \"$d\"; [ \"$out\" = unset ]",
            "bash"].concat(fallback) })
        fallbackRun.exited.connect(function(code) {
            root._check(code === 0, "an app a refused dispatch starts here does not inherit the shell's global shortcut claim")
            root._launchEnvDone = true
            fallbackRun.destroy()
        })
        fallbackRun.running = true
        root._check(Hooks._runner0.environment && Hooks._runner0.environment.SILERE_GLOBAL_SHORTCUTS === null,
            "hooks run without the shell's global shortcut claim")

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
        root._check(HyprDispatch._text("exec", "'a b'") === "exec 'a b'",
            "a classic config launches through the exec dispatcher")
        HyprDispatch.useLua = true
        root._check(HyprDispatch._text("exec", "'q\"x' 'back\\slash'\n\r")
                === "hl.dsp.exec_cmd(\"'q\\\"x' 'back\\\\slash'\\n\\r\")",
            "a Lua launch escapes quotes, backslashes and line breaks for the Lua string")
        HyprDispatch.useLua = luaWas

        const spacing = ShellSettings.schemaFor("barSpacing")
        root._check(spacing !== null && spacing.t === "int"
                && spacing.min === 4 && spacing.max === 12 && spacing.step === 4,
            "settings expose a row's schema by key")
        root._check(ShellSettings.schemaFor("noSuchSetting") === null,
            "settings reject an unknown schema key")
        root._check(ShellSettings.schemaFor("barRadius").sec === "surface",
            "roundness is attributed to the one page that carries its row")
        const spacingWas = ShellSettings.barSpacing
        ShellSettings.setValue("barSpacing", 999)
        root._check(ShellSettings.barSpacing === 12,
            "a key-bound row clamps to the schema maximum")
        ShellSettings.setValue("barSpacing", 7)
        root._check(ShellSettings.barSpacing === 8,
            "an old widget gap between presets snaps to the nearest one")
        ShellSettings.setValue("barSpacing", -5)
        root._check(ShellSettings.barSpacing === 4,
            "a key-bound row clamps to the schema minimum")
        ShellSettings.setValue("noSuchSetting", 1)

        // the tray gap once grew wider than the widget gap it sits inside, at both
        // ends of the range; each formula was fine alone, only the ordering broke
        let gapOrderHolds = true
        let gapSaturates = true
        let lastCompactGap = -1
        for (let s = spacing.min; s <= spacing.max; s += spacing.step) {
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

        let textFits = true, fitIsMonotonic = true
        for (const centeredInGap of [false, true]) {
            for (const hasCenter of [false, true]) {
                for (let titleZone = 0; titleZone < 3; titleZone++) {
                    const zones = [{ fixed: 80, flexible: 0 },
                        { fixed: hasCenter ? 24 : 0, flexible: 0 },
                        { fixed: 140, flexible: 0 }]
                    if (!hasCenter && titleZone === 1) continue
                    zones[titleZone].flexible = 180
                    zones[titleZone === 2 ? 0 : 2].flexible += 120
                    let previous = -1
                    for (const capacity of [0, 240, 320, 400, 600, 900]) {
                        const scale = Metrics.barTextFit(zones[0], zones[1], zones[2],
                            hasCenter, capacity, 12, centeredInGap)
                        const fixed = Metrics.barLayoutWidth(zones[0].fixed, zones[1].fixed,
                            zones[2].fixed, hasCenter, 12, centeredInGap)
                        const fitted = zones.map(zone => zone.fixed + zone.flexible * scale)
                        const span = Metrics.barLayoutWidth(fitted[0], fitted[1], fitted[2],
                            hasCenter, 12, centeredInGap)
                        if (!isFinite(scale) || scale < 0 || scale > 1
                                || (fixed <= capacity && span > capacity + 0.001)) textFits = false
                        if (scale < previous) fitIsMonotonic = false
                        previous = scale
                    }
                }
            }
        }
        root._check(textFits,
            "flexible bar text fits around controls in every zone under both centring modes")
        root._check(fitIsMonotonic,
            "widening a bar never reduces the space allocated to flexible text")
        root._check(Metrics.barTextFit({ fixed: 100, flexible: 0 }, { fixed: 0, flexible: 0 },
                { fixed: 100, flexible: 0 }, false, 0, 12, false) === 1,
            "a bar without flexible text keeps finite budgets even with no available width")

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
        root._check(ShellSettings._ipcSet("BARSPACING", "999") === "12"
                && ShellSettings.barSpacing === 12,
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
        root._check(ShellSettings.constraintOf("barSpacing") === "4..12 in steps of 4",
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
        Hooks._runTimes = Array(Hooks.maxRunsPerSecond).fill(Date.now() + 3 * 3600 * 1000)
        root._check(Hooks._budgetAllows(),
            "hook runs stamped before the wall clock stepped back do not hold the budget")
        Hooks._runTimes = []

        const hooksPresentWas = Hooks._present
        const hooksFoundWas = Hooks._found
        const hooksDelayWas = Hooks._rescanDelayMs
        Hooks._present = { probe: true }
        const knownHooks = Hooks._present
        Hooks._found = { partial: true }
        Hooks._rescanDelayMs = 0
        Hooks._acceptScanResult(127, false)
        root._check(Hooks._present === knownHooks && Object.keys(Hooks._found).length === 0
                && Hooks._rescanDelayMs === Hooks._minRescanDelayMs,
            "a hook scanner that fails to start keeps known hooks, discards partial input, and retries")
        Hooks._acceptScanResult(1, false)
        root._check(Hooks._present === knownHooks
                && Hooks._rescanDelayMs === 2 * Hooks._minRescanDelayMs,
            "a nonzero hook scan exit backs off instead of disarming hooks")
        Hooks._rescanDelayMs = Hooks._maxRescanDelayMs
        Hooks._acceptScanResult(0, true)
        root._check(Hooks._present === knownHooks
                && Hooks._rescanDelayMs === Hooks._maxRescanDelayMs,
            "a truncated hook scan keeps its previous list and caps retry backoff")
        Hooks._found = { recovered: true }
        Hooks._acceptScanResult(0, false)
        root._check(Hooks.has("recovered") && !Hooks.has("probe")
                && Hooks._rescanDelayMs === 0 && Object.keys(Hooks._found).length === 0,
            "a successful hook scan replaces the known list and resets retry backoff")
        Hooks._acceptScanResult(0, false)
        root._check(Object.keys(Hooks._present).length === 0,
            "a successful empty hook scan still removes hooks that are gone")
        Hooks._present = hooksPresentWas
        Hooks._found = hooksFoundWas
        Hooks._rescanDelayMs = hooksDelayWas

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
            "a notification-owner recheck that cannot ask the bus clears stale conflict state immediately")
        root._check(NotifWatch._sandboxed && !NotifWatch._checked,
            "a sandboxed shell does not report the desktop notification owner as a conflict")
        const ownerToolsWas = SystemTools._tools
        const ownerReadyWas = SystemTools.ready
        SystemTools._tools = Object.assign({}, ownerToolsWas, { busctl: true })
        SystemTools.ready = true
        NotifWatch._sandboxed = false
        NotifWatch.conflict = "mako"
        let ownerAlerts = 0
        const countOwnerAlert = () => ownerAlerts++
        NotifWatch.conflictChanged.connect(countOwnerAlert)
        NotifWatch.recheck()
        const ownerKept = NotifWatch._checked && NotifWatch.conflict === "mako" && ownerAlerts === 0
        NotifWatch.conflictChanged.disconnect(countOwnerAlert)
        NotifWatch._sandboxed = true
        SystemTools._tools = ownerToolsWas
        SystemTools.ready = ownerReadyWas
        NotifWatch.recheck()
        root._check(ownerKept && !NotifWatch._checked && NotifWatch.conflict === "",
            "a tool rescan keeps the known notification owner until the bus answers, so its alert does not fire again")
    }

    function _checksAccentBalanceAndAnchors(): void {
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

        root._check(Network.connectivityIssueFor(true, Net.NetworkConnectivity.Portal) === "portal"
                && Network.connectivityIssueFor(true, Net.NetworkConnectivity.Limited) === "limited",
            "a captive portal and a dead uplink each surface as a connectivity issue")
        root._check(Network.connectivityIssueFor(true, Net.NetworkConnectivity.Full) === ""
                && Network.connectivityIssueFor(true, Net.NetworkConnectivity.Unknown) === ""
                && Network.connectivityIssueFor(false, Net.NetworkConnectivity.Portal) === "",
            "full, unchecked or unlinked connectivity raises no issue")
        let alertTiers = true
        for (const strength of [10, 40, 60, 90])
            alertTiers = alertTiers && Network.issueGlyph(true, strength).codePointAt(0)
                === Network.signalGlyph(strength).codePointAt(0) + 1
        root._check(alertTiers && Network.issueGlyph(false, 0) === "󰪎",
            "a Wi-Fi issue keeps its signal tier with the alert mark, and wired shows the crossed globe")

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
    }

    function _checksNotificationStatePruning(): void {
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
    }

    function _checksNotificationTitlesIconsAndLimit(): void {
        const titleTemplate = {
            actions: [], hints: ({}), appIcon: "", image: "", appName: "Probe", desktopEntry: "",
            summary: "Task finished", body: "", urgency: 1, expireTimeout: 0,
            resident: false, transient: false, hasInlineReply: false
        }
        const titled = notificationCardFactory.createObject(root, { width: 320, notification: titleTemplate })
        const bodyOnly = notificationCardFactory.createObject(root, { width: 320,
            notification: Object.assign({}, titleTemplate, { summary: "", body: "Task finished" }) })
        const blank = notificationCardFactory.createObject(root, { width: 320,
            notification: Object.assign({}, titleTemplate, { summary: " ", body: "" }) })
        root._check(bodyOnly._collapseBasis === titled._collapseBasis
                && bodyOnly.Accessible.name === "Probe: Task finished"
                && bodyOnly.Accessible.description === ""
                && blank.Accessible.name === "Probe: Notification",
            "a notification with no summary shows its body as the title, not under a blank bold line")
        bodyOnly._thread = ({ count: 3, lines: ["Started", "Halfway"] })
        root._check(bodyOnly.earlierCount === 2 && bodyOnly.Accessible.description === "2 earlier",
            "a threaded notification whose body is its title says only how many came earlier")
        for (const card of [titled, bodyOnly, blank]) card.destroy()

        const openWas = MenuState.open
        const filterWas = MenuState.recentFilter
        MenuState.open = true
        Notifications.clearHistory()
        Notifications._prependHistory({ id: 9301, appName: "silere-probe-absent", summary: "",
            body: "Task finished", appIcon: "/usr/share/pixmaps/silere-probe-absent.png", time: Date.now() })
        const host = notificationIconWindowFactory.createObject(root)
        const pageComponent = Qt.createComponent("modules/menu/RecentPage.qml")
        const page = pageComponent.status === Component.Ready ? pageComponent.createObject(host.contentItem, {
            y: 160, width: 332, viewportHeight: 380, active: true, powerOpen: false
        }) : null
        const navComponent = Qt.createComponent("modules/menu/RecentNav.qml")
        const nav = navComponent.status === Component.Ready
            ? navComponent.createObject(host.contentItem, { x: 200, width: 180, height: 160 }) : null
        host.input.wait(50)
        const list = page ? root._findTrayNode(page, item => typeof item.itemAtIndex === "function") : null
        if (list) list.forceLayout()
        const row = list ? list.itemAtIndex(0) : null
        const rowCard = row ? root._findTrayNode(row, item => item.Accessible.role === Accessible.Notification) : null
        root._check(rowCard !== null && rowCard.Accessible.name === "silere-probe-absent: Task finished"
                && rowCard.Accessible.description === "",
            "a history row with no summary reads its body as the title, as its popup did")
        const iconIn = item => root._findTrayNode(item, node => node.backer !== undefined
            && String(node.source).indexOf("silere-probe-absent.png") >= 0)
        const dpr = host.devicePixelRatio
        const cardIcon = iconIn(host.card)
        const rowIcon = iconIn(row)
        const railIcon = iconIn(nav)
        root._check(cardIcon && rowIcon && railIcon
                && cardIcon.backer.sourceSize.width === Math.round(24 * dpr)
                && rowIcon.backer.sourceSize.width === Math.round(16 * dpr)
                && railIcon.backer.sourceSize.width === Math.round(16 * dpr),
            "notification, history and app rail icons decode at their device size, as the tray's do")
        // the page goes invisible as its fade ends (PageShell); its rows must not relay themselves out for that
        const shownHeight = row ? row.height : -1
        if (page) page.opacity = 0
        host.input.wait(50)
        const hiddenHeight = row ? row.height : -2
        const pageHidden = page !== null && !page.visible
        if (page) page.opacity = 1
        host.input.wait(50)
        root._check(pageHidden && shownHeight > 0 && hiddenHeight === shownHeight && row.height === shownHeight,
            "a history row keeps its size while its page fades out of sight, so coming back relays nothing out")
        if (nav) nav.destroy()
        navComponent.destroy()
        if (page) page.destroy()
        pageComponent.destroy()
        host.destroy()
        Notifications.clearHistory()
        MenuState.open = openWas
        MenuState.setRecentFilter(filterWas)

        const limitWas = ShellSettings.notifHistoryLimit
        ShellSettings.notifHistoryLimit = 50
        for (let i = 0; i < 12; i++)
            Notifications._prependHistory({ id: 9310 + i, appName: "Chat", summary: "m" + i, time: 1000 + i })
        const popupsComponent = Qt.createComponent("modules/menu/settings/SettingsHistorySection.qml")
        const popups = popupsComponent.status === Component.Ready
            ? popupsComponent.createObject(root, { width: 360 }) : null
        const limitRow = popups ? root._findTrayNode(popups, item => item.key === "notifHistoryLimit") : null
        const limitTrack = limitRow ? root._findTrayNode(limitRow, item => typeof item._press === "function") : null
        let limitShownLow = ""
        if (limitTrack) {
            limitTrack._press(0)
            limitShownLow = limitRow.displayValue
            limitTrack._drag(limitTrack.width)
            limitTrack._release()
        }
        root._check(limitTrack !== null && limitTrack.width > 0 && limitShownLow === "5"
                && Notifications.historyCount === 12 && ShellSettings.notifHistoryLimit === 100,
            "a history limit dragged down and back keeps every row; only the value let go of applies")
        ShellSettings.notifHistoryLimit = 50
        const stepHost = keyboardFixtureFactory.createObject(root)
        const stepped = popupsComponent.createObject(stepHost.contentItem, { y: 220, width: 360 })
        const stepTrack = root._findTrayNode(stepped, item => typeof item._press === "function")
        let passedLow = false
        if (stepTrack) {
            for (let i = 0; i < 9; i++) stepTrack.nudge(-1, 1)
            passedLow = stepTrack.shownValue === 5
            for (let i = 0; i < 9; i++) stepTrack.nudge(1, 1)
            stepHost.requestActivate()
            stepHost.input.wait(40)
            stepTrack.forceActiveFocus(Qt.TabFocusReason)
            stepHost.input.keyPress(Qt.Key_Home)
            stepHost.input.wait(Scroll.sliderRestMs + 60)
            passedLow = passedLow && stepTrack.shownValue === 5
            stepHost.input.keyPress(Qt.Key_PageUp)
            stepHost.input.wait(Scroll.sliderRestMs + 60)
            stepHost.input.keyRelease(Qt.Key_PageUp)
            stepHost.input.wait(Scroll.sliderRestMs + 60)
            stepHost.input.keyRelease(Qt.Key_Home)
            passedLow = passedLow && ShellSettings.notifHistoryLimit === 55
            stepHost.input.keyPress(Qt.Key_Left)
            stepHost.button.forceActiveFocus(Qt.TabFocusReason)
            stepHost.input.wait(Scroll.sliderRestMs + 60)
            stepHost.input.keyRelease(Qt.Key_Left)
        }
        root._check(passedLow && Notifications.historyCount === 12 && ShellSettings.notifHistoryLimit === 50,
            "a history limit wheeled or keyed down and back keeps every row; where the steps rest applies")
        stepped.destroy()
        stepHost.destroy()
        if (popups) popups.destroy()
        popupsComponent.destroy()
        Notifications.clearHistory()
        ShellSettings.notifHistoryLimit = limitWas
    }

    function _checksDisplayIdentityAndBluetoothDiscovery(): void {
        const scanAdapterWas = Bluetooth._scanAdapter
        const dockDisplay = { name: "DP-1", model: "Fixture display", serialNumber: "12345" }
        const reconnectedDisplay = Object.assign({}, dockDisplay, { name: "DP-3" })
        const otherDisplay = { name: "DP-1", model: "Other display", serialNumber: "67890" }
        const displayIdentityKey = Monitors.identity(dockDisplay)
        const quietPanel = { name: "eDP-2", model: "0x1637", serialNumber: "" }
        root._check(Monitors.identity(quietPanel, {}) === ""
                && Monitors.identity(quietPanel, { "eDP-2": "0x00006000" })
                    === Monitors.identity({ name: "eDP-9", model: "0x1637", serialNumber: "0x00006000" }, {})
                && Monitors.identity(dockDisplay, { "DP-1": "elsewhere" })
                    === Monitors.identity(Object.assign({}, dockDisplay, { serialNumber: "elsewhere" }), {})
                && Monitors.identity(dockDisplay, {}) === displayIdentityKey,
            "a screen takes the compositor's serial before Quickshell's, under the same key either would give")
        root._check(Monitors.screenForPreference("DP-1", displayIdentityKey, [otherDisplay, reconnectedDisplay]) === reconnectedDisplay,
            "a remembered display follows its physical identity when docking changes the connector name")
        root._check(Monitors.screenForPreference("DP-1", displayIdentityKey, [otherDisplay]) === null,
            "another known display on the old port does not inherit the missing display's preference")
        root._check(Monitors.uniqueIdentity(dockDisplay, [dockDisplay, reconnectedDisplay]) === ""
                && Monitors.screenForPreference("DP-1", displayIdentityKey, [dockDisplay, reconnectedDisplay]) === dockDisplay,
            "duplicate monitor identities use the explicit connector instead of guessing between identical displays")
        root._check(Monitors.identity({ model: "Fixture", serialNumber: "0" }) === ""
                && Monitors.identity({ model: "Fixture", serialNumber: "" }) === ""
                && Monitors.screenForPreference("DP-1", "", [otherDisplay]) === otherDisplay
                && Monitors.screenForPreference("", displayIdentityKey, [dockDisplay]) === null,
            "missing or placeholder monitor serials preserve existing connector-based preferences")
        const otherIdentityKey = Monitors.identity(otherDisplay)
        root._check(Monitors.overlayIdentityFor("DP-1", displayIdentityKey, true, [otherDisplay, reconnectedDisplay]) === otherIdentityKey
                && Monitors.overlayIdentityFor("DP-1", displayIdentityKey, false, [otherDisplay, reconnectedDisplay]) === displayIdentityKey
                && Monitors.overlayIdentityFor("DP-2", displayIdentityKey, true, [otherDisplay]) === ""
                && Monitors.overlayIdentityFor("DP-1", "", false, [otherDisplay]) === otherIdentityKey
                && Monitors.overlayIdentityFor("", displayIdentityKey, false, [otherDisplay]) === "",
            "a changed popup monitor name re-reads its identity from that screen, while a screen change keeps the identity")
        const monitorLoadedWas = ShellSettings._loaded
        Monitors._rebindOverlayIdentity = false
        ShellSettings._loaded = false
        Monitors.rememberOverlay()
        const firstLoadRebinds = Monitors._rebindOverlayIdentity
        ShellSettings._loaded = true
        Monitors.rememberOverlay()
        root._check(!firstLoadRebinds && Monitors._rebindOverlayIdentity,
            "the first settings load keeps a saved popup monitor identity, and a later name change re-reads it")
        Monitors._rebindOverlayIdentity = false
        Monitors.selectOverlay(ShellSettings.overlayMonitor)
        root._check(Monitors._rebindOverlayIdentity,
            "choosing the popup monitor's own connector again re-reads its identity")
        Monitors._rebindOverlayIdentity = false
        ShellSettings._loaded = monitorLoadedWas
        root._check(Object.keys(Monitors.identityMap("malformed")).length === 0
                && Object.keys(Monitors.identityMap('{"DP-1":42}')).length === 0
                && Monitors.identityMap(JSON.stringify({ "DP-1": displayIdentityKey }))["DP-1"] === displayIdentityKey,
            "display identity metadata rejects malformed input and preserves valid mappings")
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
        // BlueZ answers a start a round trip later: the write lands only when the fixture says so
        const slowRadio = { enabled: true, _on: false, _asked: null,
            get discovering() { return this._on }, set discovering(v) { this._asked = v },
            land() { if (this._asked !== null) this._on = this._asked; this._asked = null } }
        Bluetooth._scanAdapter = null
        Bluetooth._scanRequested = true
        Bluetooth._syncDiscovery(slowRadio)
        Bluetooth._scanRequested = false
        Bluetooth._syncDiscovery(slowRadio)
        slowRadio.land()
        Bluetooth._syncDiscovery(slowRadio)
        slowRadio.land()
        root._check(!slowRadio.discovering && Bluetooth._scanAdapter === null && Bluetooth._scanStarting === null,
            "a Bluetooth picker closed before its discovery start lands still stops that discovery")
        const deferredRadio = () => {
            const listeners = []
            return { enabled: true, _on: false, _asked: null,
                discoveringChanged: {
                    connect(callback) { listeners.push(callback) },
                    disconnect(callback) {
                        const at = listeners.indexOf(callback)
                        if (at >= 0) listeners.splice(at, 1)
                    }
                },
                get discovering() { return this._on },
                set discovering(value) { this._asked = value },
                land() {
                    if (this._asked === null) return
                    const changed = this._on !== this._asked
                    this._on = this._asked
                    this._asked = null
                    if (changed) for (const listener of listeners.slice()) listener()
                },
                get listeners() { return listeners.length }
            }
        }
        const delayed = deferredRadio()
        const replacement = { enabled: true, discovering: false }
        Bluetooth._scanRequested = true
        Bluetooth._syncDiscovery(delayed)
        Bluetooth._syncDiscovery(replacement)
        delayed.land()
        delayed.land()
        root._check(!delayed.discovering && replacement.discovering && delayed.listeners === 0,
            "switching controllers before a Bluetooth scan starts releases the old controller's late scan")
        const returning = deferredRadio()
        Bluetooth._syncDiscovery(returning)
        Bluetooth._syncDiscovery(replacement)
        Bluetooth._syncDiscovery(returning)
        returning.land()
        root._check(returning.discovering && !replacement.discovering && returning.listeners === 0,
            "reselecting a controller before its scan starts preserves the newly requested scan")
        Bluetooth._scanRequested = false
        Bluetooth._syncDiscovery(returning)
        returning.land()
        const lost = deferredRadio()
        Bluetooth._scanRequested = true
        Bluetooth._syncDiscovery(lost)
        Bluetooth._syncDiscovery(null)
        lost.land()
        lost.land()
        root._check(!lost.discovering && lost.listeners === 0 && Bluetooth._scanStarting === null
                && Bluetooth._deferredScanStops.length === 0,
            "losing the selected controller before discovery starts still releases its late scan")
        const silent = deferredRadio()
        Bluetooth._syncDiscovery(silent)
        Bluetooth._syncDiscovery(replacement)
        Bluetooth._syncDiscovery(silent)
        Bluetooth._syncDiscovery(replacement)
        root._check(silent.listeners === 1 && Bluetooth._deferredScanStops.length === 1,
            "repeated switches while a controller stays silent retain only one cleanup watcher")
        Bluetooth._releaseMissingAdapter()
        root._check(silent.listeners === 0 && Bluetooth._deferredScanStops.length === 0,
            "a vanished Bluetooth controller releases a cleanup watcher even without a final discovery signal")
        Bluetooth._scanRequested = false
        Bluetooth._syncDiscovery(replacement)
        Bluetooth._scanAdapter = scanAdapterWas
        Bluetooth._scanRequested = scanRequestedWas
    }

    function _checksBluetoothBrightnessAndHookQueue(): void {
        root._check(Bluetooth._toggleStep(true, false, false) === "unblock"
                && Bluetooth._toggleStep(true, true, false) === ""
                && Bluetooth._toggleStep(false, false, false) === "on"
                && Bluetooth._toggleStep(false, false, true) === "off",
            "the bluetooth toggle lifts a soft rfkill block and leaves a hardware switch alone")

        root._check(!Bluetooth.hardBlockedFor("hci0\t0\nhci1\t1\n", "hci0")
                && Bluetooth.hardBlockedFor("hci0\t0\nhci1\t1\n", "hci1"),
            "a blocked Bluetooth controller does not disable another controller's toggle")
        root._check(!Bluetooth.hardBlockedFor("ideapad_bluetooth\t1\nhci0\t0\n", "hci0")
                && !Bluetooth.hardBlockedFor("hci0\t0\nideapad_bluetooth\t1\n", "hci0"),
            "a controller's own rfkill state takes priority over a platform switch in any order")
        root._check(Bluetooth.hardBlockedFor("ideapad_bluetooth\t1\nhci1\t0\n", "hci0")
                && !Bluetooth.hardBlockedFor("hci1\t1\n", "hci0"),
            "drivers without a controller switch fall back to platform switches, not other radios")
        root._check(!Bluetooth.hardBlockedFor("hci0\tinvalid\n\t1\nmalformed\n", "hci0")
                && !Bluetooth.hardBlockedFor("", "hci0"),
            "missing or malformed rfkill readings cannot invent a hardware block")

        const maxPairWaitMs = Bluetooth._attemptGuardMs
            * (Bluetooth._maxPairGuardExtensions + 1)
        root._check(Bluetooth._pairableTimeoutSec * 1000 > maxPairWaitMs,
            "Bluetooth pairability outlasts every allowed passkey guard extension")
        root._check(Bluetooth._extendAttemptGuard("pair", true, 0,
                    Bluetooth._maxPairGuardExtensions - 1)
                && !Bluetooth._extendAttemptGuard("pair", true, 0,
                    Bluetooth._maxPairGuardExtensions)
                && !Bluetooth._extendAttemptGuard("pair", false, 0, 0),
            "passkey pairing extends only while progressing and within its bounded limit")
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

        const privateCards = [
            { transient: false, tracked: true, resident: true, urgency: 2,
                appName: "Probe", appIcon: "", desktopEntry: "",
                summary: "Persistent critical card", body: "Private content" },
            { transient: false, tracked: true, hasInlineReply: true, urgency: 1,
                appName: "Probe", appIcon: "", desktopEntry: "",
                summary: "Reply card", body: "Private conversation" }
        ]
        Notifications.list = privateCards.map((n, i) => ({ notification: n, id: 63 + i, time: Date.now() }))
        Notifications.presentationMode = true
        root._check(Notifications.activeCount === 0 && privateCards.every(n => !n.tracked)
                && Notifications.historyCount === 2,
            "presentation mode untracks persistent critical and inline-reply cards while archiving their history")
        Notifications.presentationMode = false
        root._check(Notifications.activeCount === 0 && Notifications.historyCount === 2,
            "ending privacy keeps retired cards in history without replaying their content")
        Notifications.clearHistory()

        const displayIdentity = "a".repeat(64)
        const ddcRows = DisplayBrightness.parseDisplays("card1-DP-1\t7\t" + displayIdentity + "\t20\t80\n"
            + "card1-HDMI-A-1\t9\t" + displayIdentity + "\t101\t100\n"
            + "card1-DP-2\t7\tinvalid\t20\t100\n")
        root._check(ddcRows.length === 1 && ddcRows[0].percent === 25
                && ddcRows[0].key === "card1-DP-1:" + displayIdentity,
            "external display parsing normalizes non-100 ranges and rejects invalid identities and levels")
        const silentRow = DisplayBrightness.parseDisplays("card1-DP-3\t8\t" + displayIdentity + "\t-2\t100\n")
        root._check(silentRow.length === 1 && silentRow[0].unreadable && silentRow[0].percent === -1
                && !ddcRows[0].unreadable,
            "a display that answered on none of its buses parses as an unreadable row")

        const previewToolsWas = SystemTools._tools
        const previewDdcWas = ShellSettings.ddcBrightnessEnabled
        SystemTools._tools = Object.assign({}, previewToolsWas, { busctl: true, ddcutil: true, timeout: true })
        ShellSettings.ddcBrightnessEnabled = true
        const liveOffer = KeyboardBrightness.toolAvailable && DisplayBrightness.supported && DisplayBrightness.available
        SystemTools.preview = true
        root._check(liveOffer && !KeyboardBrightness.toolAvailable && !KeyboardBrightness.ready
                && !DisplayBrightness.supported && !DisplayBrightness.available,
            "the preview offers no keyboard light or external brightness control it would refuse to write")
        SystemTools.preview = false
        ShellSettings.ddcBrightnessEnabled = previewDdcWas
        SystemTools._tools = previewToolsWas

        const scanWas = { displays: DisplayBrightness.displays, values: DisplayBrightness.values,
            queued: DisplayBrightness._queued, error: DisplayBrightness._scanError,
            lastScan: DisplayBrightness._lastScan, pending: DisplayBrightness._refreshPending }
        const partialKey = "card1-DP-1:" + displayIdentity
        const partialRead = "card1-DP-1\t7\t" + displayIdentity + "\t20\t80\ncard1-DP-2\t8"
        DisplayBrightness.displays = []
        DisplayBrightness.values = ({})
        DisplayBrightness._queued = ({ [partialKey]: 65 })
        DisplayBrightness._acceptScanResult(DisplayBrightness._generation, 0, true, partialRead)
        root._check(DisplayBrightness.displays.length === 1
                && DisplayBrightness.levelFor(partialKey) === 65
                && DisplayBrightness._scanError.length > 0 && DisplayBrightness._lastScan === 0,
            "an incomplete brightness scan preserves completed displays and queued levels without claiming success")
        const partialDisplays = DisplayBrightness.displays
        DisplayBrightness._acceptScanResult(DisplayBrightness._generation, 1, false, "")
        root._check(DisplayBrightness.displays === partialDisplays && DisplayBrightness.levelFor(partialKey) === 65,
            "a failed brightness scan with no completed readings preserves the last usable controls")
        DisplayBrightness._acceptScanResult(DisplayBrightness._generation - 1, 0, true, partialRead)
        root._check(DisplayBrightness.displays === partialDisplays && DisplayBrightness._refreshPending,
            "an invalidated partial brightness scan cannot restore obsolete displays")
        DisplayBrightness._queued = ({})
        DisplayBrightness._acceptScanResult(DisplayBrightness._generation, 0, false, partialRead)
        root._check(DisplayBrightness.levelFor(partialKey) === 25
                && DisplayBrightness._scanError === "" && DisplayBrightness._lastScan > 0,
            "a complete brightness scan restores measured values and clears the incomplete-scan warning")
        DisplayBrightness.displays = scanWas.displays
        DisplayBrightness.values = scanWas.values
        DisplayBrightness._queued = scanWas.queued
        DisplayBrightness._scanError = scanWas.error
        DisplayBrightness._lastScan = scanWas.lastScan
        DisplayBrightness._refreshPending = scanWas.pending

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

        root._startHistoryRetentionProbe()
    }

    property var _retentionProbe: null

    function _startHistoryRetentionProbe(): void {
        const now = Date.now(), day = 86400000
        root._retentionProbe = { days: ShellSettings.notifHistoryDays, ready: ShellSettings.ready,
            seen: Notifications._seen, times: Notifications._times,
            updates: Notifications._updateTimes, list: Notifications.list, phase: 0 }
        root._check(ShellSettings._discreteKeys["notifHistoryDays"] === true,
            "retention choices save immediately rather than waiting for a slider debounce")
        root._check(!Notifications.historyExpiredAt(now - day, 0, now, true)
                && !Notifications.historyExpiredAt(now - day, 1, now, false),
            "history retention stays off by default and waits for settings to load")
        root._check(Notifications.historyExpiredAt(now - day, 1, now, true)
                && !Notifications.historyExpiredAt(now - day + 1, 1, now, true)
                && !Notifications.historyExpiredAt(now + day, 1, now, true)
                && !Notifications.historyExpiredAt(now, 1, NaN, true),
            "history expires at its exact age boundary and leaves recent and future rows intact")
        ShellSettings.notifHistoryDays = 0
        Notifications.clearHistory()
        Notifications.list = [{ id: 6201, time: now - day - 5, notification: { tracked: true } }]
        Notifications._seen = { "6201": true, "6202": true }
        Notifications._times = { "6201": now - day - 5, "6202": now - day - 10 }
        Notifications._updateTimes = { "6201": now, "6202": now }
        for (const entry of [{id: 6201, time: now - day - 5},
                {id: 6202, time: now - day - 10}, {id: 6203, time: now - 1000},
                {id: 6204, time: now - day + 5000}, {id: 6205, time: now + day}])
            Notifications._prependHistory(Object.assign({appName: "Retention", summary: "Probe " + entry.id}, entry))
        Notifications.historyModel.move(4, 1, 1)
        ShellSettings._loaded = false
        ShellSettings.notifHistoryDays = 1
        root._check(Notifications.historyCount === 5 && Notifications._expireHistory(now) === 0
                && Notifications._historyExpiryDelay(now) === 0 && !Notifications._historyExpiryTimer.running,
            "a partially loaded retention setting cannot prune restored history early")
        const revision = Notifications.historyRevision
        ShellSettings._loaded = true
        root._check(Notifications.historyCount === 3 && Notifications.historyRevision === revision + 1
                && Notifications.historyModel.get(0).id === 6205
                && Notifications.historyModel.get(1).id === 6203
                && Notifications.historyModel.get(2).id === 6204,
            "loaded retention removes expired rows from an unsorted history in one revision")
        root._check(Notifications.list.length === 1 && Notifications.list[0].notification.tracked
                && Notifications._seen["6201"] && Notifications._times["6201"] !== undefined
                && Notifications._updateTimes["6201"] !== undefined
                && Notifications._seen["6202"] === undefined && Notifications._times["6202"] === undefined
                && Notifications._updateTimes["6202"] === undefined,
            "history expiry prunes orphan state while preserving an active popup with the same id")
        root._check(JSON.parse(Notifications._serializeDisk()).history.length === 3,
            "expired notification text is removed from the persisted history payload")
        root._check(Notifications._historyExpiryTimer.running
                && Notifications._historyExpiryDelay(now) === 5000,
            "retention waits once for the earliest expiry instead of polling in the background")
        const beforeOldInsert = Notifications.historyRevision
        Notifications._prependHistory({ id: 6206, time: now - day - 1000, summary: "Old popup" })
        root._check(Notifications.historyRevision === beforeOldInsert && Notifications.historyCount === 3,
            "closing an old popup cannot reinsert history beyond the retention window")
        root._check(Notifications._expireHistory(now + 5000) === 1
                && Notifications.historyCount === 2 && Notifications._expireHistory(now + 5000) === 0,
            "history expiry is idempotent and removes an entry exactly at its deadline")
        ShellSettings.notifHistoryDays = 365
        root._check(Notifications._historyExpiryDelay(now) === 2147483647
                && Notifications._historyExpiryTimer.interval === 2147483647,
            "long retention periods stay inside Qt's signed timer interval range")
        ShellSettings.notifHistoryDays = 0
        root._check(!Notifications._historyExpiryTimer.running && Notifications._historyExpiryDelay(now) === 0,
            "disabling history expiry cancels its timer")
        Notifications.clearHistory()
        Notifications._prependHistory({ id: 6207, time: now - 10 * day, summary: "Keep indefinitely" })
        root._check(Notifications._expireHistory(now) === 0 && Notifications.historyCount === 1,
            "the default retention policy continues to keep older history")
        Notifications.clearHistory()
        for (let i = 0; i < 4; i++)
            Notifications._prependHistory({ id: 6210 + i, time: now - 2 * day - i, summary: "Expire together" })
        Notifications._prependHistory({ id: 6214, time: now, summary: "Keep" })
        ShellSettings._loaded = false
        ShellSettings.notifHistoryDays = 1
        let removals = 0
        const noteRemoval = () => { removals++ }
        Notifications.historyModel.countChanged.connect(noteRemoval)
        ShellSettings._loaded = true
        Notifications.historyModel.countChanged.disconnect(noteRemoval)
        root._check(removals === 1 && Notifications.historyCount === 1,
            "a normally ordered history expires its old rows in one model edit")
        Notifications.clearHistory()
        ShellSettings.notifHistoryDays = 7
        Notifications._prependHistory({ id: 6215, time: now - 2 * day, summary: "Two days old" })
        root._check(Notifications.historyCount === 1, "a week of retention keeps a two-day-old notification")
        ShellSettings.notifHistoryDays = 1
        root._check(Notifications.historyCount === 0,
            "shortening history retention immediately removes entries outside the new period")
        Notifications._restoreFromDisk(JSON.stringify({__version: 1, history: [
            {id: 6216, time: now - 2 * day, summary: "Expired on disk"},
            {id: 6217, time: now, summary: "Current on disk"}]}))
        Notifications._syncHistoryRetention()
        root._check(Notifications.historyCount === 1 && Notifications.historyModel.get(0).id === 6217
                && JSON.parse(Notifications._serializeDisk()).history.length === 1,
            "history restored after a restart is pruned and persisted against the active retention policy")
        // The earlier settings-file tests still have external-read callbacks queued.
        // Let those settle before testing a deadline across event-loop turns.
        _historyRetentionSettle.restart()
    }

    Timer {
        id: _historyRetentionSettle
        interval: 250
        onTriggered: {
            if (root._retentionProbe.phase === 0) {
                root._retentionProbe.phase = 1
                ShellSettings.notifHistoryDays = 1
                Notifications.clearHistory()
                const nearDeadline = Date.now() - 86400000 + 150
                Notifications._prependHistory({ id: 6218, time: nearDeadline, summary: "Expire without interaction" })
                Notifications._syncHistoryRetention()
                root._check(Notifications._historyExpiryTimer.running
                        && Notifications._historyExpiryTimer.interval > 0
                        && Notifications._historyExpiryTimer.interval <= 150,
                    "a newly archived row arms its own expiry deadline")
                restart()
                return
            }
            root._check(Notifications.historyCount === 0 && !Notifications._historyExpiryTimer.running,
                "history expires automatically while the shell has no new user input")
            const saved = root._retentionProbe
            ShellSettings.notifHistoryDays = saved.days
            ShellSettings._loaded = saved.ready
            Notifications.list = saved.list
            Notifications._seen = saved.seen
            Notifications._times = saved.times
            Notifications._updateTimes = saved.updates
            root._retentionProbe = null
            root._startSelectFadeProbe()
        }
    }

    property var _barLayoutProbe: null

    function _startBarLayoutProbe(): void {
        const settings = {}
        for (const key of ["reduceMotion", "barCompact", "barAutoCompact", "barCenterInGap",
                "osdEnabled", "osdBarIntegrated", "osdBatteryWarn", "osdChargedNotify", "osdTempWarn",
                "barShowClock", "barShowVolume", "showWindowTitle"])
            settings[key] = ShellSettings[key]
        const osd = {}
        for (const key of ["showing", "kind", "label", "muted", "icon", "nextIcon", "value"])
            osd[key] = OsdBarState[key]
        ShellSettings.reduceMotion = true
        ShellSettings.barCompact = false
        ShellSettings.barAutoCompact = true
        ShellSettings.barCenterInGap = true
        ShellSettings.osdBatteryWarn = false
        ShellSettings.osdChargedNotify = false
        ShellSettings.osdTempWarn = false
        // a conflict-warning expiry from an earlier test must not replace this fixture's volume state
        OsdBarState._clearEntries()
        ShellSettings.osdEnabled = true
        ShellSettings.osdBarIntegrated = true
        ShellSettings.barShowClock = true
        ShellSettings.barShowVolume = true
        ShellSettings.showWindowTitle = true
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
                    "a crowded integrated volume track contracts while retaining its reading"
                        + " (track " + (track ? track.width : "missing") + ", room " + room
                        + ", kind " + OsdBarState.kind + ", label width " + (osd ? osd._labelWidth : 0)
                        + ", font " + Settings.fontSize + ", bar " + bar.width
                        + ", edges " + bar.titleFreeLeft + "/" + bar.titleFreeRight + ")")
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
                    "a nearly squeezed-out volume track keeps its fill within its bounds"
                        + " (track " + (s.track ? s.track.width : "missing") + ")")
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
            case 6: {
                const pill = pillFactory.createObject(barFixtureHost, {
                    compact: false, glyph: "V", shrinkDelay: 2400, height: 24
                })
                pill.text = Qt.binding(() => pill.compact ? "Short" : "A much longer reading")
                const row = pill.children.find(item => typeof item.forceLayout === "function")
                row.forceLayout()
                pill._minW = pill.rowWidth
                s.pill = pill
                s.expandedPillWidth = pill.implicitWidth
                pill.compact = true
                row.forceLayout()
                // headless rows never polish, so their implicit widths stay stale without this
                s.layout = () => s.zones.forEach(zone => {
                    zone.children.forEach(slot => { if (slot.forceLayout) slot.forceLayout() })
                    zone.forceLayout()
                })
                s.zones[1].widgetComponents = { windowTitle: barFlexibleFactory, volume: barCenterFactory }
                s.zones[1].orderKeys = ["windowTitle"]
                ShellSettings.barCenterInGap = true
                bar.width = 400
                bar.fitWidth = 400
                break
            }
            case 7:
                root._check(s.pill._minW <= s.pill.rowWidth
                        && s.pill.implicitWidth < s.expandedPillWidth && s.pill.shrinkDelay === 2400,
                    "compact mode releases a pill's old width without waiting for its reading-jitter delay")
                s.layout()
                root._check(bar.effectiveCompact && bar.textFitScale < 1
                        && bar._widgetLayoutWidth <= bar.width + 0.5
                        && s.zones[1].x >= bar.titleFreeLeft - 0.5
                        && s.zones[1].x + s.zones[1].width <= bar.titleFreeRight + 0.5,
                    "a crowded compact bar fits its middle title between controls instead of growing or overlapping")
                bar.width = 600
                bar.fitWidth = 600
                break
            case 8:
                root._check(!bar.effectiveCompact && bar.textFitScale === 1,
                    "a widened bar restores expanded widgets and their preferred text widths")
                ShellSettings.barCenterInGap = false
                break
            case 9:
                s.layout()
                root._check(bar.textFitScale < 1 && bar._widgetLayoutWidth <= bar.width + 0.5
                        && s.zones[1].x >= bar.titleFreeLeft - 0.5
                        && s.zones[1].x + s.zones[1].width <= bar.titleFreeRight + 0.5,
                    "screen-centred text budgets clear the wider side zone")
                s.zones[0].widgetComponents = { workspaces: barLeftFactory, windowTitle: barFlexibleFactory }
                s.zones[0].orderKeys = ["workspaces", "windowTitle"]
                s.zones[1].orderKeys = ["volume"]
                bar.width = 700
                bar.fitWidth = 700
                break
            case 10:
                s.layout()
                root._check(bar.textFitScale < 1 && bar._widgetLayoutWidth <= bar.width + 0.5,
                    "moving a long title to a side preserves space for screen-centred controls")
                s.zones[0].orderKeys = ["workspaces"]
                s.zones[2].widgetComponents = { clock: barRightFactory, windowTitle: barFlexibleFactory }
                s.zones[2].orderKeys = ["clock", "windowTitle"]
                break
            case 11:
                s.layout()
                root._check(bar.textFitScale === 1 && bar._widgetLayoutWidth <= bar.width + 0.5,
                    "moving flexible text to a roomier zone restores its preferred width")
                bar.width = 1
                bar.fitWidth = 1
                break
            case 12:
                root._check(bar.textFitScale === 0 && s.zones[2].widthMetrics.flexible === 180,
                    "a fully squeezed-out title remains measured without oscillating between visible and hidden")
                bar.width = 900
                bar.fitWidth = 900
                break
            case 13:
                root._check(bar.textFitScale === 1 && s.zones[2].widthMetrics.flexible === 180,
                    "a title with a zero-width slot reappears when space returns")
                s.pill.destroy()
                bar.destroy()
                for (const key of Object.keys(s.settings)) ShellSettings[key] = s.settings[key]
                for (const key of Object.keys(s.osd)) OsdBarState[key] = s.osd[key]
                OsdBarState._clearEntries()
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
        ShellSettings.reduceMotion = false
        MenuState.close()
        MenuState.requestWarm(probeAnchor, null)
        MenuState.requestWarm(invalidProbeAnchor, null)
        MenuState.cancelWarm(probeAnchor)
        state.select = selectRowFactory.createObject(root, {
            model: Array.from({ length: 1000 }, (_, i) => ({ value: "v" + i, label: "Option " + i })),
            currentValue: "v999"
        })
        state.select._setOpen(true)
        _resourceSettle.interval = Motion.medium + 150
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
                    "an animated long dropdown keeps its selected option visible after expansion")
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
                const list = root._findTrayNode(select, item =>
                    typeof item.positionViewAtIndex === "function")
                let chosen = ""
                select.chosen.connect(value => { chosen = value })
                if (list) list.flick(0, 800)
                if (selected) selected.trigger()
                root._check(chosen === "v999" && !select._open,
                    "a recycled dropdown option chooses its current value and closes")
                root._check(list && !list.flicking && !list.interactive,
                    "closing a dropdown stops its inertia and releases wheel input during the fade")
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

        const layoutWas = [ShellSettings.barWidgetOrderLeft, ShellSettings.barWidgetOrderCenter,
            ShellSettings.barWidgetOrderRight]
        const where = key => ShellSettings.barWidgetLocate(key)
        const rightKeys = ShellSettings.barWidgetOrderRightKeys
        const lastKey = rightKeys[rightKeys.length - 1]
        settings._moveBy(lastKey, -1)
        const steppedUp = where(lastKey).index === rightKeys.length - 2
        settings._moveBy(lastKey, 1)
        settings._moveBy(lastKey, 1)
        const heldAtEnd = where(lastKey).zone === "right" && where(lastKey).index === rightKeys.length - 1
        const firstRight = ShellSettings.barWidgetOrderRightKeys[0]
        const centerCount = ShellSettings.barWidgetOrderCenterKeys.length
        settings._moveBy(firstRight, -1)
        const crossed = where(firstRight).zone === "center" && where(firstRight).index === centerCount
        settings._moveBy(firstRight, 1)
        root._check(steppedUp && heldAtEnd && crossed
                && where(firstRight).zone === "right" && where(firstRight).index === 0,
            "arrow keys on a widget's grip move it one place, across a zone edge, and stop at the bar's end")
        const grip = root._findTrayNode(settings, item =>
            item.Accessible.name === "Move " + ShellSettings.barWidgetMeta.clock.label)
        root._check(grip !== null && grip.Accessible.role === Accessible.Button && grip.activeFocusOnTab,
            "each widget's grip is a keyboard stop a screen reader names as moving that widget")
        ShellSettings.setBarWidgetLayout(ShellSettings.barWidgetOrderLeftKeys, ShellSettings.barWidgetOrderCenterKeys,
            ["clock"].concat(ShellSettings.barWidgetOrderRightKeys.filter(k => k !== "clock")))
        if (grip) grip.Accessible.pressAction()
        const pressedOn = where("clock").zone === "right" && where("clock").index === 1
        ShellSettings.setBarWidgetLayout(ShellSettings.barWidgetOrderLeftKeys, ShellSettings.barWidgetOrderCenterKeys,
            ["clock"].concat(ShellSettings.barWidgetOrderRightKeys.filter(k => k !== "clock")))
        root._check(pressedOn, "pressing a widget's grip, as a screen reader does, moves it one place along the bar")
        const toggleOf = key => root._findTrayNode(settings, item => item.Accessible.role === Accessible.CheckBox
            && item.Accessible.name === ShellSettings.barWidgetMeta[key].label)
        // clock is built last, so first on the right its drawn neighbour is not its built one. The fixture has
        // no window to hold focus, so this checks the switch an arrow lands on
        root._check(settings._toggleAfter("clock", 1) === toggleOf(ShellSettings.barWidgetOrderRightKeys[1])
                && settings._toggleAfter(ShellSettings.barWidgetOrderRightKeys[1], -1) === toggleOf("clock"),
            "arrow keys walk the widget switches in the order drawn, not the order the rows were built")
        const gripOf = key => root._findTrayNode(settings, item =>
            item.Accessible.name === "Move " + ShellSettings.barWidgetMeta[key].label)
        const secondRight = ShellSettings.barWidgetOrderRightKeys[1]
        root._check(settings._tabTarget(toggleOf("clock"), true) === gripOf(secondRight)
                && settings._tabTarget(gripOf(secondRight), false) === toggleOf("clock")
                && settings._tabTarget(gripOf("clock"), true) === toggleOf("clock")
                && settings._tabTarget(toggleOf("tray"), true) === appToggle,
            "Tab walks each row's grip, switch and tray apps in the order drawn, not the order the rows were built")
        // a list of its own in a real window: the shared fixture has none, and moving it into one upsets the tray checks
        const keyHost = keyboardFixtureFactory.createObject(root)
        const keyList = Qt.createComponent("modules/menu/settings/DraggableWidgetList.qml")
            .createObject(keyHost.contentItem, { width: 320 })
        keyHost.requestActivate()
        keyHost.input.wait(80)
        const inList = (label, key) => root._findTrayNode(keyList, item => item.Accessible.name === label
            && item.visible && (key === undefined || item.Accessible.role === key))
        const label = key => ShellSettings.barWidgetMeta[key].label
        inList(label("clock"), Accessible.CheckBox).forceActiveFocus(Qt.TabFocusReason)
        keyHost.input.keyClick(Qt.Key_Tab)
        const tabbed = inList("Move " + label(secondRight)).activeFocus
        keyHost.input.keyClick(Qt.Key_Backtab, Qt.ShiftModifier)
        const backtabbed = inList(label("clock"), Accessible.CheckBox).activeFocus
        inList("Move " + label(ShellSettings.barWidgetOrderLeftKeys[0])).forceActiveFocus(Qt.TabFocusReason)
        keyHost.input.keyClick(Qt.Key_Backtab, Qt.ShiftModifier)
        const leftList = keyHost.activeFocusItem !== null && keyList._rowOf(keyHost.activeFocusItem) === null
        // clock is built last: drawn first, the row Shift+Tab reaches from Reset below the list is not the last one built
        const drawnWas = [ShellSettings.barWidgetOrderLeftKeys, ShellSettings.barWidgetOrderCenterKeys, ShellSettings.barWidgetOrderRightKeys]
        ShellSettings.setBarWidgetLayout(["clock"].concat(drawnWas[0].filter(k => k !== "clock")),
            drawnWas[1].filter(k => k !== "clock"), drawnWas[2].filter(k => k !== "clock"))
        ShellSettings.setTrayItemHidden("probe-a", true)
        keyList._setTrayOpen(true)
        keyHost.input.wait(80)
        const resetButton = inList("Reset", Accessible.Button)
        if (resetButton) resetButton.forceActiveFocus(Qt.TabFocusReason)
        keyHost.input.keyClick(Qt.Key_Backtab, Qt.ShiftModifier)
        const drawnNow = ShellSettings.barWidgetOrderLeftKeys.concat(ShellSettings.barWidgetOrderCenterKeys, ShellSettings.barWidgetOrderRightKeys)
        const backRow = keyHost.activeFocusItem ? keyList._rowOf(keyHost.activeFocusItem) : null
        const backFromReset = resetButton !== null && backRow !== null && backRow.key === drawnNow[drawnNow.length - 1]
        keyHost.input.keyClick(Qt.Key_Tab)
        const fromReset = backFromReset && resetButton.activeFocus
        const showAllApps = inList("Show all apps")
        if (showAllApps) showAllApps.forceActiveFocus(Qt.TabFocusReason)
        keyHost.input.keyClick(Qt.Key_Tab)
        const drawn = ShellSettings.barWidgetOrderLeftKeys.concat(ShellSettings.barWidgetOrderCenterKeys, ShellSettings.barWidgetOrderRightKeys)
        const afterTray = drawn[drawn.indexOf("tray") + 1]
        const pastTray = showAllApps !== null && keyHost.activeFocusItem !== null && (afterTray
            ? inList("Move " + label(afterTray)).activeFocus : keyList._rowOf(keyHost.activeFocusItem) === null)
        ShellSettings.setTrayItemHidden("probe-a", false)
        ShellSettings.setBarWidgetLayout(drawnWas[0], drawnWas[1], drawnWas[2])
        keyHost.destroy()
        root._check(fromReset,
            "Reset sits below the list: Shift+Tab from it reaches the last widget drawn, and Tab from there returns to it")
        root._check(pastTray,
            "Tab from the tray's Show all apps row moves on to the next widget instead of back to the tray's grip")
        root._check(tabbed && backtabbed && leftList,
            "real Tab and Shift+Tab keys follow the drawn order and leave the list past its first row")
        const chevron = root._findTrayNode(settings, item => item.visible
            && /^(Show|Hide) tray apps$/.test(String(item.Accessible.name)))
        const trayWasOpen = settings._trayOpen
        if (chevron) chevron.Accessible.pressAction()
        root._check(chevron !== null && chevron.Accessible.role === Accessible.Button && chevron.activeFocusOnTab
                && settings._trayOpen !== trayWasOpen,
            "the tray's app list opens and closes from the keyboard")
        settings._setTrayOpen(trayWasOpen)
        ShellSettings.setBarWidgetLayout(layoutWas[0], layoutWas[1], layoutWas[2])
    }

    function _checkTrayCell(s, widget, tile, icon): void {
        const label = tile ? root._findTrayNode(tile, item => item.reserveText !== undefined && item.expanded !== undefined) : null
        if (!widget || !tile || !icon || !label) {
            root._check(false, "the tray cell checks found the widget, its tile, icon and name")
            return
        }
        const pad = Metrics.pillPadFor(widget.compact)
        root._check(tile.width === widget.cellWidth && widget.cellWidth === widget.iconSize + 2 * pad
                && icon.width === Metrics.devicePx(widget.iconSize, icon.dpr)
                && Math.abs(icon.x + icon.width / 2 - widget.cellWidth / 2) < 0.01,
            "a tray icon sits centred in a cell with a glyph pill's padding, on whole device pixels")

        const spacingWas = ShellSettings.barSpacing
        ShellSettings.barSpacing = 4
        const tightGap = widget.itemGap
        ShellSettings.barSpacing = 12
        const wideGap = widget.itemGap
        const wideWidgetGap = Metrics.widgetGapFor(widget.compact)
        ShellSettings.barSpacing = spacingWas
        root._check(tightGap === 0 && wideGap > 0 && wideGap < wideWidgetGap,
            "tray icons abut at the tightest widget gap and stay closer than the widgets as it widens")

        const statusWas = s.first.status
        s.first.status = St.Status.Passive
        root._check(tile.opacity === 1 && icon.opacity === 1,
            "a passive tray app is idle, not off, and keeps its full colour")
        s.first.status = statusWas

        const hoverWas = ShellSettings.valuesOnHover
        const restRight = tile.width - (icon.x + icon.width)
        ShellSettings.valuesOnHover = false
        tile._dwelled = true
        root._check(!label.expanded && tile.width === widget.cellWidth,
            "with hover reveals off the tray names no app, like the clock's date and the workspace names")
        ShellSettings.valuesOnHover = true
        tile.syncMenuAnchor()
        const iconCentre = tile.mapToItem(null, icon.x + icon.width / 2, 0).x
        root._check(widget.labelLeads && label.expanded && label.width > 0 && label.x + label.width <= icon.x
                && Math.abs(tile.width - (icon.x + icon.width) - restRight) < 0.01
                && Math.abs(tile.menuAnchorX - iconCentre) < 0.5,
            "in the right zone a tray name grows to the icon's left, so the icon and its menu stay under the pointer")
        ShellSettings.setBarWidgetLayout("tray," + s.layout[0], s.layout[1],
            s.layout[2].split(",").filter(k => k !== "tray").join(","))
        root._check(!widget.labelLeads && label.x >= icon.x + icon.width && icon.x === pad,
            "in the left zone the name grows to the right, away from the edge that zone is pinned to")
        ShellSettings.setBarWidgetLayout(s.layout[0], s.layout[1], s.layout[2])
        tile._dwelled = false
        // resting on the next icon names it and drops the one left behind, as across the bar
        const next = root._findTrayNode(s.zone, item => typeof item.syncMenuAnchor === "function"
            && item.modelData === s.second)
        let handed = false
        if (next) {
            tile._dwelled = true
            widget._heldTile = tile
            next._dwelled = true
            widget._heldTile = next
            handed = !tile._dwelled && next._dwelled
            next._dwelled = false
            widget._heldTile = null
        }
        root._check(handed, "resting on another tray icon closes the name left behind, so only one shows at a time")
        // as in a bar zone: a name whose fold would slide the icon now rested on stays out until the hold ends
        const after = widget.labelLeads ? next : null
        let trayKept = false, trayFreed = false
        if (next && after) {
            s.zone.pointerInside = true
            s.zone.claimHold("tray")
            next._dwelled = true
            widget._heldTile = next
            tile._dwelled = true
            widget._heldTile = tile
            trayKept = widget.holdOpen && next._dwelled && tile._dwelled
            s.zone.pointerInside = false
            trayFreed = !next._dwelled && !tile._dwelled && widget._heldTile === null
        }
        root._check(trayKept && trayFreed,
            "a tray name whose fold would slide the icon rested on stays out until the pointer leaves the zone")
        ShellSettings.valuesOnHover = hoverWas
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
        state.zone = zoneComponent.createObject(barFixtureHost, {
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
                root._checkTrayCell(s, widget, tile, icon)
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
                if (widget && tile) {
                    widget.barActive = false
                    widget._activateItem(s.first, tile)
                    widget._openMenu(s.first, tile)
                }
                root._check(s.first.activations === 1 && !TrayMenuState.open,
                    "a sleeping tray rejects both app activation and menu opening")
                widget.barActive = true
                s.zone.visible = false
                tile.Accessible.pressAction()
                widget._activateItem(s.first, tile)
                widget._openMenu(s.first, tile)
                root._check(s.first.activations === 1 && !TrayMenuState.open
                        && !tile.Accessible.focusable,
                    "hiding the tray's parent rejects retained app and menu actions")
                TrayMenuState.close()
                s.first.activations = 1
                s.zone.visible = true
                root._check(tile.Accessible.focusable,
                    "revealing the tray's parent restores its app controls")
                s.first.icon = "file://" + trayIconFixture.path
                break
            case 11: {
                root._check(tile && icon && icon.status === Image.Ready
                        && !tile.fallbackVisible && !tile._providedIconFailed,
                    "a tray app gaining a valid icon replaces its fallback")
                s.first.icon = "file://" + trayIconFixture.path + "?frame=2"
                root._check(icon.status === Image.Loading && icon.opacity === 1 && !tile.fallbackVisible,
                    "a tray icon stays up while the app's next icon loads")
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

    function _checkHistoryKeyboard(): void {
        const motionWas = ShellSettings.reduceMotion
        MenuState.setRecentFilter("")
        MenuState.selectTab(MenuState.recentTab)
        MenuState.openAt(17, null, probeAnchor)
        Notifications.clearHistory()
        Notifications._prependHistory({ id: 9201, appName: "Mail", summary: "First message", time: Date.now() - 1000 })
        Notifications._prependHistory({ id: 9202, appName: "Chat", summary: "Second message", time: Date.now() })
        const host = keyboardFixtureFactory.createObject(root, { width: 380, height: 560 })
        const component = Qt.createComponent("modules/menu/RecentPage.qml")
        const page = component.status === Component.Ready ? component.createObject(host.contentItem, {
            width: 332, viewportHeight: 520, active: true, powerOpen: false
        }) : null
        root._check(page !== null, "history builds for keyboard navigation")
        if (page) {
            page.settleVisual(true)
            const silence = root._findTrayNode(page, item => item.endable !== undefined && typeof item.end === "function")
            const silenceWas = { dnd: ShellSettings.dnd, until: ShellSettings.dndUntil, schedule: ShellSettings.dndSchedule,
                from: ShellSettings.dndFrom, to: ShellSettings.dndTo, presenting: Notifications.presentationMode }
            ShellSettings.dndSchedule = false
            Notifications.presentationMode = false
            const quietAtFirst = silence && !silence.expanded
            Notifications.setDnd(true, 0)
            const dndBand = silence && silence.expanded && silence._shown === "Do Not Disturb" && silence.endable
            if (silence) silence.end()
            const dndEnded = !ShellSettings.dnd && silence && !silence.expanded
            Notifications.presentationMode = true
            const presenting = silence && silence.expanded && silence._shown === "Presentation Mode" && silence.endable
            if (silence) silence.end()
            const presentingEnded = !Notifications.presentationMode && silence && !silence.expanded
                && silence._shown === "Presentation Mode"
            ShellSettings.dndFrom = DateTime.hour24
            ShellSettings.dndTo = (DateTime.hour24 + 1) % 24
            ShellSettings.dndSchedule = true
            const scheduled = silence && silence.expanded && silence._shown === "Quiet hours" && !silence.endable
            ShellSettings.dndSchedule = silenceWas.schedule
            ShellSettings.dndFrom = silenceWas.from
            ShellSettings.dndTo = silenceWas.to
            Notifications.setDnd(silenceWas.dnd, silenceWas.until)
            Notifications.presentationMode = silenceWas.presenting
            root._check(quietAtFirst && dndBand && dndEnded && presenting && presentingEnded && scheduled,
                "history says while popups are held, ends Do Not Disturb or Presentation Mode from there, and only names quiet hours")
            host.requestActivate()
            host.input.wait(40)
            const field = root._findTrayNode(page, item => item.Accessible.name === "Search notifications")
            const list = root._findTrayNode(page, item => typeof item.itemAtIndex === "function")
            list.forceLayout()
            const cardAt = index => root._findTrayNode(list.itemAtIndex(index), item => item.Accessible.role === Accessible.Notification)
            field.forceActiveFocus(Qt.TabFocusReason)
            host.input.keyClick(Qt.Key_Down)
            host.input.wait(10)
            root._check(cardAt(0).activeFocus, "Down from history search focuses the first message")
            host.input.keyClick(Qt.Key_Down)
            host.input.wait(10)
            const second = cardAt(1).activeFocus
            host.input.keyClick(Qt.Key_Up)
            host.input.wait(10)
            const first = cardAt(0).activeFocus
            host.input.keyClick(Qt.Key_Up)
            root._check(second && first && field.activeFocus,
                "history arrows move between messages and Up from the first returns to search")
            host.input.keyClick(Qt.Key_Down)
            host.input.wait(10)
            host.input.keyClick(Qt.Key_Down)
            host.input.wait(10)
            host.input.keyClick(Qt.Key_Delete)
            host.input.wait(20)
            root._check(Notifications.historyCount === 1 && cardAt(0).activeFocus,
                "removing the last focused history row hands focus to the preceding message")
            Notifications._prependHistory({ id: 9201, appName: "Mail", summary: "First message", time: Date.now() })
            page.searchText = "Second"
            field.forceActiveFocus(Qt.TabFocusReason)
            field.cursorPosition = 0
            host.input.keyClick(Qt.Key_Delete)
            root._check(page.searchText === "econd" && Notifications.historyCount === 2,
                "Delete edits history search without removing a notification")
            page.searchText = "Second"
            host.input.keyClick(Qt.Key_Return)
            host.input.wait(10)
            host.input.keyClick(Qt.Key_Delete)
            host.input.wait(20)
            root._check(Notifications.historyCount === 1 && page.rowCount === 0 && field.activeFocus,
                "Delete removes the focused match and returns to search when other history remains")
            const clear = root._findTrayNode(page, item => item.label === "Clear search")
            clear.Accessible.pressAction()
            host.input.wait(10)
            root._check(page.rowCount === 1 && field.activeFocus && page.searchText === "",
                "the empty-results action clears search and keeps the field ready for typing")
            host.input.keyClick(Qt.Key_Down)
            host.input.wait(10)
            const remaining = list.itemAtIndex(0)
            page.active = false
            remaining.removeSelf()
            root._check(Notifications.historyCount === 1,
                "an inactive history row refuses a retained remove action")
            page.active = true
            page.settleVisual(true)
            remaining.focusCard()
            host.input.keyClick(Qt.Key_Tab)
            host.input.wait(10)
            const remove = root._findTrayNode(remaining, item => item.Accessible.name === "Remove notification")
            root._check(remove.activeFocus && remove.visible && remove.opacity === 1,
                "Tab reveals the focused history row's remove button without pointer hover")
            remove.Accessible.pressAction()
            host.input.wait(20)
            root._check(Notifications.historyCount === 0,
                "the focused history remove button deletes the final entry")
            Notifications._prependHistory({ id: 9203, appName: "Mail", summary: "Still here", time: Date.now() })
            MenuState.setRecentFilter("Missing app")
            const showAll = root._findTrayNode(page, item => item.label === "Show all notifications")
            showAll.Accessible.pressAction()
            root._check(MenuState.recentFilter === "" && page.rowCount === 1 && Notifications.historyCount === 1,
                "an empty app filter offers a route back to all notifications without deleting history")
            Notifications._prependHistory({ id: 9204, appName: "Chat", summary: "Animated removal", time: Date.now() })
            ShellSettings.reduceMotion = false
            host.input.wait(220)
            page._focusRow(0)
            host.input.keyClick(Qt.Key_Delete)
            host.input.wait(20)
            root._check(Notifications.historyCount === 1 && cardAt(0).activeFocus,
                "focus moves to the next message while the removed card is still animating out")
            page.destroy()
        }
        host.close()
        host.destroy()
        component.destroy()
        Notifications.clearHistory()
        MenuState.close()
        MenuState.setRecentFilter("")
        ShellSettings.reduceMotion = motionWas
    }

    // newer cards push one past the visible limit: it folds and fades where it stands, and its slot lets go when the fold ends
    function _checkNotificationFold(): void {
        const motionWas = ShellSettings.reduceMotion
        const fixture = notificationKeyboardFactory.createObject(root, { timeout: 60000 })
        const card = fixture.card
        fixture.input.wait(80)
        const rect = card.children.find(c => c._behaviorEnabled !== undefined)
        let finished = 0
        card.foldFinished.connect(() => finished++)
        ShellSettings.reduceMotion = true
        const stillUnderReduced = !card.foldAway() && !card._folding
        ShellSettings.reduceMotion = false
        const started = Date.now()
        const folding = card.foldAway() && card._folding && card.clip
        fixture.input.wait(60)
        const inTime = Date.now() - started < 170
        const midway = !inTime || (card.collapseRatio > 0 && card.collapseRatio < 1 && rect.opacity < 1)
        card.unfold()
        const back = !card._folding
        fixture.input.wait(Motion.ms(200) + 120)
        const unfolded = card.collapseRatio === 1 && rect.opacity === 1 && finished === 0 && !card._leaving
        card.foldAway()
        fixture.input.wait(Motion.ms(200) + 120)
        const done = finished === 1 && card.collapseRatio === 0
        root._check(stillUnderReduced && folding && midway && back && unfolded && done,
            "a card pushed past the visible limit folds away and reports it, and unfolds if it comes back first")
        card.unfold()
        fixture.input.wait(Motion.ms(200) + 120)
        card.foldAway()
        card.dismiss(false)
        root._check(card._leaving && !card._folding && fixture.input !== null,
            "dismissing a folding card plays its exit instead of the fold")
        fixture.input.wait(Motion.ms(210) + 120)
        root._check(fixture.dismissed === 1 && finished === 1,
            "and it leaves once, without a second fold report")
        fixture.close()
        fixture.destroy()
        ShellSettings.reduceMotion = motionWas
    }

    // a row arriving at the top of its run takes the run's header from the row below, and removing a row can take a header
    // from the one under it; both flip at once. The row growing in or folding away carries it, so text below never steps back
    function _checkHistoryRowCarry(): void {
        const motionWas = ShellSettings.reduceMotion
        ShellSettings.reduceMotion = false
        MenuState.setRecentFilter("")
        MenuState.selectTab(MenuState.recentTab)
        MenuState.openAt(17, null, probeAnchor)
        Notifications.clearHistory()
        const now = Date.now()
        Notifications._prependHistory({ id: 9301, appName: "Mail", summary: "Older mail", time: now - 4000 })
        Notifications._prependHistory({ id: 9302, appName: "Chat", summary: "Chat between", time: now - 3000 })
        Notifications._prependHistory({ id: 9303, appName: "Mail", summary: "Newer mail", time: now - 2000 })
        const host = keyboardFixtureFactory.createObject(root, { width: 380, height: 640 })
        const component = Qt.createComponent("modules/menu/RecentPage.qml")
        const page = component.status === Component.Ready ? component.createObject(host.contentItem, {
            width: 332, viewportHeight: 600, active: true, powerOpen: false
        }) : null
        root._check(page !== null, "history builds for the row carry checks")
        if (page) {
            page.settleVisual(true)
            host.input.wait(80)
            const list = root._findTrayNode(page, item => typeof item.itemAtIndex === "function")
            const textY = summary => {
                const t = root._findTrayNode(list.contentItem, item => item.text === summary && item.visible)
                return t ? t.mapToItem(list, 0, 0).y : NaN
            }
            list.forceLayout()
            const newerBefore = textY("Newer mail"), olderBefore = textY("Older mail")
            Notifications._prependHistory({ id: 9304, appName: "Mail", summary: "Arrival", time: now - 1000 })
            list.forceLayout()
            const newerAfter = textY("Newer mail"), olderAfter = textY("Older mail")
            root._check(isFinite(newerBefore) && newerAfter >= newerBefore - 1.5 && olderAfter >= olderBefore - 1.5,
                "an arrival that takes its run's header does not step the rows below up before they slide down")
            host.input.wait(Motion.normal + 120)
            list.forceLayout()
            const chatRow = root._findTrayNode(list.contentItem, item => typeof item.removeSelf === "function"
                && item.modelData && item.modelData.summary === "Chat between")
            const olderSettled = textY("Older mail")
            if (chatRow) chatRow.removeSelf()
            list.forceLayout()
            const olderOnRemove = textY("Older mail")
            root._check(chatRow !== null && isFinite(olderSettled) && Math.abs(olderOnRemove - olderSettled) <= 1.5,
                "removing a row whose neighbour joins the run above leaves that neighbour's text in place as the row folds")
            host.input.wait(Motion.normal + 120)
            list.forceLayout()
            root._check(textY("Older mail") < olderSettled - 20,
                "the neighbour then rises into the removed row's place")
            page.destroy()
        }
        host.close()
        host.destroy()
        component.destroy()
        Notifications.clearHistory()
        MenuState.close()
        MenuState.setRecentFilter("")
        ShellSettings.reduceMotion = motionWas
    }

    function _startHistoryPageProbe(): void {
        root._historyReduceWas = ShellSettings.reduceMotion
        ShellSettings.reduceMotion = true
        root._checkHistoryKeyboard()
        root._checkHistoryRowCarry()
        root._checkNotificationFold()
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
            root._startAccentResizeProbe()
        }
    }

    property var _accentResizeState: null

    function _startAccentResizeProbe(): void {
        const saved = [ShellSettings.neutralTheme, ShellSettings.neutralAccentAuto, ShellSettings.reduceMotion]
        ShellSettings.neutralTheme = true
        ShellSettings.neutralAccentAuto = false
        ShellSettings.reduceMotion = true
        const component = Qt.createComponent("modules/menu/settings/SettingsThemeSection.qml")
        const section = component.status === Component.Ready
            ? component.createObject(root, { width: 520 }) : null
        const viewport = root._findTrayNode(section, item => typeof item.revealIndex === "function")
        const swatches = root._findTrayNode(section, item => typeof item.itemRight === "function"
            && item.accessiblePrefix === "Accent")
        const picker = root._findTrayNode(section, item => item._customPinned !== undefined)
        root._check(viewport !== null && swatches !== null && picker !== null,
            "theme controls expose the accent viewport for resize checks")
        if (!viewport || !swatches || !picker) {
            if (section) section.destroy()
            component.destroy()
            ShellSettings.neutralTheme = saved[0]
            ShellSettings.neutralAccentAuto = saved[1]
            ShellSettings.reduceMotion = saved[2]
            root._startDirectAnchorProbe()
            return
        }
        picker._customPinned = true
        root._accentResizeState = { saved: saved, component: component, section: section,
            viewport: viewport, swatches: swatches, step: 0 }
        _accentResizeTick.restart()
    }

    Timer {
        id: _accentResizeTick
        interval: 40
        onTriggered: {
            const s = root._accentResizeState
            if (s.step === 0) {
                root._check(!s.viewport.interactive && s.viewport.contentX === 0,
                    "a wide accent picker shows all its swatches without a scroll offset")
                s.section.width = 240
            } else if (s.step === 1) {
                const left = s.swatches.itemLeft(s.swatches.activeIndex) - s.swatches.edgePadding
                const right = s.swatches.itemRight(s.swatches.activeIndex) + s.swatches.edgePadding
                root._check(s.viewport.interactive && s.viewport.contentX > 0
                        && left >= s.viewport.contentX - 0.5
                        && right <= s.viewport.contentX + s.viewport.width + 0.5,
                    "shrinking a theme pane reveals the selected accent even when its index did not change")
                s.viewport.contentX = 0
                s.viewport.movementEnded()
            } else if (s.step === 2) {
                root._check(s.viewport.contentX === 0,
                    "scrolling the accent picker without a pending resize does not snap back to its selection")
                s.viewport.contentX = 24
                s.section.width = 520
            } else {
                root._check(!s.viewport.interactive && s.viewport.contentX === 0,
                    "expanding the theme pane clears an obsolete horizontal scroll offset")
                s.section.destroy()
                s.component.destroy()
                ShellSettings.neutralTheme = s.saved[0]
                ShellSettings.neutralAccentAuto = s.saved[1]
                ShellSettings.reduceMotion = s.saved[2]
                root._accentResizeState = null
                root._startLockEditorProbe()
                return
            }
            s.step++
            restart()
        }
    }

    property var _lockEditorProbe: null

    function _startLockEditorProbe(): void {
        const saved = { provider: ShellSettings.lockProvider, command: ShellSettings.lockCommandCustom,
            tab: MenuState.activeTab, open: MenuState.open, section: MenuState.settingsSection,
            scale: ShellSettings.uiScale, contrast: ShellSettings.highContrast }
        ShellSettings.lockProvider = "custom"
        ShellSettings.lockCommandCustom = "swaylock -f"
        MenuState.selectTab(MenuState.settingsTab)
        MenuState.setSettingsSection("interface")
        MenuState.open = true
        const window = lockEditorWindowFactory.createObject(root)
        root._lockEditorProbe = { window: window, saved: saved }
        _lockEditorSettle.restart()
    }

    Timer {
        id: _lockEditorSettle
        interval: 150
        onTriggered: {
            const s = root._lockEditorProbe
            const f = s.window
            const editor = f.editor
            root._check(editor !== null, "the custom-lock editor builds in a real offscreen window")
            if (editor) {
                const field = root._findTrayNode(editor, item => item.maximumLength !== undefined)
                const save = root._findTrayNode(editor, item => item.label === "Save")
                const revert = root._findTrayNode(editor, item => item.label === "Revert")
                root._check(field && save && revert && field.text === "swaylock -f"
                        && field.Accessible.name === "Lock command" && !editor.dirty && !save.enabled,
                    "the lock editor labels its saved command and starts without pending edits")
                f.requestActivate()
                field.forceActiveFocus()
                field.cursorPosition = field.text.length
                f.input.keyClick(Qt.Key_X)
                root._check(editor.draft === "swaylock -fx" && editor.dirty
                        && ShellSettings.lockCommandCustom === "swaylock -f",
                    "real typing updates the lock draft without changing the saved command")
                f.input.mouseClick(save)
                root._check(ShellSettings.lockCommandCustom === "swaylock -fx"
                        && !editor.dirty && !save.enabled,
                    "clicking Save commits the custom lock command once")
                editor.draft = "swaylock 'unfinished"
                root._check(editor.validationMessage.length > 0 && !save.enabled,
                    "an incomplete quoted lock command displays an error and disables Save")
                editor.save()
                root._check(ShellSettings.lockCommandCustom === "swaylock -fx",
                    "invalid lock input cannot replace the saved command")
                f.input.mouseClick(revert)
                root._check(editor.draft === ShellSettings.lockCommandCustom
                        && editor.validationMessage.length === 0,
                    "Revert restores the previous command and clears its validation error")
                editor.draft = "a".repeat(257)
                root._check(editor.validationMessage.length > 0 && !save.enabled
                        && field.text.length === 257,
                    "an overlong command is visible as invalid rather than silently truncated")
                editor.draft = "gtklock"
                field.forceActiveFocus()
                f.input.keyClick(Qt.Key_Escape)
                root._check(!editor.dirty && field.text === ShellSettings.lockCommandCustom
                        && !field.activeFocus,
                    "Escape discards lock edits and releases the text field's focus")
                editor.draft = "swaylock --image \"/home/me/Lock screen.png\""
                field.forceActiveFocus()
                f.input.keyClick(Qt.Key_Return)
                root._check(!editor.dirty && Settings.customLockCommand.length === 3
                        && Settings.customLockCommand[2] === "/home/me/Lock screen.png",
                    "Enter saves a quoted command without executing it")
                editor.draft = "unsaved"
                MenuState.setSettingsSection("clock")
                root._check(!editor.dirty, "leaving Interface discards its pending command edit")
                MenuState.setSettingsSection("interface")
                editor.draft = "unsaved"
                MenuState.close()
                root._check(!editor.dirty, "closing settings discards its pending command edit")
                editor.draft = "unsaved"
                ShellSettings.lockCommandCustom = "gtklock"
                root._check(!editor.dirty && field.text === "gtklock",
                    "external command changes replace a stale draft and keep the field in sync")
                editor.draft = "unsaved"
                editor.visible = false
                editor.save()
                root._check(!editor.dirty && ShellSettings.lockCommandCustom === "gtklock",
                    "hidden command editors discard their draft and reject saves")
                editor.visible = true
                editor.draft = "unsaved"
                ShellSettings.lockProvider = "auto"
                editor.save()
                root._check(!editor.dirty && ShellSettings.lockCommandCustom === "gtklock",
                    "switching away from a custom provider cannot save an old draft")
                ShellSettings.lockProvider = "custom"
                editor.draft = ""
                editor.save()
                root._check(ShellSettings.lockCommandCustom === "" && Settings.lockCommand.length === 0,
                    "saving an empty custom command deliberately disables the lock action")
                ShellSettings.uiScale = 1.5
                ShellSettings.highContrast = true
                f.width = 232
                f.input.wait(100)
                let fits = true
                for (const item of [field, save, revert]) {
                    const p = item.mapToItem(editor, 0, 0)
                    if (p.x < 0 || p.x + item.width > editor.width + 0.5) fits = false
                }
                root._check(fits && field.height >= field.implicitHeight - 0.5,
                    "lock input and actions fit a narrow pane at the largest interface scale")
            }
            f.close()
            f.destroy()
            ShellSettings.lockProvider = s.saved.provider
            ShellSettings.lockCommandCustom = s.saved.command
            ShellSettings.uiScale = s.saved.scale
            ShellSettings.highContrast = s.saved.contrast
            MenuState.selectTab(s.saved.tab)
            MenuState.setSettingsSection(s.saved.section)
            MenuState.open = s.saved.open
            root._lockEditorProbe = null
            root._startSettingsSearchProbe()
        }
    }

    property var _settingsSearchProbe: null

    function _startSettingsSearchProbe(): void {
        const saved = { tab: MenuState.activeTab, open: MenuState.open,
            section: MenuState.settingsSection, scale: ShellSettings.uiScale,
            reduce: ShellSettings.reduceMotion }
        MenuState.selectTab(MenuState.settingsTab)
        MenuState.open = true
        MenuState.setSettingsSection("theme")
        ShellSettings.reduceMotion = true
        root._settingsSearchProbe = { saved: saved,
            window: settingsSearchWindowFactory.createObject(root) }
        _settingsSearchSettle.restart()
    }

    Timer {
        id: _settingsSearchSettle
        interval: 150
        onTriggered: {
            const state = root._settingsSearchProbe
            const f = state.window
            const search = f.search
            root._check(search !== null, "settings search builds in a real offscreen window")
            if (search) {
                const input = root._findTrayNode(search, item => item.maximumLength !== undefined)
                const toggle = root._findTrayNode(search, item => item.accessibleName === "Search settings")
                const close = root._findTrayNode(search, item => item.accessibleName === "Close settings search")
                const clear = root._findTrayNode(search, item => item.accessibleName === "Clear settings query")
                root._check(input && input.Accessible.name === "Search settings"
                        && input.maximumLength === 256 && !search.searching,
                    "settings search exposes a labelled, bounded text field")
                root._check(toggle && toggle.visible && !search.expanded && !input.visible
                        && search.height === search.toggleHeight,
                    "settings search starts as a compact icon with its text field hidden")
                f.requestActivate()
                if (toggle) f.input.mouseMove(toggle)
                f.input.wait(550)
                const hint = root._findTrayNode(search, item => item.text === "Search settings · Ctrl+F")
                root._check(hint && hint.parent.visible && toggle.Accessible.description.indexOf("Ctrl+F") >= 0,
                    "the compact search icon reveals its purpose and shortcut on hover")
                f.input.mouseMove(f.contentItem, 10, 290)
                root._check(hint && !hint.parent.visible,
                    "leaving the search icon dismisses its hover hint")
                if (toggle) f.input.mouseClick(toggle)
                root._check(input.width > 100 && input.activeFocus,
                    "search input has usable geometry and focus on the first opening frame")
                f.input.keyClick(Qt.Key_F)
                f.input.wait(Motion.fast + 20)
                root._check(search.expanded && input.visible && input.activeFocus
                        && close && close.visible && !toggle.visible,
                    "clicking the search icon expands and focuses its field")
                root._check(search.query === "f", "typing immediately after opening search preserves the first character")
                search.focusSearch()
                f.input.keyClick(Qt.Key_F)
                f.input.keyClick(Qt.Key_O)
                f.input.keyClick(Qt.Key_N)
                f.input.keyClick(Qt.Key_T)
                f.input.wait(40)
                root._check(search.query === "font" && search.results.some(row => row.section === "interface"),
                    "real typing locates Interface through a font query")
                const result = root._findTrayNode(search, item => item.title === "Interface")
                root._check(result !== null, "a settings match creates a clickable section result")
                if (result) f.input.mouseClick(result)
                root._check(MenuState.settingsSection === "interface" && !search.searching
                        && !search.expanded && !input.activeFocus,
                    "clicking a settings result selects its section and releases text focus")
                search.query = "bar"
                root._check(search.results.length > 4,
                    "a broad settings query retains matches beyond the visible result cap")
                root._check(search.resultSummary.indexOf("Scroll for more") >= 0,
                    "a capped settings result list explicitly announces additional matches")
                search.choose("workspaces")
                root._check(search.searching && MenuState.settingsSection === "interface",
                    "a section outside the current results cannot be selected through search")
                f.input.wait(Motion.fast + 20)
                if (clear) f.input.mouseClick(clear)
                root._check(clear && search.expanded && search.query.length === 0
                        && input.activeFocus && close.visible && search.results.length === 0,
                    "clearing the query keeps search expanded and ready for another query")
                f.input.keyClick(Qt.Key_Escape)
                root._check(!search.searching && !search.expanded && !search.dismissInline(),
                    "Escape collapses settings search once before allowing the popup to close")
                search.query = "calendarWeekStart"
                search.focusSearch()
                root._check(search.resultSummary === "1 section · Enter to open",
                    "a unique settings match advertises its Enter action")
                f.input.keyClick(Qt.Key_Return)
                root._check(MenuState.settingsSection === "clock" && !search.expanded && !input.activeFocus,
                    "Enter opens a unique settings match and folds search away")
                search.query = "dismiss after"
                search.focusSearch()
                const focusedTitle = () => {
                    const it = input.Window.window ? input.Window.window.activeFocusItem : null
                    return it && it.title !== undefined ? it.title : ""
                }
                f.input.keyClick(Qt.Key_Down)
                f.input.wait(40)
                const downOne = focusedTitle() === search.results[0].label
                f.input.keyClick(Qt.Key_Down)
                f.input.wait(40)
                const downTwo = focusedTitle() === search.results[1].label
                f.input.keyClick(Qt.Key_Up)
                f.input.wait(40)
                f.input.keyClick(Qt.Key_Up)
                f.input.wait(40)
                root._check(search.results.length === 3 && downOne && downTwo && input.activeFocus && search.expanded,
                    "arrow keys walk from the settings search field through its results and back")
                search.query = "bar"
                root._check(search.resultSummary.indexOf("Enter opens Layout") >= 0,
                    "a broad settings query names the section Enter will open")
                f.input.keyClick(Qt.Key_Return)
                root._check(MenuState.settingsSection === "surface" && !search.expanded && !input.activeFocus,
                    "Enter opens the top match of a broad settings query")
                MenuState.setSettingsSection("interface")
                search.query = "qzx nonexistent"
                root._check(search.results.length === 0
                        && root._findTrayNode(search, item => item.text === "No matching settings. Try a feature name.") !== null,
                    "an unmatched settings query gives an explicit empty-state hint")
                f.input.wait(Motion.fast + 20)
                if (close) f.input.mouseClick(close)
                root._check(!search.expanded && search.query.length === 0 && toggle.visible,
                    "the search close button discards its query and restores the compact icon")
                search.query = "font"
                search.shown = false
                search.choose("interface")
                search.submit()
                root._check(!search.searching && search.results.length === 0 && !input.activeFocus,
                    "leaving settings clears its query, results and input focus")
                search.shown = true
                search.query = "font"
                const beforeHiddenChoice = MenuState.settingsSection
                search.visible = false
                search.choose("interface")
                root._check(!search.searching && MenuState.settingsSection === beforeHiddenChoice,
                    "hidden settings search rejects navigation through an old result")
                search.visible = true
                search.query = "font"
                MenuState.setSettingsSection("clock")
                root._check(!search.searching,
                    "a sidebar or IPC section request replaces the search with that section")
                search.query = "font"
                MenuState.setSettingsSection("clock")
                root._check(!search.searching,
                    "retapping the selected settings section also clears search")
                ShellSettings.uiScale = 1.5
                f.width = 232
                search.query = "notifications"
                f.input.wait(60)
                const row = root._findTrayNode(search, item => item.title === "Notifications")
                const title = root._findTrayNode(row, item => item.text === "Notifications")
                root._check(row && title && !title.truncated
                        && row.x + row.width <= search.width + 0.5
                        && input.width > 100,
                    "settings results and their input remain readable in a narrow pane at the largest scale")
                search.visible = false
                const page = settingsPageFactory.createObject(f.contentItem, {
                    width: 232, active: true, powerOpen: false
                })
                const pageSearch = root._findTrayNode(page, item => typeof item.choose === "function")
                const detail = page.children.find(child => child._bodyGap !== undefined)
                root._check(pageSearch && detail, "Settings embeds search above its section body")
                if (pageSearch && detail) {
                    root._check(!pageSearch.expanded && detail.y === 0
                            && page.implicitHeight === detail.height,
                        "collapsed settings search occupies the existing heading without adding a row")
                    const scroller = flickableFactory.createObject(root)
                    scroller.interactive = Qt.binding(() => scroller.height < 150)
                    page.scroller = scroller
                    const pinHeader = detail.children.find(child => child.pinnedToViewport === true)
                    const pinClip = detail.children.find(child => child._bleed !== undefined)
                    scroller.contentY = 120
                    const pinnedNow = pinHeader && pinClip && pinHeader.y === 120 && pageSearch.y >= 120
                        && pinClip.clip && pinClip.y === 120 + page.pinnedHeight
                    scroller.contentY = 0
                    root._check(pinnedNow && pinHeader.y === 0 && !pinClip.clip,
                        "a scrolled settings page holds its header and search in place and cuts the body below them")
                    root._check(page.revealOffset(600, 50) === 200 && page.revealOffset(120, 50) === 50
                            && page.revealOffset(300, -4) === 100,
                        "a search result lands a third of the way down, or below a pinned header taller than that")
                    const insetView = insetScrollFactory.createObject(f.contentItem)
                    insetView.target.forceActiveFocus(Qt.TabFocusReason)
                    f.input.wait(30)
                    const shownBelow = insetView.contentY === 220
                    insetView.contentY = 400
                    insetView.forceActiveFocus()
                    insetView.target.forceActiveFocus(Qt.TabFocusReason)
                    f.input.wait(30)
                    const revealedUnder = insetView.contentY === 260
                    insetView.contentY = 0
                    insetView.pinnedTarget.forceActiveFocus(Qt.TabFocusReason)
                    f.input.wait(30)
                    root._check(shownBelow && revealedUnder && insetView.contentY === 0,
                        "keyboard focus reveals a row below a pinned header and leaves the header's own controls alone")
                    insetView.destroy()
                    scroller.contentY = 200
                    scroller.flick(0, -1000)
                    const previousHeight = page.implicitHeight
                    pageSearch.query = "font"
                    root._check(!detail.visible && !detail.enabled && page.implicitHeight >= previousHeight,
                        "search results replace section controls without shrinking the panel under the pointer")
                    root._check(!scroller.interactive && !scroller.flicking && scroller.contentY === scroller.originY,
                        "search results stop outer scroll momentum and keep the field out of blank held-height space")
                    scroller.height = 160
                    const stub = selectStubFactory.createObject(root)
                    MenuState.claimSettingsSelect(stub)
                    root._check(page.dismissInline() && stub.folded && pageSearch.searching,
                        "an open settings dropdown is dismissed before the search query")
                    stub.destroy()
                    root._check(page.dismissInline() && !pageSearch.searching && detail.visible,
                        "dismissing the settings search restores the current section")
                    root._check(!scroller.interactive,
                        "closing search restores the original scroll binding's current value")
                    scroller.height = 100
                    root._check(scroller.interactive,
                        "the restored scroll binding continues responding to viewport changes")
                    scroller.contentY = 300
                    scroller.flick(0, -1000)
                    f.input.keyClick(Qt.Key_F, Qt.ControlModifier)
                    const pageInput = root._findTrayNode(pageSearch, item => item.maximumLength !== undefined)
                    const heldAt = scroller.contentY
                    f.input.wait(30)
                    root._check(pageSearch.expanded && pageInput.activeFocus && !scroller.flicking
                            && heldAt > scroller.originY && scroller.contentY === heldAt
                            && pageSearch.y >= heldAt - scroller.originY,
                        "Ctrl+F stops scrolling and focuses the pinned settings search where the page stands")
                    page.scroller = null
                    scroller.destroy()
                    pageSearch.query = "font"
                    page.active = false
                    root._check(!pageSearch.searching && !pageSearch.expanded && !pageInput.activeFocus,
                        "switching away from Settings clears a cached page's search state")
                }
                page.destroy()
            }
            f.close()
            f.destroy()
            ShellSettings.uiScale = state.saved.scale
            ShellSettings.reduceMotion = state.saved.reduce
            MenuState.selectTab(state.saved.tab)
            MenuState.setSettingsSection(state.saved.section)
            MenuState.open = state.saved.open
            root._settingsSearchProbe = null
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
            TrayMenuState.openAt(17, null, probeAnchor)
            TrayMenuState._setAnchor(null)
            _anchorHoldSettle.restart()
        }
    }

    // the regrab timer stays private, so its effect is what gets read: a stray close lands within its 150 ms
    property int _anchorHoldStep: 0
    Timer {
        id: _anchorHoldSettle
        interval: 220
        onTriggered: {
            const popup = TrayMenuState
            if (root._anchorHoldStep === 0) {
                root._check(popup.open && popup.anchorSource === null,
                    "deliberately clearing a popup anchor arms no close")
                popup._setAnchor(probeAnchor)
                popup.anchorSource = null
                popup.close()
                popup.openUnanchored()
                root._anchorHoldStep = 1
                restart()
                return
            }
            root._check(popup.open,
                "closing a popup cancels the close its dropped anchor armed")
            popup.close()
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
    property var _motionBodyItem: null
    property int _motionSectionSwaps: 0
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
        // the first card into an empty stack builds while the stack still reads empty, so it is hidden as it completes
        root._entryHost = entryHostFactory.createObject(barFixtureHost)
        const freshId = 2147483590
        root._entryWasUnseen = !Notifications.isSeen(freshId)
        root._entryCard = notificationCardFactory.createObject(root._entryHost, { notifId: freshId })
        root._entryHeldHidden = root._entryCard._entryPending === true
        root._entryHost.visible = true
        root._entryShownAt = Date.now()
        root._motionStep = 0
        _pageMotionCheck.interval = 40
        _pageMotionCheck.restart()
    }
    Component { id: entryHostFactory; Item { visible: false; width: 360; height: 200 } }
    property var _entryHost: null
    property var _entryCard: null
    property bool _entryWasUnseen: false
    property bool _entryHeldHidden: false
    property real _entryShownAt: 0
    function _checkHiddenCardEntry(): void {
        const card = root._entryCard
        const rect = card ? card.children.find(c => c._behaviorEnabled !== undefined) : null
        // the slide, fade and height all run 200-280 ms; a check that came later than that cannot see them
        const inTime = Date.now() - root._entryShownAt < 180
        root._check(root._entryWasUnseen && root._entryHeldHidden && card && !card._entryPending && rect
                && rect._behaviorEnabled && (!inTime || (card.collapseRatio < 1 && rect.opacity < 1)),
            "a new card built while hidden plays its entrance when it is first shown, not in place")
        root._entryHost.destroy()
        root._entryHost = null
        root._entryCard = null
    }

    Timer {
        id: _pageMotionCheck
        onTriggered: {
            const page = root._motionPage
            switch (root._motionStep++) {
            case 0:
                root._checkHiddenCardEntry()
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
                const detail = settings.children.find(child => child._bodyGap !== undefined)
                const body = root._findTrayNode(detail, child => child.sourceComponent !== undefined)
                root._check(settings.contentReady, "settings content finishes its initial load")
                body.active = false
                settings._awaitingSectionEnter = true
                detail._fade = 0
                detail._startSectionEnter()
                root._check(settings._awaitingSectionEnter && detail._fade === 0,
                    "a settings section waits for its loader before starting its reveal")
                body.active = true
                interval = 500
                restart()
                break
            }
            case 3: {
                const settings = root._motionSettings
                const detail = settings.children.find(child => child._bodyGap !== undefined)
                const revealed = settings.contentReady && !settings._awaitingSectionEnter
                        && detail._fade === 1 && detail._shift === 0
                        && detail._lift === 0
                if (root._motionNotYet(revealed)) break
                root._check(revealed, "a ready settings section completes its reveal")
                // a section change moves the body alone; the header frame and the search toggle hold still
                const sectionBody = root._findTrayNode(detail, child => child.sourceComponent !== undefined)
                const headerTitle = root._findTrayNode(detail, item => item.font !== undefined
                    && item.font.weight === Font.DemiBold && item.text === settings._sectionMeta[settings._shownSection]?.label)
                detail._fade = 0.5
                root._check(detail.transform.length === 0 && sectionBody.transform.length === 1
                        && detail.opacity === 1 && sectionBody.parent.opacity === 0.5
                        && headerTitle !== null && headerTitle.parent.opacity === 0.5,
                    "a section change fades the header's words with the body but moves only the body")
                detail._fade = 1
                const enterDefer = detail.data.find(item => item.interval !== undefined && item.triggered !== undefined)
                const glidesWere = Motion.layoutGlides
                Motion.layoutGlides = 0
                const stillInterval = enterDefer ? enterDefer.interval : -1
                Motion.layoutGlides = glidesWere + 1
                const glidingInterval = enterDefer ? enterDefer.interval : -1
                Motion.layoutGlides = glidesWere
                root._check(stillInterval === 0 && glidingInterval === Motion.ms(55),
                    "a new section enters at once unless the panel is resizing under it")
                MenuState.close()
                MenuState.setSettingsSection("clock")
                root._check(settings._shownSection === "clock" && detail._fade === 1
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
                MenuState.setSettingsSection("updates")
                interval = 500
                restart()
                break
            }
            case 4: {
                const settings = root._motionSettings
                if (root._motionNotYet(settings.contentReady)) break
                root._check(root._findTrayNode(settings, item => item.title === "Silere Shell") !== null
                        && root._findTrayNode(settings, item => item.title === "Feature readiness") !== null
                        && root._findTrayNode(settings, item => item.key === "updatesWidget") !== null,
                    "the system overview builds update controls and diagnostics in one page")
                const detail = settings.children.find(child => child._bodyGap !== undefined)
                const body = root._findTrayNode(detail, child => child.sourceComponent !== undefined)
                root._motionBodyItem = body.item
                root._motionSectionSwaps = 0
                settings.sectionSwapped.connect(() => root._motionSectionSwaps++)
                MenuState.open = true
                MenuState.setSettingsSection("clock")
                MenuState.setSettingsSection("updates")
                interval = Motion.pageOut + Motion.pageIn + 80
                restart()
                break
            }
            case 5: {
                const settings = root._motionSettings
                const detail = settings.children.find(child => child._bodyGap !== undefined)
                const body = root._findTrayNode(detail, child => child.sourceComponent !== undefined)
                root._check(root._motionSectionSwaps === 0 && body.item === root._motionBodyItem
                        && detail._fade === 1 && detail._shift === 0 && detail._lift === 0,
                    "returning mid-fade keeps the settings body and reverses to a settled reveal")
                const exit = detail.data.find(item => item.animations?.length === 2)
                let exits = 0
                if (exit) exit.started.connect(() => exits++)
                const toggle = root._findTrayNode(settings, item => item.key === "updatesWidget")
                const checked = ShellSettings.updatesWidget
                MenuState.setSettingsSection("clock")
                if (toggle) toggle._activate()
                root._check(toggle && !toggle.enabled && ShellSettings.updatesWidget === checked,
                    "a departing settings section rejects changes from its retained controls")
                MenuState.setSettingsSection("theme")
                MenuState.setSettingsSection("separators")
                root._check(exit && exits === 1,
                    "successive settings selections share one exit instead of restarting its fade")
                // Return to the retained body before continuing the page checks.
                MenuState.setSettingsSection("updates")
                root._check(detail.enabled,
                    "returning to the displayed settings section restores its controls")
                root._motionBodyItem = null
                page.active = false
                page.settleVisual(false)
                page.revealReady = false
                page._menuOpenSettled = true
                page.active = true
                interval = Motion.pageIn + 80
                restart()
                break
            }
            case 6:
                root._check(page._awaitingEnter && page.opacity === 0,
                    "a page with a pending body does not spend its fade on empty content")
                page.viewportReady = false
                page.revealReady = true
                root._check(page._awaitingEnter && page.opacity === 0,
                    "a ready page waits for the widening panel to make room for its reveal")
                page.active = false
                page.viewportReady = true
                root._check(!page._awaitingEnter && page.opacity === 0,
                    "body readiness cannot revive a page after another tab was selected")
                page.revealReady = false
                page.active = true
                ShellSettings.reduceMotion = true
                root._check(page.opacity === 1 && !page._awaitingEnter,
                    "reduced motion clears a pending reveal without leaving a page invisible")
                ShellSettings.reduceMotion = false
                page.active = false
                page.settleVisual(false)
                page.active = true
                page.revealReady = true
                interval = Motion.pageIn + 80
                restart()
                break
            case 7:
                root._check(page.opacity === 1 && page._pageShift === 0
                        && page._pageLift === 0 && !page._awaitingEnter,
                    "a retained page completes its reveal after its body becomes ready")
                root._motionPage.destroy()
                root._motionPage = pageShellFactory.createObject(root, {
                    active: true, powerOpen: false, animateOnCreate: true,
                    revealReady: true, viewportReady: false
                })
                interval = Motion.pageIn + 80
                restart()
                break
            case 8:
                root._check(page.opacity === 0 && page._awaitingEnter,
                    "a newly loaded page also waits for its panel viewport")
                page.active = false
                page.viewportReady = true
                interval = Motion.pageOut + 80
                restart()
                break
            case 9:
                root._check(page.opacity === 0 && !page._awaitingEnter,
                    "a cold page stays hidden when its body finishes after departure")
                MenuState.setSettingsSection("surface")
                MenuState.setSettingsSection("separators")
                MenuState.setSettingsSection("workspaces")
                interval = Motion.pageOut + Motion.pageIn + 180
                restart()
                break
            case 10: {
                const settings = root._motionSettings
                const detail = settings.children.find(child => child._bodyGap !== undefined)
                const settled = settings.contentReady && !settings._awaitingSectionEnter
                    && detail._fade === 1 && detail._shift === 0 && detail._lift === 0
                if (root._motionNotYet(settled)) break
                root._check(settled && settings._shownSection === "workspaces"
                        && root._motionSectionSwaps === 1 && detail.enabled,
                    "a rapid settings sequence reveals only its latest destination")
                MenuState.setSettingsSection("clock")
                ShellSettings.reduceMotion = true
                root._check(settings._shownSection === "clock" && detail._fade === 1
                        && detail._shift === 0 && detail._lift === 0,
                    "reduced motion settles an interrupted settings transition at its destination")
                MenuState.close()
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
        const resultProbe = boundedProcessFactory.createObject(root)
        root._check(resultProbe.completedSuccessfully(0)
                && !resultProbe.completedSuccessfully(1)
                && !resultProbe.completedSuccessfully(127),
            "bounded process success requires a clean zero exit")
        resultProbe.timedOut = true
        root._check(!resultProbe.completedSuccessfully(0)
                && !resultProbe.completedSuccessfully(1),
            "timed-out bounded processes reject every exit status")
        resultProbe.destroy()
        root._timeoutProbe = boundedProcessFactory.createObject(root, {
            command: ["bash", "-c", "trap 'exit 0' TERM; while :; do sleep 0.02; done"],
            timeoutMs: 80
        })
        let timeoutSeen = false
        root._timeoutProbe.timeoutReached.connect(function() {
            root._check(root._timeoutProbe.timedOut,
                "bounded process records its timeout")
            timeoutSeen = true
        })
        root._timeoutProbe.exited.connect(function(code) {
            if (!timeoutSeen) return
            root._check(code === 0 && !root._timeoutProbe.completedSuccessfully(code),
                "a helper exiting zero after its timeout never reports successful completion")
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
            Qt.callLater(root._runChainedSpawnCheck)
        }
    }

    // Process signals exited before the next run's runningChanged, so a command chained from exited
    // must not inherit the finished run's exit
    function _runChainedSpawnCheck(): void {
        const chained = boundedProcessFactory.createObject(root, { command: ["true"] })
        const codes = []
        let settled = false
        chained.exited.connect(function(code) {
            codes.push(code)
            if (codes.length === 1) chained.exec(["/nonexistent/silere-probe-binary"])
        })
        chained.runningChanged.connect(function() {
            if (codes.length === 0 || chained.running || settled) return
            settled = true
            Qt.callLater(function() {
                root._check(codes.length === 2 && codes[0] === 0 && codes[1] === 127,
                    "a bounded process chained from exited still reports its spawn failure")
                chained.destroy()
                root._runChainedDeadlineCheck()
            })
        })
        chained.running = true
    }

    // a run chained from exited never sees running fall, so a timeout bound to running alone
    // kept the finished run's deadline: the second 0.6 s run here was cut off 0.4 s in
    function _runChainedDeadlineCheck(): void {
        const chained = boundedProcessFactory.createObject(root, {
            command: ["sleep", "0.6"], timeoutMs: 1000
        })
        let runs = 0
        chained.exited.connect(function(code) {
            runs++
            if (runs === 1) { chained.running = true; return }
            const complete = chained.completedSuccessfully(code)
            Qt.callLater(function() {
                root._check(complete, "a bounded process chained from exited gets a deadline of its own")
                chained.destroy()
                root._runChainedSupervisedCheck()
            })
        })
        chained.running = true
    }

    function _runChainedSupervisedCheck(): void {
        const chained = supervisedProcessFactory.createObject(root, {
            command: ["true"], restartDelay: 60000, superviseWhen: true
        })
        let exits = 0
        let settled = false
        chained.exited.connect(function() {
            exits++
            if (exits === 1) chained.exec(["/nonexistent/silere-probe-binary"])
        })
        chained.runningChanged.connect(function() {
            if (exits === 0 || chained.running || settled) return
            settled = true
            Qt.callLater(function() {
                root._check(exits === 1 && chained.gaveUp,
                    "a supervised process chained from exited gives up when that command cannot start")
                chained.superviseWhen = false
                chained.destroy()
                root._startHistoryPersistenceProbe()
            })
        })
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
        store.writePaused = true
        store.queue()
        store.flush(false)
        store.flush(true)
        persistenceGuardFixture.reload()
        root._check(persistenceGuardFixture.text() === externalText
                && store.lastSavedText.length === 0,
            "a pending migration backup blocks ordinary and forced persistence without claiming a save")
        store.stop()
        root._check(store.writePaused,
            "cancelling a debounce cannot lift a pending backup's persistence barrier")
        store.writePaused = false
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

        let removedReadSeen = false
        store.watchChanges = true
        store.loadFailed.connect(function() { removedReadSeen = true })
        const removal = boundedProcessFactory.createObject(root, {
            command: ["rm", "--", store.path], timeoutMs: 2000
        })
        removal.running = true
        const removalDeadline = Date.now() + 3000
        while ((!removedReadSeen || removal.running) && Date.now() < removalDeadline)
            discoveryClock.wait(10)
        root._check(removedReadSeen && !removal.running,
            "removing a watched settings fixture reports the failed reload")
        root._check(store.lastSavedText.length === 0,
            "a failed reload invalidates the saved-content cache for a removed file")
        store.flush(true)
        persistenceGuardFixture.reload()
        root._check(persistenceGuardFixture.text().trim() === sessionText,
            "flushing unchanged settings recreates a file removed after the previous save")
        removal.destroy()
        store.destroy()
        root._barPointerWindow = barPointerFactory.createObject(root)
        root._check(root._barPointerWindow !== null, "the bar pointer fixture creates an offscreen window")
        if (root._barPointerWindow) _barPointerSettle.restart()
        else Qt.callLater(root._finish)
    }

    Timer {
        id: _volumeCancelCheck
        interval: 120
        onTriggered: {
            const control = root._volumeCancelProbe
            // child exit is asynchronous and parallel checks can delay delivery.
            // Stay below the helper's 3s safety timeout so a missed cancel still fails
            if (control && control._wpctl.running && Date.now() < root._volumeCancelDeadline) {
                restart()
                return
            }
            root._check(control && !control._wpctl.running,
                "an invalidated audio route leaves no fallback process running")
            if (control) {
                control._wpctl.running = false
                control._wpctlGap.stop()
                control.destroy()
            }
            root._volumeCancelProbe = null
            root._volumeCancelDone = true
        }
    }

    function _checkBarWheelLifetimes(f, app, tile): void {
        const wheel = (target, x, y) => f.input.mouseWheel(target,
            target.width / 2, target.height / 2, x, y, Qt.NoButton, Qt.NoModifier, 0)
        const trayKey = item => item._wheelKey ?? ("tray:" + item.modelData.id)
        const resetTray = item => {
            Scroll.resetControl(trayKey(item) + ":h")
            Scroll.resetControl(trayKey(item) + ":v")
        }
        for (const gate of ["bar", "app", "widget"]) {
            resetTray(tile)
            app.wheelDelta = 0
            app.horizontalWheelDelta = 0
            wheel(f.tray, 0, 60)
            wheel(f.tray, 60, 0)
            if (gate === "bar") { f.tray.barActive = false; f.tray.barActive = true }
            if (gate === "app") {
                ShellSettings.setTrayItemHidden(app.id, true)
                ShellSettings.setTrayItemHidden(app.id, false)
            }
            if (gate === "widget") { ShellSettings.trayWidget = false; ShellSettings.trayWidget = true }
            wheel(f.tray, 0, 60)
            wheel(f.tray, 60, 0)
            root._check(app.wheelDelta === 0 && app.horizontalWheelDelta === 0,
                "tray scroll input starts fresh after concealing the " + gate)
        }
        resetTray(tile)
        const replacement = trayItemFactory.createObject(f, { id: app.id, title: "Replacement app" })
        wheel(f.tray, 0, 60)
        tile.modelData = replacement
        wheel(f.tray, 0, 60)
        root._check(replacement.wheelDelta === 0,
            "a replacement tray app cannot finish the previous app's partial scroll")
        tile.modelData = app
        replacement.destroy()
        resetTray(tile)
        const other = trayWidgetFactory.createObject(f.contentItem, {
            trayModel: Qt.binding(() => [app]), x: 300, y: 12, height: 48
        })
        f.input.wait(10)
        const otherTile = root._findTrayNode(other, item => item.modelData === app)
        app.wheelDelta = 0
        wheel(f.tray, 0, 60)
        wheel(other, 0, 60)
        root._check(app.wheelDelta === 0,
            "the same tray app on two bars has independent partial scroll gestures")
        wheel(f.tray, 0, 60)
        wheel(other, 0, 60)
        root._check(app.wheelDelta === 240,
            "each tray bar completes its own wheel notch")
        resetTray(tile)
        if (otherTile) resetTray(otherTile)
        other.destroy()
        const before = app.activations
        f.input.mousePress(f.tray, f.tray.width / 2, f.tray.height / 2, Qt.LeftButton, Qt.NoModifier, 0)
        for (let i = 0; i < 4; i++) {
            app.icon = i % 2 ? "utilities-terminal" : "application-x-executable"
            app.tooltipTitle = "Updating icon " + i
            f.input.wait(15)
        }
        f.input.mouseRelease(f.tray, f.tray.width / 2, f.tray.height / 2, Qt.LeftButton, Qt.NoModifier, 0)
        root._check(app.activations === before + 1
                && root._findTrayNode(f.tray, item => item.modelData === app) === tile,
            "tray icon and tooltip updates preserve an in-progress click and its delegate")

        const mediaKey = f.media._wheelKey ?? "media"
        Scroll.resetControl(mediaKey)
        wheel(f.media, 0, 60)
        const received = Scroll._accums[mediaKey] === 60
        f.media.barActive = false
        f.media.barActive = true
        root._check(received && Scroll._accums[mediaKey] === undefined,
            "concealing the media bar discards its partial track-switch gesture")
        Scroll.resetControl(mediaKey)
        wheel(f.media, 0, 60)
        Media.playerChanged()
        root._check(Scroll._accums[mediaKey] === undefined,
            "changing the media player discards a gesture meant for the previous player")
        Scroll.resetControl(mediaKey)
        wheel(f.media, 0, 60)
        f.media.layoutWidthLimit = 0
        root._check(Scroll._accums[mediaKey] === undefined,
            "squeezing media out of the bar discards its partial scroll")
        f.media.layoutWidthLimit = 180
        Scroll.resetControl(mediaKey)
        const otherMedia = mediaWidgetFactory.createObject(f.contentItem, {
            x: 220, y: 110, width: 140, layoutWidthLimit: 140
        })
        wheel(f.media, 0, 60)
        wheel(otherMedia, 0, 60)
        const otherMediaKey = otherMedia._wheelKey ?? "media"
        root._check(Scroll._accums[mediaKey] === 60 && Scroll._accums[otherMediaKey] === 60,
            "two media bars keep their partial track-switch gestures separate")
        Scroll.resetControl(mediaKey)
        Scroll.resetControl(otherMediaKey)
        otherMedia.destroy()
    }

    Timer {
        id: _barPointerSettle
        interval: 150
        onTriggered: {
            const f = root._barPointerWindow
            f.requestActivate()
            f.input.mouseMove(f.cell, 12, 12)
            root._check(f.cell.hovered && f.reports.join(",") === "2:true",
                "a real pointer entering a workspace reports its identity")
            f.cell.wsId = 3
            root._check(f.reports.join(",") === "2:true,2:false,3:true",
                "reassigning a hovered workspace slot clears its old identity before reporting the new one")
            f.cell.barActive = false
            root._check(f.reports.join(",") === "2:true,2:false,3:true,3:false",
                "concealing a hovered workspace clears the reported identity")
            f.cell.barActive = true
            f.input.mouseMove(f.contentItem, 260, 80)
            root._check(f.cell._reportedHoverId === -1,
                "leaving a reassigned workspace clears its hover identity")
            f.input.mouseMove(f.pill, 12, 12)
            f.input.wait(100)
            root._check(f.pill.hovered && f.pill.expanded,
                "a real pointer dwell reveals a bar pill")
            let seconds = 0
            f.pill.secondaryActivated.connect(() => seconds++)
            f.input.mouseClick(f.pill, 12, 12, Qt.RightButton)
            const unoffered = seconds
            f.pill.hasSecondary = true
            f.input.mouseClick(f.pill, 12, 12, Qt.LeftButton)
            f.input.mouseClick(f.pill, 12, 12, Qt.RightButton)
            f.pill.barActive = false
            f.input.mouseClick(f.pill, 12, 12, Qt.RightButton)
            f.pill.barActive = true
            f.pill.hasSecondary = false
            root._check(unoffered === 0 && seconds === 1,
                "a right-click runs a pill's second action once: not where none is offered, not from a left click, not on a sleeping bar")
            Scroll._processDelta(30, f.pill.wheelKey, 60, 1, 0)
            f.pill.barActive = false
            root._check(!f.pill.hoverActive && !f.pill.expanded
                    && Scroll._accums[f.pill.wheelKey] === undefined,
                "concealing a hovered pill clears its reveal and partial wheel gesture")
            f.pill.barActive = true
            const oldKey = f.pill.wheelKey
            Scroll._processDelta(30, oldKey, 60, 1, 0)
            f.pill.wheelKey = "probe:replacement-route"
            root._check(Scroll._accums[oldKey] === undefined,
                "retargeting a pill forgets scroll input from the previous device")
            Scroll._processDelta(30, f.pill.wheelKey, 60, 1, 0)
            f.pill.collapsed = true
            root._check(Scroll._accums[f.pill.wheelKey] === undefined,
                "a collapsing pill discards its unfinished scroll gesture")
            const barWas = { tray: ShellSettings.trayWidget, hidden: ShellSettings.trayHidden,
                scale: ShellSettings.uiScale, reduce: ShellSettings.reduceMotion,
                hover: ShellSettings.valuesOnHover, media: ShellSettings.barShowMedia, shown: Media.shown }
            ShellSettings.reduceMotion = true
            ShellSettings.valuesOnHover = false
            ShellSettings.trayWidget = true
            ShellSettings.trayHidden = ""
            const app = trayItemFactory.createObject(f, { id: "__bar_pointer_tray__", title: "Bar pointer app" })
            f.tray.trayModel = [app]
            f.input.wait(20)
            const trayTile = root._findTrayNode(f.tray, item => item.modelData === app)
            root._check(trayTile !== null, "the bar pointer fixture builds a tray app")
            if (trayTile) {
                for (const scale of [1, 1.5]) {
                    ShellSettings.uiScale = scale
                    for (const h of [32, 48]) {
                        f.tray.height = h
                        f.input.wait(10)
                        const before = app.activations
                        f.input.mouseClick(f.tray, f.tray.cellWidth / 2, 1, Qt.LeftButton)
                        f.input.mouseClick(f.tray, f.tray.cellWidth / 2, h - 1, Qt.LeftButton)
                        root._check(app.activations === before + 2,
                            "tray clicks reach both bar edges at height " + h + " and interface scale " + scale)
                    }
                }
                const cap = root._findTrayNode(trayTile, item => item.radius !== undefined
                    && item.color !== undefined && item.width === trayTile.width)
                f.input.mouseMove(f.contentItem, 390, 85)
                TrayMenuState.sourceItem = app
                TrayMenuState.open = true
                root._check(cap && cap.height === Metrics.barRowHeight
                        && Math.abs(cap.y + cap.height / 2 - trayTile.height / 2) < 0.01
                        && cap.opacity === 1 && Qt.colorEqual(cap.color, Theme.barSelected),
                    "an open tray menu keeps a centred row-sized highlight on its full-height bar target")
                TrayMenuState.close()
                root._check(cap && cap.opacity === 0,
                    "closing a tray menu releases its selected highlight when the pointer is elsewhere")
            }
            ShellSettings.uiScale = barWas.scale
            ShellSettings.barShowMedia = true
            Media.shown = true
            const mediaClip = root._findTrayNode(f.media, item => item.preferredMaxW !== undefined)
            const longTrack = "The beginning of a long song title and its distinctive ending"
            if (mediaClip) mediaClip._shown = longTrack
            const mediaText = root._findTrayNode(f.media, item => item.text === longTrack && item.elide !== undefined)
            f.input.wait(20)
            f.input.mouseMove(f.media, Math.max(1, f.media.width / 2), 18)
            root._check(mediaText && mediaText.elide === Text.ElideLeft,
                "hovering a shortened media title reveals its ending with reduced motion")
            f.input.mouseMove(f.contentItem, 390, 85)
            root._check(mediaText && mediaText.elide === Text.ElideRight,
                "leaving the media title restores its beginning with reduced motion")
            if (trayTile) root._checkBarWheelLifetimes(f, app, trayTile)
            f.media.forceActiveFocus(Qt.TabFocusReason)
            f.media.layoutWidthLimit = 0
            f.input.wait(10)
            root._check(f.media.width === 0 && !f.media.Accessible.focusable && !f.media.activeFocus,
                "a media widget squeezed completely out of the bar releases keyboard focus and its tab stop")
            f.tray.trayModel = []
            app.destroy()
            ShellSettings.trayWidget = barWas.tray
            ShellSettings.trayHidden = barWas.hidden
            ShellSettings.valuesOnHover = barWas.hover
            ShellSettings.barShowMedia = barWas.media
            Media.shown = barWas.shown
            ShellSettings.reduceMotion = barWas.reduce
            f.input.mouseMove(f.contentItem, 260, 80)
            f.close()
            f.destroy()
            root._barPointerWindow = null
            Qt.callLater(root._runClockAnchorCheck)
        }
    }

    // reduced motion makes the resize one step, the case where a stale read stayed put until the calendar closed
    function _runClockAnchorCheck(): void {
        root._clockAnchorReduceWas = ShellSettings.reduceMotion
        root._clockAnchorDateWas = ShellSettings.clockShowDate
        ShellSettings.reduceMotion = true
        ShellSettings.clockShowDate = false
        root._clockAnchorStep = 0
        root._clockAnchorWindow = clockAnchorFactory.createObject(root)
        root._check(root._clockAnchorWindow !== null, "the clock anchor fixture creates an offscreen window")
        if (root._clockAnchorWindow) _clockAnchorSettle.restart()
        else Qt.callLater(root._finish)
    }

    Timer {
        id: _clockAnchorSettle
        interval: 200
        onTriggered: {
            const clock = root._clockAnchorWindow.clock
            const middle = clock.mapToItem(null, clock.width / 2, 0).x
            const held = CalendarState.open && Math.abs(CalendarState.effectiveAnchorX - middle) < 1
            if (root._clockAnchorStep === 0) {
                clock._openCalendar()
                root._check(CalendarState.open && CalendarState.anchorSource === clock,
                    "a clock in a centred zone opens the calendar from itself")
                root._clockAnchorWidth = clock.width
                ShellSettings.clockShowDate = true
            } else if (root._clockAnchorStep === 1) {
                root._check(held && clock.width > root._clockAnchorWidth,
                    "a centred clock gaining its date keeps the open calendar on its middle")
                ShellSettings.clockShowDate = false
            } else {
                root._check(held, "a centred clock losing its date keeps the open calendar on its middle")
                CalendarState.close()
                root._clockAnchorWindow.close()
                root._clockAnchorWindow.destroy()
                root._clockAnchorWindow = null
                ShellSettings.clockShowDate = root._clockAnchorDateWas
                ShellSettings.reduceMotion = root._clockAnchorReduceWas
                Qt.callLater(root._finish)
                return
            }
            root._clockAnchorStep++
            restart()
        }
    }
    property real _clockAnchorWidth: 0

    function _finish(): void {
        // here, seconds after the theme checks flipped the source and contrast, so no mode switch is still settling
        root._checkModeSwitchFades()
        root._check(root._volumeCancelDone, "the audio route cleanup check completes")
        root._check(root._ignoredUpdatesDone, "the ignored AUR package check completes")
        root._check(root._helperUpdatesDone, "the helper-only update split check completes")
        root._check(root._launchEnvDone, "the launch fallback environment check completes")
        root._check(root._zoneLinkDone, "the time zone link check completes")
        root._check(Motion.layoutGlides === 0 && !Motion.layoutGliding,
            "every panel glide gives its count back, including one destroyed mid-flight")
        root._runSettingsDiagnosticsProbe()
        ShellSettings.dnd = true
        ShellSettings.nightLightTemp = ShellSettings._defaults.nightLightTemp - 500
        ShellSettings.showSeconds = !ShellSettings._defaults.showSeconds
        root._check(ShellSettings.modifiedTotal >= 3 && ShellSettings.modifiedTotal > ShellSettings.modifiedCount,
            "the restore row counts settings no page lists, or it could not be pressed for them")
        root._check(ShellSettings.resetToDefaults() === true, "a restore with room for its copy goes ahead")
        root._check(ShellSettings.dnd === false && ShellSettings.modifiedTotal === 0
                && ShellSettings.nightLightTemp === ShellSettings._defaults.nightLightTemp
                && ShellSettings.showSeconds === ShellSettings._defaults.showSeconds,
            "restoring settings resets every one of them, Do Not Disturb and night light too")
        root._check(ShellSettings.canUndoReset, "a restore keeps a way back")
        // held, so the probe sees whether the undo left a write owed: the file on disk still holds the defaults
        ShellSettings._persistence.writePaused = true
        ShellSettings.undoReset()
        root._check(ShellSettings._persistence.lastSavedText !== ShellSettings._serialize(),
            "undoing a restore saves what it put back")
        ShellSettings._persistence.writePaused = false
        root._check(ShellSettings.dnd === true && ShellSettings.showSeconds !== ShellSettings._defaults.showSeconds
                && ShellSettings.nightLightTemp === ShellSettings._defaults.nightLightTemp - 500
                && !ShellSettings.canUndoReset,
            "undoing a restore puts every setting back")
        ShellSettings.resetToDefaults()
        if (root._failures === 0)
            console.warn("PROBE-LOGIC passed " + root._checks + " checks")
        else
            console.warn("PROBE-LOGIC failed " + root._failures + "/" + root._checks + " checks")
        // The harness validates this log before terminating the process.
        // Qt.exit starts teardown too early on newer Quickshell versions.
    }

    Component.onCompleted: Qt.callLater(root._run)
}
