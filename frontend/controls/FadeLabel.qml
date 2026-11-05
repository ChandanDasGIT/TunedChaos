import QtQuick
import QtQuick.Controls

// A label that fades and slides to its new text instead of switching instantly
// (track title / artist in the now-playing panel).
Item {
    id: root

    property string text
    property alias color: label.color
    property alias font: label.font
    property alias horizontalAlignment: label.horizontalAlignment

    property string shownText

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight

    Component.onCompleted: shownText = text
    onTextChanged: swap.restart()

    Label {
        id: label
        textFormat: Text.PlainText
        width: parent.width
        text: root.shownText
        elide: Text.ElideRight
        transform: Translate { id: shift }
    }

    SequentialAnimation {
        id: swap

        ParallelAnimation {
            NumberAnimation { target: label; property: "opacity"; to: 0; duration: Theme.animFast }
            NumberAnimation { target: shift; property: "y"; to: -6; duration: Theme.animFast }
        }
        ScriptAction {
            script: {
                root.shownText = root.text
                shift.y = 6
            }
        }
        ParallelAnimation {
            NumberAnimation { target: label; property: "opacity"; to: 1; duration: Theme.anim }
            NumberAnimation { target: shift; property: "y"; to: 0; duration: Theme.anim; easing.type: Theme.easing }
        }
    }
}
