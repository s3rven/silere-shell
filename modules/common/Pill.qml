pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"

Item {
    id: root

    property string glyph:      ""
    property string text:       ""
    property color  glyphColor: Theme.barText
    property color  textColor:  Theme.barSubtext
    property bool   interactive: false
    // scroll-only: still a control under the pointer, but no button to a screen reader
    property bool   adjustable: false
    property int    maxTextWidth: 150
    property bool   compact: ShellSettings.barCompact
    readonly property int horizontalPadding: Metrics.pillPadFor(compact)
    property bool   barActive: true
    // a scrollable pill names the controlled route/device so partial gestures cannot carry over when that target changes or the pill disappears
    property string wheelKey: ""
    property string _previousWheelKey: ""
    readonly property bool wheelEnabled: root.hoverEnabled && (root.interactive || root.adjustable)
    function _resetWheel(): void { Scroll.resetControl(root.wheelKey) }
    onWheelKeyChanged: {
        Scroll.resetControl(root._previousWheelKey || "")
        root._previousWheelKey = root.wheelKey
    }
    onWheelEnabledChanged: if (!root.wheelEnabled) root._resetWheel()
    Component.onDestruction: root._resetWheel()
    readonly property bool motionActive: root.barActive && root.visible && !root.collapsed
        && !Idle.isIdle && !ShellSettings.reduceMotion && !Motion.unseen
    property bool   animateGlyph: true
    property bool   animateText: false
    property int    glyphPixelSize: Settings.iconSize + 2
    // 0 to 1 draws the glyph inside a ring filled that far, as a segment's `ring` does for its own glyph; under 0, no ring
    property real   glyphRing: -1
    property color  glyphRingColor: Theme.barAccentMark
    // the icon's own cell and a stroke either side, its glyph a size down: sized off the row, the ring stood twice the
    // reading's height, two pixels inside the hover capsule, round a glyph three sizes smaller than the bar's others
    readonly property int ringSize: Metrics.iconCellFor(root.glyphPixelSize) + 2
    readonly property int _ringGlyphSize: Math.max(8, root.glyphPixelSize - 2)
    // a reading sits left in its reserve: one digit keeps to its glyph and the spare room trails it
    property string reserveText: ""
    readonly property real _reserveW: reserveText.length > 0 ? Math.ceil(_reserveMetrics.implicitWidth) : 0
    // further { glyph, text, reserve, color } pairs after the text, for one widget showing several readings;
    // the content scan does not sweep them, which only the status pills use
    property var    segments: []
    property bool   contentScanEnabled: false
    property color  contentScanColor: Theme.barText
    property real   contentScanProgress: 0.0
    property real   contentScanWidth: 10.0
    property real   levelValue: -1.0
    property bool   levelVisible: false
    property color  levelColor: Theme.barAccentMark

    property bool   hoverActive: false
    // the pointer is still over this pill's bar zone, so a revealed detail waits for it to leave the zone
    property bool   holdOpen: false
    onHoldOpenChanged: if (!holdOpen && !_pillHover.hovered) {
        _hoverRevealTimer.stop()
        hoverActive = false
    }
    readonly property bool hoverEnabled: root.enabled && root.visible && root.barActive
        && !root.collapsed && !Idle.isIdle
    readonly property bool canActivate: root.interactive && root.hoverEnabled
    readonly property bool hovered: root.hoverEnabled && _pillHover.hovered
    readonly property bool expanded: root.hoverEnabled && hoverActive

    property bool   pressed: false
    readonly property bool visualPressed: pressed && root.hoverEnabled

    signal activated()
    // right-click, for the app that owns the pill's subject, as the volume pill opens the mixer
    property bool   hasSecondary: false
    signal secondaryActivated()

    property string accessibleName: root.text

    Accessible.role: root.interactive ? Accessible.Button : Accessible.StaticText
    Accessible.name: root.accessibleName
    Accessible.focusable: root.canActivate
    Accessible.onPressAction: if (root.canActivate) root.activated()
    KeyboardFocus { interactive: control ? control.Accessible.focusable : false; listNavigation: true; onActivated: { if (control) control.Accessible.pressAction() } }

    readonly property int  pillH:   Metrics.barRowHeight
    readonly property bool hasText: text.length > 0

    property bool collapsed: false
    property int  shrinkDelay: 600
    property real _minW: 0
    // a reading inside the row (the system monitor's, between its glyphs) changes width on hover. Its box glides
    // with the pill's own edge, so the readings after it hold still: laid out at once, they were shoved past the edge
    // and slid back on every hover, and jumped back and slid out again on leaving
    readonly property bool _glideReadings: root._shownSegments.length > 0
    readonly property int _gap: Metrics.pillGapFor(root.compact)
    // the row's width once its readings land, so the pill heads there from the first frame. Summed from the boxes'
    // own targets, each holding the gap before it: the Row measures only at its next polish,
    // and its width plus what the boxes still had to cover mixed two frames, so the pill's glide chased a target
    // that jumped twice a frame, parked a pixel wide and stepped back once the readings settled
    readonly property real rowWidth: {
        let sum = _glyphBox.implicitWidth + _textBox._spanW
        const count = Math.min(root.segments.length, _segments.count)
        for (let i = 0; i < count; i++) sum += _segments.itemAt(i)?._finalW ?? 0
        // whole px: a fractional text width puts the pill and every widget after it off-pixel
        return Math.ceil(sum)
    }
    implicitWidth: _widthGlide.value
    SmoothGlide {
        id: _widthGlide
        target: root.collapsed ? 0
            : Math.max(root.rowWidth, root._minW) + root.horizontalPadding * 2
        duration: Motion.width
        // the zone draws the slot at the width rounded up, so a closing pill held its last pixel through the glide's
        // long tail and the bar after it stepped once more 80 ms after it had come to rest
        precision: 0.5
        gate: root._ready && root.barActive
        onRunningChanged: if (!running) {
            root._unfolding = false
            root._ghostText = ""
            if (root._closingFirstSpan >= 0) Qt.callLater(root._finishSegmentConceal)
        }
    }
    // true from a collapse or uncollapse until the width glide that follows it settles
    property bool _unfolding: false
    onCollapsedChanged: {
        root._unfolding = true
        Qt.callLater(function() { if (root && !_widthGlide.running) root._unfolding = false })
    }

    onRowWidthChanged: {
        if (shrinkDelay <= 0 || !root.hoverEnabled || _release.running) {
            _shrinkDelay.stop()
            _minW = rowWidth
            return
        }
        if (rowWidth > _minW) _minW = rowWidth
        _shrinkDelay.restart()
    }
    // a reading cut back as a hover closes stays drawn past the row while the pill's edge closes over it, as the
    // reveal uncovered it; blinked out, it left the capsule's empty tail to collapse on its own. Only a cut back to
    // the reading's own start: any other change is a new value, and a stale one must never show
    property string _ghostText: ""
    property string _lastText: ""
    // the pill's state before this update's handlers: a hover closing changes expanded and text in one batch
    property bool _expandedBefore: false
    property var _shownSegments: []
    property real _closingFirstSpan: -1
    // when plain style returns to one glyph, keep the existing row in place under the retreating edge
    onSegmentsChanged: {
        if (root._ready && root.motionActive && !root.expanded && root._expandedBefore
                && root.segments.length === 0 && root._shownSegments.length > 0) {
            root._closingFirstSpan = _textBox.width
            return
        }
        root._closingFirstSpan = -1
        root._shownSegments = root.segments
    }
    function _finishSegmentConceal(): void {
        if (root._closingFirstSpan < 0) return
        root._closingFirstSpan = -1
        root._shownSegments = root.segments
    }
    function concealsAs(before: string, after: string, wasExpanded: bool): bool {
        return wasExpanded && before.length > after.length && before.indexOf(after) === 0
    }
    onTextChanged: {
        const before = root._lastText
        root._lastText = root.text
        root._ghostText = ""
        if (root._ready && root.motionActive && !root.expanded && !root.animateText
                && (!root._glideReadings || text.length === 0)
                && root.concealsAs(before, root.text, root._expandedBefore)) {
            root._ghostText = before
            _ghostExpiry.restart()
        }
        if (text.length === 0) root._releaseHold()
    }
    // the row relays out a frame later, so the glide that clears the ghost has not started yet; with no glide at all,
    // as when both readings overflow the text cap, nothing closes over it and it goes after the glide's own length
    Timer {
        id: _ghostExpiry
        interval: Motion.width + 120
        onTriggered: if (!_widthGlide.running) root._ghostText = ""
    }
    onShrinkDelayChanged: if (shrinkDelay <= 0) { _shrinkDelay.stop(); _minW = rowWidth }
    onCompactChanged: root._releaseHold()
    // the hold is for readings that flicker; a hover reveal closing, compact, or a new font or scale is
    // deliberate and settles at once. The row relays out on the next frame and can shrink in steps, so the
    // content is followed down for a moment: measured against a released hold, the first step read as growth
    // and kept the pill near its old width, with empty room after the readings, for the whole shrink delay
    function _releaseHold(): void {
        _shrinkDelay.stop()
        _minW = 0
        _release.restart()
    }
    onExpandedChanged: {
        if (!expanded) root._releaseHold()
        Qt.callLater(function() { if (root) root._expandedBefore = root.expanded })
    }
    Connections {
        target: Settings
        function onFontChanged() { root._releaseHold() }
        function onIconFontChanged() { root._releaseHold() }
        function onFontSizeChanged() { root._releaseHold() }
        function onIconSizeChanged() { root._releaseHold() }
    }
    Timer {
        id: _release
        interval: 250
    }
    onHoverEnabledChanged: if (!hoverEnabled) {
        _hoverRevealTimer.stop()
        _shrinkDelay.stop()
        hoverActive = false
        _minW = rowWidth
    }
    onMotionActiveChanged: if (!motionActive && _ready) _settleAnimatedContent()
    Timer {
        id: _shrinkDelay
        interval: root.shrinkDelay
        onTriggered: root._minW = root.rowWidth
    }

    property bool _ready: false
    property string _shownGlyph: ""
    property string _nextGlyph:  ""

    // a widget switched on in Settings is built fresh: it unfolds out of nothing like one leaving hiding, where it
    // landed whole and shoved every widget beside it in one frame. Called by the zone before the first frame
    property bool _unfoldPending: false
    function unfold(): void {
        if (root.collapsed) return
        root._unfoldPending = true
        root._unfolding = true
        _widthGlide.value = 0
    }

    Component.onCompleted: {
        _shownGlyph = root.glyph
        _nextGlyph = root.glyph
        _lastText = root.text
        Qt.callLater(function() {
            if (!root) return
            root._ready = true
            if (!root._unfoldPending) return
            root._unfoldPending = false
            _widthGlide.glideFrom(_widthGlide.value)
        })
    }

    function _settleAnimatedContent(): void {
        _glyphStamp.stop()
        _textSwap.stop()
        _shownGlyph = root.glyph
        _nextGlyph = root.glyph
        _glyphText.scale = 1.0
        _textEl.opacity = 1.0
        _ghostText = ""
        root._finishSegmentConceal()
        if (root.animateText) _textEl._shown = root.text
    }

    onAnimateTextChanged: if (_ready) _settleAnimatedContent()
    onAnimateGlyphChanged: if (_ready && !animateGlyph) _settleAnimatedContent()

    onGlyphChanged: {
        if (!_ready) { _shownGlyph = glyph; return }
        if (!root.motionActive || !animateGlyph) {
            _settleAnimatedContent()
            return
        }
        _nextGlyph = glyph
        if (!_glyphStamp.running) _glyphStamp.start()
    }

    SequentialAnimation {
        id: _glyphStamp
        NumberAnimation { target: _glyphText; property: "scale"; to: 0.72; duration: Motion.instant; easing.type: Easing.InCubic }
        ScriptAction    { script: root._shownGlyph = root._nextGlyph }
        NumberAnimation { target: _glyphText; property: "scale"; from: 0.72; to: 1.0; duration: Motion.fast; easing.type: Easing.OutQuart }
        onFinished: {
            if (root.motionActive && root._nextGlyph !== root._shownGlyph)
                _glyphStamp.start()
        }
    }

    implicitHeight: Math.max(pillH, parent ? parent.height : 0)
    // only while it eases open into wider text, or the scan sweeps in from off-pill; a standing clip node breaks batching
    clip: _contentScan.active || _ghostEl.visible || row.x < 0 || row.x + row.width > width

    HoverCap {
        hot: root.hovered && ShellSettings.barHoverHighlight
        pressed: root.visualPressed
    }

    Item {
        id: _levelTrack
        // the hover capsule has already curved inward by the track's last row, so padding alone leaves the ends poking past the rounded corner
        readonly property real _capR: Metrics.hoverRadiusFor(root.pillH)
        readonly property real _inset: Math.max(root.horizontalPadding + 1,
            Math.ceil(_capR - Math.sqrt(Math.max(0, 2 * _capR - 1))))
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round((parent.height + root.pillH) / 2) - 3
        width: Math.max(10, parent.width - _inset * 2)
        height: 2
        opacity: root.levelVisible && root.levelValue >= 0 ? 1 : 0
        visible: opacity > 0.001

        MotionBehavior on opacity {
            NumberAnimation { duration: Motion.fast }
        }

        Rectangle {
            anchors.fill: parent
            radius: 1
            color: Theme.withAlpha(Theme.barSubtext, 0.16)
        }

        Rectangle {
            // the level eases, not the width: the track resizes with the pill on every frame of its glide, and a
            // width behaviour restarted each frame never moved, leaving the fill up to 126 px past a shrinking pill
            property real _level: Math.max(0, Math.min(1, root.levelValue))
            width: Math.round(parent.width * _level)
            height: parent.height
            radius: 1
            color: root.levelColor
            opacity: 0.78

            MotionBehavior on _level {
                NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
            }
            ColorFade on color {}
        }
    }

    readonly property bool _contentHot: (root.hovered
        && ShellSettings.barHoverHighlight)
        || root.visualPressed
    // "pills follow theming": tint only glyphs resting at the neutral text color up
    // to the bar accent, so inactive, warning and error states keep their own meaning
    function _glyphTint(c: color, hot: bool): color {
        const rest = ShellSettings.barAccentPills && Qt.colorEqual(c, Theme.barText) ? Theme.barAccentMark : c
        return hot ? Theme.mix(rest, Theme.barAccentMark, 0.20) : rest
    }
    readonly property color _restGlyphColor: _glyphTint(glyphColor, false)
    readonly property color _hoverGlyphColor: _glyphTint(glyphColor, _contentHot)
    readonly property color _hoverTextColor: _contentHot
        ? Theme.mix(textColor, Theme.barAccent, 0.16) : textColor

    // full height, so glyph and text each centre once on the bar like the clock; centring a glyph-tall row
    // first rounds twice and drops the text a pixel below every other label on the bar
    Row {
        id: row
        // centred only while the pill grows out of nothing or folds into it. Open, the content keeps its padding and
        // the pill's edge uncovers a longer reading: centred against it, the glyph jumped half the new text's width in
        // the first frame of every hover reveal, partly clipped, then glided on (measured 14 of 28 px for "45%").
        // A held or releasing width keeps the padding too, or each shorter reading jumped right by half the slack
        x: root.collapsed || root._unfolding
            ? Math.round(Math.min((parent.width - width) / 2, root.horizontalPadding))
            : root.horizontalPadding
        height: parent.height
        // with several readings each part carries the gap before it, so the gap glides with its reading: a Row adds or
        // drops its spacing at once as a box crosses zero width, and each ring after a closing reading stepped 5 px
        spacing: root._glideReadings ? 0 : root._gap

        Item {
            id: _glyphBox
            // Math.round, as the row did before it filled the pill: centre anchors round half down and lift the glyph
            y: Math.round((parent.height - height) / 2)
            implicitWidth:  root._shownGlyph.length > 0 ? Metrics.iconCellFor(root.glyphPixelSize) : 0
            implicitHeight: _glyphText.implicitHeight

            ShellText {
                id: _glyphText
                anchors.centerIn: parent
                // a ring shows any rounding: centred to the whole pixel, half down, the glyph sat 0.75 px high and left in it
                anchors.alignWhenCentered: !_glyphBox._ringed
                text:            root._shownGlyph
                color:           root._hoverGlyphColor
                transformOrigin: Item.Center
                font.pixelSize:  _glyphBox._ringed ? root._ringGlyphSize : root.glyphPixelSize
                ColorFade on color {}
            }
        }

        Item {
            id: _textBox
            readonly property bool _hasShownText: _textEl._hasShownText
            anchors.verticalCenter: parent.verticalCenter
            visible: _hasShownText
            readonly property real _targetW: _hasShownText
                ? Math.ceil(Math.min(Math.max(implicitWidth, root._reserveW), root.maxTextWidth)) : 0
            width: root._glideReadings ? _textGlide.value : _targetW
            height: _textEl.implicitHeight
            implicitWidth: _textEl.implicitWidth
            clip: width < _spanW - 0.5 || _textEl._concealing
            SmoothGlide {
                id: _textGlide
                target: root._closingFirstSpan >= 0 ? root._closingFirstSpan : _textBox._spanW
                duration: Motion.width
                gate: root._ready && root.barActive && root._glideReadings
            }

            ShellText {
                id: _textEl
                property string _shown: ""
                readonly property bool _hasShownText: root.animateText ? _shown.length > 0 : root.hasText
                readonly property bool _concealing: root._glideReadings && root._ghostText.length > 0
                // the box uncovers the reading as it glides; a narrower text would elide afresh every frame
                x: root._glideReadings ? _textBox._lead : 0
                width: _concealing ? Math.min(implicitWidth, root.maxTextWidth) : _textBox._targetW
                anchors.verticalCenter: parent.verticalCenter
                elide:   Text.ElideRight
                text:    root.animateText ? _shown : _concealing ? root._ghostText : root.text
                // its start is drawn by the ghost, and two copies blend to a bolder line
                visible: _concealing || root._ghostText.length === 0
                color:   root._hoverTextColor
                font.pixelSize: Settings.fontSize
                font.features: root.reserveText.length > 0 ? ({ "tnum": 1 }) : ({})
                ColorFade on color {}
            }

            // measured as the reading is: an advance leaves out the overhang of a trailing "%", so "00%" came up
            // a pixel short of "14%" and every reserved pill grew a pixel between one digit and two
            Text {
                id: _reserveMetrics
                visible: false
                textFormat: Text.PlainText
                renderType: _textEl.renderType
                font: _textEl.font
                text: root.reserveText
            }

            Component.onCompleted: if (root.animateText) _textEl._shown = root.text

            Connections {
                target: root
                enabled: root.animateText
                function onTextChanged() {
                    if (!root._ready) { _textEl._shown = root.text; return }
                    if (!root.motionActive) {
                        root._settleAnimatedContent()
                        return
                    }
                    if (!_textSwap.running) _textSwap.start()
                }
            }

            SequentialAnimation {
                id: _textSwap
                NumberAnimation { target: _textEl; property: "opacity"; to: 0;   duration: Motion.instant; easing.type: Easing.InCubic  }
                ScriptAction    { script: _textEl._shown = root.text }
                NumberAnimation { target: _textEl; property: "opacity"; to: 1.0; duration: Motion.fast;    easing.type: Easing.OutCubic }
                onFinished: if (root.motionActive && _textEl._shown !== root.text) _textSwap.start()
            }
        }

        // indexed, not modelled: a reading that ticks rebinds its text instead of rebuilding the pair
        Repeater {
            id: _segments
            model: root._shownSegments.length
            Row {
                id: _segment
                required property int index
                readonly property var seg: root._shownSegments[index] ?? ({})
                readonly property string _requestedText: seg.text ?? ""
                property string _shownText: _requestedText
                on_RequestedTextChanged: {
                    if (_requestedText.length === 0 && _segBox.width > 0.5 && root.motionActive
                            && !root.expanded && root._expandedBefore) return
                    _shownText = _requestedText
                }
                // held here, so a reading's tick, which hands every segment a new object, writes no colour: Text keeps
                // 8 bits a channel, a computed colour never reads back equal, and each write restarted the 160 ms fade
                readonly property color _ink: root._glyphTint(_segment.seg.color ?? root.glyphColor, root._contentHot)
                readonly property color _ringInk: root._glyphTint(_segment.seg.ringColor ?? root.glyphRingColor, root._contentHot)
                height: row.height
                // the glyph gap and half again ahead of each pair: a glyph reads as its own reading's, yet the pairs stay one widget
                leftPadding: root._gap + Math.round(root._gap / 2)

                Item {
                    id: _segGlyphBox
                    readonly property real _ring: typeof _segment.seg.ring === "number" ? _segment.seg.ring : -1
                    readonly property bool _ringed: _ring >= 0
                    y: Math.round((parent.height - height) / 2)
                    implicitWidth: Metrics.iconCellFor(root.glyphPixelSize)
                    implicitHeight: _segGlyph.implicitHeight
                    ShellText {
                        id: _segGlyph
                        anchors.centerIn: parent
                        anchors.alignWhenCentered: !_segGlyphBox._ringed
                        text: _segment.seg.glyph ?? ""
                        color: _segment._ink
                        font.pixelSize: _segGlyphBox._ringed ? root._ringGlyphSize : root.glyphPixelSize
                        ColorFade on color {}
                    }
                }

                Item {
                    id: _segBox
                    readonly property real _targetW: Math.ceil(Math.max(_segText.implicitWidth, _segReserve.implicitWidth))
                    anchors.verticalCenter: parent.verticalCenter
                    width: _segGlide.value
                    height: _segText.implicitHeight
                    clip: width < _spanW - 0.5 || _concealing
                    SmoothGlide {
                        id: _segGlide
                        target: _segBox._spanW
                        duration: Motion.width
                        gate: root._ready && root.barActive
                        onRunningChanged: if (!running) _segment._shownText = _segment._requestedText
                    }
                    ShellText {
                        id: _segText
                        x: root._gap
                        anchors.verticalCenter: parent.verticalCenter
                        width: _segBox._targetW
                        text: _segment.seg.text ?? ""
                        color: root._hoverTextColor
                        font.pixelSize: Settings.fontSize
                        font.features: ({ "tnum": 1 })
                        ColorFade on color {}
                        Text {
                            id: _segReserve
                            visible: false
                            textFormat: Text.PlainText
                            renderType: _segText.renderType
                            font: _segText.font
                            text: _segment.seg.reserve ?? ""
                        }
                    }
                }
                readonly property real _finalW: leftPadding + _segGlyphBox.implicitWidth + _segBox._spanW
            }
        }
    }

    // beside the row, not in it, so the pill's width already follows the shorter reading
    ShellText {
        id: _ghostEl
        visible: !root._glideReadings && root._ghostText.length > 0
        x: row.x + (_glyphBox.width > 0 ? _glyphBox.width + row.spacing : 0)
        anchors.verticalCenter: row.verticalCenter
        width: Math.min(implicitWidth, root.maxTextWidth)
        elide: Text.ElideRight
        text: root._ghostText
        color: root._hoverTextColor
        font.pixelSize: Settings.fontSize
        font.features: _textEl.font.features
        ColorFade on color {}
    }

    Loader {
        id: _contentScan
        active: root.motionActive && root.contentScanEnabled
        width: Math.max(1, root.contentScanWidth)
        height: row.height
        x: row.x - width + (row.width + width) * Math.max(0, Math.min(1, root.contentScanProgress))
        y: row.y

        sourceComponent: Item {
            clip: true
            width: _contentScan.width
            height: _contentScan.height

            Row {
                x: row.x - _contentScan.x
                y: 0
                spacing: row.spacing

                Item {
                    y: _glyphBox.y
                    width: _glyphBox.width
                    height: _glyphBox.height

                    ShellText {
                        anchors.centerIn: parent
                        text:           root._shownGlyph
                        color:          root.contentScanColor
                        font.pixelSize: root.glyphPixelSize
                    }
                }

                Item {
                    visible: _textBox._hasShownText
                    width: _textBox.width
                    height: row.height

                    ShellText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        elide: Text.ElideRight
                        text: root.animateText ? _textEl._shown : root.text
                        color: root.contentScanColor
                        font.pixelSize: Settings.fontSize
                        font.features: _textEl.font.features
                    }
                }
            }
        }
    }

    HoverHandler {
        id: _pillHover
        enabled: root.hoverEnabled
        margin: 0
        cursorShape: root.interactive || root.adjustable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onHoveredChanged: root._pointerChanged(hovered)
    }

    TapHandler {
        enabled: root.canActivate && root.hasSecondary
        acceptedButtons: Qt.RightButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: root.secondaryActivated()
    }

    function _pointerChanged(over: bool): void {
        if (over) {
            _hoverRevealTimer.restart()
            return
        }
        _hoverRevealTimer.stop()
        if (!root.holdOpen) root.hoverActive = false
    }

    Timer {
        id: _hoverRevealTimer
        interval: 80
        onTriggered: root.hoverActive = root.hoverEnabled && _pillHover.hovered
    }
}
