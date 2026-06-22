import QtQuick 2.12
import Style 1.0
import MediaPlayerModel 1.0

NormalModeContentItem {
    id: playerRoot

    readonly property color accentGreen: "#1ed760"
    readonly property color accentDim: "#2d3440"
    readonly property bool hostLibrary: MediaPlayerModel.currentArtist === "Host media"
    readonly property bool hasTrackDetails: MediaPlayerModel.currentSong !== "No media"
                                            || MediaPlayerModel.currentArtist !== "Bluetooth device"
    readonly property bool btConnected: MediaPlayerModel.mediaAvailable
    readonly property string statusLabel: MediaPlayerModel.mediaPlayback
                                          ? "Playing"
                                          : (hasTrackDetails ? "Paused" : "No media")
    readonly property string spotifyLogoSource: "qrc:/images/media/spotify.svg"

    Item {
        anchors.fill: parent
        anchors.margins: 14

        // ── Top status bar ──────────────────────────────────────────
        Item {
            id: topBar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 34

            // Source badge (left)
            Rectangle {
                id: sourceBadge
                anchors.left: parent.left
                height: 28
                width: sourcePillRow.width + 20
                radius: 14
                color: Qt.rgba(0.06, 0.07, 0.09, 0.55)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.13)

                Row {
                    id: sourcePillRow
                    anchors.centerIn: parent
                    spacing: 7

                    Image {
                        source: playerRoot.spotifyLogoSource
                        width: 13
                        height: 13
                        fillMode: Image.PreserveAspectFit
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "SPOTIFY"
                        color: Style.textPrimary
                        font.pixelSize: 10
                        font.bold: true
                        font.letterSpacing: 1.4
                    }
                }
            }

            // Playback status badge (right)
            Rectangle {
                anchors.right: parent.right
                height: 28
                width: statusText.implicitWidth + 20
                radius: 14
                color: Qt.rgba(0.06, 0.07, 0.09, 0.55)
                border.width: 1
                border.color: {
                    if (MediaPlayerModel.mediaPlayback) return Qt.rgba(0.12, 0.84, 0.38, 0.55)
                    if (playerRoot.btConnected) return Qt.rgba(0.33, 0.56, 1.0, 0.40)
                    return Qt.rgba(1, 1, 1, 0.12)
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    // Bluetooth indicator dot
                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        anchors.verticalCenter: parent.verticalCenter
                        color: {
                            if (!playerRoot.hostLibrary) {
                                if (MediaPlayerModel.mediaPlayback) return playerRoot.accentGreen
                                if (playerRoot.btConnected) return "#5590ff"
                                return "#6b7280"
                            }
                            return "transparent"
                        }

                        SequentialAnimation on opacity {
                            running: MediaPlayerModel.mediaPlayback && !playerRoot.hostLibrary
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.3; duration: 900; easing.type: Easing.InOutQuad }
                            NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutQuad }
                        }
                    }

                    Text {
                        id: statusText
                        anchors.verticalCenter: parent.verticalCenter
                        text: playerRoot.statusLabel
                        color: {
                            if (MediaPlayerModel.mediaPlayback) return playerRoot.accentGreen
                            if (playerRoot.btConnected) return "#8ab4ff"
                            return "#8a8f98"
                        }
                        font.pixelSize: 10
                        font.bold: true
                        font.letterSpacing: 0.8
                    }
                }
            }
        }

        // ── Album art / ambient area ─────────────────────────────────
        Item {
            id: artArea
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: topBar.bottom
            anchors.topMargin: 14
            height: 182

            // Outer pulse ring
            Rectangle {
                width: MediaPlayerModel.mediaPlayback ? 220 : 190
                height: width
                radius: width / 2
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: artFrame.verticalCenter
                color: MediaPlayerModel.mediaPlayback ? Qt.rgba(0.12, 0.84, 0.38, 0.09)
                                                      : Qt.rgba(1, 1, 1, 0.025)

                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

                SequentialAnimation on scale {
                    running: MediaPlayerModel.mediaPlayback && playerRoot.selected && playerRoot.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 1.07; duration: 1500; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 0.96; duration: 1500; easing.type: Easing.InOutQuad }
                }

                SequentialAnimation on opacity {
                    running: MediaPlayerModel.mediaPlayback && playerRoot.selected && playerRoot.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.28; duration: 1500; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 0.08; duration: 1500; easing.type: Easing.InOutQuad }
                }
            }

            // Inner ring
            Rectangle {
                width: 160
                height: 160
                radius: 80
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: artFrame.verticalCenter
                color: "transparent"
                border.width: 1
                border.color: MediaPlayerModel.mediaPlayback ? Qt.rgba(0.12, 0.84, 0.38, 0.20)
                                                             : Qt.rgba(1, 1, 1, 0.07)

                SequentialAnimation on scale {
                    running: MediaPlayerModel.mediaPlayback && playerRoot.selected && playerRoot.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 1.09; duration: 1900; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 0.95; duration: 1900; easing.type: Easing.InOutQuad }
                }
            }

            // Art frame circle
            Rectangle {
                id: artFrame
                width: 100
                height: 100
                radius: 50
                anchors.horizontalCenter: parent.horizontalCenter
                y: 6
                color: Qt.rgba(0.07, 0.09, 0.12, 0.60)
                border.width: 1
                border.color: MediaPlayerModel.mediaPlayback ? Qt.rgba(0.12, 0.84, 0.38, 0.25)
                                                             : Qt.rgba(1, 1, 1, 0.10)

                Rectangle {
                    anchors.centerIn: parent
                    width: 80
                    height: 80
                    radius: 40
                    color: MediaPlayerModel.mediaPlayback ? Qt.rgba(0.12, 0.84, 0.38, 0.16)
                                                          : Qt.rgba(1, 1, 1, 0.04)
                }

                Image {
                    anchors.centerIn: parent
                    source: playerRoot.spotifyLogoSource
                    width: 68
                    height: 68
                    fillMode: Image.PreserveAspectFit
                    opacity: MediaPlayerModel.mediaPlayback ? 1.0 : 0.55

                    Behavior on opacity { NumberAnimation { duration: 300 } }
                }
            }

            // Track info below art
            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                spacing: 4

                // Song title
                Text {
                    id: songTitleText
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: MediaPlayerModel.currentSong
                    color: Style.textPrimary
                    font.pixelSize: 20
                    font.bold: true
                    elide: Text.ElideRight
                    opacity: playerRoot.hasTrackDetails ? 1.0 : 0.45

                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }

                // Artist
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: MediaPlayerModel.currentArtist
                    color: playerRoot.hasTrackDetails ? "#9ea4b0" : "#5f6470"
                    font.pixelSize: 14
                    elide: Text.ElideRight
                }
            }
        }

        // ── Playback controls ────────────────────────────────────────
        Item {
            id: controlsArea
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: artArea.bottom
            anchors.topMargin: 6
            height: 74

            Row {
                anchors.centerIn: parent
                spacing: 16

                // Previous
                Item {
                    width: 50
                    height: 50
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: prevMouseArea.pressed ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0.06, 0.07, 0.09, 0.35)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, prevMouseArea.pressed ? 0.20 : 0.10)

                        Behavior on color { ColorAnimation { duration: 100 } }
                    }

                    Image {
                        anchors.centerIn: parent
                        source: "qrc:/images/media/skip-previous.svg"
                        width: 22
                        height: 22
                        opacity: prevMouseArea.pressed ? 0.65 : 0.92
                    }

                    MouseArea {
                        id: prevMouseArea
                        anchors.fill: parent
                        onClicked: MediaPlayerModel.previousSong()
                    }
                }

                // Play / Pause (main button)
                Item {
                    width: 72
                    height: 72

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: playMouseArea.pressed ? "#18c254" : playerRoot.accentGreen

                        Behavior on color { ColorAnimation { duration: 110 } }
                    }

                    Image {
                        anchors.centerIn: parent
                        source: MediaPlayerModel.mediaPlayback
                                ? "qrc:/images/media/pause.svg"
                                : "qrc:/images/media/play.svg"
                        width: 34
                        height: 34
                    }

                    MouseArea {
                        id: playMouseArea
                        anchors.fill: parent
                        onClicked: MediaPlayerModel.togglePlayback()
                    }
                }

                // Next
                Item {
                    width: 50
                    height: 50
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: nextMouseArea.pressed ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0.06, 0.07, 0.09, 0.35)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, nextMouseArea.pressed ? 0.20 : 0.10)

                        Behavior on color { ColorAnimation { duration: 100 } }
                    }

                    Image {
                        anchors.centerIn: parent
                        source: "qrc:/images/media/skip-next.svg"
                        width: 22
                        height: 22
                        opacity: nextMouseArea.pressed ? 0.65 : 0.92
                    }

                    MouseArea {
                        id: nextMouseArea
                        anchors.fill: parent
                        onClicked: MediaPlayerModel.nextSong()
                    }
                }
            }
        }

        // ── Footer: source + connection info ────────────────────────
        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 26

            Row {
                anchors.centerIn: parent
                spacing: 7

                Image {
                    source: "qrc:/images/others/bluetooth.png"
                    width: 11
                    height: 11
                    fillMode: Image.PreserveAspectFit
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !playerRoot.hostLibrary
                    opacity: playerRoot.btConnected ? 0.85 : 0.35
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: playerRoot.hostLibrary ? "Local" : (playerRoot.btConnected ? "Connected" : "No device")
                    color: playerRoot.btConnected ? "#c8ced8" : "#5f6470"
                    font.pixelSize: 11
                    font.bold: true
                }

                Rectangle {
                    width: 3
                    height: 3
                    radius: 1.5
                    color: "#4a505a"
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: MediaPlayerModel.modeLabel
                    color: "#4a505a"
                    font.pixelSize: 11
                }
            }
        }
    }
}
