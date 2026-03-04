import QtQuick 2.12
import Style 1.0
import MediaPlayerModel 1.0
import NormalModeModel 1.0

NormalModeContentItem {
    id: playerRoot

    /* === Song Title === */
    Text {
        id: songTitle
        anchors.horizontalCenter: parent.horizontalCenter
        y: 100
        text: MediaPlayerModel.currentSong
        font.pixelSize: 18
        font.bold: true
        font.family: "Sarabun"
        color: Style.lightPeriwinkle

        Behavior on text { enabled: false }
        Behavior on opacity { NumberAnimation { duration: MediaPlayerModel.changeSongDuration } }
    }

    /* === Artist Name === */
    Text {
        id: artistName
        anchors.horizontalCenter: parent.horizontalCenter
        y: 128
        text: MediaPlayerModel.currentArtist
        font.pixelSize: 13
        font.family: "Sarabun"
        color: "#657080"

        Behavior on text { enabled: false }
    }

    /* === Transport Controls === */
    Row {
        id: controls
        anchors.horizontalCenter: parent.horizontalCenter
        y: 165
        spacing: 36

        /* Previous button */
        Canvas {
            width: 28; height: 28
            anchors.verticalCenter: parent.verticalCenter

            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.fillStyle = Style.lightPeriwinkle
                // Left-pointing double triangle
                ctx.beginPath()
                ctx.moveTo(14, 4); ctx.lineTo(2, 14); ctx.lineTo(14, 24)
                ctx.fill()
                ctx.beginPath()
                ctx.moveTo(24, 4); ctx.lineTo(12, 14); ctx.lineTo(24, 24)
                ctx.fill()
            }

            MouseArea {
                anchors.fill: parent
                onClicked: MediaPlayerModel.previousSong()
            }
        }

        /* Play / Pause button */
        Canvas {
            id: playPauseBtn
            width: 40; height: 40
            anchors.verticalCenter: parent.verticalCenter

            property bool isPlaying: MediaPlayerModel.mediaPlayback
            onIsPlayingChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()

                // Circle outline
                ctx.strokeStyle = Style.brightBlue
                ctx.lineWidth = 2
                ctx.beginPath()
                ctx.arc(20, 20, 18, 0, Math.PI * 2)
                ctx.stroke()

                ctx.fillStyle = Style.brightBlue
                if (isPlaying) {
                    // Pause icon (two bars)
                    ctx.fillRect(13, 12, 4, 16)
                    ctx.fillRect(23, 12, 4, 16)
                } else {
                    // Play icon (triangle)
                    ctx.beginPath()
                    ctx.moveTo(15, 10)
                    ctx.lineTo(30, 20)
                    ctx.lineTo(15, 30)
                    ctx.fill()
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: MediaPlayerModel.togglePlayback()
            }
        }

        /* Next button */
        Canvas {
            width: 28; height: 28
            anchors.verticalCenter: parent.verticalCenter

            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.fillStyle = Style.lightPeriwinkle
                // Right-pointing double triangle
                ctx.beginPath()
                ctx.moveTo(4, 4); ctx.lineTo(16, 14); ctx.lineTo(4, 24)
                ctx.fill()
                ctx.beginPath()
                ctx.moveTo(14, 4); ctx.lineTo(26, 14); ctx.lineTo(14, 24)
                ctx.fill()
            }

            MouseArea {
                anchors.fill: parent
                onClicked: MediaPlayerModel.nextSong()
            }
        }
    }

    /* === Progress Bar === */
    Item {
        id: progressContainer
        anchors.horizontalCenter: parent.horizontalCenter
        y: 230
        width: 240
        height: 30

        /* Track background */
        Rectangle {
            id: progressBg
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 4
            radius: 2
            color: "#1a3366"
        }

        /* Filled progress */
        Rectangle {
            id: progressFill
            anchors.verticalCenter: parent.verticalCenter
            width: progressBg.width * MediaPlayerModel.progress
            height: 4
            radius: 2
            color: Style.brightBlue

            Behavior on width {
                NumberAnimation { duration: 800; easing.type: Easing.OutQuad }
            }
        }

        /* Progress knob */
        Rectangle {
            id: knob
            x: progressFill.width - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: 10
            height: 10
            radius: 5
            color: Style.brightBlue
            border.color: Style.lightPeriwinkle
            border.width: 1

            Behavior on x {
                NumberAnimation { duration: 800; easing.type: Easing.OutQuad }
            }
        }

        /* Time labels */
        Text {
            anchors.left: parent.left
            anchors.top: progressBg.bottom
            anchors.topMargin: 6
            text: MediaPlayerModel.timePassedText
            font.pixelSize: 11
            font.family: "Sarabun"
            color: "#657080"
        }

        Text {
            anchors.right: parent.right
            anchors.top: progressBg.bottom
            anchors.topMargin: 6
            text: MediaPlayerModel.timeRemainingText
            font.pixelSize: 11
            font.family: "Sarabun"
            color: "#657080"
        }
    }

    /* === Bluetooth status hint === */
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 280
        spacing: 5
        opacity: 0.4

        Text {
            text: "♪"
            font.pixelSize: 11
            color: Style.brightBlue
        }
        Text {
            text: "Simulation"
            font.pixelSize: 10
            font.family: "Sarabun"
            color: "#657080"
        }
    }
}
