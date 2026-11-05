import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A song on Home: cover, title, artist and a note on the right ("12 plays",
// "21:40"). A click plays it (with the list it's in); hold and drag to drop it
// on the Queue or the player. With `removable`, an × (on hover; always on a
// phone) removes it. `song` is a HistoryController song map.
Rectangle {
    id: root

    required property var song
    property string note: ""
    property bool removable: false
    property string removeTip: qsTr("Remove from history")
    readonly property bool isCurrent: PlayerController.source === (song.path || "")

    signal clicked()
    signal removeRequested()

    implicitHeight: 52
    radius: Theme.radius
    color: isCurrent ? (hover.hovered ? Theme.currentRowHover : Theme.currentRow)
         : hover.hovered ? Theme.hover : "transparent"

    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        onTapped: root.clicked()
    }

    DragSource {
        payload: function() {
            return { items: [root.song.item], title: root.song.title, subtitle: root.song.artist,
                     cover: Util.coverSource(root.song.path, root.song.thumbnail) }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 10
        spacing: Theme.padding

        Rectangle {
            Layout.preferredWidth: 40
            Layout.preferredHeight: 40
            radius: Theme.radius
            color: Theme.surfaceAlt
            clip: true

            Icon {
                anchors.centerIn: parent
                name: "music"
                size: 13
                color: Theme.textDim
            }

            Image {
                anchors.fill: parent
                source: Util.coverSource(root.song.path, root.song.thumbnail)
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
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.song.title
                color: root.isCurrent ? Theme.accent : Theme.text
                font.pixelSize: Theme.fontSize
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Label {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                visible: text !== ""
                text: root.song.artist
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideRight
            }
        }

        Label {
            textFormat: Text.PlainText
            visible: root.note !== ""
            text: root.note
            color: Theme.textMuted
            font.pixelSize: Theme.fontSizeSmall
        }

        PillButton {
            visible: root.removable
            iconName: "close"
            iconSize: 10
            implicitWidth: 28
            implicitHeight: 28
            transparentIdle: true
            opacity: hover.hovered || Theme.touchOnly ? 1 : 0 // (no hovering on a phone)
            ToolTip.visible: hovered
            ToolTip.text: root.removeTip
            onClicked: root.removeRequested()

            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
        }
    }
}
