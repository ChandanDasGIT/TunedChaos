import QtQuick
import QtQuick.Controls

// Seek bar drawn as a flowing wave ‿⁀‿⁀: the played part in the accent
// color, the rest dimmed. The wave flows while playing, eases flat when
// paused, and wiggles harder around the pointer while dragging, springing
// back when released. With the "dot" style only that wiggle plays, around the
// dot, for as long as a song plays. Elapsed time on the left; remaining (or
// total) on the right, click it to switch.
Item {
    id: root

    readonly property bool active: PlayerController.hasTrack && PlayerController.duration > 0
    property bool covered: false // a panel lies over this (see NowPlayingPanel)
    signal detailsRequested() // the quality chip was clicked

    readonly property bool dragging: mouse.pressed && active
    property real dragProgress: 0
    readonly property real progress: !active ? 0
                                   : dragging ? dragProgress
                                   : Math.min(1, PlayerController.position / PlayerController.duration)
    readonly property bool showRemaining: SettingsController.showRemainingTime

    // ---- Wave shape -------------------------------------------------------
    readonly property real pad: 8          // keeps round line caps inside
    readonly property real wavelength: 24
    property real phase: 0
    readonly property bool aroundDot: PlayerController.playing && SettingsController.seekbarStyle === "dot"
    property real baseAmplitude: PlayerController.playing && !aroundDot ? 3.2 : 0 // flat when paused/stopped
    property real dragBoost: dragging || aroundDot ? 5.5 : 0
    readonly property real handleX: pad + progress * (waveArea.width - 2 * pad)

    Behavior on baseAmplitude {
        NumberAnimation {
            id: amplitudeAnimation
            duration: Theme.animSlow * 1.5
            easing.type: Easing.InOutQuad
        }
    }
    Behavior on dragBoost {
        SpringAnimation {
            id: boostSpring
            spring: 4
            damping: 0.12
            epsilon: 0.02
        }
    }

    // Extra height around the pointer while dragging (gaussian bump).
    function amplitudeAt(x) {
        const d = (x - handleX) / 46
        return baseAmplitude + dragBoost * Math.exp(-d * d)
    }
    function waveY(x) {
        return waveArea.height / 2 + amplitudeAt(x) * Math.sin(2 * Math.PI * x / wavelength - phase)
    }

    implicitHeight: waveArea.height + timeRow.height + 6

    readonly property real thumbGap: thumb.visible ? thumb.gap : 0
    onThumbGapChanged: canvas.requestPaint()
    onProgressChanged: canvas.requestPaint()
    onBaseAmplitudeChanged: canvas.requestPaint()
    onDragBoostChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()

    // Advances the wave; only runs while something moves.
    FrameAnimation {
        running: root.visible && root.active
                 && (PlayerController.playing || root.dragging || boostSpring.running
                     || amplitudeAnimation.running)
        onTriggered: {
            const speed = root.dragging || root.aroundDot ? 9 : PlayerController.playing ? 2.4 : 0.5
            root.phase = (root.phase + frameTime * speed) % (2 * Math.PI)
            canvas.requestPaint()
        }
    }

    Item {
        id: waveArea
        width: parent.width
        height: 28

        Canvas {
            id: canvas
            anchors.fill: parent
            antialiasing: true

            function strokeWave(ctx, x0, x1) {
                if (x1 <= x0)
                    return
                ctx.beginPath()
                ctx.moveTo(x0, root.waveY(x0))
                for (let x = x0 + 2; x < x1; x += 2)
                    ctx.lineTo(x, root.waveY(x))
                ctx.lineTo(x1, root.waveY(x1))
                ctx.stroke()
            }

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.lineWidth = 3
                ctx.lineCap = "round"
                ctx.lineJoin = "round"

                const left = root.pad
                const right = width - root.pad

                ctx.strokeStyle = Theme.textDim.toString()
                ctx.globalAlpha = 0.55
                strokeWave(ctx, root.handleX + root.thumbGap, right)

                ctx.globalAlpha = 1
                ctx.strokeStyle = root.active ? Theme.accent.toString() : Theme.textDim.toString()
                strokeWave(ctx, left, root.handleX - root.thumbGap)
            }
        }

        // The thumb: stays on the bar's center line while the wave moves around it
        SeekThumb {
            id: thumb
            visible: root.active
            kind: SettingsController.seekbarThumb
            moving: PlayerController.playing && !root.dragging
            wavePhase: root.phase - 2 * Math.PI * root.handleX / root.wavelength
            waveAmplitude: root.amplitudeAt(root.handleX)
            waveLength: root.wavelength
            mixing: true
            barAhead: Qt.rgba(Theme.textDim.r, Theme.textDim.g, Theme.textDim.b, 0.55)
            size: root.dragging ? 18 : hover.hovered ? 15 : 13
            x: root.handleX - width / 2
            y: waveArea.height / 2 - height / 2

            Behavior on size { NumberAnimation { duration: Theme.animFast; easing.type: Theme.easing } }
        }

        HoverHandler {
            id: hover
            enabled: root.active
            cursorShape: Qt.PointingHandCursor
        }

        MouseArea {
            id: mouse

            function setFromX(x) {
                const target = Math.max(0, Math.min(1, (x - root.pad) / (width - 2 * root.pad)))
                thumb.scrubbed((target - root.dragProgress) * width)
                root.dragProgress = target
            }

            anchors.fill: parent
            anchors.topMargin: -6
            anchors.bottomMargin: -2 // stops short of the quality chip, which has clicks of its own
            enabled: root.active
            preventStealing: true

            onPressed: (event) => {
                root.dragProgress = Math.min(1, PlayerController.position / PlayerController.duration)
                setFromX(event.x)
            }
            onPositionChanged: (event) => setFromX(event.x)
            onReleased: {
                thumb.direction = 1
                PlayerController.seek(Math.round(root.dragProgress * PlayerController.duration))
            }
            onCanceled: thumb.direction = 1
        }
    }

    Item {
        id: timeRow
        anchors.top: waveArea.bottom
        anchors.topMargin: 4
        width: parent.width
        height: Math.max(elapsedLabel.implicitHeight, 20)

        QualityChip {
            anchors.centerIn: parent
            covered: root.covered
            onClicked: root.detailsRequested()
        }

        Label {
            id: elapsedLabel
            textFormat: Text.PlainText
            x: root.pad
            text: Util.formatTime(root.progress * PlayerController.duration)
            color: root.dragging ? Theme.text : Theme.textMuted
            font.pixelSize: Theme.fontSizeSmall
            font.features: { "tnum": 1 } // fixed-width digits: no jitter while counting

            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }

        Label {
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.rightMargin: root.pad
            text: root.showRemaining
                  ? "-" + Util.formatTime(PlayerController.duration * (1 - root.progress))
                  : Util.formatTime(PlayerController.duration)
            color: remainingArea.containsMouse ? Theme.text : Theme.textMuted
            font.pixelSize: Theme.fontSizeSmall
            font.features: { "tnum": 1 }

            Behavior on color { ColorAnimation { duration: Theme.animFast } }

            MouseArea {
                id: remainingArea
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: SettingsController.showRemainingTime = !SettingsController.showRemainingTime
            }
        }
    }
}
