import QtQuick
import Quickshell
import Quickshell.Io
import "../../../config"
import "../../../services"
import "../../common"
import "../controls"
import "../../../services/KeybindList.js" as KeybindList

// the compositor's shortcuts and what each does, read from Hyprland when the page opens or the config is saved;
// nothing polls. Then Silere's own calls worth a key, each a line to paste into that config
Column {
    id: root
    width: parent ? parent.width : 0

    property var rows: []
    property bool loaded: false
    property string failure: ""
    property string query: ""
    readonly property var shown: KeybindList.filter(root.rows, root.query)
    // the config's language, read off its binds; with none read yet, Lua, as Hyprland 0.55 and later read only that
    readonly property bool lua: root.rows.length === 0 || root.rows.some(r => r.lua)
    readonly property int unnamed: root.rows.filter(r => !r.own).length
    // a line names the launcher as the compositor will find it: on PATH, or this copy's own
    readonly property string launcher: !SystemTools.ready || SystemTools.hasSilere ? "silere"
        : KeybindList.launcherWord(Quickshell.shellDir + "/scripts/silere")
    readonly property var suggestions: KeybindList.suggest(root.rows, root.lua, Compositor.globalShortcuts, root.launcher)
    property string copied: ""

    // a save while a read runs reads again once it ends; that read may have started before the change
    property bool _readAgain: false
    function load(): void {
        if (!Compositor.isHyprland) return
        if (_read.running) {
            root._readAgain = true
            return
        }
        _read.running = true
    }
    Component.onCompleted: root.load()
    // a bind added since the page last showed appears when it opens again
    Connections {
        target: MenuState
        function onSettingsSectionChanged() { if (MenuState.settingsSection === "keybinds") root.load() }
    }
    // a line pasted from below shows as bound once the config is saved
    Connections {
        target: Compositor
        function onConfigReloaded() { if (MenuState.settingsSection === "keybinds") root.load() }
    }
    Timer { id: _copiedHold; interval: 1600; onTriggered: root.copied = "" }

    BoundedProcess {
        id: _read
        timeoutMs: 5000
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector { id: _out }
        onExited: code => {
            const parsed = _read.completedSuccessfully(code) ? KeybindList.parse(_out.text, 500) : null
            root.failure = parsed ? "" : "Could not read Hyprland's keybinds"
            if (parsed) root.rows = parsed
            root.loaded = true
            if (root._readAgain) {
                root._readAgain = false
                Qt.callLater(root.load)
            }
        }
    }

    SectionLabel { label: "KEYBINDS"; first: true }
    HintText {
        visible: !Compositor.isHyprland
        text: Compositor.isNiri ? "niri lists its own with Mod + Shift + /." : "Keybinds are read from Hyprland."
    }

    SettingsCard {
        visible: Compositor.isHyprland

        Item {
            width: parent.width
            height: 4 * Math.ceil((_field.height + 20) / 4)
            Rectangle {
                id: _field
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, parent.width - 28)
                height: 4 * Math.ceil(Math.max(Metrics.rowHeightFor(36), _input.implicitHeight + 20) / 4)
                radius: Theme.radiusField
                color: Theme.menuControl
                transform: PixelSnap { item: _field; dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1 }
                OutlineBorder {
                    radius: parent.radius
                    outlineWidth: 1
                    outlineColor: _input.activeFocus ? Theme.withAlpha(Theme.accent, Theme.focusRingSoftAlpha)
                        : Theme.menuControlLine
                    ColorFade on outlineColor {}
                }
                TextInput {
                    id: _input
                    activeFocusOnTab: true
                    anchors.fill: parent
                    anchors.margins: 10
                    onTextEdited: root.query = text
                    Keys.onShortcutOverride: event => { if (event.key === Qt.Key_Escape && text.length > 0) event.accepted = true }
                    Keys.onEscapePressed: event => {
                        if (text.length === 0) { event.accepted = false; return }
                        text = ""
                        root.query = ""
                        event.accepted = true
                    }
                    selectByMouse: true
                    maximumLength: 128
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.text
                    selectionColor: Theme.withAlpha(Theme.accent, 0.4)
                    font.family: Settings.font
                    font.pixelSize: Settings.fontSize
                    inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                    clip: true
                    Accessible.name: "Filter keybinds"
                    Accessible.description: "Words from what a bind does or its keys"
                    FocusScroll { revealTarget: _field }
                    ShellText {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: _input.text.length === 0
                        text: "Filter, such as volume or Super + Q"
                        color: Theme.menuTextDetail
                        font.pixelSize: Settings.fontSize
                    }
                }
            }
        }

        // one block of rows, not a card row each: the card re-reads every row each time one is added, so 500 binds
        // took a gigabyte and froze the shell 3.5 s. Each row draws the divider above it instead
        Column {
            width: parent.width
        Repeater {
            // a count, so typing in the filter rebinds rows instead of rebuilding them
            model: root.shown.length
            delegate: Item {
                id: _bind
                required property int index
                readonly property var bind: root.shown[_bind.index] ?? null
                readonly property bool described: !!_bind.bind && _bind.bind.action.length > 0
                // a reading such as "Run a command" names a kind of bind, not this one
                readonly property bool exact: _bind.described && _bind.bind.exact
                width: parent ? parent.width : 0
                height: Math.max(Metrics.rowHeightFor(32), _action.implicitHeight + 12)
                Accessible.role: Accessible.StaticText
                Accessible.name: _bind.bind ? (_bind.described ? _bind.bind.action : "No description") + ", " + _bind.bind.keys : ""

                // as the card's own dividers draw: whole logical pixels, one output pixel thick
                Rectangle {
                    readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
                    visible: _bind.index > 0
                    x: 14
                    y: Math.round(_bind.y) - _bind.y
                    width: Math.max(0, parent.width - 28)
                    height: Math.max(1, Math.ceil(_dpr - 0.5)) / _dpr
                    antialiasing: false
                    color: Theme.menuDivider
                }

                ShellText {
                    id: _keys
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, Math.round(parent.width * 0.5))
                    horizontalAlignment: Text.AlignRight
                    text: _bind.bind ? (_bind.bind.submap.length > 0 ? _bind.bind.submap + " · " : "") + _bind.bind.keys : ""
                    color: Theme.menuTextDetail
                    font.pixelSize: Settings.fontCaption
                    elide: Text.ElideLeft
                }
                ShellText {
                    id: _action
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, _keys.x - x - 12)
                    text: _bind.described ? _bind.bind.action : "No description"
                    color: _bind.exact ? Theme.text : _bind.described ? Theme.menuTextDetail : Theme.menuTextQuiet
                    font.pixelSize: Settings.fontSize
                    elide: Text.ElideRight
                }
            }
        }
        }
    }

    HintText {
        visible: Compositor.isHyprland && root.loaded
        text: root.failure.length > 0 ? root.failure
            : root.rows.length === 0 ? "Hyprland reports no keybinds."
            : root.shown.length === 0 ? "No keybind matches."
            : root.query.trim().length > 0 ? root.shown.length + " of " + root.rows.length + " keybinds"
            : root.rows.length + " keybinds, as your Hyprland config sets them"
        textColor: root.failure.length > 0 ? Theme.menuTextWarning : Theme.menuTextDetail
    }
    HintText {
        visible: Compositor.isHyprland && root.loaded && root.failure.length === 0 && root.unnamed > 0
            && root.query.trim().length === 0
        text: (root.unnamed === root.rows.length ? "No bind has a description, so each is named by what it does."
                : root.unnamed === 1 ? "One bind has no description, so it is named by what it does."
                : root.unnamed + " binds have no description, so they are named by what they do.")
            + (root.lua ? " To name one, add { description = \"…\" } to its hl.bind."
                : " To name one, write it as bindd = SUPER, Q, Terminal, exec, kitty.")
    }

    SectionLabel { visible: Compositor.isHyprland && root.loaded && root.failure.length === 0; label: "SILERE SHORTCUTS" }
    SettingsCard {
        visible: Compositor.isHyprland && root.loaded && root.failure.length === 0

        Repeater {
            model: root.suggestions
            ControlRow {
                required property var modelData
                readonly property bool bound: modelData.bound.length > 0
                glyph: modelData.glyph
                title: modelData.label
                status: bound ? "On " + modelData.bound
                    : modelData.free ? "Copies a bind on " + modelData.keys
                    : modelData.keys + " is taken: edit after pasting"
                statusColor: !bound && !modelData.free ? Theme.warning : "transparent"
                valueText: bound ? "" : root.copied === modelData.call ? "Copied" : "Copy"
                valueIsAction: !bound
                passive: bound
                onActivated: {
                    Quickshell.clipboardText = modelData.line
                    root.copied = modelData.call
                    _copiedHold.restart()
                }
            }
        }
    }
    HintText {
        visible: Compositor.isHyprland && root.loaded && root.failure.length === 0
        text: "Paste a copied line into " + (root.lua ? "hyprland.lua" : "hyprland.conf")
            + " and save: Hyprland applies it at once."
    }
}
