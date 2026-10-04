import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Item {
    id: root

    readonly property bool _shouldShow: ShellSettings.osdEnabled
        && ShellSettings.osdBarIntegrated && OsdBarState.showing
        && !OsdBarState.barConcealed && !Idle.isIdle
    readonly property int  _barH: ShellSettings.barHeight

    readonly property real _slide: 5
    readonly property int _iconWidth: Settings.iconSize + 6
    readonly property real _labelWidth: OsdBarState.hasBar
        ? Math.ceil(Math.max(_maxLabel.advanceWidth, _maxValue.advanceWidth)) + 2
        : Math.min(Math.round(240 * ShellSettings.uiScale),
            Math.max(Math.ceil(_alertLabel.advanceWidth) + 2, _alertWidth))
    readonly property real _availableWidth: Math.max(0,
        width - _iconWidth - (OsdBarState.hasBar ? 16 : 8))

    implicitHeight: _barH
    // the desired width, not the rendered one: the bar grows to fit it while the content still fits mid-animation
    implicitWidth: _iconWidth + _labelWidth + (OsdBarState.hasBar ? 96 : 8)
    visible: _op > 0.001 || state === "visible"
    clip: width < implicitWidth
    Accessible.role: Accessible.StaticText
    Accessible.name: OsdBarState.label

    property real _op:   0
    property real _y:    _slide
    property real _bump: 1.0

    // set imperatively, inside the dismiss call-stack: a passive active binding batches the flip, so a late audio signal replays exit then enter
    state: "hidden"
    function _sync(): void {
        state = _shouldShow ? "visible" : "hidden"
        if (!_shouldShow) _alertWidth = 0
    }
    Component.onCompleted: _sync()
    on_ShouldShowChanged: _sync()

    Connections {
        target: OsdBarState
        function onRapidChanged() {
            if (!OsdBarState.rapid) root._refreshAlertWidth()
        }
        function onBumped() {
            if (!Idle.isIdle && root.state === "visible" && !_bumpAnim.running)
                _bumpAnim.restart()
        }
        function onNextIconChanged() {
            if (OsdBarState.nextIcon === OsdBarState.icon) return
            if (Idle.isIdle || root.state !== "visible"
                    || ShellSettings.reduceMotion || OsdBarState.rapid) {
                OsdBarState.icon = OsdBarState.nextIcon
                return
            }
            if (!_iconStamp.running) _iconStamp.start()
        }
    }
    Connections {
        target: Idle
        function onIsIdleChanged() {
            if (!Idle.isIdle) return
            _bumpAnim.retire()
            _iconStamp.stop()
            _iconText.scale = 1
            if (OsdBarState.nextIcon !== OsdBarState.icon)
                OsdBarState.icon = OsdBarState.nextIcon
        }
    }

    states: [
        State { name: "hidden";  PropertyChanges { root._op: 0; root._y: root._slide } },
        State { name: "visible"; PropertyChanges { root._op: 1.0; root._y: 0 } }
    ]
    transitions: [
        Transition {
            to: "visible"
            enabled: !Idle.isIdle && !ShellSettings.reduceMotion
            ParallelAnimation {
                NumberAnimation { target: root; property: "_op"; duration: Motion.ms(105); easing.type: Easing.OutCubic }
                NumberAnimation { target: root; property: "_y";  duration: Motion.ms(165); easing.type: Easing.OutQuart }
            }
        },
        Transition {
            to: "hidden"
            enabled: !Idle.isIdle && !ShellSettings.reduceMotion
            ParallelAnimation {
                NumberAnimation { target: root; property: "_y";  duration: Motion.ms(100); easing.type: Easing.InCubic }
                NumberAnimation { target: root; property: "_op"; duration: Motion.ms(115); easing.type: Easing.InCubic }
            }
        }
    ]

    BumpAnimation {
        id: _bumpAnim
        target: root
        targetProperty: "_bump"
    }

    TextMetrics {
        id: _maxLabel
        font.family:    Settings.font
        font.pixelSize: Settings.fontSize
        font.weight:    Font.Medium
        text: "Muted"
    }

    TextMetrics {
        id: _maxValue
        font: _maxLabel.font
        text: "100%"
    }

    TextMetrics {
        id: _alertLabel
        font.family:    Settings.font
        font.pixelSize: Settings.fontSize
        font.weight:    Font.Medium
        text: !OsdBarState.hasBar ? OsdBarState.label : ""
        onAdvanceWidthChanged: root._refreshAlertWidth()
    }
    property real _alertWidth: 0
    function _refreshAlertWidth(): void {
        const w = Math.ceil(_alertLabel.advanceWidth) + 2
        _alertWidth = OsdBarState.rapid ? Math.max(_alertWidth, w) : w
    }

    Row {
        id: _content
        anchors.centerIn: parent
        spacing: 8
        opacity: root._op
        transform: [
            Translate { y: root._y },
            Scale {
                origin.x: _content.width / 2; origin.y: _content.height / 2
                xScale: root._bump; yScale: root._bump
            }
        ]

        ShellText {
            id: _iconText
            anchors.verticalCenter: parent.verticalCenter
            width:               Math.min(root._iconWidth, root.width)
            horizontalAlignment: Text.AlignHCenter
            transformOrigin:     Item.Center
            text:           OsdBarState.icon
            color:          OsdBarState.hasBar ? Theme.text : OsdBarState.fillColor
            font.pixelSize: Settings.iconSize + 2
            MotionBehavior on color {
                ColorAnimation { duration: Motion.medium }
            }
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: OsdBarState.hasBar
            width: visible ? Math.min(80,
                Math.max(0, root._availableWidth - root._labelWidth)) : 0
            height: 3
            radius: 1.5
            color:  Theme.withAlpha(Theme.text, 0.22)

            Rectangle {
                id: _fill
                width: {
                    const v = OsdBarState.clamped
                    return v <= 0 ? 0 : Math.min(parent.width,
                        Math.max(parent.radius * 2, parent.width * v))
                }
                height: parent.height
                radius: parent.radius
                color: OsdBarState.muted
                    ? Theme.withAlpha(Theme.subtext, 0.58)
                    : Theme.withAlpha(OsdBarState.fillColor, 0.88)

                MotionBehavior on width {
                    gate: root.state === "visible" && !OsdBarState.rapid
                    NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic }
                }
            }
        }

        ShellText {
            anchors.verticalCenter: parent.verticalCenter
            text:           !OsdBarState.hasBar ? OsdBarState.label
                            : OsdBarState.muted ? "Muted"
                            : (Math.round(OsdBarState.clamped * 100) + "%")
            width: Math.min(root._labelWidth, root._availableWidth)
            elide: Text.ElideRight
            horizontalAlignment: OsdBarState.hasBar ? Text.AlignRight : Text.AlignLeft
            color:          OsdBarState.muted
                                ? Theme.withAlpha(Theme.subtext, 0.7)
                                : (OsdBarState.hasBar ? Theme.text : OsdBarState.fillColor)
            font.pixelSize: Settings.fontSize
            font.weight:    Font.Medium
            MotionBehavior on color {
                ColorAnimation { duration: Motion.medium }
            }
        }
    }

    SequentialAnimation {
        id: _iconStamp
        NumberAnimation { target: _iconText; property: "scale"; to: 0.72; duration: Motion.ms(55); easing.type: Easing.InCubic }
        ScriptAction    { script: OsdBarState.icon = OsdBarState.nextIcon }
        NumberAnimation { target: _iconText; property: "scale"; from: 0.72; to: 1.0; duration: Motion.ms(125); easing.type: Easing.OutQuart }
        onFinished: { if (OsdBarState.nextIcon !== OsdBarState.icon) _iconStamp.start() }
    }
}
