import QtQuick

// Phones: shown while the app loads (main.cpp closes it once the app has drawn
// itself). A flat solar system turning around its sun, in one color: white on
// black in dark mode, black on white in light mode. The orbits turn with
// RotationAnimator, which runs on the render thread, so they keep turning while
// the app is busy loading.
Window {
    id: root

    property bool dark: true
    readonly property color ink: dark ? "#ffffff" : "#000000"

    visible: true
    color: dark ? "#000000" : "#ffffff"
    flags: Qt.Window | Qt.ExpandedClientAreaHint | Qt.NoTitleBarBackgroundHint

    Item {
        id: system
        anchors.centerIn: parent
        width: 260
        height: 260
        // It eases in (fades and grows) instead of popping up; animators, like
        // the orbits, so a busy app can't make them stutter.
        opacity: 0
        scale: 0.85

        OpacityAnimator on opacity {
            from: 0
            to: 1
            duration: 500
            easing.type: Easing.OutCubic
        }
        ScaleAnimator on scale {
            from: 0.85
            to: 1
            duration: 700
            easing.type: Easing.OutCubic
        }

        // The sun
        Rectangle {
            anchors.centerIn: parent
            width: 34
            height: 34
            radius: width / 2
            color: root.ink
        }

        Repeater {
            // orbit radius, planet size, time for one turn (ms), where it starts
            model: [
                { orbit: 52, size: 9, turn: 1800, start: 40 },
                { orbit: 80, size: 13, turn: 3000, start: 200 },
                { orbit: 108, size: 10, turn: 4600, start: 120 },
                { orbit: 128, size: 7, turn: 6800, start: 300 }
            ]

            delegate: Item {
                id: orbitItem

                required property var modelData

                anchors.centerIn: parent
                width: 2 * modelData.orbit
                height: width
                rotation: modelData.start

                // The orbit
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 1.5
                    border.color: root.ink
                    opacity: 0.3
                }

                // The planet, on the orbit's top
                Rectangle {
                    x: (parent.width - width) / 2
                    y: -height / 2
                    width: orbitItem.modelData.size
                    height: width
                    radius: width / 2
                    color: root.ink
                }

                RotationAnimator on rotation {
                    from: orbitItem.modelData.start
                    to: orbitItem.modelData.start + 360
                    duration: orbitItem.modelData.turn
                    loops: Animation.Infinite
                    running: true
                }
            }
        }
    }
}
