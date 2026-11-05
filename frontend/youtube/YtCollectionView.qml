pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// An opened playlist / album (from Home, Search or an artist's page), over the
// tabs, with a back button.
ColumnLayout {
    spacing: Theme.spacing

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.spacing
        Layout.rightMargin: Theme.padding
        Layout.topMargin: Theme.spacing
        spacing: Theme.spacing

        PillButton {
            iconName: "back"
            iconSize: 12
            implicitWidth: 38
            implicitHeight: 34
            onClicked: YouTubeController.closeCollection()
        }

        Label {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: YouTubeController.collectionTitle
            color: Theme.text
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        PillButton {
            visible: YouTubeController.collectionSongs.length > 0
            filled: true
            iconName: "play"
            iconSize: 11
            text: qsTr("Play all")
            implicitHeight: 34
            onClicked: YouTubeController.playList(YouTubeController.collectionSongs, 0, YouTubeController.collectionTitle)
        }
    }

    ListView {
        populate: ListPopulate {}
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        model: YouTubeController.collectionSongs
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: Theme.flickDeceleration
        maximumFlickVelocity: Theme.flickVelocity
        synchronousDrag: true
        ScrollBar.vertical: ScrollBar {}

        // A song here plays the album / playlist from that song.
        delegate: YtTrackRow {
            required property var modelData
            required property int index
            song: modelData
            listSongs: YouTubeController.collectionSongs
            listIndex: index
            listTitle: YouTubeController.collectionTitle
            x: 4
            width: ListView.view.width - 8
        }

        YtStatus {
            anchors.centerIn: parent
            width: parent.width - 2 * Theme.padding
            loading: YouTubeController.collectionLoading
            loadingText: qsTr("Loading songs…")
            errorText: YouTubeController.collectionError
            onRetry: YouTubeController.closeCollection()
        }
    }
}
