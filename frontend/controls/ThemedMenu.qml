pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

// The app's menu look: dark rounded card, icon + text rows, a chevron on
// submenus, quick fade/scale. Use Actions (icon.name = an Icon name).
Menu {
    id: root

    // Counted while open, so Esc / Back only closes the menu (Main's goBack waits).
    property bool countedOpen: false
    function setCountedOpen(open) {
        if (open !== countedOpen) {
            countedOpen = open
            Util.openMenus += open ? 1 : -1
        }
    }
    onAboutToShow: {
        setCountedOpen(true)
        // Phones: closing hands focus back, and a search box getting it reopens the keyboard.
        if (Theme.touchOnly) {
            const focused = Overlay.overlay.Window.activeFocusItem
            if (focused && "cursorPosition" in focused)
                focused.focus = false
        }
    }
    onAboutToHide: setCountedOpen(false)
    Component.onDestruction: setCountedOpen(false)

    padding: 4

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animFast }
        NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: Theme.anim; easing.type: Theme.easing }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; to: 0; duration: Theme.animFast }
    }

    background: Rectangle {
        implicitWidth: 230
        color: Theme.surfaceAlt
        border.color: Theme.border
        radius: Theme.radiusLarge
    }

    delegate: MenuItem {
        id: item

        implicitHeight: 34

        contentItem: Item {
            Icon {
                id: itemIcon
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                name: item.subMenu ? "listMusic" : item.icon.name
                size: 12
                color: item.enabled ? Theme.textMuted : Theme.textDim
            }

            Label {
                textFormat: Text.PlainText
                anchors.left: itemIcon.right
                anchors.leftMargin: Theme.spacing
                anchors.right: chevron.left
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                text: item.text
                color: item.enabled ? Theme.text : Theme.textDim
                font.pixelSize: Theme.fontSize
                elide: Text.ElideRight
            }

            Icon {
                id: chevron
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                visible: item.subMenu !== null
                width: visible ? 10 : 0
                name: "chevronRight"
                size: 9
                color: Theme.textMuted
            }
        }

        arrow: null
        indicator: null

        background: Rectangle {
            radius: Theme.radius
            color: item.highlighted ? Theme.hover : "transparent"

            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }
    }
}
