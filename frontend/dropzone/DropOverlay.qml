import QtQuick
import QtQuick.Controls

// Accepts folders/files dropped anywhere on the window, highlights the window
// while dragging, and shows scan progress afterwards.
DropArea {
    id: root

    signal urlsDropped()      // songs / folders: added to the Queue
    signal playlistsDropped() // .m3u / .m3u8 files: imported as playlists

    onEntered: (drag) => {
        if (!drag.hasUrls)
            drag.accepted = false
    }

    onDropped: (drop) => {
        if (!drop.hasUrls)
            return
        const songs = []
        let playlists = 0
        for (const url of drop.urls) {
            if (/\.m3u8?$/i.test(url.toString())) {
                PlaylistsController.importM3u(url.toString())
                ++playlists
            } else {
                songs.push(url)
            }
        }
        drop.acceptProposedAction()
        if (songs.length > 0) {
            LibraryController.addUrls(songs)
            root.urlsDropped()
        }
        if (playlists > 0)
            root.playlistsDropped()
    }

    // Drag highlight
    Rectangle {
        anchors.fill: parent
        anchors.margins: Theme.spacing
        opacity: root.containsDrag ? 1 : 0
        visible: opacity > 0
        scale: root.containsDrag ? 1 : 0.97
        radius: Theme.radiusLarge

        Behavior on opacity { NumberAnimation { duration: Theme.anim } }
        Behavior on scale { NumberAnimation { duration: Theme.anim; easing.type: Theme.easing } }
        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
        border.color: Theme.accent
        border.width: 2

        Column {
            anchors.centerIn: parent
            spacing: Theme.padding

            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "folderOpen"
                size: 48
                color: Theme.accent
            }

            Label {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Drop to add to the Queue")
                color: Theme.text
                font.pixelSize: Theme.fontSizeLarge
            }
        }
    }

    // Scan progress pill
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: LibraryController.scanning ? Theme.padding * 2 : -height
        opacity: LibraryController.scanning ? 1 : 0
        visible: opacity > 0

        Behavior on anchors.bottomMargin { NumberAnimation { duration: Theme.animSlow; easing.type: Theme.easing } }
        Behavior on opacity { NumberAnimation { duration: Theme.anim } }
        width: progressLabel.implicitWidth + 2 * Theme.padding * 1.5
        height: 32
        radius: height / 2
        color: Theme.surfaceAlt
        border.color: Theme.border

        Label {
            id: progressLabel
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: LibraryController.totalCount > 0
                  ? qsTr("Scanning… %1 / %2").arg(LibraryController.scannedCount).arg(LibraryController.totalCount)
                  : qsTr("Looking for music…")
            color: Theme.text
            font.pixelSize: Theme.fontSize
        }
    }
}
