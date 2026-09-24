import QtQuick
import "../../../config"
import "../../common"

Item {
    id: root

    property string label: ""
    property string displayValue: ""
    property alias position: _slider.position
    property alias thumbColor: _slider.thumbColor
    property alias trackGradient: _slider.trackGradient
    property alias wraps: _slider.wraps
    property alias displayScale: _slider.displayScale
    property alias wheelKey: _slider.wheelKey

    signal picked(real position)

    width: parent ? parent.width : 0
    height: Metrics.rowHeightFor(48)

    // label column and value cell match SliderRow, so these read as the page's other sliders
    ShellText {
        id: _label
        anchors.left: parent.left
        anchors.leftMargin: 42
        anchors.top: parent.top
        anchors.topMargin: 6
        anchors.right: _value.left
        anchors.rightMargin: 10
        height: 20
        verticalAlignment: Text.AlignVCenter
        text: root.label
        elide: Text.ElideRight
        color: Theme.withAlpha(Theme.text, 0.85)
        font.pixelSize: Settings.fontSize
    }

    TextMetrics {
        id: _vm
        font.family: Settings.font
        font.pixelSize: Settings.fontLabel
        font.weight: Font.DemiBold
        text: "100%"
    }
    ShellText {
        id: _value
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: _label.verticalCenter
        width: Math.max(Math.ceil(_vm.advanceWidth), Math.ceil(implicitWidth))
        horizontalAlignment: Text.AlignRight
        text: root.displayValue
        color: _slider.dragging ? Theme.accent : Theme.withAlpha(Theme.text, 0.58)
        ColorFade on color {}
        font.pixelSize: Settings.fontLabel
        font.weight: Font.DemiBold
    }

    GradientSlider {
        id: _slider
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        accessibleName: root.label
        accessibleValueText: root.displayValue
        onPicked: p => root.picked(p)
    }
}
