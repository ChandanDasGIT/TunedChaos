import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// One setting: title + description on the left, its control on the right.
RowLayout {
    id: root

    readonly property bool settingsRow: true // (Settings search)
    property string title
    property string description
    default property alias control: holder.data

    spacing: Theme.padding

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        Label {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            visible: root.title !== ""
            text: root.title
            color: Theme.text
            font.pixelSize: Theme.fontSize
            wrapMode: Text.WordWrap
        }

        Label {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            visible: root.description !== ""
            text: root.description
            color: Theme.textMuted
            font.pixelSize: Theme.fontSizeSmall
            wrapMode: Text.WordWrap
        }
    }

    Item {
        id: holder
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
    }
}
