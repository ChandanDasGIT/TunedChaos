import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Library > Hosted library: the songs on a music server (Jellyfin for now).
// Signing in and browsing come next; until then it says so.
Item {
    id: root

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 2 * Theme.padding, 360)
        spacing: Theme.spacing

        Icon {
            Layout.alignment: Qt.AlignHCenter
            name: "cloud"
            size: 32
            color: Theme.textDim
        }

        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: qsTr("No server yet")
            color: Theme.text
            font.pixelSize: Theme.fontSizeLarge
        }

        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: qsTr("Connecting a Jellyfin server comes in the next update.")
            color: Theme.textMuted
            font.pixelSize: Theme.fontSize
            wrapMode: Text.WordWrap
        }
    }
}
