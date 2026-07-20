import QtQuick
import "../../services"

Column {
    width: parent ? parent.width : 0
    spacing: 0

    SettingsCard {
        visible: NightLight.toolAvailable
        ToggleRow {
            glyph: "󰖙"; label: "Follow sun position"
            checked: ShellSettings.nightLightAuto
            onToggled: ShellSettings.nightLightAuto = !ShellSettings.nightLightAuto
        }
        CollapsibleSection {
            expanded: !ShellSettings.nightLightAuto
            SliderRow {
                glyph: "󰖚"; label: "Color temperature"
                value: ShellSettings.nightLightTemp
                min: 1000; max: 6500; step: 100
                displayValue: ShellSettings.nightLightTemp + "K"
                onChanged: (v) => ShellSettings.nightLightTemp = v
            }
        }
        CollapsibleSection {
            expanded: ShellSettings.nightLightAuto
            HintText { text: "Temperature tracks sunset and sunrise at " + NightLight.locationLabel + "." }
        }
    }
    HintText {
        visible: !NightLight.toolAvailable
        text: "hyprsunset is not installed."
    }
}
