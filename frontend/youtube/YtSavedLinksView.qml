pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Saved tab: your own library of YouTube songs, no account needed. Paste a
// video or playlist link to save it; "Play all" adds them to the playlist.
Item {
    id: root

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacing

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.padding
            Layout.rightMargin: Theme.padding
            Layout.topMargin: Theme.spacing
            spacing: Theme.spacing

            TextField {
                id: field
                Layout.fillWidth: true
                implicitHeight: 44
                leftPadding: 42
                rightPadding: 16
                placeholderText: qsTr("Paste a YouTube video or playlist link")
                placeholderTextColor: Theme.textMuted
                color: Theme.text
                font.pixelSize: Theme.fontSize
                selectByMouse: true
                enabled: !YouTubeController.addingLink
                onAccepted: save()

                function save() {
                    if (text.trim() === "")
                        return
                    YouTubeController.addLink(text)
                    text = ""
                }

                background: Rectangle {
                    radius: height / 2
                    color: field.activeFocus ? Theme.fillStrong : Theme.fill
                    border.width: field.activeFocus ? 1 : 0
                    border.color: Theme.accent

                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                }

                Icon {
                    id: linkIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    name: YouTubeController.addingLink ? "refresh" : "link"
                    size: 13
                    color: field.activeFocus ? Theme.accent : Theme.textMuted

                    RotationAnimation on rotation {
                        running: YouTubeController.addingLink
                        from: 0
                        to: 360
                        duration: 1100
                        loops: Animation.Infinite
                        onRunningChanged: if (!running) linkIcon.rotation = 0
                    }
                }
            }

            PillButton {
                text: qsTr("Save")
                implicitHeight: 44
                enabled: field.text.trim() !== "" && !YouTubeController.addingLink
                onClicked: field.save()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.padding
            Layout.rightMargin: Theme.padding
            visible: YouTubeController.savedSongs.length > 0

            Label {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: YouTubeController.savedSongs.length === 1 ? qsTr("1 saved song")
                                                               : qsTr("%1 saved songs").arg(YouTubeController.savedSongs.length)
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeSmall
            }

            PillButton {
                filled: true
                iconName: "play"
                iconSize: 11
                text: qsTr("Play all")
                implicitHeight: 36
                onClicked: YouTubeController.playList(YouTubeController.savedSongs, 0, qsTr("Saved"))
            }
        }

        ListView {
            id: list
            populate: ListPopulate {}
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: YouTubeController.savedSongs
            boundsBehavior: Flickable.StopAtBounds
            flickDeceleration: Theme.flickDeceleration
            maximumFlickVelocity: Theme.flickVelocity
            synchronousDrag: true
            ScrollBar.vertical: ScrollBar {}

            delegate: YtTrackRow {
                id: row
                required property var modelData
                required property int index
                song: modelData
                showSave: false
                showRemove: true
                x: 4
                width: ListView.view.width - 8
                onRemoveRequested: YouTubeController.removeSaved(row.index)
            }

            YtStatus {
                anchors.centerIn: parent
                width: parent.width - 2 * Theme.padding
                emptyText: list.count === 0 && !YouTubeController.addingLink
                           ? qsTr("Paste YouTube links above, or use the bookmark button on any song, to build your own library. No account needed.")
                           : ""
            }
        }
    }
}
