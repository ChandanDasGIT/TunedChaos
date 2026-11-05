pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// An artist's page (from Search or a card): their picture and name, top songs,
// then shelves of albums, singles and similar artists. Over the tabs, with a
// back button; an album opened from here comes back here.
Item {
    id: root

    readonly property bool swipeBlocked: shelvesBusy > 0
    property int shelvesBusy: 0
    // Top songs shown before "Show all"
    property bool allSongs: false

    Connections {
        target: YouTubeController
        function onArtistChanged() {
            if (YouTubeController.artistLoading) {
                root.allSongs = false
                page.contentY = 0
            }
        }
    }

    Flickable {
        id: page
        anchors.fill: parent
        contentHeight: column.implicitHeight + Theme.padding
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: Theme.flickDeceleration
        maximumFlickVelocity: Theme.flickVelocity
        synchronousDrag: true
        ScrollBar.vertical: ScrollBar {}

        ColumnLayout {
            id: column
            width: parent.width
            spacing: Theme.spacing

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacing
                Layout.rightMargin: Theme.padding
                Layout.topMargin: Theme.spacing
                spacing: Theme.padding

                Item { // room for the back button, which stays put above the page
                    Layout.preferredWidth: 38
                    Layout.preferredHeight: 34
                    Layout.alignment: Qt.AlignTop
                }

                YtThumbnail {
                    Layout.preferredWidth: 88
                    Layout.preferredHeight: 88
                    round: true
                    source: YouTubeController.artistThumbnail
                    hue: YouTubeController.artistName.length % 10 / 10
                    iconName: "user"
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing

                    Label {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: YouTubeController.artistName
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeLarge * 1.3
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    PillButton {
                        visible: YouTubeController.artistSongs.length > 0
                        filled: true
                        iconName: "play"
                        iconSize: 11
                        text: qsTr("Play top songs")
                        implicitHeight: 34
                        onClicked: YouTubeController.playList(YouTubeController.artistSongs, 0, YouTubeController.artistName)
                    }
                }
            }

            Label {
                textFormat: Text.PlainText
                visible: YouTubeController.artistSongs.length > 0
                Layout.leftMargin: Theme.padding
                Layout.topMargin: Theme.spacing
                text: qsTr("Top songs")
                color: Theme.text
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.DemiBold
            }

            Repeater {
                model: root.allSongs ? YouTubeController.artistSongs : YouTubeController.artistSongs.slice(0, 5)

                delegate: YtTrackRow {
                    required property var modelData
                    required property int index
                    song: modelData
                    listSongs: YouTubeController.artistSongs
                    listIndex: index
                    listTitle: YouTubeController.artistName
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    Layout.rightMargin: 4
                }
            }

            PillButton {
                visible: YouTubeController.artistSongs.length > 5
                Layout.leftMargin: Theme.padding
                text: root.allSongs ? qsTr("Show fewer") : qsTr("Show all %1").arg(YouTubeController.artistSongs.length)
                implicitHeight: 30
                transparentIdle: true
                onClicked: root.allSongs = !root.allSongs
            }

            Repeater {
                model: YouTubeController.artistShelves

                delegate: YtShelf {
                    required property var modelData
                    Layout.fillWidth: true
                    title: modelData.title
                    items: modelData.items
                    onBusyChanged: root.shelvesBusy += busy ? 1 : -1
                    Component.onDestruction: if (busy) root.shelvesBusy -= 1
                }
            }
        }
    }

    Rectangle { // solid behind the back button, over the scrolled page
        x: Theme.spacing
        y: Theme.spacing
        width: 38
        height: 34
        radius: height / 2
        color: Theme.surface
        opacity: page.contentY > 0 ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
    }
    PillButton {
        x: Theme.spacing
        y: Theme.spacing
        iconName: "back"
        iconSize: 12
        implicitWidth: 38
        implicitHeight: 34
        onClicked: YouTubeController.closeArtist()
    }

    YtStatus {
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.padding
        loading: YouTubeController.artistLoading
        loadingText: qsTr("Loading the artist…")
        errorText: YouTubeController.artistError
        onRetry: YouTubeController.closeArtist()
    }
}
