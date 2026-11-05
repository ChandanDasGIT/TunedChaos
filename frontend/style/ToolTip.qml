import QtQuick
import QtQuick.Templates as T

// The app's tooltip (ChaoticStyle; every other control falls back to Basic).
// Dark rounded card above the control, appears after a short pause with a
// small pop, wraps long text. Colors come from the window's palette, which
// Main.qml sets from Theme (a style module can't import the app module).
T.ToolTip {
    id: control

    x: parent ? (parent.width - implicitWidth) / 2 : 0
    y: -implicitHeight - 6

    implicitWidth: Math.min(260, Math.max(implicitBackgroundWidth + leftInset + rightInset,
                                          contentItem.implicitWidth + leftPadding + rightPadding))
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             contentItem.implicitHeight + topPadding + bottomPadding)

    margins: 8
    topPadding: 6
    bottomPadding: 6
    leftPadding: 12
    rightPadding: 12

    closePolicy: T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutsideParent | T.Popup.CloseOnReleaseOutsideParent

    // A short pause before it appears, so passing over buttons doesn't flash tooltips.
    enter: Transition {
        SequentialAnimation {
            PropertyAction { property: "opacity"; value: 0 }
            PauseAnimation { duration: 350 }
            ParallelAnimation {
                NumberAnimation { property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.88; to: 1; duration: 200; easing.type: Easing.OutBack }
            }
        }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; to: 0; duration: 100 }
    }

    readonly property Item noInput: Item {} // no area: contains no point

    // Phones: a tap counts as hovering, so tooltips would pop up on every
    // touch. None there.
    readonly property bool touchOnly: Qt.platform.os === "android" || Qt.platform.os === "ios"
    onOpened: if (touchOnly) close()

    contentItem: Text {
        textFormat: Text.PlainText
        visible: !control.touchOnly
        text: control.text
        font.pixelSize: 12
        color: control.palette.toolTipText
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
    }

    background: Rectangle {
        visible: !control.touchOnly
        // Never take the pointer: near the window's top Qt squeezes the tooltip
        // over its control, and a click there must still reach the control.
        onParentChanged: if (parent) parent.containmentMask = control.noInput

        color: control.palette.toolTipBase
        radius: 9
        border.color: Qt.rgba(control.palette.toolTipText.r, control.palette.toolTipText.g,
                              control.palette.toolTipText.b, 0.18)
    }
}
