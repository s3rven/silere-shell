pragma ComponentBehavior: Bound

import QtQuick
import "../../../config"
import "../../../services"
import "../../common"
import "../controls"

Column {
    id: root

    property string draft: ShellSettings.lockCommandCustom
    readonly property bool dirty: root.draft !== ShellSettings.lockCommandCustom
    readonly property bool _canEdit: root.enabled && root.visible
        && ShellSettings.lockProvider === "custom"
    readonly property string validationMessage: root.validationFor(root.draft)

    width: parent ? parent.width : 0
    spacing: 0

    function validationFor(text: string): string {
        const schema = ShellSettings.schemaFor("lockCommandCustom")
        if (!schema || !schema.re.test(text)) return "Use one line, up to 256 characters."
        if (text.trim().length === 0) return ""
        if (Settings.splitCommand(text).length === 0)
            return "Enter a program and close any quotes or escapes."
        return ""
    }

    function revert(): void {
        root.draft = ShellSettings.lockCommandCustom
        _input.focus = false
    }

    function save(): void {
        if (!root._canEdit || !root.dirty || root.validationMessage.length > 0) return
        ShellSettings.setValue("lockCommandCustom", root.draft.trim())
        root.revert()
    }

    Connections {
        target: ShellSettings
        function onLockCommandCustomChanged() { root.revert() }
        function onLockProviderChanged() { root.revert() }
    }
    Connections {
        target: MenuState
        function onSettingsActiveChanged() { if (!MenuState.settingsActive) root.revert() }
        function onSettingsSectionChanged() { root.revert() }
    }
    onEnabledChanged: if (!enabled) root.revert()
    onVisibleChanged: if (!visible) root.revert()

    Item {
        width: parent.width
        height: Math.max(Metrics.rowHeightFor(32), _label.implicitHeight + 12)
        ShellText {
            id: _label
            x: 42
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width - 56)
            text: "Lock command"
            color: Theme.text
            font.pixelSize: Settings.fontSize
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        }
    }

    Rectangle {
        x: 14
        width: Math.max(0, parent.width - 28)
        height: 4 * Math.ceil(Math.max(Metrics.rowHeightFor(36), _input.implicitHeight + 20) / 4)
        radius: Theme.radiusField
        color: Theme.menuControl
        OutlineBorder {
            radius: parent.radius
            outlineWidth: 1
            outlineColor: root.validationMessage.length > 0 ? Theme.warning
                : _input.activeFocus ? Theme.withAlpha(Theme.accent, Theme.focusRingSoftAlpha)
                : Theme.menuControlLine
            ColorFade on outlineColor {}
        }
        TextInput {
            id: _input
            anchors.fill: parent
            anchors.margins: 10
            enabled: root._canEdit
            text: root.draft
            onTextEdited: root.draft = text
            onAccepted: root.save()
            Keys.onEscapePressed: event => { root.revert(); event.accepted = true }
            selectByMouse: true
            // keep a too-long paste visible for validation instead of silently saving a truncated command
            maximumLength: 4096
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text
            selectionColor: Theme.withAlpha(Theme.accent, 0.4)
            font.family: Settings.font
            font.pixelSize: Settings.fontSize
            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
            clip: true
            Accessible.name: "Lock command"
            Accessible.description: root.validationMessage.length > 0
                ? root.validationMessage : "Lock program and arguments"
            ShellText {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                visible: _input.text.length === 0
                text: "swaylock -f"
                color: Theme.menuTextDetail
                font.pixelSize: Settings.fontSize
            }
        }
    }

    HintText {
        text: root.validationMessage.length > 0 ? root.validationMessage
            : root.dirty ? "Unsaved changes"
            : root.draft.trim().length === 0 ? "Enter a lock program and its arguments."
            : "Saved. Used when you choose Lock."
        textColor: root.validationMessage.length > 0 ? Theme.menuTextWarning : Theme.menuTextDetail
    }

    Item {
        width: parent.width
        height: Metrics.rowHeightFor(40)
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 12
            spacing: 8
            ActionButton {
                label: "Revert"
                enabled: root._canEdit && root.dirty
                onTriggered: root.revert()
            }
            ActionButton {
                label: "Save"
                emphasis: true
                enabled: root._canEdit && root.dirty && root.validationMessage.length === 0
                onTriggered: root.save()
            }
        }
    }
}
