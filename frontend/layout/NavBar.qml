import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// The floating bar at the bottom of the window: the panels in `panels`, then
// Settings, each an icon over its name. What is open is marked with a pill behind
// its icon. Wide windows get a compact, centered bar; phone-size ones a full-width
// bar. Two panels or more share the width; with fewer, a toy seek bar fills it.
Rectangle {
    id: root

    property var panels: ["youtube", "queue", "home", "library"]
    readonly property bool fidget: panels.length < 2
    readonly property var panelInfo: ({
        youtube: { icon: "cloud", label: qsTr("YouTube"), tip: qsTr("YouTube Music (Ctrl+2)") },
        queue: { icon: "listMusic", label: qsTr("Queue"), tip: qsTr("Queue (Ctrl+1)") },
        home: { icon: "home", label: qsTr("Home"), tip: qsTr("Home") },
        library: { icon: "compactDisc", label: qsTr("Library"), tip: qsTr("Library (Ctrl+3)") },
        player: { icon: "music", label: qsTr("Player"), tip: qsTr("Player") } // (phones: in the default panel's place)
    })

    property bool homeOpen: false
    property bool queueOpen: false
    property bool youtubeOpen: false
    property bool libraryOpen: false
    property bool settingsOpen: false
    property bool playerOpen: false

    signal homeClicked()
    signal queueClicked()
    signal youtubeClicked()
    signal libraryClicked()
    signal settingsClicked()
    signal playerClicked()

    implicitHeight: 64
    radius: Theme.radiusCard
    color: Theme.miniPlayer
    border.color: Theme.border

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacing
        anchors.rightMargin: Theme.spacing
        spacing: 0

        Repeater {
            model: root.panels

            delegate: NavButton {
                required property string modelData

                iconName: root.panelInfo[modelData].icon
                label: root.panelInfo[modelData].label
                tip: root.panelInfo[modelData].tip
                divider: !root.fidget && SettingsController.navDividers // (Settings always comes after it)
                active: root[modelData + "Open"]
                onClicked: root[modelData + "Clicked"]()
            }
        }

        FidgetBar {
            visible: root.fidget
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        NavButton {
            iconName: "settings"
            label: qsTr("Settings")
            active: root.settingsOpen
            tip: qsTr("Settings (Ctrl+,)")
            onClicked: root.settingsClicked()
        }
    }

    // Looks like the seek bar but has nothing to do with the music: only there
    // to be dragged around, filling the bar when it has one panel or none.
    component FidgetBar: Item {
        id: bar

        readonly property real pad: 8
        readonly property real wavelength: 24
        readonly property bool dragging: touch.pressed
        property real progress: 0.5
        property real phase: 0
        property real boost: dragging ? 5.5 : 0
        readonly property real handleX: pad + progress * (width - 2 * pad)

        function amplitudeAt(x) {
            if (SettingsController.fidgetStyle === "wave")
                return boost * 0.6
            const d = (x - handleX) / 46
            return boost * Math.exp(-d * d)
        }
        function waveY(x) {
            return height / 2 + amplitudeAt(x) * Math.sin(2 * Math.PI * x / wavelength - phase)
        }
        function dragTo(x) {
            const target = Math.max(0, Math.min(1, (x - pad) / Math.max(1, width - 2 * pad)))
            fidgetThumb.scrubbed((target - progress) * width)
            progress = target
        }

        readonly property real thumbGap: fidgetThumb.gap
        onThumbGapChanged: wave.requestPaint()
        onProgressChanged: wave.requestPaint()
        onBoostChanged: wave.requestPaint()
        onWidthChanged: wave.requestPaint()

        Behavior on boost {
            SpringAnimation {
                id: spring
                spring: 4
                damping: 0.25
                epsilon: 0.05
            }
        }

        FrameAnimation {
            running: bar.visible && (bar.dragging || spring.running)
            onTriggered: {
                bar.phase = (bar.phase + frameTime * 9) % (2 * Math.PI)
                wave.requestPaint()
            }
        }

        Canvas {
            id: wave
            anchors.fill: parent
            antialiasing: true

            function strokeWave(ctx, x0, x1) {
                if (x1 <= x0)
                    return
                ctx.beginPath()
                ctx.moveTo(x0, bar.waveY(x0))
                for (let x = x0 + 2; x < x1; x += 2)
                    ctx.lineTo(x, bar.waveY(x))
                ctx.lineTo(x1, bar.waveY(x1))
                ctx.stroke()
            }

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.lineWidth = 3
                ctx.lineCap = "round"
                ctx.lineJoin = "round"

                ctx.strokeStyle = Theme.textDim.toString()
                ctx.globalAlpha = 0.55
                strokeWave(ctx, bar.handleX + bar.thumbGap, width - bar.pad)

                ctx.globalAlpha = 1
                ctx.strokeStyle = Theme.accent.toString()
                strokeWave(ctx, bar.pad, bar.handleX - bar.thumbGap)
            }
        }

        SeekThumb {
            id: fidgetThumb
            kind: SettingsController.fidgetThumb
            wavePhase: bar.phase - 2 * Math.PI * bar.handleX / bar.wavelength
            waveAmplitude: bar.amplitudeAt(bar.handleX)
            waveLength: bar.wavelength
            mixing: true
            barAhead: Qt.rgba(Theme.textDim.r, Theme.textDim.g, Theme.textDim.b, 0.55)
            size: bar.dragging ? 18 : 13
            x: bar.handleX - width / 2
            y: (bar.height - height) / 2

            Behavior on size { NumberAnimation { duration: Theme.animFast; easing.type: Theme.easing } }
        }

        MouseArea {
            id: touch
            anchors.fill: parent
            preventStealing: true
            onPressed: (mouse) => bar.dragTo(mouse.x)
            onPositionChanged: (mouse) => bar.dragTo(mouse.x)
            onReleased: fidgetThumb.direction = 1
            onCanceled: fidgetThumb.direction = 1
        }
    }

    // An icon in a pill (filled while active) over its name.
    component NavButton: AbstractButton {
        id: button

        property string iconName
        property string label
        property string tip
        property bool active: false
        property bool divider: false // a thin line on its right

        Layout.fillWidth: !root.fidget
        Layout.preferredWidth: 72
        Layout.fillHeight: true
        hoverEnabled: true
        focusPolicy: Qt.NoFocus
        ToolTip.visible: hovered && tip !== ""
        ToolTip.text: tip
        ToolTip.delay: 600

        Rectangle {
            visible: button.divider
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: parent.height * 0.5
            color: Theme.text
            opacity: 0.35
        }

        contentItem: Item {
            Rectangle {
                id: pill
                anchors.horizontalCenter: parent.horizontalCenter
                y: 8
                // The active pill grows out from the icon; hovering shows a smaller one.
                width: button.active ? 56 : button.hovered ? 44 : 28
                height: 28
                radius: height / 2
                color: button.active ? Theme.accentSoft : button.hovered ? Theme.hover : "transparent"
                scale: button.pressed ? 0.92 : 1

                Behavior on width { NumberAnimation { duration: Theme.animSlow; easing.type: Theme.easingBack } }
                Behavior on color { ColorAnimation { duration: Theme.anim } }
                Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Theme.easing } }

                Icon {
                    id: navIcon
                    anchors.centerIn: parent
                    name: button.iconName
                    size: 14
                    color: button.active ? Theme.accent : Theme.text

                    Behavior on color { ColorAnimation { duration: Theme.anim } }
                }

                // A small pop as it becomes active
                SequentialAnimation {
                    id: pop
                    NumberAnimation { target: navIcon; property: "scale"; to: 1.25; duration: Theme.animFast; easing.type: Theme.easing }
                    NumberAnimation { target: navIcon; property: "scale"; to: 1; duration: Theme.animSlow; easing.type: Theme.easingBack }
                }
                Connections {
                    target: button
                    function onActiveChanged() { if (button.active) pop.restart() }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: pill.bottom
                anchors.topMargin: 3
                text: button.label
                color: button.active ? Theme.accent : Theme.textMuted
                font.pixelSize: Theme.fontSizeSmall
                font.weight: button.active ? Font.DemiBold : Font.Normal
            }
        }
    }
}
