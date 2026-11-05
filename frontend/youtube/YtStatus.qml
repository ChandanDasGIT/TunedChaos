import QtQuick
import QtQuick.Controls

// Loading / error / empty message for the YouTube tabs.
Column {
    id: root

    property bool loading: false
    property string loadingText
    property string errorText
    property string emptyText

    signal retry()

    spacing: Theme.spacing
    visible: loading || errorText !== "" || emptyText !== ""

    Icon {
        id: statusIcon
        anchors.horizontalCenter: parent.horizontalCenter
        name: root.errorText !== "" ? "cloud" : "refresh"
        size: 24
        color: root.errorText !== "" ? Theme.error : Theme.textMuted

        RotationAnimation on rotation {
            running: root.loading
            from: 0
            to: 360
            duration: 1100
            loops: Animation.Infinite
            onRunningChanged: if (!running) statusIcon.rotation = 0
        }
    }

    Label {
        textFormat: Text.PlainText
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: root.loading ? root.loadingText : root.errorText !== "" ? root.errorText : root.emptyText
        color: root.errorText !== "" ? Theme.text : Theme.textMuted
        font.pixelSize: Theme.fontSize
    }

    PillButton {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: !root.loading && root.errorText !== ""
        text: qsTr("Try again")
        implicitHeight: 34
        onClicked: root.retry()
    }
}
