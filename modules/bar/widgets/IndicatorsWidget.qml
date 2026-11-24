import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Row {
    id: root
    property var screen: null
    property bool compact: ShellSettings.barCompact
    property bool barActive: true
    readonly property bool show: Indicators.items.length > 0
    readonly property bool layoutVisible: show
    visible: show

    Repeater {
        model: Indicators.items
        Pill {
            required property var modelData
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            height: root.height
            compact: root.compact
            barActive: root.barActive
            glyph: modelData.glyph
            text: modelData.label
            glyphColor: Theme.barSubtext
            textColor: Theme.barSubtext
            accessibleName: modelData.label.length > 0 ? modelData.name + ": " + modelData.label : modelData.name
        }
    }
}
