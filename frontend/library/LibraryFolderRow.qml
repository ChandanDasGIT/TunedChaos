import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// One folder in the Folders tab, as a file manager lists it: folder icon,
// name, how many songs are in it (and where it is, for a music folder), ">".
// A click opens it; hold and drag to drop all its songs on the Queue or the player.
Rectangle {
    id: root

    required property string name
    required property string path
    required property int count
    property string location: "" // shown under the name (the music folders)
    property string coverPath: "" // a song in it with a cover: shown instead of the folder icon

    signal opened()

    implicitHeight: 52
    radius: Theme.radius
    color: hover.hovered ? Theme.hover : "transparent"

    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        onTapped: root.opened()
    }

    DragSource {
        payload: function() {
            return { items: LocalLibraryController.folderItems(root.path), title: root.name,
                     subtitle: Util.songCount(root.count) }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 12
        spacing: Theme.padding

        Rectangle {
            Layout.preferredWidth: 40
            Layout.preferredHeight: 40
            radius: Theme.radius
            color: Theme.accentSoft
            clip: true

            Icon {
                anchors.centerIn: parent
                name: "folder"
                size: 15
                color: Theme.accent
            }

            Image {
                anchors.fill: parent
                visible: root.coverPath !== ""
                source: root.coverPath !== "" ? Util.coverSource(root.coverPath, "") : ""
                sourceSize: Qt.size(80, 80)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                opacity: status === Image.Ready ? 1 : 0
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            Label {
                Layout.fillWidth: true
                text: root.name
                color: Theme.text
                font.pixelSize: Theme.fontSize
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Label {
                Layout.fillWidth: true
                text: root.location !== "" ? Util.songCount(root.count) + "  ·  " + root.location
                                           : Util.songCount(root.count)
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideMiddle
            }
        }

        Icon {
            name: "chevronRight"
            size: 11
            color: Theme.textDim
        }
    }
}
