import QtQuick
import "../../config"
import "../common"

// the body both rail drawers share: a titled list that glides to a row unless the pointer is holding it
Item {
    id: root

    required property string title
    property real contentHeight: 0
    // the title shares the page header's line: MenuWindow's 12px page inset, then a 32px header row
    readonly property int listTop: _title.y + _title.height + 8
    default property alias content: _content.data
    readonly property alias viewportHeight: _scroll.height
    signal viewportResized()

    // a range taller than the viewport keeps its top in view
    function reveal(top: real, bottom: real): void {
        const viewH = _scroll.height
        if (root.contentHeight <= viewH + 1) {
            _scroll.contentY = 0
            return
        }
        const margin = 7
        let target = _scroll.contentY
        if (bottom - top > viewH - margin * 2) target = top - margin
        else if (top - margin < target) target = top - margin
        else if (bottom + margin > target + viewH) target = bottom + margin - viewH
        _scroll.contentY = Math.max(0, Math.min(root.contentHeight - viewH, target))
    }

    ShellFlickable {
        id: _scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: _content.height
        interactive: contentHeight > height + 1

        onHeightChanged: root.viewportResized()

        MotionBehavior on contentY {
            gate: !_scroll.moving
            NumberAnimation {
                duration: Motion.normal
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.standard
            }
        }

        Item {
            id: _content
            width: root.width
            height: root.contentHeight

            Item {
                id: _title
                x: 8
                y: 12
                width: Math.max(1, parent.width - 16)
                height: Metrics.rowHeightFor(32)

                ShellText {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.title
                    color: Theme.withAlpha(Theme.text, 0.88)
                    font.pixelSize: Settings.fontSize
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
            }
        }
    }

    ListEdgeLines {
        anchors.fill: _scroll
        z: 2
        list: _scroll
        maxOpacity: 0.72
    }
}
