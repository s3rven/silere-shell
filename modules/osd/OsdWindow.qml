pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland._WlrLayerShell
import "../../config"
import "../../services"
import "../common"

PanelWindow {
    id: osd

    required property ShellScreen targetScreen

    screen:         targetScreen
    color:          "transparent"
    exclusiveZone:  -1
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "silere-osd"

    implicitHeight: 150

    readonly property bool _bottom: ShellSettings.barPosition === "bottom"
    readonly property int _barInset: ShellSettings.barFloating ? 4 : 0
    readonly property int _edgeY: _barInset + ShellSettings.barHeight + 8
    readonly property bool _active: !ShellSettings.osdBarIntegrated || OsdBarState.barConcealed

    anchors {
        top:    !osd._bottom
        bottom: osd._bottom
        left:   true
        right:  true
    }

    margins.top:    osd._bottom ? 0 : osd._edgeY
    margins.bottom: osd._bottom ? osd._edgeY : 0
    mask: Region {}

    visible: osd._active && OsdBarState.activeCount > 0

    Column {
        id: stack
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 6

        states: [
            State {
                name: "top"
                when: !osd._bottom
                AnchorChanges { target: stack; anchors.top: parent.top; anchors.bottom: undefined }
                PropertyChanges { stack.anchors.topMargin: 6; stack.anchors.bottomMargin: 0 }
            },
            State {
                name: "bottom"
                when: osd._bottom
                AnchorChanges { target: stack; anchors.top: undefined; anchors.bottom: parent.bottom }
                PropertyChanges { stack.anchors.topMargin: 0; stack.anchors.bottomMargin: 6 }
            }
        ]

        Repeater {
            // integrated mode hides this window — detach the model too so delegates stop measuring/laying out/animating behind the bar OSD
            model: osd._active ? OsdBarState.entries : null

            delegate: Item {
                id: card

                required property string kind
                required property string icon
                required property string label
                required property bool muted
                required property bool hasBar
                required property real clamped
                required property bool closing
                required property int serial
                required property var fillColor
                required property var barColor

                readonly property int pillH: ShellSettings.osdMatchBar ? Math.max(28, ShellSettings.barHeight) : 34
                readonly property int chromeW: hasBar ? 216 : 70
                readonly property int pillW: Math.max(268, Math.min(520, chromeW + Math.ceil(_labelMetrics.advanceWidth) + 2))
                // follow the bar's corner choice when matching (holds even on a non-floating bar), else panel radius
                readonly property real pillRadius: ShellSettings.osdMatchBar
                    ? (ShellSettings.barCornerStyle === "flat" ? 0 : Math.min(ShellSettings.barRadius, pillH / 2))
                    : Math.min(Theme.radiusPanel, pillH / 2)
                readonly property real _hiddenSlide: osd._bottom ? 7 : -7

                property bool _ready: false
                property real _op: 0
                property real _slide: _hiddenSlide
                property real _bump: 1.0

                width: pillW
                height: 0
                visible: osd._active && (_ready || _op > 0.001 || height > 0.5)
                z: serial

                Component.onCompleted: _ready = true

                TextMetrics {
                    id: _labelMetrics
                    font.family:    Settings.font
                    font.pixelSize: Settings.fontSize
                    text: card.label
                }

                Connections {
                    target: OsdBarState
                    function onEntryBumped(kind) {
                        if (kind === card.kind && !_bumpAnim.running) _bumpAnim.restart()
                    }
                }

                states: [
                    State {
                        name: "hidden"
                        when: !card._ready || card.closing
                        PropertyChanges { card.height: 0; card._op: 0; card._slide: card._hiddenSlide }
                    },
                    State {
                        name: "visible"
                        when: card._ready && !card.closing
                        PropertyChanges { card.height: card.pillH; card._op: 1.0; card._slide: 0 }
                    }
                ]

                transitions: [
                    Transition {
                        to: "visible"
                        ParallelAnimation {
                            NumberAnimation { target: card; property: "height"; duration: Motion.ms(150); easing.type: Easing.OutCubic }
                            NumberAnimation { target: card; property: "_op";    duration: Motion.ms(105); easing.type: Easing.OutCubic }
                            NumberAnimation { target: card; property: "_slide"; duration: Motion.ms(165); easing.type: Easing.OutQuart }
                        }
                    },
                    Transition {
                        to: "hidden"
                        ParallelAnimation {
                            NumberAnimation { target: card; property: "_slide"; duration: Motion.ms(105); easing.type: Easing.InCubic }
                            NumberAnimation { target: card; property: "_op";    duration: Motion.ms(115); easing.type: Easing.InCubic }
                            NumberAnimation { target: card; property: "height"; duration: Motion.ms(165); easing.type: Easing.InCubic }
                        }
                    }
                ]

                SequentialAnimation {
                    id: _bumpAnim
                    NumberAnimation { target: card; property: "_bump"; to: 1.018; duration: Motion.ms(70);  easing.type: Easing.OutQuad }
                    NumberAnimation { target: card; property: "_bump"; to: 1.0;   duration: Motion.ms(130); easing.type: Easing.OutCubic }
                }

                Behavior on width {
                    enabled: !ShellSettings.reduceMotion
                    NumberAnimation { duration: Motion.ms(80); easing.type: Easing.OutCubic }
                }

                Item {
                    id: pillWrap
                    width: card.pillW
                    height: card.pillH
                    anchors.horizontalCenter: parent.horizontalCenter
                    opacity: card._op
                    transform: [
                        Translate { y: card._slide },
                        Scale {
                            origin.x: pillWrap.width / 2
                            origin.y: pillWrap.height / 2
                            xScale: card._bump
                            yScale: card._bump
                        }
                    ]

                    Loader {
                        active: ShellSettings.barFloating && ShellSettings.barShadow
                        anchors.fill: parent
                        sourceComponent: FloatingShadow {
                            radius: card.pillRadius
                            atBottom: osd._bottom
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: card.pillRadius
                        antialiasing: true
                        color: card.hasBar ? Theme.panel : Theme.surface
                        border.width: 1
                        border.color: !card.hasBar
                            ? Theme.withAlpha(card.fillColor, 0.32)
                            : Theme.outline
                        Behavior on border.color { ColorAnimation { duration: Motion.medium } }

                        Row {
                            anchors.centerIn: parent
                            spacing: 10

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width:               20
                                horizontalAlignment: Text.AlignHCenter
                                text:           card.icon
                                color:          card.hasBar ? Theme.text : card.fillColor
                                font.family:    Settings.font
                                font.pixelSize: Settings.fontSize + 4
                                renderType:     Text.NativeRendering
                                Behavior on color { enabled: !ShellSettings.reduceMotion; ColorAnimation { duration: Motion.medium } }
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: card.hasBar
                                width:  136
                                height: 6
                                radius: 3
                                color:  Theme.withAlpha(Theme.text, 0.22)

                                Rectangle {
                                    id: _fill
                                    width: {
                                        const v = card.clamped
                                        return v <= 0 ? 0 : Math.max(parent.radius * 2, parent.width * v)
                                    }
                                    height: parent.height
                                    radius: parent.radius
                                    clip: true

                                    property real _shimmerPhase: 0

                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop {
                                            position: 0.0
                                            color: card.muted
                                                ? Theme.withAlpha(Theme.subtext, 0.40)
                                                : Theme.withAlpha(card.barColor, 0.65)
                                        }
                                        GradientStop {
                                            position: 1.0
                                            color: card.muted
                                                ? Theme.withAlpha(Theme.subtext, 0.68)
                                                : Theme.withAlpha(card.barColor, 0.95)
                                        }
                                    }

                                    Rectangle {
                                        visible: !card.muted && !ShellSettings.reduceMotion
                                        x: -40 + _fill._shimmerPhase * (_fill.width + 40)
                                        width: 40
                                        height: parent.height
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0.0; color: "transparent" }
                                            GradientStop { position: 0.5; color: Theme.withAlpha(Theme.text, 0.38) }
                                            GradientStop { position: 1.0; color: "transparent" }
                                        }
                                    }

                                    SequentialAnimation on _shimmerPhase {
                                        running: osd._active && !card.closing && card.kind === "volume"
                                            && ShellSettings.osdVolumeTint && !ShellSettings.reduceMotion
                                        // setPaused() warns unless the animation is running
                                        paused: running && card.muted
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 0; to: 1; duration: Motion.ms(900); easing.type: Easing.Linear }
                                        PauseAnimation  { duration: Motion.ms(800) }
                                    }

                                    Behavior on width {
                                        enabled: !ShellSettings.reduceMotion && !card.closing && !OsdBarState.rapid
                                        NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic }
                                    }
                                }
                            }

                            TextMetrics {
                                id: tm
                                font.family:    Settings.font
                                font.pixelSize: Settings.fontSize
                                text: "Muted"
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(Math.ceil(tm.advanceWidth),
                                    Math.min(Math.ceil(_labelMetrics.advanceWidth), card.pillW - card.chromeW)) + 2
                                horizontalAlignment: Text.AlignRight
                                elide:          Text.ElideRight
                                text:           card.label
                                textFormat:     Text.PlainText
                                color:          card.muted
                                    ? Theme.withAlpha(Theme.subtext, 0.7)
                                    : (card.hasBar ? Theme.text : card.fillColor)
                                font.family:    Settings.font
                                font.pixelSize: Settings.fontSize
                                renderType:     Text.NativeRendering

                                Behavior on color {
                                    enabled: !ShellSettings.reduceMotion
                                    ColorAnimation { duration: Motion.medium }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
