import QtQuick
import QtQuick.Controls

// A letter group's header in the Library (like Windows phones' app list): the
// letter in a tile. Tapping it opens the letter grid to jump to another letter.
// Phones: slim, the letter in a small tile followed by a thin line, so the
// headers don't take a song row's room each.
Item {
    id: root

    required property string letter

    signal tapped()

    readonly property bool slim: Theme.touchOnly
    readonly property real tileSize: slim ? 28 : 40

    implicitHeight: slim ? 38 : 52
    implicitWidth: 200

    Rectangle {
        id: tile
        x: 8
        anchors.verticalCenter: parent.verticalCenter
        width: root.tileSize
        height: root.tileSize
        radius: root.slim ? 8 : Theme.radius
        color: tileHover.hovered ? Theme.accentSoftHover : Theme.accentSoft

        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        Label {
            anchors.centerIn: parent
            text: root.letter
            color: Theme.accent
            font.pixelSize: root.slim ? Theme.fontSize + 1 : Theme.fontSizeLarge + 2
            font.weight: Font.DemiBold
        }

        HoverHandler { id: tileHover; cursorShape: Qt.PointingHandCursor }
    }

    // (Phones) the line after the letter
    Rectangle {
        visible: root.slim
        anchors.left: tile.right
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        height: 1
        color: Theme.border
    }

    // The whole header takes the tap (a small target on phones otherwise)
    TapHandler { onTapped: root.tapped() }
}
