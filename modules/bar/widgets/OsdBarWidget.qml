import QtQuick
import "../../../config"
import "../../../services"

Item {
    id: root

    // Hands off to the floating pill while the overview conceals the bar.
    readonly property bool _shouldShow: ShellSettings.osdBarIntegrated && OsdBarState.showing && !OverviewState.active
    readonly property int  _barH: ShellSettings.barHeight

    readonly property real _slide: 5

    implicitHeight: parent ? parent.height : _barH
    implicitWidth:  _content.implicitWidth
    visible: _op > 0.001 || state === "visible"

    property real _op:    0
    property real _y:     _slide
    property real _scale: 0.97
    property real _bump:  1.0

    // State is set imperatively from OsdBarState.showing (synchronous, in the
    // same call-stack as the dismiss). A passive `active` binding batches the
    // flip, so a stray audio signal landing a frame after dismiss fired
    // exit→enter — the OSD fading out, sweeping back in, then leaving again.
    state: "hidden"
    function _sync(): void {
        state = _shouldShow ? "visible" : "hidden"
        if (!_shouldShow) _alertWidth = 0
    }
    Component.onCompleted: _sync()

    Connections {
        target: OsdBarState
        function onShowingChanged() { root._sync() }
        function onBumped() { if (root.state === "visible" && !_bumpAnim.running) _bumpAnim.restart() }
        // queued icon swap → stamp while visible (matches the pill); during a
        // rapid burst just snap, a queued stamp-on-stamp reads as thrashing
        function onNextIconChanged() {
            if (OsdBarState.nextIcon === OsdBarState.icon) return
            if (root.state !== "visible" || ShellSettings.reduceMotion || OsdBarState.rapid) {
                OsdBarState.icon = OsdBarState.nextIcon
                return
            }
            if (!_iconStamp.running) _iconStamp.start()
        }
    }
    // Mode flips (overview reveal/conceal, bar-OSD toggle) aren't audio-race
    // prone, so a plain resync covers them.
    Connections { target: OverviewState; function onActiveChanged() { root._sync() } }
    Connections { target: ShellSettings; function onOsdBarIntegratedChanged() { root._sync() } }

    states: [
        State { name: "hidden";  PropertyChanges { target: root; _op: 0;   _y: root._slide; _scale: 0.97 } },
        State { name: "visible"; PropertyChanges { target: root; _op: 1.0; _y: 0;           _scale: 1.0  } }
    ]
    transitions: [
        Transition {
            to: "visible"
            ParallelAnimation {
                NumberAnimation { target: root; property: "_op";    duration: Motion.ms(105); easing.type: Easing.OutCubic }
                NumberAnimation { target: root; property: "_y";     duration: Motion.ms(165); easing.type: Easing.OutQuart }
                NumberAnimation { target: root; property: "_scale"; duration: Motion.ms(150); easing.type: Easing.OutCubic }
            }
        },
        Transition {
            to: "hidden"
            // Opacity is the longest leg so the content stays drawn through the
            // whole slide/scale and never blink-cuts at the tail.
            ParallelAnimation {
                NumberAnimation { target: root; property: "_y";     duration: Motion.ms(100); easing.type: Easing.InCubic }
                NumberAnimation { target: root; property: "_scale"; duration: Motion.ms(100); easing.type: Easing.InCubic }
                NumberAnimation { target: root; property: "_op";    duration: Motion.ms(115); easing.type: Easing.InCubic }
            }
        }
    ]

    SequentialAnimation {
        id: _bumpAnim
        NumberAnimation { target: root; property: "_bump"; to: 1.018; duration: Motion.ms(65);  easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "_bump"; to: 1.0;   duration: Motion.ms(125); easing.type: Easing.OutCubic }
    }

    // Pins the value label width so the Row doesn't shift as the number changes.
    TextMetrics {
        id: _maxLabel
        font.family:    Settings.font
        font.pixelSize: Settings.fontSize
        font.weight:    Font.Medium
        text: "Muted"   // widest value text in hasBar context
    }

    // Alert (non-bar) labels vary in width; measure the live one and, during a
    // rapid burst, latch to the widest seen so the centered Row can't shift.
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
        scale:   root._scale
        transformOrigin: Item.Center
        // Bump rides its own transform so the tactile kick can't fight the
        // entrance/exit scale — multiplying both into `scale` made them jitter.
        transform: [
            // A transform stays in the scene graph; animating an anchor offset
            // forced the bar's anchor/layout pass to run every frame.
            Translate { y: root._y },
            Scale {
                origin.x: _content.width / 2; origin.y: _content.height / 2
                xScale: root._bump; yScale: root._bump
            }
        ]

        Text {
            id: _iconText
            anchors.verticalCenter: parent.verticalCenter
            width:               Settings.fontSize + 6   // fixed so the stamp's scale-to-0 doesn't collapse the Row
            horizontalAlignment: Text.AlignHCenter
            transformOrigin:     Item.Center
            text:           OsdBarState.icon
            color:          OsdBarState.hasBar ? Theme.text : OsdBarState.fillColor
            font.family:    Settings.font
            font.pixelSize: Settings.fontSize + 2
            renderType:     Text.NativeRendering
            Behavior on color { enabled: !ShellSettings.reduceMotion; ColorAnimation { duration: Motion.medium } }
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: OsdBarState.hasBar
            width:  visible ? 80 : 0
            height: 3
            radius: 1.5
            color:  Theme.withAlpha(Theme.text, 0.22)

            Rectangle {
                id: _fill
                width: {
                    const v = OsdBarState.clamped
                    return v <= 0 ? 0 : Math.max(parent.radius * 2, parent.width * v)
                }
                height: parent.height
                radius: parent.radius

                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop {
                        position: 0.0
                        color: OsdBarState.muted
                            ? Theme.withAlpha(Theme.subtext, 0.40)
                            : Theme.withAlpha(OsdBarState.barColor, 0.65)
                    }
                    GradientStop {
                        position: 1.0
                        color: OsdBarState.muted
                            ? Theme.withAlpha(Theme.subtext, 0.68)
                            : Theme.withAlpha(OsdBarState.barColor, 0.95)
                    }
                }

                Behavior on width {
                    enabled: !ShellSettings.reduceMotion && root.state === "visible" && !OsdBarState.rapid
                    NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic }
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text:           !OsdBarState.hasBar ? OsdBarState.label
                            : OsdBarState.muted ? "Muted"
                            : (Math.round(OsdBarState.clamped * 100) + "%")
            textFormat:     Text.PlainText
            // Fixed width keeps the Row centered as digits/labels change.
            width:          OsdBarState.hasBar
                                ? Math.ceil(_maxLabel.advanceWidth) + 2
                                : Math.max(implicitWidth, root._alertWidth)
            horizontalAlignment: OsdBarState.hasBar ? Text.AlignRight : Text.AlignLeft
            color:          OsdBarState.muted
                                ? Theme.withAlpha(Theme.subtext, 0.7)
                                : (OsdBarState.hasBar ? Theme.text : OsdBarState.fillColor)
            font.family:    Settings.font
            font.pixelSize: Settings.fontSize
            font.weight:    Font.Medium
            renderType:     Text.NativeRendering
            Behavior on color {
                enabled: !ShellSettings.reduceMotion
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
