import QtQuick
import QtQuick.Controls

// A letter group's header in the Library (like Windows phones' app list): the
// letter in a tile. Tapping it opens the letter grid to jump to another letter.
Item {
    id: root

    required property string letter

    signal tapped()

    implicitHeight: 52
    implicitWidth: 200

    Rectangle {
        x: 8
        anchors.verticalCenter: parent.verticalCenter
        width: 40
        height: 40
        radius: Theme.radius
        color: tileHover.hovered ? Theme.accentSoftHover : Theme.accentSoft

        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        Label {
            anchors.centerIn: parent
            text: root.letter
            color: Theme.accent
            font.pixelSize: Theme.fontSizeLarge + 2
            font.weight: Font.DemiBold
        }

        HoverHandler { id: tileHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.tapped() }
    }
}
