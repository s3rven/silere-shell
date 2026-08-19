pragma ComponentBehavior: Bound

import QtQuick
import "../../../config"
import "../../common"

Item {
    id: root

    property var model: []
    property string textRole: ""
    property string trailingRole: ""
    // rows flagged by this role take the brighter trailing colour and the suffix
    property string emphasisRole: ""
    property string trailingSuffix: ""
    property int maxHeight: 240

    // entries scroll inside a capped list with no dividers, so they track the text
    // rather than the row grid every other settings row snaps to
    readonly property int _entryH: Math.max(22, Settings.capHeight + 8)

    width: parent ? parent.width : 0
    height: Math.min(_list.contentHeight, root.maxHeight)

    ShellListView {
        id: _list
        anchors.fill: parent
        interactive: contentHeight > height
        spacing: 0
        model: root.model

        delegate: Item {
            id: _entry
            required property var modelData
            readonly property bool emphasised: root.emphasisRole.length > 0
                && _entry.modelData[root.emphasisRole] === true

            width: _list.width
            height: root._entryH

            ShellText {
                anchors.left: parent.left
                anchors.leftMargin: 42
                anchors.right: _trailing.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: String(_entry.modelData[root.textRole] ?? "")
                elide: Text.ElideRight
                color: Theme.withAlpha(Theme.text, 0.80)
                font.pixelSize: Settings.fontLabel
            }

            ShellText {
                id: _trailing
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: String(_entry.modelData[root.trailingRole] ?? "")
                    + (_entry.emphasised ? "  " + root.trailingSuffix : "")
                color: Theme.withAlpha(Theme.subtext, _entry.emphasised ? 0.75 : 0.55)
                font.pixelSize: Settings.fontCaption
            }
        }
    }

    ListEdgeLines {
        anchors.fill: parent
        list: _list
    }
}
