import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// What Library opens on: the songs on this device, or a music server.
Item {
    id: root

    signal chosen(string source) // "local" or "hosted"

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.padding
        spacing: Theme.padding

        SourceCard {
            icon: "folder"
            title: qsTr("Local library")
            subtitle: LocalLibraryController.songCount > 0
                      ? qsTr("%1 on this device").arg(Util.songCount(LocalLibraryController.songCount))
                      : qsTr("Songs in your music folders")
            onTapped: root.chosen("local")
        }

        SourceCard {
            icon: "cloud"
            title: qsTr("Hosted library")
            subtitle: qsTr("Your music server, like Jellyfin")
            onTapped: root.chosen("hosted")
        }

        Item { Layout.fillHeight: true }
    }

    component SourceCard: Rectangle {
        id: card

        required property string icon
        required property string title
        required property string subtitle

        signal tapped()

        Layout.fillWidth: true
        Layout.preferredHeight: 96
        radius: Theme.radiusLarge
        color: cardHover.hovered ? Theme.hover : Theme.fillSoft
        border.color: Theme.border

        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        HoverHandler { id: cardHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: card.tapped() }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.padding + 4
            anchors.rightMargin: Theme.padding + 4
            spacing: Theme.padding + 4

            Rectangle {
                Layout.preferredWidth: 52
                Layout.preferredHeight: 52
                radius: Theme.radiusLarge
                color: Theme.accentSoft

                Icon {
                    anchors.centerIn: parent
                    name: card.icon
                    size: 20
                    color: Theme.accent
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Label {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: card.title
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Label {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: card.subtitle
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSize
                    elide: Text.ElideRight
                }
            }

            Icon {
                name: "chevronRight"
                size: 12
                color: Theme.textDim
            }
        }
    }
}
