pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Library tab: your liked songs on YouTube Music. Signing in means choosing
// your web browser in Settings; yt-dlp then uses that browser's YouTube
// session (the app never sees your password).
Item {
    id: root

    signal settingsRequested()

    onVisibleChanged: {
        if (visible && YouTubeController.signedIn && YouTubeController.librarySongs.length === 0
                && !YouTubeController.libraryLoading)
            YouTubeController.loadLibrary()
    }

    // ---- Not signed in ----------------------------------------------------------
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.padding
        visible: !YouTubeController.signedIn
        implicitHeight: signIn.implicitHeight + 2 * Theme.padding * 1.5
        radius: Theme.radiusLarge
        color: Theme.fill

        ColumnLayout {
            id: signIn
            anchors.fill: parent
            anchors.margins: Theme.padding * 1.5
            spacing: Theme.spacing

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 56
                implicitHeight: 56
                radius: 28
                color: Theme.accentSoft

                Icon {
                    anchors.centerIn: parent
                    name: "user"
                    size: 22
                    color: Theme.accent
                }
            }

            Label {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Your YouTube Music library")
                color: Theme.text
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.DemiBold
            }

            Label {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: qsTr("Sign in by choosing the web browser where you use YouTube Music. Your liked songs then appear here. The app never sees your password.")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeSmall
            }

            PillButton {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 4
                filled: true
                iconName: "settings"
                iconSize: 12
                text: qsTr("Choose browser")
                implicitHeight: 40
                onClicked: root.settingsRequested()
            }
        }
    }

    // ---- Signed in: liked songs ------------------------------------------------
    ColumnLayout {
        anchors.fill: parent
        visible: YouTubeController.signedIn
        spacing: Theme.spacing

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.padding
            Layout.rightMargin: Theme.padding
            Layout.topMargin: Theme.spacing

            Icon {
                name: "heart"
                size: 13
                color: Theme.accent
            }

            Label {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: qsTr("Liked songs")
                color: Theme.text
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.DemiBold
            }

            PillButton {
                iconName: "refresh"
                iconSize: 12
                implicitWidth: 34
                implicitHeight: 34
                enabled: !YouTubeController.libraryLoading
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Refresh")
                onClicked: YouTubeController.loadLibrary()
            }

            PillButton {
                visible: YouTubeController.librarySongs.length > 0
                filled: true
                iconName: "play"
                iconSize: 11
                text: qsTr("Play all")
                implicitHeight: 34
                onClicked: YouTubeController.playList(YouTubeController.librarySongs, 0, qsTr("Liked songs"))
            }
        }

        ListView {
            populate: ListPopulate {}
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: YouTubeController.librarySongs
            boundsBehavior: Flickable.StopAtBounds
            flickDeceleration: Theme.flickDeceleration
            maximumFlickVelocity: Theme.flickVelocity
            synchronousDrag: true
            ScrollBar.vertical: ScrollBar {}

            delegate: YtTrackRow {
                required property var modelData
                song: modelData
                x: 4
                width: ListView.view.width - 8
            }

            YtStatus {
                anchors.centerIn: parent
                width: parent.width - 2 * Theme.padding
                loading: YouTubeController.libraryLoading
                loadingText: qsTr("Reading your library through your browser…")
                errorText: YouTubeController.libraryError
                onRetry: YouTubeController.loadLibrary()
            }
        }
    }
}
