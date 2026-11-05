import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// "Are you sure?" dialog with a red confirm button.
Popup {
    id: root

    property string title
    property string message
    property string confirmText: qsTr("Delete")
    signal confirmed()

    function ask(dialogTitle, dialogMessage) {
        title = dialogTitle
        message = dialogMessage
        open()
    }

    anchors.centerIn: Overlay.overlay
    width: Math.min(Overlay.overlay ? Overlay.overlay.width - 2 * Theme.padding : 380, 380)
    modal: true
    onVisibleChanged: Util.openDialogs += visible ? 1 : -1
    focus: true
    padding: Theme.padding * 1.5
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.anim }
        NumberAnimation { property: "scale"; from: 0.92; to: 1; duration: Theme.anim; easing.type: Theme.easingBack }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; to: 0; duration: Theme.animFast }
        NumberAnimation { property: "scale"; to: 0.96; duration: Theme.animFast }
    }

    background: Rectangle {
        color: Theme.surface
        radius: Theme.radiusLarge * 1.5
        border.color: Theme.border
    }

    Overlay.modal: Rectangle {
        color: Theme.scrim
        Behavior on opacity { NumberAnimation { duration: Theme.anim } }
    }

    contentItem: ColumnLayout {
        spacing: Theme.padding

        Label {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.title
            color: Theme.text
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
        }

        Label {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.message
            color: Theme.textMuted
            font.pixelSize: Theme.fontSize
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: Theme.spacing

            PillButton {
                text: qsTr("Cancel")
                implicitHeight: 36
                onClicked: root.close()
            }

            PillButton {
                text: root.confirmText
                implicitHeight: 36
                iconColor: Theme.background
                onClicked: {
                    root.confirmed()
                    root.close()
                }

                background: Rectangle {
                    radius: height / 2
                    color: Theme.error
                }
            }
        }
    }
}
