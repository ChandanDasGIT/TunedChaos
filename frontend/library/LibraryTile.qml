import QtQuick
import QtQuick.Controls

// One tile of a Library grid (TileGrid): a square picture (or an icon), a title
// and a line under it. Songs also get a "⋮" for their menu, and the playing one
// is tinted. Used for songs, albums, artists, genres, playlists and folders.
Item {
    id: root

    property string image: ""      // a picture's source ("": the icon)
    property string icon: "compactDisc"
    property string title
    property string subtitle
    property bool current: false   // the song playing
    property bool showMore: false  // a "⋮" button
    property var dragPayload: null // a function for DragSource (null: no dragging)

    signal tapped()
    signal moreRequested(Item button)

    Rectangle {
        anchors.fill: parent
        anchors.margins: 4
        radius: Theme.radiusLarge
        color: root.current ? Theme.currentRow : tileHover.hovered ? Theme.hover : "transparent"

        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        HoverHandler { id: tileHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: if (tapCount === 1) root.tapped() }

        // Hold and drag onto the Queue or the player
        Loader {
            anchors.fill: parent
            active: root.dragPayload !== null
            sourceComponent: DragSource { payload: root.dragPayload }
        }

        Rectangle {
            id: cover
            x: 6
            y: 6
            width: parent.width - 12
            height: width
            radius: Theme.radius
            color: Theme.surfaceAlt
            clip: true
            scale: tileHover.hovered ? 1.03 : 1

            Behavior on scale { NumberAnimation { duration: Theme.anim; easing.type: Theme.easing } }

            // Under the picture (a cover can come back empty: the icon then shows through)
            Icon {
                anchors.centerIn: parent
                name: root.icon
                size: Math.max(20, cover.width * 0.22)
                color: Theme.textDim
            }

            Image {
                id: picture
                anchors.fill: parent
                visible: root.image !== ""
                source: root.image
                sourceSize: Qt.size(280, 280)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                opacity: status === Image.Ready ? 1 : 0

                Behavior on opacity { NumberAnimation { duration: Theme.anim } }
            }

            // The "⋮" on the picture's corner, on a disc so it shows on any cover
            Rectangle {
                id: moreDisc
                visible: root.showMore && (tileHover.hovered || Theme.touchOnly)
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 6
                width: 30
                height: 30
                radius: 15
                color: Theme.withAlpha(Theme.background, 0.75)

                ControlButton {
                    anchors.fill: parent
                    iconName: "more"
                    iconSize: 12
                    iconColor: Theme.text
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("More")
                    onClicked: root.moreRequested(moreDisc)
                }
            }
        }

        Label {
            anchors.top: cover.bottom
            anchors.topMargin: 6
            x: 8
            width: parent.width - 16
            text: root.title
            color: root.current ? Theme.accent : Theme.text
            font.pixelSize: Theme.fontSize
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        Label {
            anchors.top: cover.bottom
            anchors.topMargin: 24
            x: 8
            width: parent.width - 16
            text: root.subtitle
            color: Theme.textMuted
            font.pixelSize: Theme.fontSizeSmall
            elide: Text.ElideRight
        }
    }
}
