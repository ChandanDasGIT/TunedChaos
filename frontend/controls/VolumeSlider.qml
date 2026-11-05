import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Mute toggle + volume slider + equalizer and mood buttons. The mouse
// wheel changes the volume by the step set in Settings.
RowLayout {
    id: root

    signal equalizerRequested()

    spacing: Theme.spacing / 2

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            const notches = event.angleDelta.y / 120
            PlayerController.muted = false
            PlayerController.volume = Math.max(0, Math.min(1,
                PlayerController.volume + notches * SettingsController.volumeStep / 100))
        }
    }

    ControlButton {
        iconName: PlayerController.muted || PlayerController.volume === 0 ? "volumeMute"
                : PlayerController.volume < 0.5 ? "volumeLow" : "volume"
        iconSize: 14
        onClicked: PlayerController.muted = !PlayerController.muted
    }

    ThemedSlider {
        Layout.fillWidth: true
        from: 0
        to: 1
        value: PlayerController.volume
        opacity: PlayerController.muted ? 0.5 : 1
        onMoved: PlayerController.volume = value
    }

    // Opens the equalizer (accent while it is on)
    ControlButton {
        iconName: "equalizer"
        iconSize: 13
        active: SettingsController.eqEnabled
        ToolTip.visible: hovered
        ToolTip.text: SettingsController.eqEnabled ? qsTr("Equalizer (on)") : qsTr("Equalizer")
        onClicked: root.equalizerRequested()
    }

    // Adds the song playing to a mood (accent once it is in one)
    ControlButton {
        id: heartButton
        iconName: "heart"
        iconSize: 13
        enabled: PlayerController.hasTrack
        active: MoodsController.currentMoods.length > 0
        ToolTip.visible: hovered
        ToolTip.text: qsTr("Add to a mood")
        onClicked: moodPicker.open()
    }

    // Which moods the song playing is in: in the middle of the window. Stays open
    // while moods are ticked (a song can be in several); outside it or Back closes it.
    Popup {
        id: moodPicker

        readonly property var emoji: ["😄", "😢", "🥱", "😨", "🤘", "💃"] // in MoodsController's order

        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(300, parent.width - 2 * Theme.padding)
        modal: true
        dim: true
        focus: true
        padding: Theme.spacing
        onAboutToShow: Util.openMenus += 1 // (Back only closes this: Main's goBack waits)
        onAboutToHide: Util.openMenus -= 1

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.anim }
            NumberAnimation { property: "scale"; from: 0.9; to: 1; duration: Theme.anim; easing.type: Theme.easing }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; to: 0; duration: Theme.animFast }
        }

        background: Rectangle {
            color: Theme.surfaceAlt
            border.color: Theme.border
            radius: Theme.radiusCard
        }

        contentItem: Column {
            spacing: 2

            Label {
                textFormat: Text.PlainText
                width: parent.width
                padding: Theme.spacing
                text: qsTr("Add to a mood")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSize
            }

            Repeater {
                model: MoodsController.moods

                delegate: AbstractButton {
                    id: moodRow

                    required property var modelData
                    required property int index
                    readonly property bool inMood: MoodsController.currentMoods.includes(modelData.id)

                    width: parent.width
                    height: 54
                    hoverEnabled: true
                    focusPolicy: Qt.NoFocus
                    onClicked: MoodsController.toggleCurrent(modelData.id)

                    background: Rectangle {
                        radius: Theme.radius
                        color: moodRow.inMood ? Theme.accentSoft : moodRow.hovered ? Theme.hover : "transparent"

                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    }

                    contentItem: RowLayout {
                        spacing: Theme.padding

                        Label {
                            textFormat: Text.PlainText
                            Layout.leftMargin: Theme.spacing
                            Layout.preferredWidth: 32
                            horizontalAlignment: Text.AlignHCenter
                            text: moodPicker.emoji[moodRow.index]
                            font.pixelSize: 24
                        }

                        Label {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: moodRow.modelData.name
                            color: moodRow.inMood ? Theme.accent : Theme.text
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: moodRow.inMood ? Font.DemiBold : Font.Medium
                            elide: Text.ElideRight
                        }

                        Icon {
                            Layout.rightMargin: Theme.padding
                            visible: moodRow.inMood
                            name: "check"
                            size: 14
                            color: Theme.accent
                        }
                    }
                }
            }
        }
    }
}
