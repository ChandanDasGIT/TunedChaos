import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// One row of the Hosted library: a song (with its length, a heart for the
// server's favourites, "add to the Queue" and a menu) or an album / artist /
// playlist (with a chevron).
Rectangle {
    id: root

    property string thumbnail
    property string title
    property string subtitle
    property real duration: -1 // ms; -1: not a song
    property bool playing: false
    property string icon: isSong ? "music" : "compactDisc" // shown without a picture
    property bool favorite: false

    signal tapped()
    signal queueRequested()
    signal favoriteToggled()
    signal menuRequested(Item button)

    readonly property bool isSong: duration >= 0

    height: 56
    radius: Theme.radius
    color: playing ? Theme.currentRow : rowHover.hovered ? Theme.hover : "transparent"

    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: root.tapped() }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        spacing: Theme.padding

        Rectangle {
            Layout.preferredWidth: 44
            Layout.preferredHeight: 44
            radius: Theme.radius
            color: Theme.surfaceAlt
            clip: true

            Icon {
                anchors.centerIn: parent
                name: root.icon
                size: 14
                color: Theme.textDim
            }

            Image {
                anchors.fill: parent
                source: root.thumbnail
                sourceSize: Qt.size(120, 120)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                opacity: status === Image.Ready ? 1 : 0
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Label {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.title
                color: root.playing ? Theme.accent : Theme.text
                font.pixelSize: Theme.fontSize
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Label {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                visible: text !== ""
                text: root.subtitle
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideRight
            }
        }

        Label {
            textFormat: Text.PlainText
            visible: root.isSong && root.duration > 0
            text: Util.formatTime(root.duration)
            color: Theme.textMuted
            font.pixelSize: Theme.fontSizeSmall
        }

        // Phones: room for the title. Favourite and Queue are in the menu; a small
        // heart only marks favourites.
        Icon {
            visible: root.isSong && Theme.touchOnly && root.favorite
            name: "heart"
            size: 11
            color: Theme.accent
        }

        ControlButton {
            visible: root.isSong && !Theme.touchOnly
            iconName: "heart"
            iconSize: 13
            iconColor: root.favorite ? Theme.accent : Theme.textDim
            ToolTip.visible: hovered
            ToolTip.text: root.favorite ? qsTr("Remove from your favourites") : qsTr("Add to your favourites")
            onClicked: root.favoriteToggled()
        }

        ControlButton {
            visible: root.isSong && !Theme.touchOnly
            iconName: "plus"
            iconSize: 13
            iconColor: Theme.textMuted
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Add to the Queue")
            onClicked: root.queueRequested()
        }

        ControlButton {
            id: moreButton
            visible: root.isSong
            iconName: "more"
            iconSize: 13
            iconColor: Theme.textMuted
            ToolTip.visible: hovered
            ToolTip.text: qsTr("More")
            onClicked: root.menuRequested(moreButton)
        }

        Icon {
            visible: !root.isSong
            name: "chevronRight"
            size: 10
            color: Theme.textDim
        }
    }
}
