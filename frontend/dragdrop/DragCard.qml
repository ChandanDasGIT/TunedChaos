import QtQuick
import QtQuick.Layouts

// The card following the pointer while songs are dragged: cover, title and
// what it is ("12 songs", the artist...). Stays inside its parent (the window).
Rectangle {
    id: root

    readonly property real offset: 14 // beside the pointer, not under it

    x: Math.min(SongDrag.scenePos.x + offset, parent.width - width - 4)
    y: Math.min(SongDrag.scenePos.y + offset, parent.height - height - 4)
    width: Math.min(280, row.implicitWidth + 2 * Theme.spacing)
    height: 56
    radius: Theme.radiusLarge
    color: Theme.surfaceAlt
    border.color: Theme.border
    opacity: SongDrag.active ? 0.96 : 0
    scale: SongDrag.active ? 1 : 0.9
    visible: opacity > 0

    Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
    Behavior on scale { NumberAnimation { duration: Theme.anim; easing.type: Theme.easing } }

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.margins: Theme.spacing
        spacing: Theme.spacing

        Rectangle {
            Layout.preferredWidth: 40
            Layout.preferredHeight: 40
            radius: Theme.radius
            color: Theme.surface
            clip: true

            Icon {
                anchors.centerIn: parent
                name: SongDrag.browseId !== "" || SongDrag.items.length > 1 ? "listMusic" : "music"
                size: 13
                color: Theme.textDim
            }

            Image {
                anchors.fill: parent
                source: SongDrag.cover
                sourceSize: Qt.size(80, 80)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                opacity: status === Image.Ready ? 1 : 0
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.maximumWidth: 200
            spacing: 1

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: SongDrag.title
                elide: Text.ElideRight
                color: Theme.text
                font.pixelSize: Theme.fontSize
                font.weight: Font.DemiBold
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                visible: text !== ""
                text: SongDrag.subtitle
                elide: Text.ElideRight
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }
}
