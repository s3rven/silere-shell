pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import "../../config"
import "../../services"
import "../common"

Item {
    id: root

    readonly property int _navTop:  42
    readonly property int _rowH:    Metrics.rowHeightFor(28)
    readonly property int _rowGap:   1
    readonly property bool compact: width < 132

    signal filterPicked()

    implicitHeight: root._navTop + _rowColumn.implicitHeight + 10

    property var _names: [""]

    function _syncNames(apps): void {
        const names = [""]
        for (let i = 0; i < apps.length; i++) names.push(apps[i].appName)
        if (names.length === root._names.length
                && names.every((name, index) => name === root._names[index])) return
        root._names = names
    }

    Component.onCompleted: root._syncNames(Notifications.historyApps)
    Connections {
        target: Notifications
        function onHistoryAppsChanged() { root._syncNames(Notifications.historyApps) }
    }

    function _appFor(name: string): var {
        const apps = Notifications.historyApps
        for (let i = 0; i < apps.length; i++)
            if (apps[i].appName === name) return apps[i]
        return null
    }
    function _labelFor(name: string): string {
        return name.length === 0 ? "All" : name
    }
    function _countFor(name: string): int {
        if (name.length === 0) return Notifications.historyCount
        const app = root._appFor(name)
        return app ? app.count : 0
    }

    // an app whose last notification was cleared takes the filter down with it
    on_NamesChanged: {
        root._queueReveal()
        const want = MenuState.recentFilter
        if (want.length === 0) return
        const names = root._names
        for (let i = 0; i < names.length; i++)
            if (names[i] === want) return
        MenuState.setRecentFilter("")
    }

    function _activate(name: string): void {
        MenuState.setRecentFilter(name)
        root.filterPicked()
    }

    function _rowY(index: real): real {
        return root._navTop + index * (root._rowH + root._rowGap)
    }
    readonly property int _activeIndex: root._names.indexOf(MenuState.recentFilter)

    function _revealActive(): void {
        if (!MenuState.recentActive) return
        const index = Math.max(0, root._activeIndex)
        const contentH = root.implicitHeight
        const viewH = _navScroll.height
        if (contentH <= viewH + 1) {
            _navScroll.contentY = 0
            return
        }
        const margin = 7
        const top = root._rowY(index)
        const bottom = top + root._rowH
        let target = _navScroll.contentY
        if (top - margin < target) target = top - margin
        else if (bottom + margin > target + viewH) target = bottom + margin - viewH
        _navScroll.contentY = Math.max(0, Math.min(Math.max(0, contentH - viewH), target))
    }

    // the outer panel keeps resizing the viewport for the whole open, so height
    // notifications arrive every frame; reveal once they stop
    Timer {
        id: _revealSettle
        interval: ShellSettings.reduceMotion ? 0 : 50
        onTriggered: root._revealActive()
    }
    function _queueReveal(): void { _revealSettle.restart() }

    Connections {
        target: MenuState
        function onRecentActiveChanged() {
            if (MenuState.recentActive) root._queueReveal()
            else _revealSettle.stop()
        }
        function onRecentFilterChanged() { root._queueReveal() }
    }

    ShellFlickable {
        id: _navScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: _content.height
        interactive: contentHeight > height + 1

        onHeightChanged: if (MenuState.recentActive) root._queueReveal()

        MotionBehavior on contentY {
            gate: !_navScroll.moving
            NumberAnimation {
                duration: Motion.normal
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.standard
            }
        }

        Item {
            id: _content
            width: root.width
            height: root.implicitHeight

            Item {
                x: 8
                y: 6
                width: Math.max(1, parent.width - 16)
                height: 28

                ShellText {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Apps"
                    color: Theme.withAlpha(Theme.text, 0.88)
                    font.pixelSize: Settings.fontSize
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
            }

            RailSelection {
                id: _selection
                x: _rowColumn.x
                width: _rowColumn.width
                index: root._activeIndex
                rowHeight: root._rowH
                rowTop: root._rowY(_selection.slot)
            }

            Column {
                id: _rowColumn
                x: 6
                y: root._navTop
                width: Math.max(1, parent.width - 12)
                spacing: root._rowGap

                Repeater {
                    model: root._names

                    delegate: Rectangle {
                        id: _row

                        required property string modelData

                        readonly property bool isAll: _row.modelData.length === 0
                        readonly property bool active:
                            MenuState.recentFilter === _row.modelData
                        readonly property string label: root._labelFor(_row.modelData)
                        readonly property int count: root._countFor(_row.modelData)
                        // strings, not the app row: the row object is rebuilt on every
                        // revision, and the icon must only re-resolve when it truly changes
                        readonly property string appIcon:
                            _row.isAll ? "" : (root._appFor(_row.modelData)?.appIcon ?? "")
                        readonly property string desktopEntry:
                            _row.isAll ? "" : (root._appFor(_row.modelData)?.desktopEntry ?? "")

                        width: _rowColumn.width
                        height: root._rowH
                        radius: Theme.radiusInline
                        antialiasing: true
                        // the gliding selection underneath carries the resting fill
                        color: _row.active
                            ? Theme.withAlpha(Theme.accent,
                                _rowTap.pressed ? 0.09 : _rowHover.hovered ? 0.04 : 0)
                            : _rowTap.pressed
                                ? Theme.withAlpha(Theme.accent, 0.12)
                            : _rowHover.hovered
                                ? Theme.withAlpha(Theme.text, 0.042)
                                : "transparent"

                        Accessible.role: Accessible.PageTab
                        Accessible.name: _row.label + ", " + _row.count
                            + (_row.count === 1 ? " notification" : " notifications")
                        Accessible.focusable: true
                        Accessible.selected: _row.active
                        Accessible.onPressAction: root._activate(_row.modelData)

                        HoverHandler {
                            id: _rowHover
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            id: _rowTap
                            onTapped: root._activate(_row.modelData)
                        }

                        ColorFade on color {}

                        Item {
                            id: _iconSlot
                            visible: !root.compact
                            anchors.left: parent.left
                            anchors.leftMargin: 9
                            anchors.verticalCenter: parent.verticalCenter
                            width: Metrics.iconCellFor(Settings.fontLabel)
                            height: width

                            ShellText {
                                anchors.centerIn: parent
                                visible: _row.isAll || _rowIcon.status !== Image.Ready
                                text: _row.isAll ? "󰂚"
                                    : SafeText.initial(_row.label, "N")
                                color: _row.active
                                    ? Theme.mix(Theme.accent, Theme.text, 0.10)
                                    : Theme.withAlpha(Theme.subtext,
                                        _rowHover.hovered ? 0.92 : 0.76)
                                font.pixelSize: _row.isAll
                                    ? Settings.fontLabel : Settings.fontMicro
                                font.weight: _row.isAll ? Font.Normal : Font.DemiBold
                                ColorFade on color {}
                            }

                            IconImage {
                                id: _rowIcon
                                anchors.centerIn: parent
                                width: 16
                                height: 16
                                visible: !_row.isAll && status === Image.Ready
                                implicitSize: 16
                                asynchronous: true
                                property bool _fellBack: false
                                readonly property string _primary: {
                                    Notifications.entriesTick
                                    return _row.isAll ? "" : Notifications.appIconSource(
                                        _row.appIcon, _row.desktopEntry, _row.label)
                                }
                                readonly property string _fallback: {
                                    Notifications.entriesTick
                                    return _row.isAll ? "" : Notifications.entryIconSource(
                                        _row.desktopEntry, _row.label)
                                }
                                on_PrimaryChanged: _fellBack = false
                                source: _fellBack ? _fallback : _primary
                                onStatusChanged: if (status === Image.Error
                                        && _rowIcon._fallback.length > 0
                                        && _rowIcon._fallback !== _rowIcon._primary)
                                    _fellBack = true
                            }
                        }

                        ShellText {
                            id: _rowCount
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(_row.count)
                            color: Theme.withAlpha(Theme.subtext, _row.active ? 0.92 : 0.76)
                            font.pixelSize: Settings.fontMicro
                            font.weight: Font.DemiBold
                            ColorFade on color {}
                        }

                        ShellText {
                            anchors.left: _iconSlot.visible ? _iconSlot.right : parent.left
                            anchors.leftMargin: _iconSlot.visible ? 7 : 12
                            anchors.right: _rowCount.left
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            text: _row.label
                            color: _row.active
                                ? Theme.withAlpha(Theme.text, 0.96)
                                : Theme.withAlpha(Theme.text,
                                    _rowHover.hovered ? 0.96 : 0.84)
                            font.pixelSize: Settings.fontLabel
                            font.weight: _row.active ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                            ColorFade on color {}
                        }
                    }
                }
            }
        }
    }

    ListEdgeLines {
        anchors.fill: _navScroll
        z: 2
        list: _navScroll
        maxOpacity: 0.72
    }
}
