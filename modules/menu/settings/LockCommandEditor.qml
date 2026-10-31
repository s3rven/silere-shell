import "../../../services"

CommandEditor {
    settingKey: "lockCommandCustom"
    label: "Lock command"
    example: "swaylock -f"
    editingEnabled: ShellSettings.lockProvider === "custom"
    savedHint: "Saved. Used when you choose Lock."
    emptyHint: "Enter a lock program and its arguments."
}
