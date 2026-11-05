import QtQuick
import QtQuick.Controls

// On/off switch: a pill track with a sliding knob.
AbstractButton {
    id: root

    checkable: true
    hoverEnabled: true
    focusPolicy: Qt.NoFocus
    implicitWidth: 46
    implicitHeight: 26
    opacity: enabled || Util.openDialogs > 0 ? 1 : 0.4

    background: Rectangle {
        radius: height / 2
        color: root.checked ? Theme.accent : root.hovered ? Theme.switchTrackHover : Theme.switchTrack

        Behavior on color { ColorAnimation { duration: Theme.anim } }
    }

    contentItem: Item {
        Rectangle {
            readonly property real size: root.pressed ? 22 : 18
            // 0: off, 1: on. Animated itself (not x), so only flipping the switch
            // slides the knob: a new switch growing to its size doesn't.
            property real onAmount: root.checked ? 1 : 0

            width: size
            height: 18
            radius: height / 2
            y: (parent.height - height) / 2
            x: 4 + onAmount * (parent.width - width - 8)
            color: root.checked ? Theme.background : Theme.text

            Behavior on onAmount { NumberAnimation { duration: Theme.anim; easing.type: Theme.easing } }
            Behavior on width { NumberAnimation { duration: Theme.animFast } }
            Behavior on color { ColorAnimation { duration: Theme.anim } }
        }
    }
}
