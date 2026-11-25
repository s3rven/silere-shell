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

    function unfold(): void {
        for (const pill of children) if (typeof pill.unfold === "function") pill.unfold()
    }

    Repeater {
        // names only: any change to an array model rebuilds every delegate, so a script updating its text each second
        // rebuilt every pill
        model: Indicators.items.map(i => i.name)
        Pill {
            required property string modelData
            readonly property var mark: Indicators.items.find(i => i.name === modelData) ?? { glyph: "", label: "" }
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            height: root.height
            compact: root.compact
            barActive: root.barActive
            glyph: mark.glyph
            text: mark.label
            glyphColor: Theme.barSubtext
            textColor: Theme.barSubtext
            accessibleName: mark.label.length > 0 ? modelData + ": " + mark.label : modelData
        }
    }
}
