import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Small dialog asking for a name (new playlist / rename).
Popup {
    id: root

    property string title
    signal accepted(string name)

    function ask(dialogTitle, initialName) {
        title = dialogTitle
        field.text = initialName
        open()
        field.forceActiveFocus()
        field.selectAll()
    }

    function accept() {
        if (field.text.trim() === "")
            return
        root.accepted(field.text.trim())
        close()
    }

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Util.dialogY(parent.height, height)
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
            text: root.title
            color: Theme.text
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.DemiBold
        }

        TextField {
            id: field
            Layout.fillWidth: true
            implicitHeight: 42
            leftPadding: 16
            rightPadding: 16
            color: Theme.text
            font.pixelSize: Theme.fontSize
            selectByMouse: true
            onAccepted: root.accept()

            background: Rectangle {
                radius: height / 2
                color: Theme.fillStrong
                border.width: field.activeFocus ? 1 : 0
                border.color: Theme.accent
            }
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
                filled: true
                text: qsTr("OK")
                implicitHeight: 36
                enabled: field.text.trim() !== ""
                onClicked: root.accept()
            }
        }
    }
}
