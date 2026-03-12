import QtQuick 2.12
import Style 1.0
import MediaPlayerModel 1.0

NormalModeContentItem {
    id: playerRoot

    readonly property color spotifyGreen: "#1ed760"
    readonly property bool hostLibrary: MediaPlayerModel.currentArtist === "Host media"
    readonly property bool hasTrackDetails: MediaPlayerModel.currentSong !== "No media"
                                            || MediaPlayerModel.currentArtist !== "Bluetooth device"
    readonly property string sourceLabel: hostLibrary ? "Local playback" : "Spotify"
    readonly property string statusLabel: MediaPlayerModel.mediaPlayback
                                          ? "Playing now"
                                          : (hasTrackDetails ? "Paused on phone" : "Waiting for media")
    readonly property string spotifyLogoSource: "qrc:/images/media/spotify.svg"

    Item {
        anchors.fill: parent
        anchors.margins: 16

        Item {
            id: topRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 32

            Rectangle {
                anchors.left: parent.left
                height: 32
                width: spotifyPillRow.width + 24
                radius: 16
                color: Qt.rgba(0.06, 0.07, 0.09, 0.42)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.12)

                Row {
                    id: spotifyPillRow
                    anchors.centerIn: parent
                    spacing: 8

                    Image {
                        source: playerRoot.spotifyLogoSource
                        width: 14
                        height: 14
                        fillMode: Image.PreserveAspectFit
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "SPOTIFY"
                        color: Style.textPrimary
                        font.pixelSize: 11
                        font.bold: true
                        font.letterSpacing: 1.2
                    }
                }
            }

            Rectangle {
                anchors.right: parent.right
                height: 32
                width: statusLabelItem.implicitWidth + 24
                radius: 16
                color: Qt.rgba(0.06, 0.07, 0.09, 0.42)
                border.width: 1
                border.color: MediaPlayerModel.mediaPlayback ? Qt.rgba(0.12, 0.84, 0.38, 0.55)
                                                             : Qt.rgba(1, 1, 1, 0.12)

                Text {
                    id: statusLabelItem
                    anchors.centerIn: parent
                    text: playerRoot.statusLabel
                    color: MediaPlayerModel.mediaPlayback ? playerRoot.spotifyGreen : "#d3d6dc"
                    font.pixelSize: 11
                    font.bold: true
                }
            }
        }

        Item {
            id: ambientStage
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: topRow.bottom
            anchors.topMargin: 18
            height: 200

            Rectangle {
                width: MediaPlayerModel.mediaPlayback ? 238 : 206
                height: width
                radius: width / 2
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: logoFrame.verticalCenter
                color: MediaPlayerModel.mediaPlayback ? Qt.rgba(0.12, 0.84, 0.38, 0.10)
                                                      : Qt.rgba(1, 1, 1, 0.03)
                scale: MediaPlayerModel.mediaPlayback ? 1.0 : 0.92
                opacity: MediaPlayerModel.mediaPlayback ? 1.0 : 0.55

                SequentialAnimation on scale {
                    running: MediaPlayerModel.mediaPlayback && playerRoot.selected && playerRoot.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 1.08; duration: 1400; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 0.96; duration: 1400; easing.type: Easing.InOutQuad }
                }

                SequentialAnimation on opacity {
                    running: MediaPlayerModel.mediaPlayback && playerRoot.selected && playerRoot.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.34; duration: 1400; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 0.10; duration: 1400; easing.type: Easing.InOutQuad }
                }
            }

            Rectangle {
                width: 176
                height: 176
                radius: 88
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: logoFrame.verticalCenter
                color: "transparent"
                border.width: 1
                border.color: MediaPlayerModel.mediaPlayback ? Qt.rgba(0.12, 0.84, 0.38, 0.18)
                                                             : Qt.rgba(1, 1, 1, 0.08)
                scale: MediaPlayerModel.mediaPlayback ? 0.94 : 1.0
                opacity: MediaPlayerModel.mediaPlayback ? 0.9 : 0.45

                SequentialAnimation on scale {
                    running: MediaPlayerModel.mediaPlayback && playerRoot.selected && playerRoot.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 1.10; duration: 1800; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 0.94; duration: 1800; easing.type: Easing.InOutQuad }
                }

                SequentialAnimation on opacity {
                    running: MediaPlayerModel.mediaPlayback && playerRoot.selected && playerRoot.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.06; duration: 1800; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 0.24; duration: 1800; easing.type: Easing.InOutQuad }
                }
            }

            Rectangle {
                width: 132
                height: 132
                radius: 66
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: logoFrame.verticalCenter
                color: "transparent"
                border.width: 1
                border.color: MediaPlayerModel.mediaPlayback ? Qt.rgba(0.12, 0.84, 0.38, 0.18)
                                                             : Qt.rgba(1, 1, 1, 0.06)
            }

            Rectangle {
                id: logoFrame
                width: 104
                height: 104
                radius: 52
                anchors.horizontalCenter: parent.horizontalCenter
                y: 8
                color: Qt.rgba(0.06, 0.07, 0.09, 0.48)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.10)

                Rectangle {
                    anchors.centerIn: parent
                    width: 84
                    height: 84
                    radius: 42
                    color: MediaPlayerModel.mediaPlayback ? Qt.rgba(0.12, 0.84, 0.38, 0.18)
                                                          : Qt.rgba(1, 1, 1, 0.04)
                }

                Image {
                    anchors.centerIn: parent
                    source: playerRoot.spotifyLogoSource
                    width: 72
                    height: 72
                    fillMode: Image.PreserveAspectFit
                }
            }

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                spacing: 8

                Item {
                    width: parent.width
                    height: 48
                    clip: true

                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 20
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: MediaPlayerModel.currentSong
                        color: Style.textPrimary
                        font.pixelSize: 24
                        font.bold: true
                    }
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: MediaPlayerModel.currentArtist
                    color: "#b6bac2"
                    font.pixelSize: 16
                    elide: Text.ElideRight
                }
            }
        }

        Item {
            id: controlsArea
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: ambientStage.bottom
            anchors.topMargin: 8
            height: 78

            Row {
                anchors.centerIn: parent
                spacing: 18

                Item {
                    width: 52
                    height: 52
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Qt.rgba(0.06, 0.07, 0.09, 0.32)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, prevMouseArea.pressed ? 0.22 : 0.10)
                    }

                    Image {
                        anchors.centerIn: parent
                        source: "qrc:/images/media/skip-previous.svg"
                        width: 24
                        height: 24
                        opacity: prevMouseArea.pressed ? 0.70 : 0.96
                    }

                    MouseArea {
                        id: prevMouseArea
                        anchors.fill: parent
                        onClicked: MediaPlayerModel.previousSong()
                    }
                }

                Item {
                    width: 74
                    height: 74

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: playMouseArea.pressed ? "#19c258" : playerRoot.spotifyGreen

                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    Image {
                        anchors.centerIn: parent
                        source: MediaPlayerModel.mediaPlayback
                                ? "qrc:/images/media/pause.svg"
                                : "qrc:/images/media/play.svg"
                        width: 36
                        height: 36
                    }

                    MouseArea {
                        id: playMouseArea
                        anchors.fill: parent
                        onClicked: MediaPlayerModel.togglePlayback()
                    }
                }

                Item {
                    width: 52
                    height: 52
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Qt.rgba(0.06, 0.07, 0.09, 0.32)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, nextMouseArea.pressed ? 0.22 : 0.10)
                    }

                    Image {
                        anchors.centerIn: parent
                        source: "qrc:/images/media/skip-next.svg"
                        width: 24
                        height: 24
                        opacity: nextMouseArea.pressed ? 0.70 : 0.96
                    }

                    MouseArea {
                        id: nextMouseArea
                        anchors.fill: parent
                        onClicked: MediaPlayerModel.nextSong()
                    }
                }
            }
        }

        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 28

            Row {
                anchors.centerIn: parent
                spacing: 8

                Image {
                    source: "qrc:/images/others/bluetooth.png"
                    width: 12
                    height: 12
                    fillMode: Image.PreserveAspectFit
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !playerRoot.hostLibrary
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: playerRoot.sourceLabel
                    color: Style.textPrimary
                    font.pixelSize: 12
                    font.bold: true
                }

                Rectangle {
                    width: 4
                    height: 4
                    radius: 2
                    color: "#5f646d"
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: MediaPlayerModel.modeLabel
                    color: "#9ea4ad"
                    font.pixelSize: 12
                }
            }
        }
    }
}
