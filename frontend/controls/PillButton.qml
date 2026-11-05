import QtQuick
import QtQuick.Controls

// Stadium-shaped button with an icon and/or text.
//   filled: accent background (main action)
//   active: toggled on (accent-tinted)
// Pressing squishes it and squares the corners a little.
AbstractButton {
    id: root

    property string iconName
    property real iconSize: 16
    property bool filled: false
    property bool active: false
    property bool iconAfter: false // the icon on the text's right
    property bool transparentIdle: false // no background unless hovered/active (inside a group)
    property real sidePadding: 16 // left and right of the icon and text
    property color iconColor: filled ? Theme.background : active ? Theme.accent : Theme.text

    implicitHeight: 44
    implicitWidth: Math.max(implicitHeight, row.implicitWidth + 2 * sidePadding)
    hoverEnabled: true
    focusPolicy: Qt.NoFocus
    opacity: enabled || Util.openDialogs > 0 ? 1 : 0.35
    scale: pressed ? 0.93 : 1

    Behavior on opacity { NumberAnimation { duration: Theme.anim } }
    Behavior on scale { NumberAnimation { duration: Theme.anim; easing.type: Theme.easingBack } }

    contentItem: Item {
        Row {
            id: row
            anchors.centerIn: parent
            spacing: root.sidePadding < 16 ? 6 : 8
            layoutDirection: root.iconAfter ? Qt.RightToLeft : Qt.LeftToRight

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.iconName !== ""
                name: root.iconName
                size: root.iconSize
                color: root.iconColor

                Behavior on color { ColorAnimation { duration: Theme.anim } }
            }

            Label {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                visible: root.text !== ""
                text: root.text
                color: root.iconColor
                font.pixelSize: Theme.fontSize
                font.weight: Font.DemiBold
            }
        }
    }

    background: Rectangle {
        radius: root.pressed ? root.height * 0.3 : root.height / 2
        color: {
            if (root.filled)
                return root.pressed ? Qt.darker(Theme.accent, 1.15)
                     : root.hovered ? Qt.lighter(Theme.accent, 1.08) : Theme.accent
            if (root.active)
                return root.hovered ? Theme.accentSoftHover : Theme.accentSoft
            if (root.pressed)
                return Theme.selection
            if (root.hovered)
                return Theme.fillHover
            return root.transparentIdle ? "transparent" : Theme.fill
        }

        Behavior on radius { NumberAnimation { duration: Theme.anim; easing.type: Theme.easing } }
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }
}
