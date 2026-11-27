pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
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

    implicitHeight: Math.max(150, Math.ceil((stack.implicitHeight + 24) / 64) * 64)
    // cap the surface for both the output and the cost of recompositing it on every animated frame
    implicitWidth: Math.max(1, Math.min(576, 8 * Math.floor((osd.targetScreen?.width ?? 576) / 8)))
    // leave room for the shadow; a multiple of eight centres the pill on the four-pixel grid
    readonly property int _pillLimit: Math.max(1, 8 * Math.floor((implicitWidth - 32) / 8))

    readonly property bool _bottom: Metrics.barAtBottom
    readonly property real _edgeY: Metrics.popupClearanceOn(osd.targetScreen, 2)
    readonly property bool _active: !ShellSettings.osdBarIntegrated || OsdBarState.barConcealed

    anchors {
        top:    !osd._bottom
        bottom: osd._bottom
    }

    // at 1.25 only multiples of 4 land on whole output pixels, so every offset down to the pill stays on that grid
    margins.top:    osd._bottom ? 0 : Metrics.snap4Up(osd._edgeY)
    margins.bottom: osd._bottom ? Metrics.snap4Up(osd._edgeY) : 0
    mask: Region {}
    BackgroundEffect.blurRegion: Region { regions: osd._blurShapes }
    property var _blurShapes: []

    visible: osd._active && OsdBarState.activeCount > 0
    // loaded for a key press, the window draws only once the compositor has configured it; a pill that rose before
    // that first frame showed already 70% faded in. Shown again after a hide, it waits once more
    property bool presented: false
    onVisibleChanged: if (!visible) osd.presented = false
    Connections {
        target: osd.presented ? null : stack.Window.window
        function onFrameSwapped() { osd.presented = true }
    }

    Column {
        id: stack
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 8

        states: [
            State {
                name: "top"
                when: !osd._bottom
                AnchorChanges { target: stack; anchors.top: parent.top; anchors.bottom: undefined }
                PropertyChanges { stack.anchors.topMargin: 8; stack.anchors.bottomMargin: 0 }
            },
            State {
                name: "bottom"
                when: osd._bottom
                AnchorChanges { target: stack; anchors.top: undefined; anchors.bottom: parent.bottom }
                PropertyChanges { stack.anchors.topMargin: 0; stack.anchors.bottomMargin: 8 }
            }
        ]

        Repeater {
            model: osd._active ? OsdBarState.entries : null
            onItemAdded: (index, item) => osd._blurShapes = osd._blurShapes.concat([item.blurShape])
            onItemRemoved: (index, item) => osd._blurShapes = osd._blurShapes.filter(s => s !== item.blurShape)

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

                readonly property int glyphW: Math.max(20, Metrics.iconCellFor(Settings.fontSize + 4))
                readonly property int _preferredTrackW: Metrics.snap4(136 * Metrics.typeGain)
                // the wider readout in both states: a slot that followed mute recentred the glyph and track on every press
                readonly property real _levelW: Math.max(_valueMetrics.advanceWidth, _mutedMetrics.advanceWidth)
                readonly property int _minimumLabelW: Math.ceil(_levelW) + 2
                readonly property int _labelW: Metrics.snap4Up(Math.max(_minimumLabelW, _levelPrefix.length > 0
                    ? Math.ceil(_prefixMetrics.advanceWidth + _levelW) + 2 : Math.ceil(_labelMetrics.advanceWidth) + 2))
                readonly property int pillH: ShellSettings.osdMatchBar ? Math.max(28, Metrics.barHeight) : Metrics.rowHeightFor(36)
                readonly property int _preferredChromeW: glyphW + (hasBar ? _preferredTrackW + 20 : 10) + 40
                readonly property int pillW: Math.min(osd._pillLimit, 2 * Metrics.snap4(
                    Math.max(Math.round(268 * Metrics.typeGain), Math.min(520, _preferredChromeW + _labelW)) / 2))
                readonly property int _sideSpace: Math.min(40, Math.floor(pillW / 5))
                readonly property int _levelRoom: Math.max(0, pillW - _sideSpace - glyphW - 20)
                // give the readout most of the remaining room when its full device label cannot fit
                readonly property int _labelShare: Math.max(_minimumLabelW, Math.floor(_levelRoom * 0.6))
                readonly property int trackW: hasBar ? Math.min(_preferredTrackW,
                    Math.max(0, Metrics.snap4Down(_levelRoom - Math.min(_labelW, _labelShare)))) : 0
                readonly property int chromeW: glyphW + (trackW > 0 ? trackW + 20 : 10) + _sideSpace
                readonly property int _labelFit: Math.min(_labelW, Math.max(0, pillW - chromeW))
                readonly property string _levelPrefix: hasBar ? OsdBarState.levelPrefix(label) : ""
                readonly property string _levelSuffix: _levelPrefix.length > 0 ? label.slice(_levelPrefix.length) : ""
                // shorten the device name while retaining the whole level or mute state
                readonly property string _displayLabel: {
                    if (_levelSuffix.length === 0 || _labelFit >= _labelMetrics.advanceWidth + 2) return label
                    const prefix = _contextMetrics.elidedText
                    return prefix.length > 0 && prefix !== "…" ? prefix + _suffixMetrics.text : _levelSuffix
                }
                readonly property real pillRadius: ShellSettings.osdMatchBar
                    ? Math.min(ShellSettings.barRadius, pillH / 2)
                    : Math.min(Theme.surfaceRadius, pillH / 2)
                readonly property real _hiddenSlide: osd._bottom ? 7 : -7
                readonly property Item blurItem: Theme.frosted
                    && _osdPillFill.color.a < 1 && card._op > 0 ? _blurBox : null
                readonly property Region blurShape: Region {
                    item: card.blurItem
                    radius: Math.round(card.pillRadius)
                }
                // a region follows only its own item, and the pill moves by transform in a moving column
                Item {
                    id: _blurBox
                    parent: stack.parent
                    x: stack.x + card.x + pillWrap.x
                    y: stack.y + card.y + pillWrap.y + card._slide
                    width: pillWrap.width
                    height: pillWrap.height
                }

                property bool _built: false
                readonly property bool _ready: _built && osd.presented
                property real _op: 0
                property real _slide: _hiddenSlide
                property real _bump: 1.0

                onClosingChanged: {
                    if (!closing) return
                    _bumpAnim.retire()
                }

                width: pillW
                // a Column only stacks: unset, a narrower pill hangs off the wider one's left edge
                x: OsdBarState.pillX(stack.width, width)
                height: 0
                visible: osd._active && (_ready || _op > 0.001 || height > 0.5)
                z: serial
                Accessible.role: Accessible.StaticText
                Accessible.name: card.label

                Component.onCompleted: _built = true

                TextMetrics {
                    id: _labelMetrics
                    font.family:    Settings.font
                    font.pixelSize: Settings.fontSize
                    text: card.label
                }
                TextMetrics {
                    id: _valueMetrics
                    font: _labelMetrics.font
                    text: "100%"
                }
                TextMetrics {
                    id: _mutedMetrics
                    font: _labelMetrics.font
                    text: "Muted"
                }
                TextMetrics {
                    id: _suffixMetrics
                    font: _labelMetrics.font
                    text: card._levelSuffix.length > 0 ? " · " + card._levelSuffix : ""
                }
                TextMetrics {
                    id: _prefixMetrics
                    font: _labelMetrics.font
                    text: card._levelPrefix
                }
                TextMetrics {
                    id: _contextMetrics
                    font: _labelMetrics.font
                    text: card._levelPrefix.slice(0, -3)
                    elide: Text.ElideRight
                    elideWidth: Math.max(0, card._labelFit - _suffixMetrics.advanceWidth - 2)
                }

                Connections {
                    target: OsdBarState
                    function onEntryBumped(kind) {
                        if (kind === card.kind && !_bumpAnim.running) _bumpAnim.restart()
                    }
                }

                Connections {
                    target: Idle
                    function onIsIdleChanged() { if (Idle.isIdle) _bumpAnim.retire() }
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
                        enabled: !Idle.isIdle
                        ParallelAnimation {
                            NumberAnimation { target: card; property: "height"; duration: Motion.ms(150); easing.type: Easing.OutCubic }
                            NumberAnimation { target: card; property: "_op";    duration: Motion.ms(105); easing.type: Easing.OutCubic }
                            NumberAnimation { target: card; property: "_slide"; duration: Motion.ms(165); easing.type: Easing.OutQuart }
                        }
                    },
                    Transition {
                        to: "hidden"
                        enabled: !Idle.isIdle
                        ParallelAnimation {
                            NumberAnimation { target: card; property: "_slide"; duration: Motion.ms(105); easing.type: Easing.InCubic }
                            // soft at both ends: on the accelerating curve the pill went from 42% to nothing in its last
                            // frame, a blink rather than a fade, and a decelerating one dropped half of it in the first
                            NumberAnimation { target: card; property: "_op";    duration: Motion.ms(115); easing.type: Easing.InOutQuad }
                            NumberAnimation { target: card; property: "height"; duration: Motion.ms(165); easing.type: Easing.InCubic }
                        }
                    }
                ]

                BumpAnimation {
                    id: _bumpAnim
                    target: card
                    targetProperty: "_bump"
                }

                MotionBehavior on width {
                    NumberAnimation { duration: Motion.ms(80); easing.type: Easing.OutCubic }
                }

                Item {
                    id: pillWrap
                    // the card's glide: bound to pillW, a new device label snapped the pill 36 px wider while the
                    // card's animation moved nothing drawn. The readout sits 40 px inside each edge, so it never overhangs
                    width: card.width
                    height: card.pillH
                    anchors.horizontalCenter: parent.horizontalCenter
                    opacity: card._op
                    transform: Translate { y: card._slide }

                    Loader {
                        active: ShellSettings.barShadow
                        anchors.fill: parent
                        sourceComponent: FloatingShadow {
                            hollow: _osdPillFill.color.a < 0.999
                            radius: card.pillRadius
                            atBottom: osd._bottom
                        }
                    }

                    Rectangle {
                        id: _osdPillFill
                        anchors.fill: parent
                        radius: card.pillRadius
                        antialiasing: true
                        // every OSD follows the same opacity and blur policy as the popups
                        color: Theme.popup

                        readonly property color _outlineColor: !card.hasBar
                            ? Theme.withAlpha(card.fillColor, 0.55)
                            : Theme.outline

                        OutlineBorder {
                            radius: _osdPillFill.radius
                            // two device pixels at 1.25: one reads as a broken hairline over whatever is behind a floating card
                            outlineWidth: 1.5
                            outlineColor: _osdPillFill._outlineColor
                            ColorFade on outlineColor { duration: Motion.medium }
                        }

                        Row {
                            id: _content
                            anchors.centerIn: parent
                            spacing: 10
                            // the bump rides the content: a scaled frame takes its outline off the pixel grid and past its blur region
                            transform: Scale {
                                origin.x: _content.width / 2
                                origin.y: _content.height / 2
                                xScale: card._bump
                                yScale: card._bump
                            }

                            ShellText {
                                anchors.verticalCenter: parent.verticalCenter
                                width:               card.glyphW
                                horizontalAlignment: Text.AlignHCenter
                                text:           card.icon
                                color:          card.hasBar ? Theme.text : card.fillColor
                                font.pixelSize: Settings.fontSize + 4
                                ColorFade on color { duration: Motion.medium }
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: card.trackW > 0
                                width:  card.trackW
                                height: 6
                                radius: Theme.capsuleRadius(height)
                                color:  Theme.menuTrack

                                Rectangle {
                                    id: _fill
                                    readonly property real _target: {
                                        const v = card.clamped
                                        return v <= 0 ? 0 : Math.min(parent.width,
                                            Math.max(parent.radius * 2, parent.width * v))
                                    }
                                    // a glide follows held keys smoothly; a restarted ease kicked on every step
                                    width: Math.min(parent.width, _fillGlide.value)
                                    readonly property SmoothGlide _fillGlide: SmoothGlide {
                                        target: _fill._target; duration: Motion.normal; gate: !card.closing
                                    }
                                    height: parent.height
                                    radius: parent.radius
                                    color: card.muted
                                        ? Theme.withAlpha(Theme.subtext, 0.58)
                                        : Theme.withAlpha(card.fillColor, 0.88)
                                    // muting greys the level with its glyph and label, which fade
                                    ColorFade on color { duration: Motion.medium }
                                }
                            }

                            ShellText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: card._labelFit
                                horizontalAlignment: Text.AlignRight
                                // an output switch reads "name · 45%": a long device name cut the level off its end
                                elide:          Text.ElideMiddle
                                text:           card._displayLabel
                                // the glyph and rim carry the alert; a coloured readout only costs contrast
                                color:          card.muted
                                    ? Theme.withAlpha(Theme.subtext, 0.82)
                                    : Theme.text
                                font.pixelSize: Settings.fontSize

                                ColorFade on color { duration: Motion.medium }
                            }
                        }
                    }
                }
            }
        }
    }
}
