import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Library > Hosted library: sign in to a music server (Jellyfin), then its
// songs, albums, artists and playlists (HostedController).
Item {
    id: root

    property int tab: HostedController.SongsTab
    readonly property var tabLists: [HostedController.songs, HostedController.albums,
                                     HostedController.artists, HostedController.playlists]

    onVisibleChanged: if (visible) HostedController.load(tab)
    onTabChanged: {
        HostedController.closeDetail()
        HostedController.load(tab)
    }
    Connections {
        target: HostedController
        function onAccountChanged() { if (root.visible) HostedController.load(root.tab) }
    }

    // ---------------------------------------------------------------- signing in
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.padding
        visible: !HostedController.signedIn
        spacing: Theme.spacing

        Label {
            Layout.fillWidth: true
            text: qsTr("Connect your Jellyfin server")
            color: Theme.text
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.DemiBold
        }

        Label {
            Layout.fillWidth: true
            text: qsTr("Its songs play here like your own. Your password is only used to sign in; it isn't kept.")
            color: Theme.textMuted
            font.pixelSize: Theme.fontSize
            wrapMode: Text.WordWrap
        }

        FormField {
            id: serverField
            placeholderText: qsTr("Server address, e.g. http://192.168.1.10:8096")
            inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
            onAccepted: userField.forceActiveFocus()
        }

        FormField {
            id: userField
            placeholderText: qsTr("User name")
            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
            onAccepted: passwordField.forceActiveFocus()
        }

        FormField {
            id: passwordField
            placeholderText: qsTr("Password")
            echoMode: TextInput.Password
            onAccepted: signInButton.clicked()
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing

            Label {
                Layout.fillWidth: true
                text: HostedController.busy ? qsTr("Connecting…") : HostedController.error
                color: HostedController.busy ? Theme.textMuted : Theme.error
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            PillButton {
                id: signInButton
                filled: true
                text: qsTr("Sign in")
                implicitHeight: 36
                enabled: !HostedController.busy && serverField.text.trim() !== "" && userField.text.trim() !== ""
                onClicked: {
                    HostedController.signIn(serverField.text.trim(), userField.text.trim(), passwordField.text)
                    passwordField.text = ""
                }
            }
        }

        Item { Layout.fillHeight: true }
    }

    // ---------------------------------------------------------------- signed in
    ColumnLayout {
        anchors.fill: parent
        visible: HostedController.signedIn
        spacing: 0

        // Which server, and signing out
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.padding
            Layout.rightMargin: Theme.padding
            Layout.topMargin: Theme.spacing
            spacing: Theme.spacing

            Icon {
                name: "cloud"
                size: 12
                color: Theme.accent
            }

            Label {
                Layout.fillWidth: true
                text: HostedController.serverName + "  ·  " + HostedController.userName
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideRight
            }

            ControlButton {
                iconName: "refresh"
                iconSize: 12
                iconColor: HostedController.busy ? Theme.accent : Theme.textMuted
                enabled: !HostedController.busy
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Load again from the server")
                onClicked: HostedController.refresh(root.tab)
            }

            PillButton {
                text: qsTr("Sign out")
                implicitHeight: 28
                onClicked: HostedController.signOut()
            }
        }

        TabRow {
            Layout.fillWidth: true
            Layout.margins: Theme.padding
            Layout.bottomMargin: 4
            current: root.tab
            tabs: [
                { icon: "music", label: qsTr("Songs") },
                { icon: "compactDisc", label: qsTr("Albums") },
                { icon: "user", label: qsTr("Artists") },
                { icon: "listMusic", label: qsTr("Playlists") }
            ]
            onTabPicked: (index) => root.tab = index
        }

        Label {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.padding
            Layout.rightMargin: Theme.padding
            visible: text !== ""
            text: HostedController.error !== "" ? HostedController.error
                : HostedController.busy ? qsTr("Loading…") : ""
            color: HostedController.error !== "" ? Theme.error : Theme.textMuted
            font.pixelSize: Theme.fontSizeSmall
            wrapMode: Text.WordWrap
        }

        // Songs, or the list of albums / artists / playlists
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: Theme.spacing
            Layout.rightMargin: Theme.spacing
            visible: !HostedController.detailOpen
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            flickDeceleration: Theme.flickDeceleration
            maximumFlickVelocity: Theme.flickVelocity
            model: root.tabLists[root.tab]
            ScrollBar.vertical: ScrollBar {}

            delegate: HostedRow {
                required property var modelData
                required property int index

                width: ListView.view.width
                thumbnail: modelData.thumbnail || ""
                title: root.tab === HostedController.SongsTab ? modelData.title : modelData.name
                subtitle: root.tab === HostedController.SongsTab
                          ? [modelData.artist, modelData.album].filter(s => s).join("  ·  ")
                          : modelData.subtitle
                duration: root.tab === HostedController.SongsTab ? modelData.durationMs : -1
                playing: root.tab === HostedController.SongsTab && modelData.path === PlayerController.source
                onTapped: root.tab === HostedController.SongsTab
                          ? HostedController.play(false, index)
                          : HostedController.open(root.tab, modelData.id, modelData.name, modelData.thumbnail)
                onQueueRequested: HostedController.addToQueue(false, index)
            }
        }

        // An opened album / artist / playlist
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: HostedController.detailOpen
            spacing: Theme.spacing

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacing
                Layout.rightMargin: Theme.padding
                spacing: Theme.spacing

                ControlButton {
                    iconName: "back"
                    iconSize: 13
                    iconColor: Theme.textMuted
                    onClicked: HostedController.closeDetail()
                }

                Label {
                    Layout.fillWidth: true
                    text: HostedController.detailTitle
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                PillButton {
                    filled: true
                    iconName: "play"
                    iconSize: 11
                    text: qsTr("Play")
                    implicitHeight: 32
                    enabled: HostedController.detailSongs.length > 0
                    onClicked: HostedController.play(true, 0)
                }
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: Theme.spacing
                Layout.rightMargin: Theme.spacing
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                flickDeceleration: Theme.flickDeceleration
                maximumFlickVelocity: Theme.flickVelocity
                model: HostedController.detailSongs
                ScrollBar.vertical: ScrollBar {}

                delegate: HostedRow {
                    required property var modelData
                    required property int index

                    width: ListView.view.width
                    thumbnail: modelData.thumbnail || ""
                    title: modelData.title
                    subtitle: [modelData.artist, modelData.album].filter(s => s).join("  ·  ")
                    duration: modelData.durationMs
                    playing: modelData.path === PlayerController.source
                    onTapped: HostedController.play(true, index)
                    onQueueRequested: HostedController.addToQueue(true, index)
                }
            }
        }
    }

    component FormField: TextField {
        Layout.fillWidth: true
        implicitHeight: 42
        color: Theme.text
        placeholderTextColor: Theme.textMuted
        font.pixelSize: Theme.fontSize
        leftPadding: Theme.padding
        background: Rectangle {
            radius: Theme.radius
            color: Theme.fillSoft
            border.color: parent.activeFocus ? Theme.accent : Theme.border
        }
    }
}
