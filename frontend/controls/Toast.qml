import QtQuick
import QtQuick.Controls

// Message that slides up from the bottom and fades away. Long ones wrap and
// stay up longer.
Rectangle {
    id: root

    property bool shown: false
    property real bottomOffset: Theme.padding * 1.5

    function show(text) {
        label.text = text
        shown = true
        timer.interval = Math.max(2600, text.length * 55)
        timer.restart()
    }

    anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
    anchors.bottom: parent ? parent.bottom : undefined
    anchors.bottomMargin: shown ? bottomOffset : -height
    width: Math.min((parent ? parent.width : 400) - 2 * Theme.padding, 460, label.implicitWidth + 36)
    height: label.height + 20
    radius: Math.min(height / 2, 18)
    color: Theme.surfaceAlt
    border.color: Theme.border
    opacity: shown ? 1 : 0
    z: 100

    Behavior on anchors.bottomMargin { NumberAnimation { duration: Theme.animSlow; easing.type: Theme.easingBack } }
    Behavior on opacity { NumberAnimation { duration: Theme.anim } }

    Label {
        id: label
        textFormat: Text.PlainText
        anchors.centerIn: parent
        width: Math.min(implicitWidth, root.width - 36)
        color: Theme.text
        font.pixelSize: Theme.fontSizeSmall
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
    }

    Timer {
        id: timer
        interval: 2600
        onTriggered: root.shown = false
    }
}
